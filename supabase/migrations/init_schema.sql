-- =============================================================================
-- The Trellis — init_schema.sql
-- =============================================================================
-- Initial Supabase/Postgres schema, generated from the Flutter data models in
-- lib/models/ (runner_profile.dart, rule_item.dart, witness.dart,
-- canopy_rhythm.dart, church_roster_entry.dart, church_code.dart,
-- church_rhythm_metric.dart, prayer_item.dart, watched_prayer_item.dart,
-- watched_runner.dart, meeting_request.dart, check_in_entry.dart).
--
-- Design notes (translating the mock Flutter model to a real, multi-user
-- backend — read before extending this file):
--
-- 1. The Flutter app is single-profile-scoped and denormalizes a lot for
--    offline mock convenience: `WatchedRunner`, `WatchedRuleItem`,
--    `WatchedPrayerItem`, `WatchedMeetingRequest`, and `ChurchRosterEntry`
--    are all *read-only snapshots* a Runner's real data, from a Witness's or
--    Cloud Admin's point of view. In this schema there is only ONE canonical
--    copy of each entity (rule_items, prayer_items, meetings, check_ins) —
--    a Witness's "watched" view and the Cloud's "roster" view are both just
--    RLS-scoped reads of those same tables, never separate storage. Mirroring
--    the Watched* classes as their own tables would create duplicate,
--    driftable copies of the same data — the exact bug class RLS is meant to
--    prevent.
-- 2. `ChurchRhythmMetric` (title, completionRate) is not a stored table
--    either — it's the *output shape* of `get_congregational_health()` below,
--    computed live from real check_ins so the aggregate can never go stale
--    or be edited directly.
-- 3. `RunnerActivityEvent` (the Witness dashboard's "2 hours ago" feed) is a
--    derived UI projection, not persisted state, and is intentionally left
--    out of this schema — build it in the app layer from the tables below.
-- 4. Grace Mechanics (three consecutive missed Anchor Rhythm check-ins) is
--    reproduced as a real trigger on check_ins (see grace_nudges below),
--    matching RunnerProfile._fireGraceNudge/_consecutiveAnchorMisses exactly
--    — silent, never surfaced to the Runner, only ever queued for a Witness.
-- 5. Anything the Flutter code marks TODO(firebase-cloud-function) — e.g.
--    "removing a Witness under the accountability lock requires their
--    approval" — needs real workflow logic (a Supabase Edge Function or a
--    pending-request table + notification), not just an RLS policy. RLS can
--    only express "who can read/write which rows right now," not multi-step
--    approval flows, so those are called out below rather than faked.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 0. Extensions
-- -----------------------------------------------------------------------------
-- gen_random_uuid() ships via pgcrypto, already enabled by default on Supabase.
create extension if not exists "pgcrypto";


-- -----------------------------------------------------------------------------
-- 1. Enums (mirroring the Dart enums exactly)
-- -----------------------------------------------------------------------------
create type public.user_role as enum ('runner', 'witness', 'cloud');
create type public.membership_status as enum ('trial', 'active', 'cancelled');

-- RuleCategory (rule_item.dart)
create type public.rule_category as enum (
  'abiding_prayer', 'marriage_family', 'body_purity', 'work_rest', 'community_hospitality'
);

-- RuleFrequency (rule_item.dart)
create type public.rule_frequency as enum ('daily', 'weekly', 'monthly', 'annual');

-- PrayerCategory (prayer_item.dart)
create type public.prayer_category as enum ('witness_requests', 'people', 'situations');

-- MeetingStatus (meeting_request.dart)
create type public.meeting_status as enum ('pending_response', 'confirmed', 'declined');

-- Who proposed a meeting — drives which side is waiting on a response.
create type public.meeting_proposer as enum ('runner', 'witness');

-- witness_pairings.status — 'active' is the only status the Flutter model
-- (witness.dart) currently represents, but a real backend needs to track a
-- removal request separately from an outright delete (see
-- accountability_lock_enabled below), so this leaves room for that.
create type public.pairing_status as enum ('active', 'removed');


