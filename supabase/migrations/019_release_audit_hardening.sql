-- =============================================================================
-- The Trellis — 019_release_audit_hardening.sql   (1.0 beta pre-flight audit)
-- =============================================================================
-- Result of auditing every function, grant, policy and view in init_schema +
-- 002..018. Idempotent — safe to run more than once. Run AFTER 011..018 (and
-- 015, the demo-code migration, which is not in this repository).
--
-- What the audit found, and what this file does about it:
--
--  A. [BLOCKER] New-Runner signup fails. 013 added the constraint "a weekly
--     rhythm must have days", but the app's starter baselines contain weekly
--     rhythms with no days — including one in "The Essential", which is
--     inserted for every new Runner at signup. The whole insert is rejected.
--     The app data is fixed in the same release; this adds the database-side
--     net so NO client (old build, future bug) can ever trip it: a weekly
--     rhythm saved without days is given the weekday it was created on.
--
--  B. [HIGH] A Witness could rewrite a Runner's shared prayer. The policy that
--     lets a Witness mark a shared prayer prayed/answered (002) granted UPDATE
--     on the whole row, so title, details, phone number and category were
--     editable by the Witness. Now only the three fields that policy was for.
--
--  C. [HIGH] profiles.email was client-writable, so anyone could put any
--     address on their profile (it is shown to their church's Cloud admin and
--     to their Witness as a contact address), and it drifted from the real
--     sign-in address. It is now maintained by the database from auth.users
--     and is read-only to clients.
--
--  D. [MEDIUM] Declining/rescheduling a meeting silently did nothing: the app
--     DELETEs the row, but meetings never had a DELETE policy, so RLS removed
--     zero rows without an error and the meeting reappeared on reload.
--
--  D2. [MEDIUM] The accountability lock was a one-way door: a Runner could ask
--     for it to be removed, but no Witness could ever approve, so it stayed on
--     (and "pending") forever. Adds the Witness's approve/decline.
--
--  E. [MEDIUM] Account deletion could be blocked by calendar cleanup: the
--     trigger that purges a connection's Vault secrets ran inside the delete;
--     if the Vault delete failed, the whole account deletion failed with it.
--     It now can't.
--
--  F. [MEDIUM] The service role (Edge Functions) had no explicit grants. On a
--     project without Supabase's default privileges that is a 42501 in every
--     function (this is the likely cause of "Could not record feedback").
--
--  G. [LOW] One function had no fixed search_path; every client-callable
--     function's EXECUTE grant is re-asserted from a single allowlist, and
--     every internal function's lock-out likewise, so a missed grant from any
--     earlier migration cannot survive this file.
--
--  The verification block at the bottom lists what `anon`, `authenticated` and
--  `service_role` can execute and read, so "airtight" is something you can
--  see rather than take on trust.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- A. A weekly rhythm always has days (safety net for 013's constraint)
-- -----------------------------------------------------------------------------
create or replace function public.normalize_rule_item()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.frequency = 'weekly'
     and (new.weekly_days is null or cardinality(new.weekly_days) = 0) then
    -- The closest thing to intent we have: the weekday it was created on.
    new.weekly_days := array[extract(isodow from coalesce(new.created_at, now()))::smallint];
  end if;
  return new;
end;
$$;

-- BEFORE triggers fire in name order: rule_items_guard_update (011) runs first,
-- then this one — so the guard still sees exactly what the client sent.
drop trigger if exists rule_items_normalize on public.rule_items;
create trigger rule_items_normalize
  before insert or update on public.rule_items
  for each row execute function public.normalize_rule_item();


-- -----------------------------------------------------------------------------
-- B. A Witness may only mark a shared prayer prayed / answered
-- -----------------------------------------------------------------------------
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
       and (   new.category             is distinct from old.category
            or new.title                is distinct from old.title
            or new.details              is distinct from old.details
            or new.phone_number         is distinct from old.phone_number
            or new.scripture            is distinct from old.scripture
            or new.share_with_witnesses is distinct from old.share_with_witnesses) then
      raise exception 'A Witness can only mark a shared prayer as prayed or answered.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists prayer_items_guard_update on public.prayer_items;
create trigger prayer_items_guard_update
  before update on public.prayer_items
  for each row execute function public.guard_prayer_item_update();


-- -----------------------------------------------------------------------------
-- C. profiles.email mirrors the real sign-in address; clients can't write it
-- -----------------------------------------------------------------------------
-- Changing an address goes through Supabase Auth (which confirms the new
-- address); when auth.users.email actually changes, this copies it across.
create or replace function public.handle_user_email_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.email is not null and new.email is distinct from old.email then
    update public.profiles set email = new.email where id = new.id;
  end if;
  return new;
exception when others then
  -- Never let a profile-sync problem block an auth change.
  raise warning 'handle_user_email_change failed for %: % (SQLSTATE %)', new.id, sqlerrm, sqlstate;
  return new;
end;
$$;

drop trigger if exists on_auth_user_email_changed on auth.users;
create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row execute function public.handle_user_email_change();

-- One-time repair of any address that has already drifted.
update public.profiles p
   set email = u.email
  from auth.users u
 where u.id = p.id
   and u.email is not null
   and p.email is distinct from u.email;

revoke update (email) on public.profiles from authenticated;

-- 011's guard, with `email` added to the protected list (everything else is
-- unchanged).
create or replace function public.guard_profile_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.id                           is distinct from old.id
       or new.email                     is distinct from old.email
       or new.role                      is distinct from old.role
       or new.membership_status         is distinct from old.membership_status
       or new.church_id                 is distinct from old.church_id
       or new.is_church_affiliation_locked is distinct from old.is_church_affiliation_locked
       or new.cloud_admin_church_id     is distinct from old.cloud_admin_church_id
       or new.pairing_code              is distinct from old.pairing_code
       or new.created_at                is distinct from old.created_at then
      raise exception 'That profile field can only be changed by The Trellis itself.'
        using errcode = '42501';
    end if;

    -- Turning the lock off needs a Witness's approval (D2 below) — unless the
    -- Runner has no active Witness at all, in which case nobody could ever
    -- approve and the lock would be permanent. (The pairing lookup runs as the
    -- caller; RLS lets a Runner see their own pairings.)
    if old.accountability_lock_enabled and not new.accountability_lock_enabled
       and exists (
         select 1 from public.witness_pairings wp
          where wp.runner_id = old.id and wp.status = 'active'
       ) then
      raise exception 'The accountability lock can only be removed with your Witness''s approval.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;


