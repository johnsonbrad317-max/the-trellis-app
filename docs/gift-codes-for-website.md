# The Trellis gift codes: notes for the website developer

The website (unhinderedlives.com) sells gift memberships for The Trellis app. After a
successful checkout, the website's server asks The Trellis for one or more gift codes and
gives them to the buyer by showing them and emailing them. The recipient redeems the code
**on the website** (a redeem page you build, described below), against the email address of
their Trellis account. That gives them a Runner membership for the number of months bought
(12 by default). Witnesses use the app free, so codes are only for Runners.

**Codes are never typed into the app.** Apple's App Review Guideline 3.1.1 forbids an iPhone
app from unlocking paid features with its own codes or license keys. What Apple allows
(3.1.3(b)) is an account that already holds a membership bought on the web, so the
redemption has to happen on the website. The website may link to the App Store, but
nothing should ask people to type a code into the app.

## Issuing codes: endpoint

```
POST https://qonsiliimbkcjmcnhonb.supabase.co/functions/v1/issue-gift-code
```

**Call this from the server only.** The request carries a shared secret. Never call it from
browser JavaScript, never put the secret in a page, and never commit it to a repository. The
endpoint sends no CORS headers, so browsers will block it anyway.

## Headers

| Header                  | Value                                                        |
|-------------------------|--------------------------------------------------------------|
| `Content-Type`          | `application/json`                                           |
| `x-trellis-gift-secret` | The shared secret. The Trellis owner gives it to you privately. |

No Supabase key or `Authorization` header is needed.

## Body

```json
{
  "quantity": 1,
  "months": 12,
  "purchaser_email": "buyer@example.com"
}
```

| Field             | Type    | Required | Rules                                                              |
|-------------------|---------|----------|--------------------------------------------------------------------|
| `quantity`        | integer | no (1)   | 1 to 20 codes per call                                             |
| `months`          | integer | no (12)  | 1 to 120. Each code gives this many months.                        |
| `purchaser_email` | string  | no       | The buyer's email. It's stored with the codes so support can look them up later. Recommended. |

## Success response: `200`

```json
{
  "codes": ["7KQ3MX9ZPA"],
  "months": 12
}
```

- Each code has **10 characters** from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`. The letters I and O
  and the digits 0 and 1 are never used, so codes are easy to read.
- You can show a code as `7KQ3M-X9ZPA` to make it easier to read. Redemption ignores dashes,
  spaces and letter case when someone types it in.
- Each code works **once**. Its months are added on top of any gift time the person
  already has.
- Codes don't expire before they're redeemed.

## Errors

Every error looks like this: `{ "error": "<a sentence>", "code": "<machine code>" }`

| Status | `code`                                  | Meaning                                                         |
|--------|-----------------------------------------|-----------------------------------------------------------------|
| 400    | `invalid_json`                          | The body isn't a JSON object.                                   |
| 400    | `invalid_request`                       | A field breaks the rules above. `error` says which one.         |
| 401    | `unauthorized`                          | The secret header is missing or wrong.                          |
| 405    | `method_not_allowed`                    | The request wasn't a POST.                                      |
| 413    | `payload_too_large`                     | The body is over 16 KB.                                         |
| 500    | `not_configured` / `issue_failed` / `internal_error` | A problem on The Trellis side. No codes were issued. Retry later. |

**Retries:** a `200` means the codes exist. If the call times out, you can't tell whether
codes were issued. Retrying is safe because unused codes cost nothing, but give the buyer
only the codes from the call that succeeded. Keep the codes with the order on your side,
so you can resend the email.

## Example

```bash
curl -X POST https://qonsiliimbkcjmcnhonb.supabase.co/functions/v1/issue-gift-code \
  -H 'Content-Type: application/json' \
  -H 'x-trellis-gift-secret: <secret>' \
  -d '{"quantity":1,"months":12,"purchaser_email":"buyer@example.com"}'
```

Every successful call issues real codes that work, so don't test against the live endpoint
more than you need to.

## Redeeming a code: the redeem page

Build a page at **unhinderedlives.com/trellis/redeem** with two fields, **Gift code** and
**The email address you use for The Trellis**, and a **Redeem** button. The page posts to
your server; your server calls:

```
POST https://qonsiliimbkcjmcnhonb.supabase.co/functions/v1/redeem-gift-code
Content-Type: application/json
x-trellis-gift-secret: <the same shared secret>

{ "code": "7KQ3M-X9ZPA", "email": "runner@example.com" }
```

The code may include dashes, spaces or lowercase letters.

| Response | Show the person |
|----------|-----------------|
| `200 { "ok": true, "paid_until": "2027-10-07T…" }` | "Done. Your Trellis membership is active through October 7, 2027. Open the app; if it was waiting on you, tap **Check again**." |
| `200 { "ok": false, "reason": "not_recognized", "message": … }` | the `message` |
| `200 { "ok": false, "reason": "no_account", "message": … }` | the `message`. It tells them to create their account in the app first. The code is **not** used up. |
| `200 { "ok": false, "reason": "rate_limited", "message": … }` | the `message` (10 tries per email per hour) |
| `400` / `401` / `500` | "Something went wrong. Please try again." (same error format as above) |

The recipient needs a Trellis account before redeeming. The match is on the account's
email, ignoring letter case.

## Suggested email wording for the recipient

> You've been given a year of The Trellis. Download The Trellis from the App Store and
> create your account. Then go to **unhinderedlives.com/trellis/redeem**, enter
> **7KQ3M-X9ZPA** and the email address you signed up with. Your membership starts right
> away.

## Setup for The Trellis owner (not the website)

1. Apply `supabase/migrations/029_membership_gate.sql`, then
   `supabase/migrations/030_gift_codes_redeemed_on_web.sql`.
2. Set the secret. Use a long random string and give the same string to the website
   developer privately:
   `supabase secrets set GIFT_CODE_SECRET='<long random string>'`
3. Deploy both functions:
   `supabase functions deploy issue-gift-code --no-verify-jwt`
   `supabase functions deploy redeem-gift-code --no-verify-jwt`
