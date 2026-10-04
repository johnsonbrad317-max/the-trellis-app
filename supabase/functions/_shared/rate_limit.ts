// Shared rate limiting for Edge Functions, backed by the `edge_rate_limit_hit`
// Postgres function (supabase/migrations/020_edge_rate_limits.sql) so every
// function instance shares one count.
//
// Deliberately pure (no `Deno`, no npm imports): the database client is taken
// as a structural type, so this can be unit-tested outside Deno.
//
// Failure policy: FAIL OPEN. If the limiter itself cannot be reached (the
// migration has not been applied yet, a database blip), the request is let
// through and the problem is logged — a broken limiter must not take the
// feature down with it. The limits exist to stop abuse of a third-party quota,
// and every function that uses this has already authenticated the caller.

import { jsonResponse } from './http.ts';

/// The slice of a Supabase client this module needs.
export interface RpcClient {
  rpc(
    fn: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: { message?: string; code?: string } | null }>;
}

export interface RateLimit {
  /// Short label for the window, e.g. 'minute' — becomes part of the key.
  name: string;
  limit: number;
  windowSeconds: number;
}

export type RateLimitResult =
  | { allowed: true }
  | { allowed: false; retryAfterSeconds: number };

/// Counts one request for `subject` (e.g. a user id) against each limit in
/// order and stops at the first one that is exceeded. Never throws.
export async function checkRateLimits(
  admin: RpcClient,
  scope: string,
  subject: string,
  limits: RateLimit[],
): Promise<RateLimitResult> {
  for (const rule of limits) {
    try {
      const { data, error } = await admin.rpc('edge_rate_limit_hit', {
        p_key: `${scope}:${subject}:${rule.name}`,
        p_limit: rule.limit,
        p_window_seconds: rule.windowSeconds,
      });
      if (error) {
        console.error(`${scope}: rate limiter unavailable (failing open):`, error.code ?? 'error');
        return { allowed: true };
      }
      const row = Array.isArray(data) ? data[0] : data;
      if (row === null || typeof row !== 'object') {
        console.error(`${scope}: rate limiter returned nothing (failing open)`);
        return { allowed: true };
      }
      const { allowed, retry_after_seconds: retryAfter } = row as Record<string, unknown>;
      if (allowed === false) {
        const seconds = typeof retryAfter === 'number' && Number.isFinite(retryAfter) && retryAfter >= 1
          ? Math.ceil(retryAfter)
          : rule.windowSeconds;
        return { allowed: false, retryAfterSeconds: seconds };
      }
    } catch (e) {
      console.error(`${scope}: rate limiter threw (failing open):`, e instanceof Error ? e.name : 'unknown');
      return { allowed: true };
    }
  }
  return { allowed: true };
}

/// The 429 for an exceeded limit: the usual `{ error, code }` plus
/// `retry_after_seconds`, and a standard `Retry-After` header.
export function rateLimitedResponse(retryAfterSeconds: number, message: string): Response {
  return jsonResponse(
    429,
    { error: message, code: 'rate_limited', retry_after_seconds: retryAfterSeconds },
    { headers: { 'Retry-After': String(retryAfterSeconds) } },
  );
}
