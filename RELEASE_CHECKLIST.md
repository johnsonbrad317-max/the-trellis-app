# The Trellis 1.0.0 beta — release checklist

Target: build **1.0.0** through Codemagic, to **TestFlight** (iOS) and the
**Google Play internal testing track** (Android).

Work top to bottom; later sections assume earlier ones are done.

**How to read this document**

- `[ ]` is something you (the owner) must do. None of these could be done from
  the development machine.
- **[UNVERIFIED]** marks a statement that could not be checked from here. The
  development machine is Windows with no Xcode and no Android SDK, so **no
  Android or iOS build of this app has ever been run** — not locally, not in
  CI. `codemagic.yaml`, the Gradle signing config, the Xcode project edit and
  the manifest/plist changes were written and syntax-checked, but never built.
  Expect to fix something on the first build of each platform.

Identifiers used throughout (confirmed identical in the Xcode project,
`android/app/build.gradle.kts`, `android/app/google-services.json`,
`lib/firebase_options.dart` and `codemagic.yaml`):

| What | Value |
| --- | --- |
| iOS bundle ID / Android application ID | `com.unhinderedlives.trellis` |
| Version | `1.0.0` (build number assigned by CI) |
| Firebase project | `the-trellis-4a580` |
| Supabase project ref | `qonsiliimbkcjmcnhonb` |

---

## 0. Blockers — nothing ships until these are done

- [ ] **Put the project in git and push it to a remote** (GitHub, GitLab or
      Bitbucket). The project folder is not a git repository today and
      Codemagic builds only from a git remote. Before the first commit:
  - [x] Root `.gitignore` now covers keystores, `key.properties`, `.p8`/`.p12`,
        provisioning profiles, `.env*`, service-account JSON and
        `supabase/.temp/` (done in the audit). Check `git status` before the
        first commit anyway — nothing secret should appear in it.
  - [x] Root `.gitattributes` added (`* text=auto eol=lf`), so the Mac and
        Linux build machines receive LF line endings even though the files were
        authored on Windows.
  - [ ] **Commit `pubspec.lock`.** CI runs `flutter pub get --enforce-lockfile`
        and fails without it; it is what pins every transitive package.
  - [ ] Add migration **015** (the demo-code migration you applied by hand) to
        `supabase/migrations/` so the repository can rebuild the database.
