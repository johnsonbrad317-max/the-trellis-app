-- =============================================================================
-- The Trellis — 002_grants_and_cloud_access.sql
-- =============================================================================
-- Run this AFTER init_schema.sql (already applied to the live project). Two
-- independent fixes bundled together:
--
-- 1. The missing GRANTs. init_schema.sql defined RLS policies but never
--    granted the underlying table privileges those policies gate — RLS only
--    narrows what a role can already touch; it's not a substitute for the
--    GRANT itself. Confirmed live: `curl` against the REST endpoint returned
--    `permission denied for table churches ... GRANT SELECT ON public.churches
--    TO anon`, i.e. every table was unreachable regardless of any policy.
--
-- 2. Cloud access as its own grant, not a role value. Runner and Witness are
--    just two free-switching views on the same account; Cloud is different —
--    it's unlocked per-account by redeeming a church-specific Cloud Access
--    Code (minted when a church purchases a Cloud-level membership), fully
--    independent of `profiles.role`. `role` stays 'runner'/'witness' only
--    going forward — cosmetic UI state, not a security boundary.
--
-- 3. `profiles.phone_number` — missed in init_schema.sql. The app's SMS
--    actions (witness/runner "text them" buttons) and the Cloud Roster's
--    contact info both need it; there was nowhere to read it from.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- A. Cloud access schema (created before the blanket GRANT below, so the
--    REVOKE that follows it has something to act on)
-- -----------------------------------------------------------------------------
alter table public.profiles
  add column if not exists cloud_admin_church_id uuid references public.churches (id) on delete set null;

alter table public.profiles
  add column if not exists phone_number text;

create index if not exists profiles_cloud_admin_church_idx on public.profiles (cloud_admin_church_id);

create table if not exists public.cloud_access_codes (
  id            uuid primary key default gen_random_uuid(),
  church_id     uuid not null references public.churches (id) on delete cascade,
  code          text not null unique,
  generated_at  timestamptz not null default now(),
  is_redeemed   boolean not null default false,
  redeemed_by   uuid references public.profiles (id) on delete set null,
  redeemed_at   timestamptz
);
comment on table public.cloud_access_codes is
  'Grants Cloud (Church Admin) access — distinct from church_codes, which is '
  'the Runner-facing roster-join code. Deliberately has NO RLS policies at '
  'all (see part C below): unlike church_codes, not even that church''s own '
  'Cloud admin can SELECT this table directly. The only way in or out is '
  'through generate_cloud_access_code()/redeem_cloud_access_code() below.';

create index if not exists cloud_access_codes_church_idx on public.cloud_access_codes (church_id);


-- -----------------------------------------------------------------------------
-- B. The missing GRANTs
-- -----------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;

-- Postgres's "ALL TABLES IN SCHEMA" also covers views (church_roster,
-- church_license_usage) — no separate grant needed for those.
grant select, insert, update, delete on all tables in schema public to authenticated;

-- anon (pre-auth) never touches application data directly — sign-up/sign-in
-- goes through Supabase Auth, church-code/cloud-code validation goes through
-- the SECURITY DEFINER RPCs, which run as their owner regardless of the
-- caller's own grants. No table-level grants to anon are needed or added.


-- -----------------------------------------------------------------------------
-- C. Lock cloud_access_codes down completely
-- -----------------------------------------------------------------------------
-- Explicitly undo the blanket grant above for this one table — belt-and-
-- suspenders alongside RLS, so "no direct access" holds even if RLS were
-- ever accidentally disabled on this table later.
revoke all on public.cloud_access_codes from authenticated, anon;

alter table public.cloud_access_codes enable row level security;
-- Deliberately zero `create policy` statements follow. RLS enabled with no
-- policies denies every row to every role via PostgREST — SELECT, INSERT,
-- UPDATE, DELETE all included — with no exceptions carved out, not even for
-- that church's own Cloud admin. Only the two SECURITY DEFINER functions
-- below can read or write this table, since they run as their owner (who
-- isn't subject to RLS at all, being the table's owning role).


-- -----------------------------------------------------------------------------
-- D. Cloud access RPCs
-- -----------------------------------------------------------------------------
-- Mints a new code for a church. Callable only by that church's existing
-- Cloud admin (so a pastor can hand out more codes to staff) — note this
-- means the very FIRST code for a newly-onboarded church can't be
-- self-service; it's created directly (dashboard SQL editor or a
-- service-role Edge Function) at the point the church actually purchases a
-- Cloud membership, same operational pattern as church creation itself in
-- init_schema.sql.
create or replace function public.generate_cloud_access_code(p_church_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if not public.is_cloud_admin_of_church(p_church_id) then
    raise exception 'Not authorized to generate a Cloud Access Code for this church.';
  end if;

  v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8));

  insert into public.cloud_access_codes (church_id, code)
  values (p_church_id, v_code);

  return v_code;
end;
$$;

