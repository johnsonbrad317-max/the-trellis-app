-- =============================================================================
-- The Trellis — 012_roster_dna_scheduling_role.sql  (Phase 2)
-- =============================================================================
-- Builds on 011_security_lockdown.sql. Three independent fixes:
--
--   A. set_my_role(): the only way to change profiles.role now that 011 made
--      the column read-only to clients. Limited to runner <-> witness.
--
--   B. DNA Rhythm scheduling. A church's DNA Rhythm defaults to weekly, but
--      dna_rhythms had no weekly_days, so redeem_church_code() injected
--      weekly rule_items with an empty day set. RuleItem.scheduledFor() reads
--      "weekly + no days" as "never due" — those rhythms never reached the
--      Daily Check-In, never produced a check_in row, and so never fed the
--      Witness heat map or Congregational Health. Fixed at the source:
--        * dna_rhythms.weekly_days (the Cloud admin picks the days)
--        * a normalizing trigger: a weekly rhythm can never be saved without
--          days (defaults to Sunday, ISO 7), non-weekly never carries days
--        * redeem_church_code() copies the days into the Runner's rule_item
--        * edits to a DNA Rhythm propagate to Runners' mandated copies
--        * one-time backfill of every existing row
--
--   C. church_roster for Cloud admins. The view was security_invoker, so its
--      subqueries on check_ins / rule_items / witness_pairings ran under the
--      Cloud admin's own RLS — which (correctly) grants them none of that —
--      so every Runner read as 0% vitality, "999 days since check-in", and
--      "No Active Witness". It now runs with the owner's rights but only ever
--      returns rows for the church the caller administers, and still exposes
--      only what the roster screen shows: name, contact, an aggregate vitality
--      number, last check-in DATE, and consent-gated Witness contact. Raw
--      check_ins / rule_items / pairings stay as closed to a Cloud admin as
--      before. It also stops filtering on role = 'runner': role is a cosmetic
--      Runner/Witness view toggle, and with set_my_role() persisting it, a
--      church member who switched to Witness view would otherwise vanish from
--      the roster and the license count.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 0. Schema drift: profiles.consumer_health_data_consent
-- -----------------------------------------------------------------------------
-- 009 was meant to add this column but the live database never got it (which
-- is why 011's grants had to drop it to run at all). Add it here, then give the
-- client back exactly the column access 011 intended: it may read it (the app
-- loads it at sign-in) and write it (recordConsumerHealthDataConsent). It is
-- deliberately NOT in guard_profile_update's protected list, so the consent a
-- user records is theirs to set. `not null default false` matches 009's intent
-- and backfills existing rows to "not yet consented".
alter table public.profiles
  add column if not exists consumer_health_data_consent boolean not null default false;

grant select (consumer_health_data_consent) on public.profiles to authenticated;
grant update (consumer_health_data_consent) on public.profiles to authenticated;


-- -----------------------------------------------------------------------------
-- A. set_my_role
-- -----------------------------------------------------------------------------
create or replace function public.set_my_role(p_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := lower(trim(coalesce(p_role, '')));
begin
  if auth.uid() is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  -- Cloud is never a role value (it is the cloud_admin_church_id grant).
  if v_role not in ('runner', 'witness') then
    raise exception 'Role must be runner or witness.' using errcode = '22023';
  end if;

  -- Runs as the function owner, so profiles' guard trigger (which only blocks
  -- direct client writes) lets this one column through.
  update public.profiles
     set role = v_role::public.user_role
   where id = auth.uid();
end;
$$;

revoke execute on function public.set_my_role(text) from public, anon;
grant  execute on function public.set_my_role(text) to authenticated;


-- -----------------------------------------------------------------------------
-- B. DNA Rhythm scheduling
-- -----------------------------------------------------------------------------
alter table public.dna_rhythms
  add column if not exists weekly_days smallint[] not null default '{}';

alter table public.dna_rhythms
  drop constraint if exists dna_rhythms_weekly_days_range;
alter table public.dna_rhythms
  add constraint dna_rhythms_weekly_days_range
  check (weekly_days <@ array[1,2,3,4,5,6,7]::smallint[]);

-- A weekly rhythm can never exist without at least one due day, and a
-- non-weekly one never carries days. Days are de-duplicated and sorted.
-- Default for "weekly, nothing chosen" is Sunday (ISO 7) — the church's
-- natural weekly rhythm; the Church Profile screen lets the admin choose.
create or replace function public.normalize_dna_rhythm()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.frequency = 'weekly' then
    if cardinality(new.weekly_days) = 0 then
      new.weekly_days := array[7]::smallint[];
    end if;
    new.weekly_days := (
      select coalesce(array_agg(distinct d order by d), array[7]::smallint[])
      from unnest(new.weekly_days) as d
    );
  else
    new.weekly_days := '{}'::smallint[];
  end if;
  return new;
end;
$$;

drop trigger if exists dna_rhythms_normalize on public.dna_rhythms;
create trigger dna_rhythms_normalize
  before insert or update on public.dna_rhythms
  for each row execute function public.normalize_dna_rhythm();

-- Backfill (before the propagation trigger below exists, so this touches only
-- dna_rhythms): the no-op UPDATE fires the normalizer on every existing row.
update public.dna_rhythms set frequency = frequency;

-- Backfill Runners' already-injected mandated copies. First from the matching
-- church rhythm...
update public.rule_items ri
   set weekly_days = d.weekly_days
  from public.profiles p
  join public.dna_rhythms d on d.church_id = p.church_id
 where ri.runner_id = p.id
   and ri.is_church_mandated
   and ri.frequency = 'weekly'
   and cardinality(ri.weekly_days) = 0
   and d.title = ri.title
   and d.frequency = 'weekly';

-- ...then any orphan (the church has since removed or renamed the rhythm).
update public.rule_items
   set weekly_days = array[7]::smallint[]
 where is_church_mandated
   and frequency = 'weekly'
   and cardinality(weekly_days) = 0;

-- Injection now carries the days across. Everything else is 011's version
-- (affiliation lock check, atomic code claim, never touches is_anchor_rhythm).
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
  if auth.uid() is null then
    return false;
  end if;

  if exists (
    select 1 from public.profiles
    where id = auth.uid() and is_church_affiliation_locked
  ) then
    return false;
  end if;

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
    select title, category, frequency, weekly_days
    from public.dna_rhythms
    where church_id = v_church_id
  loop
    insert into public.rule_items
      (runner_id, category, title, frequency, weekly_days, is_church_mandated)
    values
      (auth.uid(), v_rhythm.category, v_rhythm.title, v_rhythm.frequency,
       v_rhythm.weekly_days, true);
  end loop;

  return true;
end;
$$;

revoke execute on function public.redeem_church_code(text) from public, anon;
grant  execute on function public.redeem_church_code(text) to authenticated;

-- When a church edits a DNA Rhythm, Runners' mandated copies follow — they are
-- the church's rhythm, not the Runner's, and without this a corrected schedule
-- would only reach people who join afterwards. Matches on the OLD title (the
-- only stable key a copy has). Deleting a rhythm deliberately does NOT remove
-- Runners' copies (the Church Profile screen already says so).
-- SECURITY DEFINER: the editing Cloud admin has no rights on rule_items, and
-- 011's guard on mandated rows only blocks direct client writes.
create or replace function public.propagate_dna_rhythm_edit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.title       is distinct from old.title
     or new.category    is distinct from old.category
     or new.frequency   is distinct from old.frequency
     or new.weekly_days is distinct from old.weekly_days then
    update public.rule_items ri
       set title       = new.title,
           category    = new.category,
           frequency   = new.frequency,
           weekly_days = new.weekly_days
      from public.profiles p
     where ri.runner_id = p.id
       and p.church_id = new.church_id
       and ri.is_church_mandated
       and ri.title = old.title;
  end if;
  return new;
end;
$$;

drop trigger if exists dna_rhythms_propagate_edit on public.dna_rhythms;
create trigger dna_rhythms_propagate_edit
  after update on public.dna_rhythms
  for each row execute function public.propagate_dna_rhythm_edit();


-- -----------------------------------------------------------------------------
-- C. Roster + license usage
-- -----------------------------------------------------------------------------
-- Same columns, same order, same consent gating (008) as before — only the
-- access model and the role filter change. The WHERE clause is the entire
-- security boundary: a row is returned only if the CALLER (auth.uid(), read
-- from the request's JWT, not from the view owner) is a Cloud admin of that
-- row's church.
create or replace view public.church_roster as
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
    select jsonb_agg(jsonb_build_object(
      'id', w.id,
      'name', w.name,
      'phone_number',
        case when wp.church_data_consent = true then w.phone_number else null end,
      'email',
        case when wp.church_data_consent = true then w.email else null end,
      'consent', wp.church_data_consent
    ))
    from public.witness_pairings wp
    join public.profiles w on w.id = wp.witness_id
    where wp.runner_id = p.id and wp.status = 'active'
  ), '[]'::jsonb)                                      as witnesses,
  p.email                                              as runner_email,
  p.phone_number                                       as runner_phone_number
