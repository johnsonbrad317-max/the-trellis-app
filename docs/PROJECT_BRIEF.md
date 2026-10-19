# The Trellis: project brief for a new contributor

Read this before changing anything. It covers what the app is, why it exists, how it should feel and read, and the conventions the code already follows. When something here and the code disagree, the code is current. Say so instead of guessing.

---

## 1. What it is

**The Trellis** is an iPhone app (Flutter, so Android exists but is secondary) for Christian discipleship and accountability. It belongs to **Unhindered Lives** (unhinderedlives.com). The owner is Brad Johnson.

It is built on Hebrews 12:1–2: *"Since we are surrounded by so great a cloud of witnesses, let us also lay aside every weight, and sin which clings so closely, and let us run with endurance the race that is set before us."*

Three roles, and one account can hold more than one (a role switcher sits in the top bar):

- **Runner** writes a **Rule of Life**: the rhythms they want to keep (Scripture, prayer, family, rest, community) and the sins they want to *throw off*. Every morning they check in on the day before: one yes/no question per rhythm. They keep a **Prayer Garden** (people and situations), and can ask a Witness to meet.
- **Witness** walks with one or more Runners. They see the Runner's Rule, check-ins and shared prayers. They get gentle nudges when something slips (a missed Anchor Rhythm, three misses in a row, going quiet) and a weekly roll-up, and can text, pray, or suggest a meeting.
- **Cloud** is a church or organization leader. They buy seats, give their people a code, add church-wide "DNA" rhythms, and see aggregate health for the congregation, never anyone's private answers.

### Core ideas in the product

