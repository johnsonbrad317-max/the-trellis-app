-- =============================================================================
-- The Trellis — 028_departure_notices.sql   (a Witness is told when a Runner leaves)
-- =============================================================================
-- Run AFTER 026. Idempotent — safe to run more than once.
--
-- Why: when a Runner deletes their account, everything about them is deleted
-- at once — their pairing included — so they vanish from their Witness's
-- Runners list. delete-account already pushes each Witness ("Account Deleted"),
-- but a Witness who missed that push, had notifications off, or never had a
-- device token simply found the Runner gone, with no word of why. The app
-- "forgot they ever existed".
--
-- What this file does, in plain English:
--
--   A. Table witness_notices: one small note per Witness, kept on the WITNESS's
--      side. It holds the departed Runner's FIRST NAME ONLY — no id, no email,
--      no link to the deleted account (there is deliberately no foreign key to
--      them; their row is about to disappear). A Witness can read their own
--      notes; no client can write, change or delete one.
--
--   B. record_runner_departure(runner) — called by delete-account (service
--      role) just BEFORE the account is deleted: one note per ACTIVE Witness of
--      that Runner. retract_runner_departure(runner) undoes it if the deletion
--      then fails, so nobody is told "Sarah has left" while Sarah is still here.
--
--   C. get_my_witness_notices() and mark_witness_notice_seen(id) — what the app
--      calls: the Witness's unseen notes, newest first; then "I've read it".
--
--   D. Housekeeping: a note is deleted 30 days after it was written, or 7 days
--      after it was seen, whichever comes first (daily pg_cron job
--      trellis-notice-cleanup, 04:00 UTC). So the departed person's first name
--      is kept for AT MOST 30 days — the privacy policy should say so.
--
--   E. Last-seen stays private: revokes SELECT on profiles.last_seen_at and
--      profiles.app_removed_at from every client (the owner's decision: a
--      Witness or a church leader has no need to see when a Runner last opened
--      the app). 026 itself no longer grants them; this covers a database where
--      the earlier draft of 026 already ran.
--
--   F. Grants, all in one place.
--
--   G. Verification queries (bottom of the file).
--
-- Client contract (lib/models/runner_profile.dart → refreshWitnessNotices,
-- markWitnessNoticeSeen; shown by lib/widgets/departure_notice.dart):
--   rpc('get_my_witness_notices') →
--       [{"id": uuid, "kind": "runner_left", "runner_first_name": "Sarah",
--         "created_at": timestamptz}, ...]      unseen, own, newest first;
--                                               notes older than 30 days are
--                                               never returned
--   rpc('mark_witness_notice_seen', {p_id}) → true (marked) | false (not
--       yours, unknown, or already seen). Errors: 28000 not signed in.
--   Before this file is applied the app gets PGRST202 (no such function) and
--   simply shows nothing.
--
-- Server contract (supabase/functions/delete-account):
--   rpc('record_runner_departure', {p_runner_id}) → integer, notes written.
--   rpc('retract_runner_departure', {p_runner_id}) → integer, notes removed.
--   Both service role only.
--
-- ALSO REQUIRED ALONGSIDE THIS FILE (not SQL):
--   * Redeploy delete-account (it now calls record_runner_departure before the
--     deletion, and retract_runner_departure if the deletion fails):
--       supabase functions deploy delete-account
--     In either order: an old delete-account against this file writes no
--     notes; the new one against a database without this file logs the missing
--     function and deletes the account exactly as before.
--   * Section D.3 needs pg_cron (021 E.5 and 026 needed it too). Without it
--     everything else here still applies (unseen notes past 30 days are already
--     hidden from the app), and the DO block prints what to do.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- A. witness_notices
-- -----------------------------------------------------------------------------
-- A.1  witness_id is the WITNESS (the reader). Deleted with the Witness's own
--      account. Nothing points at the departed Runner.
create table if not exists public.witness_notices (
  id                 uuid primary key default gen_random_uuid(),
  witness_id         uuid not null references public.profiles (id) on delete cascade,
  kind               text not null,
  runner_first_name  text not null,
  created_at         timestamptz not null default now(),
  seen_at            timestamptz,
  constraint witness_notices_kind_known
    check (kind in ('runner_left')),
  constraint witness_notices_first_name_short
    check (length(runner_first_name) between 1 and 40)
);