-- -----------------------------------------------------------------------------
-- 2. Churches (Cloud role's "canopy")
-- -----------------------------------------------------------------------------
create table public.churches (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null,
  rate_per_runner       numeric(10, 2) not null default 15.00,
  license_cap           integer not null default 50,
  annual_renewal_date   date not null default (current_date + interval '1 year')::date,
  created_at            timestamptz not null default now()
);
comment on table public.churches is
  'A church "canopy" a Cloud (Church Admin) role manages. active_license_count '
  'is intentionally not a stored column — see the active_license_count view below.';


-- -----------------------------------------------------------------------------
-- 3. Profiles (one row per auth.users row — runner_profile.dart)
-- -----------------------------------------------------------------------------
create table public.profiles (
  id                                  uuid primary key references auth.users (id) on delete cascade,
  name                                text not null,
  email                               text not null,
  role                                public.user_role not null default 'runner',
  membership_status                   public.membership_status not null default 'trial',
  church_id                           uuid references public.churches (id) on delete set null,
  is_church_affiliation_locked        boolean not null default false,

  -- Personal accountability-lock settings (Runner-only, but present for
  -- every role for schema simplicity).
  accountability_lock_enabled         boolean not null default false,
  -- True while a request to disable accountability_lock_enabled awaits a
  -- Witness's approval. NOTE: enforcing that approval step (a Runner cannot
  -- flip this to false themselves while pending) is workflow logic — model
  -- it as a `lock_removal_requests` table + Edge Function, not bare RLS.
  accountability_lock_removal_pending boolean not null default false,

  pairing_code                        text,
  daily_check_in_reminder             time not null default '20:00',
  has_committed_rule                  boolean not null default false,
  prayer_reminder_time                time not null default '07:00',
  has_completed_scheduling_setup      boolean not null default false,
  calendar_connected                  boolean not null default false,
  home_address                        text,
  work_address                        text,

  -- Map<NotificationCategory, bool> — small, fixed key set, so a JSONB bag
  -- is simpler here than a join table. Keys: anchor_rhythm_alerts,
  -- weekly_roll_up, meeting_requests, prayer_reminders.
  notification_preferences            jsonb not null default '{
    "anchor_rhythm_alerts": true,
    "weekly_roll_up": true,
    "meeting_requests": true,
    "prayer_reminders": true
  }'::jsonb,

  created_at                          timestamptz not null default now()
);
comment on table public.profiles is
  'One row per Supabase auth user. role determines which of the Runner/'
  'Witness/Cloud UIs and RLS policies apply to them.';

create index profiles_church_id_idx on public.profiles (church_id);


-- -----------------------------------------------------------------------------
-- 4. Witness pairings (witness.dart) — the relationship RLS hinges on
-- -----------------------------------------------------------------------------
create table public.witness_pairings (
  id           uuid primary key default gen_random_uuid(),
  runner_id    uuid not null references public.profiles (id) on delete cascade,
  witness_id   uuid not null references public.profiles (id) on delete cascade,
  paired_since timestamptz not null default now(),
  status       public.pairing_status not null default 'active',
  unique (runner_id, witness_id)
);
comment on table public.witness_pairings is
  'The Runner<->Witness relationship. Every RLS policy that grants a Witness '
  'visibility into "their paired Runner''s data" joins through this table.';

create index witness_pairings_runner_idx on public.witness_pairings (runner_id) where status = 'active';
create index witness_pairings_witness_idx on public.witness_pairings (witness_id) where status = 'active';


-- -----------------------------------------------------------------------------
-- 5. Rule of Life items (rule_item.dart)
-- -----------------------------------------------------------------------------
create table public.rule_items (
  id                  uuid primary key default gen_random_uuid(),
  runner_id           uuid not null references public.profiles (id) on delete cascade,
  category            public.rule_category not null,
  title               text not null,
  frequency           public.rule_frequency not null default 'daily',
  -- DateTime.monday..sunday, stored as 1..7 (ISO weekday), only meaningful
  -- when frequency = 'weekly'.
  weekly_days         smallint[] not null default '{}',
  is_anchor_rhythm    boolean not null default false,
  -- True for a Canopy Rhythm injected at church-code redemption — see
  -- canopy_rhythms below. Deliberately independent of is_anchor_rhythm: a
  -- church-mandated baseline is never automatically a Runner's own personal
  -- distress-signal rhythm.
  is_church_mandated  boolean not null default false,
  created_at          timestamptz not null default now(),
  constraint weekly_days_range check (weekly_days <@ array[1,2,3,4,5,6,7]::smallint[])
);