- **Rhythms** have a frequency (daily, weekly on chosen days, monthly, annual). One can be marked an **Anchor Rhythm**: the ones that matter most.
- **Throw-offs** ("Avoid ___") are always daily, and are asked as "Did you avoid ___?" so that **Yes is always the good answer**. Anything worded as a "No …" or "Abstain from …" belongs here.
- **Settling and locking:** for the first 7 days after committing (and for each rhythm's first 7 days) everything can be changed. After that **only Anchor Rhythms (and church DNA rhythms) are locked**. Changing one needs a Witness to approve an unlock. Other rhythms stay editable; removing a settled one tells the Witness. Every 180 days a season ends and the whole Rule opens for a week.
- **Check-ins lock in once given.** There is no resubmitting a day.
- **The living vine** on the dashboard shows the season: one engraved grapevine built from layered artwork. A branch grows each week. Fruit follows consistency, and the newest branches wither in a hard stretch.
- **Connect** suggests meeting times from both people's on-device calendars (busy blocks only, never event details) and a midway coffee shop or lunch spot.
- **Pricing (built, but switched off until launch):** two free weeks, then $12/year via in-app purchase, a church/organization code, or a gift membership redeemed on the website. Witnesses are always free. `app_settings.enforce_membership` is `false`, so nobody is asked to pay during the beta.

---

## 2. Ethos

- **Accountability without shame.** The app exists to help someone keep a promise to God with a friend beside them, not to grade them. A Witness is notified "so they can support you, not to keep score." Nothing should feel like surveillance or a report card.
- **Grace, then truth.** Missed days are shown honestly, but the wording invites a conversation ("You might ask them about it"), never a verdict.
- **No therapy-speak.** Plain, warm, direct. The owner cut "Nothing you did caused this." Don't write sentences that tell people how to feel.
- **Privacy is a feature.** Show the least that serves the relationship:
  - A **lock-screen notification never names a rhythm.** "Brad removed a rhythm," not "Brad removed 'Avoid pornography.'" The in-app note can name it.
  - Witnesses and leaders do **not** see last-seen times.
  - Calendars share busy blocks only.
  - Church leaders see aggregates, plus only what each person consented to.
  - Prayer photos are never sent to a Witness.
- **Don't overreact to one tester.** The owner weighs feedback. Fix real bugs quickly. For new features, propose them first, keep them small, and wait for a yes.
- **Honest product, honest business.** No dark patterns, no fake urgency, and nothing that games App Store rules.

---

## 3. Voice and copy

- The owner's own wording is in `lib/models/witness_messages.dart` and in the welcome deck (`lib/screens/welcome_walkthrough_screen.dart`). Match it. When copy is quoted from the owner, keep it word for word.
- Use **first names** in anything personal: texts, notes, greetings. "Hey Kevin," not "Hey Kevin Barb."
- Say **"church or organization,"** not just "church," in general copy.
- Never call anything a **journal**.
- Check-in prompts are generated from the rhythm title: put-on rhythms become "Did you ___?" and throw-offs become "Did you avoid ___?". Write rhythm titles so that reads naturally ("Finish work by 6 PM," not "Be done with work by 6 PM").
- Title Case for display; abbreviations already in capitals stay that way ("6 PM", "AA").
- Scripture in the app is the **Berean Standard Bible (BSB)**, public domain, quoted word for word with ", BSB" after the reference. The prayer-text verses live in `lib/models/scripture_verses.dart`.
- Buttons say what happens: "Remove," "Keep It," "Request Unlock," "Check again."

---

## 4. Look and feel: 19th-century woodcut / bookplate

This is strict. Every screen should look like an engraved book plate, not a stock Material app.

- **Colors** (`lib/theme/app_colors.dart`): forest green `#1E3A2B` (ink, primary), antique brass `#B8860B` (accents, borders), parchment `#F9F6F0` and vellum `#F8F1E0` (backgrounds, plates), terracotta `#9E4B2F` (misses, destructive actions).
- **Type:** EB Garamond everywhere (`AppTheme`). Italics for scripture and quiet notes.
- **No stock Material visuals.** No `Icons.*`, no default spinners, no stock dialogs, chips or snack bars. Use the house widgets in `lib/widgets/`:
  - `BookplateButton`, `BookplatePlate`, `BookplateChip`, `showBookplateForm` / `showBookplateConfirm` / `showBookplateNotice` / `showBookplateSheet`, `BookplateSpinner`
  - `BrassGlyph` / `BrassGlyphButton` for icons
  - `CustomToggle`, `BrassChevron`, `TrellisScaffold`, `VineFrame`, `GradientButton`
- Cards use a double-line border (1px outer, 4px gap, 1px inner) with a soft forest-green shadow.
- Illustrations are engraved/woodcut PNG art in `assets/images/`. New art must match that style.
- Every layout must work on a 375-wide phone at 1.3× text size without overflowing. Tests check this for key screens.

---

## 5. Architecture

**App:** Flutter 3.47 / Dart 3.13. State lives in one `ChangeNotifier`, `RunnerProfile` (`lib/models/runner_profile.dart`). Screens listen with `ListenableBuilder`. No other state framework.

- `lib/models/`: plain models plus `RunnerProfile` (all Supabase reads and writes go through it). `RunnerProfile.preview()` is a fake, offline profile for demos and tests. Every write calls `_refuseInPreview()`.
- `lib/screens/`: `runner_shell.dart`, `witness_shell.dart`, `cloud_shell.dart` (the three role shells with bottom tabs), plus `runner/`, `witness/`, `cloud/`.
- `lib/services/`: push (FCM), local reminders, device calendars, Google Places, RevenueCat purchases, PostHog analytics, notification routing.
- `lib/widgets/`: the design system above, plus shared pieces.

**Backend:** Supabase project `qonsiliimbkcjmcnhonb`.

- **Postgres with Row Level Security everywhere.** Client writes are guarded by triggers that check `current_user in ('authenticated','anon')`. Cross-account actions are `SECURITY DEFINER` functions that check `auth.uid()` themselves. Grants are revoked from `public`/`anon` and given only where needed.
- **Push:** a table insert fires `notify_push_engine('<event>')`, which calls the `push-notification-engine` Edge Function using a Vault secret. Each event has a resolver that builds the message. Recipients can mute some events through `notification_preferences`.
- **Edge Functions** (`supabase/functions/`, Deno): `push-notification-engine`, `delete-account`, `revenuecat-webhook`, `submit-feedback`, `issue-gift-code`, `redeem-gift-code`. Shared helpers are in `_shared/http.ts`. Functions called by other servers use a shared-secret header and `--no-verify-jwt`.
- **pg_cron** runs the daily Witness nudges, weekly roll-ups and cleanups.

**Website:** a separate repository (`unhinderedlives-web`, Next.js on Vercel) on the same Supabase project. It handles church checkout (Stripe), gift-code sales and redemption, and legal pages.

---

## 6. Conventions that matter

### Database migrations

- Numbered files in `supabase/migrations/` (`NNN_short_name.sql`). The latest is **034**.
- **The owner runs them by hand in the Supabase SQL editor.** They must be **idempotent**: `create or replace`, `if not exists`, `drop … if exists` before re-creating.
- Each file opens with a plain-English header saying what it does and why, and ends with commented check queries.
- **Never break older app builds.** Testers lag behind. New columns are nullable or defaulted. The client reads new columns tolerantly, so a missing column becomes null. Inserts only send a new column when it's needed.
- A failure in a notification or side effect must **never undo the user's write**. Use `exception when others then raise warning …; return new;`.

### Dart

- Comments explain **why**, in full sentences, at the density of the surrounding code.
- Every write is optimistic only when it can be rolled back on failure (see `updateRuleItem`). Otherwise wait, then update local state.
- User-facing failures go through `showBookplateNotice`, with a sentence that says what to do ("Check your connection and try again").
- `flutter analyze` must be clean.

### Tests

- `flutter test` must pass in full (about 400 tests) before every commit.
- Add tests for new logic and for every bug fixed.
- Tests must not depend on today's date or time zone. **Codemagic runs in UTC.** Pass `now` in where possible, as `RunnerProfile.preview(now:)` does.
- Render tests (`test/render_*_test.dart`, `--dart-define=RENDER_OUT=<dir>`) produce the welcome-deck screenshots and website images. Re-run them when those screens change.

### Git and release

- Work on `master`, commit locally, and do **not** push. The owner pushes with `git push origin master:weekend-ai-edits`. **Codemagic** builds from `weekend-ai-edits`, runs analyze and tests, and uploads to TestFlight.
- Never commit `.claude/scheduled_tasks.lock`.
- Commit messages: a short subject, then a few lines on what changed and why.

### Secrets

- Never paste, print, log or commit a secret (API keys, webhook secrets, the gift-code secret, service-role keys). The owner sets secrets himself. Refer to them by name only.

---

## 7. App Store rules this project is built around

- **Guideline 3.1.1:** paid features are unlocked only by in-app purchase. **No code field in the app unlocks a membership.** Gift codes are redeemed **on the website**, using the recipient's account email. The app just sees the active membership.
- **Guideline 3.1.3:** church and organization seats are enterprise access (a code joins a church). That's allowed, but **the app never links or points people to buy anything outside the App Store.** Support contact is fine; "buy at our website" is not.
- The in-app purchase is the $12/year subscription. Restore Purchases and the Terms/Privacy links sit beside it.

---

## 8. Current state (October 2026)

- In TestFlight beta with a growing group of testers. Feedback arrives as TestFlight screenshots with comments.
- **Recently shipped:**
  - Locked check-ins; only Anchors lock, with a Witness note on removal
  - Rename rhythms
  - Edit prayers
  - Share a prayer with chosen Witnesses, with a push
  - Pull to refresh, plus a refresh when the app returns to the front
  - Negative rhythms sorted into the throw-off section
  - The living vine (v6 art)
  - Website gift codes
  - "Hard week" only judged after 3 days
- **Dormant until launch:** membership enforcement. Launch steps are in `RELEASE_CHECKLIST.md` and `docs/gift-codes-for-website.md`.
- **Deferred ideas (don't build without a yes):** connecting with church friends as "supporters" (a third relationship type).
- Useful docs:
  - `BETA_QA_SCRIPT.md`
  - `RELEASE_CHECKLIST.md`
  - `supabase/CALENDAR_SETUP.md`
  - `docs/privacy-policy-for-website.md`
  - `docs/living-vine-art-brief.md`

---

## 9. How to work on it

1. Read the files you'll touch, and the migration that created any table you'll change.
2. Keep each change as small as the request. Match the code around it.
3. For copy, match the voice above. For UI, use the house widgets. For data, follow RLS and guard patterns and write an idempotent migration.
4. Run `flutter analyze` and the full `flutter test`, and fix anything you broke.
5. Commit locally. Then tell the owner, in plain words, what changed, what he needs to do (run migration NNN, deploy function X, push), and what you could not verify (anything only a real phone or the live database can prove).
6. If a request would cross one of the lines above (App Store purchase pointers, rhythm names on lock screens, shaming copy, a secret in the open), say so and propose the alternative before building.