comment on table public.witness_notices is
  'One-time notes shown to a Witness in the app — today only "runner_left": a '
  'Runner they walked with deleted their account. Holds the departed person''s '
  'first name only, and nothing that links back to them. Written only by '
  'record_runner_departure() (delete-account); deleted 30 days after creation '
  'or 7 days after being seen (cleanup_witness_notices, pg_cron '
  'trellis-notice-cleanup).';

comment on column public.witness_notices.runner_first_name is
  'The departed Runner''s first name (first word of profiles.name), or '
  '''Your Runner'' when they had none. The only thing kept about them.';

create index if not exists witness_notices_witness_idx
  on public.witness_notices (witness_id, created_at desc);

-- A.2  RLS: a Witness may read their own notes; nobody writes from the client
--      (writes happen only inside the functions below, which run as the owner).
alter table public.witness_notices enable row level security;

drop policy if exists "witness_notices_select_own" on public.witness_notices;
create policy "witness_notices_select_own"
  on public.witness_notices for select
  to authenticated
  using (witness_id = auth.uid());

-- New tables get no default grants in this project — say exactly who gets what.
revoke all on public.witness_notices from public, anon, authenticated;
grant select on public.witness_notices to authenticated;
grant all    on public.witness_notices to service_role;


-- -----------------------------------------------------------------------------
-- B. Writing (and un-writing) the notes — delete-account only
-- -----------------------------------------------------------------------------
-- B.1  The first name kept for a departed Runner: the first word of
--      profiles.name, at most 40 characters; 'Your Runner' when there is no
--      name. Used by both functions below so they always agree.
create or replace function public.departure_first_name(p_name text)
returns text
language sql
immutable
set search_path = public
as $$
  select coalesce(
    nullif(left(split_part(regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g'), ' ', 1), 40), ''),
    'Your Runner'
  );
$$;

comment on function public.departure_first_name(text) is
  'First word of a name (max 40 chars), or ''Your Runner''. Helper for '
  'record_runner_departure / retract_runner_departure.';

revoke execute on function public.departure_first_name(text) from public, anon, authenticated;
grant  execute on function public.departure_first_name(text) to service_role;

-- B.2  record_runner_departure: one runner_left note per ACTIVE Witness of
--      p_runner_id (a self-pairing is skipped). Called by delete-account BEFORE
--      it deletes the account — afterwards the pairings and the name are gone.
--      A retry of a failed deletion does not write a second note: a Witness
--      who already has an UNSEEN note with the same first name from the last
--      day is skipped. Returns how many notes were written (0 for a Runner
--      with no Witnesses, or an unknown id).
create or replace function public.record_runner_departure(p_runner_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_first text;
  v_rows  integer;
begin
  if p_runner_id is null then
    return 0;
  end if;

  select public.departure_first_name(p.name)
    into v_first
    from public.profiles p
   where p.id = p_runner_id;

  if not found then
    return 0;
  end if;

  insert into public.witness_notices (witness_id, kind, runner_first_name)
  select distinct wp.witness_id, 'runner_left', v_first
    from public.witness_pairings wp
   where wp.runner_id = p_runner_id
     and wp.witness_id <> p_runner_id
     and wp.status = 'active'
     and not exists (
       select 1
         from public.witness_notices n
        where n.witness_id = wp.witness_id
          and n.kind = 'runner_left'
          and n.runner_first_name = v_first
          and n.seen_at is null
          and n.created_at > now() - interval '1 day'
     );

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

comment on function public.record_runner_departure(uuid) is
  'delete-account, just before deleting p_runner_id: writes one runner_left '
  'witness_notices row (first name only) per active Witness. Skips a Witness '
  'who already has the same unseen note from the last day. Returns rows '
  'written. Service role only.';

revoke execute on function public.record_runner_departure(uuid) from public, anon, authenticated;
grant  execute on function public.record_runner_departure(uuid) to service_role;

-- B.3  retract_runner_departure: the deletion FAILED, so the Runner is still
--      here — remove the notes B.2 just wrote. Without a link to the Runner the
--      notes are found the same way they were made: an active Witness of that
--      Runner, the same first name, unseen, written in the last 15 minutes. If
--      the account did in fact go (a timeout after the delete committed), the
--      pairings are gone too and this removes nothing — the notes stay, as
--      they should. Returns how many notes were removed.
create or replace function public.retract_runner_departure(p_runner_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_first text;
  v_rows  integer;
begin
  if p_runner_id is null then
    return 0;
  end if;

  select public.departure_first_name(p.name)
    into v_first
    from public.profiles p
   where p.id = p_runner_id;

  if not found then
    return 0;
  end if;

  delete from public.witness_notices n
   using public.witness_pairings wp
   where wp.runner_id = p_runner_id
     and wp.witness_id <> p_runner_id
     and wp.status = 'active'
     and n.witness_id = wp.witness_id
     and n.kind = 'runner_left'
     and n.runner_first_name = v_first
     and n.seen_at is null
     and n.created_at > now() - interval '15 minutes';

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

comment on function public.retract_runner_departure(uuid) is
  'delete-account, when the deletion of p_runner_id failed: removes the unseen '
  'runner_left notes written for their active Witnesses in the last 15 '
  'minutes. Returns rows removed. Service role only.';

revoke execute on function public.retract_runner_departure(uuid) from public, anon, authenticated;
grant  execute on function public.retract_runner_departure(uuid) to service_role;


-- -----------------------------------------------------------------------------
-- C. Reading the notes — the app
-- -----------------------------------------------------------------------------
-- C.1  The caller's unseen notes, newest first. Notes over 30 days old are
--      never returned, even if housekeeping (D) has not run. At most 20.
--      Errors: 28000 not signed in.
create or replace function public.get_my_witness_notices()
returns table (id uuid, kind text, runner_first_name text, created_at timestamptz)
language plpgsql
security definer
stable
set search_path = public
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'You must be signed in.'
      using errcode = '28000';
  end if;

  return query
    select n.id, n.kind, n.runner_first_name, n.created_at
      from public.witness_notices n
     where n.witness_id = v_me
       and n.seen_at is null
       and n.created_at > now() - interval '30 days'
     order by n.created_at desc
     limit 20;
end;
$$;

comment on function public.get_my_witness_notices() is
  'The caller''s unseen witness_notices (id, kind, runner_first_name, '
  'created_at), newest first, none older than 30 days, at most 20.';

revoke execute on function public.get_my_witness_notices() from public, anon;
grant  execute on function public.get_my_witness_notices() to authenticated;

-- C.2  "I've read it." Only the caller's own note, only once. Returns true when
--      a note was marked, false when it is not theirs, unknown, or already
--      seen (the same answer for all three — nobody learns whether someone
--      else's note id exists). Errors: 28000 not signed in.
create or replace function public.mark_witness_notice_seen(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'You must be signed in.'
      using errcode = '28000';
  end if;

  update public.witness_notices
     set seen_at = now()
   where id = p_id
     and witness_id = v_me
     and seen_at is null;

  return found;
end;
$$;

comment on function public.mark_witness_notice_seen(uuid) is
  'Marks one of the caller''s own witness_notices as seen. True if marked.';

revoke execute on function public.mark_witness_notice_seen(uuid) from public, anon;
grant  execute on function public.mark_witness_notice_seen(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- D. Housekeeping
-- -----------------------------------------------------------------------------
-- D.1  Deletes notes written more than 30 days ago, and notes seen more than 7
--      days ago. Returns how many were deleted.
--
--      Its own small job rather than a line in an existing one: the only daily
--      jobs belong to 023 and 026, whose functions those files re-create on a
--      re-run — which would silently drop an added line (the same reasoning as
--      021 B and 025 B).
create or replace function public.cleanup_witness_notices()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows integer;
begin
  delete from public.witness_notices
   where created_at < now() - interval '30 days'
      or seen_at    < now() - interval '7 days';

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

comment on function public.cleanup_witness_notices() is
  'Daily (pg_cron trellis-notice-cleanup): deletes witness_notices written over '
  '30 days ago or seen over 7 days ago. Returns rows deleted.';

revoke execute on function public.cleanup_witness_notices() from public, anon, authenticated;
grant  execute on function public.cleanup_witness_notices() to service_role;

-- D.2  (No muting switch: a note is shown once, in the app, and never pushed.)

-- D.3  The schedule: every day at 04:00 UTC, job name `trellis-notice-cleanup`.
--      Wrapped so that a project without pg_cron still gets everything else in
--      this file (same pattern as 021 E.5 and 026 D.3). If the notice below
--      appears: Dashboard -> Database -> Extensions -> enable pg_cron, then run
--      this one DO block again.
do $do$
declare
  v_jobid bigint;
begin
  create extension if not exists pg_cron;

  -- Start clean: remove any earlier job of this name before scheduling.
  for v_jobid in
    select jobid from cron.job where jobname = 'trellis-notice-cleanup'
  loop
    perform cron.unschedule(v_jobid);
  end loop;

  perform cron.schedule(
    'trellis-notice-cleanup',
    '0 4 * * *',
    'select public.cleanup_witness_notices();'
  );

  raise notice '028: notice cleanup scheduled (job trellis-notice-cleanup, daily 04:00 UTC).';
exception when others then
  raise notice '028: the notice cleanup job was NOT scheduled: % (SQLSTATE %).', sqlerrm, sqlstate;
  raise notice '028: to fix: Dashboard -> Database -> Extensions -> enable pg_cron, then re-run the DO block in section D.3 of 028_departure_notices.sql. Nothing else in this file depends on it.';
end
$do$;


-- -----------------------------------------------------------------------------
-- E. Last-seen is private
-- -----------------------------------------------------------------------------
-- No client — the person, their Witnesses, their church's Cloud admin — may
-- read profiles.last_seen_at or profiles.app_removed_at (nor write them; 026
-- never granted that). Only touch_last_seen(), record_app_removed() and the
-- nudge/probe functions use them, and they are SECURITY DEFINER, so they need
-- no column grant. The app never selects either column.
-- (A column-level revoke cannot undo a table-level grant; 011 removed the
-- table-level ones, so this is the whole story.)
-- Guarded so this file still runs on a database where 026 has not been
-- applied yet (then there is nothing to revoke).
do $do$
begin
  if exists (
       select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'profiles'
          and column_name = 'last_seen_at'
     ) and exists (
       select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'profiles'
          and column_name = 'app_removed_at'
     ) then
    revoke select (last_seen_at, app_removed_at),
           update (last_seen_at, app_removed_at)
      on public.profiles from anon, authenticated;
    raise notice '028: profiles.last_seen_at / app_removed_at are private to the server.';
  else
    raise notice '028: profiles.last_seen_at / app_removed_at do not exist yet (026 not applied) — nothing to revoke. 026 itself grants clients nothing on them.';
  end if;
end
$do$;


-- -----------------------------------------------------------------------------
-- F. Grants, all in one place
-- -----------------------------------------------------------------------------
--   client (authenticated)        get_my_witness_notices()
--                                 mark_witness_notice_seen(uuid)
--   service role / pg_cron only   record_runner_departure(uuid)
--                                 retract_runner_departure(uuid)
--                                 cleanup_witness_notices()
--                                 departure_first_name(text)
--   table                         witness_notices: authenticated SELECT (own
--                                 rows, by RLS); service_role all
--   columns                       profiles.last_seen_at, app_removed_at:
--                                 no client access (E)
revoke execute on function public.get_my_witness_notices()          from public, anon;
grant  execute on function public.get_my_witness_notices()          to authenticated;
revoke execute on function public.mark_witness_notice_seen(uuid)    from public, anon;
grant  execute on function public.mark_witness_notice_seen(uuid)    to authenticated;
revoke execute on function public.record_runner_departure(uuid)     from public, anon, authenticated;
grant  execute on function public.record_runner_departure(uuid)     to service_role;
revoke execute on function public.retract_runner_departure(uuid)    from public, anon, authenticated;
grant  execute on function public.retract_runner_departure(uuid)    to service_role;
revoke execute on function public.cleanup_witness_notices()         from public, anon, authenticated;
grant  execute on function public.cleanup_witness_notices()         to service_role;
revoke execute on function public.departure_first_name(text)        from public, anon, authenticated;
grant  execute on function public.departure_first_name(text)        to service_role;
revoke all on public.witness_notices from public, anon, authenticated;
grant select on public.witness_notices to authenticated;
grant all    on public.witness_notices to service_role;


-- =============================================================================
-- G. VERIFICATION — run in the SQL editor and compare with "expect"
-- =============================================================================
-- Blocks that act as a signed-in user use `set local role` (as 018–027 do).
-- Replace the <...> placeholders with real test ids. A block that ends in an
-- expected ERROR must be run on its own: the error aborts that transaction, and
-- the `rollback;` on its last line cleans up. Every dry run here rolls back.
--
-- 0. Privileges at a glance. Expect, in order:
--    false, true,  true     get_my_witness_notices: not anon; signed-in; service role
--    false, true,  true     mark_witness_notice_seen
--    false, false, true     record_runner_departure
--    false, false, true     retract_runner_departure
--    false, false, true     cleanup_witness_notices
--    false, true,  true     witness_notices SELECT (rows limited by RLS)
--    false, false, false    witness_notices INSERT / UPDATE / DELETE for authenticated
--    false, false           last_seen_at: authenticated cannot read / write
--    false, false           app_removed_at: authenticated cannot read / write
--
--   select has_function_privilege('anon',          'public.get_my_witness_notices()', 'execute'),
--          has_function_privilege('authenticated', 'public.get_my_witness_notices()', 'execute'),
--          has_function_privilege('service_role',  'public.get_my_witness_notices()', 'execute');
--   select has_function_privilege('anon',          'public.mark_witness_notice_seen(uuid)', 'execute'),
--          has_function_privilege('authenticated', 'public.mark_witness_notice_seen(uuid)', 'execute'),
--          has_function_privilege('service_role',  'public.mark_witness_notice_seen(uuid)', 'execute');
--   select has_function_privilege('anon',          'public.record_runner_departure(uuid)', 'execute'),
--          has_function_privilege('authenticated', 'public.record_runner_departure(uuid)', 'execute'),
--          has_function_privilege('service_role',  'public.record_runner_departure(uuid)', 'execute');
--   select has_function_privilege('anon',          'public.retract_runner_departure(uuid)', 'execute'),
--          has_function_privilege('authenticated', 'public.retract_runner_departure(uuid)', 'execute'),
--          has_function_privilege('service_role',  'public.retract_runner_departure(uuid)', 'execute');
--   select has_function_privilege('anon',          'public.cleanup_witness_notices()', 'execute'),
--          has_function_privilege('authenticated', 'public.cleanup_witness_notices()', 'execute'),
--          has_function_privilege('service_role',  'public.cleanup_witness_notices()', 'execute');
--   select has_table_privilege('anon',          'public.witness_notices', 'select'),
--          has_table_privilege('authenticated', 'public.witness_notices', 'select'),
--          has_table_privilege('service_role',  'public.witness_notices', 'select');
--   select has_table_privilege('authenticated', 'public.witness_notices', 'insert'),
--          has_table_privilege('authenticated', 'public.witness_notices', 'update'),
--          has_table_privilege('authenticated', 'public.witness_notices', 'delete');
--   select has_column_privilege('authenticated', 'public.profiles', 'last_seen_at', 'select'),
--          has_column_privilege('authenticated', 'public.profiles', 'last_seen_at', 'update');
--   select has_column_privilege('authenticated', 'public.profiles', 'app_removed_at', 'select'),
--          has_column_privilege('authenticated', 'public.profiles', 'app_removed_at', 'update');
--
-- 1. Structure. Expect: rls = true, 1 policy (witness_notices_select_own); the
--    two check constraints; NO foreign key other than witness_id -> profiles.
--   select c.relrowsecurity as rls,
--          (select count(*) from pg_policies where schemaname = 'public' and tablename = 'witness_notices') as policies
--     from pg_class c where c.oid = 'public.witness_notices'::regclass;
--   select conname, contype, pg_get_constraintdef(oid) from pg_constraint
--    where conrelid = 'public.witness_notices'::regclass order by 1;
--
-- 2. The first-name rule. Expect: 'Sarah', 'Sarah', 'Your Runner', 'Your Runner', 'Cher'.
--   select public.departure_first_name('Sarah Mitchell'),
--          public.departure_first_name('  Sarah   Jane  Mitchell '),
--          public.departure_first_name(''),
--          public.departure_first_name(null),
--          public.departure_first_name('Cher');
--
-- 3. The whole round trip, dry run. Use a Runner and a Witness from your test
--    accounts. Everything rolls back.
--   begin;
--   insert into public.witness_pairings (runner_id, witness_id, status, paired_since)
--   values ('<runner-uuid>', '<witness-uuid>', 'active', now() - interval '5 days')
--   on conflict (runner_id, witness_id) do update set status = 'active';
--
--   -- 3a. Recorded: expect >= 1 (one per active Witness of the Runner), then 0
--   --     on a second call (a retried deletion does not double up).
--   select public.record_runner_departure('<runner-uuid>');
--   select public.record_runner_departure('<runner-uuid>');           -- 0
--   select witness_id, kind, runner_first_name, seen_at from public.witness_notices
--    where witness_id = '<witness-uuid>';
--
--   -- 3b. The Witness sees it (one row, the Runner's first name), marks it
--   --     seen (true), marks it again (false), and then no longer sees it.
--   set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<witness-uuid>","role":"authenticated"}', true);
--   select * from public.get_my_witness_notices();
--   select public.mark_witness_notice_seen(
--            (select id from public.get_my_witness_notices() limit 1));   -- true
--   select public.mark_witness_notice_seen(
--            (select id from public.witness_notices where witness_id = auth.uid() limit 1));  -- false
--   select count(*) from public.get_my_witness_notices();              -- 0
--   reset role;
--
--   -- 3c. Somebody else cannot see or mark it: as the RUNNER, expect 0 rows and
--   --     false.
--   set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   select count(*) from public.witness_notices;                        -- 0 (RLS)
--   select public.mark_witness_notice_seen(
--            (select id from public.witness_notices limit 1));          -- false (null id)
--   reset role;
--
--   -- 3d. Retract after a failed deletion: write a fresh one, then expect
--   --     retract to return >= 1 and the note to be gone.
--   delete from public.witness_notices where witness_id = '<witness-uuid>';
--   select public.record_runner_departure('<runner-uuid>');           -- >= 1
--   select public.retract_runner_departure('<runner-uuid>');          -- >= 1
--   select count(*) from public.witness_notices where witness_id = '<witness-uuid>';   -- 0
--
--   -- 3e. Housekeeping: one old unseen note, one seen 8 days ago, one fresh.
--   --     Expect cleanup to return 2 and the fresh one to remain.
--   insert into public.witness_notices (witness_id, kind, runner_first_name, created_at, seen_at)
--   values ('<witness-uuid>', 'runner_left', 'Old',  now() - interval '31 days', null),
--          ('<witness-uuid>', 'runner_left', 'Seen', now() - interval '10 days', now() - interval '8 days'),
--          ('<witness-uuid>', 'runner_left', 'New',  now(), null);
--   select public.cleanup_witness_notices();                          -- 2
--   select runner_first_name from public.witness_notices where witness_id = '<witness-uuid>';   -- New
--   rollback;
--
-- 4. Clients cannot write notes or call the server-only functions (expect
--    ERROR 42501 permission denied for each; run one at a time):
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<witness-uuid>","role":"authenticated"}', true);
--   insert into public.witness_notices (witness_id, kind, runner_first_name)
--   values (auth.uid(), 'runner_left', 'Nobody');
--   rollback;
--   (likewise: select public.record_runner_departure('<runner-uuid>');
--    select public.retract_runner_departure('<runner-uuid>');
--    select public.cleanup_witness_notices();
--    update public.witness_notices set seen_at = now();
--    delete from public.witness_notices;)
--
-- 5. Last-seen is private (expect ERROR 42501 permission denied — run alone):
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<witness-uuid>","role":"authenticated"}', true);
--   select last_seen_at from public.profiles where id = auth.uid();
--   rollback;
--   And the app's own presence call still works (expect no error):
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<witness-uuid>","role":"authenticated"}', true);
--   select public.touch_last_seen();
--   rollback;
--
-- 6. The job. Expect one row: trellis-notice-cleanup `0 4 * * *`, active. If
--    this errors with "relation cron.job does not exist", pg_cron is not
--    enabled — see D.3:
--   select jobid, jobname, schedule, command, active
--     from cron.job where jobname = 'trellis-notice-cleanup';
--   After the first night, how it went:
--   select d.status, d.return_message, d.start_time
--     from cron.job_run_details d join cron.job j on j.jobid = d.jobid
--    where j.jobname = 'trellis-notice-cleanup'
--    order by d.start_time desc limit 5;
--
-- 7. End to end (DELETES A REAL ACCOUNT — test accounts only). After
--    delete-account is redeployed: pair a throwaway Runner with a test Witness,
--    delete the Runner's account from the app, then as the editor:
--      select witness_id, runner_first_name, created_at, seen_at
--        from public.witness_notices order by created_at desc limit 5;
--    Expect one fresh row for the test Witness. Open the app as that Witness:
--    "<First> has left The Trellis" appears once; after OK, seen_at is set and
--    it never appears again. Edge Functions -> delete-account -> Logs shows no
--    "departure notice" error.
-- =============================================================================
