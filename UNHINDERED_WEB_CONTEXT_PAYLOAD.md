# Context Payload — Unhindered LLC Web Portal (unhinderedlives.com)

Paste this whole document as the first message in a fresh chat to build the
Next.js site. It contains everything that chat needs to know about the
existing Supabase backend and Flutter app it has to interoperate with —
nothing here has been built yet on the web side; this is the spec.

## 0. What this is

**Unhindered LLC** is the parent company. **The Trellis** is its first
product: a Flutter mobile app (iOS/Android) for personal spiritual
accountability — a Runner tracks a "Rule of Life" (daily/weekly/monthly
rhythms), paired with a Witness who receives push notifications when
something's missed. Churches can buy memberships in bulk for their
congregation via an enterprise code system (already built server-side, not
yet exposed on the web — see §2).

This new site, at **unhinderedlives.com**, is the company's web presence:
marketing, legal pages, and — the actual functional requirement — a B2B
portal where a church can pay to purchase a block of Trellis memberships
for its congregation.

**Action item, not yet resolved**: the Flutter app already ships with two
hardcoded URLs — `https://thetrellis.app/terms` and
`https://thetrellis.app/privacy` (in `lib/widgets/settings_drawer.dart`).
Decide in this new project whether `thetrellis.app` becomes an alias/
redirect to pages on `unhinderedlives.com`, or whether those two Flutter
constants get updated to point at `unhinderedlives.com/trellis/...` and the
app gets rebuilt. Apple requires the Privacy Policy URL entered in App
Store Connect to actually resolve — this has to be settled before
submission either way.

---

## 1. Design tokens — "Parchment & Botanic"

Source of truth: `lib/theme/app_colors.dart` and `lib/theme/app_theme.dart`
in the Flutter repo. Reproduced exactly, not approximated:

```css
:root {
  --forest-green: #1E3A2B;   /* primary — text, buttons, icons */
  --antique-brass: #B8860B;  /* secondary/accent — links, highlights, badges */
  --parchment-light: #F4ECD8; /* page background (top of gradient) */
  --parchment-dark: #E9DFC2;  /* page background (bottom of gradient) */
  --vellum: #F8F1E0;          /* card/surface background */
  --vellum-border: rgba(30, 58, 43, 0.15); /* #1E3A2B at 15% alpha */
}
```

- **Background**: a subtle top-to-bottom linear gradient, `parchment-light`
  → `parchment-dark`. Never a flat color.
- **Typography**: **EB Garamond** for everything — headings through body
  text and labels. It's loaded via Google Fonts in the app
  (`google_fonts` package); use the same family from Google Fonts on the
  web (`https://fonts.google.com/specimen/EB+Garamond`). Body text color
  is `forest-green`, not black.
- **Cards**: `vellum` background at ~85% opacity, 16px border radius,
  1px `vellum-border` border, no elevation/shadow — flat, not skeuomorphic.
- **Buttons**: solid `forest-green` fill, `parchment-light` text, 12px
  border radius, generous padding (24px horizontal / 14px vertical).
  Secondary/text actions use `antique-brass` as the text color, no fill.
- **Aesthetic**: minimalist, "friction-removal" — generous whitespace, no
  decorative chrome, no drop shadows, no gradients-as-decoration beyond the
  one background gradient. Every screen in the app reads as calm and
  uncluttered by design; the web portal should match that register rather
  than defaulting to a typical SaaS-dashboard density.

---

## 2. Supabase schema & RPCs the portal needs

**Project URL**: `https://qonsiliimbkcjmcnhonb.supabase.co`

**Critical security boundary**: the Flutter app only ever uses the
*publishable* (anon) key client-side — safe to embed, since RLS is the
real gate. The web portal is different: fulfilling a Stripe purchase means
calling `generate_enterprise_church_code`, which requires being a
church's Cloud admin (or bypassing that check entirely via the
service-role key from a trusted server context). **The Supabase
service-role key must only ever be used in a Next.js server action / API
route / webhook handler — never sent to the browser, never in a
`NEXT_PUBLIC_*` env var.** This mirrors how every privileged write in the
Flutter app's backend works (see the Edge Functions in
`supabase/functions/` — `delete-account`, `push-notification-engine` —
all service-role-only, called from environments the client can't inspect).