create index rule_items_runner_idx on public.rule_items (runner_id);


-- -----------------------------------------------------------------------------
-- 6. Daily check-ins (check_in_entry.dart)
-- -----------------------------------------------------------------------------
-- The Dart model stores one CheckInEntry per day with a
-- Map<ruleItemId, answeredYes>; normalized here to one row per
-- (rule item, day) so aggregation (and the k-anonymity function below) is a
-- plain GROUP BY instead of unpacking JSON.
create table public.check_ins (
  id             uuid primary key default gen_random_uuid(),
  runner_id      uuid not null references public.profiles (id) on delete cascade,
  rule_item_id   uuid not null references public.rule_items (id) on delete cascade,
  check_in_date  date not null,
  answered_yes   boolean not null,
  created_at     timestamptz not null default now(),
  unique (rule_item_id, check_in_date)
);
comment on table public.check_ins is
  'One row per rule item per day. check_in_date is the day being reported on '
  '(the Daily Check-In screen always looks back on "yesterday").';

create index check_ins_runner_date_idx on public.check_ins (runner_id, check_in_date desc);
create index check_ins_rule_item_date_idx on public.check_ins (rule_item_id, check_in_date desc);


-- -----------------------------------------------------------------------------
-- 7. Grace Mechanics (silent Grace Nudge log — never shown to the Runner)
-- -----------------------------------------------------------------------------
create table public.grace_nudges (
  id            uuid primary key default gen_random_uuid(),
  runner_id     uuid not null references public.profiles (id) on delete cascade,
  rule_item_id  uuid not null references public.rule_items (id) on delete cascade,
  message       text not null,
  created_at    timestamptz not null default now()
);
comment on table public.grace_nudges is
  'Fires when an Anchor Rhythm hits exactly three consecutive misses — see '
  'the trigger below. Intentionally never selectable by the Runner (RLS only '
  'grants their Witness(es) read access), matching '
  'RunnerProfile._fireGraceNudge''s "never a failure alert to the Runner '
  'themselves."';

create index grace_nudges_runner_idx on public.grace_nudges (runner_id);

-- Reproduces RunnerProfile._consecutiveAnchorMisses + _fireGraceNudge: after
-- a "No" check-in on an Anchor Rhythm, count consecutive misses (most recent
-- first) and queue exactly one Grace Nudge the moment that streak hits 3.
create or replace function public.handle_check_in_grace_nudge()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_anchor   boolean;
  v_title       text;
  v_streak      integer := 0;
  v_rec         record;
begin
  if new.answered_yes then
    return new;
  end if;

  select is_anchor_rhythm, title into v_is_anchor, v_title
  from public.rule_items
  where id = new.rule_item_id;

  if not coalesce(v_is_anchor, false) then
    return new;
  end if;

  for v_rec in
    select answered_yes
    from public.check_ins
    where rule_item_id = new.rule_item_id
    order by check_in_date desc
  loop
    exit when v_rec.answered_yes;
    v_streak := v_streak + 1;
  end loop;

  if v_streak = 3 then
    insert into public.grace_nudges (runner_id, rule_item_id, message)
    values (new.runner_id, new.rule_item_id, v_title || ' has been missed three days in a row.');
  end if;

  return new;
end;
$$;

create trigger check_ins_grace_nudge
  after insert on public.check_ins
  for each row
  execute function public.handle_check_in_grace_nudge();


-- -----------------------------------------------------------------------------
-- 8. Prayer items (prayer_item.dart) — the Runner's own Prayer Garden
-- -----------------------------------------------------------------------------
create table public.prayer_items (
  id                    uuid primary key default gen_random_uuid(),
  runner_id             uuid not null references public.profiles (id) on delete cascade,
  category              public.prayer_category not null,
  title                 text not null,
  details               text not null default '',
  phone_number          text,
  scripture             text,
  share_with_witnesses  boolean not null default false,
  is_answered           boolean not null default false,
  last_prayed_date      date,
  answered_date         date,
  created_at            timestamptz not null default now()
);

