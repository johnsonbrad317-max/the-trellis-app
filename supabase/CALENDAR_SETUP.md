# Calendar availability — owner setup

Runners and Witnesses can connect Google Calendar, Outlook or Apple (iCloud)
Calendar. When one of them proposes a meeting, The Trellis suggests times when
**both** people are free — and neither person ever sees the other's busy blocks
or event details.

It uses [Cronofy](https://www.cronofy.com/) as one unified calendar API for all
three providers, asking only for the `read_free_busy` scope (never event
contents). The busy intervals of each person are fetched separately, intersected
inside our own Edge Function, and only the **shared open windows** are returned
to the app.

```
App ──calendar-connect-start──▶ signed authorize URL ──▶ browser ──▶ Cronofy / Google / Microsoft / Apple
                                                                          │
App ◀── (resume, reload) ◀── result page ◀── calendar-oauth-callback ◀────┘  (code + signed state)
                                                   │ tokens → Supabase Vault (service-role only)
App ──calendar-availability──▶ pairing check → free/busy for BOTH → intersect → {suggestions}
App ──calendar-disconnect────▶ revoke at Cronofy + delete tokens
```

## What you need to do (once)

### 1. Create a Cronofy developer app

1. Sign up at <https://app.cronofy.com/> (choose the data center that matches
   your users — see `CRONOFY_DATA_CENTER` below) and create an **application**
   in the developer dashboard.
2. **Scopes:** enable `read_free_busy` (nothing else is needed or requested).
3. **Redirect URI:** register exactly
   `https://qonsiliimbkcjmcnhonb.supabase.co/functions/v1/calendar-oauth-callback`
   (your project ref is in `lib/services/supabase_client.dart`). Cronofy rejects
   authorisations whose `redirect_uri` is not pre-registered.
4. Note the **Client ID** and **Client Secret**.
5. Check which providers your plan enables (Google / Microsoft / Apple). Use a
   test account on each provider before launch.

### 2. Set the Edge Function secrets

Placeholders only — put the real values in yourself; never commit them.

```bash
supabase secrets set CRONOFY_CLIENT_ID='<from Cronofy>'
supabase secrets set CRONOFY_CLIENT_SECRET='<from Cronofy>'
supabase secrets set CRONOFY_DATA_CENTER='us'      # us (default) | de | uk | au | ca | sg
supabase secrets set CALENDAR_OAUTH_REDIRECT_URI='https://qonsiliimbkcjmcnhonb.supabase.co/functions/v1/calendar-oauth-callback'
supabase secrets set CALENDAR_STATE_SECRET="$(openssl rand -hex 32)"   # signs the OAuth state; any long random string
# Optional, but see "The result page" below:
supabase secrets set CALENDAR_RESULT_REDIRECT_URL='https://<where-you-host>/calendar-result.html'
```

| Secret | Used by | Notes |
| --- | --- | --- |
| `CRONOFY_CLIENT_ID` | start, callback, disconnect, availability | From the Cronofy app. |
| `CRONOFY_CLIENT_SECRET` | callback, disconnect, availability | From the Cronofy app. |
| `CRONOFY_DATA_CENTER` | all | Picks `api-<dc>.cronofy.com` / `app-<dc>.cronofy.com`. Default `us`. |
| `CALENDAR_OAUTH_REDIRECT_URI` | start, callback | Must equal the URI registered at Cronofy. |
| `CALENDAR_STATE_SECRET` | start, callback | HMAC key for the OAuth `state`. |
| `CALENDAR_RESULT_REDIRECT_URL` | callback | Optional: https URL of the hosted result page. |

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are injected
automatically.

### 3. Run the migration

Run `supabase/migrations/017_calendar_availability.sql` in the SQL editor (or
`supabase db push`). It is idempotent. It needs Supabase **Vault** (on by
default; migration 011 already uses it). The verification queries are at the
bottom of the file.

### 4. Deploy the four functions

Only the OAuth callback is deployed with JWT verification **off** — it is hit by
a browser redirect that carries no JWT, and authenticates itself with the signed
state + single-use nonce. The other three keep the default (JWT verified).

```bash
supabase functions deploy calendar-connect-start
supabase functions deploy calendar-disconnect
supabase functions deploy calendar-availability
supabase functions deploy calendar-oauth-callback --no-verify-jwt
```

(There is no `config.toml` in this repo, so the flag on the command line is what
controls it. Re-use it on every redeploy of the callback.)

### 5. The result page (important)

After approving, the browser lands on the callback, which should show a small
parchment/forest/brass "Calendar connected" page. **Supabase rewrites HTML
responses from the default `*.supabase.co` domain to plain text** (an
anti-phishing measure), so on the default domain the page would show as raw
source. Pick one:

