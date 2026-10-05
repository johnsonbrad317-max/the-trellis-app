-- =============================================================================
-- The Trellis — 021_beta_feedback.sql   (changes that came out of beta feedback)
-- =============================================================================
-- Run AFTER 020. Idempotent — safe to run more than once.
--
-- What this file does, in plain English:
--
--   A. Phone number at sign-up. The app now sends the new person's phone number
--      with their name and role; the sign-up trigger stores it on their profile.
--
--   B. Remembers WHEN a Rule of Life was committed (profiles.rule_committed_at).
--      Committing is now a one-way step for the app: it cannot be un-committed
--      and the app cannot write the timestamp itself.
--
--   C. A committed rhythm becomes "set" after 7 days. After that, changing or
--      removing it needs a Witness to approve an unlock (which opens a 24-hour
--      window). A Runner with no active Witness is never locked, because nobody
--      could approve. Adding rhythms is always allowed.
--
--   D. The Cloud "Needs Attention" list never names a Runner who has not
--      committed a Rule of Life, and never counts days before the commitment
--      as days of inactivity.
--
--   E. A weekly roll-up for Witnesses: one row per Runner/Witness pair per
--      week ("kept 5 of 7"), produced every Tuesday by a scheduled job, and a
--      push notification for each row.
--
--   F. Prayer photos: a photo_path column on prayer_items and a PRIVATE storage
--      bucket in which each person can only reach their own folder.
--
--   G. Documents the notification_preferences keys in use.
--
--   H. Verification queries (bottom of the file).
--
-- ALSO REQUIRED ALONGSIDE THIS FILE (not SQL):
--   * Redeploy two Edge Functions after running it:
--       supabase functions deploy push-notification-engine --no-verify-jwt
--       supabase functions deploy delete-account
--     (the engine learns the 'weekly_roll_up' event; delete-account removes a
--     person's prayer photos before deleting the account).
--   * Section E needs the pg_cron extension. If it is not enabled, the rest of
--     this file still applies and section E.5 prints what to do.
--
-- EXISTING APP BUILDS: nothing here breaks a build that is already installed
-- on the day it runs — every existing committed Runner is given a fresh 7 days
-- (section B's backfill). After those 7 days an OLD build that tries to edit or
-- remove a set rhythm gets the refusal from section C as a raw error, so the
-- build that understands locks should be out within that week.
--
-- RE-RUNNING OLDER FILES: 011 and 019 contain earlier versions of three things
-- this file replaces (handle_new_user, guard_rule_item_update and the
-- unlock-request insert policy in 011; guard_prayer_item_update in 019). If
-- either of those files is ever run again, run this file again afterwards.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- A. Phone number at sign-up
-- -----------------------------------------------------------------------------
-- 011's version of this function, unchanged except for the phone number: same
-- role restriction (sign-up can only ever create a Runner or a Witness), same
-- error handling.
--
-- The app sends `phone` in the sign-up metadata as an E.164 string such as
-- +18165551234. A phone number must never be the reason a sign-up fails, so
-- anything that is not clearly a phone number is stored as NULL instead of
-- raising:
--   * spaces, dashes and parentheses are stripped first ("+1 (816) 555-1234"
--     is accepted and stored as +18165551234);
--   * what is left must be an optional leading + followed by 7 to 15 digits
--     (15 is the longest number the E.164 standard allows, so the stored value
--     is never longer than 16 characters — nothing is ever truncated, because a
--     truncated phone number is a wrong phone number);
--   * missing, blank, letters, a + anywhere but the front, too short, too long
--     -> NULL.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role  public.user_role;
  v_phone text;
begin
  v_role := case lower(coalesce(new.raw_user_meta_data ->> 'role', ''))
              when 'witness' then 'witness'::public.user_role
              else 'runner'::public.user_role
            end;

  v_phone := regexp_replace(
               coalesce(new.raw_user_meta_data ->> 'phone', ''),
               '[[:space:]()-]', '', 'g'
             );
  if v_phone !~ '^\+?[0-9]{7,15}$' then
    v_phone := null;
  end if;

  insert into public.profiles (id, name, email, role, phone_number)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'name', ''),
    new.email,
    v_role,
    v_phone
  );

  return new;
exception when others then
  raise exception 'handle_new_user failed for auth.users.id=%: % (SQLSTATE %)',
    new.id, sqlerrm, sqlstate;
end;
$$;
-- (The on_auth_user_created trigger from init_schema/010 already calls this.
--  profiles.phone_number has existed since 002 and 011 already lets its owner
--  read and update it, so no grant changes are needed here.)


-- -----------------------------------------------------------------------------
-- B. When a Rule of Life was committed
-- -----------------------------------------------------------------------------
alter table public.profiles
  add column if not exists rule_committed_at timestamptz;

comment on column public.profiles.rule_committed_at is
  'When has_committed_rule last went from false to true. Set by the database '
  '(profiles_rule_commit trigger), never by a client. Rhythm locks (021 C), the '
  'Cloud triage list (021 D) and the weekly roll-up (021 E) all count from it.';

-- Why a small trigger of its own rather than more lines in guard_profile_update
-- (011/019): this one has to do something for EVERY writer (stamp the time,
-- including when a server-side function commits a rule), while that guard only
-- ever refuses things for clients. Keeping it separate also means a re-run of
-- 019 — which re-creates guard_profile_update — cannot silently remove it.
--
-- BEFORE triggers on a table fire in name order: profiles_guard_update (011)
-- runs first, then profiles_rule_commit.
--
-- Not SECURITY DEFINER on purpose: like the other guards it tells a client
-- from the server by looking at current_user, which a definer function would
-- hide. It calls no helper functions, so there is no EXECUTE privilege to trip
-- over.
create or replace function public.guard_rule_commit()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    -- Profiles are created uncommitted by handle_new_user; this only matters
    -- if the server ever inserts one that is already committed.
    if new.has_committed_rule and new.rule_committed_at is null then
      new.rule_committed_at := now();
    end if;
    return new;
  end if;

  if current_user in ('authenticated', 'anon') then
    -- Committing is one-way from the app. (Otherwise un-committing and
    -- re-committing would hand out a fresh 7 days of free editing on demand.)
    if old.has_committed_rule and not new.has_committed_rule then
      raise exception 'A committed Rule of Life can''t be un-committed.'
        using errcode = '42501';
    end if;

    -- Layer 2 for the column grant (clients have no UPDATE grant on it either).
    if new.rule_committed_at is distinct from old.rule_committed_at then
      raise exception 'That profile field can only be changed by The Trellis itself.'
        using errcode = '42501';
    end if;
  end if;

  -- false -> true: stamp the moment. (If a server-side writer sets its own
  -- timestamp in the same statement — a data repair, say — that is respected.
  -- A client can never do that; it was refused just above.)
  if new.has_committed_rule and not old.has_committed_rule
     and new.rule_committed_at is not distinct from old.rule_committed_at then
    new.rule_committed_at := now();
  end if;

  return new;
