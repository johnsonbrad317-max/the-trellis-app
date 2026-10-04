// The Trellis — calendar-availability
// =============================================================================
// "When are we BOTH free?" — the only place two people's calendars meet.
//
//   supabase.functions.invoke('calendar-availability', body: {
//     other_user_id, from, to, duration_minutes,
//     tz_offset_minutes?, tzid?, day_start_hour?, day_end_hour?, max_suggestions?
//   })
//   -> 200 { suggestions: [{start, end}], both_connected, me_connected, other_connected }
//   -> non-2xx { error, code }
//        400 invalid_json | invalid_request      401 unauthorized
//        403 not_paired                          405 method_not_allowed
//        429 rate_limited (+ retry_after_seconds, Retry-After header)
//        413 payload_too_large                   500 pairing_check_failed | internal_error
//        503 not_configured | calendar_provider_timeout | calendar_unavailable |
//            auth_unavailable
//
// Privacy contract (the whole point of this function):
//   * Authorisation: the caller must be in an ACTIVE witness_pairings row with
//     other_user_id (either direction), re-checked here on every call with the
//     service role — never taken on the client's word. Anyone else gets 403
//     and nothing is read.
//   * Each person's free/busy is fetched with THEIR OWN token, merged and
//     intersected here, and ONLY the shared free windows leave this function.
//     Neither person's busy blocks, nor which calendar provider either of them
//     uses, is ever returned or logged — on success or on any error path. Logs
//     carry only error classes and HTTP status codes, and never say whose
//     calendar a failure belonged to.
//   * If either side has no active connection, suggestions are empty and the
//     flags say who is missing. That is not an error.
//   * All or nothing: if anyone's calendar cannot be read completely (Cronofy
//     down, slow, rate-limited, more data than we read), the answer is a 503 —
//     never suggestions computed from a partial picture.
//
// Bounded work: at most 3 connections per person, at most 10 free/busy pages
// per connection, 10 s per Cronofy request and 20 s for all Cronofy work in
// one call; the search window is capped at 21 days.
//
// Rate limited per caller, in Postgres so every instance shares one count
// (migration 020, edge_rate_limit_hit): at most 6 requests a minute and 40 an
// hour. Over the limit -> 429 { error, code: "rate_limited", retry_after_seconds }
// with a Retry-After header. Requests are counted after the caller is
// authenticated and the body is valid, but BEFORE the pairing check, so probing
// for who is paired with whom is limited too. If the limiter itself is down it
// fails open (see _shared/rate_limit.ts) — apply migration 020 before relying on it.
//
// Deploy (JWT verification ON — the default):
//   supabase functions deploy calendar-availability
//
// Secrets: CRONOFY_CLIENT_ID, CRONOFY_CLIENT_SECRET, CRONOFY_DATA_CENTER.
// =============================================================================

import type { SupabaseClient } from 'npm:@supabase/supabase-js@2';
import { authenticate } from '../_shared/auth.ts';
import { isValidTzid, sharedFreeWindows, utcOffsetMinutesAt } from '../_shared/availability.ts';
import {
  type BusySpan,
  CronofyAuthError,
  CronofyConfigError,
  CronofyTimeoutError,
  fetchFreeBusy,
  isCalendarProvider,
  missingSecrets,
  refreshTokens,
} from '../_shared/cronofy.ts';
import { checkRateLimits, type RateLimit, rateLimitedResponse } from '../_shared/rate_limit.ts';
import {
  describeError,
  errorResponse,
  guarded,
  handlePreflight,
  isUuid,
  jsonResponse,
  methodNotAllowed,
  parseIsoInstant,
  readJsonObject,
} from '../_shared/http.ts';

