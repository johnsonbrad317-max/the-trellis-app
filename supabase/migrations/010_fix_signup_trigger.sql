-- =============================================================================
-- 010 — Fix "Database error saving new user" (unexpected_failure) on signup.
-- =============================================================================
-- Confirmed live via a direct POST to /auth/v1/signup with a brand-new email:
-- GoTrue returns a 500 unexpected_failure, which means the on_auth_user_created
-- trigger on auth.users is raising inside the transaction that creates the
-- auth.users row itself (GoTrue rolls back and returns this generic message
-- for any such failure, masking the real Postgres error).
--
-- Nothing in this schema's own history explains it: handle_new_user() only
-- ever has the one definition (init_schema.sql), every column it doesn't
-- mention has a DEFAULT, no other trigger touches profiles, and no migration
-- here enables FORCE ROW LEVEL SECURITY. That means the live database has
-- most likely drifted from this migration history — e.g. a one-off edit made
-- directly in the SQL Editor, or a Dashboard Auth Hook (Authentication ->
-- Hooks) pointed at something broken. Run the two diagnostic queries at the
-- bottom of this file in the SQL Editor to see what's actually deployed.
--
-- This migration is a defensive fix either way:
--   1. Re-asserts every grant the trigger's insert could plausibly need.
--   2. Rewrites handle_new_user() to catch its own failure and re-raise with
--      a specific, loggable message — so if it ever fails again, Postgres's
--      logs (Dashboard -> Logs -> Postgres Logs) show exactly why instead of
--      GoTrue's generic "Database error saving new user".
--   3. Adds a direct, narrowly-scoped INSERT policy on profiles (and
--      confirms the existing UPDATE policy) as a fallback — belt-and-
--      suspenders in case the SECURITY DEFINER trigger path is ever bypassed
--      or blocked on this project for a reason the above doesn't surface.
-- =============================================================================

-- 1. Re-assert grants. Harmless to repeat if already correct.
grant usage on schema public to anon, authenticated;
grant usage on type public.user_role to anon, authenticated;
grant select, insert, update, delete on public.profiles to authenticated;

-- 2. Rewrite the trigger function defensively.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.user_role;
begin
  -- Cast defensively: an unrecognized role string must fall back to
  -- 'runner' rather than raising and blocking account creation entirely.
  begin
    v_role := coalesce((new.raw_user_meta_data ->> 'role')::public.user_role, 'runner');
  exception when invalid_text_representation then
    v_role := 'runner';
  end;

  insert into public.profiles (id, name, email, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'name', ''),
    new.email,
    v_role
  );

  return new;
exception when others then
  -- Re-raise with the original SQLSTATE/message intact, but prefixed so
  -- it's unmistakable in Postgres Logs which trigger produced it — GoTrue
  -- itself will still only show the caller a generic 500.
  raise exception 'handle_new_user failed for auth.users.id=%: % (SQLSTATE %)',
    new.id, sqlerrm, sqlstate;
end;
$$;

-- Trigger definition is unchanged, but re-created to guarantee it points at
-- the function above (in case the live one had been redefined to call
-- something else).
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- 3. Fallback direct-write policies for profiles. The trigger above should
-- make this insert policy unreachable in normal operation (SECURITY DEFINER
-- bypasses RLS), but having it costs nothing and protects against a client
-- ever needing to insert its own row directly.
drop policy if exists "profiles_insert_self" on public.profiles;
create policy "profiles_insert_self"
  on public.profiles for insert
  to authenticated
  with check (id = auth.uid());

-- profiles_update_self already exists from init_schema.sql — re-created here
-- only to guarantee it matches this exact shape on the live database.
drop policy if exists "profiles_update_self" on public.profiles;
create policy "profiles_update_self"
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- =============================================================================
-- Diagnostics — run these in the Supabase SQL Editor if signup still fails
-- after this migration. Both are read-only.
-- =============================================================================
-- A) Every trigger currently on auth.users (should show exactly one row:
--    on_auth_user_created / handle_new_user). More than one, or a
--    tgenabled value other than 'O', points at something outside this
--    migration history.
--
--   select tgname, tgenabled, pg_get_triggerdef(oid)
--     from pg_trigger
--    where tgrelid = 'auth.users'::regclass and not tgisinternal;
--
-- B) The function body actually deployed right now, to compare against
--    this file:
--
--   select pg_get_functiondef('public.handle_new_user()'::regprocedure);
--
-- If both match this file and signup still fails, the cause is outside the
-- database entirely — check Authentication -> Hooks in the Supabase
-- Dashboard for a configured hook (e.g. a "Before User Created" hook)
-- pointed at a failing Edge Function.
