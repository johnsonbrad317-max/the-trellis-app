# The Trellis — Solo Burn-In QA Script (iPhone 16 Pro Max)

Goal: try to break it. Every step below has a specific expected result —
anything else is a bug. Work through sections in order; later sections
assume earlier ones passed.

## Before you start

- [ ] Migrations `002` through `005` have all been run, in order, in the Supabase SQL Editor
- [ ] All three Edge Functions are deployed with current source: `push-notification-engine`, `delete-account`, `revenuecat-webhook` (`--no-verify-jwt`)
- [ ] Xcode: Push Notifications capability added, In-App Purchase capability added, `GoogleService-Info.plist` added to the Runner target, your Apple Developer Team selected for code signing
- [ ] Installed on your physical iPhone via Xcode (Product → Run) or TestFlight, **not** the Simulator — APNs push delivery doesn't work on the Simulator
- [ ] You have terminal/computer access alongside the phone — several tests below trigger the "other side" of a Runner↔Witness interaction via `curl` against the live Supabase REST API, since you're testing solo on one device and can only be signed into one account at a time on the phone itself. This mirrors exactly how these features were verified during development.
- [ ] Two throwaway test accounts exist (or create them now): one Runner, one Witness, paired to each other (Settings → My Witnesses → generate a code as Runner, redeem it as Witness — or use the pairing-code screen's app-bar icon)

---

## 1. Push Deep-Linking

**Setup**: On the phone, sign in as the **Witness** account, then background the app (press the Home button / swipe up — don't force-quit yet) so the notification actually appears on the Lock Screen instead of just showing in-app.

### 1a. Unlock Request → routes to Witness Runners tab, correct Runner pre-selected
1. On your computer, get the Runner's JWT (sign in via `curl` to `/auth/v1/token?grant_type=password`, or pull it from the Runner account's session if you have it saved)
2. Add a rule item for the Runner (if none exist) and flip one to `is_church_mandated: true` via a direct `PATCH` to `/rest/v1/rule_items` (same technique used during development — see the migration comments for the exact RLS shape if you need a refresher)
3. Insert a row into `pending_unlock_requests` via `curl POST /rest/v1/pending_unlock_requests` as the Runner, with `witness_id` set to your test Witness
4. **Expected**: within a few seconds, a push notification titled "Unlock Request" appears on the Lock Screen
5. Tap it
6. **Expected**: app opens directly to the **Witness Runners tab**, with that Runner's card already selected, and the "Unlock Requests" section showing the request — not the Witness Dashboard's default/empty state, not a generic app-open

### 1b. Grace Nudge → same routing
1. As the Runner (via `curl`), insert 3 consecutive `check_ins` rows with `answered_yes: false` for the same **Anchor Rhythm** `rule_item_id` (needs `is_anchor_rhythm: true` — a non-anchor rhythm will correctly **not** fire this, see the backend audit)
2. **Expected**: a "Grace Nudge" push arrives on the Witness's Lock Screen
3. Tap it → **expected**: same routing as 1a, that Runner pre-selected on the Witness Runners tab

### 1c. Meeting Proposal → routes to the correct *side*
1. As the Runner, insert a row into `meetings` with `proposed_by: 'runner'`
2. **Expected**: push arrives on the Witness's phone (since the Runner proposed, the Witness is notified) → tap → routes to Witness shell
3. Now flip it: sign the phone into the **Runner** account instead, background the app, and insert a `meetings` row via `curl` with `proposed_by: 'witness'`
4. **Expected**: push arrives on the Runner's phone this time → tap → routes to the **Runner shell** (not Witness) — this is the one path in `notification_router.dart` that has to pick between two different destination shells based on which side got notified; specifically worth breaking

### 1d. Account Deleted
Covered in Section 4 — same routing mechanism, tested there since it's destructive.

### Things to specifically try to break
- Tap the notification from the **Lock Screen** (device locked, Face ID prompt appears first) — not just from within the Notification Center list
- Force-quit the app completely (swipe up in the app switcher), *then* trigger a push, *then* tap it cold — this exercises `getInitialMessage()` instead of `onMessageOpenedApp`, a completely different code path with its own 5-second retry-for-profile-load logic. This is the highest-value thing to test in this whole section.
- Tap two different notification types in quick succession before the first one finishes routing

---

## 2. Offline Resilience

### 2a. Daily Check-In
1. Sign in as the Runner, commit a Rule of Life if you haven't
2. Open **Daily Check-In**, answer every rhythm
3. **Before tapping Submit**, enable Airplane Mode
4. Tap Submit → confirm through the dialog
5. **Expected**: a snackbar reading *"Network error — couldn't submit your check-in. Try again."* — **not** a crash, **not** a frozen spinner, **not** a silent no-op
6. Disable Airplane Mode, tap Submit again (your answers should still be filled in — they aren't cleared on failure)
7. **Expected**: submits successfully this time, normal "Check-in submitted" confirmation

### 2b. Sign Out while offline
1. Enable Airplane Mode
2. Open the drawer → Sign Out → confirm
3. **Expected**: snackbar *"Network error — couldn't sign out. Try again."* — you should remain signed in and on the same screen, not stuck on a dead loading state
4. Disable Airplane Mode, retry → should succeed and return you to the sign-in screen

### 2c. Delete Account while offline
1. Enable Airplane Mode
2. Drawer → Delete Account & Data → confirm through the dialog
3. **Expected**: the loading spinner appears briefly, then a snackbar: *"Couldn't delete your account — check your connection and try again."* Your account must **not** be deleted, and you should land back on the drawer, not a broken state.
4. Disable Airplane Mode before Section 4, where you'll actually complete this flow

### Things to specifically try to break
- Toggle Airplane Mode back on *mid-request* (not just before) — e.g., enable it the instant after tapping Submit
- Try the same offline tests on a screen that does **not** have explicit error handling (almost everything besides check-in/sign-out/delete-account) — this won't crash, but confirm what it actually does (most likely: button appears to do nothing, no feedback at all). Not a regression from today's work, just worth knowing the current boundary of what's handled.

---

## 3. Pairing Logistics

### 3a. Witness pairing code — full loop
1. As the Runner: Settings → My Witnesses → Generate Pairing Code → note the 6-character code and that the dialog says it expires in 24 hours
2. Sign out, sign in as the Witness
3. Tap the person-add icon in the Witness shell's app bar (should be visible immediately, even with zero Runners so far)
4. Enter the code → **expected**: loading spinner on the button, then success snackbar *"You're now walking alongside this Runner."*, screen pops, Runner now appears in the carousel
5. **Break it**: generate a fresh code, then try entering it **twice** as the Witness (redeem it once successfully, then try the exact same code again from the empty-field entry point) → second attempt should show *"That code wasn't recognized"* (already consumed)
6. **Break it**: enter a code with lowercase letters / extra spaces around it → should still work (codes are trimmed and uppercased server-side)
7. **Break it**: enter total garbage (`XXXXXX`) → should show the invalid-code error, not crash or hang
8. **Break it**: turn on Airplane Mode, attempt redemption → should show the network-error variant, not the invalid-code message (these are two different error states — confirm the right one shows for the right cause)

### 3b. Enterprise Church Code (paywall bypass)
1. As a Runner with `trial` or `cancelled` membership status, go to Account & Membership
2. Tap **"Have a Church Code?"**
3. **First**, without a real code minted yet, enter garbage → expect *"That code wasn't recognized. Check it with your church."*
4. To actually test success, you'll need a real code — mint one via the `generate_enterprise_church_code` RPC from a Cloud-admin account (or directly via SQL as the project owner: `select generate_enterprise_church_code('<church_id>', 5, null);` for a 5-use code)
5. Enter that code as the Runner → **expected**: dialog closes, snackbar *"Membership unlocked — welcome!"*, and the Membership card now shows "Your membership is active." with the Subscribe/Resubscribe button and the church-code link both gone (only shown for trial/cancelled)
6. **Break it**: redeem the same code again with the same account → should silently succeed (treated as already-redeemed, not an error) per the RPC's design — confirm it doesn't double-count or error
7. **Break it**: if you minted a code with `max_redemptions: 1`, try redeeming it with a *second* test Runner account → should fail once the cap is hit

### Things to specifically try to break
- Redeem a Witness pairing code from a **Runner**-role screen somehow, or vice versa (shouldn't be reachable via normal navigation — confirm there's no way to get there)
- Background the app mid-redemption (after tapping Redeem, before it resolves) — reopen and confirm no double-submit happened

---

## 4. Compliance & Deletion

This is the one with real irreversible consequences — use a fully throwaway test account for both sides.

1. Confirm the Runner and Witness test accounts are actively paired (Section 3a)
2. On the phone, sign in as the **Witness**, background the app (same setup as Section 1) so you'll see the real Lock Screen push
3. On the computer, sign in as the **Runner** via `curl` (or use a second device/simulator if you have one, signed in as the Runner, to drive this from the UI instead)
4. As the Runner: drawer → **Delete Account & Data** → read the confirmation copy (it should explicitly say *"Your Witness will be notified"*) → confirm → **Delete Everything**
5. **Expected, in this exact order**:
   - A brief loading spinner on the Runner's screen
   - **Before** the Runner's screen finishes and returns to the sign-in screen, the Witness's phone should receive the "Account Deleted" push on the Lock Screen — the notify-then-delete ordering is enforced server-side in `delete-account`, specifically so this can't happen out of order even under a bad network
   - The Runner's screen then completes and returns to the auth/sign-in screen
6. Tap the push on the Witness's phone → **expected**: routes to the Witness Runners tab; the deleted Runner should be **gone** from the list (the pairing row cascade-deleted along with the account)
7. Try to sign back in as the deleted Runner account with its old credentials → **expected**: fails, account genuinely no longer exists (not just hidden/soft-deleted)
8. Check the Supabase Dashboard directly (Table Editor → `profiles`) → confirm the row is actually gone, not just flagged

### Things to specifically try to break
- Force-quit the Runner's app **immediately** after tapping "Delete Everything," before the spinner resolves — reopen the app; the account should either still exist (safe — the delete never completed) or be fully gone (safe — it completed), never in a half-deleted state. This is exactly the ordering guarantee the function is designed to provide; worth actually trying to catch it out.
- Attempt to delete an account that has **zero** paired Witnesses → should succeed with no notification step attempted (confirm no error/hang from having nobody to notify)
- Attempt to delete an account with **multiple** active Witnesses → confirm all of them get notified, not just one

---

## Reporting a bug

For anything that doesn't match "Expected," note: which numbered step, what actually happened, whether Airplane Mode/background state was involved, and whether it reproduces a second time. The exact repro conditions matter more than a description of the symptom.
