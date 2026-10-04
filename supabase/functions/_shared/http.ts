// Shared HTTP plumbing for every Edge Function: CORS, JSON responses, a single
// error shape, bounded body reading, bounded outbound fetches, constant-time
// secret comparison and a last-resort error guard.
//
// Deliberately pure Web-platform code (no `Deno`, no npm imports), so it can be
// bundled into any function via a relative import and exercised outside Deno.
//
// The error contract every function follows:
//   non-2xx  ->  { "error": "<calm sentence fit to show a person>",
//                  "code":  "<short_machine_code>" }
// Real causes go to console.error only — never a stack trace, never a
// third-party response body, never a token/code/email.

// ---------------------------------------------------------------------------
// CORS + responses
// ---------------------------------------------------------------------------

/// The Flutter web build calls the user-JWT functions cross-origin, so each of
/// them answers the OPTIONS preflight and carries these on EVERY response.
export const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Max-Age': '86400',
};

export interface ResponseOptions {
  /// Attach the CORS headers. Default true. Server-to-server webhooks
  /// (push-notification-engine, revenuecat-webhook) pass false: no browser
  /// should ever be able to call them.
  cors?: boolean;
  headers?: Record<string, string>;
}

export function jsonResponse(status: number, body: unknown, options: ResponseOptions = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...(options.cors === false ? {} : corsHeaders),
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
      ...(options.headers ?? {}),
    },
  });
}

/// The one error shape: `{ error, code }`.
export function errorResponse(
  status: number,
  code: string,
  message: string,
  options: ResponseOptions = {},
): Response {
  return jsonResponse(status, { error: message, code }, options);
}

/// Returns a response for a CORS preflight, or null for any other method.
export function handlePreflight(req: Request): Response | null {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { status: 200, headers: corsHeaders });
  }
  return null;
}

/// A 405 naming the method(s) that are allowed.
export function methodNotAllowed(allow: string, options: ResponseOptions = {}): Response {
  return errorResponse(405, 'method_not_allowed', 'Method not allowed.', {
    ...options,
    headers: { ...(options.headers ?? {}), Allow: allow },
  });
}

// ---------------------------------------------------------------------------
// Request bodies
// ---------------------------------------------------------------------------

export const DEFAULT_MAX_BODY_BYTES = 16 * 1024;

export type JsonBodyResult =
  | { ok: true; body: Record<string, unknown> }
  | { ok: false; response: Response };

/// Reads the request body as a JSON OBJECT, refusing anything larger than
/// `maxBytes` (checked against Content-Length first, then enforced while
/// streaming, so a lying or absent header can't get a big body buffered).
/// Arrays, scalars, null and malformed JSON are all rejected with a 400.
export async function readJsonObject(
  req: Request,
  options: { maxBytes?: number; cors?: boolean } = {},
): Promise<JsonBodyResult> {
  const maxBytes = options.maxBytes ?? DEFAULT_MAX_BODY_BYTES;
  const responseOptions: ResponseOptions = { cors: options.cors };
  const tooLarge = (): JsonBodyResult => ({
    ok: false,
    response: errorResponse(413, 'payload_too_large', 'That request is too large.', responseOptions),
  });
  const invalid = (): JsonBodyResult => ({
    ok: false,
    response: errorResponse(400, 'invalid_json', 'The request body must be a JSON object.', responseOptions),
  });

  const declared = req.headers.get('content-length');
  if (declared !== null && declared !== '') {
    const length = Number(declared);
    if (Number.isFinite(length) && length > maxBytes) return tooLarge();
  }

  let text: string;
  try {
    if (!req.body) return invalid();
    const reader = req.body.getReader();
    const chunks: Uint8Array[] = [];
    let total = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value) continue;
      total += value.byteLength;
      if (total > maxBytes) {
        try {
          await reader.cancel();
        } catch (_) {
          // Nothing useful to do; we are rejecting the request anyway.
        }
        return tooLarge();
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    text = new TextDecoder().decode(bytes);
  } catch (_) {
    return invalid();
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch (_) {
    return invalid();
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) return invalid();
  return { ok: true, body: parsed as Record<string, unknown> };
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(value: unknown): value is string {
  return typeof value === 'string' && UUID_RE.test(value);
}

export function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

// A full ISO 8601 instant with an explicit zone, e.g. 2026-10-06T00:00:00.000Z
// (what Dart's toUtc().toIso8601String() produces). Stricter than Date.parse,
// which also accepts things like "October 6, 2026".
const ISO_INSTANT_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,9})?)?(Z|[+-]\d{2}:?\d{2})$/;

/// Epoch milliseconds for a strict ISO 8601 instant, or null.
export function parseIsoInstant(value: unknown): number | null {
  if (typeof value !== 'string' || value.length > 40 || !ISO_INSTANT_RE.test(value)) return null;
  const ms = Date.parse(value);
  return Number.isFinite(ms) ? ms : null;
}

// ---------------------------------------------------------------------------
// Secrets
// ---------------------------------------------------------------------------

/// Constant-time comparison of a presented secret against the expected one.
/// Both sides are hashed first, so neither the content nor the LENGTH of the
/// expected secret can be learned from response timing. Fails closed: an
/// empty/unset expected secret never matches.
export async function secretsMatch(
  provided: string | null | undefined,
  expected: string | null | undefined,
): Promise<boolean> {
  if (!expected) return false;
  const encoder = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest('SHA-256', encoder.encode(provided ?? '')),
    crypto.subtle.digest('SHA-256', encoder.encode(expected)),
  ]);
  const x = new Uint8Array(a);
  const y = new Uint8Array(b);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