const DAY_MS = 86_400_000;
const MAX_WINDOW_DAYS = 21;
/// How far ahead a search may start (Cronofy only answers ~200 days out).
const MAX_START_AHEAD_DAYS = 180;
/// One row per provider per user; this only bounds the work if that changes.
const MAX_CONNECTIONS_PER_USER = 3;
/// Everything we ask Cronofy in one call must be done within this.
const CRONOFY_BUDGET_MS = 20_000;
/// Each call reads two people's calendars from a third party, so it is budgeted
/// per caller: a short burst allowance and a sustained one. A person choosing a
/// meeting time makes a handful of calls; this only stops a loop or a script.
const RATE_LIMITS: RateLimit[] = [
  { name: 'minute', limit: 6, windowSeconds: 60 },
  { name: 'hour', limit: 40, windowSeconds: 3600 },
];

interface ConnectionRow {
  provider: string;
  status: string;
  access_token: string | null;
  refresh_token: string | null;
  token_expires_at: string | null;
}

/// A transient problem (network, 5xx, timeout, database) reading someone's
/// calendar. We refuse to answer rather than suggest times from an incomplete
/// picture. `timedOut` picks the response code; the message never says whose
/// calendar it was.
class UnavailableError extends Error {
  timedOut: boolean;
  constructor(message: string, timedOut = false) {
    super(message);
    this.name = 'UnavailableError';
    this.timedOut = timedOut;
  }
}

function asUnavailable(error: unknown): UnavailableError {
  if (error instanceof UnavailableError) return error;
  if (error instanceof CronofyTimeoutError) return new UnavailableError('Calendar provider timed out', true);
  return new UnavailableError('Calendar provider unavailable');
}

// ---------------------------------------------------------------------------
// Input validation
// ---------------------------------------------------------------------------

/// An optional numeric field: absent/null -> fallback; a finite number ->
/// truncated and clamped to [min, max]; anything else -> null (reject).
function optionalInt(value: unknown, min: number, max: number, fallback: number): number | null {
  if (value === undefined || value === null) return fallback;
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  return Math.min(max, Math.max(min, Math.trunc(value)));
}

interface Query {
  otherUserId: string;
  fromMs: number;
  toMs: number;
  durationMinutes: number;
  maxSuggestions: number;
  dayStartHour: number;
  dayEndHour: number;
  tzid: string | undefined;
  tzOffsetMinutes: number | undefined;
}

/// Returns the cleaned query, or a sentence saying what is wrong with it.
function parseQuery(body: Record<string, unknown>, userId: string, now: number): Query | string {
  const otherUserId = body.other_user_id;
  if (!isUuid(otherUserId)) return 'other_user_id must be a user id.';
  if (otherUserId.toLowerCase() === userId.toLowerCase()) return 'other_user_id must be someone else.';

  const requestedFrom = parseIsoInstant(body.from);
  const requestedTo = parseIsoInstant(body.to);
  if (requestedFrom === null || requestedTo === null) return 'from and to must be ISO 8601 times.';
  if (requestedFrom > now + MAX_START_AHEAD_DAYS * DAY_MS) return 'from is too far in the future.';
  // Never suggest the past; cap the window at 21 days.
  const fromMs = Math.max(requestedFrom, now);
  const toMs = Math.min(requestedTo, fromMs + MAX_WINDOW_DAYS * DAY_MS);
  if (toMs <= fromMs) return 'to must be after from (and in the future).';

  const durationMinutes = optionalInt(body.duration_minutes, 15, 240, 60);
  if (durationMinutes === null) return 'duration_minutes must be a number.';
  const maxSuggestions = optionalInt(body.max_suggestions, 1, 20, 8);
  if (maxSuggestions === null) return 'max_suggestions must be a number.';
  const dayStartHour = optionalInt(body.day_start_hour, 0, 23, 8);
  const dayEndHour = optionalInt(body.day_end_hour, 1, 24, 20);
  if (dayStartHour === null || dayEndHour === null) return 'day_start_hour and day_end_hour must be numbers.';
  if (dayEndHour <= dayStartHour) return 'day_end_hour must be after day_start_hour.';

  // The app sends the UTC offset in minutes (Dart's timeZoneName isn't an IANA
  // id); a tzid is also accepted. The offset wins if both are present.
  let tzOffsetMinutes: number | undefined;
  const offsetRaw = body.tz_offset_minutes;
  if (offsetRaw !== undefined && offsetRaw !== null) {
    if (typeof offsetRaw !== 'number' || !Number.isFinite(offsetRaw) || Math.abs(offsetRaw) > 14 * 60) {
      return 'tz_offset_minutes must be a UTC offset in minutes.';
    }
    tzOffsetMinutes = Math.trunc(offsetRaw);
  }
  let tzid: string | undefined;
  if (body.tzid !== undefined && body.tzid !== null) {
    if (typeof body.tzid !== 'string' || body.tzid.length === 0 || body.tzid.length > 64 || !isValidTzid(body.tzid)) {
      return 'tzid must be an IANA time zone.';
    }
    tzid = body.tzid;
  }

  return {
    otherUserId,
    fromMs,
    toMs,
    durationMinutes,
    maxSuggestions,
    dayStartHour,
    dayEndHour,
    tzid,
    tzOffsetMinutes,
  };
}