### `public.profiles` (relevant columns only)

```sql
create table public.profiles (
  id                    uuid primary key references auth.users (id) on delete cascade,
  name                  text not null,
  email                 text not null,
  role                  public.user_role not null default 'runner', -- 'runner' | 'witness'
  membership_status     public.membership_status not null default 'trial', -- 'trial' | 'active' | 'cancelled'
  church_id             uuid references public.churches (id) on delete set null,
  cloud_admin_church_id uuid references public.churches (id) on delete set null,
  phone_number          text,
  fcm_token             text,
  created_at            timestamptz not null default now()
  -- (additional columns exist for app-internal settings; omitted — not
  -- relevant to the web portal)
);
```

- `cloud_admin_church_id` is what makes an account a "Cloud admin" for a
  given church — the only account type authorized to call
  `generate_enterprise_church_code` for that church (see below). It's set
  by redeeming a `cloud_access_code` (a separate, pre-existing system for
  granting in-app admin dashboard access — not the same thing as the
  enterprise membership codes this portal sells).
- `membership_status` is what an enterprise code redemption flips to
  `'active'` for an individual Runner — see §2's RPC.

### `public.churches`

```sql
create table public.churches (
  id                  uuid primary key default gen_random_uuid(),
  name                text not null,
  rate_per_runner     numeric(10, 2) not null default 15.00,
  license_cap         integer not null default 50,
  annual_renewal_date date not null default (current_date + interval '1 year')::date,
  created_at          timestamptz not null default now()
);
```

A church has to exist as a row here before any codes can be generated for
it. Today, church creation itself is a manual/out-of-band step (direct SQL
by the app owner) — **this web portal, if it lets a church sign up and pay
without a human provisioning them first, will need its own flow to create
this row**, most likely inside the same server action that handles a
successful Stripe payment.

### `public.enterprise_church_codes` + RPCs (migration `005`)

This is the actual mechanism the portal needs to drive. Full source:

```sql
create table public.enterprise_church_codes (
  id                uuid primary key default gen_random_uuid(),
  church_id         uuid not null references public.churches (id) on delete cascade,
  code              text not null unique,
  max_redemptions   integer,          -- null = unlimited
  redemption_count  integer not null default 0,
  expires_at        timestamptz,
  created_at        timestamptz not null default now()
);

create table public.enterprise_church_code_redemptions (
  id           uuid primary key default gen_random_uuid(),
  code_id      uuid not null references public.enterprise_church_codes (id) on delete cascade,
  runner_id    uuid not null references public.profiles (id) on delete cascade,
  redeemed_at  timestamptz not null default now(),
  unique (code_id, runner_id)
);
```

Both tables have **zero RLS policies** (RLS enabled, nothing granted) —
reachable only through these two `security definer` RPCs:

```sql
-- Mints a new code. Only callable by that church's Cloud admin
-- (cloud_admin_church_id must match p_church_id) — so from the portal,
-- this has to be called either (a) by an authenticated Supabase session
-- that's already a Cloud admin for that church, or (b) via the
-- service-role key from your fulfillment webhook, bypassing the admin
-- check entirely (the more likely path for a self-serve Stripe purchase
-- where the buyer may not have a Trellis account yet at all).
generate_enterprise_church_code(
  p_church_id uuid,
  p_max_redemptions integer default null,  -- pass the quantity purchased
  p_expires_at timestamptz default null
) returns text  -- the generated code, e.g. "F3A9C1B2D4"

-- Redeems a code — called from inside the Flutter app by an individual
-- Runner, not from the web portal. Included here so you understand the
-- full loop the portal is kicking off.
redeem_enterprise_church_code(p_code text) returns boolean
```

