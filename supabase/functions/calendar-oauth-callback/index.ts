// The Trellis — calendar-oauth-callback
// =============================================================================
// Step 2 of connecting a calendar. Cronofy redirects the user's BROWSER here
// (GET ?code=...&state=...) after they approve. There is no app JWT on a
// browser redirect, so this function is deployed with JWT verification OFF and
// authenticates the request itself:
//   1. `state` must carry a valid HMAC signature (CALENDAR_STATE_SECRET), so a
//      forged callback is rejected — checked with pure computation, BEFORE any
//      network or database call;
//   2. the nonce inside it must be an unused, unexpired row in
//      calendar_oauth_states (consumed atomically — single use), which also
//      tells us WHICH user and provider this is. Nothing in the URL is trusted
//      to name the user.
// Only then does it exchange the code for tokens (10 s timeout), store them in
// Supabase Vault via the service-role-only SQL helper, and show a small themed
// result page.
//
// Nothing from the query string is ever written into the page: every message
// is a fixed sentence chosen here. The code and tokens are never logged or
// echoed. Whatever goes wrong — the person cancelled, Cronofy is down or slow,
// the server is not configured, an unexpected exception — the browser gets the
// same calm page, never a stack trace.
//
// Deploy (JWT verification OFF — a browser redirect carries no JWT):
//   supabase functions deploy calendar-oauth-callback --no-verify-jwt
//
// Secrets: CRONOFY_CLIENT_ID, CRONOFY_CLIENT_SECRET, CRONOFY_DATA_CENTER,
// CALENDAR_OAUTH_REDIRECT_URI, CALENDAR_STATE_SECRET, and optionally
// CALENDAR_RESULT_REDIRECT_URL (see below / supabase/CALENDAR_SETUP.md).
//
// RESULT PAGE: Supabase serves text/html from the default *.supabase.co domain
// as text/plain. So, if CALENDAR_RESULT_REDIRECT_URL (an https URL hosting
// result.html from this folder) is set, this function 302-redirects there with
// ?status=connected|cancelled|error instead of returning HTML itself. Without
// it, the themed HTML is returned directly (fine on a custom domain).
// =============================================================================

import { adminClientOrNull } from '../_shared/auth.ts';
import {
  type CalendarProvider,
  exchangeCode,
  isCalendarProvider,
  missingSecrets,
  revokeToken,
  type TokenSet,
} from '../_shared/cronofy.ts';
import { describeError, guarded, methodNotAllowed } from '../_shared/http.ts';
import { renderResultPage } from '../_shared/result_page.ts';
import { StateSecretMissingError, verifyState } from '../_shared/state.ts';

const PROVIDER_LABEL: Record<CalendarProvider, string> = {
  google: 'Google Calendar',
  outlook: 'Outlook Calendar',
  outlook_personal: 'Outlook.com Calendar',
  apple: 'Apple Calendar',
};

/// Best-effort revokes must not keep the person staring at a blank tab.
const REVOKE_TIMEOUT_MS = 5_000;

type Outcome = 'connected' | 'cancelled' | 'error';

const MESSAGES = {
  cancelled: 'The calendar connection was cancelled. You can try again from The Trellis.',
  providerError: 'Your calendar provider could not complete the connection. Please try again from The Trellis.',
  incomplete: 'This link is incomplete. Please start again from The Trellis.',
  invalid: 'This link is invalid or has expired. Please start again from The Trellis.',
  used: 'This link has already been used or has expired. Please start again from The Trellis.',
  notConfigured: 'Calendar connection is not configured yet. Please try again later.',
  exchange: 'We could not complete the connection with your calendar provider. Please try again.',
  save: 'We could not save your calendar connection. Please try again.',
  unexpected: 'Something went wrong while connecting your calendar. Please try again from The Trellis.',
  connected: 'Return to The Trellis to continue.',
} as const;