- [x] **Firebase re-registered under `com.unhinderedlives.trellis`** (Android and
      iOS apps created in project `the-trellis-4a580`). `google-services.json`,
      `ios/Runner/GoogleService-Info.plist` and `lib/firebase_options.dart` now
      carry the new app IDs; a test checks they agree with each other and with
      the native projects. Still to do:
  - [ ] Upload the APNs auth key to the **new** iOS app in Firebase (section
        4.1) — push on iPhone fails without it.
  - [ ] Optional: once the old `com.usengineering.trellis` apps are deleted in
        the Firebase console, delete the second `client` entry from
        `google-services.json` too.
  - [ ] `GoogleService-Info.plist` is in the repo but is *not* added to the
        Xcode Runner target (the app configures Firebase from
        `firebase_options.dart`, so it isn't needed). If you ever want it
        bundled, add it in Xcode (File > Add Files to "Runner").
- [ ] **Replace the app icon.** *(Done: the official icon is generated for both
      platforms.)* Both platforms still carry the stock Flutter
      logo (`android/app/src/main/res/mipmap-*/ic_launcher.png` are
      byte-identical to the Flutter template; `ios/Runner/Assets.xcassets/AppIcon.appiconset`
      is the Flutter logo). Internal TestFlight / internal Play testing will
      accept it; Apple's Beta App Review and both stores' public review will
      not. iOS: 1024×1024 PNG with no transparency plus the sizes listed in
      `Contents.json`. Android: all five `mipmap-*` densities (an adaptive icon
      is recommended).
- [ ] **Apple Developer Program membership** (organisation) and **Google Play
      developer account**, each with the legal entity that will own the app.
- [ ] **Apple: Paid Applications agreement, tax and banking** completed in App
      Store Connect > Business. Without it, subscription products never load —
      not even in TestFlight.
- [ ] Secrets and keys you must supply (sections 1, 4 and 5 say where each
      goes): App Store Connect API key, iOS distribution certificate, Android
      upload keystore, Play service-account JSON, APNs auth key, RevenueCat SDK
      keys, Google Places key.
- [ ] Decide whether the following dependency risk is acceptable or should be
      fixed first (owner of `pubspec.yaml`): see section 8, "Known risks".

---

## 1. Codemagic dashboard

### 1.1 Add the app
- [ ] Codemagic > Add application > select the repository > project type
      **Flutter** > confirm it detects `codemagic.yaml` on the default branch.
- [ ] Enable the repository **webhook** (App settings > Webhooks) so pushed
      tags and pull requests start builds.

### 1.2 App Store Connect integration (iOS)
- [ ] App Store Connect > Users and Access > Integrations > App Store Connect
      API > generate a **Team key** with the **App Manager** role. Download the
      `.p8` (one-time download), note the Key ID and Issuer ID.
- [ ] Codemagic > Team settings > Integrations > **Developer Portal** > add
      the key and name it exactly **`codemagic_api_key`** (the name
      `codemagic.yaml` references).

### 1.3 iOS code signing
Do section 2.1 (App ID with Push Notifications) **first** — a profile created
before the capability is enabled does not contain the push entitlement and the
build fails at signing.
- [ ] Codemagic > Team settings > codemagic.yaml settings > Code signing
      identities > **iOS certificates**: generate (or upload) an **Apple
      Distribution** certificate.
- [ ] Apple Developer portal > Profiles > create an **App Store** provisioning
      profile for `com.unhinderedlives.trellis` using that certificate.
- [ ] Codemagic > Code signing identities > **iOS provisioning profiles** >
      fetch (or upload) that profile.
      `codemagic.yaml` selects it by `distribution_type: app_store` +
      `bundle_identifier: com.unhinderedlives.trellis`.
      **[UNVERIFIED]** exact menu names — Codemagic's UI changes; the concepts
      (one distribution certificate, one App Store profile, both stored under
      Code signing identities) are from the current docs.

### 1.4 Android upload keystore
- [ ] Create the upload keystore **once**, on a trusted machine, and back it up
      somewhere safe (password manager / company vault). Losing it means asking
      Google to reset the upload key.
      `keytool -genkey -v -keystore trellis-upload.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
- [ ] Never put the keystore or its passwords in the repository.
- [ ] Codemagic > Team settings > codemagic.yaml settings > Code signing
      identities > **Android keystores** > upload the file, enter keystore
      password, key alias and key password, and set the **Reference name** to
      exactly **`trellis_upload_keystore`**.
- [ ] (Optional, local release builds only) create `android/key.properties`
      (git-ignored) with `storeFile`, `storePassword`, `keyAlias`,
      `keyPassword`. Without it a local release build is signed with the debug
      key; a CI release build without a keystore **fails on purpose**.

### 1.5 Environment variable groups
App settings > Environment variables. Tick **Secret** for every value.

Group **`trellis_app_config`** (used by both release workflows):

| Variable | Value | Used by |
| --- | --- | --- |
| `REVENUECAT_APPLE_API_KEY` | RevenueCat public SDK key for the App Store app (`appl_…`) | iOS build |
| `REVENUECAT_GOOGLE_API_KEY` | RevenueCat public SDK key for the Play app (`goog_…`) | Android build |
| `GOOGLE_PLACES_API_KEY` | Google Cloud API key, see 5.4 | both |

Group **`google_play`** (Android workflow only):

| Variable | Value |
| --- | --- |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS` | the full JSON key file contents of the Play service account (section 3.3) |

Note: older Codemagic guides call this variable
`GCLOUD_SERVICE_ACCOUNT_CREDENTIALS`. The current docs and the `google-play`
command-line tool read `GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS`, so that is
the name `codemagic.yaml` uses.

- [ ] Both groups created with every variable above.
- [ ] A release build **stops with a clear message** if one of the three app
      keys is missing. To ship a build without one on purpose (the feature it
      powers is then switched off), add `ALLOW_MISSING_APP_CONFIG=true`.

### 1.6 One edit to `codemagic.yaml`
- [ ] After creating the App Store Connect app record (2.2), put its numeric
      **Apple ID** into `ios-release > environment > vars > APP_STORE_APPLE_ID`
      (keep the quotes). The iOS build refuses to run with the placeholder.
- [ ] (Recommended) pin Flutter: change `flutter_version: &flutter_version stable`
      to the exact version the app was developed on (`3.47.4`) once a build log
      confirms Codemagic offers it. **[UNVERIFIED]** which Flutter versions
      Codemagic currently provides; `pubspec.lock` needs 3.44.0 or newer.

### 1.7 Starting a release
- [ ] Both release workflows start on any pushed tag matching `v*`
      (`git tag v1.0.0-beta.1 && git push origin v1.0.0-beta.1`), or manually
      from the Codemagic UI. One tag starts **both** platforms.
- [ ] Build numbers are automatic: latest TestFlight build number + 1 and
      latest Play versionCode + 1; the first build is 1. To force a number, set
      `BUILD_NUMBER_OVERRIDE` for that build.
- [ ] The version name comes from `pubspec.yaml` (`version: 1.0.0+…`).

---

## 2. Apple

### 2.1 Developer portal — App ID
- [ ] Identifiers > App IDs > register **`com.unhinderedlives.trellis`**
      (explicit, not wildcard).
- [ ] Enable **Push Notifications**. (In-App Purchase is on by default and
      needs no entitlement.)
- [ ] Keys > create an **APNs Auth Key** (`.p8`, "Apple Push Notifications
      service"). Note Key ID and Team ID — it goes to Firebase in 4.1.

### 2.2 App Store Connect — app record
- [ ] My Apps > + > New App: platform iOS, name "The Trellis" (must be unique
      on the store — have an alternative ready), bundle ID
      `com.unhinderedlives.trellis`, SKU of your choice.
- [ ] Copy the **Apple ID** (App Information) into `codemagic.yaml` (1.6).

### 2.3 Subscription product
- [ ] Monetization > Subscriptions > create a subscription group and the
      product(s). The paywall shows the offering's **annual** package if there
      is one, otherwise the first package (`lib/widgets/paywall_sheet.dart`).
- [ ] Fill in price, localisation and review screenshot so the product reaches
      "Ready to Submit"; attach it to the first version you send to App Review.
- [ ] Generate the **In-App Purchase key** (Users and Access > Integrations >
      In-App Purchase) for RevenueCat (5.1).
- [ ] Sandbox tester account created (Users and Access > Sandbox).

### 2.4 TestFlight
- [ ] **Export compliance** is answered in the binary:
      `ITSAppUsesNonExemptEncryption = false` in `ios/Runner/Info.plist` (the
      app only uses HTTPS and hashing/signature checks for authentication). No
      per-build question should appear. Change this if the app ever adds its
      own encryption of user content.
- [ ] Internal testing: add testers under TestFlight > Internal Testing. Builds
      appear a few minutes after Apple finishes processing.
- [ ] External testing (needs Beta App Review): create a group, fill in
      **Test Information** (feedback email, privacy policy URL, what to test,
      sign-in credentials), then uncomment `beta_groups` in `codemagic.yaml`
      with the exact group name.

### 2.5 App Privacy ("nutrition label") — summary of what the app implies
Fill in App Store Connect > App Privacy. Based on reading the code; have
whoever owns the privacy policy confirm. **Tracking: No** (no advertising ID,
no cross-app tracking, so no App Tracking Transparency prompt).

| Data type (Apple's name) | What it is in The Trellis | Linked to the user | Purpose |
| --- | --- | --- | --- |
| Contact Info — Email Address, Name | account sign-up (Supabase Auth) | Yes | App Functionality |
| Contact Info — Phone Number | phone numbers the user types for Witnesses / prayer contacts (other people's numbers) | Yes | App Functionality |
| Health & Fitness — Health | daily check-ins on rhythms/habits (the app itself shows a consumer-health-data consent) | Yes | App Functionality |
| Sensitive Info | content reveals religious belief and practice (prayer notes, church affiliation, Rule of Life) | Yes | App Functionality |
| User Content — Other User Content | prayer notes, Rule of Life items, meeting places and times | Yes | App Functionality |
| User Content — Customer Support | feedback notes sent from the app | Yes (only if the user opts in to a reply; otherwise sent without identity) | App Functionality |
| Identifiers — User ID | Supabase user id; a SHA-256 hash of it is sent to PostHog; RevenueCat app user id | Yes | App Functionality, Analytics |
| Identifiers — Device ID | Firebase Cloud Messaging push token stored on the profile | Yes | App Functionality |
| Purchases — Purchase History | subscription status via RevenueCat | Yes | App Functionality |
| Usage Data — Product Interaction | PostHog events (role viewed, rhythm completed, feedback rating; no free text) | Yes (hashed id — Apple treats hashed ids as linked) | Analytics |

Points to settle:
- [ ] **Location:** the app does not read device location. PostHog derives
      approximate location from the IP address on its servers unless that is
      disabled; switch on "Discard client IP data" in the PostHog project, or
      declare **Coarse Location** (Analytics).
- [ ] **Calendar:** connecting a calendar goes through Cronofy with the
      free/busy scope only; busy times are fetched server-side per request and
      not stored, but the access tokens are stored (Supabase Vault). Describe
      this in the privacy policy; declare it under **Other Data Types** if your
      counsel wants the label to mention it.
- [ ] Third-party SDK disclosures to cross-check: Firebase (Messaging /
      Installations), RevenueCat, PostHog, Supabase.
- [ ] **Privacy manifest:** every plugin in the build ships its own
      `PrivacyInfo.xcprivacy` where it has one (checked in the package cache:
      add_2_calendar, app_links, firebase_messaging, posthog_flutter,
      share_plus, shared_preferences_foundation, url_launcher_ios). The Runner
      target's own native code (AppDelegate, SceneDelegate) uses no
      "required reason" APIs, so **an app-level manifest is not required
      today** and none was added. **[UNVERIFIED]** — the authoritative check is
      Apple's email after the first upload (ITMS-91053 lists any missing
      declaration).

### 2.6 App Review notes (needed for external TestFlight and for the store)
- [ ] **Demo accounts**: one Runner, one Witness (paired to each other) and one
      Cloud (church admin) account, with passwords, in the review notes.
- [ ] **A working Church Code** for the reviewer, and a sentence on where to
      enter it (Account settings > "Have a Church Code?"). Migration 015 (the
      "demo-code migration", applied to the database but not in this
      repository) appears to exist for this. **[UNVERIFIED]** that a demo code
      is live.
- [ ] **Membership model, guideline 3.1.3.** Explain in the notes, in plain
      words: individuals subscribe through In-App Purchase (auto-renewable
      subscription, restore available in the paywall). Separately, a church can
      hold an organisational agreement with the publisher and give its members
      a Church Code that unlocks membership at no charge to the member
      (3.1.3(c), Enterprise Services). Codes are never sold to individuals and
      the app contains no link or call to action to buy outside the app.
      - [ ] Confirm the pages the app links to (`unhinderedlives.com/trellis`,
            `/terms`, `/privacy`, `/consumer-health-data`) are live and do not
            offer an individual purchase outside the app.
- [ ] Subscription paywall requirements (3.1.2): price, period, and working
      links to Terms of Use and Privacy Policy visible on or next to the
      paywall; Terms/EULA link also in the App Store description.
      **[UNVERIFIED]** — check the paywall on a device.
- [ ] Account deletion is available in the app (Settings drawer > Delete
      Account & Data) — mention it in the notes (guideline 5.1.1(v)).
- [ ] Explain the push notifications (accountability prompts between a Runner
      and their Witness) and the calendar/contacts/location permission strings
      (they belong to Apple's "add event" sheet; the app itself reads none of
      them).
- [ ] **iPad:** the project builds for iPhone and iPad
      (`TARGETED_DEVICE_FAMILY = "1,2"`). Apple will review it on iPad and the
      store needs iPad screenshots. If the app is not meant for iPad at
      launch, change that setting to `"1"` in the three Runner build
      configurations before the first store submission.

---

## 3. Google Play

### 3.1 Create the app
- [ ] Play Console > Create app: name "The Trellis", app (not game),
      free with in-app purchases, accept declarations.
- [ ] Accept **Play App Signing** (default). The keystore from 1.4 is the
      *upload* key; Google holds the app signing key.

### 3.2 First upload is manual
Google's API cannot create the first release of a new app.
- [ ] Run the `android-release` workflow once. It is **expected to build and
      sign the `.aab` and then fail at the Google Play publishing step**.
      (If it fails earlier, that is a real build problem — see section 8.)
- [ ] Download the `.aab` artifact from that build and upload it by hand:
      Play Console > Testing > Internal testing > Create new release.
- [ ] From the second run on, the workflow uploads by itself. While the app
      has never been published, Google only accepts **draft** releases through
      the API (`submit_as_draft: true`): after each build, open the draft in
      Internal testing and press **Save and publish**. Once Google accepts
      non-draft releases for the app, set `submit_as_draft: false`.
      **[UNVERIFIED]** exactly when Google lifts the draft-only restriction for
      this account.

### 3.3 Service account for Codemagic
- [ ] Google Cloud Console (any project you control) > enable **Google Play
      Android Developer API** > create a **service account** > create a JSON
      key.
- [ ] Play Console > Users and permissions > Invite new user > the service
      account's email > grant, for this app: view app information, release to
      testing tracks, manage testing tracks (release manager level).
- [ ] Put the JSON into Codemagic as `GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS`
      (group `google_play`). Permissions can take up to a day to become active.

### 3.4 Subscription product
- [ ] Monetize > Subscriptions > create the subscription and base plan(s)
      matching the App Store product. (Play only allows this after a build
      containing the billing library has been uploaded — the first manual
      upload satisfies that.)
- [ ] License testers added (Setup > License testing) so test purchases are
      free.

### 3.5 Store listing and policy forms (needed before any wider track)
- [ ] Main store listing, content rating questionnaire, target audience
      (adults), ads declaration (no ads), **health apps declaration**.
- [ ] **Data safety form** — summary of what the app implies:

  | Play data type | In The Trellis | Collected | Shared | Purpose |
  | --- | --- | --- | --- | --- |
  | Personal info — Name, Email address, User IDs | account | Yes | No | App functionality, Account management |
  | Personal info — Phone number | numbers typed for Witness / prayer contacts | Yes | No | App functionality |
  | Personal info — Political or religious beliefs | prayer notes, church affiliation, Rule of Life | Yes | No | App functionality |
  | Health and fitness — Health info | rhythm / habit check-ins | Yes | No | App functionality |
  | Financial info — Purchase history | subscription status (RevenueCat) | Yes | No | App functionality |
  | App activity — App interactions | PostHog events with a hashed user id | Yes | No | Analytics |
  | App activity — Other user-generated content | prayer notes, feedback | Yes | No | App functionality |
  | Device or other IDs | FCM push token | Yes | No | App functionality |

  Data is encrypted in transit (HTTPS). Users can request deletion in the app;
  Play also requires a **web URL where account deletion can be requested** —
  publish one and enter it in the form. ("Shared" is No on the basis that
  Supabase, Firebase, RevenueCat, PostHog, Cronofy and Resend act as service
  providers processing on your behalf — confirm with counsel.)
- [ ] The app requests only `INTERNET` and `POST_NOTIFICATIONS` (plus what
      Firebase Messaging adds: `WAKE_LOCK`, `ACCESS_NETWORK_STATE`, and what
      the billing library adds). Calendar and location permissions were
      removed from the manifest because nothing in the app uses them.

### 3.6 Internal testing track
- [ ] Testing > Internal testing > Testers: create an email list, copy the
      opt-in link to the testers.
- [ ] If the developer account is a **personal** account created after
      November 2023, production access later requires a closed test with at
      least 12 testers for 14 days. Organisation accounts are exempt.

---

## 4. Firebase (project `the-trellis-4a580`)

### 4.1 iOS push (APNs)
- [ ] Project settings > Cloud Messaging > Apple app configuration > the iOS
      app `com.unhinderedlives.trellis` > upload the **APNs Auth Key** (.p8)
      with Key ID and Team ID. Without this no push reaches any iPhone.
- [ ] `GoogleService-Info.plist` is **not** in the project and is **not
      needed**: Firebase is initialised from `lib/firebase_options.dart`.
      **[UNVERIFIED]** on a device. One thing to watch: the background message
      handler in `lib/services/push_notifications.dart` calls
      `Firebase.initializeApp()` *without* options; on Android that works
      because `google-services.json` is present, on iOS it relies on the app
      having already initialised Firebase in the same process.
- [ ] Confirm the iOS app is registered in the Firebase console with app id
      `1:896201231315:ios:67b2c81f16edff3397bd26` (what `firebase_options.dart`
      contains).

### 4.2 Android push
- [ ] `android/app/google-services.json` is present and matches
      `com.unhinderedlives.trellis`. **No SHA-1 fingerprint is needed for Cloud
      Messaging.**
- [ ] If you ever add an "Android apps" restriction to the Firebase Android
      API key in Google Cloud, include the SHA-1 of **both** the upload key and
      the Play App Signing key, or token registration fails on store builds.

### 4.3 Server side
- [ ] Firebase Cloud Messaging API (V1) is enabled for the project.
- [ ] A service account JSON with permission to send messages exists for the
      push engine (goes into the `FCM_SERVICE_ACCOUNT_JSON` Supabase secret,
      section 6.3).

---

## 5. RevenueCat and Google Places

### 5.1 RevenueCat project
- [ ] Add an **App Store** app (bundle `com.unhinderedlives.trellis`) and upload
      the In-App Purchase key from 2.3.
- [ ] Add a **Play Store** app (package `com.unhinderedlives.trellis`) and
      upload Play service-account credentials (RevenueCat's own guide lists the
      permissions; it can be the same service account as 3.3 with financial
      data access added).
- [ ] Import the products, create **one entitlement** and attach both store
      products to it. The app treats *any* active entitlement as membership.
- [ ] Create an **offering**, mark it **Current**, and include an **Annual**
      package (the paywall prefers it).
- [ ] Copy the two **public SDK keys** into Codemagic (1.5).

### 5.2 Webhook to Supabase
- [ ] RevenueCat > Project settings > Integrations > Webhooks > add
      `https://qonsiliimbkcjmcnhonb.supabase.co/functions/v1/revenuecat-webhook`
- [ ] "Authorization header value" = the same string as the Supabase secret
      `REVENUECAT_WEBHOOK_SECRET` (paste the raw secret; RevenueCat adds
      "Bearer").
- [ ] Send a test event; expect HTTP 200.

### 5.3 How identity lines up
The app calls `Purchases.logIn(<Supabase user id>)` after sign-in, so the
webhook's `app_user_id` is the profile id. Nothing to configure; verify in the
smoke test (7).

### 5.4 Google Places key
- [ ] Google Cloud > enable **Places API (New)** > create an API key
      restricted to that API.
- [ ] Do **not** add an Android-app or iOS-app restriction: the app calls the
      REST endpoint with only the key header, so app-restricted keys are
      rejected. The key is therefore extractable from the app binary — set a
      **daily quota** and a **budget alert**. (Sending the platform
      identification headers from the app would allow app restrictions; that
      is a code change in `lib/widgets/places_autocomplete_field.dart`.)

---

## 6. Supabase (project `qonsiliimbkcjmcnhonb`)

### 6.1 Migrations — apply in this order, in the SQL editor
Migrations have always been applied by hand; there is no CLI migration history
(do not use `supabase db push` — see the warning in `codemagic.yaml`).

- [ ] `init_schema.sql`, then `002` … `010` — already applied according to
      earlier notes. **[UNVERIFIED]**
- [ ] `011_security_lockdown.sql` — read its "DEPLOY ORDER" header first: it
      locks out any app build older than the matching Dart change.
- [ ] `012_roster_dna_scheduling_role.sql`
- [ ] `013_true_analytics_and_triage.sql`
- [ ] `014_fair_start_requests_secure_codes.sql`
- [ ] **015 — the "demo-code migration". Not in this repository.** It is
      referenced by 016, 017 and 019 as already applied separately. Find the
      SQL and add it to `supabase/migrations/`, or record what it did.
      **[UNVERIFIED]** whether it is applied.
- [ ] `016_feedback_and_dna_propagation.sql`
- [ ] `017_calendar_availability.sql` (needs Supabase Vault — on by default)
- [ ] `018_roster_score_permission_and_feedback_grants.sql`
- [ ] `019_release_audit_hardening.sql` — must run after 011–018 (and 015).
      It fixes a sign-up blocker; run the verification queries at the bottom.
- [ ] `020_edge_rate_limits.sql` — the calendar-availability rate limit (6 a
      minute, 40 an hour, per person). Run it **before** deploying the updated
      `calendar-availability` function; if it is missing the function still
      works but is unlimited (the limiter fails open and logs it). Run the
      three verification queries at the bottom of the file.
- [ ] Any file numbered above 020 that has appeared in `supabase/migrations/`
      since this checklist was written.

### 6.2 Database secret (Vault)
- [ ] Generate one long random string (`openssl rand -hex 32`) and store it in
      Vault, SQL editor:
      `select vault.create_secret('<the secret>', 'push_engine_webhook_secret');`
      The same value goes into the `PUSH_ENGINE_WEBHOOK_SECRET` function secret
      below. If it is missing, database triggers skip push with a warning.

### 6.3 Edge Function secrets (`supabase secrets set NAME=value`)

| Secret | Needed by |
| --- | --- |
| `PUSH_ENGINE_WEBHOOK_SECRET` | push-notification-engine, delete-account (same value as the Vault secret) |
| `FCM_PROJECT_ID` (`the-trellis-4a580`) | push-notification-engine |
| `FCM_SERVICE_ACCOUNT_JSON` | push-notification-engine |
| `REVENUECAT_WEBHOOK_SECRET` | revenuecat-webhook |
| `RESEND_API_KEY` | submit-feedback (sending domain `unhinderedlives.com` must be verified in Resend) |
| `FEEDBACK_TO`, `FEEDBACK_FROM` | submit-feedback (optional; defaults in the function) |
| `CRONOFY_CLIENT_ID`, `CRONOFY_CLIENT_SECRET`, `CRONOFY_DATA_CENTER` | calendar functions |
| `CALENDAR_OAUTH_REDIRECT_URI` | calendar-connect-start, calendar-oauth-callback |
| `CALENDAR_STATE_SECRET` | calendar-connect-start, calendar-oauth-callback |
| `CALENDAR_RESULT_REDIRECT_URL` | calendar-oauth-callback (optional; see `supabase/CALENDAR_SETUP.md`) |

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are
injected automatically.

### 6.4 Deploy the functions (flags are from each function's header comment)

JWT verification **off** — these authenticate with their own shared secret or
signed state:
- [ ] `supabase functions deploy push-notification-engine --no-verify-jwt`
- [ ] `supabase functions deploy revenuecat-webhook --no-verify-jwt`
- [ ] `supabase functions deploy calendar-oauth-callback --no-verify-jwt`

JWT verification **on** (the default) — called by signed-in app users:
- [ ] `supabase functions deploy calendar-connect-start`
- [ ] `supabase functions deploy calendar-disconnect`
- [ ] `supabase functions deploy calendar-availability`
- [ ] `supabase functions deploy submit-feedback`
- [ ] `supabase functions deploy delete-account` — its header gives no deploy
      line; it requires the caller's session and is invoked by the app with
      the user's token, so the default applies. **[UNVERIFIED]**

There is no `supabase/config.toml`, so these flags are not recorded anywhere
but here and in the function headers: a redeploy without `--no-verify-jwt`
silently turns verification back on and breaks push, the RevenueCat webhook
and calendar connection.

### 6.5 Other
- [ ] Cronofy application created and its redirect URI registered
      (`supabase/CALENDAR_SETUP.md`).
- [ ] Auth settings reviewed (email confirmation on/off, Site URL, password
      rules). **[UNVERIFIED]** — not inspected.

---

## 7. Pre-flight smoke test (real devices, the TestFlight / Play build)

Run on one iPhone and one Android phone. Push does not work on the iOS
Simulator.

Install and launch
- [ ] App name under the icon reads "The Trellis"; the icon is the real one.
- [ ] First launch **with network**: text renders in EB Garamond.
- [ ] First launch **in airplane mode** on a fresh install: the app opens and
      the text is still EB Garamond (the font is bundled in `assets/fonts`,
      never downloaded), on the flat #F9F6F0 parchment.
- [ ] Android release build reaches the network at all (sign-in works). This
      is the check for the `INTERNET` permission.

Account
- [ ] Sign up as a new Runner (this failed before migration 019), sign out,
      sign in.
- [ ] Redeem a Church Code; membership becomes active without a purchase.
- [ ] Delete account works and signs out.

Links and messaging (these silently did nothing before the manifest / plist
fixes — check every one on **both** platforms)
- [ ] Terms, Privacy and "Learn more" links open the browser.
- [ ] "Text" buttons open the SMS app with the number (and body where given).
- [ ] "Email" buttons open the mail app.
- [ ] A meeting location opens Apple Maps (iOS) / the maps app (Android).
- [ ] Share buttons open the share sheet (also on an iPad, if supported).

Calendar
- [ ] Confirm a meeting and "add to calendar": Apple's new-event sheet (iOS) /
      the calendar app's new-event screen (Android) opens pre-filled. On an
      iPhone running iOS 15 or 16 the calendar permission prompt appears
      first; tap the location field in the sheet and make sure nothing
      crashes.
- [ ] Connect a calendar (Google / Outlook / Apple) through the browser and
      return to the app; suggested times appear for a paired couple.
- [ ] Rate limit: open the meeting scheduler and tap "Choose calendars" then
      close it, 7 times inside a minute. The suggestions area switches to "You've
      checked calendars a lot just now. Try again in about a minute, or pick a
      time below." — no error banner, and picking a time still works. (Needs
      migration 020.)

Push notifications
- [ ] The permission prompt appears after sign-in (iOS, Android 13+).
- [ ] `profiles.fcm_token` is filled for the test account.
- [ ] Trigger each type (unlock request, grace nudge, meeting proposal,
      support request): the banner arrives with the app in the background.
- [ ] Tap a notification with the app in the background → correct screen.
- [ ] Force-quit the app, trigger a push, tap it → correct screen (cold
      start). See "Known risks" for why this one matters on iOS.
- [ ] Android: the status-bar icon is the small trellis lattice, not a blank
      square.

Purchases
- [ ] Paywall shows the annual product with the store's real price.
- [ ] Sandbox / licence-tester purchase completes; membership turns active
      (RevenueCat webhook → `profiles.membership_status`).
- [ ] Restore purchases works on a reinstall.
- [ ] Cancel / manage subscription opens the store's subscription page.

Analytics and feedback
- [ ] PostHog shows events for the test session with a hashed id and no email.
- [ ] Sending feedback delivers the email and records the row.

Then run the deeper script in `BETA_QA_SCRIPT.md`.

---

## 8. Known risks (not verified, most likely places for the first build to fail)

1. **Nothing native has ever been built.** See the note at the top.
2. **Old plugin majors on a new Android toolchain.** The Android project is on
   Android Gradle Plugin 9.1 / Gradle 9.3.1 / Kotlin 2.4, but `pubspec.yaml`
   holds `purchases_flutter` at 8.x, `firebase_core` at 3.x and
   `firebase_messaging` at 15.x, whose Gradle scripts predate that toolchain
   (`purchases_flutter` 8.11.0 uses `kotlinOptions { }`, `lintOptions { }`,
   Java 8 and compileSdk 34; `firebase_core` 3.15.2 uses `lintOptions { }` and
   compileSdk 34). They may fail at Gradle configuration. If so, the fix is to
   move to the current major versions of those three packages.
3. **Google Services Gradle plugin** was raised from 4.3.15 to 4.4.4 in
   `android/settings.gradle.kts` for AGP 9 compatibility. If the Android build
   fails in a `processReleaseGoogleServices` task, this line is the first
   place to look.
4. **iOS scene lifecycle and push.** The iOS project uses Flutter's new
   UIScene lifecycle (`SceneDelegate`), while `firebase_messaging` 15.2.10
   predates it. Notification taps on a cold start (`getInitialMessage`) are
   the feature most likely to be affected. Test it explicitly; upgrading
   `firebase_messaging` is the fix if it fails.
5. **CocoaPods + Swift Package Manager together.** `purchases_flutter` 8.11.0
   has no Swift package, so Flutter will generate a `Podfile` on the build
   machine and mix both systems. There is no `Podfile.lock` in the repo, so
   pod versions are resolved fresh on every build.
6. **Entitlements.** `ios/Runner/Runner.entitlements` (`aps-environment`) is
   now referenced by all three Runner build configurations. If the
   provisioning profile lacks Push Notifications the build fails at signing
   with a message naming `aps-environment` — fix the App ID and regenerate the
   profile (1.3).
7. **Push sound on iOS.** The push engine sends a plain `notification`
   payload with no `apns` sound, so iOS notifications arrive silently. Add
   `apns: { payload: { aps: { sound: "default" } } }` to the message in
   `supabase/functions/push-notification-engine/index.ts` if a sound is
   wanted.
8. **Android notification icon** `ic_stat_trellis` is a placeholder lattice
   glyph; replace with brand artwork when available.
9. **Dart obfuscation** is on for release builds. Keep the `*.symbols`
   artifacts of every released build; without them Dart stack traces from
   that build cannot be read.
