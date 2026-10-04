// Cronofy integration — EVERYTHING that depends on Cronofy's API shape lives in
// this one small module, so if any assumption below turns out to be wrong
// it's a one-line fix here and nowhere else. (See supabase/CALENDAR_SETUP.md,
// "Assumptions to verify", for the list.)
//
// What we use Cronofy for, and nothing more:
//   * the OAuth connect flow, requesting ONLY the `read_free_busy` scope —
//     The Trellis never asks for event contents;
//   * GET /v1/free_busy per user, to learn busy intervals;
//   * token refresh and revoke.
//
// Every request is bounded: a per-request timeout (10 s by default) and, for
// callers that pass one, an overall deadline shared by a whole operation. A
// slow or silent Cronofy becomes a CronofyTimeoutError — never a hung function.
//
// Secrets (Dashboard -> Edge Functions -> Secrets):
//   CRONOFY_CLIENT_ID, CRONOFY_CLIENT_SECRET   from the Cronofy developer app
//   CRONOFY_DATA_CENTER                        us (default) | de | uk | au | ca | sg
//   CALENDAR_OAUTH_REDIRECT_URI                https://<project-ref>.supabase.co/functions/v1/calendar-oauth-callback

import { fetchWithTimeout, FetchTimeoutError, isTimeoutError } from './http.ts';

export type CalendarProvider = 'google' | 'outlook' | 'apple';

export function isCalendarProvider(value: unknown): value is CalendarProvider {
  return value === 'google' || value === 'outlook' || value === 'apple';
}

/// Our provider -> Cronofy `provider_name`. (ASSUMPTION: for 'outlook'
/// 'office365' sends the user straight to Microsoft sign-in. Personal
/// outlook.com/hotmail accounts may need 'live_connect' instead — change it
/// here. Omit the entry to let Cronofy show its own provider chooser.)
const PROVIDER_NAME: Record<CalendarProvider, string> = {
  google: 'google',
  outlook: 'office365',
  apple: 'apple',
};

const SCOPE = 'read_free_busy';

/// Per-request timeout for every Cronofy call.
export const CRONOFY_TIMEOUT_MS = 10_000;

// ---------------------------------------------------------------------------
// Regional data centers
// ---------------------------------------------------------------------------

const REGIONS: Record<string, { api: string; app: string }> = {
  us: { api: 'https://api.cronofy.com', app: 'https://app.cronofy.com' },
  de: { api: 'https://api-de.cronofy.com', app: 'https://app-de.cronofy.com' },
  uk: { api: 'https://api-uk.cronofy.com', app: 'https://app-uk.cronofy.com' },
  au: { api: 'https://api-au.cronofy.com', app: 'https://app-au.cronofy.com' },
  ca: { api: 'https://api-ca.cronofy.com', app: 'https://app-ca.cronofy.com' },
  sg: { api: 'https://api-sg.cronofy.com', app: 'https://app-sg.cronofy.com' },
};

export function cronofyBaseUrls(): { api: string; app: string } {
  const key = (Deno.env.get('CRONOFY_DATA_CENTER') ?? 'us').trim().toLowerCase() || 'us';
  return Object.hasOwn(REGIONS, key) ? REGIONS[key] : REGIONS.us;
}

/// A required secret is not set. The message names the secret, never a value.
export class CronofyConfigError extends Error {
  constructor(name: string) {
    super(`${name} is not set`);
    this.name = 'CronofyConfigError';
  }
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new CronofyConfigError(name);
  return value;
}

/// The names (never values) of any of the given secrets that are not set, so a
/// handler can answer `not_configured` up front instead of failing midway.
export function missingSecrets(...names: string[]): string[] {
  return names.filter((name) => !Deno.env.get(name));
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Cronofy rejected our credentials/token (HTTP 400/401/403): the user must
/// re-authorise. Distinct from a transient failure (network, 5xx, 429), which
/// is a plain CronofyError and must NOT mark a connection as needing reauth.
export class CronofyAuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'CronofyAuthError';
  }
}

