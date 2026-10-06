# Calendar sharing — how it works (nothing to set up)

Runners and Witnesses can share when they are busy or free so that, when one of
them proposes a meeting, The Trellis suggests times when **both** are open.
Neither person ever sees the other's events — only shared open windows — and
The Trellis never holds a calendar account, token or event title.

Since migration 025 this works **from the phone itself**. There is no
third-party calendar service and nothing for the owner to configure.

```
Phone A ──reads its own calendars (EventKit / CalendarContract)──▶ busy blocks (start, end)
        ──replace_my_busy_blocks(blocks, window)──▶ calendar_busy_blocks (Postgres)

Phone A, proposing a meeting with B:
        ──get_pair_calendar(B, from, to)──▶ { other_connected, other_synced_at, other_busy[] }
        reads its OWN calendars again (fresh), intersects on the phone (sharedFreeWindows)
        ──▶ "Times you both have free" chips
```

## Where the pieces live

| Piece | File |
|---|---|
| Reading the phone's calendars, reducing events to busy blocks | `lib/services/device_calendars.dart` |
| Upload, refresh, stop sharing, "when are we both free?" | `lib/services/calendar_service.dart` |
| The intersection (pure, tested) | `lib/models/shared_free_windows.dart` |
| The sheet, link button and suggestion chips | `lib/widgets/calendar_connect_sheet.dart` |
| Table, RPCs, pairing check, removal of the old Cronofy objects | `supabase/migrations/025_device_calendars.sql` |
| Permission strings | `ios/Runner/Info.plist` (`NSCalendarsFullAccessUsageDescription`, `NSCalendarsUsageDescription`), `android/app/src/main/AndroidManifest.xml` (`READ_CALENDAR`, `WRITE_CALENDAR`) |

## What is shared, exactly

* Busy blocks for the next 21 days from the start of today: each a start and an
  end instant, merged where events overlap or touch, so the count of events is
  not recoverable. All-day events and events the calendar marks as *free* are
  skipped. Tentative events count as busy.
* `profiles.calendar_connected` and `profiles.calendar_synced_at` — whether and
  when the account last uploaded.
* `get_pair_calendar` answers only when the caller and the other person are in
  an **active** Witness pairing; for anyone else it says "not sharing", the
  same as a partner with no calendar, so it cannot be used to probe strangers.

## Freshness

The upload is redone whenever the app opens or returns to the foreground and
the last upload is more than six hours old, and whenever the person taps
"Refresh now". Someone who hasn't opened the app in days has stale blocks; the
suggestion chips say "last shared N days ago" when that is two days or more.

## Privacy policy wording (suggested)

> If you turn on calendar sharing, The Trellis reads the calendars on your
> phone and stores only the start and end times of your busy periods for the
> next three weeks, refreshed when you open the app. Your Witness or Runner
> sees only times you are both free — never what is on your calendar. You can
> stop sharing at any time, which deletes your busy periods from The Trellis.

## History

Before migration 025 this went through Cronofy (OAuth per provider, tokens in
Supabase Vault, four Edge Functions). That whole path — tables, functions,
Vault secrets and the `CRONOFY_*` / `CALENDAR_*` secrets — is gone. If you
still have those secrets set in the Supabase project, unset them:

```
supabase secrets unset CRONOFY_CLIENT_ID CRONOFY_CLIENT_SECRET CRONOFY_DATA_CENTER CALENDAR_OAUTH_REDIRECT_URI CALENDAR_STATE_SECRET CALENDAR_RESULT_REDIRECT_URL
```

The hosted `result.html` page can be taken down as well.
