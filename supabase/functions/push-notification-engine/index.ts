// The Trellis — push-notification-engine
// =============================================================================
// The single Edge Function behind every push notification this app sends.
// Triggered by database triggers (see supabase/migrations/004_universal_
// webhooks.sql, hardened in 011, extended in 014 and 021), one per relational
// loop, plus one direct call from another Edge Function:
//   - unlock_request    a Runner asks a Witness to unlock a rhythm in their
//                       Rule of Life — a church (DNA) rhythm, or any rhythm
//                       that has become "set" (pending_unlock_requests insert)
//   - grace_nudge       a Runner's Anchor Rhythm just crossed three
//                       consecutive misses (grace_nudges insert)
//   - meeting_proposal  either side proposes a meeting (meetings insert)
//   - support_request   a Runner asks a Witness for prayer or a meeting
//                       (support_requests insert, one row per Witness)
//   - weekly_roll_up    a Witness's weekly summary of one Runner: how many
//                       rhythm-days were kept (weekly_roll_ups insert, written
//                       every Monday by generate_weekly_roll_ups() — 021)
//   - account_deleted   called directly by delete-account/ (not a DB
//                       trigger — nothing is inserted for this one) right
//                       before it deletes the Runner's account, so their
//                       Witness finds out immediately.
//   - witness_nudge     a Runner hasn't started a Rule of Life, has gone
//                       quiet, or may have removed the app (witness_nudges
//                       insert — 026; rows written daily by
//                       generate_witness_nudges() and by the presence probe
//                       below). Copy lives in witness_nudges.ts.
//
// And one scheduled action that is not a notification at all:
//   - presence_probe    POST { "action": "presence_probe" } (pg_cron job
//                       trellis-presence-probe, daily, via
//                       request_presence_probe() — 026). Sends a silent,
//                       data-only push to each Runner who hasn't opened the
//                       app for two days; a token FCM reports as gone marks
//                       the Runner app-removed and nudges their Witnesses.
//                       See witness_nudges.ts for how slow that can be.
//
// A token FCM reports as gone during ANY send (not only the probe) is handled
// the same way, through record_app_removed() (026): the token is cleared, the
// profile is marked app-removed, and a Runner's Witnesses are nudged.
//
// Each trigger POSTs a small, uniform envelope:
//   { event_type: '...', table: '...', record: { ...the new row... } }
// This function validates that envelope, resolves it into one or more
// { profileId, title, body, data } notification jobs, looks up each
// target's fcm_token on profiles, and delivers via Firebase Cloud
// Messaging's HTTP v1 API (the legacy server-key API was shut down by
// Google — v1 needs a full OAuth2 service-account JWT exchange, done here).
//
// Adding another event type later: a new `resolve*` function below, one more
// entry in EVENT_TYPES / RESOLVERS, and its id checks in validateRecord.
//
// Secrets this function needs (Dashboard -> Edge Functions ->
// push-notification-engine -> Secrets):
//   FCM_PROJECT_ID              Firebase project ID
//   FCM_SERVICE_ACCOUNT_JSON    full JSON key of a service account granted
//                               the "Firebase Cloud Messaging API" role
//   PUSH_ENGINE_WEBHOOK_SECRET  shared secret; every caller (the
//                               notify_push_engine() DB trigger, delete-
//                               account/) sends it as `x-trellis-webhook-secret`.
//                               The same value lives in Supabase Vault as
//                               `push_engine_webhook_secret` (see
//                               supabase/migrations/011_security_lockdown.sql).
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically by
// the platform for every Edge Function — nothing to set for those.
//
// Authentication: the app's publishable key ships in every client binary, so
// it can't prove who is calling. This function therefore authenticates purely
// via the shared secret above (constant-time comparison; fails closed if it
// isn't configured) and is deployed with JWT verification off, like
// revenuecat-webhook:
//   supabase functions deploy push-notification-engine --no-verify-jwt
//
// Responses (always JSON; the DB trigger calls through pg_net, which ignores
// the response, so these exist for delete-account and for the logs):
//   200 { sent, failed }                 at least one push went out, or
//   200 { sent: 0, reason }              nothing to do (no_targets,
//                                        no_tokens_or_muted, fcm_not_configured)
//   4xx { error, code }                  unauthorized / invalid_json /
//                                        invalid_payload / unknown_event
//   5xx { error, code }                  db_unavailable / fcm_misconfigured /
//                                        fcm_auth_failed / fcm_delivery_failed
// One failed recipient never stops the others. Nothing here throws: every
// third-party call has a 10 s timeout and every failure is logged without
// device tokens, access tokens or third-party response bodies.
//
// No CORS headers on purpose: this is server-to-server only.
// =============================================================================

