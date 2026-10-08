# The Trellis — Privacy Policy (draft for unhinderedlives.com/privacy)

> **For the website chat:** this is a complete replacement draft of the
> privacy policy for **The Trellis** app, written to match what the app
> actually does as of October 2026. Publish it at
> `https://unhinderedlives.com/privacy` (the app links there). The section
> "Consumer Health Data" also belongs on
> `https://unhinderedlives.com/consumer-health-data` (the app links there
> too). Replace the bracketed items. It is a plain-language draft, not legal
> advice — have counsel review it before launch, particularly the
> consumer-health-data and children sections.
>
> **What changed since the last version** (so you can tell readers): calendar
> sharing now reads busy/free times from the calendars on the phone (no
> calendar account is connected and no third-party calendar service is
> used); "sins to throw off" can be part of a Rule of Life; meeting-place
> suggestions use home/work locations; Witnesses are notified when a Runner
> goes quiet, hasn't started, may have removed the app, or deletes their
> account; prayer photos; church leaders' view; gift codes.

**Effective date:** [date]
**Who we are:** The Trellis is provided by Unhindered Lives [legal entity name,
state, address] ("we", "us"). Contact: **support@unhinderedlives.com**.

## 1. The short version

- The Trellis helps you keep a Rule of Life and walk alongside others. Much of
  what you put in it is personal, so we collect only what the app needs, we
  never sell it, and we never use it for advertising.
- **You decide who sees what.** Your Witness sees your Rule of Life and how
  you are keeping it. Your church's leaders (only if you join your church)
  see a summary, never your daily answers or your prayers. Nobody else sees
  your information.
- You can delete your account and everything in it at any time from the app.

## 2. What we collect, and why

**Account.** Your name, email address, password (stored only as a secure
hash by our authentication provider), and your mobile number. Your mobile
number is required: it is shown only to the people you are paired with — your
Witness, or the Runners you walk with — so they can text you. If you enter a
church name or a code from your church or organization, we keep that too.

**Your Rule of Life.** The rhythms you choose (for example "read Scripture" or
"keep a weekly Sabbath"), any **sins you choose to throw off** (for example
"looking at pornography" or "getting drunk"), how often each is due, which are
Anchor Rhythms, the date you committed your Rule, and each daily **yes/no
check-in**. This is the heart of the app. Because some of it can reveal
information about your health, habits or struggles, we treat all of it as
sensitive (see "Consumer Health Data" below).

**Prayer lists.** The people and situations you pray for, any details and
Scripture you add, when you last prayed, and whether a prayer was answered.
You may add a **photo** for a person on your list; photos are stored
privately and shown only to you. A Witness may keep prayers for the Runners
they walk with, and a Runner may share prayer requests with their Witness.

**Meetings and meeting places.** Meetings you propose or accept (date, time,
place, activity). If you choose to, your **home and work addresses**. To
suggest a place halfway between you and the person you are meeting, your
phone converts *your own* addresses to map coordinates (rounded to about
100 metres) and our server computes a midpoint rounded to about a kilometre.
**The other person never receives your address or your coordinates** — only
the name and address of a suggested coffee shop or restaurant.