- **Host the static page (recommended, free).** Upload
  `supabase/functions/calendar-oauth-callback/result.html` anywhere static and
  https (e.g. Firebase Hosting — `firebase.json` is already in the repo — or your
  marketing site) and set `CALENDAR_RESULT_REDIRECT_URL` to its URL. The callback
  then 302-redirects to it with `?status=connected|error&provider=…`. The page
  only ever displays fixed strings.
- **Custom domain on Supabase (paid).** With a custom domain the callback's own
  inline HTML renders properly; leave `CALENDAR_RESULT_REDIRECT_URL` unset.

Either way, the app refreshes its calendar list automatically when the user
returns to it.

## Testing with curl

Get a user JWT for a test account (this is the test user's own session; use test
accounts only):

```bash
# 1. Start a connection (replace the placeholders)
curl -s -X POST "https://<project-ref>.supabase.co/functions/v1/calendar-connect-start" \
  -H "Authorization: Bearer <user access token>" \
  -H "apikey: <publishable key>" \
  -H "Content-Type: application/json" \
  -d '{"provider":"google"}'
# -> {"authorize_url":"https://app.cronofy.com/oauth/authorize?...&state=<nonce>.<sig>"}
# Open that URL in a browser, approve, and you should land on the result page.

# 2. Check availability with a paired partner (both must be connected)
curl -s -X POST "https://<project-ref>.supabase.co/functions/v1/calendar-availability" \
  -H "Authorization: Bearer <user access token>" -H "apikey: <publishable key>" \
  -H "Content-Type: application/json" \
  -d '{"other_user_id":"<partner uuid>","from":"2026-10-12T00:00:00Z","to":"2026-10-26T00:00:00Z","duration_minutes":60,"tz_offset_minutes":-300}'
# -> {"suggestions":[{"start":"...","end":"..."}],"both_connected":true,"me_connected":true,"other_connected":true}

# 3. Disconnect
curl -s -X POST "https://<project-ref>.supabase.co/functions/v1/calendar-disconnect" \
  -H "Authorization: Bearer <user access token>" -H "apikey: <publishable key>" \
  -H "Content-Type: application/json" -d '{"provider":"google"}'
# -> {"disconnected":true}
```

Expected failures worth trying: `other_user_id` of someone you are not paired
with → `403`; a forged callback (`...?code=x&state=bad`) → an error page, no
database change; replaying a used callback URL → error page.

Function logs: Dashboard → Edge Functions → *name* → Logs. Logs contain only
error classes and HTTP status codes — never tokens, codes, busy blocks or
provider names.

## Apple Calendar and the app-specific password

Apple has no OAuth for iCloud Calendar. Cronofy hosts a link flow that asks the
user for their Apple ID **and an app-specific password**. Tell users:

> Apple Calendar uses an app-specific password — a one-off password that only
> works for calendar access. Create one at <https://appleid.apple.com> → Sign-In
> and Security → App-Specific Passwords, name it "The Trellis", and paste it into
> the Cronofy page that opens. Your normal Apple ID password is never used.
> Revoke it there at any time.

(The in-app sheet shows a short version of this under the Apple Calendar plate.
Apple requires two-factor authentication to be on to create such passwords.)

## Privacy statement (for the privacy policy / App Store notes)

- The Trellis requests **free/busy access only** (`read_free_busy`). It never
  asks for event titles, attendees, locations or descriptions.
- Your partner sees **only times you both have open** — never your busy blocks,
  and never which calendar service you use. The app can tell your partner whether
  you have connected a calendar at all (so it can explain why no times are
  shown).
- Calendar access tokens are stored encrypted in Supabase Vault, in a place the
  app itself cannot read; only the server-side functions can use them.
- Disconnecting a calendar revokes access at the calendar service (best effort)
  and deletes the stored tokens immediately. Deleting your account removes them
  too.
- A person's calendar is only ever consulted for someone they are in an active
  Runner–Witness pairing with.

## Assumptions to verify

I could not run the TypeScript (no Deno available) or call Cronofy from here. The
Cronofy details below came from reading Cronofy's public docs; everything that
depends on them lives in **one module**, `supabase/functions/_shared/cronofy.ts`,
so any correction is a one-line change there. Please check each:

1. **Provider names.** Used: Google → `google`, Outlook → `office365`,
   Apple → `apple` (`PROVIDER_NAME` in `cronofy.ts`). Personal outlook.com /
   hotmail accounts may need `live_connect` instead (or delete the entry to let
   Cronofy show its own chooser).
