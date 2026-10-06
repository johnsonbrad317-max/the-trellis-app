-- =============================================================================
-- The Trellis — 023_dna_seasons_merge_welcome.sql
-- =============================================================================
-- Run AFTER 021 (it builds on rule_items.unlocked_until and the 021 guards) and
-- 022. Idempotent — safe to run more than once.
--
-- What this file does, in plain English:
--
--   A. Each church (DNA) rhythm on a Runner's Rule of Life now remembers WHICH
--      DNA Rhythm it came from (rule_items.dna_rhythm_id). Every path that
--      creates one sets it; existing rows are matched up once; clients can read
--      it and never write it.
--
--   B. Seasons. A DNA Rhythm can have a last day (dna_rhythms.ends_on). Null
--      means year-round.
--
--   C. Retiring a DNA Rhythm. The church's rhythm goes away, but nobody's
--      rhythm or history is deleted: every member's copy becomes their own
--      rhythm (no longer church-mandated), with a 7-day window to keep or
--      remove it freely. retire_dna_rhythm() for the app; a trigger makes a
--      plain DELETE on dna_rhythms do the same thing.
--
--   D. A daily job (05:00 UTC) retires every DNA Rhythm whose season has ended.
--
--   E. Merging. A Runner who has a personal rhythm that duplicates a church
--      rhythm can fold it into the church one: the check-in history moves over
--      and the duplicate is removed (merge_rule_item_into_dna()).
--
--   F. profiles.has_seen_welcome — whether the welcome walkthrough has been
--      shown. Existing accounts start at false and see it once (intended).
--
--   G. Grants restated for every new or changed function.
--
--   H. Verification queries (bottom of the file).
--
-- ALSO REQUIRED ALONGSIDE THIS FILE (not SQL): section D needs the pg_cron
-- extension (021 E.5 needed it too). If it is not enabled, everything else in
-- this file still applies and section D prints what to do.
--
-- RE-RUNNING OLDER FILES: this file replaces apply_dna_rhythm_to_members and
-- propagate_new_dna_rhythm (016), propagate_dna_rhythm_edit and
-- redeem_church_code (012), and guard_rule_item_update / guard_rule_item_insert
-- (021). If any of those files is ever run again, run this file again
-- afterwards. 019's function allowlist is NOT edited: on a re-run it prints one
-- notice that the old five-argument apply_dna_rhythm_to_members "is not
-- present" — expected, that signature is replaced below.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- A. Which DNA Rhythm a church rhythm came from
-- -----------------------------------------------------------------------------
-- A.1  The link. ON DELETE SET NULL: when the church's rhythm goes (section C),
--      the member's copy stays and simply stops pointing anywhere.
alter table public.rule_items
  add column if not exists dna_rhythm_id uuid
    references public.dna_rhythms (id) on delete set null;

comment on column public.rule_items.dna_rhythm_id is
  'The church DNA Rhythm this rhythm was created from (null for a Runner''s own '
  'rhythm, or once that DNA Rhythm has been retired). Set only by the database; '
  'clients can read it, never write it.';

-- The FK's SET NULL and section C's release both look rows up by this column.
create index if not exists rule_items_dna_rhythm_idx
  on public.rule_items (dna_rhythm_id)
  where dna_rhythm_id is not null;

-- Reading: rule_items still has the table-wide SELECT from 002 (011 narrowed
-- only UPDATE), so the owner and their Witness — the two people the policy
-- rule_items_select_own_or_paired admits — can already read the new column.
-- Stated anyway so this file is correct on its own.
grant select (dna_rhythm_id) on public.rule_items to authenticated;
-- Writing: 011 limits client UPDATE to title, frequency, weekly_days and
-- is_anchor_rhythm, so a client cannot update it. Client INSERT is table-wide;
-- A.4 below nulls the column on every client insert, and A.5 adds it to the
-- guard's never-changeable list as the second layer.

-- A.2  Every server-side path that creates a church rhythm sets the link.
--
--      016's apply_dna_rhythm_to_members with one more argument, the DNA
--      Rhythm's id. Same behaviour otherwise: a member who already has a
--      PERSONAL rhythm with the same title (ignoring case/spacing) adopts the
--      church's version in place and keeps their history; everyone else gets a
--      new church rhythm; safe to run twice. The old five-argument signature is
--      dropped so there is exactly one version.
drop function if exists public.apply_dna_rhythm_to_members(
  uuid, text, public.rule_category, public.rule_frequency, smallint[]);

