-- =============================================================================
-- The Trellis — 017_calendar_availability.sql
-- =============================================================================
-- Calendar free/busy availability (Google / Outlook / Apple via Cronofy).
--
-- Goal: two paired people can each connect a calendar, and the app suggests
-- times when BOTH are free — without either person ever seeing the other's
-- busy blocks, and without The Trellis ever reading event contents (Cronofy is
-- asked for the `read_free_busy` scope only).
--
-- Where the pieces live:
--   * OAuth tokens never touch a client-readable column. They are stored in
--     Supabase Vault (vault.secrets, encrypted at rest); calendar_connections
--     keeps only the Vault secret ids, in columns `authenticated` has no grant
--     on. Only the service-role Edge Functions (calendar-connect-start,
--     calendar-oauth-callback, calendar-disconnect, calendar-availability) can
--     read or write tokens, through the SECURITY DEFINER helpers below, which
--     are executable by service_role ONLY.
--   * Clients learn "which of MY calendars are connected" via
--     get_my_calendar_connections(), and "is my partner connected at all" via
--     get_calendar_pair_status() — which never says WHICH provider the partner
--     uses and answers only for an active pairing.
--
-- Same two-layer style as 011: column-level GRANTs (layer 1) plus guard
-- triggers that reject direct client writes even if a blanket GRANT from 002 is
-- ever re-run (layer 2).
--
-- Numbering: 015 is the demo-code migration, 016 belongs to another change.
-- Idempotent — safe to run more than once.
--
-- Prerequisite: Supabase Vault enabled (it is by default; 011 already uses it).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. calendar_connections
-- -----------------------------------------------------------------------------
create table if not exists public.calendar_connections (
  id                       uuid primary key default gen_random_uuid(),
  user_id                  uuid not null references public.profiles (id) on delete cascade,
  provider                 text not null check (provider in ('google', 'outlook', 'apple')),
  -- Cronofy's stable account identifier (the `sub` of the token response).
  cronofy_sub              text,
  status                   text not null default 'active'
                             check (status in ('active', 'needs_reauth')),
  connected_at             timestamptz not null default now(),
  last_checked_at          timestamptz,
  -- Vault secret ids. NOT readable by clients (no column grant below).
  access_token_secret_id   uuid,
  refresh_token_secret_id  uuid,
  token_expires_at         timestamptz,
  unique (user_id, provider)
);

comment on table public.calendar_connections is
  'One row per connected calendar provider per user. Tokens live in Supabase '
  'Vault; this table only holds their secret ids, which clients cannot read.';

create index if not exists calendar_connections_user_idx
  on public.calendar_connections (user_id);

alter table public.calendar_connections enable row level security;

-- Clients: read their OWN row, non-secret columns only. No insert/update/delete
-- (the Edge Functions write as service_role; disconnect goes through
-- calendar-disconnect -> calendar_delete_connection).
revoke all on public.calendar_connections from anon;
revoke all on public.calendar_connections from authenticated;

grant select (id, user_id, provider, status, connected_at, last_checked_at)
  on public.calendar_connections to authenticated;
-- (cronofy_sub, the *_secret_id columns and token_expires_at are deliberately
--  absent: the client never needs them.)

drop policy if exists "calendar_connections_select_own" on public.calendar_connections;
create policy "calendar_connections_select_own"
  on public.calendar_connections for select
  to authenticated
  using (user_id = auth.uid());

-- Layer 2: block direct client writes even if table-level grants reappear.
create or replace function public.guard_calendar_connections_write()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    raise exception 'Calendar connections are managed by The Trellis itself.'
      using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists calendar_connections_guard_write on public.calendar_connections;
create trigger calendar_connections_guard_write
  before insert or update or delete on public.calendar_connections
  for each row execute function public.guard_calendar_connections_write();

-- Tokens must not outlive their connection row — including when the row goes
-- away through ON DELETE CASCADE (account deletion). Runs as the function
-- owner so it may delete from the vault schema.
create or replace function public.calendar_connections_purge_secrets()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from vault.secrets
   where id in (old.access_token_secret_id, old.refresh_token_secret_id);
  return old;
end;
$$;

revoke execute on function public.calendar_connections_purge_secrets() from public, anon, authenticated;

drop trigger if exists calendar_connections_purge_secrets on public.calendar_connections;
create trigger calendar_connections_purge_secrets
  after delete on public.calendar_connections
  for each row execute function public.calendar_connections_purge_secrets();


-- -----------------------------------------------------------------------------
-- 2. calendar_oauth_states — single-use nonces for the OAuth round trip
-- -----------------------------------------------------------------------------
-- calendar-connect-start inserts a row and signs the nonce into the OAuth
-- `state`; calendar-oauth-callback consumes it exactly once. A forged or
-- replayed callback therefore fails twice over (bad signature, or no live
-- nonce). No client access at all.
create table if not exists public.calendar_oauth_states (
  nonce       text primary key,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  provider    text not null check (provider in ('google', 'outlook', 'apple')),
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default (now() + interval '10 minutes'),
  used_at     timestamptz
);

