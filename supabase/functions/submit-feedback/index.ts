// The Trellis — submit-feedback
// =============================================================================
// Backs the "Tend the Trellis" feedback sheet (lib/widgets/feedback_dialog.dart).
// Receives a rating, a category and a note from a signed-in user, records it,
// and emails it to the support inbox via Resend (https://resend.com), which is
// the simplest way for an Edge Function to send mail from the unhinderedlives.com
// domain.
//
// What it guarantees:
//   * The note is SAVED FIRST (feedback_submissions, service-role only). If the
//     email provider is down, slow (10 s timeout), misconfigured, or rejects the
//     send, the feedback is not lost — the row records email_status = 'failed'
//     and why, and the user still gets their thank-you (the response says
//     delivered: false).
//   * The email carries no name, no email address and no account id. The sheet
//     promises "no personal details are attached", and this honors it. The one
//     exception is opt-in: if the user ticks "You may reply to me", their
//     account email (read server-side from their verified session, never from
//     the request body) becomes the Reply-To, so support can answer.
//   * Per-user throttle (5 per hour) so a stuck client or abuse can't flood
//     the inbox.
//   * All user text is HTML-escaped; subject lines are stripped of newlines
//     (no header injection).
//
// Contract with the app (lib/services/feedback_service.dart):
//   200 { ok: true, delivered: boolean }
//   4xx/5xx { error: "<sentence fit to show>", code: "<machine_code>" }
//     400 invalid_json | invalid_request      413 payload_too_large
//     401 unauthorized                        429 rate_limited
//     500 not_configured | feedback_table_missing | feedback_storage_denied |
//         feedback_storage_failed | internal_error
//     503 auth_unavailable
//
// Secrets (Dashboard -> Edge Functions -> submit-feedback -> Secrets, or
// `supabase secrets set ...`):
//   RESEND_API_KEY   API key from resend.com (the sending domain
//                    unhinderedlives.com must be verified in Resend)
//   FEEDBACK_TO      optional; defaults to support@unhinderedlives.com
//   FEEDBACK_FROM    optional; defaults to "The Trellis <feedback@unhinderedlives.com>"
//                    (must be an address on the verified domain)
// SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are injected
// automatically.
//
// Deploy (JWT verification stays ON — callers are signed-in app users):
//   supabase functions deploy submit-feedback
// =============================================================================

import { authenticate } from '../_shared/auth.ts';
import {
  describeError,
  discardBody,
  errorResponse,
  fetchWithTimeout,
  FetchTimeoutError,
  guarded,
  handlePreflight,
  isPlainObject,
  jsonResponse,
  methodNotAllowed,
  readJsonObject,
  readTextBody,
  redact,
} from '../_shared/http.ts';

const CATEGORY_LABELS: Record<string, string> = {
  bug: 'Bug',
  spiritual_flow_content: 'Spiritual Flow / Content',
  ui_usability: 'UI / Usability',
};

const MAX_MESSAGE_LENGTH = 4000;
const MAX_SUBMISSIONS_PER_HOUR = 5;
const DEFAULT_TO = 'support@unhinderedlives.com';
const DEFAULT_FROM = 'The Trellis <feedback@unhinderedlives.com>';
/// A 4000-character note can be ~12 KB of UTF-8 before JSON escaping, so the
/// 16 KB default would reject some legitimate notes.
const MAX_BODY_BYTES = 32 * 1024;
const RESEND_TIMEOUT_MS = 10_000;

function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

/// A single clean line: no control characters (header injection), bounded
/// length.
function oneLine(value: string, max = 80): string {
  // deno-lint-ignore no-control-regex
  return value.replace(/[\u0000-\u001f\u007f]+/g, ' ').trim().slice(0, max);
}

interface FeedbackBody {
  rating: number;
  category: string;
  message: string;
  replyOk: boolean;
  platform: string;
  role: string;
}

