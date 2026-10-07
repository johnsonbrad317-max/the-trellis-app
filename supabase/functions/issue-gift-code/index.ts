// The Trellis — issue-gift-code
// =============================================================================
// Mints gift-membership codes for the unhinderedlives.com website, which sells
// them. The website's SERVER calls this after a successful checkout and shows /
// emails the codes to the buyer; the person receiving one redeems it in the app
// (Account & Membership -> "Have a gift code?", or the "two free weeks are
// over" page). Contract for the website's developer:
// docs/gift-codes-for-website.md.
//
// URL:  https://qonsiliimbkcjmcnhonb.supabase.co/functions/v1/issue-gift-code
//
// Authentication: a shared secret in the `x-trellis-gift-secret` header,
// compared in constant time with this function's GIFT_CODE_SECRET secret
// (fails closed when the secret is unset). The website is not a Supabase user,
// so the function is deployed with --no-verify-jwt and this header is the only
// gate. Server-to-server only: NO CORS headers, so no browser page can call it
// (the secret must never reach a browser).
//
// Request:  POST, JSON
//   { "quantity": 1..20 (default 1),
//     "months": 1..120 (default 12),
//     "purchaser_email": "buyer@example.com" (optional, recorded for support) }
//
// Responses (always JSON):
//   200 { codes: ["7KQ3MX9ZPA", ...], months }
//   400 { error, code: invalid_json | invalid_request }
//   401 { error, code: unauthorized }
//   405 { error, code: method_not_allowed }
//   413 { error, code: payload_too_large }
//   500 { error, code: not_configured | issue_failed | internal_error }
//
// The codes are minted by public.issue_gift_codes() (migration 029), which only
// the service role may call.
// =============================================================================

import { createClient } from 'npm:@supabase/supabase-js@2';
import {
  describeError,
  errorResponse,
  fetchWithDeadline,
  guarded,
  jsonResponse,
  methodNotAllowed,
  readJsonObject,
  secretsMatch,
} from '../_shared/http.ts';

const NO_CORS = { cors: false } as const;
const DB_TIMEOUT_MS = 10_000;
const MAX_QUANTITY = 20;
const MAX_MONTHS = 120;
const DEFAULT_MONTHS = 12;
const EMAIL_RE = /^[^@\s]{1,64}@[^@\s]{1,253}\.[^@\s]{1,63}$/;

interface IssueRequest {
  quantity: number;
  months: number;
  purchaserEmail: string | null;
}

/// Validates the body; returns an error sentence, or the cleaned request.
function parseBody(body: Record<string, unknown>): IssueRequest | string {
  const quantity = body.quantity ?? 1;
  if (typeof quantity !== 'number' || !Number.isInteger(quantity) || quantity < 1 || quantity > MAX_QUANTITY) {
    return `quantity must be a whole number from 1 to ${MAX_QUANTITY}.`;
  }

  const months = body.months ?? DEFAULT_MONTHS;
  if (typeof months !== 'number' || !Number.isInteger(months) || months < 1 || months > MAX_MONTHS) {
    return `months must be a whole number from 1 to ${MAX_MONTHS}.`;
  }

  let purchaserEmail: string | null = null;
  if (body.purchaser_email !== undefined && body.purchaser_email !== null) {
    if (typeof body.purchaser_email !== 'string') return 'purchaser_email must be text.';
    const trimmed = body.purchaser_email.trim();
    if (trimmed.length > 0) {
      if (trimmed.length > 320 || !EMAIL_RE.test(trimmed)) {
        return 'purchaser_email is not a valid email address.';
      }
      purchaserEmail = trimmed;
    }
  }

  return { quantity, months, purchaserEmail };
}

async function handle(req: Request): Promise<Response> {
  if (req.method !== 'POST') return methodNotAllowed('POST', NO_CORS);

  // 1. Authenticate first.
  const secret = Deno.env.get('GIFT_CODE_SECRET');
  if (!secret) {
    console.error('issue-gift-code: GIFT_CODE_SECRET is not set; rejecting every call.');
  }
  const presented = req.headers.get('x-trellis-gift-secret');
  if (!(await secretsMatch(presented, secret))) {
    return errorResponse(401, 'unauthorized', 'Unauthorized.', NO_CORS);
  }

  // 2. Validate the payload.
  const parsed = await readJsonObject(req, { cors: false });
  if (!parsed.ok) return parsed.response;
  const request = parseBody(parsed.body);
  if (typeof request === 'string') {
    return errorResponse(400, 'invalid_request', request, NO_CORS);
  }

  // 3. Mint.
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    console.error('issue-gift-code: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing');
    return errorResponse(500, 'not_configured', 'Gift codes are not configured.', NO_CORS);
  }
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch: fetchWithDeadline(DB_TIMEOUT_MS) },
  });

  const { data, error } = await supabase.rpc('issue_gift_codes', {
    p_quantity: request.quantity,
    p_months: request.months,
    p_purchaser_email: request.purchaserEmail,
  });
  if (error) {
    console.error('issue-gift-code: issue_gift_codes failed:', describeError(error));
    return errorResponse(500, 'issue_failed', 'Could not issue gift codes. Please try again.', NO_CORS);
  }

  // A `returns setof text` function comes back as an array of strings.
  const codes = Array.isArray(data) ? data.filter((code): code is string => typeof code === 'string') : [];
  if (codes.length !== request.quantity) {
    console.error(`issue-gift-code: expected ${request.quantity} codes, got ${codes.length}`);
    return errorResponse(500, 'issue_failed', 'Could not issue gift codes. Please try again.', NO_CORS);
  }

  return jsonResponse(200, { codes, months: request.months }, NO_CORS);
}

Deno.serve(guarded(
  'issue-gift-code',
  handle,
  () => errorResponse(500, 'internal_error', 'Something went wrong on our side. Please try again.', NO_CORS),
));

// =============================================================================
// Deployment notes (not code — nothing below this line runs)
// =============================================================================
// 1. Apply supabase/migrations/029_membership_gate.sql first.
// 2. Set the shared secret (a long random string; give the same string to the
//    website's developer, to keep on the website's server only):
//      supabase secrets set GIFT_CODE_SECRET='<a long random string you invent>'
// 3. Deploy with JWT verification OFF (the website has no Supabase JWT; the
//    secret header above is the gate):
//      supabase functions deploy issue-gift-code --no-verify-jwt
// 4. Smoke test (expect 200 {"codes":["..."],"months":12}):
//      curl -X POST https://qonsiliimbkcjmcnhonb.supabase.co/functions/v1/issue-gift-code \
//        -H 'content-type: application/json' -H 'x-trellis-gift-secret: <secret>' \
//        -d '{"quantity":1,"months":12,"purchaser_email":"you@example.com"}'
//    (That mints a real, redeemable code.)
// =============================================================================