import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';
import { importPKCS8, SignJWT } from 'npm:jose@5';
import {
  describeError,
  discardBody,
  errorResponse,
  fetchWithDeadline,
  fetchWithTimeout,
  FetchTimeoutError,
  guarded,
  isPlainObject,
  isUuid,
  jsonResponse,
  methodNotAllowed,
  readJsonBody,
  readJsonObject,
  secretsMatch,
} from '../_shared/http.ts';
import {
  classifyFcmError,
  isWitnessNudgeKind,
  PRESENCE_PROBE_LIMIT,
  presenceProbeMessage,
  QUIET_RUNNER_ALERTS_PREFERENCE,
  runPresenceProbe,
  witnessNudgeCopy,
  type ProbeCandidate,
} from './witness_nudges.ts';

const NO_CORS = { cors: false } as const;

const EVENT_TYPES = [
  'unlock_request',
  'grace_nudge',
  'meeting_proposal',
  'account_deleted',
  'support_request',
  'weekly_roll_up',
  'witness_nudge',
] as const;
type EventType = (typeof EVENT_TYPES)[number];

function isEventType(value: unknown): value is EventType {
  return typeof value === 'string' && (EVENT_TYPES as readonly string[]).includes(value);
}

interface NotificationJob {
  profileId: string;
  title: string;
  body: string;
  data: Record<string, string>;
  /// A key in the recipient's profiles.notification_preferences. If that
  /// preference is explicitly false the notification is skipped. Absent means
  /// "always deliver" (the existing events — an unlock or a deletion notice
  /// isn't something to mute).
  preference?: string;
}

interface FcmServiceAccount {
  client_email: string;
  private_key: string;
}

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
/// Timeout for each call to Google (token exchange, each send).
const FCM_TIMEOUT_MS = 10_000;
/// Deadline for each database round trip.
const DB_TIMEOUT_MS = 8_000;
/// Rows carry free text (a meeting location, a note), so allow more than the
/// 16 KB default — but still bounded.
const MAX_BODY_BYTES = 64 * 1024;
/// A single event never fans out further than this (a Runner's Witnesses).
const MAX_JOBS = 50;

// ---------------------------------------------------------------------------
// Payload validation
// ---------------------------------------------------------------------------

/// Checks that the ids a resolver is about to use are uuid-shaped strings.
/// Returns the name of the first bad field, or null when the record is usable.
function validateRecord(eventType: EventType, record: Record<string, unknown>): string | null {
  const need = (...fields: string[]) => fields.find((field) => !isUuid(record[field])) ?? null;
  switch (eventType) {
    case 'unlock_request':
      return need('id', 'runner_id', 'witness_id', 'rule_item_id');
    case 'grace_nudge':
      return need('runner_id', 'rule_item_id');
    case 'meeting_proposal':
      if (record.proposed_by !== 'runner' && record.proposed_by !== 'witness') return 'proposed_by';
      return need('id', 'runner_id', 'witness_id');
    case 'support_request':
      if (record.rule_item_id !== null && record.rule_item_id !== undefined && !isUuid(record.rule_item_id)) {
        return 'rule_item_id';
      }
      return need('id', 'runner_id', 'witness_id');
    case 'account_deleted':
      return need('runner_id', 'witness_id');
    case 'weekly_roll_up': {
      const badId = need('id', 'runner_id', 'witness_id');
      if (badId) return badId;
      const scheduled = record.rhythms_scheduled;
      const kept = record.rhythms_kept;
      if (!isCount(scheduled) || scheduled < 1) return 'rhythms_scheduled';
      if (!isCount(kept) || kept > scheduled) return 'rhythms_kept';
      return null;
    }
    case 'witness_nudge':
      if (!isWitnessNudgeKind(record.kind)) return 'kind';
      return need('id', 'runner_id', 'witness_id');
  }
}

/// A whole, non-negative, sensibly small number (a week's rhythm-days).
function isCount(value: unknown): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0 && value <= 100_000;
}