/// A transient or unexpected Cronofy failure (network, 5xx, 429, bad JSON,
/// more data than we are willing to read).
export class CronofyError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'CronofyError';
  }
}

/// Cronofy did not answer in time (per-request timeout or overall deadline).
export class CronofyTimeoutError extends CronofyError {
  constructor(what: string) {
    super(`Cronofy ${what} timed out`);
    this.name = 'CronofyTimeoutError';
  }
}

// Never put response bodies in error messages: they can echo tokens/codes.
function failure(what: string, status: number, authStatuses: number[] = [400, 401, 403]): Error {
  const message = `Cronofy ${what} failed (HTTP ${status})`;
  return authStatuses.includes(status)
    ? new CronofyAuthError(message)
    : new CronofyError(message);
}

export interface CronofyCallOptions {
  /// Per-request timeout. Default CRONOFY_TIMEOUT_MS.
  timeoutMs?: number;
  /// Absolute time (epoch ms) by which the whole operation must be finished.
  /// Each request gets min(timeoutMs, time left); with no time left the call
  /// fails with CronofyTimeoutError without touching the network.
  deadlineMs?: number;
}

function budget(options: CronofyCallOptions | undefined, what: string): number {
  const perRequest = options?.timeoutMs ?? CRONOFY_TIMEOUT_MS;
  if (options?.deadlineMs === undefined) return perRequest;
  const left = options.deadlineMs - Date.now();
  if (left <= 0) throw new CronofyTimeoutError(what);
  return Math.min(perRequest, left);
}

async function cronofyFetch(
  url: string,
  init: RequestInit,
  what: string,
  options?: CronofyCallOptions,
): Promise<Response> {
  const timeoutMs = budget(options, what);
  try {
    return await fetchWithTimeout(url, init, timeoutMs, `Cronofy ${what}`);
  } catch (error) {
    if (error instanceof FetchTimeoutError) throw new CronofyTimeoutError(what);
    throw new CronofyError(`Cronofy ${what} failed (network error)`);
  }
}

async function cronofyJson(response: Response, what: string): Promise<Record<string, unknown>> {
  let parsed: unknown;
  try {
    parsed = await response.json();
  } catch (error) {
    if (isTimeoutError(error)) throw new CronofyTimeoutError(what);
    throw new CronofyError(`Cronofy ${what} returned an unreadable response`);
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    throw new CronofyError(`Cronofy ${what} returned an unexpected response`);
  }
  return parsed as Record<string, unknown>;
}

async function drain(response: Response): Promise<void> {
  try {
    await response.body?.cancel();
  } catch (_) {
    // Already consumed or closed.
  }
}

// ---------------------------------------------------------------------------
// OAuth
// ---------------------------------------------------------------------------

export function buildAuthorizeUrl(provider: CalendarProvider, state: string): string {
  const { app } = cronofyBaseUrls();
  const params = new URLSearchParams({
    response_type: 'code',
    client_id: requireEnv('CRONOFY_CLIENT_ID'),
    redirect_uri: requireEnv('CALENDAR_OAUTH_REDIRECT_URI'),
    scope: SCOPE,
    state,
    // Keep each provider a separate Cronofy account, so disconnecting one
    // never touches another. (ASSUMPTION: avoid_linking=true does that.)
    avoid_linking: 'true',
  });
  const providerName = Object.hasOwn(PROVIDER_NAME, provider) ? PROVIDER_NAME[provider] : undefined;
  if (providerName) params.set('provider_name', providerName);
  return `${app}/oauth/authorize?${params.toString()}`;
}

export interface TokenSet {
  accessToken: string;
  refreshToken: string;
  /// Absolute expiry of the access token, ISO 8601.
  expiresAt: string;
  /// Cronofy's account identifier (`sub`, falling back to `account_id`).
  sub: string | null;
}

const MAX_TOKEN_LENGTH = 4096;

function isToken(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0 && value.length <= MAX_TOKEN_LENGTH;
}