end;
$$;

-- Explicit grants. A trigger function cannot be called directly by anyone
-- (Postgres refuses: "trigger functions can only be called as triggers"), so
-- EXECUTE for signed-in users exposes nothing. It is kept for them on purpose:
-- this trigger fires inside their own UPDATE, and a guard that every profile
-- save depends on should not rest on an untested assumption about when
-- Postgres does and does not check EXECUTE.
revoke execute on function public.guard_rule_commit() from public, anon;
grant  execute on function public.guard_rule_commit() to authenticated, service_role;

drop trigger if exists profiles_rule_commit on public.profiles;
create trigger profiles_rule_commit
  before insert or update on public.profiles
  for each row execute function public.guard_rule_commit();

-- Backfill: everyone who had already committed is treated as having committed
-- now. That gives each of them a fresh 7 days before their rhythms become set —
-- intended. (Runs as the migration owner, so the guards above do not apply; it
-- is not a false -> true change, so the trigger does not touch it. On a re-run
-- there is nothing left to update.)
update public.profiles
   set rule_committed_at = now()
 where has_committed_rule
   and rule_committed_at is null;

-- 011 gives clients column-by-column SELECT on profiles, so a new column is
-- invisible until it is granted. Who can see WHICH profile rows is unchanged
-- (yourself, your Runner if you are their Witness, your church's members if you
-- are its Cloud admin). No UPDATE grant: clients must not write it.
grant select (rule_committed_at) on public.profiles to authenticated;


-- -----------------------------------------------------------------------------
-- C. A committed rhythm becomes "set" after 7 days
-- -----------------------------------------------------------------------------
-- The product rule:
--   * Adding rhythms is always allowed.
--   * For 7 days after committing the Rule of Life, the Runner may freely edit
--     or remove any rhythm that is not a church (DNA) rhythm. A rhythm added
--     later gets its own 7 days from the moment it was added.
--   * After that the rhythm is "set": its title, frequency, weekly_days and
--     is_anchor_rhythm cannot be changed, and it cannot be removed, UNLESS
--       (a) the Runner has no active Witness (nobody could approve — the same
--           reasoning 019 uses for the accountability lock), or
--       (b) a Witness approved an unlock request for that rhythm within the
--           last 24 hours.
--   * Church (DNA) rhythms keep their existing behaviour: locked from day one
--     until a Witness approves an unlock (003/011). Once unlocked they are
--     ordinary rhythms and follow the rules above.

-- C.1  The 24-hour window a Witness's approval opens.
alter table public.rule_items
  add column if not exists unlocked_until timestamptz;

comment on column public.rule_items.unlocked_until is
  'Set to now() + 24 hours when a Witness approves an unlock request for this '
  'rhythm (apply_unlock_request_approval). While it is in the future the rhythm '
  'can be edited or removed even though it is "set". Clients can read it, never '
  'write it.';

-- Reading: rule_items still has the table-wide SELECT from 002 (011 only
-- narrowed UPDATE), so the owner and their Witness — the two people the RLS
-- policy rule_items_select_own_or_paired admits — can already read the new
-- column. Stated here anyway so this file is correct on its own.
grant select (unlocked_until) on public.rule_items to authenticated;
-- Writing: 011 limits client UPDATE to title, frequency, weekly_days and
-- is_anchor_rhythm, so the column cannot be updated by a client. INSERT is
-- still table-wide, which is what C.4 below closes.