from public.profiles p
where p.church_id is not null
  and public.is_cloud_admin_of_church(p.church_id);

-- Run with the owner's rights (so the subqueries above can read check_ins and
-- witness_pairings), not the caller's. The filter above is what scopes it.
alter view public.church_roster set (security_invoker = false);

revoke all on public.church_roster from anon;
revoke insert, update, delete on public.church_roster from authenticated;
grant  select on public.church_roster to authenticated;

comment on view public.church_roster is
  'Cloud Roster tab. Owner-rights view (security_invoker = false) so a Cloud '
  'admin can see aggregate vitality / last check-in date / consent-gated '
  'Witness contact for THEIR church''s members without any row-level access to '
  'check_ins, rule_items or witness_pairings. Scoped entirely by the WHERE '
  'clause: is_cloud_admin_of_church(p.church_id). Do not add columns that '
  'expose individual check-in answers.';

-- License usage: every member of the church, whichever view (Runner/Witness)
-- they last had selected. Stays security_invoker — a Cloud admin can already
-- see every member's profile row of their church under profiles' policy.
create or replace view public.church_license_usage
  with (security_invoker = true)
as
select
  c.id as church_id,
  c.license_cap,
  count(p.id) as active_license_count
from public.churches c
left join public.profiles p on p.church_id = c.id
group by c.id, c.license_cap;

