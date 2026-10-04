// The small themed page shown in the browser after the calendar OAuth round
// trip (success or error). Parchment background, forest-green text, antique
// brass accents — same palette as the app.
//
// IMPORTANT: Supabase rewrites text/html GET responses to text/plain on the
// default <project>.supabase.co domain (anti-phishing). On that domain the
// callback therefore redirects to CALENDAR_RESULT_REDIRECT_URL when set (host
// result.html from the calendar-oauth-callback folder anywhere static), and
// this inline page is what renders only on a custom domain. See
// supabase/CALENDAR_SETUP.md.

export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/// `title` and `message` are HTML-escaped here; callers should still only ever
/// pass fixed strings — nothing taken from the request URL. `status` overrides
/// the HTTP status (default 200 when ok, 400 otherwise).
export function renderResultPage(
  opts: { ok: boolean; title: string; message: string; status?: number },
): Response {
  const title = escapeHtml(String(opts.title));
  const message = escapeHtml(String(opts.message));
  const mark = opts.ok ? '&#10003;' : '!';
  const markColor = opts.ok ? '#1E3A2B' : '#9E4B2F';

  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>${title} - The Trellis</title>
<style>
  html, body { margin: 0; padding: 0; background: #F9F6F0; color: #1E3A2B; }
  body { font-family: "EB Garamond", Garamond, Georgia, "Times New Roman", serif; min-height: 100vh;
         display: flex; align-items: center; justify-content: center; padding: 24px; box-sizing: border-box; }
  .plate { max-width: 420px; width: 100%; text-align: center; background: #F8F1E0; border: 1px solid #B8860B;
           border-radius: 20px; padding: 4px; box-shadow: 0 8px 18px rgba(30,58,43,0.18); }
  .inner { border: 1px solid rgba(184,134,11,0.6); border-radius: 16px; padding: 32px 24px; }
  .mark { width: 56px; height: 56px; line-height: 52px; margin: 0 auto 16px; border-radius: 50%;
          border: 2px solid #B8860B; font-size: 28px; color: ${markColor}; }
  h1 { font-size: 28px; font-weight: 600; margin: 0 0 12px; }
  p { font-size: 19px; line-height: 1.45; margin: 0; }
  .rule { height: 1px; background: #B8860B; opacity: 0.5; margin: 20px auto; width: 60%; }
  .foot { font-size: 16px; color: #B8860B; }
</style>
</head>
<body>
  <main class="plate"><div class="inner">
    <div class="mark" aria-hidden="true">${mark}</div>
    <h1>${title}</h1>
    <p>${message}</p>
    <div class="rule"></div>
    <p class="foot">You can close this window and return to The Trellis.</p>
  </div></main>
</body>
</html>`;

  return new Response(html, {
    status: opts.status ?? (opts.ok ? 200 : 400),
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store',
      'Referrer-Policy': 'no-referrer',
      'X-Content-Type-Options': 'nosniff',
      'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'",
    },
  });
}