-- C.2  "Is this rhythm locked right now?"
--
-- locked  <=>  the owner has committed their Rule of Life
--          and at least 7 days have passed since the LATER of that commitment
--              and the rhythm's own creation
--          and the owner has at least one active Witness
--          and there is no approved unlock window still open.
--
-- Returns NULL when the rhythm does not exist or the caller is not allowed to
-- know (see below) — the two cases look the same on purpose.
--
-- About privileges (the lesson from 018): the guard triggers below run as the
-- signed-in user, and Postgres checks EXECUTE on any function they call against
-- THAT user. So this helper must be executable by `authenticated`, and because
-- it is SECURITY DEFINER (it has to read the owner's profile and pairings
-- whatever RLS says), anyone signed in can also call it directly through the
-- API with any rhythm id. It therefore answers only for the rhythm's owner or
-- one of their active Witnesses — the two people who can already read that
-- rhythm — and says NULL to everyone else. (The service role / SQL editor has
-- no auth.uid() and may ask about any rhythm.)
create or replace function public.rule_item_is_locked(p_rule_item_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_runner_id      uuid;
  v_created_at     timestamptz;
  v_unlocked_until timestamptz;
  v_committed      boolean;
  v_committed_at   timestamptz;
begin
  select ri.runner_id, ri.created_at, ri.unlocked_until
    into v_runner_id, v_created_at, v_unlocked_until
    from public.rule_items ri
   where ri.id = p_rule_item_id;

  if not found then
    return null;
  end if;

  if auth.uid() is not null
     and v_runner_id is distinct from auth.uid()
     and not public.is_witness_of(v_runner_id) then
    return null;
  end if;

  select p.has_committed_rule, p.rule_committed_at
    into v_committed, v_committed_at
    from public.profiles p
   where p.id = v_runner_id;

  return coalesce(v_committed, false)
     and v_committed_at is not null
     and now() >= greatest(v_committed_at, v_created_at) + interval '7 days'
     and exists (
           select 1 from public.witness_pairings wp
            where wp.runner_id = v_runner_id and wp.status = 'active'
         )
     and not (v_unlocked_until is not null and v_unlocked_until > now());
end;
$$;

revoke execute on function public.rule_item_is_locked(uuid) from public, anon;
grant  execute on function public.rule_item_is_locked(uuid) to authenticated, service_role;

-- C.3  Editing a rhythm. 011's guard with two additions; everything it did
--      before, it still does, with the same messages:
--        * created_at, unlocked_until and id join the fields a client can never
--          change (clients have no UPDATE grant on them either — this is the
--          second layer, as for the other fields);
--        * a rhythm that is "set" cannot have its four editable fields changed.
--      If the helper declines to answer (NULL), the rhythm is treated as
--      locked: that can only mean the caller is neither the owner nor their
--      Witness, and such a caller has no business editing it.
create or replace function public.guard_rule_item_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.id                  is distinct from old.id
       or new.runner_id        is distinct from old.runner_id
       or new.category         is distinct from old.category
       or new.is_church_mandated is distinct from old.is_church_mandated
       or new.created_at       is distinct from old.created_at
       or new.unlocked_until   is distinct from old.unlocked_until then
      raise exception 'That field on a rhythm can''t be changed directly.'
        using errcode = '42501';
    end if;

    if    new.title            is distinct from old.title
       or new.frequency        is distinct from old.frequency
       or new.weekly_days      is distinct from old.weekly_days
       or new.is_anchor_rhythm is distinct from old.is_anchor_rhythm then

      if old.is_church_mandated then
        raise exception 'This is a DNA Rhythm; ask your Witness to unlock it first.'
          using errcode = '42501';
      end if;

      if coalesce(public.rule_item_is_locked(old.id), true) then
        raise exception 'This rhythm is set. Ask a Witness to unlock it before changing it.'
          using errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end;
$$;
-- (011's rule_items_guard_update trigger already calls this function. It stays
--  an invoker-rights function: it has to see the real current_user.)

-- C.4  Adding a rhythm. Always allowed — but INSERT on rule_items is
--      table-wide for clients, so without this a client could create a rhythm
--      with an unlock window already open, or dated in the future (a rhythm
--      whose "first 7 days" never end). The app sends neither field, so both
--      are simply set by the database for client inserts. Server-side writers
--      (redeem_church_code, DNA propagation, the SQL editor) are untouched.
--      Fires before rule_items_normalize (019) — name order — which is fine:
--      that one only fills in weekly_days.
create or replace function public.guard_rule_item_insert()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.created_at     := now();
    new.unlocked_until := null;
  end if;
  return new;
end;
$$;

-- (Grants: same reasoning as guard_rule_commit in section B.)
revoke execute on function public.guard_rule_item_insert() from public, anon;
grant  execute on function public.guard_rule_item_insert() to authenticated, service_role;

drop trigger if exists rule_items_guard_insert on public.rule_items;
create trigger rule_items_guard_insert
  before insert on public.rule_items
  for each row execute function public.guard_rule_item_insert();

-- C.5  Removing a rhythm. A client cannot delete a rhythm that is set.
--      (A church rhythm is already undeletable by clients: 011's delete policy
--      hides it, so that delete removes nothing and never reaches this trigger.)
--
--      This can NOT get in the way of deleting an account, in two independent
--      ways: the check only applies when current_user is a client role, and
--      account deletion is done by the service role; and the rows removed by
--      the profile -> rule_items cascade are deleted by Postgres's own
--      foreign-key machinery, which runs as the table's owner, not as the
--      person who started it.
create or replace function public.guard_rule_item_delete()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if coalesce(public.rule_item_is_locked(old.id), true) then
      raise exception 'This rhythm is set. Ask a Witness to unlock it before removing it.'
        using errcode = '42501';
    end if;
  end if;
  return old;
end;
$$;

-- (Grants: same reasoning as guard_rule_commit in section B.)
revoke execute on function public.guard_rule_item_delete() from public, anon;
grant  execute on function public.guard_rule_item_delete() to authenticated, service_role;

drop trigger if exists rule_items_guard_delete on public.rule_items;
create trigger rule_items_guard_delete
  before delete on public.rule_items
  for each row execute function public.guard_rule_item_delete();

-- C.6  Asking for an unlock. 011's policy, minus one line: the rhythm no longer
--      has to be a church rhythm — a Runner may ask a Witness to unlock ANY
--      rhythm of their own. Still required: the request is the caller's own,
--      starts as 'pending', names one of the caller's ACTIVE Witnesses, and
--      points at a rhythm the caller owns (never someone else's).
drop policy if exists "unlock_requests_insert_by_runner" on public.pending_unlock_requests;
create policy "unlock_requests_insert_by_runner"
  on public.pending_unlock_requests for insert
  to authenticated
  with check (
    runner_id = auth.uid()
    and status = 'pending'
    and exists (
      select 1 from public.witness_pairings wp
      where wp.runner_id  = auth.uid()
        and wp.witness_id = pending_unlock_requests.witness_id
        and wp.status = 'active'
    )
    and exists (
      select 1 from public.rule_items ri
      where ri.id = pending_unlock_requests.rule_item_id
        and ri.runner_id = auth.uid()
    )
  );

comment on table public.pending_unlock_requests is
  'A Runner asking a specific Witness for permission to change or remove a '
  'rhythm that is locked — a church (DNA) rhythm, or any rhythm that has become '
  '"set" (021). Approval clears is_church_mandated and opens a 24-hour window '
  '(rule_items.unlocked_until) via the apply_unlock_request_approval trigger.';

-- C.7  What an approval does. As 003: a church rhythm stops being mandated.
--      New: a 24-hour window opens in which the Runner can change or remove the
--      rhythm. (SECURITY DEFINER, as before: the approving Witness has no write
--      access to rule_items, and the guards above only stop clients.)
create or replace function public.apply_unlock_request_approval()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'approved' and old.status = 'pending' then
    update public.rule_items
       set is_church_mandated = false,
           unlocked_until     = now() + interval '24 hours'
     where id = new.rule_item_id;
  end if;
  return new;
end;
$$;
-- (003's apply_unlock_request_approval trigger already calls this.)


-- -----------------------------------------------------------------------------
-- D. No alerts for a Runner who has not committed
-- -----------------------------------------------------------------------------
-- 013's get_cloud_triage (no later file replaced it), same return shape, with
-- the smallest change that does the job:
--
--   * Only Runners who have committed a Rule of Life (has_committed_rule, with
--     a rule_committed_at) are considered at all. Someone still setting up can
--     no longer appear as struggling, isolated or dormant, and their Witness
--     cannot appear under witness_alerts because of them.
--
--   * dormant: days of inactivity are counted only AFTER the day the rule was
--     committed. The clock starts at the later of the last check-in and the
--     commitment day, so nobody is "7 days without a check-in" until 7 days
--     after committing, and days_since_check_in never includes days from
--     before the commitment. (For anyone whose check-ins all came after they
--     committed — the normal case — the numbers are exactly what they were.)
--
-- Not changed: the score behind "struggling" (it already counts each rhythm
-- only from its first check-in — 014), and "isolated" (days in the church
-- without a Witness is not a count of missed days).
create or replace function public.get_cloud_triage(p_church_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_struggle_below constant numeric := 0.45;
  v_stale_days     constant integer := 7;
begin
  if not public.is_cloud_admin_of_church(p_church_id) then
    raise exception 'Not authorized to view triage for this church.' using errcode = '42501';
  end if;

  return (
    with members as (
      select p.id, p.name,
             coalesce(cc.redeemed_at, p.created_at)::date as joined_on,
             p.rule_committed_at::date                    as committed_on
      from public.profiles p
      left join lateral (
        select c.redeemed_at
        from public.church_codes c
        where c.redeemed_by = p.id and c.church_id = p_church_id
        order by c.redeemed_at desc
        limit 1
      ) cc on true
      where p.church_id = p_church_id
        -- 021: a Runner who has not committed is never listed.
        and p.has_committed_rule
        and p.rule_committed_at is not null
    ),
    scored as (
      select m.id, m.name, m.joined_on, m.committed_on,
             (a.an ->> 'score')::numeric        as score,
             (a.an ->> 'has_data')::boolean     as has_data,
             (a.an ->> 'is_drooping')::boolean  as is_drooping,
             (select max(ci.check_in_date) from public.check_ins ci where ci.runner_id = m.id)
               as last_check_in,
             (select count(*) from public.witness_pairings wp
               where wp.runner_id = m.id and wp.status = 'active') as witness_count
      from members m
      cross join lateral (select public._runner_analytics(m.id) as an) a
    ),
    struggling as (
      select * from scored
      where has_data and (score < v_struggle_below or is_drooping)
    ),
    witness_alerts as (
      select w.id, w.name,
             count(*) as runner_count,
             bool_or(wp.church_data_consent) as consent,
             case when bool_or(wp.church_data_consent) then max(w.phone_number) end as phone_number,
             case when bool_or(wp.church_data_consent) then max(w.email) end as email
      from struggling s
      join public.witness_pairings wp on wp.runner_id = s.id and wp.status = 'active'
      join public.profiles w on w.id = wp.witness_id
      group by w.id, w.name
    )
    select jsonb_build_object(
      'struggling', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'runner_id', s.id, 'name', s.name,
                 'score', round(s.score, 4), 'is_drooping', s.is_drooping
               ) order by s.score, s.name)
        from struggling s
      ), '[]'::jsonb),
      'isolated', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'runner_id', s.id, 'name', s.name,
                 'days_in_church', current_date - s.joined_on
               ) order by s.joined_on, s.name)
        from scored s
        where s.witness_count = 0 and s.joined_on <= current_date - v_stale_days
      ), '[]'::jsonb),
      'dormant', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'runner_id', s.id, 'name', s.name,
                 'days_since_check_in',
                   case when s.last_check_in is null then null
                        -- 021: only days after the commitment count.
                        else current_date - greatest(s.last_check_in, s.committed_on) end
               ) order by s.last_check_in nulls first, s.name)
        from scored s
        -- 021: both clocks start no earlier than the day the rule was committed.
        where (s.last_check_in is null
               and greatest(s.joined_on, s.committed_on) <= current_date - v_stale_days)
           or (s.last_check_in is not null
               and greatest(s.last_check_in, s.committed_on) < current_date - v_stale_days)
      ), '[]'::jsonb),
      'witness_alerts', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'witness_id', a.id, 'name', a.name, 'runner_count', a.runner_count,
                 'consent', a.consent, 'phone_number', a.phone_number, 'email', a.email
               ) order by a.runner_count desc, a.name)
        from witness_alerts a
      ), '[]'::jsonb),
      'thresholds', jsonb_build_object(
        'struggling_below', v_struggle_below,
        'stale_days', v_stale_days
      )
    )
  );
