-- =============================================================================
-- The Trellis — 025_device_calendars.sql   (on-device calendars replace Cronofy)
-- =============================================================================
-- Run AFTER 023 and 024. Idempotent — safe to run more than once.
--
-- What this file does, in plain English:
--
--   The app no longer connects to Google / Outlook / Apple through Cronofy.
--   Instead each phone reads its OWN calendars (EventKit on iOS, CalendarContract
--   on Android), reduces the next three weeks or so to BUSY BLOCKS — a start
--   and an end, never a title, never a location, never who else is invited —
--   and uploads those. Working out when two paired people are both free now
--   happens on the phone. The database's whole job is to hold each person's
--   busy blocks, let their paired partner read them, and say when they were
--   last refreshed.
--
--   A. Table calendar_busy_blocks: one row per busy block per person. Clients
--      have NO direct access to it at all; everything goes through the RPCs.
--
--   B. profiles.calendar_synced_at — when the phone last uploaded its blocks.
--      Clients can read it, never write it (only the RPCs below do).
--
--   C. replace_my_busy_blocks(blocks, window_start, window_end) — the phone
--      hands over its whole set of busy blocks for a window; the old set is
--      thrown away and the new one stored.
--
--   D. clear_my_busy_blocks() — "stop sharing my calendar".
--
--   E. get_pair_calendar(other, from, to) — both people's connected/synced
--      state plus the OTHER person's busy blocks in a window, for an active
--      Runner/Witness pairing only. Anyone else is told "no calendar", exactly
--      as a partner without a calendar would be, so it cannot probe strangers.
--
--   F. Removes the Cronofy integration from 017 and 022: both tables, all
--      eleven functions, every leftover OAuth token in Vault, and the
--      calendar-availability rate-limit rows from 020.
--
--   G. Grants restated for every new function.
--
--   H. Verification queries (bottom of the file).
--
-- ALSO REQUIRED ALONGSIDE THIS FILE (not SQL):
--   * The four Cronofy Edge Functions (calendar-connect-start,
--     calendar-oauth-callback, calendar-disconnect, calendar-availability) are
--     deleted from the project; nothing in the database serves them any more.
--   * delete-account still calls calendar_read_tokens() as a courtesy step. It
--     already treats "function does not exist" as "nothing to revoke" and
--     continues, so account deletion keeps working; it just logs one error per
--     deletion until that step is removed and the function redeployed.
--
-- RE-RUNNING OLDER FILES: 019's function allowlist names the nine 017 functions
-- this file drops (get_my_calendar_connections, get_calendar_pair_status and
-- the seven calendar_* helpers). 019 is NOT edited: on a re-run it prints one
-- "is not present (migration not applied?)" notice for each of them — expected.
-- If 017 or 022 is ever run again by mistake, run this file again afterwards.
--
-- Unchanged on purpose: profiles.calendar_connected keeps 011's SELECT and
-- UPDATE grants. The app still writes it from completeSchedulingSetup, and the
-- RPCs below set it as well. "Connected" in the sense that matters to the
-- partner view is calendar_connected AND calendar_synced_at is not null — a
-- flag alone, with no upload behind it, does not count.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- A. calendar_busy_blocks
-- -----------------------------------------------------------------------------
create table if not exists public.calendar_busy_blocks (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  starts_at  timestamptz not null,
  ends_at    timestamptz not null,
  constraint calendar_busy_blocks_ends_after_start check (ends_at > starts_at)
);

comment on table public.calendar_busy_blocks is
  'A person''s busy blocks as uploaded by their own phone: a start and an end '
  'and nothing else — never an event title, location or attendee. Replaced '
  'wholesale on every upload (replace_my_busy_blocks); read by a paired partner '
  'through get_pair_calendar. Clients have no direct access to this table.';

create index if not exists calendar_busy_blocks_user_start_idx
  on public.calendar_busy_blocks (user_id, starts_at);