// ---------------------------------------------------------------------------
// Tokens
// ---------------------------------------------------------------------------

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

async function loadConnections(admin: SupabaseClient, userId: string): Promise<ConnectionRow[]> {
  const { data, error } = await admin.rpc('calendar_read_tokens', { p_user_id: userId });
  if (error) throw new UnavailableError('Could not read calendar connections');
  return ((Array.isArray(data) ? data : []) as ConnectionRow[])
    .filter((row) => row !== null && typeof row === 'object' && isCalendarProvider(row.provider));
}

async function readConnection(
  admin: SupabaseClient,
  userId: string,
  provider: string,
): Promise<ConnectionRow | null> {
  const { data, error } = await admin.rpc('calendar_read_tokens', {
    p_user_id: userId,
    p_provider: provider,
  });
  if (error) throw new UnavailableError('Could not read calendar connections');
  return (Array.isArray(data) ? data[0] ?? null : null) as ConnectionRow | null;
}

/// Never throws: a failed status write must not change the answer.
async function setStatus(
  admin: SupabaseClient,
  userId: string,
  provider: string,
  status: 'active' | 'needs_reauth',
): Promise<void> {
  try {
    const { error } = await admin.rpc('calendar_set_status', {
      p_user_id: userId,
      p_provider: provider,
      p_status: status,
    });
    if (error) console.error('calendar-availability: status update failed:', describeError(error));
  } catch (e) {
    console.error('calendar-availability: status update failed:', e instanceof Error ? e.name : 'unknown');
  }
}

/// A usable access token for the connection, refreshing (and persisting the
/// rotated tokens) if it is about to expire. Returns null if the user must
/// re-authorise — in which case the connection has been marked needs_reauth.
async function usableAccessToken(
  admin: SupabaseClient,
  userId: string,
  conn: ConnectionRow,
  deadlineMs: number,
): Promise<string | null> {
  const expiresAt = conn.token_expires_at ? Date.parse(conn.token_expires_at) : 0;
  if (conn.access_token && Number.isFinite(expiresAt) && expiresAt - Date.now() > 60_000) {
    return conn.access_token;
  }
  return await refreshAndStore(admin, userId, conn, deadlineMs);
}