end;
$$;

revoke execute on function public.get_cloud_triage(uuid) from public, anon;
grant  execute on function public.get_cloud_triage(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- E. Weekly roll-up for Witnesses
-- -----------------------------------------------------------------------------
-- E.1  One row per Runner/Witness pair per week (Monday to Sunday). It carries
--      two numbers and nothing else — never a rhythm's name, never which days.
create table if not exists public.weekly_roll_ups (
  id                 uuid primary key default gen_random_uuid(),
  runner_id          uuid not null references public.profiles (id) on delete cascade,
  witness_id         uuid not null references public.profiles (id) on delete cascade,
  -- The Monday the week began on.
  week_start         date not null,
  -- How many rhythm-days were due that week, and how many were kept.
  rhythms_scheduled  integer not null,
  rhythms_kept       integer not null,
  created_at         timestamptz not null default now(),
  unique (runner_id, witness_id, week_start),
  constraint weekly_roll_ups_counts_sane
    check (rhythms_kept >= 0 and rhythms_kept <= rhythms_scheduled)
);
comment on table public.weekly_roll_ups is
  'A Witness''s weekly summary of one Runner: rhythm-days due and kept in a '
  'Monday-Sunday week. Written only by generate_weekly_roll_ups() (pg_cron job '
  'trellis-weekly-roll-up); each new row triggers a weekly_roll_up push.';

create index if not exists weekly_roll_ups_witness_idx
  on public.weekly_roll_ups (witness_id, week_start desc);

alter table public.weekly_roll_ups enable row level security;

-- A Witness reads the roll-ups addressed to them, for as long as they are still
-- that Runner's active Witness. (The second half goes one step further than
-- "witness_id is me": once a pairing ends, the former Witness stops seeing that
-- Runner's past numbers, like everything else about the Runner.) The Runner
-- gets no policy: this is the Witness's summary. Nobody writes from the client.
drop policy if exists "weekly_roll_ups_select_by_witness" on public.weekly_roll_ups;
create policy "weekly_roll_ups_select_by_witness"
  on public.weekly_roll_ups for select
  to authenticated
  using (witness_id = auth.uid() and public.is_witness_of(runner_id));

-- New tables get no default grants in this project — say exactly who gets what.
revoke all on public.weekly_roll_ups from public, anon, authenticated;
grant select on public.weekly_roll_ups to authenticated;
grant all    on public.weekly_roll_ups to service_role;

-- E.2  The generator. Returns how many roll-ups it wrote.
--
--   p_week_start  any date inside the week wanted (it is moved back to that
--                 week's Monday). Omitted = the Monday-to-Sunday week that
--                 ended most recently before today, by the UTC calendar.
--                 A week that has not finished yet is refused, because a
--                 half-week total would be stored as that week's roll-up.
--
--   For every ACTIVE pairing whose Runner has committed a Rule of Life, counts
--   the Runner's rhythm-days that week:
--     scheduled = each day a rhythm was due, by the same recurrence the app and
--                 the scoring functions use (013/014): daily = every day;
--                 weekly = its weekly_days (ISO weekdays, Monday = 1);
--                 monthly = the 1st; annual = January 1st —
--                 counting only days strictly AFTER the day the Rule of Life
--                 was committed and on or after the day the rhythm was created;
--     kept      = those days with a check-in answered "Yes".
--   A pairing with nothing scheduled gets no row (and so no notification).
--   Running it twice for the same week writes nothing the second time.
--
--   The count uses each rhythm's schedule as it is when the job runs, and
--   rhythms deleted since are not counted.
--
--   SECURITY DEFINER because it reads every Runner's rhythms and check-ins.
--   Clients cannot call it: only the scheduled job (which runs as the database
--   owner) and the service role can.
create or replace function public.generate_weekly_roll_ups(p_week_start date default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today      date := (now() at time zone 'utc')::date;
  v_week_start date;
  v_count      integer;
begin
  if p_week_start is null then
    -- Monday of the current week, minus 7 days = Monday of the last full week.
    v_week_start := v_today - (extract(isodow from v_today)::integer - 1) - 7;
  else
    v_week_start := p_week_start - (extract(isodow from p_week_start)::integer - 1);
  end if;

  if v_week_start + 6 >= v_today then
    raise exception 'The week starting % has not ended yet.', v_week_start
      using errcode = '22023';
  end if;

  insert into public.weekly_roll_ups
    (runner_id, witness_id, week_start, rhythms_scheduled, rhythms_kept)
  select wp.runner_id, wp.witness_id, v_week_start, t.scheduled, t.kept
    from public.witness_pairings wp
    join public.profiles p on p.id = wp.runner_id
    cross join lateral (
      select count(*)::integer                              as scheduled,
             (count(*) filter (where ci.answered_yes))::integer as kept
        from public.rule_items ri
        cross join lateral (
          select v_week_start + g.n as day
            from generate_series(0, 6) as g(n)
        ) d
        left join public.check_ins ci
          on ci.rule_item_id = ri.id and ci.check_in_date = d.day
       where ri.runner_id = wp.runner_id
         and d.day >  (p.rule_committed_at at time zone 'utc')::date
         and d.day >= (ri.created_at at time zone 'utc')::date
         and case ri.frequency
               when 'daily'   then true
               when 'weekly'  then extract(isodow from d.day)::smallint = any (ri.weekly_days)
               when 'monthly' then extract(day from d.day) = 1
               when 'annual'  then extract(month from d.day) = 1 and extract(day from d.day) = 1
             end
    ) t
   where wp.status = 'active'
     and p.has_committed_rule
     and p.rule_committed_at is not null
     and t.scheduled > 0
  on conflict (runner_id, witness_id, week_start) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.generate_weekly_roll_ups(date) from public, anon, authenticated;
grant  execute on function public.generate_weekly_roll_ups(date) to service_role;

-- E.3  Each new roll-up asks the push engine to tell the Witness — the same
--      trigger function every other notification uses (004, hardened in 011),
--      so a missing Vault secret or a network problem only skips the push; it
--      can never undo the roll-up itself.
drop trigger if exists notify_push_on_weekly_roll_up on public.weekly_roll_ups;
create trigger notify_push_on_weekly_roll_up
  after insert on public.weekly_roll_ups
  for each row execute function public.notify_push_engine('weekly_roll_up');

-- E.4  Muting. A Witness turns this off with the existing key `weekly_roll_up`
--      in their own profiles.notification_preferences (false = no push; absent
--      or true = push). The roll-up row is still written either way, so it can
--      be shown in the app.

-- E.5  The schedule: every TUESDAY at 13:00 UTC (8 a.m. US Central in summer,
--      7 a.m. in winter), job name `trellis-weekly-roll-up`.
--
--      Why Tuesday and not Monday: the app's Daily Check-In looks back on
--      "yesterday", so Sunday is answered on Monday. Run on Monday morning,
--      the roll-up would count Sunday as not kept for almost everyone ("6 of
--      7" for a faithful Runner). By Tuesday morning Monday's check-in — the
--      one that reports on Sunday — has had a full day to be made. The week
--      summarised is still the last FINISHED Monday-to-Sunday week.
--
--      Wrapped so that a project without pg_cron still gets everything else in
--      this file. If the notice below appears: Dashboard -> Database ->
--      Extensions -> enable pg_cron, then run this one DO block again.
do $do$
declare
  v_jobid bigint;
begin
  create extension if not exists pg_cron;

  -- Start clean: remove any earlier job of this name before scheduling.
  for v_jobid in
    select jobid from cron.job where jobname = 'trellis-weekly-roll-up'
  loop
    perform cron.unschedule(v_jobid);
  end loop;

  perform cron.schedule(
    'trellis-weekly-roll-up',
    '0 13 * * 2',
    'select public.generate_weekly_roll_ups();'
  );

  raise notice '021: weekly roll-up scheduled (job trellis-weekly-roll-up, Tuesdays 13:00 UTC).';
exception when others then
  raise notice '021: the weekly roll-up job was NOT scheduled: % (SQLSTATE %).', sqlerrm, sqlstate;
  raise notice '021: to fix: Dashboard -> Database -> Extensions -> enable pg_cron, then re-run the DO block in section E.5 of 021_beta_feedback.sql. Nothing else in this file depends on it.';
end
$do$;


-- -----------------------------------------------------------------------------
-- F. Prayer photos
-- -----------------------------------------------------------------------------
-- F.1  Where a prayer's photo lives in storage: `<owner's user id>/<prayer id>.jpg`
--      inside the private bucket below, or NULL for no photo.
alter table public.prayer_items
  add column if not exists photo_path text;

comment on column public.prayer_items.photo_path is
  'Object path inside the private prayer-photos bucket '
  '(<owner user id>/<prayer item id>.jpg), or null. Set and cleared by the owner.';

-- Can the owner write the new column? Yes, nothing to fix: prayer_items still
-- has the table-wide INSERT/UPDATE from 002 (no later file narrowed it to
-- particular columns), so a new column is writable by whoever the row policies
-- admit — the owner.
--
-- Can a Witness change it? Under 019's guard: YES, which is wrong. That guard
-- listed the fields a Witness may NOT change, so a column added later slipped
-- through. Rewritten the other way round: it now names the three fields a
-- Witness MAY change (is_answered, last_prayed_date, answered_date — "prayed"
-- and "answered") and refuses a change to anything else, including photo_path
-- and any column added in future. For the columns that existed before, the
-- result and the messages are the same as 019's.
create or replace function public.guard_prayer_item_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.runner_id is distinct from old.runner_id
       or new.created_at is distinct from old.created_at then
      raise exception 'That field on a prayer can''t be changed.' using errcode = '42501';
    end if;

    -- Anyone other than the Runner who owns it (i.e. their Witness, admitted
    -- by prayer_items_update_shared_by_witness) may change only these three.
    if auth.uid() is distinct from old.runner_id
       and (to_jsonb(new) - array['is_answered', 'last_prayed_date', 'answered_date'])
           is distinct from
           (to_jsonb(old) - array['is_answered', 'last_prayed_date', 'answered_date']) then
      raise exception 'A Witness can only mark a shared prayer as prayed or answered.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
-- (019's prayer_items_guard_update trigger already calls this.)

-- F.2  The bucket: private (no public URLs), 5 MB per file, images only.
--      If a bucket of this name already exists it is made private and given
--      these limits, rather than left as it was — a public prayer-photos bucket
--      must not survive this migration.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'prayer-photos',
  'prayer-photos',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
  set public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- F.3  Who can touch the files. Each signed-in person can read, add, replace
--      and delete objects ONLY inside the folder named after their own user id.
--      A Witness gets NO access to photos in this version — not even for a
--      prayer shared with them (they can see that a shared prayer has a
--      photo_path, but cannot open it). The service role (delete-account)
--      bypasses these policies.
drop policy if exists "prayer_photos_select_own_folder" on storage.objects;
create policy "prayer_photos_select_own_folder"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'prayer-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "prayer_photos_insert_own_folder" on storage.objects;
create policy "prayer_photos_insert_own_folder"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'prayer-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "prayer_photos_update_own_folder" on storage.objects;
create policy "prayer_photos_update_own_folder"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'prayer-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'prayer-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "prayer_photos_delete_own_folder" on storage.objects;
create policy "prayer_photos_delete_own_folder"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'prayer-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );


-- -----------------------------------------------------------------------------
-- G. profiles.notification_preferences — the keys in use
-- -----------------------------------------------------------------------------
-- No schema change: it is one JSON object per person, and a missing key always
-- means "on". Recorded on the column so the list travels with the database.
--
--   anchor_rhythm_alerts  Witness. Alerts about a Runner's Anchor Rhythm.
--   weekly_roll_up        Witness. Receive the weekly roll-up push (section E).
--                         false = the push engine does not send it.
--   meeting_requests      Meeting and prayer requests (the push engine checks
--                         it for support_request).
--   prayer_reminders      On-device prayer reminder; the server never reads it.
--   check_in_reminder     On-device daily check-in reminder; the server never
--                         reads it. Absent = on.
comment on column public.profiles.notification_preferences is
  'JSON object of notification switches; a missing key means ON. Keys: '
  'anchor_rhythm_alerts (Witness), weekly_roll_up (Witness: receive the weekly '
  'roll-up push), meeting_requests, prayer_reminders (on-device), '
  'check_in_reminder (on-device; absent = on).';


-- =============================================================================
-- H. VERIFICATION — run in the SQL editor and compare with "expect"
-- =============================================================================
-- Several blocks act as a signed-in user with `set local role` (as 018/019 do).
-- Replace the <...> placeholders with real test ids. A block that ends in an
-- expected ERROR must be run on its own: the error aborts that transaction, and
-- the `rollback;` on its last line cleans up.
--
-- 0. Privileges at a glance. Expect, in order:
--    false, true,  true     rule_item_is_locked: not anon; signed-in users; service role
--    false, false, true     generate_weekly_roll_ups: clients no; service role yes
--    true,  false           rule_committed_at: clients can read it, cannot write it
--    true,  false           unlocked_until: clients can read it, cannot write it
--    true,  false, true     weekly_roll_ups: clients read (RLS narrows), never write; service role writes
--
--   select has_function_privilege('anon',          'public.rule_item_is_locked(uuid)', 'execute'),
--          has_function_privilege('authenticated', 'public.rule_item_is_locked(uuid)', 'execute'),
--          has_function_privilege('service_role',  'public.rule_item_is_locked(uuid)', 'execute');
--   select has_function_privilege('anon',          'public.generate_weekly_roll_ups(date)', 'execute'),
--          has_function_privilege('authenticated', 'public.generate_weekly_roll_ups(date)', 'execute'),
--          has_function_privilege('service_role',  'public.generate_weekly_roll_ups(date)', 'execute');
--   select has_column_privilege('authenticated', 'public.profiles', 'rule_committed_at', 'select'),
--          has_column_privilege('authenticated', 'public.profiles', 'rule_committed_at', 'update');
--   select has_column_privilege('authenticated', 'public.rule_items', 'unlocked_until', 'select'),
--          has_column_privilege('authenticated', 'public.rule_items', 'unlocked_until', 'update');
--   select has_table_privilege('authenticated', 'public.weekly_roll_ups', 'select'),
--          has_table_privilege('authenticated', 'public.weekly_roll_ups', 'insert'),
--          has_table_privilege('service_role',  'public.weekly_roll_ups', 'insert');
--
-- A. Phone at sign-up. The trigger function now mentions the phone:
--      select pg_get_functiondef('public.handle_new_user()'::regprocedure) like '%phone_number%';   -- true
--    The clean-up rule, checked on its own (expect the right-hand column):
--      select input,
--             case when regexp_replace(input, '[[:space:]()-]', '', 'g') ~ '^\+?[0-9]{7,15}$'
--                  then regexp_replace(input, '[[:space:]()-]', '', 'g') end as stored
--        from (values ('+18165551234'),          -- +18165551234
--                     ('+1 (816) 555-1234'),     -- +18165551234
--                     ('8165551234'),            -- 8165551234
--                     (''),                      -- null
--                     ('call me'),               -- null
--                     ('816+5551234'),           -- null
--                     ('+123456789012345678'))   -- null (too long)
--             as t(input);
--    End to end: sign up a new test account from the app with a phone number, then
--      select name, role, phone_number from public.profiles order by created_at desc limit 1;
--
-- B. Commit timestamp.
--    Nobody committed is missing a date (expect 0):
--      select count(*) from public.profiles where has_committed_rule and rule_committed_at is null;
--    Committing stamps it (use a test Runner who has NOT committed; expect a
--    timestamp of "now" from the second statement; nothing is kept):
--      begin;
--      set local role authenticated;
--      select set_config('request.jwt.claims', '{"sub":"<uncommitted-runner-uuid>","role":"authenticated"}', true);
--      update public.profiles set has_committed_rule = true where id = auth.uid();
--      select has_committed_rule, rule_committed_at from public.profiles where id = auth.uid();
--      rollback;
--    A client cannot un-commit (use a Runner who HAS committed; expect
--    ERROR 42501 "A committed Rule of Life can't be un-committed."):
--      begin;
--      set local role authenticated;
--      select set_config('request.jwt.claims', '{"sub":"<committed-runner-uuid>","role":"authenticated"}', true);
--      update public.profiles set has_committed_rule = false where id = auth.uid();
--      rollback;
--    A client cannot write the timestamp (expect ERROR 42501 permission denied):
--      begin;
--      set local role authenticated;
--      select set_config('request.jwt.claims', '{"sub":"<committed-runner-uuid>","role":"authenticated"}', true);
--      update public.profiles set rule_committed_at = now() - interval '30 days' where id = auth.uid();
--      rollback;
--
-- C. The lock. Use a committed Runner WITH an active Witness and one of their
--    own (non-church) rhythms. Each block first makes the commitment and the
--    rhythm look 8 days old — as the SQL editor's own role, which the guards
--    let through — and rolls everything back at the end.
--
--    C-1. A set rhythm cannot be changed. Expect: true, then
--         ERROR 42501 "This rhythm is set. Ask a Witness to unlock it before changing it."
--      begin;
--      update public.profiles   set rule_committed_at = now() - interval '8 days' where id = '<runner-uuid>';
--      update public.rule_items set created_at = now() - interval '8 days', unlocked_until = null
--       where id = '<rule-item-uuid>';
--      set local role authenticated;
--      select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--      select public.rule_item_is_locked('<rule-item-uuid>');
--      update public.rule_items set title = 'changed' where id = '<rule-item-uuid>';
--      rollback;
--
--    C-2. ...nor removed. Same block with the last statement replaced by
--         (expect ERROR 42501 "This rhythm is set. Ask a Witness to unlock it before removing it."):
--      delete from public.rule_items where id = '<rule-item-uuid>';
--
--    C-3. Adding is always allowed, and a new rhythm starts unlocked whatever
--         the client sends. Same setup as C-1, then (expect one row with
--         created_at = now, unlocked_until = null, locked = false):
--      insert into public.rule_items (runner_id, category, title, frequency, created_at, unlocked_until)
--      values (auth.uid(), 'abiding_prayer', '021 probe', 'daily', now() - interval '1 year', now() + interval '1 year')
--      returning created_at, unlocked_until, public.rule_item_is_locked(id) as locked;
--
--    C-4. A Witness's approval opens 24 hours. Expect: true (locked), then after
--         the approval false, an unlocked_until about 24 hours ahead, and the
--         final update succeeding (UPDATE 1).
--      begin;
--      update public.profiles   set rule_committed_at = now() - interval '8 days' where id = '<runner-uuid>';
--      update public.rule_items set created_at = now() - interval '8 days', unlocked_until = null
--       where id = '<rule-item-uuid>';
--      set local role authenticated;
--      select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--      select public.rule_item_is_locked('<rule-item-uuid>');
--      insert into public.pending_unlock_requests (runner_id, witness_id, rule_item_id)
--      values (auth.uid(), '<witness-uuid>', '<rule-item-uuid>');     -- allowed for a non-church rhythm now
--      select set_config('request.jwt.claims', '{"sub":"<witness-uuid>","role":"authenticated"}', true);
--      update public.pending_unlock_requests set status = 'approved'
--       where rule_item_id = '<rule-item-uuid>' and status = 'pending';
--      select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--      select public.rule_item_is_locked('<rule-item-uuid>'), unlocked_until
--        from public.rule_items where id = '<rule-item-uuid>';
--      update public.rule_items set title = title || ' (edited)' where id = '<rule-item-uuid>';
--      rollback;
--      -- (Nothing is sent: the push request queued by the insert is rolled back too.)
--
--    C-5. A Runner with NO active Witness is never locked. Same setup as C-1
--         for such a Runner; expect false, and the update succeeds.
--
--    C-6. A stranger learns nothing. As any other signed-in user (expect NULL):
--      begin;
--      set local role authenticated;
--      select set_config('request.jwt.claims', '{"sub":"<unrelated-user-uuid>","role":"authenticated"}', true);
--      select public.rule_item_is_locked('<rule-item-uuid>');
--      rollback;
--
--    C-7. The triggers are in place (expect the three rule_items_guard_* rows
--         plus rule_items_normalize, and profiles_guard_update + profiles_rule_commit):
--      select tgrelid::regclass as table_name, tgname
--        from pg_trigger
--       where not tgisinternal and tgrelid in ('public.rule_items'::regclass, 'public.profiles'::regclass)
--       order by 1, 2;
--
-- D. Triage. As a Cloud admin (expect: nobody in any list has
--    has_committed_rule = false; compare the names with the second query):
--      begin;
--      set local role authenticated;
--      select set_config('request.jwt.claims', '{"sub":"<cloud-admin-uuid>","role":"authenticated"}', true);
--      select jsonb_pretty(public.get_cloud_triage('<church-uuid>'));
--      rollback;
--      select name, has_committed_rule, rule_committed_at
--        from public.profiles where church_id = '<church-uuid>' order by name;
--    Straight after this migration the dormant list is empty for 7 days (every
--    committed Runner's clock was just restarted by the backfill in B).
--
-- E. Weekly roll-up.
--    The job exists (expect one row: schedule `0 13 * * 1`, active = true). If
--    this errors with "relation cron.job does not exist", pg_cron is not
--    enabled — see section E.5:
--      select jobid, jobname, schedule, command, active
--        from cron.job where jobname = 'trellis-weekly-roll-up';
--    After its first Monday, how the runs went:
--      select status, return_message, start_time
--        from cron.job_run_details
--       where jobid = (select jobid from cron.job where jobname = 'trellis-weekly-roll-up')
--       order by start_time desc limit 5;
--
--    By hand, as the SQL editor's own role:
--      select public.generate_weekly_roll_ups();
--    Expect: the number of active Runner/Witness pairs whose Runner had at
--    least one rhythm due last week (Monday-Sunday, UTC) on a day AFTER the day
--    they committed. RIGHT AFTER THIS MIGRATION THAT IS 0, because the backfill
--    dated every commitment today. A second call always returns 0 (a week is
--    only ever written once).
--
--    To see real numbers without waiting a week and without sending anything,
--    backdate one test Runner's commitment inside a transaction and roll back
--    (the rows AND the push requests they queued are discarded):
--      begin;
--      update public.profiles set rule_committed_at = now() - interval '30 days' where id = '<runner-uuid>';
--      select public.generate_weekly_roll_ups();                          -- >= 1 if they have an active Witness
--      select week_start, rhythms_scheduled, rhythms_kept
--        from public.weekly_roll_ups where runner_id = '<runner-uuid>';   -- e.g. 7 scheduled for one daily rhythm
--      rollback;
--    For a real end-to-end push test, end that block with `commit;` instead and
--    watch Edge Functions -> push-notification-engine -> Logs.
--
--    A week that is not over is refused (expect ERROR 22023 "...has not ended yet."):
--      select public.generate_weekly_roll_ups(current_date);
--
--    Clients: a Witness sees only their own rows; a client can never write.
--      begin;
--      set local role authenticated;
--      select set_config('request.jwt.claims', '{"sub":"<witness-uuid>","role":"authenticated"}', true);
--      select count(*) filter (where witness_id <> auth.uid()) from public.weekly_roll_ups;   -- 0
--      select public.generate_weekly_roll_ups();                                              -- ERROR 42501 permission denied
--      rollback;
--
-- F. Prayer photos.
--    The bucket is private with the limits (expect false, 5242880, {image/jpeg,image/png,image/webp}):
--      select public, file_size_limit, allowed_mime_types from storage.buckets where id = 'prayer-photos';
--    The four policies exist (expect 4 rows: DELETE, INSERT, SELECT, UPDATE):
--      select policyname, cmd from pg_policies
--       where schemaname = 'storage' and tablename = 'objects' and policyname like 'prayer_photos_%'
--       order by 1;
--    A Witness cannot change a shared prayer's photo (expect ERROR 42501
--    "A Witness can only mark a shared prayer as prayed or answered."), but
--    can still mark it prayed — run the second update in its own block (UPDATE 1):
--      begin;
--      set local role authenticated;
--      select set_config('request.jwt.claims', '{"sub":"<witness-uuid>","role":"authenticated"}', true);
--      update public.prayer_items set photo_path = 'x/y.jpg'
--       where runner_id = '<runner-uuid>' and share_with_witnesses;
--      rollback;
--      -- update public.prayer_items set last_prayed_date = current_date
--      --  where runner_id = '<runner-uuid>' and share_with_witnesses;
--    The owner can set and clear it (expect UPDATE 1 twice):
--      begin;
--      set local role authenticated;
--      select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--      update public.prayer_items set photo_path = auth.uid()::text || '/' || id::text || '.jpg'
--       where id = '<prayer-item-uuid>';
--      update public.prayer_items set photo_path = null where id = '<prayer-item-uuid>';
--      rollback;
--    Photo folders that belong to nobody (expect 0 rows; a row here means an
--    account was deleted while photo clean-up failed — remove that folder in
--    Dashboard -> Storage -> prayer-photos):
--      select (storage.foldername(o.name))[1] as folder, count(*) as files
--        from storage.objects o
--       where o.bucket_id = 'prayer-photos'
--         and not exists (select 1 from public.profiles p
--                          where p.id::text = (storage.foldername(o.name))[1])
--       group by 1;
--
-- G. The documented keys:
--      select col_description('public.profiles'::regclass,
--               (select attnum from pg_attribute
--                 where attrelid = 'public.profiles'::regclass and attname = 'notification_preferences'));
-- =============================================================================
