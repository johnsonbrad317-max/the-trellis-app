// Caller authentication for the user-JWT functions (submit-feedback,
// delete-account): an anon-key client carrying the caller's own Authorization
// header is used ONLY to establish who is asking (auth.getUser() verifies the
// token with the auth server — a forged, expired or deleted-user token is
// rejected); everything else goes through a service-role client.
//
// Every client built here has a request deadline, so a stalled auth or database
// call becomes an ordinary error instead of a hung function.

import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';
import { describeError, errorResponse, fetchWithDeadline } from './http.ts';

/// Deadline for each auth/database round trip made through these clients.
export const DB_TIMEOUT_MS = 10_000;

export interface AuthedCaller {
  userId: string;
  /// The caller's verified account email (from their session, never from a
  /// request body). Null for accounts without one.
  email: string | null;
  admin: SupabaseClient;
}

function clientOptions(timeoutMs: number, headers?: Record<string, string>) {
  return {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch: fetchWithDeadline(timeoutMs), ...(headers ? { headers } : {}) },
  };
}

/// Service-role client, or null when the platform credentials are missing.
export function adminClientOrNull(timeoutMs: number = DB_TIMEOUT_MS): SupabaseClient | null {
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) return null;
  return createClient(supabaseUrl, serviceRoleKey, clientOptions(timeoutMs));
}

/// Resolves the caller, or returns a ready-made error Response (401 when the
/// session is missing/invalid, 503 when auth can't be reached, 500 when the
/// function itself is not configured). Never throws.
export async function authenticate(
  req: Request,
  options: { adminTimeoutMs?: number } = {},
): Promise<AuthedCaller | Response> {
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = /^Bearer\s+(\S+)$/i.exec(authHeader.trim())?.[1] ?? '';
  if (!token) {
    return errorResponse(401, 'unauthorized', 'Please sign in again.');
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const admin = adminClientOrNull(options.adminTimeoutMs ?? DB_TIMEOUT_MS);
  if (!supabaseUrl || !anonKey || !admin) {
    console.error('authenticate: SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY missing');
    return errorResponse(500, 'not_configured', 'This feature is not available right now.');
  }

  try {
    const callerClient = createClient(
      supabaseUrl,
      anonKey,
      clientOptions(DB_TIMEOUT_MS, { Authorization: `Bearer ${token}` }),
    );
    // The token is passed explicitly, so this works the same on every
    // supabase-js 2.x release.
    const { data, error } = await callerClient.auth.getUser(token);
    const user = data?.user ?? null;
    if (error || !user) {
      // A missing HTTP status means the auth server could not be reached (or
      // timed out) — that is our problem, not an invalid session.
      const status = (error as { status?: number } | null)?.status;
      if (error && (status === undefined || status === 0 || status >= 500)) {
        console.error('authenticate: auth lookup failed:', describeError(error));
        return errorResponse(503, 'auth_unavailable', 'We could not verify your session. Please try again.');
      }
      return errorResponse(401, 'unauthorized', 'Your session has expired. Please sign in again.');
    }
    return { userId: user.id, email: user.email ?? null, admin };
  } catch (error) {
    console.error('authenticate: auth lookup threw:', describeError(error));
    return errorResponse(503, 'auth_unavailable', 'We could not verify your session. Please try again.');
  }
}
