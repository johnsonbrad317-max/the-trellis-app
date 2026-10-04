// The Trellis — calendar-connect-start
// =============================================================================
// Step 1 of connecting a calendar. The app calls
//   supabase.functions.invoke('calendar-connect-start', body: { provider })
// (the SDK attaches the caller's JWT), then opens the returned `authorize_url`
// in the external browser. After the user approves at Cronofy, Cronofy
// redirects the browser to calendar-oauth-callback, which finishes the job.
//
// Contract with the app (lib/services/calendar_service.dart → connect):
//   200 { authorize_url: "https://..." }
//   non-2xx { error, code }
//     400 invalid_json | invalid_request      401 unauthorized
//     413 payload_too_large                   405 method_not_allowed
//     500 state_failed | internal_error       503 not_configured | auth_unavailable
//
// This function makes no third-party network call: it only writes a single-use
// nonce row and signs it.
//
// Deploy (JWT verification ON — the default):
//   supabase functions deploy calendar-connect-start
//
// Secrets: CRONOFY_CLIENT_ID, CRONOFY_DATA_CENTER, CALENDAR_OAUTH_REDIRECT_URI,
// CALENDAR_STATE_SECRET (see supabase/CALENDAR_SETUP.md). SUPABASE_* are
// injected automatically.
// =============================================================================

import { authenticate } from '../_shared/auth.ts';
import { buildAuthorizeUrl, isCalendarProvider, missingSecrets } from '../_shared/cronofy.ts';
import {
  describeError,
  errorResponse,
  guarded,
  handlePreflight,
  jsonResponse,
  methodNotAllowed,
  readJsonObject,
} from '../_shared/http.ts';
import { signState } from '../_shared/state.ts';

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
    return errorResponse(400, 'invalid_request', 'provider must be google, outlook or apple.');
  }

  // Check the configuration BEFORE creating a nonce, so an unconfigured server
  // answers clearly and leaves nothing behind.
  const missing = missingSecrets('CRONOFY_CLIENT_ID', 'CALENDAR_OAUTH_REDIRECT_URI', 'CALENDAR_STATE_SECRET');
  if (missing.length > 0) {
    // Names only — never values.
    console.error('calendar-connect-start: not configured; missing secrets:', missing.join(', '));
    return errorResponse(503, 'not_configured', 'Calendar connection is not available yet. Please try again later.');
  }

  const { data: nonce, error } = await caller.admin.rpc('calendar_create_oauth_state', {
    p_user_id: caller.userId,
    p_provider: provider,
  });
  if (error || typeof nonce !== 'string' || nonce.length === 0) {
    console.error('calendar-connect-start: calendar_create_oauth_state failed:', describeError(error));
    return errorResponse(500, 'state_failed', 'Could not start the calendar connection. Please try again.');
  }

  try {
    const state = await signState(nonce);
    return jsonResponse(200, { authorize_url: buildAuthorizeUrl(provider, state) });
  } catch (e) {
    // The message names a missing secret or a malformed nonce, never a value.
    console.error('calendar-connect-start: could not build the authorize URL:', describeError(e));
    return errorResponse(500, 'state_failed', 'Could not start the calendar connection. Please try again.');
  }
}

Deno.serve(guarded('calendar-connect-start', handle));