/// A themed page, or — when CALENDAR_RESULT_REDIRECT_URL is configured — a
/// redirect to the hosted copy of it. `message` is always one of MESSAGES;
/// `provider` is always a validated value from our own database.
function finish(outcome: Outcome, provider: CalendarProvider | null, message: string): Response {
  const target = Deno.env.get('CALENDAR_RESULT_REDIRECT_URL');
  if (target && target.startsWith('https://')) {
    try {
      const url = new URL(target);
      url.searchParams.set('status', outcome);
      if (provider) url.searchParams.set('provider', provider);
      return new Response(null, {
        status: 302,
        headers: { Location: url.toString(), 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer' },
      });
    } catch (_) {
      // Malformed URL in the secret: fall through to the inline page.
    }
  }

  if (outcome === 'connected') {
    const label = provider ? PROVIDER_LABEL[provider] : 'Your calendar';
    return renderResultPage({ ok: true, title: 'Calendar connected', message: `${label} is connected. ${message}` });
  }
  return renderResultPage({
    ok: false,
    title: 'Calendar not connected',
    message,
    // Cancelling is the person's choice, not a bad request.
    status: outcome === 'cancelled' ? 200 : 400,
  });
}

interface ExistingTokens {
  cronofy_sub: string | null;
  refresh_token: string | null;
}

/// Revoke that can never throw or hang the response.
async function revokeQuietly(token: string, why: string): Promise<void> {
  try {
    await revokeToken(token, { timeoutMs: REVOKE_TIMEOUT_MS });
  } catch (e) {
    console.error(`calendar-oauth-callback: could not revoke ${why} (ignored):`, describeError(e));
  }
}

async function handle(req: Request): Promise<Response> {
  if (req.method !== 'GET') return methodNotAllowed('GET', { cors: false });

  const params = new URL(req.url).searchParams;

  // The person pressed cancel, or the provider reported a problem. Handled
  // without any network call; the parameter's text is never shown or logged
  // verbatim (only whether it was the standard "access_denied").
  const providerError = params.get('error');
  if (providerError !== null) {
    if (providerError === 'access_denied') {
      return finish('cancelled', null, MESSAGES.cancelled);
    }
    console.error('calendar-oauth-callback: provider returned an error other than access_denied.');
    return finish('error', null, MESSAGES.providerError);
  }

  const code = params.get('code');
  const state = params.get('state');
  // Authorization codes are short opaque tokens: printable ASCII, no spaces.
  if (!code || !state || !/^[\x21-\x7e]{1,2048}$/.test(code) || state.length > 512) {
    return finish('error', null, MESSAGES.incomplete);
  }

  // 1. Signature — pure computation, before any network or database call.
  let nonce: string | null;
  try {
    nonce = await verifyState(state);
  } catch (e) {
    console.error(
      'calendar-oauth-callback: not configured:',
      e instanceof StateSecretMissingError ? e.message : describeError(e),
    );
    return finish('error', null, MESSAGES.notConfigured);
  }
  if (!nonce) {
    return finish('error', null, MESSAGES.invalid);
  }

  // Configuration, checked before the nonce is spent.
  const missing = missingSecrets('CRONOFY_CLIENT_ID', 'CRONOFY_CLIENT_SECRET', 'CALENDAR_OAUTH_REDIRECT_URI');
  const admin = adminClientOrNull();
  if (missing.length > 0 || !admin) {
    console.error(
      'calendar-oauth-callback: not configured; missing secrets:',
      [...missing, ...(admin ? [] : ['SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY'])].join(', '),
    );
    return finish('error', null, MESSAGES.notConfigured);
  }

  // 2. Single-use nonce -> which user and provider this is.
  const { data: consumed, error: consumeError } = await admin.rpc('calendar_consume_oauth_state', {
    p_nonce: nonce,
  });
  if (consumeError) {
    console.error('calendar-oauth-callback: calendar_consume_oauth_state failed:', describeError(consumeError));
    return finish('error', null, MESSAGES.unexpected);
  }
  const row = Array.isArray(consumed) ? consumed[0] : null;
  if (!row || typeof row.user_id !== 'string' || !isCalendarProvider(row.provider)) {
    return finish('error', null, MESSAGES.used);
  }
  const userId: string = row.user_id;
  const provider: CalendarProvider = row.provider;

  // 3. Exchange the code (bounded; a timeout lands in the catch).
  let tokens: TokenSet;
  try {
    tokens = await exchangeCode(code);
  } catch (e) {
    console.error('calendar-oauth-callback: Cronofy code exchange failed:', describeError(e));
    return finish('error', provider, MESSAGES.exchange);
  }

  // 4. Remember the grant this provider was previously connected with (if
  //    any), so it can be revoked once the new one is safely stored.
  let previous: ExistingTokens | null = null;
  try {
    const { data: existing, error: readError } = await admin.rpc('calendar_read_tokens', {
      p_user_id: userId,
      p_provider: provider,
    });
    if (readError) throw new Error(describeError(readError));
    previous = (Array.isArray(existing) ? existing[0] : null) as ExistingTokens | null;
  } catch (e) {
    console.error('calendar-oauth-callback: could not read the previous connection (ignored):', describeError(e));
  }

  // 5. Store the tokens in Vault and upsert the connection.
  let saveFailed = false;
  try {
    const { error: saveError } = await admin.rpc('calendar_save_connection', {
      p_user_id: userId,
      p_provider: provider,
      p_cronofy_sub: tokens.sub,
      p_access_token: tokens.accessToken,
      p_refresh_token: tokens.refreshToken,
      p_expires_at: tokens.expiresAt,
    });
    if (saveError) {
      saveFailed = true;
      console.error('calendar-oauth-callback: calendar_save_connection failed:', describeError(saveError));
    }
  } catch (e) {
    saveFailed = true;
    console.error('calendar-oauth-callback: calendar_save_connection threw:', describeError(e));
  }
  if (saveFailed) {
    // Don't leave a grant at Cronofy that we hold no record of — unless it is
    // the same account as the connection that is still stored.
    if (!previous?.cronofy_sub || previous.cronofy_sub !== tokens.sub) {
      await revokeQuietly(tokens.refreshToken, 'the unsaved grant');
    }
    return finish('error', provider, MESSAGES.save);
  }

  // 6. If this provider was previously connected to a DIFFERENT calendar
  //    account, revoke the old grant (best effort) so it doesn't linger.
  if (previous?.refresh_token && previous.cronofy_sub && tokens.sub && previous.cronofy_sub !== tokens.sub) {
    await revokeQuietly(previous.refresh_token, 'the previous grant');
  }

  return finish('connected', provider, MESSAGES.connected);
}

Deno.serve(guarded(
  'calendar-oauth-callback',
  handle,
  // Even a completely unexpected failure shows the calm page.
  () => finish('error', null, MESSAGES.unexpected),
));
