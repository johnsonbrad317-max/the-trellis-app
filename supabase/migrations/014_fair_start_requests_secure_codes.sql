-- =============================================================================
-- The Trellis — 014_fair_start_requests_secure_codes.sql  (Phase 4)
-- =============================================================================
-- Builds on 013. Three independent changes:
--
--   A. A fair start. 013 began counting a rhythm's scheduled days from the day
--      it was CREATED, so someone who set up a Rule of Life and waited a few
--      days to begin met their first check-in with a pile of misses and a dead
--      vine. A rhythm now begins counting on the day of its FIRST check-in.
--      A rhythm with no check-ins yet is simply unscored (it neither helps
--      nor hurts the average). Everything after that first check-in is
--      unchanged: every scheduled day counts, an unanswered one is a miss.
--
--   B. Real Runner -> Witness requests: support_requests, a create RPC that
--      fans a request out to the Runner's active Witnesses, RLS, a push event.
--      Replaces the old Insight-card button that claimed a Witness had been
--      notified while sending nothing.
--
--   C. Secure code generation. Invite/credential codes were minted from
--      md5(random()) (not cryptographically secure; 24-40 bits) and, for
--      church codes, from Dart's non-secure Random() on the client. Every
--      code is now generated server-side from pgcrypto's CSPRNG, and church
--      codes can only be minted through generate_church_code() — clients lose
--      INSERT on church_codes entirely.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- A. Fair start: a rhythm counts from its first check-in
-- -----------------------------------------------------------------------------
-- Same contract as 013's version (columns, 360-day horizon, countable grace for
-- the newest day, same recurrence rules). The only change: instead of
-- `day >= rhythm.created_at`, a rhythm's first day is its earliest check-in,
-- and a rhythm with no check-ins has no days at all.
create or replace function public._runner_resolved_days(
  p_runner_id uuid,
  p_days integer default 360
)
returns table (rule_item_id uuid, day date, hit boolean, countable boolean)
language sql
stable
security definer
set search_path = public
as $$
  with bounds as (select (current_date - 1) as last_day)
  select
    ri.id,
    d.day,
    coalesce(ci.answered_yes, false) as hit,
    -- Unanswered counts as a miss — except for the newest day (grace rule).
    (ci.id is not null or d.day <= b.last_day - 1) as countable
  from public.rule_items ri
  cross join bounds b
  -- First check-in per rhythm; rhythms never checked in drop out right here.
  join lateral (
    select min(c.check_in_date) as first_day
    from public.check_ins c
    where c.rule_item_id = ri.id
  ) f on f.first_day is not null
  cross join lateral (
    select g::date as day
    from generate_series(
      (b.last_day - (p_days - 1))::timestamp,
      b.last_day::timestamp,
      interval '1 day'
    ) as g
  ) d
  left join public.check_ins ci
    on ci.rule_item_id = ri.id and ci.check_in_date = d.day
  where ri.runner_id = p_runner_id
    and d.day >= f.first_day
    and case ri.frequency
          when 'daily'   then true
          when 'weekly'  then extract(isodow from d.day)::smallint = any (ri.weekly_days)
          when 'monthly' then extract(day from d.day) = 1
          when 'annual'  then extract(month from d.day) = 1 and extract(day from d.day) = 1
        end;
$$;

revoke execute on function public._runner_resolved_days(uuid, integer) from public, anon, authenticated;


-- -----------------------------------------------------------------------------
-- B. support_requests
-- -----------------------------------------------------------------------------
create table if not exists public.support_requests (
  id               uuid primary key default gen_random_uuid(),
  runner_id        uuid not null references public.profiles (id) on delete cascade,
  witness_id       uuid not null references public.profiles (id) on delete cascade,
  kind             text not null check (kind in ('prayer', 'meeting')),
  -- The rhythm the Runner was looking at when they asked (optional context).
  rule_item_id     uuid references public.rule_items (id) on delete set null,
  note             text check (note is null or char_length(note) <= 280),
  status           text not null default 'open' check (status in ('open', 'acknowledged')),
  created_at       timestamptz not null default now(),
  acknowledged_at  timestamptz
);
comment on table public.support_requests is
  'A Runner asking one of their Witnesses for prayer or a meeting. Created '
  'only through create_support_request(); the Witness acknowledges it.';

create index if not exists support_requests_witness_idx
  on public.support_requests (witness_id, status, created_at desc);
create index if not exists support_requests_runner_idx
  on public.support_requests (runner_id, created_at desc);

alter table public.support_requests enable row level security;

drop policy if exists "support_requests_select_either_side" on public.support_requests;
create policy "support_requests_select_either_side"
  on public.support_requests for select
  to authenticated
  using (runner_id = auth.uid() or witness_id = auth.uid());

-- Only the addressed Witness, only while still paired, may acknowledge.
drop policy if exists "support_requests_acknowledge_by_witness" on public.support_requests;
create policy "support_requests_acknowledge_by_witness"
  on public.support_requests for update
  to authenticated
  using (witness_id = auth.uid() and status = 'open' and public.is_witness_of(runner_id))
  with check (witness_id = auth.uid());