create or replace function public.apply_dna_rhythm_to_members(
  p_church_id     uuid,
  p_title         text,
  p_category      public.rule_category,
  p_frequency     public.rule_frequency,
  p_weekly_days   smallint[],
  p_dna_rhythm_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_adopted integer := 0;
  v_added   integer := 0;
begin
  -- Adopt: a personal rhythm with the same name becomes the church's, keeping
  -- its id (and so its check-in history). Now also linked to the DNA Rhythm.
  update public.rule_items ri
     set is_church_mandated = true,
         dna_rhythm_id      = p_dna_rhythm_id,
         title              = p_title,
         category           = p_category,
         frequency          = p_frequency,
         weekly_days        = p_weekly_days
    from public.profiles p
   where ri.runner_id = p.id
     and p.church_id = p_church_id
     and not ri.is_church_mandated
     and lower(trim(ri.title)) = lower(trim(p_title));
  get diagnostics v_adopted = row_count;

  -- Add: everyone who has neither this DNA Rhythm nor a church rhythm of the
  -- same name gets a new, linked church rhythm.
  insert into public.rule_items
    (runner_id, category, title, frequency, weekly_days, is_church_mandated, dna_rhythm_id)
  select p.id, p_category, p_title, p_frequency, p_weekly_days, true, p_dna_rhythm_id
    from public.profiles p
   where p.church_id = p_church_id
     and not exists (
       select 1 from public.rule_items ri
        where ri.runner_id = p.id
          and ri.is_church_mandated
          and (   ri.dna_rhythm_id = p_dna_rhythm_id
               or lower(trim(ri.title)) = lower(trim(p_title)))
     );
  get diagnostics v_added = row_count;

  return v_adopted + v_added;
end;
$$;

revoke execute on function public.apply_dna_rhythm_to_members(
  uuid, text, public.rule_category, public.rule_frequency, smallint[], uuid)
  from public, anon, authenticated;

-- 016's trigger function, passing the new row's id through.
create or replace function public.propagate_new_dna_rhythm()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- AFTER INSERT, so NEW already carries the days chosen by 012's normalizer
  -- (a weekly rhythm always has at least one).
  perform public.apply_dna_rhythm_to_members(
    new.church_id, new.title, new.category, new.frequency, new.weekly_days, new.id
  );
  return new;
end;
$$;
-- (016's dna_rhythms_propagate_new trigger already calls this.)

-- 012's edit propagation, now matching on the link first and falling back to
-- the old title for rows that have no link yet (and linking those as it goes).
-- Otherwise unchanged: the church's rhythm, not the Runner's, so mandated
-- copies follow the church's edit. A change to ends_on alone propagates
-- nothing — the season lives on dna_rhythms only.
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
       set title         = new.title,
           category      = new.category,
           frequency     = new.frequency,
           weekly_days   = new.weekly_days,
           dna_rhythm_id = new.id
      from public.profiles p
     where ri.runner_id = p.id
       and p.church_id = new.church_id
       and ri.is_church_mandated
       and (   ri.dna_rhythm_id = new.id
            or (ri.dna_rhythm_id is null and ri.title = old.title));
  end if;
  return new;
end;
$$;
-- (012's dna_rhythms_propagate_edit trigger already calls this.)

-- 012's redeem_church_code (the version 011 hardened), with two small changes:
-- each injected rhythm is linked to the DNA Rhythm it copies, and a rhythm
-- whose season has already ended (section B) is not handed to a new member.
-- Everything else is the same: affiliation-lock check, atomic code claim,
-- never touches is_anchor_rhythm.
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
    select id, title, category, frequency, weekly_days
    from public.dna_rhythms
    where church_id = v_church_id
      and (ends_on is null or ends_on >= (now() at time zone 'utc')::date)
  loop
    insert into public.rule_items
      (runner_id, category, title, frequency, weekly_days, is_church_mandated, dna_rhythm_id)
    values
      (auth.uid(), v_rhythm.category, v_rhythm.title, v_rhythm.frequency,
       v_rhythm.weekly_days, true, v_rhythm.id);
  end loop;

  return true;
end;
$$;

revoke execute on function public.redeem_church_code(text) from public, anon;
grant  execute on function public.redeem_church_code(text) to authenticated;

-- A.3  One-time backfill. Every church rhythm that has no link yet is matched
--      to the DNA Rhythm of its owner's church with the same category and the
--      same title (ignoring case and surrounding spaces) — but only when
--      exactly ONE such DNA Rhythm exists, so a guess is never recorded. Rows
--      with no match or two matches stay unlinked; section C's fallback still
--      finds them by name when a rhythm is retired. Safe to re-run (a linked
--      row is never touched again). Runs as the migration owner, so the
--      client-only guards on rule_items do not apply.
with candidates as (
  select ri.id as item_id, d.id as dna_id
    from public.rule_items ri
    join public.profiles p    on p.id = ri.runner_id
    join public.dna_rhythms d on d.church_id = p.church_id
                             and d.category  = ri.category
                             and lower(trim(d.title)) = lower(trim(ri.title))
   where ri.is_church_mandated
     and ri.dna_rhythm_id is null
),
unique_matches as (
  select item_id, (array_agg(dna_id))[1] as dna_id
    from candidates
   group by item_id
  having count(*) = 1
)
update public.rule_items ri
   set dna_rhythm_id = u.dna_id
  from unique_matches u
 where ri.id = u.item_id;

-- A.4  Client inserts never carry a link. 021's guard_rule_item_insert plus one
--      line: the app sends no dna_rhythm_id, and a client may not pretend a
--      rhythm came from the church. Server-side writers are untouched.
create or replace function public.guard_rule_item_insert()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.created_at     := now();
    new.unlocked_until := null;
    new.dna_rhythm_id  := null;
  end if;
  return new;
end;
$$;

-- (Grants: same reasoning as 021 section B — a trigger function cannot be
--  called directly, so EXECUTE exposes nothing; kept for the roles whose own
--  INSERT fires it.)
revoke execute on function public.guard_rule_item_insert() from public, anon;
grant  execute on function public.guard_rule_item_insert() to authenticated, service_role;
-- (021's rule_items_guard_insert trigger already calls this.)

-- A.5  Client updates never change the link. 021's guard_rule_item_update with
--      dna_rhythm_id added to the never-changeable list; everything 021 put
--      there (id, runner_id, category, is_church_mandated, created_at,
--      unlocked_until, the DNA-rhythm refusal, the "set" refusal) is kept with
--      the same messages. It stays an invoker-rights function: it has to see
--      the real current_user.
--
--      The FK's ON DELETE SET NULL (section C) also updates this column — that
--      update is run by Postgres's foreign-key machinery as the table's owner,
--      not as the person who deleted the DNA Rhythm, so this guard lets it
--      through (the same fact 021 C.5 relies on for account deletion).
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
       or new.unlocked_until   is distinct from old.unlocked_until
       or new.dna_rhythm_id    is distinct from old.dna_rhythm_id then
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

-- (Grants: as for guard_rule_item_insert. 011 left this one at the Postgres
--  default — PUBLIC — which is wider than needed; this narrows it to the roles
--  whose own UPDATE fires it.)
revoke execute on function public.guard_rule_item_update() from public, anon;
grant  execute on function public.guard_rule_item_update() to authenticated, service_role;
-- (011's rule_items_guard_update trigger already calls this.)


-- -----------------------------------------------------------------------------
-- B. Seasons: a DNA Rhythm's last day
-- -----------------------------------------------------------------------------
alter table public.dna_rhythms
  add column if not exists ends_on date;

comment on column public.dna_rhythms.ends_on is
  'The last day this DNA Rhythm is in force (inclusive); null = year-round. '
  'The day after, the daily job trellis-dna-season-end retires it (section C: '
  'members keep their copy as their own rhythm). Set by the church''s Cloud admin '
  'through the Church Profile screen.';

-- Who can write it? dna_rhythms still has the table-wide SELECT / INSERT /
-- UPDATE / DELETE from 002 for signed-in users (no later file narrowed it to
-- columns), and the row policies from init_schema/006 admit only that church's
-- Cloud admin for writes — so the app's existing direct inserts and updates
-- (RunnerProfile.addDnaRhythm / updateDnaRhythm) can carry ends_on as soon as
-- they send it. The column-level grants below add nothing today; they are here
-- so that if dna_rhythms is ever narrowed to column grants, this column stays
-- usable without anyone having to remember it.
grant select (ends_on), insert (ends_on), update (ends_on)
  on public.dna_rhythms to authenticated;


-- -----------------------------------------------------------------------------
-- C. Retiring a DNA Rhythm — release, never delete
-- -----------------------------------------------------------------------------
-- WHY RELEASE RATHER THAN DELETE. A member's copy of a church rhythm carries
-- their check-in history (check_ins cascades from rule_items), and that history
-- feeds the Witness heat map, the season score and Congregational Health.
-- Deleting the copies would erase months of a person's faithfulness because
-- the church changed its mind. So retiring a DNA Rhythm turns each member's
-- copy into the member's OWN rhythm — is_church_mandated goes false, the link
-- is cleared by the FK — and opens a 7-day window (unlocked_until) in which
-- they may keep it, change it or remove it even if their Rule of Life is
-- "set" (021 C). After the window the ordinary 021 rules apply, as for any
-- rhythm of their own.
--
-- HOW THE PIECES FIT (no double-processing). The work is done in ONE place: a
-- BEFORE DELETE trigger on dna_rhythms (C.2). retire_dna_rhythm (C.3) checks
-- who is asking, counts the rows the trigger is about to release, and then
-- deletes the dna_rhythms row — the trigger releases, the FK nulls the link,
-- and the function returns the count it took first. retire_expired_dna_rhythms
-- (D) also just deletes. And the app's existing direct
-- `delete from dna_rhythms` (RunnerProfile.removeDnaRhythm) gets exactly the
-- same effect, because the trigger does not care who deleted the row.

-- C.1  Which rows belong to a DNA Rhythm. Internal helper used by the trigger
--      (to release) and by retire_dna_rhythm (to count), so both agree.
--        * linked rows: rule_items.dna_rhythm_id = the rhythm;
--        * fallback for rows that predate the link: a church rhythm of a member
--          of that church with the same category and the same title (ignoring
--          case/spaces) — but NOT when another DNA Rhythm of the same church
--          also matches by name, because then the copy still belongs to that
--          other, surviving rhythm and must stay mandated.
create or replace function public._dna_rhythm_linked_items(p_dna_rhythm_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select ri.id
    from public.rule_items ri
   where ri.dna_rhythm_id = p_dna_rhythm_id
  union
  select ri.id
    from public.dna_rhythms d
    join public.profiles p    on p.church_id = d.church_id
    join public.rule_items ri on ri.runner_id = p.id
   where d.id = p_dna_rhythm_id
     and ri.dna_rhythm_id is null
     and ri.is_church_mandated
     and ri.category = d.category
     and lower(trim(ri.title)) = lower(trim(d.title))
     and not exists (
       select 1 from public.dna_rhythms o
        where o.church_id = d.church_id
          and o.id <> d.id
          and o.category = d.category
          and lower(trim(o.title)) = lower(trim(d.title))
     );
$$;

revoke execute on function public._dna_rhythm_linked_items(uuid) from public, anon, authenticated;

-- C.2  The release, as a BEFORE DELETE trigger on dna_rhythms. SECURITY
--      DEFINER: the deleting Cloud admin has no write access to rule_items, and
--      inside a definer function current_user is the owner, so 011/021's
--      client-only guards on rule_items let these updates through (and the
--      helper's EXECUTE is checked against the owner, not the admin — the
--      lesson from 018). The link itself is left for the FK to null after the
--      row is gone.
create or replace function public.release_dna_rhythm_members()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.rule_items ri
     set is_church_mandated = false,
         unlocked_until     = now() + interval '7 days'
   where ri.id in (select public._dna_rhythm_linked_items(old.id));
  return old;
end;
$$;

-- (Grants: same reasoning as the trigger functions in 021 and A.4 above.)
revoke execute on function public.release_dna_rhythm_members() from public, anon;
grant  execute on function public.release_dna_rhythm_members() to authenticated, service_role;

drop trigger if exists dna_rhythms_release_members on public.dna_rhythms;
create trigger dna_rhythms_release_members
  before delete on public.dna_rhythms
  for each row execute function public.release_dna_rhythm_members();

-- C.3  The RPC for the app. Refuses (42501) unless the caller is a Cloud admin
--      of the rhythm's church; a rhythm that does not exist gets the same
--      refusal, so nobody can probe ids. Returns how many members' rhythms were
--      released (one per member's copy). The SQL editor / service role (no
--      auth.uid()) cannot use this — it can `delete from dna_rhythms` directly
--      and the trigger does the same release.
create or replace function public.retire_dna_rhythm(p_dna_rhythm_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_church_id uuid;
  v_count     integer;
begin
  if auth.uid() is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  -- Lock the row so the count below and the delete see the same members.
  select church_id into v_church_id
    from public.dna_rhythms
   where id = p_dna_rhythm_id
     for update;

  if v_church_id is null or not public.is_cloud_admin_of_church(v_church_id) then
    raise exception 'Only a Cloud admin of this church can retire its DNA Rhythms.'
      using errcode = '42501';
  end if;

  select count(*) into v_count
    from public._dna_rhythm_linked_items(p_dna_rhythm_id);

  -- The BEFORE DELETE trigger (C.2) releases the members' copies; the FK then
  -- clears their dna_rhythm_id.
  delete from public.dna_rhythms where id = p_dna_rhythm_id;

  return v_count;
end;
$$;

comment on function public.retire_dna_rhythm(uuid) is
  'Cloud admin: retire one of the church''s DNA Rhythms. Members keep their copy '
  'as their own rhythm with a 7-day free-edit window; nothing of theirs is '
  'deleted. Returns the number of members'' rhythms released.';

revoke execute on function public.retire_dna_rhythm(uuid) from public, anon;
grant  execute on function public.retire_dna_rhythm(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- D. Season end: retire every DNA Rhythm whose last day has passed
-- -----------------------------------------------------------------------------
-- D.1  Retires every DNA Rhythm with ends_on before today (UTC calendar) by
--      deleting it — section C's trigger releases the members' copies. Returns
--      how many DNA Rhythms were retired. Service role / scheduled job only.
create or replace function public.retire_expired_dna_rhythms()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  delete from public.dna_rhythms
   where ends_on is not null
     and ends_on < (now() at time zone 'utc')::date;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.retire_expired_dna_rhythms() from public, anon, authenticated;
grant  execute on function public.retire_expired_dna_rhythms() to service_role;

-- D.2  The schedule: every day at 05:00 UTC (midnight US Central in summer,
--      11 p.m. the evening before in winter), job name `trellis-dna-season-end`.
--      A rhythm is in force through the whole of its ends_on day everywhere in
--      the US before this runs.
--
--      Wrapped so that a project without pg_cron still gets everything else in
--      this file (same pattern as 021 E.5). If the notice below appears:
--      Dashboard -> Database -> Extensions -> enable pg_cron, then run this one
--      DO block again.
do $do$
declare
  v_jobid bigint;
begin
  create extension if not exists pg_cron;

  -- Start clean: remove any earlier job of this name before scheduling.
  for v_jobid in
    select jobid from cron.job where jobname = 'trellis-dna-season-end'
  loop
    perform cron.unschedule(v_jobid);
  end loop;

  perform cron.schedule(
    'trellis-dna-season-end',
    '0 5 * * *',
    'select public.retire_expired_dna_rhythms();'
  );

  raise notice '023: DNA season-end job scheduled (job trellis-dna-season-end, daily 05:00 UTC).';
exception when others then
  raise notice '023: the DNA season-end job was NOT scheduled: % (SQLSTATE %).', sqlerrm, sqlstate;
  raise notice '023: to fix: Dashboard -> Database -> Extensions -> enable pg_cron, then re-run the DO block in section D.2 of 023_dna_seasons_merge_welcome.sql. Nothing else in this file depends on it.';
end
$do$;


-- -----------------------------------------------------------------------------
-- E. Merging a Runner's own rhythm into a church rhythm
-- -----------------------------------------------------------------------------
-- The case: a Runner already had "Rest on Sunday" when the church added the
-- DNA Rhythm "Sabbath Rest". 016's adopt-by-name could not see they are the
-- same, so the Runner now has two rhythms for one habit. This folds the
-- Runner's own rhythm (p_own_item_id) into the church one (p_dna_item_id):
--
--   * Both rows must belong to the caller (42501 otherwise), be different rows,
--     the own item must NOT be church-mandated, and the DNA item must be a
--     church rhythm (is_church_mandated, or linked to a DNA Rhythm) — 22023 for
--     a bad pair.
--   * Check-ins move from the own item to the DNA item. On a date where BOTH
--     have an answer, the DNA item's answer is kept and the own item's is
--     dropped (check_ins is unique per rhythm and day).
--   * Then the own item is deleted. Because this runs as the function owner,
--     021's delete guard (clients only) does not apply — and that is right: the
--     habit continues under the church rhythm with its history intact, so the
--     Rule of Life is not weakened by this removal. The "set" lock is therefore
--     not consulted here.
--   * Returns the number of check-ins moved.
--
-- What happens to everything else that pointed at the own item:
--   * check_ins (init, ON DELETE CASCADE): none left to cascade — every row
--     was moved or, on a shared date, deliberately dropped.
--   * grace_nudges (init, ON DELETE CASCADE): moved to the DNA item first, so
--     a Witness's nudge history survives.
--   * support_requests.rule_item_id (014, ON DELETE SET NULL): re-pointed at
--     the DNA item first, so the request keeps its "which rhythm" context.
--   * pending_unlock_requests (003, ON DELETE CASCADE): allowed to cascade. A
--     request still pending for the own item is moot once the rhythm is folded
--     away (the Witness's list simply no longer shows it); resolved ones are
--     history about a rhythm that no longer exists.
--   * weekly_roll_ups (021): carries counts only, no link to rule_items.
-- The DNA item itself is not changed (its anchor flag, schedule and title stay
-- as the church set them).
create or replace function public.merge_rule_item_into_dna(
  p_own_item_id uuid,
  p_dna_item_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_own   public.rule_items%rowtype;
  v_dna   public.rule_items%rowtype;
  v_moved integer := 0;
begin
  if v_uid is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  if p_own_item_id is null or p_dna_item_id is null or p_own_item_id = p_dna_item_id then
    raise exception 'Choose two different rhythms to merge.' using errcode = '22023';
  end if;

  select * into v_own from public.rule_items where id = p_own_item_id for update;
  if not found or v_own.runner_id is distinct from v_uid then
    raise exception 'That rhythm is not yours.' using errcode = '42501';
  end if;

  select * into v_dna from public.rule_items where id = p_dna_item_id for update;
  if not found or v_dna.runner_id is distinct from v_uid then
    raise exception 'That rhythm is not yours.' using errcode = '42501';
  end if;

  if v_own.is_church_mandated then
    raise exception 'Only one of your own rhythms can be folded into a church rhythm.'
      using errcode = '22023';
  end if;

  if not (v_dna.is_church_mandated or v_dna.dna_rhythm_id is not null) then
    raise exception 'The rhythm to keep must be a church (DNA) rhythm.'
      using errcode = '22023';
  end if;

  -- A day both rhythms answered: keep the church rhythm's answer.
  delete from public.check_ins own_ci
   where own_ci.rule_item_id = p_own_item_id
     and exists (
       select 1 from public.check_ins dna_ci
        where dna_ci.rule_item_id = p_dna_item_id
          and dna_ci.check_in_date = own_ci.check_in_date
     );

  update public.check_ins
     set rule_item_id = p_dna_item_id
   where rule_item_id = p_own_item_id;
  get diagnostics v_moved = row_count;

  update public.grace_nudges
     set rule_item_id = p_dna_item_id
   where rule_item_id = p_own_item_id;

  update public.support_requests
     set rule_item_id = p_dna_item_id
   where rule_item_id = p_own_item_id;

  delete from public.rule_items where id = p_own_item_id;

  return v_moved;
end;
$$;

comment on function public.merge_rule_item_into_dna(uuid, uuid) is
  'Runner: fold one of your own rhythms into one of your church (DNA) rhythms. '
  'Check-ins move across (the church rhythm''s answer wins on a shared day), then '
  'the own rhythm is removed. Returns the number of check-ins moved.';

revoke execute on function public.merge_rule_item_into_dna(uuid, uuid) from public, anon;
grant  execute on function public.merge_rule_item_into_dna(uuid, uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- F. Welcome walkthrough
-- -----------------------------------------------------------------------------
-- Existing accounts get false and so see the walkthrough once — intended.
alter table public.profiles
  add column if not exists has_seen_welcome boolean not null default false;

comment on column public.profiles.has_seen_welcome is
  'Whether this account has been shown the welcome walkthrough (Runner / Witness '
  '/ Cloud slides). The app sets it true after the first viewing; the walkthrough '
  'stays reachable from the menu.';

-- 011 gives clients column-by-column SELECT and UPDATE on profiles, so the new
-- column is invisible and unwritable until granted. It is the owner's own
-- preference, so (unlike rule_committed_at) they may write it; row visibility
-- is unchanged and guard_profile_update (011/019) does not list it.
grant select (has_seen_welcome) on public.profiles to authenticated;
grant update (has_seen_welcome) on public.profiles to authenticated;


-- -----------------------------------------------------------------------------
-- G. Grants, all in one place
-- -----------------------------------------------------------------------------
-- Every function this file creates or replaces, and who may call it. (Each is
-- also stated next to its definition above; repeated here so the whole picture
-- is one screen. 019's allowlist is not edited and does not need to be: it
-- only ever narrows what it names, and names none of these.)
--
--   client (authenticated)        retire_dna_rhythm(uuid)
--                                 merge_rule_item_into_dna(uuid, uuid)
--                                 redeem_church_code(text)
--   service_role / job only       retire_expired_dna_rhythms()
--   internal (nobody directly)    apply_dna_rhythm_to_members(uuid, text, rule_category, rule_frequency, smallint[], uuid)
--                                 _dna_rhythm_linked_items(uuid)
--   trigger functions             propagate_new_dna_rhythm(), propagate_dna_rhythm_edit(),
--   (not directly callable)       release_dna_rhythm_members(), guard_rule_item_insert(),
--                                 guard_rule_item_update()
revoke execute on function public.retire_dna_rhythm(uuid)                 from public, anon;
grant  execute on function public.retire_dna_rhythm(uuid)                 to authenticated;
revoke execute on function public.merge_rule_item_into_dna(uuid, uuid)    from public, anon;
grant  execute on function public.merge_rule_item_into_dna(uuid, uuid)    to authenticated;
revoke execute on function public.redeem_church_code(text)                from public, anon;
grant  execute on function public.redeem_church_code(text)                to authenticated;
revoke execute on function public.retire_expired_dna_rhythms()            from public, anon, authenticated;
grant  execute on function public.retire_expired_dna_rhythms()            to service_role;
revoke execute on function public.apply_dna_rhythm_to_members(
  uuid, text, public.rule_category, public.rule_frequency, smallint[], uuid) from public, anon, authenticated;
revoke execute on function public._dna_rhythm_linked_items(uuid)          from public, anon, authenticated;
revoke execute on function public.propagate_new_dna_rhythm()              from public, anon;
grant  execute on function public.propagate_new_dna_rhythm()              to authenticated, service_role;
revoke execute on function public.propagate_dna_rhythm_edit()             from public, anon;
grant  execute on function public.propagate_dna_rhythm_edit()             to authenticated, service_role;
revoke execute on function public.release_dna_rhythm_members()            from public, anon;
grant  execute on function public.release_dna_rhythm_members()            to authenticated, service_role;
revoke execute on function public.guard_rule_item_insert()                from public, anon;
grant  execute on function public.guard_rule_item_insert()                to authenticated, service_role;
revoke execute on function public.guard_rule_item_update()                from public, anon;
grant  execute on function public.guard_rule_item_update()                to authenticated, service_role;


-- =============================================================================
-- H. VERIFICATION — run in the SQL editor and compare with "expect"
-- =============================================================================
-- Several blocks act as a signed-in user with `set local role` (as 018–021 do).
-- Replace the <...> placeholders with real test ids. A block that ends in an
-- expected ERROR must be run on its own: the error aborts that transaction, and
-- the `rollback;` on its last line cleans up. Every dry run below ends in
-- rollback, so nothing is kept.
--
-- 0. Privileges at a glance. Expect, in order:
--    false, true,  true     retire_dna_rhythm: not anon; signed-in users; service role
--    false, true,  true     merge_rule_item_into_dna: same
--    false, false, true     retire_expired_dna_rhythms: clients no; service role yes
--    false, false, true     apply_dna_rhythm_to_members (6 args): internal
--    false, false, true     _dna_rhythm_linked_items: internal
--    true,  false           rule_items.dna_rhythm_id: clients read, never update
--    true,  true,  true     dna_rhythms.ends_on: clients read / insert / update (RLS narrows to the church's admin)
--    true,  true            profiles.has_seen_welcome: clients read and update
--
--   select has_function_privilege('anon',          'public.retire_dna_rhythm(uuid)', 'execute'),
--          has_function_privilege('authenticated', 'public.retire_dna_rhythm(uuid)', 'execute'),
--          has_function_privilege('service_role',  'public.retire_dna_rhythm(uuid)', 'execute');
--   select has_function_privilege('anon',          'public.merge_rule_item_into_dna(uuid,uuid)', 'execute'),
--          has_function_privilege('authenticated', 'public.merge_rule_item_into_dna(uuid,uuid)', 'execute'),
--          has_function_privilege('service_role',  'public.merge_rule_item_into_dna(uuid,uuid)', 'execute');
--   select has_function_privilege('anon',          'public.retire_expired_dna_rhythms()', 'execute'),
--          has_function_privilege('authenticated', 'public.retire_expired_dna_rhythms()', 'execute'),
--          has_function_privilege('service_role',  'public.retire_expired_dna_rhythms()', 'execute');
--   select has_function_privilege('anon',          'public.apply_dna_rhythm_to_members(uuid,text,public.rule_category,public.rule_frequency,smallint[],uuid)', 'execute'),
--          has_function_privilege('authenticated', 'public.apply_dna_rhythm_to_members(uuid,text,public.rule_category,public.rule_frequency,smallint[],uuid)', 'execute'),
--          has_function_privilege('service_role',  'public.apply_dna_rhythm_to_members(uuid,text,public.rule_category,public.rule_frequency,smallint[],uuid)', 'execute');
--   select has_function_privilege('anon',          'public._dna_rhythm_linked_items(uuid)', 'execute'),
--          has_function_privilege('authenticated', 'public._dna_rhythm_linked_items(uuid)', 'execute'),
--          has_function_privilege('service_role',  'public._dna_rhythm_linked_items(uuid)', 'execute');
--   select has_column_privilege('authenticated', 'public.rule_items', 'dna_rhythm_id', 'select'),
--          has_column_privilege('authenticated', 'public.rule_items', 'dna_rhythm_id', 'update');
--   select has_column_privilege('authenticated', 'public.dna_rhythms', 'ends_on', 'select'),
--          has_column_privilege('authenticated', 'public.dna_rhythms', 'ends_on', 'insert'),
--          has_column_privilege('authenticated', 'public.dna_rhythms', 'ends_on', 'update');
--   select has_column_privilege('authenticated', 'public.profiles', 'has_seen_welcome', 'select'),
--          has_column_privilege('authenticated', 'public.profiles', 'has_seen_welcome', 'update');
--
--    Exactly one apply_dna_rhythm_to_members remains, with six arguments (expect 1 row, pronargs = 6):
--      select oid::regprocedure, pronargs from pg_proc
--       where proname = 'apply_dna_rhythm_to_members' and pronamespace = 'public'::regnamespace;
--
-- A. The link.
--    The column, its FK and index exist (expect one row each):
--      select conname, pg_get_constraintdef(oid) from pg_constraint
--       where conrelid = 'public.rule_items'::regclass and conname like '%dna_rhythm_id%';     -- ... ON DELETE SET NULL
--      select indexname from pg_indexes where tablename = 'rule_items' and indexname = 'rule_items_dna_rhythm_idx';
--    How the backfill went. First: church rhythms still unlinked (expect only
--    rows whose title no longer matches any DNA Rhythm of their church, or
--    matches two):
--      select p.church_id, ri.title, ri.category, count(*) as members
--        from public.rule_items ri join public.profiles p on p.id = ri.runner_id
--       where ri.is_church_mandated and ri.dna_rhythm_id is null
--       group by 1, 2, 3 order by 1, 2;
--    Second: no link points at a rhythm of a DIFFERENT church (expect 0):
--      select count(*) from public.rule_items ri
--        join public.profiles p on p.id = ri.runner_id
--        join public.dna_rhythms d on d.id = ri.dna_rhythm_id
--       where d.church_id is distinct from p.church_id;
--    A new DNA Rhythm reaches every member linked (as the SQL editor's role; rolled back):
--      begin;
--      insert into public.dna_rhythms (church_id, title, category, frequency, weekly_days)
--      values ('<church-uuid>', '023 probe', 'community_hospitality', 'weekly', '{7}');
--      select count(*) filter (where ri.dna_rhythm_id = d.id) as linked, count(*) as total
--        from public.rule_items ri
--        join public.profiles p on p.id = ri.runner_id
--        join public.dna_rhythms d on d.church_id = p.church_id and d.title = '023 probe'
--       where ri.title = '023 probe' and p.church_id = '<church-uuid>';            -- linked = total = member count
--      rollback;
--    A client cannot set the link on insert (expect dna_rhythm_id null) nor change
--    it on update (expect ERROR 42501 permission denied — the column grant stops
--    it before the guard does; run the update in its own block):
--      begin;
--      set local role authenticated;
--      select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--      insert into public.rule_items (runner_id, category, title, frequency, dna_rhythm_id)
--      values (auth.uid(), 'abiding_prayer', '023 insert probe', 'daily', '<dna-rhythm-uuid>')
--      returning dna_rhythm_id;                                                     -- null
--      rollback;
--      -- update public.rule_items set dna_rhythm_id = null where runner_id = auth.uid();   -- ERROR 42501
--
-- B. Seasons. A Cloud admin can set and clear ends_on through a direct update,
--    as the app does (expect UPDATE 1 twice; rolled back):
--      begin;
--      set local role authenticated;
--      select set_config('request.jwt.claims', '{"sub":"<cloud-admin-uuid>","role":"authenticated"}', true);
--      update public.dna_rhythms set ends_on = current_date + 30 where id = '<dna-rhythm-uuid>';
--      update public.dna_rhythms set ends_on = null where id = '<dna-rhythm-uuid>';
--      rollback;
--    Setting ends_on alone touches no member's rhythm (same block, add before rollback;
--    expect 0 — the propagation trigger only fires for title/category/schedule changes):
--      select count(*) from public.rule_items where dna_rhythm_id = '<dna-rhythm-uuid>' and not is_church_mandated;
--
-- C. Retiring — rolled-back dry run as the church's Cloud admin. Pick a DNA
--    Rhythm that members have. Expect: the function returns the member count;
--    afterwards every former copy is still there, no longer mandated, with
--    unlocked_until about 7 days ahead and dna_rhythm_id null; check-ins untouched.
--      begin;
--      select count(*) as copies_before from public.rule_items where dna_rhythm_id = '<dna-rhythm-uuid>';
--      select count(*) as check_ins_before from public.check_ins ci
--        join public.rule_items ri on ri.id = ci.rule_item_id where ri.dna_rhythm_id = '<dna-rhythm-uuid>';
--      create temp table probe_items as select id from public.rule_items where dna_rhythm_id = '<dna-rhythm-uuid>';
--      set local role authenticated;
--      select set_config('request.jwt.claims', '{"sub":"<cloud-admin-uuid>","role":"authenticated"}', true);
--      select public.retire_dna_rhythm('<dna-rhythm-uuid>');                        -- = copies_before
--      reset role;
--      select count(*) as copies_after,
--             count(*) filter (where not is_church_mandated)                           as released,
--             count(*) filter (where unlocked_until between now() + interval '6 days 23 hours'
--                                                      and now() + interval '7 days 1 hour') as windowed,
--             count(*) filter (where dna_rhythm_id is null)                            as unlinked
--        from public.rule_items where id in (select id from probe_items);           -- all four equal copies_before
--      select count(*) as check_ins_after from public.check_ins
--       where rule_item_id in (select id from probe_items);                          -- = check_ins_before
--      select count(*) from public.dna_rhythms where id = '<dna-rhythm-uuid>';       -- 0
--      rollback;
--    A Cloud admin of a DIFFERENT church, or any Runner, is refused (expect
--    ERROR 42501 "Only a Cloud admin of this church can retire its DNA Rhythms."):
--      begin;
--      set local role authenticated;
--      select set_config('request.jwt.claims', '{"sub":"<unrelated-user-uuid>","role":"authenticated"}', true);
--      select public.retire_dna_rhythm('<dna-rhythm-uuid>');
--      rollback;
--    A direct delete (the app's current removeDnaRhythm) releases the same way
--    (as the SQL editor's role; expect released = member count; rolled back):
--      begin;
--      create temp table probe_items2 as select id from public.rule_items where dna_rhythm_id = '<dna-rhythm-uuid>';
--      delete from public.dna_rhythms where id = '<dna-rhythm-uuid>';
--      select count(*) filter (where not is_church_mandated and dna_rhythm_id is null) as released
--        from public.rule_items where id in (select id from probe_items2);
--      rollback;
--    The trigger is in place (expect dna_rhythms_release_members among the rows,
--    with dna_rhythms_normalize, dna_rhythms_propagate_edit, dna_rhythms_propagate_new):
--      select tgname from pg_trigger where tgrelid = 'public.dna_rhythms'::regclass and not tgisinternal order by 1;
--
-- D. Season end.
--    The job exists (expect one row: schedule `0 5 * * *`, active = true). If
--    this errors with "relation cron.job does not exist", pg_cron is not
--    enabled — see section D.2:
--      select jobid, jobname, schedule, command, active
--        from cron.job where jobname = 'trellis-dna-season-end';
--    After its first run, how it went:
--      select status, return_message, start_time
--        from cron.job_run_details
--       where jobid = (select jobid from cron.job where jobname = 'trellis-dna-season-end')
--       order by start_time desc limit 5;
--    By hand, rolled back: date one rhythm's season to yesterday, run the job's
--    function, and watch it retire exactly that one (expect 1, then 0 rows):
--      begin;
--      update public.dna_rhythms set ends_on = current_date - 1 where id = '<dna-rhythm-uuid>';
--      select public.retire_expired_dna_rhythms();                                   -- 1 (plus any already overdue)
--      select count(*) from public.dna_rhythms where id = '<dna-rhythm-uuid>';       -- 0
--      rollback;
--    A rhythm whose last day is TODAY is still in force (expect 0 retired; rolled back):
--      begin;
--      update public.dna_rhythms set ends_on = (now() at time zone 'utc')::date where id = '<dna-rhythm-uuid>';
--      select public.retire_expired_dna_rhythms();                                   -- 0 (if nothing else is overdue)
--      rollback;
--    Clients cannot run it (expect ERROR 42501 permission denied):
--      begin;
--      set local role authenticated;
--      select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--      select public.retire_expired_dna_rhythms();
--      rollback;
--
-- E. Merging — rolled-back dry run as a Runner who has a church rhythm
--    <dna-item-uuid> and one of their own <own-item-uuid>, both with some
--    check-ins. Expect: the function returns the number of the own item's
--    check-in days that the church rhythm had NOT already answered; afterwards
--    the own item is gone, the church rhythm has own + dna − shared rows, and
--    no check-in is left pointing at the own item.
--      begin;
--      select (select count(*) from public.check_ins where rule_item_id = '<own-item-uuid>') as own_rows,
--             (select count(*) from public.check_ins where rule_item_id = '<dna-item-uuid>') as dna_rows,
--             (select count(*) from public.check_ins a join public.check_ins b on a.check_in_date = b.check_in_date
--               where a.rule_item_id = '<own-item-uuid>' and b.rule_item_id = '<dna-item-uuid>') as shared_days;
--      set local role authenticated;
--      select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--      select public.merge_rule_item_into_dna('<own-item-uuid>', '<dna-item-uuid>');   -- = own_rows − shared_days
--      reset role;
--      select count(*) from public.rule_items where id = '<own-item-uuid>';            -- 0
--      select count(*) from public.check_ins  where rule_item_id = '<dna-item-uuid>';  -- = own_rows + dna_rows − shared_days
--      select count(*) from public.check_ins  where rule_item_id = '<own-item-uuid>';  -- 0
--      rollback;
--    Refusals, each in its own block with the same `set local role` preamble:
--      select public.merge_rule_item_into_dna('<own-item-uuid>', '<own-item-uuid>');
--        -- ERROR 22023 "Choose two different rhythms to merge."
--      select public.merge_rule_item_into_dna('<dna-item-uuid>', '<own-item-uuid>');
--        -- ERROR 22023 "Only one of your own rhythms can be folded into a church rhythm."
--      select public.merge_rule_item_into_dna('<own-item-uuid>', '<another-own-item-uuid>');
--        -- ERROR 22023 "The rhythm to keep must be a church (DNA) rhythm."
--      select public.merge_rule_item_into_dna('<someone-elses-item-uuid>', '<dna-item-uuid>');
--        -- ERROR 42501 "That rhythm is not yours."
--
-- F. Welcome flag. Existing accounts start at false (expect 0 true rows right
--    after this migration):
--      select has_seen_welcome, count(*) from public.profiles group by 1;
--    The owner can set it (expect true; rolled back):
--      begin;
--      set local role authenticated;
--      select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--      update public.profiles set has_seen_welcome = true where id = auth.uid();
--      select has_seen_welcome from public.profiles where id = auth.uid();           -- true
--      rollback;
--
-- G. Triggers on rule_items are unchanged in shape (expect rule_items_guard_delete,
--    rule_items_guard_insert, rule_items_guard_update, rule_items_normalize):
--      select tgname from pg_trigger where tgrelid = 'public.rule_items'::regclass and not tgisinternal order by 1;
-- =============================================================================