async function refreshAndStore(
  admin: SupabaseClient,
  userId: string,
  conn: ConnectionRow,
  deadlineMs: number,
): Promise<string | null> {
  if (!conn.refresh_token) {
    await setStatus(admin, userId, conn.provider, 'needs_reauth');
    return null;
  }

  try {
    const tokens = await refreshTokens(conn.refresh_token, { deadlineMs });
    const { error } = await admin.rpc('calendar_update_tokens', {
      p_user_id: userId,
      p_provider: conn.provider,
      p_access_token: tokens.accessToken,
      p_refresh_token: tokens.refreshToken,
      p_expires_at: tokens.expiresAt,
    });
    // Cronofy rotates refresh tokens; if we can't persist the new one the
    // connection is effectively lost, so surface it rather than hide it.
    if (error) throw new UnavailableError('Could not store refreshed tokens');
    return tokens.accessToken;
  } catch (e) {
    if (!(e instanceof CronofyAuthError)) throw e instanceof CronofyConfigError ? e : asUnavailable(e);

    // Cronofy refused the refresh token. Another request may have refreshed
    // (and rotated) this connection a moment ago, invalidating the token we
    // hold — so look again, twice, before concluding the grant is dead.
    for (let attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await sleep(750);
      const fresh = await readConnection(admin, userId, conn.provider);
      if (!fresh) return null; // disconnected meanwhile
      const freshExpiry = fresh.token_expires_at ? Date.parse(fresh.token_expires_at) : 0;
      if (fresh.access_token && Number.isFinite(freshExpiry) && freshExpiry - Date.now() > 30_000) {
        return fresh.access_token;
      }
      if (fresh.refresh_token && fresh.refresh_token !== conn.refresh_token) {
        // Someone else rotated it but we cannot use the result yet: transient.
        throw new UnavailableError('Calendar tokens are being refreshed');
      }
    }

    await setStatus(admin, userId, conn.provider, 'needs_reauth');
    return null;
  }
}

