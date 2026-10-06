// The Trellis — calendar-disconnect
// =============================================================================
// Disconnects one calendar provider for the signed-in user: revokes the grant
// at Cronofy (best effort — a Cronofy outage, timeout or missing Cronofy
// secret must never trap a user in a connected state) and deletes the
// connection row, whose trigger also purges the tokens from Supabase Vault.
//
//   supabase.functions.invoke('calendar-disconnect', body: { provider })
//
// Contract with the app (lib/services/calendar_service.dart → disconnect):
//   200 { disconnected: true }      (also when there was nothing to disconnect)
//   non-2xx { error, code }
//     400 invalid_json | invalid_request      401 unauthorized
//     413 payload_too_large                   405 method_not_allowed
//     500 disconnect_failed | internal_error  503 auth_unavailable
//
// Deploy (JWT verification ON — the default):
//   supabase functions deploy calendar-disconnect
//
// Secrets: CRONOFY_CLIENT_ID, CRONOFY_CLIENT_SECRET, CRONOFY_DATA_CENTER.
// =============================================================================

import { authenticate } from '../_shared/auth.ts';
import { isCalendarProvider, revokeToken } from '../_shared/cronofy.ts';
import {
  describeError,
  errorResponse,
  guarded,
  handlePreflight,
  jsonResponse,
  methodNotAllowed,
  readJsonObject,
} from '../_shared/http.ts';

interface TokenRow {
  refresh_token: string | null;
  access_token: string | null;
}

/// The revoke is a courtesy; don't make the person wait long for it.
const REVOKE_TIMEOUT_MS = 8_000;

async function handle(req: Request): Promise<Response> {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== 'POST') return methodNotAllowed('POST, OPTIONS');

  const caller = await authenticate(req);
  if (caller instanceof Response) return caller;

  const read = await readJsonObject(req);
  if (!read.ok) return read.response;
  const provider = read.body.provider;
  if (!isCalendarProvider(provider)) {
    return errorResponse(
      400,
      'invalid_request',
      'provider must be google, outlook, outlook_personal or apple.',
    );
  }

  // Revoke first (best effort), while we still hold the token. Nothing in this
  // block may stop the local delete below.
  try {
    const { data: rows, error: readError } = await caller.admin.rpc('calendar_read_tokens', {
      p_user_id: caller.userId,
      p_provider: provider,
    });
    if (readError) {
      console.error('calendar-disconnect: could not read tokens (skipping revoke):', describeError(readError));
    }
    const row = (Array.isArray(rows) ? rows[0] : null) as TokenRow | null;
    const token = row?.refresh_token || row?.access_token || null;
    if (typeof token === 'string' && token.length > 0) {
      await revokeToken(token, { timeoutMs: REVOKE_TIMEOUT_MS });
    }
  } catch (e) {
    console.error('calendar-disconnect: Cronofy revoke failed (continuing with local delete):', describeError(e));
  }

  const { error } = await caller.admin.rpc('calendar_delete_connection', {
    p_user_id: caller.userId,
    p_provider: provider,
  });
  if (error) {
    console.error('calendar-disconnect: calendar_delete_connection failed:', describeError(error));
    return errorResponse(500, 'disconnect_failed', 'Could not disconnect the calendar. Please try again.');
  }

  return jsonResponse(200, { disconnected: true });
}

Deno.serve(guarded('calendar-disconnect', handle));