/// A single clean line of bounded length for a notification title/body part.
function clean(value: unknown, max: number): string | null {
  if (typeof value !== 'string') return null;
  // deno-lint-ignore no-control-regex
  const text = value.replace(/[\u0000-\u001f\u007f]+/g, ' ').trim();
  if (text.length === 0) return null;
  return text.length > max ? `${text.slice(0, max - 1)}…` : text;
}

// ---------------------------------------------------------------------------
// Per-event resolution — each of these turns a raw row into who gets
// notified and what it says. The tables involved only carry ids, so every
// resolver fetches the human-readable name/title itself. A failed lookup
// degrades to a generic phrase ("A Runner"); it never stops the notification.
// ---------------------------------------------------------------------------

async function profileName(supabase: SupabaseClient, id: string): Promise<string | null> {
  const { data, error } = await supabase.from('profiles').select('name').eq('id', id).maybeSingle();
  if (error) console.error('push-notification-engine: profile name lookup failed:', describeError(error));
  return clean(data?.name, 60);
}

async function ruleItemTitle(supabase: SupabaseClient, id: string): Promise<string | null> {
  const { data, error } = await supabase.from('rule_items').select('title').eq('id', id).maybeSingle();
  if (error) console.error('push-notification-engine: rhythm title lookup failed:', describeError(error));
  return clean(data?.title, 80);
}

async function resolveUnlockRequest(
  supabase: SupabaseClient,
  record: Record<string, unknown>,
): Promise<NotificationJob[]> {
  const runnerId = record.runner_id as string;
  const witnessId = record.witness_id as string;
  const ruleItemId = record.rule_item_id as string;

  // Any rhythm can be the subject now (not only a church one), so the message
  // names neither the rhythm nor its kind — a personal rhythm's title does not
  // belong on a lock screen. The app shows which rhythm once it is opened.
  const runnerName = await profileName(supabase, runnerId);

  return [{
    profileId: witnessId,
    title: 'Unlock Request',
    body: `${runnerName ?? 'A Runner'} is asking you to unlock a rhythm in their Rule of Life.`,
    data: {
      type: 'unlock_request',
      requestId: record.id as string,
      runnerId,
      ruleItemId,
    },
  }];
}

async function resolveGraceNudge(
  supabase: SupabaseClient,
  record: Record<string, unknown>,
): Promise<NotificationJob[]> {
  const runnerId = record.runner_id as string;
  const ruleItemId = record.rule_item_id as string;

  const [runnerName, title, pairings] = await Promise.all([
    profileName(supabase, runnerId),
    ruleItemTitle(supabase, ruleItemId),
    supabase
      .from('witness_pairings')
      .select('witness_id')
      .eq('runner_id', runnerId)
      .eq('status', 'active')
      .limit(MAX_JOBS),
  ]);
  if (pairings.error) {
    // Without the pairings there is nobody to notify — that is a real failure,
    // not "no targets".
    throw new Error(`witness lookup failed: ${describeError(pairings.error)}`);
  }

  const body = clean(record.message, 240) ??
    `${runnerName ?? 'A Runner'} has missed "${title ?? 'an Anchor Rhythm'}" three times in a row.`;

  return ((pairings.data ?? []) as Array<{ witness_id: unknown }>)
    .filter((pairing) => isUuid(pairing.witness_id))
    .map((pairing) => ({
      profileId: pairing.witness_id as string,
      title: 'Grace Nudge',
      body,
      data: { type: 'grace_nudge', runnerId, ruleItemId },
    }));
}

async function resolveMeetingProposal(
  supabase: SupabaseClient,
  record: Record<string, unknown>,
): Promise<NotificationJob[]> {
  const runnerId = record.runner_id as string;
  const witnessId = record.witness_id as string;
  // The proposer notifies the other party — a Runner-proposed meeting
  // alerts their Witness, and vice versa.
  const byRunner = record.proposed_by === 'runner';
  const proposerId = byRunner ? runnerId : witnessId;
  const targetId = byRunner ? witnessId : runnerId;

  const proposerName = await profileName(supabase, proposerId);
  const isEmergency = record.is_emergency === true;

  return [{
    profileId: targetId,
    title: isEmergency ? 'Urgent Meeting Request' : 'Meeting Proposal',
    body: `${proposerName ?? 'Someone'} proposed a meeting${isEmergency ? ' — marked urgent' : ''}.`,
    data: {
      type: 'meeting_proposal',
      meetingId: record.id as string,
      runnerId,
      witnessId,
    },
  }];
}

