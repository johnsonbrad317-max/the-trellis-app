-- =============================================================================
-- The Trellis — 011_security_lockdown.sql  (Phase 1)
-- =============================================================================
-- Closes the privilege-escalation holes found in the backend audit. Every one
-- of them had the same root cause: init_schema.sql wrote row-level policies
-- ("who may touch this row") but 002 then handed `authenticated` blanket
-- INSERT/UPDATE/DELETE on every table, and no policy ever said "which COLUMNS
-- may they change, and to what". The result:
--
--   * any user could UPDATE their own profiles.cloud_admin_church_id (instant
--     Cloud admin for any church), membership_status (free membership), role,
--     church_id
--   * any user could INSERT a witness_pairings row naming any victim as
--     runner_id (instant read access to that Runner's rules/check-ins/prayers)
--   * a Runner could PATCH rule_items.is_church_mandated=false, or DELETE a
--     mandated rhythm, with no Witness approval
--   * a Runner could point an unlock request at SOMEONE ELSE'S rule item
--   * Witnesses/Cloud admins could `select *` another user's fcm_token,
--     home_address, work_address
--   * a Cloud admin could rewrite their own church's license_cap / rate
--   * push-notification-engine accepted a forged event from anyone holding
--     the (public) publishable key
--
-- Strategy — two independent layers per rule, so one mistake can't reopen it:
--   Layer 1: column-level GRANTs (the client can only name columns it may set).
--   Layer 2: BEFORE UPDATE guard triggers that re-check the same rules when
--            `current_user` is a client role (authenticated/anon). SECURITY
--            DEFINER RPCs run as the function owner and service_role runs as
--            itself, so neither is affected — only direct PostgREST writes.
--            This layer exists because 002's blanket `GRANT ... ON ALL TABLES`
--            re-adds table-level UPDATE if anyone ever re-runs it, silently
--            undoing layer 1.
--
-- !! DEPLOY ORDER — READ BEFORE RUNNING !!
--   Column-level SELECT on profiles means `select('*')` on profiles now FAILS
--   with "permission denied". The current Flutter build does exactly that in
--   RunnerProfile.loadCurrent() and redeemChurchCode(); AuthGate treats a
--   loadCurrent() error as "stale session" and signs the user out, i.e. every
--   existing build is locked out until it ships the Dart companion change:
--     1. select an explicit column list instead of '*'
--     2. read home_address/work_address via rpc('get_my_private_profile')
--     3. cancelMembership() can no longer write membership_status (RevenueCat
--        webhook is the only writer) — stop updating it from the client
--   Order: the Dart change needs get_my_private_profile(), which this file
--   creates, so either (a) run this migration and release the new build in the
--   same maintenance window, or (b) release the build first with the RPC call
--   wrapped in try/catch (addresses just show empty until the migration runs).
--   Do NOT run this migration while old builds are still in users' hands.
--
-- Also required alongside this file (not SQL):
--   * supabase/functions/push-notification-engine and delete-account were
--     changed in the same commit — redeploy both, and set the secret (see
--     section 9 at the bottom).
--
-- Not changed here on purpose (later phases): profiles.role switching RPC and
-- roster view (Phase 2), analytics (Phase 3), code entropy/rate limiting.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 0. Baseline grants: nothing for anon, least privilege for authenticated
-- -----------------------------------------------------------------------------
-- anon never reads application tables; every policy is `to authenticated`.
revoke all on all tables in schema public from anon;

-- Tables whose rows are only ever written by triggers/RPCs/views:
revoke insert, update, delete on public.grace_nudges         from authenticated;
revoke insert, update, delete on public.church_roster        from authenticated;
revoke insert, update, delete on public.church_license_usage from authenticated;

-- Every user-facing function: callable by signed-in users only. Postgres grants
-- EXECUTE to PUBLIC by default, which left check_pairing_code() etc. open to
-- unauthenticated callers (code/church-name enumeration).
revoke execute on function public.is_witness_of(uuid)                              from public, anon;
revoke execute on function public.is_cloud_admin_of_church(uuid)                   from public, anon;
revoke execute on function public.is_cloud_admin_of_runner(uuid)                   from public, anon;
revoke execute on function public.generate_cloud_access_code(uuid)                 from public, anon;
revoke execute on function public.redeem_cloud_access_code(text)                   from public, anon;
revoke execute on function public.generate_pairing_code()                          from public, anon;
revoke execute on function public.check_pairing_code(text)                         from public, anon;
revoke execute on function public.redeem_pairing_code(text, boolean)               from public, anon;
revoke execute on function public.redeem_church_code(text)                         from public, anon;
revoke execute on function public.generate_enterprise_church_code(uuid, integer, timestamptz) from public, anon;
revoke execute on function public.redeem_enterprise_church_code(text)              from public, anon;
revoke execute on function public.get_congregational_health(uuid)                  from public, anon;

grant execute on function public.is_witness_of(uuid)                              to authenticated;
grant execute on function public.is_cloud_admin_of_church(uuid)                   to authenticated;
grant execute on function public.is_cloud_admin_of_runner(uuid)                   to authenticated;
grant execute on function public.generate_cloud_access_code(uuid)                 to authenticated;
grant execute on function public.redeem_cloud_access_code(text)                   to authenticated;
grant execute on function public.generate_pairing_code()                          to authenticated;
grant execute on function public.check_pairing_code(text)                         to authenticated;
grant execute on function public.redeem_pairing_code(text, boolean)               to authenticated;
grant execute on function public.redeem_church_code(text)                         to authenticated;
grant execute on function public.generate_enterprise_church_code(uuid, integer, timestamptz) to authenticated;
grant execute on function public.redeem_enterprise_church_code(text)              to authenticated;
grant execute on function public.get_congregational_health(uuid)                  to authenticated;


-- -----------------------------------------------------------------------------
-- 1. profiles
-- -----------------------------------------------------------------------------
-- 1a. Sign-up can only ever create a Runner or a Witness. handle_new_user
--     previously cast whatever the client put in raw_user_meta_data.role,
--     including 'cloud'. (Same defensive structure as 010.)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.user_role;
begin
  v_role := case lower(coalesce(new.raw_user_meta_data ->> 'role', ''))
              when 'witness' then 'witness'::public.user_role
              else 'runner'::public.user_role
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
  raise exception 'handle_new_user failed for auth.users.id=%: % (SQLSTATE %)',
    new.id, sqlerrm, sqlstate;
end;
$$;

-- 1b. No client INSERT/DELETE on profiles at all. The signup trigger (a
--     definer) is the only creator; delete-account (service role) the only
--     remover. 010's "profiles_insert_self" fallback let a client create its
--     own row with arbitrary cloud_admin_church_id/membership_status if the
--     trigger row were ever missing.
drop policy if exists "profiles_insert_self" on public.profiles;
revoke insert, delete on public.profiles from authenticated;

-- 1c. Column-level privileges.
--     SELECT: everything EXCEPT fcm_token, home_address, work_address and the
--     unused pairing_code. Row visibility (Witness sees their Runner, Cloud
--     admin sees their church) is unchanged, but those rows no longer carry
--     the sensitive fields. The owner reads their own home/work address via
--     get_my_private_profile() below; fcm_token is write-only from the client.
--     UPDATE: only genuinely self-service fields. role, membership_status,
--     church_id, is_church_affiliation_locked, cloud_admin_church_id,
--     pairing_code, created_at, id are NOT client-writable.
revoke all on public.profiles from authenticated;

grant select (
  id, name, email, role, membership_status, church_id,
  is_church_affiliation_locked, accountability_lock_enabled,
  accountability_lock_removal_pending, daily_check_in_reminder,
  has_committed_rule, prayer_reminder_time, has_completed_scheduling_setup,
  calendar_connected, notification_preferences, created_at,
  cloud_admin_church_id, phone_number
) on public.profiles to authenticated;

grant update (
  name, email, phone_number, daily_check_in_reminder, prayer_reminder_time,
  has_committed_rule, has_completed_scheduling_setup, calendar_connected,
  home_address, work_address, notification_preferences, fcm_token,
  accountability_lock_enabled, accountability_lock_removal_pending
) on public.profiles to authenticated;

-- 1d. Owner-only read of the withheld fields.
create or replace function public.get_my_private_profile()
returns table (home_address text, work_address text)
language sql
security definer
stable
set search_path = public
as $$
  select p.home_address, p.work_address
  from public.profiles p
  where p.id = auth.uid();
$$;

revoke execute on function public.get_my_private_profile() from public, anon;
grant  execute on function public.get_my_private_profile() to authenticated;

-- 1e. Row visibility. Dropped the 4th OR-branch of init_schema.sql's policy
--     (a Cloud admin reading Witness profiles via witness_pairings): it
--     subqueried witness_pairings under the CALLER's RLS, so for a Cloud admin
--     it could never match — dead code — and if it ever did match it would
--     expose every Witness's email/phone regardless of the consent recorded in
--     007/008. Phase 2 rebuilds the roster's Witness data through a
--     consent-gated function instead.
drop policy if exists "profiles_select_self_paired_or_roster" on public.profiles;
create policy "profiles_select_self_paired_or_roster"
  on public.profiles for select
  to authenticated
  using (
    id = auth.uid()
    or public.is_witness_of(id)
    or public.is_cloud_admin_of_church(church_id)
  );
-- (profiles_select_own_witnesses from 004 and profiles_update_self are kept.)

-- 1f. Layer 2: guard trigger. Blocks the protected columns for direct client
--     writes even if column grants are ever widened again, and blocks the
--     accountability lock being turned OFF from the client (the Witness-
--     approval workflow for that doesn't exist yet; the app only ever sets it
--     true and files a removal *request* flag, so nothing legitimate is lost).
create or replace function public.guard_profile_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.id                           is distinct from old.id
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

    if old.accountability_lock_enabled and not new.accountability_lock_enabled then
      raise exception 'The accountability lock can only be removed with your Witness''s approval.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_guard_update on public.profiles;
create trigger profiles_guard_update
  before update on public.profiles
  for each row execute function public.guard_profile_update();


-- -----------------------------------------------------------------------------
-- 2. witness_pairings — created only by redeem_pairing_code(); never rewritten
-- -----------------------------------------------------------------------------
drop policy if exists "witness_pairings_insert_own_side" on public.witness_pairings;
revoke insert, delete on public.witness_pairings from authenticated;

-- Clients may change exactly one column: status (to end a pairing).
revoke update on public.witness_pairings from authenticated;
grant  update (status) on public.witness_pairings to authenticated;

-- A pairing can never be with yourself. NOT VALID: don't fail on legacy rows,
-- but enforce for every new/updated row.
alter table public.witness_pairings
  drop constraint if exists witness_pairings_not_self;
alter table public.witness_pairings
  add constraint witness_pairings_not_self check (runner_id <> witness_id) not valid;

-- Layer 2. From the client a pairing can only go active -> removed, never back
-- (re-pairing needs a fresh code via the RPC, which also re-checks consent),
-- ids/consent/paired_since never change, and a Runner with the accountability
-- lock on cannot end a pairing unilaterally (a Witness can always step away).
create or replace function public.guard_pairing_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.runner_id          is distinct from old.runner_id
       or new.witness_id      is distinct from old.witness_id
       or new.paired_since    is distinct from old.paired_since
       or new.church_data_consent is distinct from old.church_data_consent then
      raise exception 'Only a pairing''s status may be changed.' using errcode = '42501';
    end if;

    if new.status is distinct from old.status then
      if not (old.status = 'active' and new.status = 'removed') then
        raise exception 'A pairing can only be ended here; use a new pairing code to re-pair.'
          using errcode = '42501';
      end if;

      if auth.uid() = old.runner_id
         and exists (
           select 1 from public.profiles p
           where p.id = old.runner_id and p.accountability_lock_enabled
         ) then
        raise exception 'Your accountability lock requires your Witness to approve this removal.'
          using errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists witness_pairings_guard_update on public.witness_pairings;
create trigger witness_pairings_guard_update
  before update on public.witness_pairings
  for each row execute function public.guard_pairing_update();

-- The RPC is now the *only* way in, so it must be airtight: add the self-pair
-- check (everything else is 007's logic unchanged). Raising rolls back the
-- code claim, so a rejected attempt doesn't burn the code.
create or replace function public.redeem_pairing_code(p_code text, p_consent boolean default false)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_runner_id uuid;
  v_church_id uuid;
begin
  if auth.uid() is null then
    return false;
  end if;

  update public.pairing_codes
     set is_redeemed = true, redeemed_by = auth.uid(), redeemed_at = now()
   where code = upper(trim(p_code)) and not is_redeemed and expires_at > now()
   returning runner_id into v_runner_id;

  if v_runner_id is null then
    return false;
  end if;

  if v_runner_id = auth.uid() then
    raise exception 'You can''t be your own Witness.';
  end if;

  select church_id into v_church_id from public.profiles where id = v_runner_id;

  if v_church_id is not null and not p_consent then
    raise exception
      'Consent to share your contact details with the Runner''s church is required.';
  end if;

  insert into public.witness_pairings (runner_id, witness_id, status, church_data_consent)
  values (v_runner_id, auth.uid(), 'active', v_church_id is not null and p_consent)
  on conflict (runner_id, witness_id)
  do update set status = 'active', church_data_consent = excluded.church_data_consent;

  return true;
end;
$$;

revoke execute on function public.redeem_pairing_code(text, boolean) from public, anon;
grant  execute on function public.redeem_pairing_code(text, boolean) to authenticated;


-- -----------------------------------------------------------------------------
-- 3. rule_items — DNA (church-mandated) rhythms are immutable to the client
-- -----------------------------------------------------------------------------
-- INSERT: a client can never create a row flagged mandated (only
-- redeem_church_code(), a definer, does). DELETE: never a mandated row.
drop policy if exists "rule_items_write_own"  on public.rule_items;
drop policy if exists "rule_items_delete_own" on public.rule_items;

create policy "rule_items_write_own"
  on public.rule_items for insert
  to authenticated
  with check (runner_id = auth.uid() and not is_church_mandated);

create policy "rule_items_delete_own"
  on public.rule_items for delete
  to authenticated
  using (runner_id = auth.uid() and not is_church_mandated);

-- UPDATE: only the four fields the Rule Builder actually edits.
revoke update on public.rule_items from authenticated;
grant  update (title, frequency, weekly_days, is_anchor_rhythm)
  on public.rule_items to authenticated;

-- Layer 2. is_church_mandated flips to false only via the approved-unlock
-- trigger (apply_unlock_request_approval, a definer — unaffected by this).
-- While mandated, nothing about the rhythm may change from the client.
create or replace function public.guard_rule_item_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.runner_id           is distinct from old.runner_id
       or new.category         is distinct from old.category
       or new.is_church_mandated is distinct from old.is_church_mandated then
      raise exception 'That field on a rhythm can''t be changed directly.'
        using errcode = '42501';
    end if;

    if old.is_church_mandated
       and (   new.title            is distinct from old.title
            or new.frequency        is distinct from old.frequency
            or new.weekly_days      is distinct from old.weekly_days
            or new.is_anchor_rhythm is distinct from old.is_anchor_rhythm) then
      raise exception 'This is a DNA Rhythm; ask your Witness to unlock it first.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists rule_items_guard_update on public.rule_items;
create trigger rule_items_guard_update
  before update on public.rule_items
  for each row execute function public.guard_rule_item_update();


-- -----------------------------------------------------------------------------
-- 4. pending_unlock_requests — can only target the requester's OWN mandated item
-- -----------------------------------------------------------------------------
-- Previously rule_item_id was unchecked: a Runner (with any paired Witness,
-- including a second account of their own) could file a request naming a
-- *victim's* rule item, and the approval trigger would then clear
-- is_church_mandated on the victim's row.
drop policy if exists "unlock_requests_insert_by_runner" on public.pending_unlock_requests;
create policy "unlock_requests_insert_by_runner"
  on public.pending_unlock_requests for insert
  to authenticated
  with check (
    runner_id = auth.uid()
    and status = 'pending'
    and exists (
      select 1 from public.witness_pairings wp
      where wp.runner_id  = auth.uid()
        and wp.witness_id = pending_unlock_requests.witness_id
        and wp.status = 'active'
    )
    and exists (
      select 1 from public.rule_items ri
      where ri.id = pending_unlock_requests.rule_item_id
        and ri.runner_id = auth.uid()
        and ri.is_church_mandated
    )
  );

-- A Witness whose pairing has ended can no longer resolve requests.
drop policy if exists "unlock_requests_update_by_witness" on public.pending_unlock_requests;
create policy "unlock_requests_update_by_witness"
  on public.pending_unlock_requests for update
  to authenticated
  using (witness_id = auth.uid() and status = 'pending'
         and public.is_witness_of(runner_id))
  with check (witness_id = auth.uid());

revoke update on public.pending_unlock_requests from authenticated;
grant  update (status) on public.pending_unlock_requests to authenticated;
-- (003's enforce_unlock_request_update trigger already restricts the
--  transition to pending -> approved/denied and stamps resolved_at.)


-- -----------------------------------------------------------------------------
-- 5. churches — only your own church; only a name is editable
-- -----------------------------------------------------------------------------
-- Previously readable by every signed-in user (a directory of church ids — the
-- exact value needed for the cloud_admin_church_id self-grant — plus each
-- church's billing rate and license cap).
create or replace function public.current_user_church_id()
returns uuid
language sql
security definer
stable
set search_path = public
as $$
  select church_id from public.profiles where id = auth.uid();
$$;

revoke execute on function public.current_user_church_id() from public, anon;
grant  execute on function public.current_user_church_id() to authenticated;

drop policy if exists "churches_select_any_authenticated" on public.churches;
create policy "churches_select_own_or_admin"
  on public.churches for select
  to authenticated
  using (
    public.is_cloud_admin_of_church(id)
    or id = public.current_user_church_id()
  );
-- Residual: a Runner can still read their OWN church's rate/license columns.
-- If that matters, move billing fields behind a Cloud-admin-only RPC (Phase 2/3).

-- A Cloud admin may rename their church; license_cap / rate_per_runner /
-- annual_renewal_date are billing facts only the service role may change.
revoke insert, update, delete on public.churches from authenticated;
grant  update (name) on public.churches to authenticated;


-- -----------------------------------------------------------------------------
-- 6. check_ins — can only record against your OWN rule items
-- -----------------------------------------------------------------------------
-- Previously rule_item_id was unchecked; (rule_item_id, check_in_date) is
-- unique, so a user could pre-insert a row for a victim's rule item and block
-- or poison that victim's check-in (and trip their grace-nudge trigger).
-- (No column-level restriction here: the app UPSERTs, whose ON CONFLICT DO
--  UPDATE touches every inserted column.)
drop policy if exists "check_ins_write_own"  on public.check_ins;
drop policy if exists "check_ins_update_own" on public.check_ins;

create policy "check_ins_write_own"
  on public.check_ins for insert
  to authenticated
  with check (
    runner_id = auth.uid()
    and exists (
      select 1 from public.rule_items ri
      where ri.id = check_ins.rule_item_id and ri.runner_id = auth.uid()
    )
  );

create policy "check_ins_update_own"
  on public.check_ins for update
  to authenticated
  using (runner_id = auth.uid())
  with check (
    runner_id = auth.uid()
    and exists (
      select 1 from public.rule_items ri
      where ri.id = check_ins.rule_item_id and ri.runner_id = auth.uid()
    )
  );


-- -----------------------------------------------------------------------------
-- 7. meetings — only between actively paired people, only as yourself
-- -----------------------------------------------------------------------------
-- Previously anyone could insert a meeting naming any two accounts, which
-- (via 004's trigger) also fired a push notification at the other account.
drop policy if exists "meetings_insert_either_side" on public.meetings;
create policy "meetings_insert_either_side"
  on public.meetings for insert
  to authenticated
  with check (
    exists (
      select 1 from public.witness_pairings wp
      where wp.runner_id  = meetings.runner_id
        and wp.witness_id = meetings.witness_id
        and wp.status = 'active'
    )
    and (
      (proposed_by = 'runner'  and runner_id  = auth.uid())
      or (proposed_by = 'witness' and witness_id = auth.uid())
    )
  );

-- Responding to a meeting only ever changes its status.
revoke update on public.meetings from authenticated;
grant  update (status) on public.meetings to authenticated;


-- -----------------------------------------------------------------------------
-- 8. redeem_church_code — the only way to set church_id now, so make it strict
-- -----------------------------------------------------------------------------
-- 006's version let a Runner who was already affiliated redeem further codes
-- (switching churches and duplicating DNA rhythms). Everything else unchanged.
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
    select title, category, frequency
    from public.dna_rhythms
    where church_id = v_church_id
  loop
    insert into public.rule_items (runner_id, category, title, frequency, is_church_mandated)
    values (auth.uid(), v_rhythm.category, v_rhythm.title, v_rhythm.frequency, true);
  end loop;

  return true;
end;
$$;

revoke execute on function public.redeem_church_code(text) from public, anon;
grant  execute on function public.redeem_church_code(text) to authenticated;


-- -----------------------------------------------------------------------------
-- 9. Push notification endpoint — shared-secret auth, secret kept in Vault
-- -----------------------------------------------------------------------------
-- The publishable key is shipped in every app binary, so "Authorization:
-- Bearer <publishable key>" authenticated nobody: anyone could POST a forged
-- { event_type, record } to push-notification-engine and push arbitrary text
-- to any profile id. The Edge Function now requires an
-- `x-trellis-webhook-secret` header equal to its PUSH_ENGINE_WEBHOOK_SECRET
-- env secret (deploy with --no-verify-jwt, like revenuecat-webhook), and this
-- trigger function reads the same value from Supabase Vault — the secret never
-- lives in the repo or in the client.
--
-- Two behavioral improvements while here:
--   * If the Vault secret isn't set yet, push is skipped with a WARNING instead
--     of failing (and rolling back) the user's actual insert.
--   * A pg_net error can never roll back a check-in / meeting / unlock request.
create or replace function public.notify_push_engine()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret text;
begin
  select decrypted_secret
    into v_secret
    from vault.decrypted_secrets
   where name = 'push_engine_webhook_secret'
   limit 1;

  if v_secret is null then
    raise warning 'notify_push_engine: Vault secret push_engine_webhook_secret is not set; skipping push for %.%', TG_TABLE_NAME, TG_ARGV[0];
    return new;
  end if;

  perform net.http_post(
    url := 'https://qonsiliimbkcjmcnhonb.supabase.co/functions/v1/push-notification-engine',
    body := jsonb_build_object(
      'event_type', TG_ARGV[0],
      'table', TG_TABLE_NAME,
      'record', to_jsonb(NEW)
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-trellis-webhook-secret', v_secret
    ),
    timeout_milliseconds := 5000
  );
  return new;
exception when others then
  raise warning 'notify_push_engine failed for %.%: % (SQLSTATE %)', TG_TABLE_NAME, TG_ARGV[0], sqlerrm, sqlstate;
  return new;
end;
$$;


-- =============================================================================
-- Deployment checklist (not SQL — nothing below runs)
-- =============================================================================
-- 1. Generate one long random secret (e.g. `openssl rand -hex 32`) and store it
--    in BOTH places:
--      -- SQL editor (Vault):
--      select vault.create_secret('<the secret>', 'push_engine_webhook_secret');
--      -- shell:
--      supabase secrets set PUSH_ENGINE_WEBHOOK_SECRET='<the secret>'
--    To rotate later: vault.update_secret(...) + `supabase secrets set ...`.
--
-- 2. Redeploy both functions (the engine now authenticates via the secret, so
--    JWT verification is switched off for it, same as revenuecat-webhook):
--      supabase functions deploy push-notification-engine --no-verify-jwt
--      supabase functions deploy delete-account
--
-- 3. Ship the Flutter companion change (see header) BEFORE or WITH this
--    migration; existing builds can't load a profile afterwards.
--
-- 4. BETA_QA_SCRIPT.md step 1a / 3b relied on PATCHing rule_items.
--    is_church_mandated from a client JWT — that is now (correctly) rejected.
--    Set it via the SQL editor / service role instead.
--
-- Verification — run in the SQL editor, simulating a signed-in client
-- (replace the uuid with a real test user's id; all of these must FAIL):
--
--   begin;
--   set local role authenticated;
--   select set_config('request.jwt.claims',
--     '{"sub":"<test-user-uuid>","role":"authenticated"}', true);
--
--   update public.profiles set cloud_admin_church_id = (select id from public.churches limit 1) where id = auth.uid();   -- permission denied
--   update public.profiles set membership_status = 'active' where id = auth.uid();                                       -- permission denied
--   select fcm_token from public.profiles where id = auth.uid();                                                          -- permission denied
--   insert into public.witness_pairings (runner_id, witness_id) values ('<other-uuid>', auth.uid());                      -- permission denied
--   update public.rule_items set is_church_mandated = false where runner_id = auth.uid();                                 -- permission denied
--   delete from public.rule_items where runner_id = auth.uid() and is_church_mandated;                                    -- 0 rows
--   select * from public.churches;                                                                                        -- own church only
--   rollback;
--
--   And these must still SUCCEED: update profiles set name/home_address/
--   fcm_token on own row; select home_address from get_my_private_profile();
--   redeem_pairing_code / redeem_church_code / redeem_cloud_access_code with a
--   valid code; update witness_pairings set status='removed' (unlocked Runner).
-- =============================================================================