-- No client INSERT or DELETE: requests come from the RPC below, and a Runner's
-- ask is a record the Witness shouldn't see vanish.
revoke all on public.support_requests from authenticated, anon;
grant select on public.support_requests to authenticated;
grant update (status) on public.support_requests to authenticated;

-- A Witness can do exactly one thing: open -> acknowledged. (Stamps the time
-- itself so a client can't backdate it.)
create or replace function public.guard_support_request_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.runner_id    is distinct from old.runner_id
       or new.witness_id   is distinct from old.witness_id
       or new.kind         is distinct from old.kind
       or new.rule_item_id is distinct from old.rule_item_id
       or new.note         is distinct from old.note
       or new.created_at   is distinct from old.created_at then
      raise exception 'Only a request''s status may change.' using errcode = '42501';
    end if;
    if not (old.status = 'open' and new.status = 'acknowledged') then
      raise exception 'A request can only be acknowledged once.' using errcode = '42501';
    end if;
    new.acknowledged_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists support_requests_guard_update on public.support_requests;
create trigger support_requests_guard_update
  before update on public.support_requests
  for each row execute function public.guard_support_request_update();

-- Push: 004's notify_push_engine() (hardened in 011) -> push-notification-
-- engine, which now understands 'support_request'.
drop trigger if exists notify_push_on_support_request on public.support_requests;
create trigger notify_push_on_support_request
  after insert on public.support_requests
  for each row execute function public.notify_push_engine('support_request');

-- Realtime, so a Witness's list updates the moment a request lands.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'support_requests'
  ) then
    alter publication supabase_realtime add table public.support_requests;
  end if;
end $$;

-- Sends a prayer or meeting request to every ACTIVE Witness of the caller.
-- Returns how many Witnesses were newly asked. Zero means every Witness
-- already has an open-or-recent identical request (the same kind about the
-- same rhythm within 24 hours) — a tap-spam guard, not an error. Raises
-- NO_WITNESS if the caller has no active Witness at all.
create or replace function public.create_support_request(
  p_kind text,
  p_rule_item_id uuid default null,
  p_note text default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kind  text := lower(trim(coalesce(p_kind, '')));
  v_note  text := nullif(left(trim(coalesce(p_note, '')), 280), '');
  v_count integer;
begin
  if auth.uid() is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;
  if v_kind not in ('prayer', 'meeting') then
    raise exception 'Request kind must be prayer or meeting.' using errcode = '22023';
  end if;
  if p_rule_item_id is not null and not exists (
    select 1 from public.rule_items ri
    where ri.id = p_rule_item_id and ri.runner_id = auth.uid()
  ) then
    raise exception 'That rhythm is not yours.' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.witness_pairings wp
    where wp.runner_id = auth.uid() and wp.status = 'active'
  ) then
    raise exception 'NO_WITNESS' using errcode = 'P0001';
  end if;

  insert into public.support_requests (runner_id, witness_id, kind, rule_item_id, note)
  select auth.uid(), wp.witness_id, v_kind, p_rule_item_id, v_note
    from public.witness_pairings wp
   where wp.runner_id = auth.uid()
     and wp.status = 'active'
     and not exists (
       select 1 from public.support_requests sr
        where sr.runner_id  = wp.runner_id
          and sr.witness_id = wp.witness_id
          and sr.kind = v_kind
          and sr.rule_item_id is not distinct from p_rule_item_id
          and sr.created_at > now() - interval '24 hours'
     );

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.create_support_request(text, uuid, text) from public, anon;
grant  execute on function public.create_support_request(text, uuid, text) to authenticated;


-- -----------------------------------------------------------------------------
-- C. Secure code generation
-- -----------------------------------------------------------------------------
-- One generator for every code: pgcrypto's CSPRNG, 32-symbol alphabet with no
-- look-alikes (no 0/O/1/I). 32 divides 256, so `byte % 32` is unbiased.
-- Internal — clients never call it.
create or replace function public._secure_code(p_length integer)
returns text
language plpgsql
volatile
set search_path = public, extensions
as $$
declare
  c_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes  bytea := gen_random_bytes(p_length);
  v_result text := '';
  i integer;
begin
  for i in 0 .. p_length - 1 loop
    v_result := v_result || substr(c_alphabet, (get_byte(v_bytes, i) % 32) + 1, 1);
  end loop;
  return v_result;
end;
$$;

revoke execute on function public._secure_code(integer) from public, anon, authenticated;

-- Church codes: the Cloud admin's invite for one Runner. Only mintable here.
-- 8 symbols = 40 bits; capped at 200 unused codes per church so a stuck client
-- can't flood the table.
create or replace function public.generate_church_code(p_church_id uuid)
returns public.church_codes
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_row     public.church_codes;
  v_attempt integer := 0;
begin
  if not public.is_cloud_admin_of_church(p_church_id) then
    raise exception 'Not authorized to generate a church code for this church.'
      using errcode = '42501';
  end if;

  if (select count(*) from public.church_codes
       where church_id = p_church_id and not is_redeemed) >= 200 then
    raise exception 'Too many unused codes — revoke some before generating more.'
      using errcode = '54000';
  end if;

  loop
    v_attempt := v_attempt + 1;
    begin
      insert into public.church_codes (church_id, code)
      values (p_church_id, public._secure_code(8))
      returning * into v_row;
      return v_row;
    exception when unique_violation then
      if v_attempt >= 5 then raise; end if;
    end;
  end loop;