2. **Scope `read_free_busy` in the standard access mode.** Cronofy documents
   `read_free_busy` as limiting *our API access* to free/busy requests. But the
   consent screen shown by Google/Microsoft in the standard mode may still ask
   for broader calendar-read permission on Cronofy's behalf. Look at the real
   consent screens. If that wording is unacceptable, Cronofy also offers a
   dedicated **Free/Busy access mode** (dashboard feature toggle; providers
   `google_free_busy` and `ms_graph_free_busy`; Google and Microsoft only, **not
   Apple**; documented as using the `free_busy_write` scope and an `access_mode`
   parameter). Adopting it means changing `SCOPE`/`PROVIDER_NAME` and adding
   the parameter in `buildAuthorizeUrl`.
3. **`avoid_linking=true`** is sent so each provider becomes its own Cronofy
   account (disconnecting one never touches another). Confirm that is what that
   flag does for your app; remove it if it causes errors.
4. **Token response** carries `access_token`, `refresh_token`, `expires_in`, and
   `sub` (falling back to `account_id`); Cronofy rotates refresh tokens on
   refresh and the new one is always stored.
5. **Auth style.** The token and revoke endpoints are called with a **JSON** body
   (`client_id`, `client_secret`, …); `GET /v1/free_busy` with
   `Authorization: Bearer <access token>`. Revoke uses `{token}` (the refresh
   token).
6. **Free/busy shape.** `GET {api}/v1/free_busy?tzid=Etc/UTC&from=…&to=…` returns
   `free_busy: [{start, end, free_busy_status}]` plus `pages.next_page` (a full
   URL). Times are ISO 8601 UTC; **all-day** events are bare dates and are read as
   local midnight in the caller's offset. Entries marked `free` are ignored;
   `busy`, `tentative` and `unknown` all count as busy. Pagination is followed
   only to Cronofy's own host, up to 10 pages.
7. **HTTP status meaning.** 400/401/403 from the token endpoints and 401 from
   free/busy mean "re-authorise" (the connection becomes `needs_reauth`); network
   errors, 5xx and 429 are treated as temporary and make `calendar-availability`
   answer 503 rather than suggest times from an incomplete picture.
8. **Supabase result page** behaviour described above (HTML served as text on the
   default domain) is from Supabase's documented limits; test it once.
9. **Time zones.** The app sends its UTC offset in minutes (taken at the start of
   the window); a daylight-saving change inside the 14-day window can shift
   suggestions by an hour at the far end. `tzid` is also accepted and is
   daylight-saving aware, but the app does not send one (Flutter has no IANA id
   without an extra package).
10. **Suggestion policy** (not from any spec, easy to change): window =
    the next 14 days starting 48 hours out (2 hours for an emergency), 08:00–20:00
    in the proposer's time zone, at most 3 windows per day, each start rounded up to
    a quarter hour, duration 60 minutes (45 for a Witness's coffee).
11. **Vault.** `vault.create_secret`, `vault.update_secret` and
    `vault.decrypted_secrets` are used as in Supabase's current Vault API.
12. **No rate limiting** is implemented on `calendar-availability`; each call makes
    one Cronofy request per connected calendar of both people.

---

## Changes from the 1.0 pre-release audit

These supersede anything above that disagrees.

- **Deploy with the CLI, not the Dashboard editor.** Every function now imports
  shared code from `supabase/functions/_shared/`; pasting a single `index.ts`
  into the Dashboard will not work.
- **Run migration `019_release_audit_hardening.sql`** as well as 017. It gives
  the service role explicit table/function privileges (without them
  `calendar-availability` answers `pairing_check_failed`) and makes the Vault
  cleanup trigger unable to block an account deletion.
- **Cancelled connections.** If the person cancels on the provider's consent
  screen, the callback redirects with `status=cancelled` (in addition to
  `connected` and `error`). Re-upload `calendar-oauth-callback/result.html`
  wherever you host it to get the matching message; an old copy still works.
- **Free/busy requests** now send `from`/`to` to Cronofy as whole UTC dates
  (not millisecond timestamps). Unverified against the live API — confirm with
  one real connect + availability call on the dev project.
- **Never partial answers.** More than 10 pages of free/busy, an unreadable
  busy time, or a provider timeout (10 s per request, 20 s overall) now returns
  HTTP 503 with a `code` (`calendar_provider_timeout` / `calendar_unavailable`)
  instead of suggestions built from incomplete data. The app then falls back to
  manual date/time entry.
- **Missing secrets** return 503 `not_configured` (the app shows "not available
  right now") rather than an error page.
- **Account deletion revokes calendar access** at Cronofy (best effort, capped
  at a few seconds) before the stored tokens are deleted, so no grant is left
  live after the account is gone.
- **Known limits, accepted for 1.0:** no rate limit on `calendar-availability`
  (a paired partner could infer busy times by many narrow queries — a correct
  limiter needs a small table + RPC); the app sends a UTC offset rather than an
  IANA time zone, so suggestions more than a few days out can be an hour off
  across a daylight-saving change.