**The whole B2B loop, end to end**: church pays on the web portal → portal
calls `generate_enterprise_church_code` (service-role, quantity →
`p_max_redemptions`) → portal displays/emails the resulting code to the
church admin → church distributes it to congregation members → each
member enters it in the Flutter app (Account & Membership → "Have a Church
Code?") → `redeem_enterprise_church_code` flips their `membership_status`
to `'active'`, no Apple/Google IAP involved.

**App Store compliance note, carried over from the Trellis side**: this
pattern is only defensible under Apple Guideline 3.1.3 because the
membership is tied to a real purchase made *outside* the iOS app, by an
organization (the church), not sold to individual consumers as an IAP
bypass. Keep that framing intact on the portal's own marketing/checkout
copy (i.e., sell "memberships for your congregation," not "skip the app's
subscription").

---

## 3. Stripe B2B checkout — requirements (not yet built anywhere)

This is a spec for the new chat to implement, not existing code.

**Product**: a church purchases a block of N Trellis memberships,
priced... (rate is currently `churches.rate_per_runner`, defaulting to
$15/seat/year in the schema — confirm whether the portal charges that
same per-seat annual rate, a flat B2B rate, or something else entirely;
not yet decided).

**Required flow**:
1. Church admin lands on a pricing/purchase page, selects a quantity (or a
   tiered package).
2. Stripe Checkout (hosted, not a custom card form — simplest PCI posture
   and matches "friction-removal") for the payment.
3. On successful payment (Stripe webhook, `checkout.session.completed` —
   **never** trust the client-side redirect alone to trigger fulfillment):
   - Look up or create the `churches` row for this buyer (needs a name at
     minimum — collect it in Checkout via `custom_fields` or a pre-checkout
     form).
   - Call `generate_enterprise_church_code` with the service-role key,
     `p_max_redemptions` = quantity purchased, a sensible `p_expires_at`
     (open question: does a code expire, or stay valid for the life of the
     church's relationship with Trellis? Nothing in the existing schema
     assumes either answer).
   - Surface the resulting code back to the buyer — on the success page,
     and via email (needs a transactional email provider; none exists yet
     anywhere in this stack).
4. Idempotency: Stripe can retry webhook delivery — guard against minting
   two codes for one payment (check the Stripe event id against something
   persisted, or make the "does a code already exist for this
   `checkout.session.id`" check before calling the RPC).

**Explicitly not decided yet, needs resolving in the new chat**: does a
purchasing church admin need their own login on this portal (Supabase
Auth? a separate simpler auth system? none at all, just email + Stripe
receipt)? Nothing in the existing backend assumes a "church admin web
user" identity distinct from an in-app Cloud admin — this is new surface
area, not a re-use of anything that exists today.

---

## 4. Apple App Review compliance — required pages

Non-negotiable for App Store submission; App Store Connect requires a
working URL for each:

- **Privacy Policy** — must actually describe what's collected: account
  info (name, email, phone optional), Rule of Life / check-in data,
  location (used only for Cloud/church-proximity features, see
  `NSLocationWhenInUseUsageDescription` in the app's `Info.plist`),
  calendar access (meeting scheduling), push notification tokens, and
  Supabase as the backend processor. Also needs to cover the in-app
  **Delete Account** flow (`supabase/functions/delete-account/`) — Apple
  specifically checks that a real, working account-and-data deletion path
  exists and is described.
- **Terms of Service** — standard SaaS/subscription terms, but must
  specifically address: the $12/year auto-renewing subscription (via
  RevenueCat/StoreKit) with its free trial, and the enterprise Church Code
  path as an alternative to that subscription (see §2's compliance note —
  worth stating plainly that this exists and how it's authorized).
- Both pages need to be **structurally stable, permanent URLs** — whatever
  paths you pick (e.g. `/trellis/privacy`, `/trellis/terms`), once
  submitted to App Store Connect and hardcoded into a shipped app build,
  changing the path breaks compliance for every version already in
  review or live. Pick final paths before first submission, not after.
