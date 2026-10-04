// The Trellis — revenuecat-webhook
// =============================================================================
// Keeps profiles.membership_status in sync with RevenueCat, which is the
// source of truth for subscription state. Configure this as a Webhook in
// RevenueCat (Project Settings -> Integrations -> Webhooks), URL:
//   https://qonsiliimbkcjmcnhonb.supabase.co/functions/v1/revenuecat-webhook
// and set an "Authorization header value" there — the same string you set
// as this function's REVENUECAT_WEBHOOK_SECRET secret. RevenueCat is the only
// caller of this endpoint, so it's deployed with --no-verify-jwt (see
// deployment notes below) and authenticates purely via that shared secret
// instead (compared in constant time; fails closed when the secret is unset).
//
// Relies on `event.app_user_id` being the Supabase auth user id — true as
// long as the client calls `Purchases.logIn(supabaseUserId)` before any
// purchase, which lib/services/purchases_service.dart's `identify` does
// (called from RunnerProfile.loadCurrent, right after sign-in). Ids that are
// not uuid-shaped (RevenueCat's anonymous `$RCAnonymousID:...`) and ids with
// no profile are acknowledged and skipped — never an error, so RevenueCat does
// not retry them forever.
//
// Responses (always JSON):
//   200 { updated: true, status }        membership_status was written
//   200 { skipped: true, reason }        nothing to do (malformed_event,
//                                        untracked_event, unknown_user)
//   400/401/405/413 { error, code }      bad request — RevenueCat will retry
//   500 { error, code }                  could not write — RevenueCat will retry
//
// No CORS headers on purpose: this is server-to-server only.
// =============================================================================

import { createClient } from 'npm:@supabase/supabase-js@2';
import {
  describeError,
  errorResponse,
  fetchWithDeadline,
  guarded,
  isPlainObject,
  isUuid,
  jsonResponse,
  methodNotAllowed,
  readJsonObject,
  secretsMatch,
} from '../_shared/http.ts';

const NO_CORS = { cors: false } as const;
/// RevenueCat events carry subscriber attributes, so allow more than the
/// 16 KB default — but still bounded.
const MAX_BODY_BYTES = 128 * 1024;
const DB_TIMEOUT_MS = 10_000;

type MembershipStatus = 'trial' | 'active' | 'cancelled';

// Grants or extends access. period_type on these distinguishes a real
// paid period from a trial/introductory one.
const ACTIVE_EVENT_TYPES = new Set([
  'INITIAL_PURCHASE',
  'RENEWAL',
  'UNCANCELLATION',
  'PRODUCT_CHANGE',
]);

// Access has actually lapsed. Deliberately does NOT include CANCELLATION —
// that only means auto-renew was turned off; the subscriber keeps access
// (and stays 'active') until the period actually ends, which is when
// RevenueCat sends EXPIRATION.
const CANCELLED_EVENT_TYPES = new Set(['EXPIRATION']);

/// The (user id -> new status) writes an event asks for; empty when the event
/// is not one this app tracks. Only uuid-shaped ids are ever returned.
function plannedUpdates(event: Record<string, unknown>, type: string): Array<[string, MembershipStatus]> {
  // TRANSFER has no app_user_id: the subscription moved from one set of app
  // users to another (e.g. a restore on a second account). The receivers gain
  // access; the previous holders lose it (no EXPIRATION is ever sent for them).
  if (type === 'TRANSFER') {
    const ids = (value: unknown) => (Array.isArray(value) ? value.filter(isUuid).slice(0, 20) : []);
    const to = ids(event.transferred_to);
    const from = ids(event.transferred_from).filter((id) => !to.includes(id));
    return [
      ...from.map((id): [string, MembershipStatus] => [id, 'cancelled']),
      ...to.map((id): [string, MembershipStatus] => [id, 'active']),
    ];
  }

  const appUserId = event.app_user_id;
  if (!isUuid(appUserId)) return [];

  if (CANCELLED_EVENT_TYPES.has(type)) return [[appUserId, 'cancelled']];
  if (ACTIVE_EVENT_TYPES.has(type)) {
    // 'TRIAL' | 'INTRO' | 'NORMAL' | ... — distinguishes a trial-period purchase
    // event from a real paid one so a fresh trial signup doesn't get marked
    // 'active' a week before it's actually being paid for.
    const periodType = event.period_type;
    return [[appUserId, periodType === 'TRIAL' || periodType === 'INTRO' ? 'trial' : 'active']];
  }
  return [];
}