/// The union of busy blocks across all of one user's ACTIVE calendars, plus
/// whether at least one of them is still usable. Throws UnavailableError (or
/// CronofyConfigError) if any active calendar could not be read completely.
async function busyForUser(
  admin: SupabaseClient,
  userId: string,
  fromMs: number,
  toMs: number,
  tzOffsetMinutes: number,
  deadlineMs: number,
): Promise<{ connected: boolean; busy: BusySpan[] }> {
  const connections = (await loadConnections(admin, userId))
    .filter((c) => c.status === 'active')
    .slice(0, MAX_CONNECTIONS_PER_USER);

  const results = await Promise.all(connections.map(async (conn) => {
    let token = await usableAccessToken(admin, userId, conn, deadlineMs);
    if (!token) return null;

    for (let attempt = 0; attempt < 2; attempt++) {
      let spans: BusySpan[];
      try {
        spans = await fetchFreeBusy(token, fromMs, toMs, tzOffsetMinutes, { deadlineMs });
      } catch (e) {
        if (e instanceof CronofyConfigError) throw e;
        if (!(e instanceof CronofyAuthError)) throw asUnavailable(e);
        // 401: the access token was revoked or expired early. Refresh once.
        if (attempt === 1) {
          await setStatus(admin, userId, conn.provider, 'needs_reauth');
          return null;
        }
        const refreshed = await refreshAndStore(admin, userId, conn, deadlineMs);
        if (!refreshed) return null;
        token = refreshed;
        continue;
      }
      // Stamps last_checked_at; best effort.
      await setStatus(admin, userId, conn.provider, 'active');
      return spans;
    }
    return null;
  }));

  const usable = results.filter((r): r is BusySpan[] => r !== null);
  return { connected: usable.length > 0, busy: usable.flat() };
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

async function handle(req: Request): Promise<Response> {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== 'POST') return methodNotAllowed('POST, OPTIONS');

  const caller = await authenticate(req);
  if (caller instanceof Response) return caller;
  const { userId, admin } = caller;

  // ---- Parse and validate inputs ---------------------------------------------
  const read = await readJsonObject(req);
  if (!read.ok) return read.response;
  const query = parseQuery(read.body, userId, Date.now());
  if (typeof query === 'string') return errorResponse(400, 'invalid_request', query);
  const { otherUserId, fromMs, toMs } = query;

  // ---- Budget: one lookup costs two provider reads ---------------------------
  const budget = await checkRateLimits(admin, 'calendar-availability', userId, RATE_LIMITS);
  if (!budget.allowed) {
    return rateLimitedResponse(
      budget.retryAfterSeconds,
      'You have checked calendars a lot in a short time. Please try again in a little while.',
    );
  }

  // ---- Authorise: active pairing, either direction ---------------------------
  // Both ids are validated UUIDs, so interpolating them into the filter is safe.
  const { data: pairing, error: pairingError } = await admin
    .from('witness_pairings')
    .select('id')
    .eq('status', 'active')
    .or(
      `and(runner_id.eq.${userId},witness_id.eq.${otherUserId}),` +
        `and(runner_id.eq.${otherUserId},witness_id.eq.${userId})`,
    )
    .limit(1);
  if (pairingError) {
    console.error('calendar-availability: pairing lookup failed:', describeError(pairingError));
    return errorResponse(500, 'pairing_check_failed', 'Could not check your pairing. Please try again.');
  }
  if (!Array.isArray(pairing) || pairing.length === 0) {
    return errorResponse(403, 'not_paired', 'You are not paired with that person.');
  }

  // ---- Configuration -----------------------------------------------------------
  const missing = missingSecrets('CRONOFY_CLIENT_ID', 'CRONOFY_CLIENT_SECRET');
  if (missing.length > 0) {
    console.error('calendar-availability: not configured; missing secrets:', missing.join(', '));
    return errorResponse(503, 'not_configured', 'Calendar availability is not available yet.');
  }

  // All-day events come back from Cronofy as bare dates; they are read as local
  // midnight in the caller's offset (taken from the tzid at the start of the
  // window if only a tzid was sent; UTC if neither was).
  const allDayOffset = query.tzOffsetMinutes ??
    (query.tzid ? utcOffsetMinutesAt(fromMs, query.tzid) : 0);

  // ---- Who is connected, and when are both free? -----------------------------
  try {
    const deadlineMs = Date.now() + CRONOFY_BUDGET_MS;
    const [mine, theirs] = await Promise.all([
      busyForUser(admin, userId, fromMs, toMs, allDayOffset, deadlineMs),
      busyForUser(admin, otherUserId, fromMs, toMs, allDayOffset, deadlineMs),
    ]);

    const meConnected = mine.connected;
    const otherConnected = theirs.connected;

    if (!(meConnected && otherConnected)) {
      return jsonResponse(200, {
        suggestions: [],
        both_connected: false,
        me_connected: meConnected,
        other_connected: otherConnected,
      });
    }

    const suggestions = sharedFreeWindows({
      busyA: mine.busy,
      busyB: theirs.busy,
      from: fromMs,
      to: toMs,
      durationMinutes: query.durationMinutes,
      dayStartHour: query.dayStartHour,
      dayEndHour: query.dayEndHour,
      tzid: query.tzid,
      tzOffsetMinutes: query.tzOffsetMinutes,
      maxSuggestions: query.maxSuggestions,
      maxPerDay: 3,
    });

    return jsonResponse(200, {
      suggestions,
      both_connected: true,
      me_connected: true,
      other_connected: true,
    });
  } catch (e) {
    // Deliberately generic: never anything about either calendar, never whose
    // it was. Only our own error classes' fixed messages are logged.
    if (e instanceof CronofyConfigError) {
      console.error('calendar-availability: not configured:', e.message);
      return errorResponse(503, 'not_configured', 'Calendar availability is not available yet.');
    }
    if (e instanceof UnavailableError) {
      console.error('calendar-availability: unavailable:', e.message);
      return e.timedOut
        ? errorResponse(503, 'calendar_provider_timeout', 'The calendar service took too long. Please try again.')
        : errorResponse(503, 'calendar_unavailable', 'Calendar availability is temporarily unavailable.');
    }
    console.error('calendar-availability: failed:', e instanceof Error ? e.name : 'unknown');
    return errorResponse(503, 'calendar_unavailable', 'Calendar availability is temporarily unavailable.');
  }
}

Deno.serve(guarded('calendar-availability', handle));