create index if not exists calendar_oauth_states_expires_idx
  on public.calendar_oauth_states (expires_at);

alter table public.calendar_oauth_states enable row level security;
revoke all on public.calendar_oauth_states from anon;
revoke all on public.calendar_oauth_states from authenticated;
-- (RLS on with no policies: even a re-granted client sees nothing.)


-- -----------------------------------------------------------------------------
-- 3. Service-role-only helpers (the Edge Functions call these)
-- -----------------------------------------------------------------------------

-- 3a. Start an OAuth round trip: returns a fresh unguessable nonce.
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
  if p_provider not in ('google', 'outlook', 'apple') then
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

-- 3b. Atomically consume a nonce: returns (user_id, provider) once, and no
--     rows if it is unknown, already used, or expired.
create or replace function public.calendar_consume_oauth_state(p_nonce text)
returns table (user_id uuid, provider text)
language sql
security definer
set search_path = public
as $$
  update public.calendar_oauth_states s
     set used_at = now()
   where s.nonce = p_nonce
     and s.used_at is null
     and s.expires_at > now()
  returning s.user_id, s.provider;
$$;

-- 3c. Create or replace a user's connection for one provider, storing both
--     tokens in Vault. Returns the connection id.
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
  if p_provider not in ('google', 'outlook', 'apple') then
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

-- 3d. Read decrypted tokens. p_provider null = every connection of the user.
create or replace function public.calendar_read_tokens(
  p_user_id  uuid,
  p_provider text default null
)
returns table (
  provider         text,
  cronofy_sub      text,
  status           text,
  access_token     text,
  refresh_token    text,
  token_expires_at timestamptz
)
language sql
security definer
stable
set search_path = public
as $$
  select c.provider,
         c.cronofy_sub,
         c.status,
         a.decrypted_secret::text,
         r.decrypted_secret::text,
         c.token_expires_at
    from public.calendar_connections c
    left join vault.decrypted_secrets a on a.id = c.access_token_secret_id
    left join vault.decrypted_secrets r on r.id = c.refresh_token_secret_id
   where c.user_id = p_user_id
     and (p_provider is null or c.provider = p_provider);
$$;

