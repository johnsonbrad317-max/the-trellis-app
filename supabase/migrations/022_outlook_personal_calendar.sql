-- =============================================================================
-- 022 — A separate calendar choice for personal Outlook accounts
-- =============================================================================
-- Run after 021 (independent of it; 017 is what it extends). Safe to re-run.
--
-- Why: "Outlook Calendar" sends people to the Microsoft 365 (work or school)
-- sign-in. A personal outlook.com / hotmail.com / live.com account signs in
-- somewhere else, so those people could not connect. The app now offers two
-- choices — "Outlook Calendar (work or school)" and "Outlook.com or Hotmail" —
-- and the second is stored as its own provider, `outlook_personal`, so each
-- card shows its own connection and either can be disconnected on its own.
--
-- What changes: the two provider check constraints from 017, and the two
-- 017 helpers that validate the provider (re-created from 017 unchanged
-- except for the added value). The Edge Functions map `outlook_personal` to
-- Cronofy's `live_connect` provider; nothing else about the flow differs.
-- =============================================================================

alter table public.calendar_connections
  drop constraint if exists calendar_connections_provider_check;
alter table public.calendar_connections
  add constraint calendar_connections_provider_check
  check (provider in ('google', 'outlook', 'outlook_personal', 'apple'));

alter table public.calendar_oauth_states
  drop constraint if exists calendar_oauth_states_provider_check;
alter table public.calendar_oauth_states
  add constraint calendar_oauth_states_provider_check
  check (provider in ('google', 'outlook', 'outlook_personal', 'apple'));

-- 3a from 017, with the new value accepted.
create or replace function public.calendar_create_oauth_state(
  p_user_id  uuid,
  p_provider text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nonce text;
begin
  if p_provider not in ('google', 'outlook', 'outlook_personal', 'apple') then
    raise exception 'Unknown calendar provider.' using errcode = '22023';
  end if;

  -- Housekeeping: drop states that are long expired or used.
  delete from public.calendar_oauth_states
   where expires_at < now() - interval '1 day';

  -- Two v4 UUIDs, hyphens stripped: 244 random bits.
  v_nonce := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');

  insert into public.calendar_oauth_states (nonce, user_id, provider)
  values (v_nonce, p_user_id, p_provider);

  return v_nonce;
end;
$$;

-- 3c from 017, with the new value accepted.
create or replace function public.calendar_save_connection(
  p_user_id       uuid,
  p_provider      text,
  p_cronofy_sub   text,
  p_access_token  text,
  p_refresh_token text,
  p_expires_at    timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row        public.calendar_connections%rowtype;
  v_access_id  uuid;
  v_refresh_id uuid;
  v_id         uuid;
begin
  if p_provider not in ('google', 'outlook', 'outlook_personal', 'apple') then
    raise exception 'Unknown calendar provider.' using errcode = '22023';
  end if;
  if coalesce(p_access_token, '') = '' or coalesce(p_refresh_token, '') = '' then
    raise exception 'Both tokens are required.' using errcode = '22023';
  end if;

  select * into v_row
    from public.calendar_connections
   where user_id = p_user_id and provider = p_provider
   for update;

  if found then
    v_access_id  := v_row.access_token_secret_id;
    v_refresh_id := v_row.refresh_token_secret_id;

    if v_access_id is null then
      v_access_id := vault.create_secret(
        p_access_token, null, 'calendar access token ' || p_user_id || ' ' || p_provider);
    else
      perform vault.update_secret(v_access_id, p_access_token);
    end if;

    if v_refresh_id is null then
      v_refresh_id := vault.create_secret(
        p_refresh_token, null, 'calendar refresh token ' || p_user_id || ' ' || p_provider);
    else
      perform vault.update_secret(v_refresh_id, p_refresh_token);
    end if;

    update public.calendar_connections
       set cronofy_sub             = p_cronofy_sub,
           status                  = 'active',
           connected_at            = now(),
           last_checked_at         = null,
           access_token_secret_id  = v_access_id,
           refresh_token_secret_id = v_refresh_id,
           token_expires_at        = p_expires_at
     where id = v_row.id
     returning id into v_id;
  else
    v_access_id := vault.create_secret(
      p_access_token, null, 'calendar access token ' || p_user_id || ' ' || p_provider);
    v_refresh_id := vault.create_secret(
      p_refresh_token, null, 'calendar refresh token ' || p_user_id || ' ' || p_provider);

    insert into public.calendar_connections (
      user_id, provider, cronofy_sub, status,
      access_token_secret_id, refresh_token_secret_id, token_expires_at
    )
    values (
      p_user_id, p_provider, p_cronofy_sub, 'active',
      v_access_id, v_refresh_id, p_expires_at
    )
    returning id into v_id;
  end if;

  return v_id;
end;
$$;

-- The two helpers keep 017's grants (create or replace preserves them); the
-- service role is still the only caller. Restated so this file stands alone.
revoke execute on function public.calendar_create_oauth_state(uuid, text) from public, anon, authenticated;
grant  execute on function public.calendar_create_oauth_state(uuid, text) to service_role;
revoke execute on function public.calendar_save_connection(uuid, text, text, text, text, timestamptz)
  from public, anon, authenticated;
grant  execute on function public.calendar_save_connection(uuid, text, text, text, text, timestamptz)
  to service_role;

-- =============================================================================
-- Verification (SQL editor)
-- =============================================================================
-- 1. The new value is accepted by both constraints (expect the check text to
--    mention outlook_personal):
--      select conname, pg_get_constraintdef(oid)
--        from pg_constraint
--       where conname in ('calendar_connections_provider_check',
--                         'calendar_oauth_states_provider_check');
--
-- 2. The helpers accept it (as postgres; rolled back):
--      begin;
--      select length(public.calendar_create_oauth_state('<a-user-uuid>', 'outlook_personal'));  -- 64
--      rollback;
--
-- 3. Still refused for clients:
--      select has_function_privilege('authenticated',
--               'public.calendar_create_oauth_state(uuid,text)', 'execute');   -- false
-- =============================================================================
