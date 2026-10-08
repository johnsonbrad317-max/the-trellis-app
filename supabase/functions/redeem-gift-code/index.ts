// The Trellis — redeem-gift-code
// =============================================================================
// Redeems a gift-membership code ON THE WEBSITE. The recipient opens the
// unhinderedlives.com redeem page, types the code and the email address of
// their Trellis account, and the website's SERVER calls this. The app has no
// code field (App Review Guideline 3.1.1 forbids unlocking with license keys);
// it simply finds the account's membership active the next time it checks.
// Contract for the website's developer: docs/gift-codes-for-website.md.
//
// URL:  https://qonsiliimbkcjmcnhonb.supabase.co/functions/v1/redeem-gift-code
//
// Authentication: the same shared secret as issue-gift-code, in the
// `x-trellis-gift-secret` header, compared in constant time with
// GIFT_CODE_SECRET (fails closed when unset). Deployed with --no-verify-jwt;
// server-to-server only, NO CORS headers.
//
// Request:  POST, JSON  { "code": "7KQ3M-X9ZPA", "email": "runner@example.com" }
//
// Responses (always JSON):
//   200 { ok: true, paid_until }
//   200 { ok: false, reason: not_recognized | no_account | rate_limited, message }
//   400 { error, code: invalid_json | invalid_request }
//   401 { error, code: unauthorized }
//   405 { error, code: method_not_allowed }
//   413 { error, code: payload_too_large }
//   500 { error, code: not_configured | redeem_failed | internal_error }
//
// The work is done by public.redeem_gift_code_for_email() (migration 030),
// which only the service role may call.
// =============================================================================

import { createClient } from 'npm:@supabase/supabase-js@2';
import {
  describeError,
  errorResponse,
  fetchWithDeadline,
  guarded,
  isPlainObject,
  jsonResponse,
  methodNotAllowed,
  readJsonObject,
  secretsMatch,
} from '../_shared/http.ts';

const NO_CORS = { cors: false } as const;
const DB_TIMEOUT_MS = 10_000;
const EMAIL_RE = /^[^@\s]{1,64}@[^@\s]{1,253}\.[^@\s]{1,63}$/;

/// Sentences the website can show the recipient as they are.
const MESSAGES: Record<string, string> = {
  not_recognized: "That code wasn't recognized or has already been used.",
  no_account:
    "We couldn't find a Trellis account with that email. Download The Trellis, create your " +
    'account, then come back here with the same email. Your code is still good.',
  rate_limited: 'Too many tries for now. Please wait a while and try again.',
};

async function handle(req: Request): Promise<Response> {
  if (req.method !== 'POST') return methodNotAllowed('POST', NO_CORS);

  // 1. Authenticate first.
  const secret = Deno.env.get('GIFT_CODE_SECRET');
  if (!secret) {
    console.error('redeem-gift-code: GIFT_CODE_SECRET is not set; rejecting every call.');
  }
  if (!(await secretsMatch(req.headers.get('x-trellis-gift-secret'), secret))) {
    return errorResponse(401, 'unauthorized', 'Unauthorized.', NO_CORS);
  }

  // 2. Validate the payload.
  const parsed = await readJsonObject(req, { cors: false });
  if (!parsed.ok) return parsed.response;
  const { code, email } = parsed.body;
  const cleanCode = typeof code === 'string' ? code.replace(/[^A-Za-z0-9]/g, '').toUpperCase() : '';
  if (cleanCode.length === 0 || cleanCode.length > 32) {
    return errorResponse(400, 'invalid_request', 'code is required.', NO_CORS);
  }
  const cleanEmail = typeof email === 'string' ? email.trim() : '';
  if (cleanEmail.length > 320 || !EMAIL_RE.test(cleanEmail)) {
    return errorResponse(400, 'invalid_request', 'email is not a valid email address.', NO_CORS);
  }

  // 3. Redeem.
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    console.error('redeem-gift-code: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing');
    return errorResponse(500, 'not_configured', 'Gift codes are not configured.', NO_CORS);
  }
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch: fetchWithDeadline(DB_TIMEOUT_MS) },
  });

  const { data, error } = await supabase.rpc('redeem_gift_code_for_email', {
    p_code: cleanCode,
    p_email: cleanEmail,
  });
  if (error || !isPlainObject(data)) {
    console.error('redeem-gift-code: redeem_gift_code_for_email failed:', describeError(error));
    return errorResponse(500, 'redeem_failed', 'Could not redeem the code. Please try again.', NO_CORS);
  }

  if (data.ok === true) {
    return jsonResponse(200, { ok: true, paid_until: data.paid_until }, NO_CORS);
  }
  const reason = typeof data.reason === 'string' && data.reason in MESSAGES ? data.reason : 'not_recognized';
  return jsonResponse(200, { ok: false, reason, message: MESSAGES[reason] }, NO_CORS);
}

Deno.serve(guarded(
  'redeem-gift-code',
  handle,
  () => errorResponse(500, 'internal_error', 'Something went wrong on our side. Please try again.', NO_CORS),
));

// =============================================================================
// Deployment notes (not code — nothing below this line runs)
// =============================================================================
// 1. Apply supabase/migrations/030_gift_codes_redeemed_on_web.sql (after 029).
// 2. GIFT_CODE_SECRET is shared with issue-gift-code; set it once.
// 3. Deploy with JWT verification OFF (the secret header is the gate):
//      supabase functions deploy redeem-gift-code --no-verify-jwt
// =============================================================================