**Calendar (only if you turn on calendar sharing).** With your permission, the
app reads the calendars synced to your phone and uploads **only the start and
end times of your busy periods** for the next three weeks — never the title,
location, attendees or notes of any event. These are refreshed when you open
the app and are used only to show you and the person you are meeting times
when you are both free. Turning sharing off deletes them from our servers.
(The app reads only calendars synced to your phone's own Calendar app.)

**Activity used for Witness alerts.** We record when you last opened the app.
If you are a Runner with a Witness and you haven't opened the app for a few
days, our server sends your phone a silent, invisible check once a day; if your
phone reports the app is no longer installed, we let your Witness know you may
have stepped away. These signals are used only to send those alerts and are
**not shown to anyone**.

**Notifications.** A push-notification token for your device, your
notification choices, and your reminder times. Daily check-in and prayer
reminders are scheduled on your phone itself.

**Purchases and codes.** If you subscribe, Apple (or Google) processes the
payment; we receive only whether your membership is active — never your card
details. If a gift code is redeemed for your account on our website, we
record that it was redeemed and which account it went to. If someone buys a
gift code on our website, we keep the purchaser's email address with the code.

**Feedback and support.** If you send feedback or a support request, we
receive what you write and basic device information (app version, device
model, operating system). You choose whether to include your email address so
we can reply.

**App usage analytics.** We collect limited, pseudonymous usage events (for
example "a rhythm was completed", the number of rhythms in a Rule, which role
is being viewed) to improve the app. These are tied to a hashed identifier,
not your name or email, and never include the text of your rhythms, prayers
or check-ins. [If the PostHog "discard client IP" setting is not switched on:
our analytics provider may derive an approximate location from your IP
address.]

## 3. Who can see your information

- **Your Witness(es)** — the people you invite with a pairing key — see your
  name and phone number, your Rule of Life (including any sins to throw off),
  your check-ins and how you're keeping each rhythm, missed Anchor Rhythms,
  prayer requests you share with them, and meetings with them. They are told
  when you miss an Anchor Rhythm, haven't started your Rule, have gone quiet
  for a few days, may have removed the app, or have deleted your account. A
  Witness never sees your private prayer photos, your addresses or calendar
  details, or when you last opened the app.
- **Runners you walk with** (if you are a Witness) see your name, phone number
  and the meetings and prayers you share with them.
- **Your church or organization's leaders** — only if you join your church
  with its code and agree to share — see a summary in their "Cloud": that you
  are a member, who your Witness is, a summary status of how you are doing over
  the season (for example "Flourishing" or "Drooping"), how long since your last
  check-in, aggregate percentages for the church's shared rhythms, and your
  contact details so they can reach out. **They never see your daily answers,
  the text of your rhythms, your sins to throw off, or your prayers.**
- **Nobody else.** We do not sell or rent personal information, and we do not
  share it for advertising.

## 4. Service providers

We use these companies to run the app. Each processes data only on our
behalf, under their own security and privacy commitments:

- **Supabase** — database, sign-in, file storage and server functions
  [region].
- **Google Firebase Cloud Messaging** — delivers push notifications.
- **Google Maps Platform (Places)** — address suggestions while typing, turning
  your own addresses into map coordinates, and finding meeting places near a
  midpoint.
- **Apple App Store / Google Play** and **RevenueCat** — subscriptions.
- **PostHog** — pseudonymous usage analytics.
- **Resend** — delivers feedback and support emails to us.

We may also disclose information if required by law, to protect the safety of
any person, or as part of a merger or sale of the service (in which case this
policy continues to apply).

## 5. How long we keep it

We keep your information for as long as your account exists. Calendar busy
times are replaced every time your phone refreshes them and cover only the
coming three weeks. When you **delete your account** (Settings → Delete
Account), we delete your profile, Rule of Life, check-ins, prayers, photos,
meetings, addresses, calendar data and pairings. Your Witnesses are told that
you left; to do that we keep **only your first name** in their notice, for at
most 30 days. Backups held by our providers are overwritten on their normal
schedule.

## 6. Your choices and rights

- **See and change** most of your information in the app at any time.
- **Turn off** calendar sharing, notifications, or individual alerts in the
  app; remove your addresses under Meeting Places.
- **Remove a Witness** in the app. A church connection made with a church code
  is locked in the app; email us to remove it.
- **Delete** your account and its data in the app, or ask us at
  support@unhinderedlives.com.
- Depending on where you live (for example California, Washington, Colorado,
  Virginia, or the EU/UK) you may have rights to access, correct, delete or
  receive a copy of your data, and to appeal a decision we make about a
  request. Email us; we respond within the time the law requires. We will not
  treat you differently for exercising these rights.

## 7. Security

Data is encrypted in transit; access is limited by database rules so that each
person can reach only their own data and the data shared with them. Prayer
photos are stored in a private store and shown through short-lived links.
No system is perfectly secure; if a breach affects you we will tell you as the
law requires.

## 8. Children

The Trellis is not directed to children under 13 [or 16 — confirm with
counsel], and we do not knowingly collect their information. If you believe a
child has given us information, contact us and we will delete it.

## 9. Changes

If we change this policy in a way that matters, we will tell you in the app or
by email before the change takes effect.

## 10. Contact

Unhindered Lives — support@unhinderedlives.com — [mailing address]

---

## Consumer Health Data (for unhinderedlives.com/consumer-health-data)

Some information in The Trellis may be "consumer health data" under laws such
as Washington's My Health My Data Act — for example rhythms about sleep,
exercise, fasting or sobriety, **sins you choose to throw off** (such as
pornography or drunkenness), your check-ins, and prayer requests about health.

- **What we collect and why:** the Rule of Life, sins to throw off, check-ins
  and prayers described above, solely to provide The Trellis to you and to the
  people you choose to share it with.
- **Consent:** we collect it only with the consent you give when you create
  your account. We share it beyond your own account only (a) with the Witness
  you invite, and (b) in summary form with your church's leaders, and only if
  you separately agree when joining your church.
- **Sources:** you, and the people you are paired with (for example a Witness's
  prayer for you).
- **We never sell consumer health data**, and we do not use it for advertising.
- **Your rights:** confirm whether we have it, see it, delete it, and withdraw
  consent — in the app or at support@unhinderedlives.com. Deleting your account
  deletes it.
- **Processors:** the service providers listed in section 4.
