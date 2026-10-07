# The Trellis gift codes: notes for the website developer

The website (unhinderedlives.com) sells gift memberships for The Trellis app. After a
successful checkout, the website's server asks The Trellis for one or more gift codes and
gives them to the buyer by showing them and emailing them. The recipient types a code into
the app, which gives them a Runner membership for the number of months bought (12 by
default). Witnesses use the app free, so codes are only for Runners.

## Endpoint

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
- You can show a code as `7KQ3M-X9ZPA` to make it easier to read. The app ignores dashes,
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

## Suggested email wording for the recipient

> You've been given a year of The Trellis. Open the app, then go to **Menu → Account &
> Membership → Have a gift code?** and enter **7KQ3M-X9ZPA**. If your two free weeks
> are already over, the app shows a page with **Enter a gift code** on it.

## How a code is redeemed in the app (for reference)

1. Someone signed in to The Trellis enters the code in either of two places:
   - **Account & Membership → Have a gift code?** This works at any time.
   - The **"Your two free weeks are over"** page, which a Runner sees once their trial ends.
2. The app calls the database function `redeem_gift_code`. It ignores case, spaces and
   dashes, uses up the code, adds the months to the account and marks the membership
   active.
3. Each account gets 10 redemption attempts per hour. A code that's wrong or already used
   shows the message "That code wasn't recognized or has already been used."

## Setup for The Trellis owner (not the website)

1. Apply `supabase/migrations/029_membership_gate.sql`.
2. Set the secret. Use a long random string and give the same string to the website
   developer privately:
   `supabase secrets set GIFT_CODE_SECRET='<long random string>'`
3. Deploy: `supabase functions deploy issue-gift-code --no-verify-jwt`