-- RLS on with no policies: even if a blanket grant is ever re-run, a client
-- sees nothing. All reads and writes go through the SECURITY DEFINER RPCs
-- below, which run as the table's owner — the same arrangement 017 used.
alter table public.calendar_busy_blocks enable row level security;

revoke all on public.calendar_busy_blocks from public, anon, authenticated;
grant  all on public.calendar_busy_blocks to service_role;


-- -----------------------------------------------------------------------------
-- B. profiles.calendar_synced_at
-- -----------------------------------------------------------------------------
alter table public.profiles
  add column if not exists calendar_synced_at timestamptz;

comment on column public.profiles.calendar_synced_at is
  'When this person''s phone last uploaded its busy blocks '
  '(replace_my_busy_blocks). Null = never, or sharing was turned off '
  '(clear_my_busy_blocks). Written only by those two RPCs, never by a client. '
  'A calendar counts as connected only when calendar_connected is true AND this '
  'is not null.';

-- 011 gives clients column-by-column SELECT and UPDATE on profiles, so the new
-- column is invisible until granted. Read yes, write no — the same shape as
-- rule_committed_at (021 B). Who can see WHICH rows is unchanged.
grant select (calendar_synced_at) on public.profiles to authenticated;

-- Layer 2 for the missing UPDATE grant (the two-layer rule from 011). Its own
-- small trigger rather than a line in guard_profile_update, for the reason 021 B
-- gives: a re-run of 019 re-creates that guard and would silently drop the line.
-- Not SECURITY DEFINER: like the other guards it tells a client from the server
-- by looking at current_user. The RPCs below run as the function owner, so this
-- never gets in their way.
create or replace function public.guard_calendar_sync_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.calendar_synced_at is distinct from old.calendar_synced_at then
      raise exception 'That profile field can only be changed by The Trellis itself.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

