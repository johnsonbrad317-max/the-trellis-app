-- =============================================================================
-- The Trellis — 005_enterprise_church_codes.sql
-- =============================================================================
-- Phase 1, item 1: an enterprise "Church Code" a Runner can redeem to get
-- full membership without going through Apple/RevenueCat IAP — for a
-- church that's already paid for a block of memberships out-of-band
-- (the same B2B motion this app already uses for Cloud access; see
-- 002_grants_and_cloud_access.sql's cloud_access_codes).
--
-- Deliberately a NEW table, not a reuse of church_codes (init_schema.sql) —
-- that one is a single-use, roster-join code that injects Canopy Rhythms; a
-- membership-bypass code is a completely different concern (billing, not
-- roster membership) and is normally shared with an entire congregation,
-- so it has to support many redemptions from one code, not one.
--
-- A note on App Store risk, since this exists specifically to bypass
-- Apple's IAP: this is only defensible under Guideline 3.1.3 if the code
-- is tied to a real, out-of-app B2B purchase a church actually made (the
-- same story as Cloud access) — never sold or handed out to individual
-- consumers as a way around the $12/yr subscription. Worth a line in your
-- App Review notes explaining the enterprise-licensing model if you ship
-- this before a wider beta.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- A. Tables
-- -----------------------------------------------------------------------------
create table if not exists public.enterprise_church_codes (
  id                uuid primary key default gen_random_uuid(),
  church_id         uuid not null references public.churches (id) on delete cascade,
  code              text not null unique,
  -- null = unlimited redemptions (a whole congregation sharing one code).
  max_redemptions   integer,
  redemption_count  integer not null default 0,
  expires_at        timestamptz,
  created_at        timestamptz not null default now()
);
comment on table public.enterprise_church_codes is
  'Bypasses Apple/RevenueCat IAP for a church that already paid for a '
  'block of memberships out-of-band. Zero RLS policies, same lockdown as '
  'cloud_access_codes/pairing_codes — reachable only through '
  'generate_enterprise_church_code()/redeem_enterprise_church_code() below.';

create index if not exists enterprise_church_codes_church_idx
  on public.enterprise_church_codes (church_id);

-- One row per successful redemption — both to stop the same Runner
-- double-counting against max_redemptions by redeeming twice, and to give
-- the church an audit trail of who actually used their code.
create table if not exists public.enterprise_church_code_redemptions (
  id           uuid primary key default gen_random_uuid(),
  code_id      uuid not null references public.enterprise_church_codes (id) on delete cascade,
  runner_id    uuid not null references public.profiles (id) on delete cascade,
  redeemed_at  timestamptz not null default now(),
  unique (code_id, runner_id)
);

create index if not exists enterprise_church_code_redemptions_runner_idx
  on public.enterprise_church_code_redemptions (runner_id);


-- -----------------------------------------------------------------------------
-- B. Lock both tables down completely — same pattern as cloud_access_codes
--    and pairing_codes (003/002): RLS enabled, zero policies, reachable
--    only through the SECURITY DEFINER functions below.
-- -----------------------------------------------------------------------------
revoke all on public.enterprise_church_codes from authenticated, anon;
alter table public.enterprise_church_codes enable row level security;

revoke all on public.enterprise_church_code_redemptions from authenticated, anon;
alter table public.enterprise_church_code_redemptions enable row level security;


-- -----------------------------------------------------------------------------
-- C. RPCs
-- -----------------------------------------------------------------------------
-- Mints a new code for a church — callable only by that church's existing
-- Cloud admin, same restriction as generate_cloud_access_code (002).
create or replace function public.generate_enterprise_church_code(
  p_church_id uuid,
  p_max_redemptions integer default null,
  p_expires_at timestamptz default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if not public.is_cloud_admin_of_church(p_church_id) then
    raise exception 'Not authorized to generate an enterprise code for this church.';
  end if;
  if p_max_redemptions is not null and p_max_redemptions < 1 then
    raise exception 'max_redemptions must be at least 1, or omitted for unlimited.';
  end if;

  v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 10));

  insert into public.enterprise_church_codes (church_id, code, max_redemptions, expires_at)
  values (p_church_id, v_code, p_max_redemptions, p_expires_at);

  return v_code;
end;
$$;

-- Redeems a code for the calling Runner: row-locks the code first so two
-- simultaneous redemptions on the last remaining slot can't both succeed,
-- then validates expiry, remaining capacity, and that this Runner hasn't
-- already redeemed this exact code before granting active membership.
create or replace function public.redeem_enterprise_church_code(p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code_row public.enterprise_church_codes%rowtype;
begin
  select * into v_code_row
  from public.enterprise_church_codes
  where code = upper(trim(p_code))
  for update;

  if v_code_row.id is null then
    return false;
  end if;
  if v_code_row.expires_at is not null and v_code_row.expires_at < now() then
    return false;
  end if;
  if v_code_row.max_redemptions is not null
     and v_code_row.redemption_count >= v_code_row.max_redemptions then
    return false;
  end if;
  if exists (
    select 1 from public.enterprise_church_code_redemptions
    where code_id = v_code_row.id and runner_id = auth.uid()
  ) then
    -- Already redeemed by this account — treat as success rather than an
    -- error; membership is already active, nothing more to do.
    return true;
  end if;

  insert into public.enterprise_church_code_redemptions (code_id, runner_id)
  values (v_code_row.id, auth.uid());

  update public.enterprise_church_codes
     set redemption_count = redemption_count + 1
   where id = v_code_row.id;

  update public.profiles
     set membership_status = 'active'
   where id = auth.uid();

  return true;
end;
$$;

grant execute on function public.generate_enterprise_church_code(uuid, integer, timestamptz)
  to authenticated;
grant execute on function public.redeem_enterprise_church_code(text) to authenticated;