/// A Runner asked one Witness for prayer or a meeting (support_requests
/// insert — one row, hence one notification, per Witness). Honors the
/// Witness's "Meeting & prayer requests" preference.
async function resolveSupportRequest(
  supabase: SupabaseClient,
  record: Record<string, unknown>,
): Promise<NotificationJob[]> {
  const runnerId = record.runner_id as string;
  const witnessId = record.witness_id as string;
  const kind = record.kind === 'meeting' ? 'meeting' : 'prayer';
  const ruleItemId = isUuid(record.rule_item_id) ? record.rule_item_id : null;

  const [runnerName, rhythm] = await Promise.all([
    profileName(supabase, runnerId),
    ruleItemId ? ruleItemTitle(supabase, ruleItemId) : Promise.resolve(null),
  ]);

  const who = runnerName ?? 'A Runner you walk with';
  const about = rhythm ? ` about "${rhythm}"` : '';

  return [{
    profileId: witnessId,
    title: kind === 'meeting' ? 'Meeting Request' : 'Prayer Request',
    body: kind === 'meeting'
      ? `${who} would like to meet${about}.`
      : `${who} is asking you to pray${about}.`,
    data: {
      type: 'support_request',
      requestId: record.id as string,
      runnerId,
      kind,
    },
    preference: 'meeting_requests',
  }];
}

/// A Witness's weekly roll-up of one Runner (weekly_roll_ups insert — one row,
/// hence one notification, per Runner/Witness pair). Two numbers only: never a
/// rhythm's name. Honors the Witness's "Weekly roll-up" preference.
async function resolveWeeklyRollUp(
  supabase: SupabaseClient,
  record: Record<string, unknown>,
): Promise<NotificationJob[]> {
  const runnerId = record.runner_id as string;
  const witnessId = record.witness_id as string;
  const kept = record.rhythms_kept as number;
  const scheduled = record.rhythms_scheduled as number;

  const runnerName = await profileName(supabase, runnerId);
  const firstName = clean(runnerName?.split(/\s+/)[0], 40) ?? 'A Runner you walk with';

  return [{
    profileId: witnessId,
    title: 'Weekly roll-up',
    body: `${firstName} kept ${kept} of ${scheduled} rhythms last week.`,
    // runnerId is what the app's notification router reads for every event;
    // runner_id carries the same value under the database's column name.
    data: { type: 'weekly_roll_up', runnerId, runner_id: runnerId },
    preference: 'weekly_roll_up',
  }];
}

function resolveAccountDeleted(
  _supabase: SupabaseClient,
  record: Record<string, unknown>,
): Promise<NotificationJob[]> {
  const witnessId = record.witness_id as string;
  const runnerId = record.runner_id as string;
  const runnerName = clean(record.runner_name, 60) ?? 'A Runner you walk with';

  return Promise.resolve([{
    profileId: witnessId,
    title: 'Account Deleted',
    body: `${runnerName} has deleted their Trellis account. You're no longer paired.`,
    data: { type: 'account_deleted', runnerId },
  }]);
}

/// A Runner hasn't started a Rule of Life, has gone quiet, or may have removed
/// the app (witness_nudges insert — one row, hence one notification, per
/// Runner/Witness pair and episode). First name only, never a rhythm's title.
/// Honors the Witness's "Check-In Alerts" preference (quiet_runner_alerts).
async function resolveWitnessNudge(
  supabase: SupabaseClient,
  record: Record<string, unknown>,
): Promise<NotificationJob[]> {
  const runnerId = record.runner_id as string;
  const witnessId = record.witness_id as string;
  // validateRecord has already checked it is one of the three kinds.
  const kind = isWitnessNudgeKind(record.kind) ? record.kind : 'quiet';

  const runnerName = await profileName(supabase, runnerId);
  const { title, body } = witnessNudgeCopy(kind, runnerName, record.detail);

  return [{
    profileId: witnessId,
    title,
    body,
    data: { type: 'witness_nudge', kind, runnerId },
    preference: QUIET_RUNNER_ALERTS_PREFERENCE,
  }];
}

const RESOLVERS: Record<
  EventType,
  (supabase: SupabaseClient, record: Record<string, unknown>) => Promise<NotificationJob[]>