/// Validates the request body; returns an error string, or the cleaned value.
function parseBody(body: Record<string, unknown>): FeedbackBody | string {
  const rating = body.rating;
  if (typeof rating !== 'number' || !Number.isInteger(rating) || rating < 1 || rating > 5) {
    return 'rating must be an integer from 1 to 5.';
  }

  const category = body.category;
  // Object.hasOwn, not `in`: "constructor"/"toString" are not categories.
  if (typeof category !== 'string' || !Object.hasOwn(CATEGORY_LABELS, category)) {
    return 'category is not recognized.';
  }

  if (typeof body.message !== 'string') return 'message is required.';
  const message = body.message.trim();
  if (message.length === 0) return 'message is required.';
  if (message.length > MAX_MESSAGE_LENGTH) {
    return `message must be ${MAX_MESSAGE_LENGTH} characters or fewer.`;
  }

  if (body.reply_ok !== undefined && body.reply_ok !== null && typeof body.reply_ok !== 'boolean') {
    return 'reply_ok must be true or false.';
  }
  for (const field of ['platform', 'role']) {
    const value = body[field];
    if (value !== undefined && value !== null && typeof value !== 'string') {
      return `${field} must be text.`;
    }
  }

  return {
    rating,
    category,
    message,
    replyOk: body.reply_ok === true,
    platform: (typeof body.platform === 'string' ? oneLine(body.platform, 24) : '') || 'unknown',
    role: (typeof body.role === 'string' ? oneLine(body.role, 24) : '') || 'unknown',
  };
}

function buildEmail(args: {
  id: string;
  body: FeedbackBody;
  receivedAt: string;
  replyTo: string | null;
}): { subject: string; text: string; html: string } {
  const { id, body, receivedAt, replyTo } = args;
  const categoryLabel = CATEGORY_LABELS[body.category];
  const stars = '★'.repeat(body.rating) + '☆'.repeat(5 - body.rating);
  const subject = oneLine(`[Trellis feedback] ${categoryLabel} · ${body.rating}/5`, 120);

  const text = [
    `Rating:    ${stars} (${body.rating}/5)`,
    `Category:  ${categoryLabel}`,
    `Viewing as: ${body.role}   Platform: ${body.platform}`,
    `Received:  ${receivedAt}`,
    `Reply OK:  ${replyTo ? 'yes — reply to this email' : 'no (anonymous)'}`,
    `Reference: ${id}`,
    '',
    body.message,
  ].join('\n');

  const html = `<!doctype html><html><body style="margin:0;padding:24px;background:#F9F6F0;">
<div style="max-width:560px;margin:0 auto;background:#F8F1E0;border:1px solid #B8860B;border-radius:12px;padding:24px;font-family:Georgia,'EB Garamond',serif;color:#1E3A2B;">
  <h2 style="margin:0 0 4px 0;font-weight:600;">Tend the Trellis</h2>
  <p style="margin:0 0 16px 0;color:#B8860B;">${escapeHtml(categoryLabel)} · ${escapeHtml(stars)} (${body.rating}/5)</p>
  <p style="white-space:pre-wrap;line-height:1.5;margin:0 0 20px 0;">${escapeHtml(body.message)}</p>
  <hr style="border:none;border-top:1px solid #B8860B33;margin:16px 0;">
  <p style="font-size:13px;margin:0;color:#5B6E62;">
    Viewing as ${escapeHtml(body.role)} · ${escapeHtml(body.platform)} · ${escapeHtml(receivedAt)}<br>
    ${replyTo ? 'The sender allowed a reply — just reply to this email.' : 'Anonymous: no reply address was shared.'}<br>
    Reference ${escapeHtml(id)}
  </p>
</div></body></html>`;

  return { subject, text, html };
}

/// A database failure while recording feedback. The user always sees the same
/// calm sentence; the real cause goes to the function logs, and a short
/// machine-readable `code` rides along so a setup problem is recognisable at a
/// glance (Dashboard -> Edge Functions -> submit-feedback -> Logs).
///   feedback_table_missing   migration 016 hasn't been run
///   feedback_storage_denied  the service role lacks privileges on the table
///                            (run migration 018 / grant ... to service_role)
///   feedback_storage_failed  anything else — see the logged message
function storageFailure(
  step: string,
  error: { message?: string; code?: string; details?: string; hint?: string } | null,
): Response {
  const pgCode = typeof error?.code === 'string' ? error.code : '';
  console.error(
    `submit-feedback: ${step} failed [${pgCode || 'no code'}]:`,
    redact(String(error?.message ?? 'unknown error')),
    redact(String(error?.hint ?? '')),
  );

  // 42P01 = undefined_table; PGRST205/PGRST106 = not in the API schema cache.
  const code = ['42P01', 'PGRST205', 'PGRST106'].includes(pgCode)
    ? 'feedback_table_missing'
    : pgCode === '42501'
    ? 'feedback_storage_denied'
    : 'feedback_storage_failed';

  return errorResponse(500, code, 'Could not record feedback right now.');
}