-- Redeems a code for the calling user: atomically claims it, then grants
-- Cloud access by setting cloud_admin_church_id — never touches role or
-- roster membership.
create or replace function public.redeem_cloud_access_code(p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_church_id uuid;
begin
  update public.cloud_access_codes
     set is_redeemed = true, redeemed_by = auth.uid(), redeemed_at = now()
   where code = upper(trim(p_code)) and not is_redeemed
   returning church_id into v_church_id;

  if v_church_id is null then
    return false;
  end if;

  update public.profiles
     set cloud_admin_church_id = v_church_id
   where id = auth.uid();

  return true;
end;
$$;

grant execute on function public.generate_cloud_access_code(uuid) to authenticated;
grant execute on function public.redeem_cloud_access_code(text) to authenticated;


-- -----------------------------------------------------------------------------
-- E. Re-key the Cloud-admin RLS helpers off cloud_admin_church_id
-- -----------------------------------------------------------------------------
-- Same signatures as init_schema.sql, so this transparently replaces them —
-- every existing policy that already calls is_cloud_admin_of_church/
-- is_cloud_admin_of_runner (canopy_rhythms, church_codes, the roster view,
-- get_congregational_health, profiles itself) picks up the corrected check
-- automatically. No other policy needs to change.
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
      and cloud_admin_church_id = p_church_id
  );
$$;

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
    join public.profiles runner_profile
      on runner_profile.church_id = admin_profile.cloud_admin_church_id
    where admin_profile.id = auth.uid()
      and admin_profile.cloud_admin_church_id is not null
      and runner_profile.id = p_runner_id
  );
$$;

-- `role` is no longer a security boundary (see header) — narrow its default
-- and leave 'cloud' defined-but-unused on the enum; Postgres can't cleanly
-- drop an enum value, and there's no data using it yet on a schema this
-- fresh, so no backfill is needed.
alter table public.profiles alter column role set default 'runner';


-- -----------------------------------------------------------------------------
-- F. church_roster — add contact info (runner + witness phone/email), needed
--    for the Roster tab's "text/email this person" actions. init_schema.sql's
--    version only had name/vitality/check-in fields. New columns are
--    appended at the end so this stays a valid CREATE OR REPLACE VIEW.
-- -----------------------------------------------------------------------------
create or replace view public.church_roster
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
    select jsonb_agg(jsonb_build_object(
      'id', w.id, 'name', w.name, 'phone_number', w.phone_number, 'email', w.email
    ))
    from public.witness_pairings wp
    join public.profiles w on w.id = wp.witness_id
    where wp.runner_id = p.id and wp.status = 'active'
  ), '[]'::jsonb)                                      as witnesses,
  p.email                                              as runner_email,
  p.phone_number                                       as runner_phone_number
from public.profiles p
where p.role = 'runner';


-- -----------------------------------------------------------------------------
-- G. Pairing codes — init_schema.sql never gave a Witness any way to redeem
--    a Runner's pairing code. witness_pairings' own INSERT policy lets
--    either side create a row once they already know both ids, but a
--    Witness starts out only knowing a human-shareable code, not the
--    Runner's uuid — exactly what generatePairingCode()/redeemPairingCode()
--    below bridge, the same pattern as church codes and Cloud Access codes.
-- -----------------------------------------------------------------------------
create table if not exists public.pairing_codes (
  id            uuid primary key default gen_random_uuid(),
  runner_id     uuid not null references public.profiles (id) on delete cascade,
  code          text not null unique,
  generated_at  timestamptz not null default now(),
  expires_at    timestamptz not null default (now() + interval '24 hours'),
  is_redeemed   boolean not null default false,
  redeemed_by   uuid references public.profiles (id) on delete set null,
  redeemed_at   timestamptz
);

create index if not exists pairing_codes_runner_idx on public.pairing_codes (runner_id);

-- Same lockdown as cloud_access_codes: RLS enabled, zero policies — only
-- reachable through the two SECURITY DEFINER functions below.
revoke all on public.pairing_codes from authenticated, anon;
alter table public.pairing_codes enable row level security;

create or replace function public.generate_pairing_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));

  insert into public.pairing_codes (runner_id, code)
  values (auth.uid(), v_code);

  return v_code;
end;
$$;

-- Redeems a code for the calling (Witness) user: validates it's unexpired
-- and unredeemed, then creates or reactivates the witness_pairings row.
-- ON CONFLICT handles re-pairing after a prior removal gracefully.
create or replace function public.redeem_pairing_code(p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_runner_id uuid;
begin
  update public.pairing_codes
     set is_redeemed = true, redeemed_by = auth.uid(), redeemed_at = now()
   where code = upper(trim(p_code)) and not is_redeemed and expires_at > now()
   returning runner_id into v_runner_id;

  if v_runner_id is null then
    return false;
  end if;

  insert into public.witness_pairings (runner_id, witness_id, status)
  values (v_runner_id, auth.uid(), 'active')
  on conflict (runner_id, witness_id) do update set status = 'active';

  return true;
end;
$$;

grant execute on function public.generate_pairing_code() to authenticated;
grant execute on function public.redeem_pairing_code(text) to authenticated;


-- -----------------------------------------------------------------------------
-- H. A Witness needs to mark a Runner's *shared* prayer item as prayed-for/
--    answered (init_schema.sql's prayer_items policies only let the owning
--    Runner write their own rows). This does not add per-witness tracking —
--    last_prayed_date/is_answered stay single shared fields on the row,
--    same simplified semantics the app already has — it only widens who can
--    set them, and only for rows the Runner already chose to share.
-- -----------------------------------------------------------------------------
create policy "prayer_items_update_shared_by_witness"
  on public.prayer_items for update
  to authenticated
  using (share_with_witnesses and public.is_witness_of(runner_id))
  with check (share_with_witnesses and public.is_witness_of(runner_id));