async function handle(req: Request): Promise<Response> {
  if (req.method !== 'POST') return methodNotAllowed('POST', NO_CORS);

  // 1. Authenticate first. RevenueCat sends the configured "Authorization
  //    header value" verbatim, so accept the secret either on its own or as
  //    "Bearer <secret>". Both comparisons always run (no short-circuit).
  const secret = Deno.env.get('REVENUECAT_WEBHOOK_SECRET');
  if (!secret) {
    console.error('revenuecat-webhook: REVENUECAT_WEBHOOK_SECRET is not set; rejecting every call.');
  }
  const authHeader = req.headers.get('Authorization');
  const [asBearer, asRaw] = await Promise.all([
    secretsMatch(authHeader, secret ? `Bearer ${secret}` : null),
    secretsMatch(authHeader, secret),
  ]);
  if (!secret || !(asBearer || asRaw)) {
    return errorResponse(401, 'unauthorized', 'Unauthorized.', NO_CORS);
  }

  // 2. Validate the payload.
  const parsed = await readJsonObject(req, { maxBytes: MAX_BODY_BYTES, cors: false });
  if (!parsed.ok) return parsed.response;

  const event = parsed.body.event;
  if (!isPlainObject(event)) {
    return errorResponse(400, 'invalid_payload', 'Missing event.', NO_CORS);
  }
  const type = event.type;
  if (typeof type !== 'string' || type.length === 0 || type.length > 64) {
    return jsonResponse(200, { skipped: true, reason: 'malformed_event' }, NO_CORS);
  }

  const tracked = type === 'TRANSFER' || ACTIVE_EVENT_TYPES.has(type) || CANCELLED_EVENT_TYPES.has(type);
  if (!tracked) {
    // e.g. CANCELLATION, BILLING_ISSUE, SUBSCRIBER_ALIAS, NON_RENEWING_PURCHASE,
    // TEST — not a membership_status change this app tracks.
    return jsonResponse(200, { skipped: true, reason: 'untracked_event', type }, NO_CORS);
  }

  const updates = plannedUpdates(event, type);
  if (updates.length === 0) {
    // No uuid-shaped app user id: an anonymous RevenueCat id, or a user this
    // project has never seen. Acknowledge so RevenueCat stops retrying.
    return jsonResponse(200, { skipped: true, reason: 'unknown_user' }, NO_CORS);
  }

  // 3. Apply.
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    console.error('revenuecat-webhook: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing');
    return errorResponse(500, 'not_configured', 'The webhook is not configured.', NO_CORS);
  }
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch: fetchWithDeadline(DB_TIMEOUT_MS) },
  });

  let matched = 0;
  let lastStatus: MembershipStatus = updates[updates.length - 1][1];
  for (const [userId, status] of updates) {
    const { data, error } = await supabase
      .from('profiles')
      .update({ membership_status: status })
      .eq('id', userId)
      .select('id');
    if (error) {
      // A 5xx makes RevenueCat retry the event later.
      console.error(`revenuecat-webhook: membership update failed for a ${type} event:`, describeError(error));
      return errorResponse(500, 'db_update_failed', 'Could not update membership status.', NO_CORS);
    }
    if (Array.isArray(data) && data.length > 0) {
      matched++;
      lastStatus = status;
    }
  }

  if (matched === 0) {
    return jsonResponse(200, { skipped: true, reason: 'unknown_user' }, NO_CORS);
  }
  return jsonResponse(200, { updated: true, status: lastStatus }, NO_CORS);
}

Deno.serve(guarded(
  'revenuecat-webhook',
  handle,
  () => errorResponse(500, 'internal_error', 'The webhook failed unexpectedly.', NO_CORS),
));

// =============================================================================
// Deployment notes (not code — nothing below this line runs)
// =============================================================================
// 1. Deploy with JWT verification OFF — RevenueCat can't send a Supabase
//    JWT, so the platform's normal "every function call needs one" gate
//    has to be disabled for this one function specifically. This
//    function's own shared-secret check above is what actually guards it:
//      supabase functions deploy revenuecat-webhook --no-verify-jwt
//    (Dashboard equivalent: Edge Functions -> revenuecat-webhook -> the
//    function's settings has a "Verify JWT" toggle — turn it off.)
//
// 2. Set its secret:
//      supabase secrets set REVENUECAT_WEBHOOK_SECRET='<a long random string you invent>'
//
// 3. In RevenueCat: Project Settings -> Integrations -> Webhooks -> Add,
//    URL above, "Authorization header value" = either the exact same string as
//    REVENUECAT_WEBHOOK_SECRET, or "Bearer <that string>" — this function
//    accepts both forms. Use RevenueCat's "Send test event" afterwards: it
//    should come back 200 {"skipped":true,"reason":"untracked_event",...}.
// =============================================================================