end;
$$;

revoke execute on function public.generate_church_code(uuid) from public, anon;
grant  execute on function public.generate_church_code(uuid) to authenticated;

-- Clients can no longer write church codes directly (they used to INSERT a
-- Dart-generated string). Reading and revoking (delete) your own church's
-- codes is unchanged.
drop policy if exists "church_codes_insert_own_church_admin" on public.church_codes;
revoke insert on public.church_codes from authenticated;

-- The other generators, moved off md5(random()):
--   Cloud Access Code: grants Cloud admin — 12 symbols (60 bits).
create or replace function public.generate_cloud_access_code(p_church_id uuid)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_code    text;
  v_attempt integer := 0;
begin
  if not public.is_cloud_admin_of_church(p_church_id) then
    raise exception 'Not authorized to generate a Cloud Access Code for this church.';
  end if;

  loop
    v_attempt := v_attempt + 1;
    v_code := public._secure_code(12);
    begin
      insert into public.cloud_access_codes (church_id, code) values (p_church_id, v_code);
      return v_code;
    exception when unique_violation then
      if v_attempt >= 5 then raise; end if;
    end;
  end loop;
end;
$$;

--   Pairing code: typed by a Witness within 24h, single-use — stays 6 symbols
--   (30 bits) for usability, but is now cryptographically random.
create or replace function public.generate_pairing_code()
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_code    text;
  v_attempt integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  loop
    v_attempt := v_attempt + 1;
    v_code := public._secure_code(6);
    begin
      insert into public.pairing_codes (runner_id, code) values (auth.uid(), v_code);
      return v_code;
    exception when unique_violation then
      if v_attempt >= 5 then raise; end if;
    end;
  end loop;
end;
$$;

--   Enterprise membership code: unlocks membership for a congregation — 12
--   symbols (60 bits). Signature and checks as in 005.
create or replace function public.generate_enterprise_church_code(
  p_church_id uuid,
  p_max_redemptions integer default null,
  p_expires_at timestamptz default null
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_code    text;
  v_attempt integer := 0;
begin
  if not public.is_cloud_admin_of_church(p_church_id) then
    raise exception 'Not authorized to generate an enterprise code for this church.';
  end if;
  if p_max_redemptions is not null and p_max_redemptions < 1 then
    raise exception 'max_redemptions must be at least 1, or omitted for unlimited.';
  end if;

  loop
    v_attempt := v_attempt + 1;
    v_code := public._secure_code(12);
    begin
      insert into public.enterprise_church_codes (church_id, code, max_redemptions, expires_at)
      values (p_church_id, v_code, p_max_redemptions, p_expires_at);
      return v_code;
    exception when unique_violation then
      if v_attempt >= 5 then raise; end if;
    end;
  end loop;
end;
$$;

-- create or replace keeps the grants made earlier; restate them so this file
-- is correct on its own.
revoke execute on function public.generate_cloud_access_code(uuid) from public, anon;
grant  execute on function public.generate_cloud_access_code(uuid) to authenticated;
revoke execute on function public.generate_pairing_code() from public, anon;
grant  execute on function public.generate_pairing_code() to authenticated;
revoke execute on function public.generate_enterprise_church_code(uuid, integer, timestamptz) from public, anon;
grant  execute on function public.generate_enterprise_church_code(uuid, integer, timestamptz) to authenticated;


-- =============================================================================
-- Verification (SQL editor, dev branch)
-- =============================================================================
-- A. Fair start
--    -- a rhythm created long ago but never checked in is unscored:
--    select * from _runner_resolved_days('<runner-uuid>', 360);   -- no rows for it
--    select _runner_analytics('<runner-uuid>') -> 'rhythms';       -- its completion_rate is null
--    -- after its first check-in, only days from that date forward appear.
--
-- B. Requests (as a signed-in Runner with an active Witness):
--    select create_support_request('prayer', '<one-of-your-rule-item-uuids>');   -- 1 per Witness
--    select create_support_request('prayer', '<same>');                          -- 0 (24h guard)
--    select create_support_request('meeting', null);                             -- 1
--    select create_support_request('prayer', '<someone-elses-rule-item>');       -- ERROR 42501
--    -- with no Witness: ERROR NO_WITNESS
--    -- as the Witness: update support_requests set status = 'acknowledged' where id = '<id>';  -- ok once
--    -- as the Runner: insert into support_requests ...  -- permission denied
--
-- C. Codes
--    select length(code), code from church_codes order by generated_at desc limit 3;
--    -- as a Cloud admin: select generate_church_code('<church-uuid>');      -- 8 symbols
--    -- as anyone else:   select generate_church_code('<church-uuid>');      -- ERROR 42501
--    -- as authenticated: insert into church_codes (church_id, code) values (...);  -- permission denied
--    -- anon: select check_pairing_code('X');   -- permission denied
-- =============================================================================