export function parseTokenResponse(json: Record<string, unknown>): TokenSet {
  const accessToken = json.access_token;
  const refreshToken = json.refresh_token;
  if (!isToken(accessToken) || !isToken(refreshToken)) {
    throw new CronofyError('Cronofy token response was missing tokens');
  }
  // A missing or nonsensical lifetime falls back to one hour; anything else is
  // clamped to [1 minute, 30 days] so the stored expiry is always a real date.
  const rawExpiry = json.expires_in;
  const expiresIn = typeof rawExpiry === 'number' && Number.isFinite(rawExpiry) && rawExpiry > 0
    ? Math.min(Math.max(rawExpiry, 60), 30 * 86_400)
    : 3600;
  const rawSub = typeof json.sub === 'string'
    ? json.sub
    : typeof json.account_id === 'string'
    ? json.account_id
    : null;
  const sub = rawSub !== null && rawSub.length > 0 && rawSub.length <= 256 ? rawSub : null;
  return {
    accessToken,
    refreshToken,
    expiresAt: new Date(Date.now() + expiresIn * 1000).toISOString(),
    sub,
  };
}

async function postToken(
  body: Record<string, string>,
  what: string,
  options?: CronofyCallOptions,
): Promise<TokenSet> {
  const { api } = cronofyBaseUrls();
  const response = await cronofyFetch(`${api}/oauth/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      client_id: requireEnv('CRONOFY_CLIENT_ID'),
      client_secret: requireEnv('CRONOFY_CLIENT_SECRET'),
      ...body,
    }),
  }, what, options);
  if (!response.ok) {
    await drain(response);
    throw failure(what, response.status);
  }
  return parseTokenResponse(await cronofyJson(response, what));
}

export function exchangeCode(code: string, options?: CronofyCallOptions): Promise<TokenSet> {
  return postToken({
    grant_type: 'authorization_code',
    code,
    redirect_uri: requireEnv('CALENDAR_OAUTH_REDIRECT_URI'),
  }, 'code exchange', options);
}

/// Cronofy rotates refresh tokens: the returned set's refreshToken MUST be
/// persisted (the old one stops working).
export function refreshTokens(refreshToken: string, options?: CronofyCallOptions): Promise<TokenSet> {
  return postToken(
    { grant_type: 'refresh_token', refresh_token: refreshToken },
    'token refresh',
    options,
  );
}

/// Best effort: callers should catch and ignore failures.
export async function revokeToken(token: string, options?: CronofyCallOptions): Promise<void> {
  const { api } = cronofyBaseUrls();
  const response = await cronofyFetch(`${api}/oauth/token/revoke`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      client_id: requireEnv('CRONOFY_CLIENT_ID'),
      client_secret: requireEnv('CRONOFY_CLIENT_SECRET'),
      token,
    }),
  }, 'revoke', options);
  await drain(response);
  if (!response.ok) throw failure('revoke', response.status);
}

// ---------------------------------------------------------------------------
// Free/busy
// ---------------------------------------------------------------------------

export interface BusySpan {
  /// Epoch milliseconds.
  start: number;
  end: number;
}

/// Parses a Cronofy free_busy `start`/`end`. Timed values are ISO 8601 in UTC
/// (we always request tzid=Etc/UTC). All-day values are bare dates
/// ("2026-10-06"), which we read as local midnight in the caller's UTC offset.
/// Returns null for anything unparseable.
export function parseCronofyTime(value: unknown, tzOffsetMinutes: number): number | null {
  const raw = typeof value === 'object' && value !== null
    ? (value as Record<string, unknown>).time
    : value;
  if (typeof raw !== 'string' || raw.length > 40) return null;
  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw);
  if (dateOnly) {
    const year = Number(dateOnly[1]);
    const month = Number(dateOnly[2]);
    const day = Number(dateOnly[3]);
    const utcMidnight = Date.UTC(year, month - 1, day);
    // Reject impossible dates (2026-02-31) instead of letting them roll over.
    const check = new Date(utcMidnight);
    if (check.getUTCFullYear() !== year || check.getUTCMonth() !== month - 1 || check.getUTCDate() !== day) {
      return null;
    }
    const offset = Number.isFinite(tzOffsetMinutes) ? tzOffsetMinutes : 0;
    return utcMidnight - offset * 60_000;
  }
  // Timed values must be a full ISO 8601 date-time; a string without an
  // explicit zone is read as UTC (it is what we asked for), never as the
  // server's local time.
  const timed = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?$/.exec(raw);
  if (!timed) return null;
  const ms = Date.parse(timed[3] ? raw : `${raw}Z`);
  return Number.isFinite(ms) ? ms : null;
}

const DAY_MS = 86_400_000;
export const MAX_FREE_BUSY_PAGES = 10;
/// More busy blocks than this for one account in a three-week window is not a
/// calendar we can reason about; refuse rather than guess.
export const MAX_BUSY_SPANS = 5000;

function utcDate(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

/// Every busy interval (busy / tentative / unknown — conservatively all
/// treated as busy; only an explicit "free" is ignored) overlapping
/// [fromMs, toMs], across all of the account's calendars. Event contents are
/// never requested and never read.
///
/// All or nothing: if Cronofy has more pages than MAX_FREE_BUSY_PAGES, or any
/// page fails or times out, this THROWS — it never returns a partial picture
/// that could make a busy time look free.
export async function fetchFreeBusy(
  accessToken: string,
  fromMs: number,
  toMs: number,
  tzOffsetMinutes: number,
  options?: CronofyCallOptions,
): Promise<BusySpan[]> {
  const { api } = cronofyBaseUrls();
  const query = new URLSearchParams({
    tzid: 'Etc/UTC',
    // Whole UTC dates (the form Cronofy documents), padded so that events
    // straddling the window edges — and all-day events in any time zone — are
    // returned: from one day before, to (exclusive) at least one day after.
    from: utcDate(fromMs - DAY_MS),
    to: utcDate(toMs + 2 * DAY_MS),
  });

  const spans: BusySpan[] = [];
  let url: string | null = `${api}/v1/free_busy?${query.toString()}`;

  for (let page = 0; url !== null; page++) {
    if (page >= MAX_FREE_BUSY_PAGES) {
      throw new CronofyError('Cronofy free/busy had more pages than we read');
    }
    const response: Response = await cronofyFetch(url, {
      headers: { Authorization: `Bearer ${accessToken}` },
    }, 'free/busy', options);
    if (!response.ok) {
      await drain(response);
      throw failure('free/busy', response.status, [401]);
    }

    const json = await cronofyJson(response, 'free/busy');
    const entries = Array.isArray(json.free_busy) ? json.free_busy as unknown[] : [];
    for (const item of entries) {
      if (typeof item !== 'object' || item === null) continue;
      const entry = item as Record<string, unknown>;
      if (entry.free_busy_status === 'free') continue;
      const start = parseCronofyTime(entry.start, tzOffsetMinutes);
      const end = parseCronofyTime(entry.end, tzOffsetMinutes);
      // A block we cannot place on the timeline must not be silently treated
      // as free time.
      if (start === null || end === null) {
        throw new CronofyError('Cronofy free/busy returned a time we could not read');
      }
      if (end <= start) continue;
      spans.push({ start, end });
      if (spans.length > MAX_BUSY_SPANS) {
        throw new CronofyError('Cronofy free/busy returned more blocks than we read');
      }
    }

    // Follow pagination only to Cronofy's own API host — never send the
    // bearer token anywhere else.
    const pages = typeof json.pages === 'object' && json.pages !== null
      ? json.pages as Record<string, unknown>
      : null;
    const next = pages?.next_page;
    if (typeof next === 'string' && next.length > 0) {
      if (!next.startsWith(`${api}/`)) {
        throw new CronofyError('Cronofy free/busy pointed at an unexpected host');
      }
      url = next;
    } else {
      url = null;
    }
  }

  return spans;
}