-- (Grants: same reasoning as guard_rule_commit in 021 B — a trigger function
--  cannot be called directly, and it fires inside the client's own UPDATE.)
revoke execute on function public.guard_calendar_sync_update() from public, anon;
grant  execute on function public.guard_calendar_sync_update() to authenticated, service_role;

drop trigger if exists profiles_guard_calendar_sync on public.profiles;
create trigger profiles_guard_calendar_sync
  before update on public.profiles
  for each row execute function public.guard_calendar_sync_update();


-- -----------------------------------------------------------------------------
-- C. replace_my_busy_blocks — the phone uploads its busy blocks
-- -----------------------------------------------------------------------------
-- p_blocks is a JSON array of objects {"start": "<ISO-8601>", "end": "<ISO-8601>"}.
-- Timestamps should carry an offset or a trailing Z; one without is read in the
-- database's time zone (UTC on Supabase). p_window_start / p_window_end is the
-- range the phone looked at.
--
-- Why the WHOLE set is replaced every time, rather than edited in place: the
-- phone is the only source of truth. It cannot know which blocks the database
-- holds from last time (events get moved, shortened and deleted on the device),
-- and the rows carry no identity worth preserving — a busy block is just two
-- timestamps. Delete-then-insert inside one transaction is therefore both the
-- simplest and the only correct thing to do. Nothing is ever edited in place.
--
-- Element by element:
--   * a block whose start or end is missing, or whose element is not an object,
--     is skipped;
--   * a block that is not a positive span (end <= start) is skipped;
--   * a block entirely outside the window is skipped;
--   * a block that overlaps the edge of the window is clipped to the window;
--   * a start or end that is present but is not a readable timestamp fails the
--     whole call with 22023 "A busy block has a time that could not be read."
--     (the transaction rolls back, so the previous blocks are kept).
--
-- Errors: 28000 not signed in; 22023 p_blocks is not an array, the window is
-- not a positive span of at most 60 days, or there are more than 1000 blocks.
-- Returns the number of blocks stored.
create or replace function public.replace_my_busy_blocks(
  p_blocks       jsonb,
  p_window_start timestamptz,
  p_window_end   timestamptz
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me    uuid := auth.uid();
  v_count integer := 0;
begin
  if v_me is null then
    raise exception 'You must be signed in to share your calendar.'
      using errcode = '28000';
  end if;

  if p_blocks is null or jsonb_typeof(p_blocks) <> 'array' then
    raise exception 'Busy blocks must be sent as a list.'
      using errcode = '22023';
  end if;

  if p_window_start is null or p_window_end is null
     or p_window_end <= p_window_start
     or p_window_end - p_window_start > interval '60 days' then
    raise exception 'The calendar window must be a positive span of at most 60 days.'
      using errcode = '22023';
  end if;

  if jsonb_array_length(p_blocks) > 1000 then
    raise exception 'Too many busy blocks in one upload (the limit is 1000).'
      using errcode = '22023';
  end if;

  -- Out with the old set — all of it (see the note above).
  delete from public.calendar_busy_blocks where user_id = v_me;

  -- In with the new. The casts happen inside this block so that an unreadable
  -- timestamp becomes one plain-English error rather than a raw Postgres one.
  -- Only the cast can fail here: the WHERE clause guarantees end > start and
  -- overlap with the window, and clipping two overlapping spans to each other
  -- always leaves a positive span, so the check constraint never trips.
  begin
    insert into public.calendar_busy_blocks (user_id, starts_at, ends_at)
    select v_me,
           greatest(b.starts_at, p_window_start),
           least(b.ends_at, p_window_end)
      from (
        select (elem ->> 'start')::timestamptz as starts_at,
               (elem ->> 'end')::timestamptz   as ends_at
          from jsonb_array_elements(p_blocks) as elem
      ) b
     where b.starts_at is not null
       and b.ends_at   is not null
       and b.ends_at   >  b.starts_at
       and b.starts_at <  p_window_end
       and b.ends_at   >  p_window_start;

    get diagnostics v_count = row_count;
  exception
    when invalid_datetime_format or datetime_field_overflow or invalid_text_representation then
      raise exception 'A busy block has a time that could not be read.'
        using errcode = '22023';
  end;

  -- Runs as the function owner, so the client-only guards on profiles
  -- (guard_profile_update, guard_rule_commit, guard_calendar_sync_update) do
  -- not apply here.
  update public.profiles
     set calendar_connected = true,
         calendar_synced_at = now()
   where id = v_me;

  return v_count;
end;
$$;

comment on function public.replace_my_busy_blocks(jsonb, timestamptz, timestamptz) is
  'The caller''s phone uploads its busy blocks (start/end only) for a window of '
  'at most 60 days. The caller''s previous blocks are all deleted and the new set '
  'stored; profiles.calendar_connected becomes true and calendar_synced_at now(). '
  'Returns the number of blocks stored.';

revoke execute on function public.replace_my_busy_blocks(jsonb, timestamptz, timestamptz) from public, anon;
grant  execute on function public.replace_my_busy_blocks(jsonb, timestamptz, timestamptz) to authenticated;


-- -----------------------------------------------------------------------------
-- D. clear_my_busy_blocks — "stop sharing my calendar"
-- -----------------------------------------------------------------------------
-- Removes every busy block of the caller and marks the calendar disconnected.
-- Errors: 28000 not signed in.
create or replace function public.clear_my_busy_blocks()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'You must be signed in to stop sharing your calendar.'
      using errcode = '28000';
  end if;

  delete from public.calendar_busy_blocks where user_id = v_me;

  update public.profiles
     set calendar_connected = false,
         calendar_synced_at = null
   where id = v_me;
end;
$$;

comment on function public.clear_my_busy_blocks() is
  'Deletes all of the caller''s busy blocks and sets profiles.calendar_connected '
  'false and calendar_synced_at null.';

revoke execute on function public.clear_my_busy_blocks() from public, anon;
grant  execute on function public.clear_my_busy_blocks() to authenticated;


-- -----------------------------------------------------------------------------
-- E. get_pair_calendar — what the phone needs to find a time for two people
-- -----------------------------------------------------------------------------
-- Returns one JSON object:
--
--   { "me_connected":    bool,                 -- calendar_connected and synced
--     "me_synced_at":    "<ISO-8601>" | null,
--     "other_connected": bool,
--     "other_synced_at": "<ISO-8601>" | null,
--     "other_busy":      [ {"start": "<ISO-8601>", "end": "<ISO-8601>"}, ... ] }
--
-- "other_busy" holds the OTHER person's blocks that overlap [p_from, p_to) —
-- overlap test starts_at < p_to and ends_at > p_from; blocks are returned as
-- stored, not clipped — ordered by start, at most 2000. The phone intersects
-- them with its own calendar; this person's own blocks are not returned because
-- the phone already has them.
--
-- Who may ask about whom: only the two sides of an ACTIVE witness_pairing
-- (either direction — 017's get_calendar_pair_status check). For anyone else,
-- including a stranger's id, your own id, or an ended pairing, the "other_*"
-- half of the answer is exactly what a partner with no calendar would get:
-- other_connected false, other_synced_at null, other_busy [] — so the call
-- cannot be used to find out whether a stranger uses a calendar, let alone
-- when they are busy. The "me_*" half is always the caller's real state.
--
-- Errors: 28000 not signed in; 22023 the window is not a positive span of at
-- most 60 days.
create or replace function public.get_pair_calendar(
  p_other_user_id uuid,
  p_from          timestamptz,
  p_to            timestamptz
)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_me              uuid := auth.uid();
  v_paired          boolean := false;
  v_me_connected    boolean;
  v_me_synced_at    timestamptz;
  v_other_connected boolean := false;
  v_other_synced_at timestamptz := null;
  v_other_busy      jsonb := '[]'::jsonb;
begin
  if v_me is null then
    raise exception 'You must be signed in to see a shared calendar.'
      using errcode = '28000';
  end if;

  if p_from is null or p_to is null
     or p_to <= p_from
     or p_to - p_from > interval '60 days' then
    raise exception 'The calendar window must be a positive span of at most 60 days.'
      using errcode = '22023';
  end if;

  select p.calendar_connected and p.calendar_synced_at is not null,
         p.calendar_synced_at
    into v_me_connected, v_me_synced_at
    from public.profiles p
   where p.id = v_me;

  if p_other_user_id is not null and p_other_user_id <> v_me then
    select exists (
      select 1
        from public.witness_pairings wp
       where wp.status = 'active'
         and ((wp.runner_id = v_me and wp.witness_id = p_other_user_id)
           or (wp.runner_id = p_other_user_id and wp.witness_id = v_me))
    ) into v_paired;
  end if;

  if v_paired then
    select p.calendar_connected and p.calendar_synced_at is not null,
           p.calendar_synced_at
      into v_other_connected, v_other_synced_at
      from public.profiles p
     where p.id = p_other_user_id;

    select coalesce(
             jsonb_agg(
               jsonb_build_object('start', b.starts_at, 'end', b.ends_at)
               order by b.starts_at
             ),
             '[]'::jsonb
           )
      into v_other_busy
      from (
        select cb.starts_at, cb.ends_at
          from public.calendar_busy_blocks cb
         where cb.user_id = p_other_user_id
           and cb.starts_at < p_to
           and cb.ends_at   > p_from
         order by cb.starts_at
         limit 2000
      ) b;
  end if;

  return jsonb_build_object(
    'me_connected',    coalesce(v_me_connected, false),
    'me_synced_at',    v_me_synced_at,
    'other_connected', coalesce(v_other_connected, false),
    'other_synced_at', v_other_synced_at,
    'other_busy',      v_other_busy
  );
end;
$$;

comment on function public.get_pair_calendar(uuid, timestamptz, timestamptz) is
  'Both people''s calendar state and the OTHER person''s busy blocks (start/end '
  'only) overlapping [p_from, p_to), for an active Runner/Witness pairing. For '
  'anyone not actively paired with the caller the other_* fields read as "no '
  'calendar", so strangers cannot be probed.';

revoke execute on function public.get_pair_calendar(uuid, timestamptz, timestamptz) from public, anon;
grant  execute on function public.get_pair_calendar(uuid, timestamptz, timestamptz) to authenticated;


-- -----------------------------------------------------------------------------
-- F. Remove the Cronofy integration (017, 022, and 020's rate-limit rows)
-- -----------------------------------------------------------------------------
-- F.1  Delete the connection ROWS before dropping the table. 017's AFTER DELETE
--      trigger (calendar_connections_purge_secrets, hardened in 019) removes
--      each row's two Vault secrets as the row goes; DROP TABLE would not fire
--      it and would leave every OAuth token sitting in Vault. The guard trigger
--      only refuses client roles, so this runs through as the SQL editor's own
--      role. Inside a DO block so that the DELETE is never even prepared on a
--      project where the table is already gone (a re-run).
do $$
declare
  v_n integer;
begin
  if to_regclass('public.calendar_connections') is not null then
    delete from public.calendar_connections;
    get diagnostics v_n = row_count;
    raise notice '025: removed % calendar connection row(s); their Vault secrets went with them.', v_n;
  else
    raise notice '025: calendar_connections is already gone; nothing to delete.';
  end if;
end $$;

-- F.2  The two 017 tables. CASCADE takes the triggers, policies, indexes and
--      022's re-created check constraints with them.
drop table if exists public.calendar_oauth_states cascade;
drop table if exists public.calendar_connections cascade;

-- F.3  Every 017 function, including the two 022 re-created (same signatures),
--      the two client RPCs and the two trigger functions (their triggers were
--      dropped with the table in F.2, so no CASCADE is needed).
drop function if exists public.calendar_create_oauth_state(uuid, text);
drop function if exists public.calendar_consume_oauth_state(text);
drop function if exists public.calendar_save_connection(uuid, text, text, text, text, timestamptz);
drop function if exists public.calendar_read_tokens(uuid, text);
drop function if exists public.calendar_update_tokens(uuid, text, text, text, timestamptz);
drop function if exists public.calendar_set_status(uuid, text, text);
drop function if exists public.calendar_delete_connection(uuid, text);
drop function if exists public.get_my_calendar_connections();
drop function if exists public.get_calendar_pair_status(uuid);
drop function if exists public.guard_calendar_connections_write();
drop function if exists public.calendar_connections_purge_secrets();

-- F.4  Belt and braces for Vault: 017 described every token secret as
--      'calendar access token <user> <provider>' or 'calendar refresh token
--      <user> <provider>'. F.1 should have purged them all, but a purge that
--      failed in the past (019 E turned that into a warning rather than an
--      error) would have left orphans. If Vault is not reachable from here, say
--      so and carry on — nothing else in this file depends on it.
do $$
declare
  v_n integer;
begin
  delete from vault.secrets where description like 'calendar % token %';
  get diagnostics v_n = row_count;
  raise notice '025: swept % leftover calendar token secret(s) from Vault.', v_n;
exception when others then
  raise notice '025: could not sweep Vault for leftover calendar token secrets: % (SQLSTATE %). Check by hand: select count(*) from vault.secrets where description like ''calendar %% token %%'';',
    sqlerrm, sqlstate;
end $$;

-- F.5  020's limiter keys rows by bucket_key, which calendar-availability set
--      to 'calendar-availability:<user-uuid>:minute' / ':hour'. Those windows
--      expire on their own within two days, but there is no reason to keep
--      them. Guarded the same way as F.1 in case 020 was never applied.
do $$
declare
  v_n integer;
begin
  if to_regclass('public.edge_rate_limits') is not null then
    delete from public.edge_rate_limits where bucket_key like 'calendar-%';
    get diagnostics v_n = row_count;
    raise notice '025: removed % calendar rate-limit row(s).', v_n;
  else
    raise notice '025: edge_rate_limits is not present; no rate-limit rows to remove.';
  end if;
end $$;


-- -----------------------------------------------------------------------------
-- G. Grants, all in one place
-- -----------------------------------------------------------------------------
-- Every function this file creates, and who may call it. (Each is also stated
-- next to its definition above; repeated here so the whole picture is one
-- screen. 019's allowlist is not edited: it only ever narrows what it names,
-- and names none of these.)
--
--   client (authenticated)        replace_my_busy_blocks(jsonb, timestamptz, timestamptz)
--                                 clear_my_busy_blocks()
--                                 get_pair_calendar(uuid, timestamptz, timestamptz)
--   trigger function              guard_calendar_sync_update()
--   (not directly callable)
--   table                         calendar_busy_blocks: nobody but service_role,
--                                 and the RPCs as owner
revoke execute on function public.replace_my_busy_blocks(jsonb, timestamptz, timestamptz) from public, anon;
grant  execute on function public.replace_my_busy_blocks(jsonb, timestamptz, timestamptz) to authenticated;
revoke execute on function public.clear_my_busy_blocks()                                 from public, anon;
grant  execute on function public.clear_my_busy_blocks()                                 to authenticated;
revoke execute on function public.get_pair_calendar(uuid, timestamptz, timestamptz)      from public, anon;
grant  execute on function public.get_pair_calendar(uuid, timestamptz, timestamptz)      to authenticated;
revoke execute on function public.guard_calendar_sync_update()                           from public, anon;
grant  execute on function public.guard_calendar_sync_update()                           to authenticated, service_role;
revoke all on public.calendar_busy_blocks from public, anon, authenticated;
grant  all on public.calendar_busy_blocks to service_role;


-- =============================================================================
-- H. VERIFICATION — run in the SQL editor and compare with "expect"
-- =============================================================================
-- Blocks that act as a signed-in user use `set local role` (as 018–023 do).
-- Replace the <...> placeholders with real test ids. A block that ends in an
-- expected ERROR must be run on its own: the error aborts that transaction, and
-- the `rollback;` on its last line cleans up. Every dry run here rolls back.
--
-- 0. Privileges at a glance. Expect, in order:
--    false, true, true     replace_my_busy_blocks: not anon; signed-in users; service role
--    false, true, true     clear_my_busy_blocks
--    false, true, true     get_pair_calendar
--    false, false, true    calendar_busy_blocks SELECT: no client may read it directly
--    false, false          calendar_busy_blocks INSERT / DELETE for authenticated
--    true,  false          calendar_synced_at: clients can read it, cannot write it
--    true,  true           calendar_connected: unchanged from 011 (read and write)
--
--   select has_function_privilege('anon',          'public.replace_my_busy_blocks(jsonb,timestamptz,timestamptz)', 'execute'),
--          has_function_privilege('authenticated', 'public.replace_my_busy_blocks(jsonb,timestamptz,timestamptz)', 'execute'),
--          has_function_privilege('service_role',  'public.replace_my_busy_blocks(jsonb,timestamptz,timestamptz)', 'execute');
--   select has_function_privilege('anon',          'public.clear_my_busy_blocks()', 'execute'),
--          has_function_privilege('authenticated', 'public.clear_my_busy_blocks()', 'execute'),
--          has_function_privilege('service_role',  'public.clear_my_busy_blocks()', 'execute');
--   select has_function_privilege('anon',          'public.get_pair_calendar(uuid,timestamptz,timestamptz)', 'execute'),
--          has_function_privilege('authenticated', 'public.get_pair_calendar(uuid,timestamptz,timestamptz)', 'execute'),
--          has_function_privilege('service_role',  'public.get_pair_calendar(uuid,timestamptz,timestamptz)', 'execute');
--   select has_table_privilege('anon',          'public.calendar_busy_blocks', 'select'),
--          has_table_privilege('authenticated', 'public.calendar_busy_blocks', 'select'),
--          has_table_privilege('service_role',  'public.calendar_busy_blocks', 'select');
--   select has_table_privilege('authenticated', 'public.calendar_busy_blocks', 'insert'),
--          has_table_privilege('authenticated', 'public.calendar_busy_blocks', 'delete');
--   select has_column_privilege('authenticated', 'public.profiles', 'calendar_synced_at', 'select'),
--          has_column_privilege('authenticated', 'public.profiles', 'calendar_synced_at', 'update');
--   select has_column_privilege('authenticated', 'public.profiles', 'calendar_connected', 'select'),
--          has_column_privilege('authenticated', 'public.profiles', 'calendar_connected', 'update');
--
-- 1. Structure. Expect: rls = true, 0 policies; one index named
--    calendar_busy_blocks_user_start_idx; the check constraint present; the
--    trigger profiles_guard_calendar_sync on profiles.
--   select c.relrowsecurity as rls,
--          (select count(*) from pg_policies where schemaname = 'public' and tablename = 'calendar_busy_blocks') as policies
--     from pg_class c where c.oid = 'public.calendar_busy_blocks'::regclass;
--   select indexname from pg_indexes where schemaname = 'public' and tablename = 'calendar_busy_blocks';
--   select conname, pg_get_constraintdef(oid) from pg_constraint
--    where conrelid = 'public.calendar_busy_blocks'::regclass and contype = 'c';
--   select tgname from pg_trigger where tgrelid = 'public.profiles'::regclass and not tgisinternal order by 1;
--
-- 2. Round trip as a signed-in user WITH an active partner (a Runner and their
--    Witness). Everything rolls back. Expect, in order:
--      2            -- two blocks stored: the one outside the window is skipped
--                      and the one straddling the window's end is clipped
--      me_connected true, me_synced_at = now, 2 rows whose second ends exactly at the window's end
--      (as the partner) other_connected true, other_synced_at = now, other_busy with 2 entries,
--        start/end as ISO-8601 strings, in start order
--      (as the partner, narrower window) other_busy with 1 entry
--      (back as the first user) clear: me_connected false, me_synced_at null, 0 rows
--   begin;
--   set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   select public.replace_my_busy_blocks(
--     '[{"start":"2026-10-07T09:00:00Z","end":"2026-10-07T10:00:00Z"},
--       {"start":"2026-10-20T23:00:00Z","end":"2026-10-21T02:00:00Z"},
--       {"start":"2026-12-01T09:00:00Z","end":"2026-12-01T10:00:00Z"},
--       {"start":"2026-10-08T10:00:00Z","end":"2026-10-08T10:00:00Z"},
--       {"nonsense": true}]'::jsonb,
--     '2026-10-06T00:00:00Z', '2026-10-21T00:00:00Z');
--   select public.get_pair_calendar('<witness-uuid>', '2026-10-06T00:00:00Z', '2026-10-27T00:00:00Z') -> 'me_connected',
--          public.get_pair_calendar('<witness-uuid>', '2026-10-06T00:00:00Z', '2026-10-27T00:00:00Z') -> 'me_synced_at';
--   reset role;   -- look at the rows as the editor's own role (clients cannot)
--   select starts_at, ends_at from public.calendar_busy_blocks where user_id = '<runner-uuid>' order by starts_at;
--   set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<witness-uuid>","role":"authenticated"}', true);
--   select jsonb_pretty(public.get_pair_calendar('<runner-uuid>', '2026-10-06T00:00:00Z', '2026-10-27T00:00:00Z'));
--   select jsonb_array_length(public.get_pair_calendar('<runner-uuid>', '2026-10-07T00:00:00Z', '2026-10-08T00:00:00Z') -> 'other_busy');
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   select public.clear_my_busy_blocks();
--   select public.get_pair_calendar('<witness-uuid>', '2026-10-06T00:00:00Z', '2026-10-27T00:00:00Z') -> 'me_connected',
--          public.get_pair_calendar('<witness-uuid>', '2026-10-06T00:00:00Z', '2026-10-27T00:00:00Z') -> 'me_synced_at';
--   reset role;
--   select count(*) from public.calendar_busy_blocks where user_id = '<runner-uuid>';
--   rollback;
--
-- 3. The stranger case. As any signed-in user who is NOT actively paired with
--    <runner-uuid> (use someone with blocks stored, or run this inside a block
--    like 2 before the rollback). Expect other_connected false, other_synced_at
--    null, other_busy [] — and the same answer for your own id and for a
--    made-up id:
--   begin;
--   set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<unrelated-user-uuid>","role":"authenticated"}', true);
--   select public.get_pair_calendar('<runner-uuid>',          '2026-10-06T00:00:00Z', '2026-10-27T00:00:00Z') - 'me_connected' - 'me_synced_at';
--   select public.get_pair_calendar(auth.uid(),               '2026-10-06T00:00:00Z', '2026-10-27T00:00:00Z') - 'me_connected' - 'me_synced_at';
--   select public.get_pair_calendar(gen_random_uuid(),        '2026-10-06T00:00:00Z', '2026-10-27T00:00:00Z') - 'me_connected' - 'me_synced_at';
--   rollback;
--
-- 4. Refusals (each on its own; each rolls back):
--    a. Not an array (expect ERROR 22023 "Busy blocks must be sent as a list."):
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   select public.replace_my_busy_blocks('{"start":"x"}'::jsonb, now(), now() + interval '21 days');
--   rollback;
--    b. Window too long (expect ERROR 22023 "...at most 60 days."):
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   select public.replace_my_busy_blocks('[]'::jsonb, now(), now() + interval '61 days');
--   rollback;
--    c. Unreadable time (expect ERROR 22023 "A busy block has a time that could not be read."):
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   select public.replace_my_busy_blocks('[{"start":"tomorrow-ish","end":"2026-10-07T10:00:00Z"}]'::jsonb,
--                                        '2026-10-06T00:00:00Z', '2026-10-21T00:00:00Z');
--   rollback;
--    d. A client cannot write calendar_synced_at (expect ERROR 42501 permission denied —
--       the column grant; the trigger behind it answers the same way if the grant
--       is ever widened):
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   update public.profiles set calendar_synced_at = now() where id = auth.uid();
--   rollback;
--    e. A client cannot read the table (expect ERROR 42501 permission denied):
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   select * from public.calendar_busy_blocks;
--   rollback;
--    f. Not signed in (expect ERROR 28000):
--   begin; set local role authenticated;
--   select public.clear_my_busy_blocks();
--   rollback;
--
-- 5. The Cronofy objects are gone. Expect: two nulls, then 0 rows, then 0:
--   select to_regclass('public.calendar_connections'), to_regclass('public.calendar_oauth_states');
--   select p.oid::regprocedure
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and (p.proname like 'calendar\_%' or p.proname in ('get_my_calendar_connections', 'get_calendar_pair_status'));
--   select count(*) from vault.secrets where description like 'calendar % token %';
--   And no calendar rows remain in the limiter (expect 0):
--   select count(*) from public.edge_rate_limits where bucket_key like 'calendar-%';
--
-- 6. Nothing else lost its way. 019's allowlist query (its verification 1)
--    still shows anon = false on every row and authenticated = true for the
--    three new RPCs.
-- =============================================================================