/// Sends the email. Never throws: returns null on success, or a short reason
/// (safe to store and log — no addresses, no API key) on any failure,
/// including a timeout.
async function sendEmail(
  resendKey: string,
  email: { subject: string; text: string; html: string },
  replyTo: string | null,
): Promise<string | null> {
  try {
    const response = await fetchWithTimeout('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${resendKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: Deno.env.get('FEEDBACK_FROM') || DEFAULT_FROM,
        to: [Deno.env.get('FEEDBACK_TO') || DEFAULT_TO],
        reply_to: replyTo ?? undefined,
        subject: email.subject,
        text: email.text,
        html: email.html,
      }),
    }, RESEND_TIMEOUT_MS, 'Resend');

    if (response.ok) {
      await discardBody(response);
      return null;
    }
    // Resend's error body is a short JSON { name, message }. Keep a redacted
    // excerpt: it is what tells "domain not verified" from "bad API key".
    const detail = redact(await readTextBody(response, 300)).replace(/\s+/g, ' ').trim();
    return `Resend ${response.status}${detail ? `: ${detail}` : ''}`.slice(0, 300);
  } catch (error) {
    return error instanceof FetchTimeoutError
      ? `Resend request timed out after ${RESEND_TIMEOUT_MS / 1000}s`
      : 'Resend request failed (network error)';
  }
}

async function handle(req: Request): Promise<Response> {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== 'POST') return methodNotAllowed('POST, OPTIONS');

  // Who is asking — from their own verified session, never from the body.
  const caller = await authenticate(req);
  if (caller instanceof Response) return caller;
  const { userId, email: accountEmail, admin } = caller;

  const read = await readJsonObject(req, { maxBytes: MAX_BODY_BYTES });
  if (!read.ok) return read.response;
  const parsed = parseBody(read.body);
  if (typeof parsed === 'string') return errorResponse(400, 'invalid_request', parsed);
  const body = parsed;

  // Throttle: a handful per hour per person. (Counted in the database, so it
  // holds across function instances.)
  const hourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { count, error: countError } = await admin
    .from('feedback_submissions')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId)
    .gte('created_at', hourAgo);
  if (countError) {
    return storageFailure('feedback throttle check', countError);
  }
  if ((count ?? 0) >= MAX_SUBMISSIONS_PER_HOUR) {
    return errorResponse(429, 'rate_limited', 'Too many submissions — please try again in a little while.');
  }

  // 1) Save first, so nothing is ever lost to an email problem.
  const replyTo = body.replyOk && accountEmail ? accountEmail : null;
  const { data: saved, error: saveError } = await admin
    .from('feedback_submissions')
    .insert({
      user_id: userId,
      rating: body.rating,
      category: body.category,
      message: body.message,
      reply_ok: replyTo !== null,
      platform: body.platform,
      role_view: body.role,
    })
    .select('id, created_at')
    .single();
  if (saveError || !isPlainObject(saved) || typeof saved.id !== 'string') {
    return storageFailure('feedback save', saveError);
  }

  // 2) Email it. From here on the user gets ok: true whatever happens — the
  //    note is safely stored.
  let failure: string | null;
  try {
    const resendKey = Deno.env.get('RESEND_API_KEY');
    if (!resendKey) {
      failure = 'RESEND_API_KEY is not configured';
    } else {
      const email = buildEmail({
        id: saved.id,
        body,
        receivedAt: typeof saved.created_at === 'string' ? saved.created_at : new Date().toISOString(),
        replyTo,
      });
      failure = await sendEmail(resendKey, email, replyTo);
    }
  } catch (error) {
    failure = `Email step failed: ${describeError(error)}`;
  }
  const delivered = failure === null;
  if (!delivered) console.error('submit-feedback: feedback email not sent:', failure);

  try {
    const { error: statusError } = await admin
      .from('feedback_submissions')
      .update({ email_status: delivered ? 'sent' : 'failed', email_error: failure })
      .eq('id', saved.id);
    if (statusError) {
      console.error('submit-feedback: could not record email status:', describeError(statusError));
    }
  } catch (error) {
    console.error('submit-feedback: could not record email status:', describeError(error));
  }

  // The feedback is safely stored either way; `delivered` says whether the
  // email went out so the client (or a dashboard) can tell the difference.
  return jsonResponse(200, { ok: true, delivered });
}

Deno.serve(guarded('submit-feedback', handle));