revoke insert, update, delete on public.church_license_usage from authenticated;


-- =============================================================================
-- Verification (SQL editor, dev branch)
-- =============================================================================
-- A. DNA scheduling
--   select title, frequency, weekly_days from dna_rhythms;                       -- no weekly row with '{}'
--   select count(*) from rule_items
--    where is_church_mandated and frequency = 'weekly'
--      and cardinality(weekly_days) = 0;                                          -- 0
--   insert into dna_rhythms (church_id, title, category, frequency)
--     values ('<church-uuid>', 'Test', 'abiding_prayer', 'weekly');              -- weekly_days = {7}
--
-- B. Roster as a Cloud admin (replace the uuid with a Cloud admin's user id):
--   begin;
--   set local role authenticated;
--   select set_config('request.jwt.claims',
--     '{"sub":"<cloud-admin-uuid>","role":"authenticated"}', true);
--   select runner_name, vitality_score, last_check_in_date, witnesses
--     from church_roster;                       -- real vitality, dates, witnesses
--   select * from check_ins;                    -- still 0 rows
--   select * from witness_pairings;             -- still 0 rows
--   rollback;
--   ...and as an ordinary Runner / a Cloud admin of a DIFFERENT church:
--   select * from church_roster;                -- 0 rows
--
-- C. set_my_role (as any signed-in user)
--   select set_my_role('witness');              -- ok
--   select set_my_role('cloud');                -- ERROR: Role must be runner or witness.
--   update profiles set role = 'runner' where id = auth.uid();   -- still denied
-- =============================================================================
