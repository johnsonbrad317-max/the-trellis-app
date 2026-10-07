-- =============================================================================
-- The Trellis — 027_meeting_midpoint.sql   (a meeting spot midway between two people)
-- =============================================================================
-- Run AFTER 025 (it copies 025's pairing check). Idempotent — safe to run more
-- than once.
--
-- What this file does, in plain English:
--
--   When a Runner and their Witness plan coffee or lunch, The Trellis suggests
--   a coffee shop or a sit-down restaurant roughly halfway between where each
--   of them is coming from. To do that without either person's home or work
--   ever reaching the other person's phone:
--
--   A. profiles gets four PRIVATE columns — home_lat, home_lng, work_lat,
--      work_lng — the map points of the person's own home / work address,
--      worked out by their own phone. Exactly like home_address and
--      work_address (011 1c), clients get no SELECT and no UPDATE on them.
--      Changing an address clears its point automatically, so a point never
--      outlives the address it came from.
--
--   B. set_my_meeting_coordinates(home_lat, home_lng, work_lat, work_lng) —
--      the phone stores the points for its OWN addresses. Null clears one.
--
--   C. get_my_meeting_coordinates_status() — "do I have a point on file for
--      home / for work?" (yes/no only), so the phone knows whether to geocode.
--
--   D. get_meeting_midpoint(other) — for an ACTIVE Runner/Witness pairing
--      only: the point halfway between the two people's starting places,
--      ROUNDED to two decimal places (about a kilometre), or which of the two
--      has nothing on file. Never either person's own point.
--
--   E. Grants, all in one place.
--
--   F. Verification queries (bottom of the file).
--
-- WHICH PLACE COUNTS AS "WHERE THEY ARE COMING FROM" (the origin rule):
--   each person's WORK point if they have one, otherwise their HOME point.
--   So: both work → work/work; one works → work/home; neither → home/home.
--   (A work address whose point could not be found falls back to home.)
--
-- WHY ROUNDED, AND WHY BOTH ORIGINS ARE SNAPPED FIRST:
--   The partner knows their own starting point, so an exact midpoint would
--   give away the other person's exact point (other = 2 × mid − mine). Each
--   origin is therefore snapped to a 0.01° grid (~1.1 km) BEFORE averaging and
--   the result is rounded to 0.01° again. Snapping first matters: rounding only
--   the final answer would let someone nudge their own stored point in tiny
--   steps and watch where the rounded answer flips, homing in on the other
--   person's exact location. With both origins snapped, the most anyone can
--   ever learn is which ~1 km grid square the other person starts from.
--
-- Client contract (lib/services/meeting_spot_service.dart):
--   rpc('set_my_meeting_coordinates', {p_home_lat, p_home_lng, p_work_lat, p_work_lng})
--     → void. Each pair both null (clear) or both set; lat −90..90, lng −180..180.
--       A point is stored only if the matching address is on file (otherwise
--       it is stored as null). Stored rounded to 3 decimals (~100 m).
--   rpc('get_my_meeting_coordinates_status') → {"home": bool, "work": bool}
--   rpc('get_meeting_midpoint', {p_other_user_id}) →
--       {"lat": 39.1, "lng": -94.58}         -- 2 decimal places at most
--     | {"missing": "me"}                    -- caller has no point on file
--     | {"missing": "other"}                 -- partner has none, or not an
--                                               active pairing (strangers get
--                                               exactly this answer)
--
-- get_my_private_profile() (011) is NOT changed: its shape stays
-- (home_address, work_address).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- A. The private point columns
-- -----------------------------------------------------------------------------
alter table public.profiles
  add column if not exists home_lat double precision,
  add column if not exists home_lng double precision,
  add column if not exists work_lat double precision,
  add column if not exists work_lng double precision;

comment on column public.profiles.home_lat is
  'Latitude of home_address, geocoded by the owner''s own phone. Private: no '
  'client grant; written only by set_my_meeting_coordinates, read only inside '
  'get_meeting_midpoint. Cleared whenever home_address changes.';
comment on column public.profiles.home_lng is
  'Longitude of home_address. Same rules as home_lat.';
comment on column public.profiles.work_lat is
  'Latitude of work_address, geocoded by the owner''s own phone. Private: no '
  'client grant; written only by set_my_meeting_coordinates, read only inside '
  'get_meeting_midpoint. Cleared whenever work_address changes.';
comment on column public.profiles.work_lng is
  'Longitude of work_address. Same rules as work_lat.';

-- Sane values only, and a point is a pair: both halves or neither.
alter table public.profiles drop constraint if exists profiles_home_point_valid;
alter table public.profiles add constraint profiles_home_point_valid check (
  (home_lat is null and home_lng is null)
  or (home_lat between -90 and 90 and home_lng between -180 and 180)
);
alter table public.profiles drop constraint if exists profiles_work_point_valid;
alter table public.profiles add constraint profiles_work_point_valid check (
  (work_lat is null and work_lng is null)
  or (work_lat between -90 and 90 and work_lng between -180 and 180)
);

-- Layer 1 (011's column grants): 011 grants SELECT and UPDATE column by
-- column, so new columns are invisible to clients until granted — and they
-- are never granted. Stated explicitly here so nobody "fixes" it later.
-- (A column-level revoke cannot undo a table-level grant; 011 removed the
-- table-level ones, which is why Layer 2 below exists as well.)
revoke select (home_lat, home_lng, work_lat, work_lng),
       update (home_lat, home_lng, work_lat, work_lng)
  on public.profiles from anon, authenticated;

-- Layer 2: a guard trigger. A client may not write the points directly (the
-- same answer as the missing grant, should grants ever be widened), and a
-- changed address drops its now-stale point. Its own small trigger, not a
-- line in guard_profile_update, for the reason 021 B and 025 B give: a re-run
-- of 019 re-creates that guard and would silently drop the line.
-- Not SECURITY DEFINER: like the other guards it tells a client from the
-- server by current_user. set_my_meeting_coordinates runs as the function
-- owner, so the first check never gets in its way.
create or replace function public.guard_meeting_coordinates()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.home_lat is distinct from old.home_lat
       or new.home_lng is distinct from old.home_lng
       or new.work_lat is distinct from old.work_lat
       or new.work_lng is distinct from old.work_lng then
      raise exception 'That profile field can only be changed by The Trellis itself.'
        using errcode = '42501';
    end if;
  end if;

  -- A new (or cleared) address makes the old point wrong. The phone geocodes
  -- the new address straight after saving it and stores the fresh point.
  if new.home_address is distinct from old.home_address then
    new.home_lat := null;
    new.home_lng := null;
  end if;
  if new.work_address is distinct from old.work_address then
    new.work_lat := null;
    new.work_lng := null;
  end if;

  return new;
end;
$$;

-- (A trigger function cannot be called directly; it fires inside the
--  client's own UPDATE — same grants as guard_calendar_sync_update in 025.)
revoke execute on function public.guard_meeting_coordinates() from public, anon;
grant  execute on function public.guard_meeting_coordinates() to authenticated, service_role;

drop trigger if exists profiles_guard_meeting_coordinates on public.profiles;
create trigger profiles_guard_meeting_coordinates
  before update on public.profiles
  for each row execute function public.guard_meeting_coordinates();


-- -----------------------------------------------------------------------------
-- B. set_my_meeting_coordinates — the phone stores its own points
-- -----------------------------------------------------------------------------
-- Errors: 28000 not signed in; 22023 half a point (a latitude without its
-- longitude or the reverse) or a value out of range (NaN and infinity are out
-- of range too).
create or replace function public.set_my_meeting_coordinates(
  p_home_lat double precision,
  p_home_lng double precision,
  p_work_lat double precision,
  p_work_lng double precision
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'You must be signed in to save your meeting places.'
      using errcode = '28000';
  end if;

  if (p_home_lat is null) <> (p_home_lng is null)
     or (p_work_lat is null) <> (p_work_lng is null) then
    raise exception 'A map point needs both a latitude and a longitude.'
      using errcode = '22023';
  end if;

  if (p_home_lat is not null
        and not (p_home_lat between -90 and 90 and p_home_lng between -180 and 180))
     or (p_work_lat is not null
        and not (p_work_lat between -90 and 90 and p_work_lng between -180 and 180)) then
    raise exception 'That map point is out of range.'
      using errcode = '22023';
  end if;

  -- ~100 m is plenty for "somewhere midway"; no need to keep a doorstep.
  -- A point is kept only while the address it belongs to is on file.
  update public.profiles p
     set home_lat = case when nullif(btrim(p.home_address), '') is not null
                         then round(p_home_lat::numeric, 3)::double precision end,
         home_lng = case when nullif(btrim(p.home_address), '') is not null
                         then round(p_home_lng::numeric, 3)::double precision end,
         work_lat = case when nullif(btrim(p.work_address), '') is not null
                         then round(p_work_lat::numeric, 3)::double precision end,
         work_lng = case when nullif(btrim(p.work_address), '') is not null
                         then round(p_work_lng::numeric, 3)::double precision end
   where p.id = v_me;
end;
$$;

comment on function public.set_my_meeting_coordinates(double precision, double precision, double precision, double precision) is
  'The caller''s phone stores the map points of its own home / work address '
  '(null clears one; each kept only while its address is on file; stored '
  'rounded to 3 decimals). Read back only by get_meeting_midpoint.';

revoke execute on function public.set_my_meeting_coordinates(double precision, double precision, double precision, double precision) from public, anon;
grant  execute on function public.set_my_meeting_coordinates(double precision, double precision, double precision, double precision) to authenticated;


-- -----------------------------------------------------------------------------
-- C. get_my_meeting_coordinates_status — yes/no only, the caller's own row
-- -----------------------------------------------------------------------------
create or replace function public.get_my_meeting_coordinates_status()
returns jsonb
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(
    (select jsonb_build_object(
              'home', p.home_lat is not null,
              'work', p.work_lat is not null)
       from public.profiles p
      where p.id = auth.uid()),
    jsonb_build_object('home', false, 'work', false)
  );
$$;

comment on function public.get_my_meeting_coordinates_status() is
  'Whether the caller has a stored map point for home and for work '
  '(booleans only). Lets the phone geocode addresses saved before 027.';

revoke execute on function public.get_my_meeting_coordinates_status() from public, anon;
grant  execute on function public.get_my_meeting_coordinates_status() to authenticated;


-- -----------------------------------------------------------------------------
-- D. get_meeting_midpoint — halfway between two paired people, rounded
-- -----------------------------------------------------------------------------
-- Who may ask about whom: only the two sides of an ACTIVE witness_pairing
-- (either direction — the same check as get_pair_calendar in 025). For anyone
-- else, including a stranger's id, your own id, or an ended pairing, the
-- answer is {"missing": "other"} — exactly what a partner with no address
-- gets — so the call cannot be used to probe whether a stranger has one.
-- {"missing": "me"} depends only on the caller's own row, so it is answered
-- first.
--
-- The midpoint: both origins snapped to 0.01°, averaged (longitude the short
-- way round, should two people ever straddle the 180° meridian), and the
-- result rounded to 0.01° again. At these distances a straight average of
-- latitude and longitude is as good as a great-circle midpoint.
--
-- Errors: 28000 not signed in.
create or replace function public.get_meeting_midpoint(p_other_user_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_me        uuid := auth.uid();
  v_paired    boolean := false;
  v_my_lat    numeric;
  v_my_lng    numeric;
  v_other_lat numeric;
  v_other_lng numeric;
  v_mid_lat   numeric;
  v_mid_lng   numeric;
begin
  if v_me is null then
    raise exception 'You must be signed in to find a meeting spot.'
      using errcode = '28000';
  end if;

  -- The origin rule: work if there is a work point, otherwise home.
  select round(coalesce(p.work_lat, p.home_lat)::numeric, 2),
         round((case when p.work_lat is not null then p.work_lng else p.home_lng end)::numeric, 2)
    into v_my_lat, v_my_lng
    from public.profiles p
   where p.id = v_me;

  if v_my_lat is null or v_my_lng is null then
    return jsonb_build_object('missing', 'me');
  end if;

  if p_other_user_id is not null and p_other_user_id <> v_me then
    select exists (
      select 1
        from public.witness_pairings wp
       where wp.status = 'active'
         and ((wp.runner_id = v_me and wp.witness_id = p_other_user_id)
           or (wp.runner_id = p_other_user_id and wp.witness_id = v_me))
    ) into v_paired;
  end if;

  if not v_paired then
    return jsonb_build_object('missing', 'other');
  end if;

  select round(coalesce(p.work_lat, p.home_lat)::numeric, 2),
         round((case when p.work_lat is not null then p.work_lng else p.home_lng end)::numeric, 2)
    into v_other_lat, v_other_lng
    from public.profiles p
   where p.id = p_other_user_id;

  if v_other_lat is null or v_other_lng is null then
    return jsonb_build_object('missing', 'other');
  end if;

  v_mid_lat := round((v_my_lat + v_other_lat) / 2, 2);

  -- Longitude the short way round.
  if v_other_lng - v_my_lng > 180 then
    v_other_lng := v_other_lng - 360;
  elsif v_my_lng - v_other_lng > 180 then
    v_other_lng := v_other_lng + 360;
  end if;
  v_mid_lng := (v_my_lng + v_other_lng) / 2;
  if v_mid_lng < -180 then
    v_mid_lng := v_mid_lng + 360;
  elsif v_mid_lng >= 180 then
    v_mid_lng := v_mid_lng - 360;
  end if;
  v_mid_lng := round(v_mid_lng, 2);

  return jsonb_build_object('lat', v_mid_lat, 'lng', v_mid_lng);
end;
$$;

comment on function public.get_meeting_midpoint(uuid) is
  'For an active Runner/Witness pairing: the point midway between the two '
  'people''s starting places (work if on file, else home), both snapped to and '
  'the answer rounded to 0.01 degrees, as {lat, lng}; or {missing: me|other}. '
  'Anyone not actively paired with the caller reads as {missing: other}.';

revoke execute on function public.get_meeting_midpoint(uuid) from public, anon;
grant  execute on function public.get_meeting_midpoint(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- E. Grants, all in one place
-- -----------------------------------------------------------------------------
--   client (authenticated)   set_my_meeting_coordinates(float8, float8, float8, float8)
--                            get_my_meeting_coordinates_status()
--                            get_meeting_midpoint(uuid)
--   trigger function         guard_meeting_coordinates()
--   (not directly callable)
--   columns                  profiles.home_lat/home_lng/work_lat/work_lng:
--                            no client SELECT, no client UPDATE
revoke execute on function public.set_my_meeting_coordinates(double precision, double precision, double precision, double precision) from public, anon;
grant  execute on function public.set_my_meeting_coordinates(double precision, double precision, double precision, double precision) to authenticated;
revoke execute on function public.get_my_meeting_coordinates_status()      from public, anon;
grant  execute on function public.get_my_meeting_coordinates_status()      to authenticated;
revoke execute on function public.get_meeting_midpoint(uuid)               from public, anon;
grant  execute on function public.get_meeting_midpoint(uuid)               to authenticated;
revoke execute on function public.guard_meeting_coordinates()              from public, anon;
grant  execute on function public.guard_meeting_coordinates()              to authenticated, service_role;


-- =============================================================================
-- F. VERIFICATION — run in the SQL editor and compare with "expect"
-- =============================================================================
-- Blocks that act as a signed-in user use `set local role` (as 018–025 do).
-- Replace the <...> placeholders with real test ids. A block that ends in an
-- expected ERROR must be run on its own: the error aborts that transaction, and
-- the `rollback;` on its last line cleans up. Every dry run here rolls back.
--
-- 0. Privileges at a glance. Expect, in order:
--    false, true           set_my_meeting_coordinates: not anon; signed-in users
--    false, true           get_my_meeting_coordinates_status
--    false, true           get_meeting_midpoint
--    false, false          home_lat SELECT / UPDATE for authenticated (same for the other three)
--    false, true           home_address SELECT / UPDATE: unchanged from 011
--
--   select has_function_privilege('anon',          'public.set_my_meeting_coordinates(float8,float8,float8,float8)', 'execute'),
--          has_function_privilege('authenticated', 'public.set_my_meeting_coordinates(float8,float8,float8,float8)', 'execute');
--   select has_function_privilege('anon',          'public.get_my_meeting_coordinates_status()', 'execute'),
--          has_function_privilege('authenticated', 'public.get_my_meeting_coordinates_status()', 'execute');
--   select has_function_privilege('anon',          'public.get_meeting_midpoint(uuid)', 'execute'),
--          has_function_privilege('authenticated', 'public.get_meeting_midpoint(uuid)', 'execute');
--   select has_column_privilege('authenticated', 'public.profiles', 'home_lat', 'select'),
--          has_column_privilege('authenticated', 'public.profiles', 'home_lat', 'update');
--   select has_column_privilege('authenticated', 'public.profiles', 'home_address', 'select'),
--          has_column_privilege('authenticated', 'public.profiles', 'home_address', 'update');
--
-- 1. Structure. Expect the four columns, the two check constraints and the
--    trigger profiles_guard_meeting_coordinates on profiles.
--   select column_name, data_type from information_schema.columns
--    where table_schema = 'public' and table_name = 'profiles'
--      and column_name in ('home_lat', 'home_lng', 'work_lat', 'work_lng');
--   select conname from pg_constraint
--    where conrelid = 'public.profiles'::regclass and conname like 'profiles_%_point_valid';
--   select tgname from pg_trigger where tgrelid = 'public.profiles'::regclass and not tgisinternal order by 1;
--
-- 2. Round trip with an ACTIVE Runner/Witness pair. Everything rolls back.
--    Expect, in order:
--      {"home": false, "work": false}            (runner, before)
--      {"missing": "me"}                         (runner, no points yet)
--      {"home": true, "work": true}              (runner, after storing)
--      {"missing": "other"}                      (runner: witness has none)
--      {"lat": 39.05, "lng": -94.55}             (runner → witness: runner's WORK
--                                                 39.10/-94.58 and witness's HOME
--                                                 39.00/-94.52, since the witness
--                                                 has no work address)
--      the same {"lat": 39.05, "lng": -94.55}    (asked from the witness's side)
--      {"home": false, "work": true}             (runner after changing the home
--                                                 address: its point was dropped)
--   begin;
--   update public.profiles set home_address = '1 Home St', work_address = '2 Work Ave'
--    where id = '<runner-uuid>';
--   update public.profiles set home_address = '3 Witness Rd', work_address = null
--    where id = '<witness-uuid>';
--   set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   select public.get_my_meeting_coordinates_status();
--   select public.get_meeting_midpoint('<witness-uuid>');
--   select public.set_my_meeting_coordinates(39.0412, -94.6113, 39.1004, -94.5799);
--   select public.get_my_meeting_coordinates_status();
--   select public.get_meeting_midpoint('<witness-uuid>');
--   select set_config('request.jwt.claims', '{"sub":"<witness-uuid>","role":"authenticated"}', true);
--   select public.set_my_meeting_coordinates(39.0011, -94.5203, 38.9, -94.4);   -- work point ignored: no work address
--   select public.get_meeting_midpoint('<runner-uuid>');
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   select public.get_meeting_midpoint('<witness-uuid>');
--   update public.profiles set home_address = '9 New St' where id = auth.uid();
--   select public.get_my_meeting_coordinates_status();
--   reset role;
--   select home_lat, home_lng, work_lat, work_lng from public.profiles
--    where id in ('<runner-uuid>', '<witness-uuid>');   -- witness work_* null; values at 3 decimals
--   rollback;
--
-- 3. The stranger case. As a signed-in user with a point on file who is NOT
--    actively paired with <runner-uuid>. Expect {"missing": "other"} for the
--    runner, for your own id and for a made-up id:
--   begin;
--   set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<unrelated-user-uuid>","role":"authenticated"}', true);
--   select public.get_meeting_midpoint('<runner-uuid>');
--   select public.get_meeting_midpoint(auth.uid());
--   select public.get_meeting_midpoint(gen_random_uuid());
--   rollback;
--
-- 4. Refusals (each on its own; each rolls back):
--    a. Half a point (expect ERROR 22023 "A map point needs both..."):
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   select public.set_my_meeting_coordinates(39.1, null, null, null);
--   rollback;
--    b. Out of range (expect ERROR 22023 "That map point is out of range."):
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   select public.set_my_meeting_coordinates(91, 0, null, null);
--   rollback;
--    c. A client cannot write a point directly (expect ERROR 42501 permission denied):
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   update public.profiles set home_lat = 1, home_lng = 1 where id = auth.uid();
--   rollback;
--    d. A client cannot read a point (expect ERROR 42501 permission denied):
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   select home_lat from public.profiles where id = auth.uid();
--   rollback;
--    e. Not signed in (expect ERROR 28000):
--   begin; set local role authenticated;
--   select public.get_meeting_midpoint(gen_random_uuid());
--   rollback;
-- =============================================================================