-- -----------------------------------------------------------------------------
-- D. Either party may withdraw a meeting (the app's "suggest another time")
-- -----------------------------------------------------------------------------
drop policy if exists "meetings_delete_either_side" on public.meetings;
create policy "meetings_delete_either_side"
  on public.meetings for delete
  to authenticated
  using (runner_id = auth.uid() or witness_id = auth.uid());

grant delete on public.meetings to authenticated;


-- -----------------------------------------------------------------------------
-- D2. The accountability lock can actually be released (by a Witness)
-- -----------------------------------------------------------------------------
-- 011 (rightly) stops a Runner turning their own lock off, and the app let
-- them "request removal" — but nothing could ever approve that request, so a
-- lock once enabled was permanent and the request sat pending forever. This is
-- the missing half: an active Witness of the Runner approves (lock off) or
-- declines (lock stays on); either way the request is cleared. Returns false
-- if there was no pending request.
create or replace function public.resolve_accountability_lock_removal(
  p_runner_id uuid,
  p_approve   boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;
  if not public.is_witness_of(p_runner_id) then
    raise exception 'Only an active Witness of this Runner can answer that request.'
      using errcode = '42501';
  end if;

  update public.profiles
     set accountability_lock_enabled =
           case when coalesce(p_approve, false) then false else accountability_lock_enabled end,
         accountability_lock_removal_pending = false
   where id = p_runner_id
     and accountability_lock_removal_pending;

  return found;
end;
$$;

revoke execute on function public.resolve_accountability_lock_removal(uuid, boolean) from public, anon;
grant  execute on function public.resolve_accountability_lock_removal(uuid, boolean) to authenticated;


-- -----------------------------------------------------------------------------
-- E. Calendar secret cleanup can never block deleting a connection or account
-- -----------------------------------------------------------------------------
create or replace function public.calendar_connections_purge_secrets()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    delete from vault.secrets
     where id in (old.access_token_secret_id, old.refresh_token_secret_id);
  exception when others then
    -- An orphaned (still-encrypted, unreadable-by-clients) secret is far
    -- better than a user who cannot delete their account.
    raise warning 'calendar secret purge failed for connection %: % (SQLSTATE %)',
      old.id, sqlerrm, sqlstate;
  end;
  return old;
end;
$$;

revoke execute on function public.calendar_connections_purge_secrets() from public, anon, authenticated;
-- (017 creates the trigger that calls this. To find orphans, if a warning is
--  ever logged:  select id, description from vault.secrets
--                 where description like 'calendar % token %'
--                   and id not in (select access_token_secret_id from calendar_connections
--                                  union select refresh_token_secret_id from calendar_connections);)


-- -----------------------------------------------------------------------------
-- F. The service role can do its job
-- -----------------------------------------------------------------------------
-- Edge Functions use the service role (which also bypasses RLS). These are the
-- privileges Supabase normally provides by default; stated explicitly so the
-- functions work whether or not this project has those defaults.
grant usage on schema public to service_role;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;

alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant all on sequences to service_role;
alter default privileges in schema public grant execute on functions to service_role;


-- -----------------------------------------------------------------------------
-- G. Function hygiene: fixed search_path + one allowlist of who may call what
-- -----------------------------------------------------------------------------
alter function public.enforce_unlock_request_update() set search_path = public;

do $$
declare
  v_sig  text;
  v_proc regprocedure;

  -- Callable by signed-in users (RPCs the app calls, plus helpers that RLS
  -- policies and the roster view evaluate AS the querying user).
  c_client constant text[] := array[
    'is_witness_of(uuid)',
    'is_cloud_admin_of_church(uuid)',
    'is_cloud_admin_of_runner(uuid)',
    'current_user_church_id()',
    '_runner_score(uuid)',                       -- used by the church_roster view (018)
    'get_my_private_profile()',
    'set_my_role(text)',
    'redeem_church_code(text)',
    'redeem_cloud_access_code(text)',
    'generate_cloud_access_code(uuid)',
    'generate_church_code(uuid)',
    'generate_pairing_code()',
    'check_pairing_code(text)',
    'redeem_pairing_code(text, boolean)',
    'generate_enterprise_church_code(uuid, integer, timestamptz)',
    'redeem_enterprise_church_code(text)',
    'get_congregational_health(uuid)',
    'get_runner_analytics(uuid)',
    'get_cloud_triage(uuid)',
    'create_support_request(text, uuid, text)',
    'resolve_accountability_lock_removal(uuid, boolean)',
    'get_my_calendar_connections()',
    'get_calendar_pair_status(uuid)'
  ];

  -- Internal: never callable by a client. (They run inside SECURITY DEFINER
  -- functions as the owner, or are called by Edge Functions as service_role.)
  c_internal constant text[] := array[
    '_runner_resolved_days(uuid, integer)',
    '_runner_analytics(uuid)',
    '_secure_code(integer)',
    'apply_dna_rhythm_to_members(uuid, text, public.rule_category, public.rule_frequency, smallint[])',
    'calendar_create_oauth_state(uuid, text)',
    'calendar_consume_oauth_state(text)',
    'calendar_save_connection(uuid, text, text, text, text, timestamptz)',
    'calendar_read_tokens(uuid, text)',
    'calendar_update_tokens(uuid, text, text, text, timestamptz)',
    'calendar_set_status(uuid, text, text)',
    'calendar_delete_connection(uuid, text)'
  ];
begin
  foreach v_sig in array c_client loop
    v_proc := to_regprocedure('public.' || v_sig);
    if v_proc is null then
      raise notice 'client function public.% is not present (migration not applied?)', v_sig;
    else
      execute format('revoke execute on function %s from public, anon', v_proc);
      execute format('grant execute on function %s to authenticated', v_proc);
    end if;
  end loop;

  foreach v_sig in array c_internal loop
    v_proc := to_regprocedure('public.' || v_sig);
    if v_proc is null then
      raise notice 'internal function public.% is not present (migration not applied?)', v_sig;
    else
      execute format('revoke execute on function %s from public, anon, authenticated', v_proc);
    end if;
  end loop;
end $$;

-- anon never touches application tables (every policy is `to authenticated`).
revoke all on all tables in schema public from anon;


-- =============================================================================
-- VERIFICATION — run each block in the SQL editor and compare with "expect"
-- =============================================================================
-- 1. Who can execute what. Expect: `anon` = false on EVERY row; `authenticated`
--    = true only for the client allowlist above (plus any RPC added by 015);
--    every `_…`, `calendar_…`(helpers) and `apply_…` row = false for authenticated.
--
--   select p.oid::regprocedure                                   as function,
--          p.prosecdef                                           as security_definer,
--          has_function_privilege('anon', p.oid, 'execute')          as anon,
--          has_function_privilege('authenticated', p.oid, 'execute') as authenticated,
--          has_function_privilege('service_role', p.oid, 'execute')  as service_role
--     from pg_proc p
--     join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and p.prorettype <> 'trigger'::regtype
--    order by 1;
--
-- 2. Every table has RLS on, and anon can read none. Expect rls = true and
--    anon_select = false on every row. Tables with 0 policies are the
--    service-only ones (codes, feedback, calendar_oauth_states).
--
--   select c.relname                                         as table_name,
--          c.relrowsecurity                                  as rls,
--          (select count(*) from pg_policies pol
--            where pol.schemaname = 'public' and pol.tablename = c.relname) as policies,
--          has_table_privilege('anon', c.oid, 'select')          as anon_select,
--          has_table_privilege('authenticated', c.oid, 'select') as authenticated_table_select,
--          has_table_privilege('service_role', c.oid, 'insert')  as service_insert
--     from pg_class c
--     join pg_namespace n on n.oid = c.relnamespace
--    where n.nspname = 'public' and c.relkind = 'r'
--    order by 1;
--
-- 3. Column-level protection. Expect NO row for profiles.fcm_token /
--    home_address / work_address / pairing_code under SELECT, none for
--    email / role / membership_status / church_id / cloud_admin_church_id /
--    is_church_affiliation_locked under UPDATE, and for calendar_connections
--    only id, user_id, provider, status, connected_at, last_checked_at.
--
--   select table_name, privilege_type, string_agg(column_name, ', ' order by column_name) as columns
--     from information_schema.column_privileges
--    where table_schema = 'public' and grantee = 'authenticated'
--      and table_name in ('profiles', 'calendar_connections', 'rule_items',
--                         'witness_pairings', 'meetings', 'pending_unlock_requests',
--                         'support_requests', 'churches')
--    group by 1, 2 order by 1, 2;
--
-- 4. Vault is out of reach of clients. Expect false, false, false.
--
--   select has_schema_privilege('authenticated', 'vault', 'usage')                    as auth_vault_usage,
--          has_table_privilege('authenticated', 'vault.decrypted_secrets', 'select') as auth_reads_secrets,
--          has_table_privilege('anon', 'vault.decrypted_secrets', 'select')          as anon_reads_secrets;
--
-- 5. Behaviour (as a signed-in user; replace the uuids):
--      begin;
--      set local role authenticated;
--      select set_config('request.jwt.claims', '{"sub":"<user-uuid>","role":"authenticated"}', true);
--      -- A: weekly without days is repaired, not rejected
--      insert into rule_items (runner_id, category, title, frequency)
--        values (auth.uid(), 'abiding_prayer', 'audit probe', 'weekly') returning weekly_days;   -- one day
--      -- C: email is read-only
--      update profiles set email = 'x@example.com' where id = auth.uid();                        -- permission denied
--      -- B: as a WITNESS of <runner>, editing a shared prayer's text is refused
--      update prayer_items set title = 'changed' where runner_id = '<runner-uuid>';               -- ERROR 42501
--      update prayer_items set last_prayed_date = current_date where runner_id = '<runner-uuid>'; -- ok
--      rollback;
-- =============================================================================