create index prayer_items_runner_idx on public.prayer_items (runner_id);


-- -----------------------------------------------------------------------------
-- 9. Witness's own private intercessions for a Runner (watched_prayer_item.dart)
-- -----------------------------------------------------------------------------
-- Deliberately a separate table from prayer_items, not a "visibility flag"
-- on it: per WatchedRunner.witnessPrayers, these are "not visible to the
-- Runner, and only editable by the Witness" — a stricter, opposite-direction
-- visibility rule than prayer_items.share_with_witnesses, so it needs its
-- own RLS policy rather than a shared one with a toggle.
create table public.witness_prayers (
  id                uuid primary key default gen_random_uuid(),
  witness_id        uuid not null references public.profiles (id) on delete cascade,
  runner_id         uuid not null references public.profiles (id) on delete cascade,
  title             text not null,
  details           text not null default '',
  is_answered       boolean not null default false,
  last_prayed_date  date,
  answered_date     date,
  created_at        timestamptz not null default now()
);

create index witness_prayers_witness_idx on public.witness_prayers (witness_id);
create index witness_prayers_runner_idx on public.witness_prayers (runner_id);


-- -----------------------------------------------------------------------------
-- 10. Meetings (meeting_request.dart + watched_runner.dart's WatchedMeetingRequest)
-- -----------------------------------------------------------------------------
-- One canonical row per meeting, shared by both sides — MeetingRequest and
-- WatchedMeetingRequest are just this same row viewed by the Runner vs. the
-- Witness in the Flutter mock.
create table public.meetings (
  id             uuid primary key default gen_random_uuid(),
  runner_id      uuid not null references public.profiles (id) on delete cascade,
  witness_id     uuid not null references public.profiles (id) on delete cascade,
  scheduled_time timestamptz not null,
  location       text not null,
  is_emergency   boolean not null default false,
  status         public.meeting_status not null default 'pending_response',
  -- e.g. "Coffee", "Lunch" — set when proposed via the activity-chip
  -- scheduling engine (witness_connect_screen.dart / connect_screen.dart).
  activity       text,
  proposed_by    public.meeting_proposer not null,
  created_at     timestamptz not null default now()
);

create index meetings_runner_idx on public.meetings (runner_id);
create index meetings_witness_idx on public.meetings (witness_id);


-- -----------------------------------------------------------------------------
-- 11. Church codes (church_code.dart)
-- -----------------------------------------------------------------------------
create table public.church_codes (
  id            uuid primary key default gen_random_uuid(),
  church_id     uuid not null references public.churches (id) on delete cascade,
  code          text not null unique,
  generated_at  timestamptz not null default now(),
  is_redeemed   boolean not null default false,
  redeemed_by   uuid references public.profiles (id) on delete set null,
  redeemed_at   timestamptz
);

create index church_codes_church_idx on public.church_codes (church_id);

-- Mirrors RunnerProfile.redeemChurchCode: validates + marks a code
-- redeemed, locks the caller's church affiliation, and injects that
-- church's Canopy Rhythms into the caller's Rule of Life as real,
-- church-mandated (never personal-anchor) rows — all in one transaction, so
-- a client never needs UPDATE rights on church_codes directly.
create or replace function public.redeem_church_code(p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_church_id uuid;
  v_rhythm    record;
begin
  -- A single UPDATE ... RETURNING both validates and claims the code
  -- atomically (Postgres's row lock during the UPDATE itself rules out a
  -- double-redemption race), rather than a separate SELECT ... FOR UPDATE
  -- followed by an UPDATE.
  update public.church_codes
     set is_redeemed = true, redeemed_by = auth.uid(), redeemed_at = now()
   where code = upper(trim(p_code)) and not is_redeemed
   returning church_id into v_church_id;

  if v_church_id is null then
    return false;
  end if;

  update public.profiles
     set church_id = v_church_id,
         is_church_affiliation_locked = true
   where id = auth.uid();

  for v_rhythm in
    select title, category, frequency
    from public.canopy_rhythms
    where church_id = v_church_id
  loop
    insert into public.rule_items (runner_id, category, title, frequency, is_church_mandated)
    values (auth.uid(), v_rhythm.category, v_rhythm.title, v_rhythm.frequency, true);
  end loop;

  return true;
end;
$$;


-- -----------------------------------------------------------------------------
-- 12. Canopy Rhythms (canopy_rhythm.dart)
-- -----------------------------------------------------------------------------
create table public.canopy_rhythms (
  id          uuid primary key default gen_random_uuid(),
  church_id   uuid not null references public.churches (id) on delete cascade,
  title       text not null,
  category    public.rule_category not null,
  frequency   public.rule_frequency not null default 'weekly',
  created_at  timestamptz not null default now(),
  unique (church_id, title)
);

create index canopy_rhythms_church_idx on public.canopy_rhythms (church_id);


-- =============================================================================
-- 13. Row-Level Security
-- =============================================================================
-- Helper functions first — every policy below is built from these three
-- checks: "is this me", "am I this Runner's active Witness", and "am I a
-- Cloud Admin of this Runner's/row's church". Declared SECURITY DEFINER +
-- STABLE so they can be reused inside policies without each policy
-- re-deriving the same join, and marked STABLE (not VOLATILE) so Postgres
-- can inline/cache them within one statement.

create or replace function public.is_witness_of(p_runner_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.witness_pairings
    where runner_id = p_runner_id
      and witness_id = auth.uid()
      and status = 'active'
  );
$$;

create or replace function public.is_cloud_admin_of_church(p_church_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role = 'cloud'
      and church_id = p_church_id
  );
$$;

-- Same as above, but keyed off a Runner's id rather than a church id
-- directly — used on tables that don't carry church_id themselves
-- (rule_items, prayer_items, meetings, ...).
create or replace function public.is_cloud_admin_of_runner(p_runner_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles admin_profile
    join public.profiles runner_profile on runner_profile.church_id = admin_profile.church_id
    where admin_profile.id = auth.uid()
      and admin_profile.role = 'cloud'
      and runner_profile.id = p_runner_id
      and admin_profile.church_id is not null
  );
$$;

alter table public.churches            enable row level security;
alter table public.profiles            enable row level security;
alter table public.witness_pairings    enable row level security;
alter table public.rule_items          enable row level security;
alter table public.check_ins           enable row level security;
alter table public.grace_nudges        enable row level security;
alter table public.prayer_items        enable row level security;
alter table public.witness_prayers     enable row level security;
alter table public.meetings            enable row level security;
alter table public.church_codes        enable row level security;
alter table public.canopy_rhythms      enable row level security;

-- --- churches ----------------------------------------------------------------
-- Names/codes aren't sensitive on their own (needed for sign-up flows), so
-- read access is broad; only that church's own Cloud Admin can change it.
create policy "churches_select_any_authenticated"
  on public.churches for select
  to authenticated
  using (true);

create policy "churches_update_own_cloud_admin"
  on public.churches for update
  to authenticated
  using (public.is_cloud_admin_of_church(id))
  with check (public.is_cloud_admin_of_church(id));

-- Church *creation* is intentionally not opened to the anon/authenticated
-- role here — provision new churches via a service-role Edge Function
-- alongside promoting the creating user's profile.role to 'cloud', so the
-- two never happen out of step.

-- --- profiles ------------------------------------------------------------
-- "Own data" + "their paired Runner's data" + a Cloud Admin's own roster
-- (both the Runners in their church AND those Runners' Witnesses, so the
-- Roster tab can render "Witnessed by ..." — a Witness's own church_id is
-- usually null, since they join via a pairing code, not a church code, so
-- that visibility has to route through witness_pairings instead).
create policy "profiles_select_self_paired_or_roster"
  on public.profiles for select
  to authenticated
  using (
    id = auth.uid()
    or public.is_witness_of(id)
    or public.is_cloud_admin_of_church(church_id)
    or exists (
      select 1 from public.witness_pairings wp
      where wp.witness_id = profiles.id
        and wp.status = 'active'
        and public.is_cloud_admin_of_runner(wp.runner_id)
    )
  );

create policy "profiles_update_self"
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Row creation happens via the handle_new_user trigger below (see §14),
-- run as the table owner — no direct client INSERT policy is needed.

-- --- witness_pairings ------------------------------------------------------
create policy "witness_pairings_select_own_side"
  on public.witness_pairings for select
  to authenticated
  using (runner_id = auth.uid() or witness_id = auth.uid());

create policy "witness_pairings_insert_own_side"
  on public.witness_pairings for insert
  to authenticated
  with check (runner_id = auth.uid() or witness_id = auth.uid());

-- NOTE: RunnerProfile.accountabilityLockEnabled means a Runner cannot
-- unilaterally drop a pairing without their Witness's approval — that
-- multi-step "request, then Witness approves" flow needs its own
-- pending-request table/Edge Function; this bare UPDATE policy only covers
-- the *unlocked* case (either side may end an unlocked pairing).
create policy "witness_pairings_update_own_side"
  on public.witness_pairings for update
  to authenticated
  using (runner_id = auth.uid() or witness_id = auth.uid())
  with check (runner_id = auth.uid() or witness_id = auth.uid());

-- --- rule_items --------------------------------------------------------------
-- A Witness "observes and responds — they don't edit the Runner's Rule of
-- Life" (watched_runner.dart), so they get SELECT only, never write.
create policy "rule_items_select_own_or_paired"
  on public.rule_items for select
  to authenticated
  using (runner_id = auth.uid() or public.is_witness_of(runner_id));

create policy "rule_items_write_own"
  on public.rule_items for insert
  to authenticated
  with check (runner_id = auth.uid());

create policy "rule_items_update_own"
  on public.rule_items for update
  to authenticated
  using (runner_id = auth.uid())
  with check (runner_id = auth.uid());

create policy "rule_items_delete_own"
  on public.rule_items for delete
  to authenticated
  using (runner_id = auth.uid());

-- --- check_ins -----------------------------------------------------------
-- A Witness's weekly heat map needs real check-in granularity for their
-- paired Runner (witness_rule_screen.dart's _WeekHeatMap) — but the Cloud
-- role gets none of this at the row level, only the k-anonymity-gated
-- aggregate via get_congregational_health() below, matching "specific daily
-- check-in data ... are never visible to the Cloud."
create policy "check_ins_select_own_or_paired"
  on public.check_ins for select
  to authenticated
  using (runner_id = auth.uid() or public.is_witness_of(runner_id));

create policy "check_ins_write_own"
  on public.check_ins for insert
  to authenticated
  with check (runner_id = auth.uid());

create policy "check_ins_update_own"
  on public.check_ins for update
  to authenticated
  using (runner_id = auth.uid())
  with check (runner_id = auth.uid());

-- --- grace_nudges ----------------------------------------------------------
-- Read-only from the client's perspective (rows are only ever written by
-- the trigger above, running as its owner) and — crucially — never
-- selectable by the Runner themselves.
create policy "grace_nudges_select_witness_only"
  on public.grace_nudges for select
  to authenticated
  using (public.is_witness_of(runner_id));

-- --- prayer_items ----------------------------------------------------------
create policy "prayer_items_select_own_or_shared"
  on public.prayer_items for select
  to authenticated
  using (
    runner_id = auth.uid()
    or (share_with_witnesses and public.is_witness_of(runner_id))
  );

create policy "prayer_items_write_own"
  on public.prayer_items for insert
  to authenticated
  with check (runner_id = auth.uid());

create policy "prayer_items_update_own"
  on public.prayer_items for update
  to authenticated
  using (runner_id = auth.uid())
  with check (runner_id = auth.uid());

create policy "prayer_items_delete_own"
  on public.prayer_items for delete
  to authenticated
  using (runner_id = auth.uid());

-- --- witness_prayers ---------------------------------------------------------
-- Owned end-to-end by the Witness who wrote them; the Runner has no access
-- at all, matching "not visible to the Runner, and only editable by the
-- Witness."
create policy "witness_prayers_all_own"
  on public.witness_prayers for all
  to authenticated
  using (witness_id = auth.uid())
  with check (witness_id = auth.uid());

-- --- meetings ----------------------------------------------------------------
create policy "meetings_select_either_side"
  on public.meetings for select
  to authenticated
  using (runner_id = auth.uid() or witness_id = auth.uid());

create policy "meetings_insert_either_side"
  on public.meetings for insert
  to authenticated
  with check (runner_id = auth.uid() or witness_id = auth.uid());

create policy "meetings_update_either_side"
  on public.meetings for update
  to authenticated
  using (runner_id = auth.uid() or witness_id = auth.uid())
  with check (runner_id = auth.uid() or witness_id = auth.uid());

-- --- church_codes --------------------------------------------------------
-- Deliberately NOT readable broadly, even for unredeemed codes: a code is a
-- bearer invite meant to be shared out-of-band with one specific person, not
-- something any authenticated user should be able to browse/enumerate.
-- Validating and redeeming one both go through redeem_church_code() above
-- (SECURITY DEFINER, so it looks the row up internally without needing a
-- SELECT policy) — the client calls that RPC directly and handles a `false`
-- result, rather than pre-checking via a raw SELECT.
create policy "church_codes_select_own_church_admin"
  on public.church_codes for select
  to authenticated
  using (public.is_cloud_admin_of_church(church_id));

create policy "church_codes_insert_own_church_admin"
  on public.church_codes for insert
  to authenticated
  with check (public.is_cloud_admin_of_church(church_id));

create policy "church_codes_delete_own_church_admin"
  on public.church_codes for delete
  to authenticated
  using (public.is_cloud_admin_of_church(church_id));

-- --- canopy_rhythms --------------------------------------------------------
-- Read-only for the whole congregation (a Runner should be able to see what
-- their church mandates); mutation is reserved for that church's Cloud
-- Admin via the Church Profile screen (church_profile_screen.dart) — never
-- from the read-only Congregational Health dashboard.
create policy "canopy_rhythms_select_own_church"
  on public.canopy_rhythms for select
  to authenticated
  using (
    public.is_cloud_admin_of_church(church_id)
    or exists (
      select 1 from public.profiles
      where id = auth.uid() and church_id = canopy_rhythms.church_id
    )
  );

create policy "canopy_rhythms_write_own_church_admin"
  on public.canopy_rhythms for insert
  to authenticated
  with check (public.is_cloud_admin_of_church(church_id));

create policy "canopy_rhythms_update_own_church_admin"
  on public.canopy_rhythms for update
  to authenticated
  using (public.is_cloud_admin_of_church(church_id))
  with check (public.is_cloud_admin_of_church(church_id));

create policy "canopy_rhythms_delete_own_church_admin"
  on public.canopy_rhythms for delete
  to authenticated
  using (public.is_cloud_admin_of_church(church_id));


-- =============================================================================
-- 14. New-user bootstrap
-- =============================================================================
-- Standard Supabase pattern: create the matching public.profiles row the
-- moment a new auth.users row appears, using whatever the client passed in
-- raw_user_meta_data at sign-up (name, role).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, name, email, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'name', ''),
    new.email,
    coalesce((new.raw_user_meta_data ->> 'role')::public.user_role, 'runner')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();


-- =============================================================================
-- 15. get_congregational_health — the k-anonymity-gated aggregate
-- =============================================================================
-- Mirrors cloud_insights_screen.dart's kAnonymityThreshold exactly: below 15
-- actively-tracked Runners, per-rhythm aggregates could be reverse-engineered
-- back to an individual, so nothing but the locked-state count is returned.
--
-- SECURITY DEFINER is what makes this safe to expose at all: it's the one
-- sanctioned path that reads across every Runner's check_ins in a church,
-- bypassing check_ins' own RLS internally — but only ever returns an
-- aggregate (title + rounded completion rate), never a raw row, and only
-- once the k=15 floor is met. Raw check-in rows stay exactly as
-- inaccessible to a Cloud Admin as check_ins' RLS policies say.
create or replace function public.get_congregational_health(p_church_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_threshold          constant integer := 15;
  v_tracked_runner_count integer;
  v_metrics            jsonb;
begin
  if not public.is_cloud_admin_of_church(p_church_id) then
    raise exception 'Not authorized to view Congregational Health for this church.';
  end if;

  -- "Actively tracking" = at least one real check-in in the trailing 30
  -- days, same window the metrics themselves are computed over.
  select count(distinct ci.runner_id)
    into v_tracked_runner_count
    from public.check_ins ci
    join public.profiles p on p.id = ci.runner_id
   where p.church_id = p_church_id
     and ci.check_in_date >= (current_date - interval '30 days');

  if v_tracked_runner_count < v_threshold then
    return jsonb_build_object(
      'is_locked', true,
      'tracked_runner_count', v_tracked_runner_count,
      'threshold', v_threshold,
      'metrics', '[]'::jsonb
    );
  end if;

  select coalesce(jsonb_agg(
           jsonb_build_object(
             'title', m.title,
             'completion_rate', m.completion_rate,
             'is_canopy_rhythm', m.is_canopy_rhythm
           )
           order by m.is_canopy_rhythm desc, m.completion_rate asc
         ), '[]'::jsonb)
    into v_metrics
    from (
      select
        ri.title,
        round(avg(case when ci.answered_yes then 1 else 0 end)::numeric, 4) as completion_rate,
        bool_or(cr.id is not null) as is_canopy_rhythm
      from public.check_ins ci
      join public.rule_items ri on ri.id = ci.rule_item_id
      join public.profiles p on p.id = ci.runner_id
      left join public.canopy_rhythms cr
        on cr.church_id = p_church_id and cr.title = ri.title
      where p.church_id = p_church_id
        and ci.check_in_date >= (current_date - interval '30 days')
      group by ri.title
    ) m;

  return jsonb_build_object(
    'is_locked', false,
    'tracked_runner_count', v_tracked_runner_count,
    'threshold', v_threshold,
    'metrics', v_metrics
  );
end;
$$;

grant execute on function public.get_congregational_health(uuid) to authenticated;
grant execute on function public.redeem_church_code(text) to authenticated;


-- =============================================================================
-- 16. Convenience view — Cloud Roster tab (church_roster_entry.dart)
-- =============================================================================
-- security_invoker means this view carries no privilege of its own — it
-- runs with the *querying user's* RLS, so a Cloud Admin only ever sees rows
-- their own profiles_select policy already allows, and a random Witness
-- querying it directly sees nothing extra beyond their own paired Runner.
create view public.church_roster
  with (security_invoker = true)
as
select
  p.id                                               as runner_id,
  p.name                                              as runner_name,
  p.church_id,
  (
    select max(ci.check_in_date)
    from public.check_ins ci
    where ci.runner_id = p.id
  )                                                    as last_check_in_date,
  coalesce((
    select avg(case when ci.answered_yes then 1 else 0 end)
    from public.check_ins ci
    join public.rule_items ri on ri.id = ci.rule_item_id
    where ri.runner_id = p.id
      and ci.check_in_date >= (current_date - interval '30 days')
  ), 0)                                                as vitality_score,
  coalesce((
    select jsonb_agg(jsonb_build_object('id', w.id, 'name', w.name))
    from public.witness_pairings wp
    join public.profiles w on w.id = wp.witness_id
    where wp.runner_id = p.id and wp.status = 'active'
  ), '[]'::jsonb)                                      as witnesses
from public.profiles p
where p.role = 'runner';

comment on view public.church_roster is
  'Backs the Cloud role''s Roster tab (cloud_roster_screen.dart). '
  'security_invoker = true, so it adds no access beyond what profiles_select '
  'already grants the querying user.';


-- =============================================================================
-- 17. Active license count (cloud_treasury_screen.dart)
-- =============================================================================
create view public.church_license_usage
  with (security_invoker = true)
as
select
  c.id as church_id,
  c.license_cap,
  count(p.id) as active_license_count
from public.churches c
left join public.profiles p
  on p.church_id = c.id and p.role = 'runner'
group by c.id, c.license_cap;