> = {
  unlock_request: resolveUnlockRequest,
  grace_nudge: resolveGraceNudge,
  meeting_proposal: resolveMeetingProposal,
  account_deleted: resolveAccountDeleted,
  support_request: resolveSupportRequest,
  weekly_roll_up: resolveWeeklyRollUp,
  witness_nudge: resolveWitnessNudge,
};

// ---------------------------------------------------------------------------
// FCM HTTP v1 delivery
// ---------------------------------------------------------------------------

/// Why an FCM step failed, in a form that is safe to log.
class FcmError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'FcmError';
  }
}

/// Parses FCM_SERVICE_ACCOUNT_JSON; null if it is not a usable key file.
function parseServiceAccount(raw: string): FcmServiceAccount | null {
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!isPlainObject(parsed)) return null;
    const { client_email: email, private_key: key } = parsed;
    if (typeof email !== 'string' || email.length === 0) return null;
    if (typeof key !== 'string' || !key.includes('PRIVATE KEY')) return null;
    return { client_email: email, private_key: key };
  } catch (_) {
    return null;
  }
}

// The access token is good for an hour; reuse it while this instance stays
// warm instead of doing an OAuth exchange for every push. (Purely an
// optimisation — a cold instance simply exchanges again.)
let cachedToken: { value: string; expiresAt: number; issuer: string } | null = null;

/// Exchanges the service account's private key for a short-lived FCM access
/// token via a self-signed JWT (the OAuth2 "JWT bearer" grant) — there is
/// no long-lived server key any more, only this exchange. Throws FcmError
/// (bad key, Google rejected it, timeout) with a log-safe message.
async function getFcmAccessToken(serviceAccount: FcmServiceAccount): Promise<string> {
  if (
    cachedToken && cachedToken.issuer === serviceAccount.client_email &&
    cachedToken.expiresAt - Date.now() > 60_000
  ) {
    return cachedToken.value;
  }

  const now = Math.floor(Date.now() / 1000);
  let assertion: string;
  try {
    const privateKey = await importPKCS8(serviceAccount.private_key, 'RS256');
    assertion = await new SignJWT({ scope: FCM_SCOPE })
      .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
      .setIssuedAt(now)
      .setIssuer(serviceAccount.client_email)
      .setSubject(serviceAccount.client_email)
      .setAudience('https://oauth2.googleapis.com/token')
      .setExpirationTime(now + 3600)
      .sign(privateKey);
  } catch (_) {
    // Never log the cause: it can quote key material.
    throw new FcmError('service account key could not be used to sign (check FCM_SERVICE_ACCOUNT_JSON)');
  }

  let response: Response;
  try {
    response = await fetchWithTimeout('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion,
      }),
    }, FCM_TIMEOUT_MS, 'FCM token exchange');
  } catch (error) {
    throw new FcmError(
      error instanceof FetchTimeoutError ? 'token exchange timed out' : 'token exchange failed (network error)',
    );
  }

  if (!response.ok) {
    await discardBody(response);
    throw new FcmError(`token exchange rejected (HTTP ${response.status})`);
  }

  let parsed: unknown;
  try {
    parsed = await readJsonBody(response, 'FCM token exchange');
  } catch (error) {
    throw new FcmError(
      error instanceof FetchTimeoutError ? 'token exchange timed out' : 'token exchange returned an unreadable response',
    );
  }
  const accessToken = isPlainObject(parsed) ? parsed.access_token : null;
  if (typeof accessToken !== 'string' || accessToken.length === 0) {
    throw new FcmError('token exchange returned no access token');
  }
  const expiresIn = isPlainObject(parsed) && typeof parsed.expires_in === 'number' && parsed.expires_in > 0
    ? parsed.expires_in
    : 3600;
  cachedToken = {
    value: accessToken,
    expiresAt: Date.now() + Math.min(expiresIn, 3600) * 1000,
    issuer: serviceAccount.client_email,
  };
  return accessToken;
}

interface FcmPostResult {
  ok: boolean;
  /// FCM says this device token is gone for good (see classifyFcmError).
  tokenGone: boolean;
  /// Log-safe reason: "timeout", "network", or "HTTP <status> <FCM status>".
  reason?: string;
}

interface SendResult extends FcmPostResult {
  profileId: string;
}