// ---------------------------------------------------------------------------
// Outbound requests — always bounded
// ---------------------------------------------------------------------------

/// The third party did not answer within the allowed time.
export class FetchTimeoutError extends Error {
  constructor(what: string) {
    super(`${what} timed out`);
    this.name = 'FetchTimeoutError';
  }
}

/// The request never completed (DNS, TLS, connection reset, unreadable body).
export class FetchNetworkError extends Error {
  constructor(what: string) {
    super(`${what} failed (network error)`);
    this.name = 'FetchNetworkError';
  }
}

export function isTimeoutError(error: unknown): boolean {
  if (error instanceof FetchTimeoutError) return true;
  const name = (error as { name?: unknown } | null)?.name;
  return name === 'TimeoutError' || name === 'AbortError';
}

/// fetch() that cannot hang: aborts after `timeoutMs` and turns every failure
/// into a typed error (FetchTimeoutError / FetchNetworkError) whose message
/// contains only `what` — never the URL, headers or body. The timeout keeps
/// running while the response body is read, so use readJsonBody/readTextBody
/// below to get the same typed errors from a stalled body.
export async function fetchWithTimeout(
  url: string | URL,
  init: RequestInit,
  timeoutMs: number,
  what: string,
): Promise<Response> {
  if (!(timeoutMs > 0)) throw new FetchTimeoutError(what);
  try {
    return await fetch(url, { ...init, signal: AbortSignal.timeout(timeoutMs) });
  } catch (error) {
    throw isTimeoutError(error) ? new FetchTimeoutError(what) : new FetchNetworkError(what);
  }
}

/// response.json() with typed failures. A body that is not JSON is reported as
/// a network-class failure (the third party misbehaved).
export async function readJsonBody(response: Response, what: string): Promise<unknown> {
  try {
    return await response.json();
  } catch (error) {
    throw isTimeoutError(error) ? new FetchTimeoutError(what) : new FetchNetworkError(what);
  }
}

/// At most `maxChars` of the body as text; never throws.
export async function readTextBody(response: Response, maxChars = 2000): Promise<string> {
  try {
    return (await response.text()).slice(0, maxChars);
  } catch (_) {
    return '';
  }
}

/// Releases a response we are not going to read; never throws.
export async function discardBody(response: Response): Promise<void> {
  try {
    await response.body?.cancel();
  } catch (_) {
    // Already consumed or already closed.
  }
}

/// A fetch implementation with a built-in deadline, for clients that take a
/// custom fetch (supabase-js: `global: { fetch }`), so a stalled database or
/// auth call becomes an ordinary error instead of a hung request.
export function fetchWithDeadline(timeoutMs: number): typeof fetch {
  return ((input: RequestInfo | URL, init?: RequestInit) => {
    const timeout = AbortSignal.timeout(timeoutMs);
    const callerSignal = init?.signal ?? null;
    const signal = callerSignal && typeof AbortSignal.any === 'function'
      ? AbortSignal.any([callerSignal, timeout])
      : timeout;
    return fetch(input, { ...init, signal });
  }) as typeof fetch;
}

// ---------------------------------------------------------------------------
// Logging + the last-resort guard
// ---------------------------------------------------------------------------

/// Strips anything that looks like an email address, a bearer credential or a
/// long opaque token from a string that is about to be logged or stored.
export function redact(text: string): string {
  return text
    .slice(0, 1000)
    .replace(/[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9-]{1,63}(\.[A-Za-z0-9-]{1,63})+/g, '[email]')
    .replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/gi, 'Bearer [redacted]')
    // JWT-shaped: three dot-separated base64url segments.
    .replace(/[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g, '[redacted]')
    // Any other long opaque run (a uuid, at 36 characters, is left alone).
    .replace(/[A-Za-z0-9_-]{40,}/g, '[redacted]');
}

/// "Name: message" for a thrown value (or a supabase-js `{ message, code }`
/// error object), redacted and bounded. No stack trace.
export function describeError(error: unknown): string {
  let text: string;
  if (error instanceof Error) {
    text = `${error.name}: ${error.message}`;
  } else if (isPlainObject(error)) {
    const code = typeof error.code === 'string' ? `[${error.code}] ` : '';
    text = `${code}${typeof error.message === 'string' ? error.message : 'unknown error'}`;
  } else {
    text = typeof error === 'string' ? error : 'unknown error';
  }
  return redact(text).slice(0, 300);
}

/// Wraps a handler so that ANY thrown error becomes a calm JSON 500 (or
/// whatever `onError` builds) and the real cause is logged. Use it as
/// `Deno.serve(guarded('name', handler))`.
export function guarded(
  name: string,
  handler: (req: Request) => Promise<Response> | Response,
  onError?: (error: unknown) => Response,
): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    try {
      return await handler(req);
    } catch (error) {
      console.error(`${name}: unhandled error:`, describeError(error));
      try {
        if (onError) return onError(error);
      } catch (_) {
        // Fall through to the default below.
      }
      return errorResponse(500, 'internal_error', 'Something went wrong on our side. Please try again.');
    }
  };
}