-- 3e. Rotate tokens after a refresh. A null refresh token keeps the old one.
--     Also flips the connection back to 'active'.
create or replace function public.calendar_update_tokens(
  p_user_id       uuid,
  p_provider      text,
  p_access_token  text,
  p_refresh_token text,
  p_expires_at    timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.calendar_connections%rowtype;
begin
  select * into v_row
    from public.calendar_connections
   where user_id = p_user_id and provider = p_provider
   for update;

  if not found then
    return false;
  end if;

  if v_row.access_token_secret_id is not null then
    perform vault.update_secret(v_row.access_token_secret_id, p_access_token);
  end if;
  if p_refresh_token is not null and v_row.refresh_token_secret_id is not null then
    perform vault.update_secret(v_row.refresh_token_secret_id, p_refresh_token);
  end if;

  update public.calendar_connections
     set token_expires_at = p_expires_at,
         status           = 'active',
         last_checked_at  = now()
   where id = v_row.id;

  return true;
end;
$$;

-- 3f. Mark a connection active / needs_reauth (and stamp last_checked_at).
create or replace function public.calendar_set_status(
  p_user_id  uuid,
  p_provider text,
  p_status   text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_status not in ('active', 'needs_reauth') then
    raise exception 'Unknown status.' using errcode = '22023';
  end if;

  update public.calendar_connections
     set status = p_status, last_checked_at = now()
   where user_id = p_user_id and provider = p_provider;

  return found;
end;
$$;

-- 3g. Delete a connection. The AFTER DELETE trigger above purges its Vault
--     secrets.
create or replace function public.calendar_delete_connection(
  p_user_id  uuid,
  p_provider text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.calendar_connections
   where user_id = p_user_id and provider = p_provider;
  return found;
end;
$$;

-- service_role only. (Postgres grants EXECUTE to PUBLIC by default, so revoke
-- explicitly from every client role.)
revoke execute on function public.calendar_create_oauth_state(uuid, text)
  from public, anon, authenticated;
revoke execute on function public.calendar_consume_oauth_state(text)
  from public, anon, authenticated;
revoke execute on function public.calendar_save_connection(uuid, text, text, text, text, timestamptz)
  from public, anon, authenticated;
revoke execute on function public.calendar_read_tokens(uuid, text)
  from public, anon, authenticated;
revoke execute on function public.calendar_update_tokens(uuid, text, text, text, timestamptz)
  from public, anon, authenticated;
revoke execute on function public.calendar_set_status(uuid, text, text)
  from public, anon, authenticated;
revoke execute on function public.calendar_delete_connection(uuid, text)
  from public, anon, authenticated;

grant execute on function public.calendar_create_oauth_state(uuid, text) to service_role;
grant execute on function public.calendar_consume_oauth_state(text) to service_role;
grant execute on function public.calendar_save_connection(uuid, text, text, text, text, timestamptz) to service_role;
grant execute on function public.calendar_read_tokens(uuid, text) to service_role;
grant execute on function public.calendar_update_tokens(uuid, text, text, text, timestamptz) to service_role;
grant execute on function public.calendar_set_status(uuid, text, text) to service_role;
grant execute on function public.calendar_delete_connection(uuid, text) to service_role;


-- -----------------------------------------------------------------------------
-- 4. Client-callable RPCs
-- -----------------------------------------------------------------------------

-- 4a. "Which of MY calendars are connected?" — no tokens, no Cronofy ids.
create or replace function public.get_my_calendar_connections()
returns table (provider text, status text, connected_at timestamptz)
language sql
security definer
stable
set search_path = public
as $$
  select c.provider, c.status, c.connected_at
    from public.calendar_connections c
   where c.user_id = auth.uid()
   order by c.connected_at;
$$;

-- 4b. "Are we both connected?" — only for an ACTIVE pairing (either
--     direction). A caller with no active pairing to p_other_user_id gets
--     (false, false), indistinguishable from "neither connected", so this can't
--     be used to probe other people. Never reveals which provider the other
--     person uses. A connection that needs re-authorising doesn't count.
create or replace function public.get_calendar_pair_status(p_other_user_id uuid)
returns table (me_connected boolean, other_connected boolean)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_me     uuid := auth.uid();
  v_paired boolean;
begin
  if v_me is null or p_other_user_id is null then
    return query select false, false;
    return;
  end if;

  select exists (
    select 1
      from public.witness_pairings wp
     where wp.status = 'active'
       and ((wp.runner_id = v_me and wp.witness_id = p_other_user_id)
         or (wp.runner_id = p_other_user_id and wp.witness_id = v_me))
  ) into v_paired;

  if not v_paired then
    return query select false, false;
    return;
  end if;

  return query
    select
      exists (select 1 from public.calendar_connections c
               where c.user_id = v_me and c.status = 'active'),
      exists (select 1 from public.calendar_connections c
               where c.user_id = p_other_user_id and c.status = 'active');
end;
$$;

revoke execute on function public.get_my_calendar_connections() from public, anon;
revoke execute on function public.get_calendar_pair_status(uuid) from public, anon;
grant  execute on function public.get_my_calendar_connections() to authenticated;
grant  execute on function public.get_calendar_pair_status(uuid) to authenticated;


-- =============================================================================
-- Verification (SQL editor, dev branch) — nothing below runs
-- =============================================================================
-- A. Structure / privileges
--    select column_name from information_schema.column_privileges
--     where table_name = 'calendar_connections' and grantee = 'authenticated';
--    -- expect ONLY: id, user_id, provider, status, connected_at, last_checked_at
--    --   (never cronofy_sub / *_secret_id / token_expires_at)
--
--    select has_function_privilege('authenticated',
--             'public.calendar_read_tokens(uuid,text)', 'execute');   -- false
--    select has_function_privilege('service_role',
--             'public.calendar_read_tokens(uuid,text)', 'execute');   -- true
--    select has_function_privilege('anon',
--             'public.get_calendar_pair_status(uuid)', 'execute');    -- false
--
-- B. As a signed-in user (set role authenticated; set request.jwt.claims ...):
--    select * from get_my_calendar_connections();            -- own rows only
--    select id, provider, status from calendar_connections;   -- own rows only
--    select * from calendar_connections;                      -- permission denied (token cols)
--    select access_token_secret_id from calendar_connections; -- permission denied
--    insert into calendar_connections (user_id, provider) values (auth.uid(), 'google');
--                                                             -- permission denied
--    select calendar_read_tokens(auth.uid(), 'google');       -- permission denied
--    select * from get_calendar_pair_status('<partner-uuid>');    -- (me, other) booleans
--    select * from get_calendar_pair_status('<stranger-uuid>');   -- (false, false)
--
-- C. As service_role (round trip):
--    select calendar_create_oauth_state('<user-uuid>', 'google');          -- nonce
--    select * from calendar_consume_oauth_state('<nonce>');                 -- 1 row
--    select * from calendar_consume_oauth_state('<nonce>');                 -- 0 rows (single use)
--    select calendar_save_connection('<user-uuid>', 'google', 'acc_123',
--                                    'access-x', 'refresh-x', now() + interval '1 hour');
--    select * from calendar_read_tokens('<user-uuid>');                     -- decrypted tokens
--    select calendar_update_tokens('<user-uuid>', 'google', 'access-y', 'refresh-y',
--                                  now() + interval '1 hour');
--    select calendar_set_status('<user-uuid>', 'google', 'needs_reauth');
--    select calendar_delete_connection('<user-uuid>', 'google');            -- true
--    select count(*) from vault.secrets
--     where description like 'calendar % token <user-uuid> google';         -- 0 (purged)
--
-- D. Cascade: deleting a profile (delete-account) removes its connections AND
--    their Vault secrets (the purge trigger fires on cascaded deletes).
-- =============================================================================