/// POSTs one FCM v1 `message`. Never throws: a timeout or network failure is
/// reported as a failed result for this one message only.
async function postFcmMessage(
  projectId: string,
  accessToken: string,
  message: Record<string, unknown>,
): Promise<FcmPostResult> {
  try {
    const response = await fetchWithTimeout(
      `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ message }),
      },
      FCM_TIMEOUT_MS,
      'FCM send',
    );

    if (response.ok) {
      await discardBody(response);
      return { ok: true, tokenGone: false };
    }

    // Keep only FCM's short status word (e.g. NOT_FOUND, UNAUTHENTICATED) and
    // whether the token is gone — never the body, which can describe the
    // device token.
    let parsed: unknown = null;
    try {
      parsed = await readJsonBody(response, 'FCM send');
    } catch (_) {
      // Unreadable error body: the HTTP status alone will do.
    }
    const { fcmStatus, tokenGone } = classifyFcmError(response.status, parsed);
    if (response.status === 401) cachedToken = null;
    return { ok: false, tokenGone, reason: `HTTP ${response.status} ${fcmStatus}`.trim() };
  } catch (error) {
    return {
      ok: false,
      tokenGone: false,
      reason: error instanceof FetchTimeoutError ? 'timeout' : 'network',
    };
  }
}

/// Sends one visible push for a notification job. Never throws.
async function sendFcmMessage(
  projectId: string,
  accessToken: string,
  deviceToken: string,
  job: NotificationJob,
): Promise<SendResult> {
  const result = await postFcmMessage(projectId, accessToken, {
    token: deviceToken,
    notification: { title: job.title, body: job.body },
    data: job.data,
  });
  return { profileId: job.profileId, ...result };
}

/// FCM said `token` is gone: clear it from the profile, mark the profile
/// app-removed and, for a Runner, nudge each active Witness (one
/// witness_nudges row each, which comes back through this function as a
/// witness_nudge event). Does nothing if the profile has registered a
/// different token since. Returns how many nudges were written; throws on a
/// database error.
async function recordAppRemoved(supabase: SupabaseClient, profileId: string, token: string): Promise<number> {
  const { data, error } = await supabase.rpc('record_app_removed', {
    p_profile_id: profileId,
    p_token: token,
  });
  if (error) throw new Error(describeError(error));
  return typeof data === 'number' ? data : 0;
}

/// Best-effort version for ordinary sends: a failure is logged, never thrown.
async function recordGoneTokens(
  supabase: SupabaseClient,
  results: SendResult[],
  tokenByProfile: Map<string, string | null>,
): Promise<void> {
  for (const result of results) {
    if (result.ok || !result.tokenGone) continue;
    const token = tokenByProfile.get(result.profileId);
    if (typeof token !== 'string' || token.length === 0) continue;
    try {
      await recordAppRemoved(supabase, result.profileId, token);
    } catch (error) {
      console.error('push-notification-engine: recording a removed app failed:', describeError(error));
    }
  }
}

// ---------------------------------------------------------------------------
// Shared set-up
// ---------------------------------------------------------------------------

/// The service-role client (bypasses RLS — needed to read across whichever
/// Runner's and Witness's own rows a given event touches), or null when the
/// platform did not inject its URL and key.
function createServiceClient(): SupabaseClient | null {
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    console.error('push-notification-engine: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing');
    return null;
  }
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch: fetchWithDeadline(DB_TIMEOUT_MS) },
  });
}

/// FCM's project id and a fresh access token — or the JSON answer to give
/// instead (200 fcm_not_configured when the secrets are simply not set yet;
/// an error when they are set but unusable).
async function prepareFcm(): Promise<{ projectId: string; accessToken: string } | Response> {
  const projectId = Deno.env.get('FCM_PROJECT_ID');
  const serviceAccountJson = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
  if (!projectId || !serviceAccountJson) {
    console.log('push-notification-engine: FCM secrets not configured; skipping push delivery.');
    return jsonResponse(200, { sent: 0, reason: 'fcm_not_configured' }, NO_CORS);
  }

  const serviceAccount = parseServiceAccount(serviceAccountJson);
  if (!serviceAccount) {
    console.error('push-notification-engine: FCM_SERVICE_ACCOUNT_JSON is not a valid service-account key file.');
    return errorResponse(500, 'fcm_misconfigured', 'Push delivery is misconfigured.', NO_CORS);
  }

  try {
    return { projectId, accessToken: await getFcmAccessToken(serviceAccount) };
  } catch (error) {
    console.error('push-notification-engine: FCM auth failed:', describeError(error));
    return errorResponse(502, 'fcm_auth_failed', 'Could not authenticate with the push service.', NO_CORS);
  }
}

// ---------------------------------------------------------------------------
// The presence probe (daily; see witness_nudges.ts)
// ---------------------------------------------------------------------------

/// Probes every Runner the app hasn't heard from in two days (at most
/// PRESENCE_PROBE_LIMIT a run — presence_probe_candidates() in 026 picks them:
/// an active pairing, a device token, not already marked app-removed, and
/// last_seen_at — or, never seen, the account's creation — over two days
/// ago). Answers 200 { probed, delivered, tokensGone, failed, marked, nudges,
/// markFailed, distrusted } or a JSON error.
async function handlePresenceProbe(): Promise<Response> {
  const supabase = createServiceClient();
  if (!supabase) {
    return errorResponse(500, 'not_configured', 'Push delivery is not configured.', NO_CORS);
  }

  let candidates: ProbeCandidate[];
  try {
    const { data, error } = await supabase.rpc('presence_probe_candidates', { p_limit: PRESENCE_PROBE_LIMIT });
    if (error) throw new Error(describeError(error));
    candidates = ((data ?? []) as Array<{ profile_id: unknown; fcm_token: unknown }>)
      .filter((row) => isUuid(row.profile_id) && typeof row.fcm_token === 'string' && row.fcm_token.length > 0)
      .slice(0, PRESENCE_PROBE_LIMIT)
      .map((row) => ({ profileId: row.profile_id as string, token: row.fcm_token as string }));
  } catch (error) {
    console.error('push-notification-engine: presence probe candidate lookup failed:', describeError(error));
    return errorResponse(502, 'db_unavailable', 'Could not look up who to probe.', NO_CORS);
  }
  if (candidates.length === 0) {
    return jsonResponse(200, { probed: 0, reason: 'no_candidates' }, NO_CORS);
  }

  const fcm = await prepareFcm();
  if (fcm instanceof Response) return fcm;

  const summary = await runPresenceProbe(candidates, {
    send: (candidate) => postFcmMessage(fcm.projectId, fcm.accessToken, presenceProbeMessage(candidate.token)),
    markRemoved: (candidate) => recordAppRemoved(supabase, candidate.profileId, candidate.token),
  });

  if (summary.distrusted) {
    console.error(
      `push-notification-engine: presence probe — ${summary.tokensGone} of ${summary.probed} tokens reported ` +
        'gone; that many at once points at a configuration problem, not uninstalls. Nobody was marked.',
    );
  }
  if (summary.markFailed > 0) {
    console.error(`push-notification-engine: presence probe — ${summary.markFailed} app-removed record(s) failed.`);
  }
  console.log('push-notification-engine: presence probe:', JSON.stringify(summary));
  return jsonResponse(200, summary, NO_CORS);
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

async function handle(req: Request): Promise<Response> {
  if (req.method !== 'POST') return methodNotAllowed('POST', NO_CORS);

  // 1. Authenticate first — before reading the body or touching anything.
  const expectedSecret = Deno.env.get('PUSH_ENGINE_WEBHOOK_SECRET');
  if (!expectedSecret) {
    console.error('push-notification-engine: PUSH_ENGINE_WEBHOOK_SECRET is not set; rejecting every call.');
  }
  const providedSecret = req.headers.get('x-trellis-webhook-secret');
  if (!(await secretsMatch(providedSecret, expectedSecret))) {
    return errorResponse(401, 'unauthorized', 'Unauthorized.', NO_CORS);
  }

  // 2. Validate the envelope.
  const parsed = await readJsonObject(req, { maxBytes: MAX_BODY_BYTES, cors: false });
  if (!parsed.ok) return parsed.response;
  const payload = parsed.body;

  // The daily presence probe is an action, not an event (no record).
  if (payload.action === 'presence_probe') return await handlePresenceProbe();

  const eventType = payload.event_type;
  if (!isEventType(eventType)) {
    return errorResponse(400, 'unknown_event', 'Unknown event_type.', NO_CORS);
  }
  const record = payload.record;
  if (!isPlainObject(record)) {
    return errorResponse(400, 'invalid_payload', 'record must be an object.', NO_CORS);
  }
  const badField = validateRecord(eventType, record);
  if (badField) {
    return errorResponse(400, 'invalid_payload', `record.${badField} is missing or malformed.`, NO_CORS);
  }

  const supabase = createServiceClient();
  if (!supabase) {
    return errorResponse(500, 'not_configured', 'Push delivery is not configured.', NO_CORS);
  }

  // 3. Resolve who gets told what.
  let jobs: NotificationJob[];
  try {
    jobs = (await RESOLVERS[eventType](supabase, record)).slice(0, MAX_JOBS);
  } catch (error) {
    console.error(`push-notification-engine: resolving ${eventType} failed:`, describeError(error));
    return errorResponse(502, 'db_unavailable', 'Could not look up who to notify.', NO_CORS);
  }
  if (jobs.length === 0) {
    return jsonResponse(200, { sent: 0, reason: 'no_targets' }, NO_CORS);
  }

  const targetIds = [...new Set(jobs.map((job) => job.profileId))];
  let profiles: Array<{
    id: string;
    fcm_token: string | null;
    notification_preferences: Record<string, unknown> | null;
  }>;
  try {
    const { data, error } = await supabase
      .from('profiles')
      .select('id, fcm_token, notification_preferences')
      .in('id', targetIds);
    if (error) throw new Error(describeError(error));
    profiles = (data ?? []) as typeof profiles;
  } catch (error) {
    console.error('push-notification-engine: device token lookup failed:', describeError(error));
    return errorResponse(502, 'db_unavailable', 'Could not look up who to notify.', NO_CORS);
  }

  const tokenByProfile = new Map(profiles.map((row) => [row.id, row.fcm_token]));
  const preferencesByProfile = new Map(profiles.map((row) => [row.id, row.notification_preferences]));

  // A preference that is explicitly false mutes that kind of notification;
  // missing or true delivers (the app's default is everything on).
  const isMuted = (job: NotificationJob) => {
    if (job.preference === undefined) return false;
    const preferences = preferencesByProfile.get(job.profileId);
    return isPlainObject(preferences) && preferences[job.preference] === false;
  };
  const hasToken = (job: NotificationJob) => {
    const token = tokenByProfile.get(job.profileId);
    return typeof token === 'string' && token.length > 0;
  };

  const deliverable = jobs.filter((job) => hasToken(job) && !isMuted(job));
  if (deliverable.length === 0) {
    // Not a failure — the target(s) just haven't registered a device yet.
    // Every one of these loops also has an in-app Realtime/list surface
    // (see RunnerProfile), so nothing is silently lost.
    console.log(`push-notification-engine: nothing to deliver for ${eventType} (no device token, or muted).`);
    return jsonResponse(200, { sent: 0, reason: 'no_tokens_or_muted' }, NO_CORS);
  }

  // 4. Deliver. A bad key or an FCM outage is a clean JSON answer, never a throw.
  const fcm = await prepareFcm();
  if (fcm instanceof Response) return fcm;
  const { projectId: fcmProjectId, accessToken } = fcm;

  // sendFcmMessage never rejects, so one bad recipient cannot stop the rest.
  const results = await Promise.all(
    deliverable.map((job) =>
      sendFcmMessage(fcmProjectId, accessToken, tokenByProfile.get(job.profileId) as string, job)
    ),
  );

  const failures = results.filter((result) => !result.ok);
  if (failures.length > 0) {
    console.error(
      `push-notification-engine: ${failures.length} of ${results.length} deliveries failed for ${eventType}:`,
      JSON.stringify(failures.map(({ profileId, reason }) => ({ profileId, reason }))),
    );
  }
  // A token FCM calls gone (app removed) is cleared, and a Runner's Witnesses
  // are told — the same path the presence probe uses.
  await recordGoneTokens(supabase, results, tokenByProfile);
  const sent = results.length - failures.length;
  if (sent === 0) {
    return jsonResponse(
      502,
      { error: 'No push notification could be delivered.', code: 'fcm_delivery_failed', sent: 0, failed: failures.length },
      NO_CORS,
    );
  }
  return jsonResponse(200, { sent, failed: failures.length }, NO_CORS);
}

Deno.serve(guarded(
  'push-notification-engine',
  handle,
  () => errorResponse(500, 'internal_error', 'Push delivery failed unexpectedly.', NO_CORS),
));
