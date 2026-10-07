-- =============================================================================
-- The Trellis — 029_membership_gate.sql   (two free weeks, then a membership)
-- =============================================================================
-- Run AFTER 027 (it uses 014's _secure_code and 020's edge_rate_limit_hit;
-- it does not depend on 028). Idempotent — safe to run more than once.
--
-- THE SWITCH IS OFF. Running this file changes nothing anyone sees: nobody is
-- ever asked to pay until someone runs, at launch,
--     update public.app_settings set enforce_membership = true;
-- (see section G). The beta never asks anyone for payment.
--
-- What this file does, in plain English:
--
--   The pricing model: every account gets two free weeks from sign-up to build
--   a Rule of Life and try being a Runner — no card. After that a RUNNER keeps
--   going with ONE of:
--     * an annual subscription in the App Store ($12/yr; RevenueCat ->
--       revenuecat-webhook -> membership_status = 'active'),
--     * a code from their church or organization (church seats bought at
--       unhinderedlives.com/trellis: redeem_church_code makes them a church
--       member, redeem_enterprise_church_code sets membership_status 'active'),
--     * a gift code someone bought for them on the website (NEW, section D).
--   Witnesses always use the app free, and the Cloud (church admin) is never
--   gated. The database cannot know which view the app has open, so the
--   CLIENT applies the gate, and only to the Runner view; this file only
--   answers "would this person's Runner view be gated?".
--
--   A. public.app_settings — one row, the launch switch (enforce_membership,
--      default FALSE) and the trial length (trial_days, default 14). Readable
--      by signed-in users; writable only from the SQL editor / service role.
--
--   B. profiles.trial_ends_at — set for every new account (created_at +
--      trial_days) by a BEFORE INSERT trigger of its own; existing accounts
--      are backfilled to created_at + 14 days. Readable by the client, never
--      writable by it.
--
--   C. profiles.membership_paid_until (gift time) and
--      profiles.membership_via_gift (whether 'active' was set BY a gift, so
--      that an expired gift stops counting while a store subscription or a
--      church code that later sets 'active' keeps counting). Neither is
--      readable or writable by a client directly; my_membership() reports
--      them.
--
--   D. Gift codes: public.gift_codes (no client access at all),
--      redeem_gift_code(code) for the signed-in user, and
--      issue_gift_codes(quantity, months, email) for the website's Edge
--      Function (service role only — supabase/functions/issue-gift-code).
--
--   E. my_membership() — the ONE answer the app reads:
--        {status, trial_ends_at, paid_until, enforce, needs_membership,
--         church_member, now}
--
--   F. Grants, all in one place.
--
--   G. Launch steps + verification queries (bottom of the file).
--
-- WHO COUNTS AS COVERED (never gated), in my_membership():
--     membership_status = 'active' and not membership_via_gift
--         -- a store subscription or an enterprise church code
--   or membership_paid_until > now()
--         -- unexpired gift time (whatever the status says, so a lapsed store
--         -- subscription doesn't swallow gift months still owed)
--   or church_id is not null
--         -- a member of a church, which holds a seat for them
--   Everyone else is covered by the free trial until trial_ends_at.
--
-- WHY membership_via_gift: a gift sets membership_status = 'active' (so the
-- app's existing "membership is active" wording is right), but a gift ends.
-- Without a marker, "status active, gift time over" would be indistinguishable
-- from "status active because the App Store renewed it". The marker is set
-- only by redeem_gift_code, and cleared by a trigger (C.4) whenever anything
-- else writes membership_status (the RevenueCat webhook on every purchase,
-- renewal or expiry; redeem_enterprise_church_code) — so neither of those
-- needed to change.
--
-- WHY redeem_gift_code RETURNS {ok:false} RATHER THAN RAISING for a wrong
-- code: a raised error rolls back the whole call, including the attempt it
-- just counted against the rate limit, so a guesser would never be limited.
-- It still raises for "not signed in" (28000).
--
-- RE-RUNNING OLDER FILES: nothing here is re-created by an earlier file. The
-- trial date is set by its own trigger (B.2), not by handle_new_user (021 A),
-- so a re-run of 021 cannot drop it; the profiles guard for the new columns is
-- its own trigger (C.3), the same reasoning as 021 B, 025 B, 026 A.3, 027 A.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- A. app_settings — the launch switch
-- -----------------------------------------------------------------------------
create table if not exists public.app_settings (
  id                 boolean     primary key default true check (id),
  enforce_membership boolean     not null default false,
  trial_days         integer     not null default 14 check (trial_days between 0 and 365),
  updated_at         timestamptz not null default now()
);

comment on table public.app_settings is
  'One row (id = true). enforce_membership is the launch switch for the Runner '
  'membership gate (029): false = nobody is ever asked to pay. trial_days is the '
  'free trial a NEW account gets. Clients may read it; only the SQL editor / '
  'service role may change it.';

-- The single row, switched OFF. "do nothing" on re-run: never flips a switch
-- someone has already turned on.
insert into public.app_settings (id, enforce_membership, trial_days)
values (true, false, 14)
on conflict (id) do nothing;

create or replace function public.touch_app_settings()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists app_settings_touch on public.app_settings;
create trigger app_settings_touch
  before update on public.app_settings
  for each row execute function public.touch_app_settings();

alter table public.app_settings enable row level security;

drop policy if exists "app_settings_read" on public.app_settings;
create policy "app_settings_read"
  on public.app_settings for select
  to authenticated
  using (true);


-- -----------------------------------------------------------------------------
-- B. profiles.trial_ends_at
-- -----------------------------------------------------------------------------
-- B.1  The column, and the backfill: every existing account's two weeks run
--      from when it was created (most beta accounts' trials are therefore
--      already over — harmless while the switch is off; see G.2 for giving
--      testers a fresh two weeks at launch).
alter table public.profiles
  add column if not exists trial_ends_at timestamptz;

comment on column public.profiles.trial_ends_at is
  'End of this account''s free Runner trial. Set on sign-up to created_at + '
  'app_settings.trial_days by profiles_set_trial_end (029 B.2). Read by '
  'my_membership(); never written by a client.';

update public.profiles
   set trial_ends_at = created_at + interval '14 days'
 where trial_ends_at is null;

-- B.2  New accounts. A BEFORE INSERT trigger of its own rather than an edit to
--      handle_new_user (021 A): it touches nothing that already works, and a
--      re-run of 021 (or of 011) cannot silently undo it. It runs for every
--      insert into profiles — in practice only handle_new_user inserts — and
--      never overrides a date that was given explicitly.
create or replace function public.set_profile_trial_end()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_days integer;
begin
  if new.trial_ends_at is null then
    begin
      select s.trial_days into v_days from public.app_settings s where s.id;
    exception when others then
      v_days := null;   -- a trial length must never be the reason a sign-up fails
    end;
    new.trial_ends_at :=
      coalesce(new.created_at, now()) + make_interval(days => coalesce(v_days, 14));
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_set_trial_end on public.profiles;
create trigger profiles_set_trial_end
  before insert on public.profiles
  for each row execute function public.set_profile_trial_end();


-- -----------------------------------------------------------------------------
-- C. Gift time on profiles
-- -----------------------------------------------------------------------------
-- C.1  The columns.
alter table public.profiles
  add column if not exists membership_paid_until timestamptz;

alter table public.profiles
  add column if not exists membership_via_gift boolean not null default false;

comment on column public.profiles.membership_paid_until is
  'Gift-code membership time: covered until this instant (null = no gift). '
  'Written only by redeem_gift_code(); reported by my_membership().';

comment on column public.profiles.membership_via_gift is
  'True when membership_status = ''active'' was set by redeem_gift_code(), so '
  'it lapses with membership_paid_until. Cleared automatically (029 C.4) '
  'whenever anything else writes membership_status.';

-- C.2  (Grants: section F. trial_ends_at is readable; these two are not — the
--      app reads them through my_membership(). None of the three is writable.)

-- C.3  Layer 2 for the missing UPDATE grants (the two-layer rule from 011): an
--      invoker-rights trigger of its own, like 026's guard_presence_update.
--      The functions in this file run as their owner, so it never gets in
--      their way.
create or replace function public.guard_membership_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.trial_ends_at            is distinct from old.trial_ends_at
       or new.membership_paid_until is distinct from old.membership_paid_until
       or new.membership_via_gift   is distinct from old.membership_via_gift then
      raise exception 'That profile field can only be changed by The Trellis itself.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_guard_membership on public.profiles;
create trigger profiles_guard_membership
  before update on public.profiles
  for each row execute function public.guard_membership_update();

-- C.4  Any write of membership_status by anyone but redeem_gift_code means the
--      status now comes from somewhere else (the RevenueCat webhook, an
--      enterprise church code), so it no longer lapses with the gift.
--      "update of membership_status" fires whenever that column is in the
--      UPDATE's SET list — including a RENEWAL that writes 'active' over
--      'active' — which is exactly what is wanted. redeem_gift_code sets the
--      marker in a separate statement AFTER its status write (section D).
create or replace function public.clear_membership_via_gift()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.membership_via_gift := false;
  return new;
end;
$$;

drop trigger if exists profiles_membership_source on public.profiles;
create trigger profiles_membership_source
  before update of membership_status on public.profiles
  for each row execute function public.clear_membership_via_gift();


-- -----------------------------------------------------------------------------
-- D. Gift codes
-- -----------------------------------------------------------------------------
-- D.1  The table. Codes are 10 characters from 014's look-alike-free alphabet
--      (no 0/O/1/I), e.g. 7KQ3MX9ZPA; the website may print them with a dash
--      (7KQ3M-X9ZPA) — redemption ignores case, spaces and dashes.
create table if not exists public.gift_codes (
  code            text        primary key check (code ~ '^[A-Z2-9]{10}$'),
  months          integer     not null default 12 check (months between 1 and 120),
  purchaser_email text        check (purchaser_email is null or length(purchaser_email) <= 320),
  created_at      timestamptz not null default now(),
  redeemed_by     uuid        references public.profiles (id) on delete set null,
  redeemed_at     timestamptz
);

comment on table public.gift_codes is
  'Gift memberships sold on unhinderedlives.com. Single use: redeemed_at is set '
  'once and never cleared (redeemed_by goes null if that account is deleted; '
  'the code stays spent). No client access at all — issued by '
  'issue_gift_codes() (service role, via the issue-gift-code Edge Function), '
  'redeemed by redeem_gift_code().';

create index if not exists gift_codes_redeemed_by_idx on public.gift_codes (redeemed_by);

alter table public.gift_codes enable row level security;
-- (No policies: RLS on with none = no rows for any client, even if a grant is
--  ever added by mistake. The service role bypasses RLS.)

-- D.2  Website: mint codes. Service role only.
create or replace function public.issue_gift_codes(
  p_quantity        integer,
  p_months          integer default 12,
  p_purchaser_email text    default null
)
returns setof text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := nullif(btrim(coalesce(p_purchaser_email, '')), '');
  v_code  text;
  i       integer;
begin
  if p_quantity is null or p_quantity < 1 or p_quantity > 20 then
    raise exception 'quantity must be between 1 and 20.' using errcode = '22023';
  end if;
  if p_months is null or p_months < 1 or p_months > 120 then
    raise exception 'months must be between 1 and 120.' using errcode = '22023';
  end if;
  if v_email is not null and length(v_email) > 320 then
    raise exception 'purchaser_email is too long.' using errcode = '22023';
  end if;

  for i in 1 .. p_quantity loop
    -- 32^10 possible codes: a collision is astronomically unlikely, but retry
    -- rather than fail if one ever happens.
    loop
      v_code := public._secure_code(10);
      insert into public.gift_codes (code, months, purchaser_email)
      values (v_code, p_months, v_email)
      on conflict (code) do nothing;
      exit when found;
    end loop;
    return next v_code;
  end loop;
  return;
end;
$$;

-- D.3  App: redeem a code for the signed-in account.
--      Returns {"ok": true,  "paid_until": "<timestamptz>"}
--           or {"ok": false, "reason": "not_recognized", "error": "<sentence>"}
--           or {"ok": false, "reason": "rate_limited",   "error": "<sentence>",
--               "retry_after_seconds": n}
--      Raises 28000 when not signed in. At most 10 attempts per account per
--      hour (020's shared counter, key 'redeem-gift-code:<uuid>').
create or replace function public.redeem_gift_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_code       text;
  v_months     integer;
  v_allowed    boolean;
  v_retry      integer;
  v_profile    public.profiles%rowtype;
  v_paid_until timestamptz;
begin
  if v_uid is null then
    raise exception 'Sign in to redeem a gift code.' using errcode = '28000';
  end if;

  -- Count the attempt first, and keep it: everything below RETURNS rather
  -- than raising, so the count is never rolled back.
  select r.allowed, r.retry_after_seconds
    into v_allowed, v_retry
    from public.edge_rate_limit_hit('redeem-gift-code:' || v_uid::text, 10, 3600) r;
  if not coalesce(v_allowed, false) then
    return jsonb_build_object(
      'ok', false,
      'reason', 'rate_limited',
      'retry_after_seconds', coalesce(v_retry, 3600),
      'error', 'Too many tries for now. Please wait a while and try again.'
    );
  end if;

  v_code := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));

  -- Claim it atomically: two people racing for the same code cannot both win.
  update public.gift_codes
     set redeemed_by = v_uid, redeemed_at = now()
   where code = v_code
     and redeemed_at is null
  returning months into v_months;

  if v_months is null then
    return jsonb_build_object(
      'ok', false,
      'reason', 'not_recognized',
      'error', 'That code wasn''t recognized or has already been used.'
    );
  end if;

  select * into v_profile from public.profiles where id = v_uid for update;

  -- Gift time stacks: it starts from whichever is later, now or the end of
  -- any gift time still left.
  v_paid_until := greatest(coalesce(v_profile.membership_paid_until, now()), now())
                  + make_interval(months => v_months);

  if v_profile.membership_status = 'active' and not v_profile.membership_via_gift then
    -- Already active from the App Store or a church code: leave that alone
    -- and simply bank the gift time (it counts once the other one lapses).
    update public.profiles
       set membership_paid_until = v_paid_until
     where id = v_uid;
  else
    update public.profiles
       set membership_status = 'active',
           membership_paid_until = v_paid_until
     where id = v_uid;
    -- Separate statement, AFTER the status write: C.4 clears the marker on
    -- every status write, including the one just above.
    update public.profiles
       set membership_via_gift = true
     where id = v_uid;
  end if;

  return jsonb_build_object('ok', true, 'paid_until', v_paid_until);
end;
$$;


-- -----------------------------------------------------------------------------
-- E. my_membership() — the one answer the app reads
-- -----------------------------------------------------------------------------
-- {
--   "status":           "trial" | "active" | "cancelled",
--   "trial_ends_at":    timestamptz,
--   "paid_until":       timestamptz | null,   -- gift time
--   "enforce":          boolean,              -- app_settings.enforce_membership
--   "needs_membership": boolean,              -- see below
--   "church_member":    boolean,
--   "now":              timestamptz           -- the server's clock
-- }
-- needs_membership = enforce AND not covered (see the header) AND the free
-- trial is over. It describes the RUNNER view only: the app never gates the
-- Witness view (witnessing is always free) or the Cloud. With the switch off
-- it is always false.
create or replace function public.my_membership()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_profile   public.profiles%rowtype;
  v_enforce   boolean;
  v_days      integer;
  v_trial_end timestamptz;
  v_church    boolean;
  v_covered   boolean;
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = '28000';
  end if;

  select * into v_profile from public.profiles where id = v_uid;
  if v_profile.id is null then
    raise exception 'No profile for this account.' using errcode = 'P0002';
  end if;

  select s.enforce_membership, s.trial_days
    into v_enforce, v_days
    from public.app_settings s
   where s.id;
  v_enforce := coalesce(v_enforce, false);

  v_trial_end := coalesce(
    v_profile.trial_ends_at,
    v_profile.created_at + make_interval(days => coalesce(v_days, 14))
  );
  v_church := v_profile.church_id is not null;
  v_covered :=
       (v_profile.membership_status = 'active' and not v_profile.membership_via_gift)
    or coalesce(v_profile.membership_paid_until > now(), false)
    or v_church;

  return jsonb_build_object(
    'status',           v_profile.membership_status::text,
    'trial_ends_at',    v_trial_end,
    'paid_until',       v_profile.membership_paid_until,
    'enforce',          v_enforce,
    'needs_membership', v_enforce and not v_covered and now() >= v_trial_end,
    'church_member',    v_church,
    'now',              now()
  );
end;
$$;


-- -----------------------------------------------------------------------------
-- F. Grants, all in one place
-- -----------------------------------------------------------------------------
-- app_settings: read for signed-in users, nothing else for clients.
revoke all on public.app_settings from public, anon, authenticated;
grant  select on public.app_settings to authenticated;
grant  select, insert, update, delete on public.app_settings to service_role;

-- gift_codes: no client access at all.
revoke all on public.gift_codes from public, anon, authenticated;
grant  select, insert, update, delete on public.gift_codes to service_role;

-- profiles: 011 grants column by column, so new columns are invisible until
-- granted. trial_ends_at: read yes, write no (the same shape as
-- rule_committed_at, 021 B). membership_paid_until / membership_via_gift: not
-- granted at all — my_membership() reports them.
grant select (trial_ends_at) on public.profiles to authenticated;

-- Trigger functions cannot be called directly; they fire inside the writer's
-- own statement (same reasoning as guard_presence_update, 026 A.3).
revoke execute on function public.guard_membership_update()   from public, anon;
grant  execute on function public.guard_membership_update()   to authenticated, service_role;
revoke execute on function public.clear_membership_via_gift() from public, anon;
grant  execute on function public.clear_membership_via_gift() to authenticated, service_role;
revoke execute on function public.set_profile_trial_end()     from public, anon, authenticated;
revoke execute on function public.touch_app_settings()        from public, anon, authenticated;

-- RPCs.
revoke execute on function public.my_membership()              from public, anon;
grant  execute on function public.my_membership()              to authenticated;
revoke execute on function public.redeem_gift_code(text)       from public, anon;
grant  execute on function public.redeem_gift_code(text)       to authenticated;
revoke execute on function public.issue_gift_codes(integer, integer, text)
  from public, anon, authenticated;
grant  execute on function public.issue_gift_codes(integer, integer, text) to service_role;


-- =============================================================================
-- G. LAUNCH — and verification (SQL editor; compare with "expect")
-- =============================================================================
-- G.1  THE SWITCH. At launch (and not before), run:
--        update public.app_settings set enforce_membership = true;
--      To turn it off again:
--        update public.app_settings set enforce_membership = false;
--      The app reads it at sign-in / launch, so it takes effect the next time
--      each person opens the app.
--
-- G.2  Beta testers' trials ran from their sign-up dates, so most are already
--      over. To give everyone at least two fresh weeks from launch day, run
--      this BEFORE (or together with) G.1:
--        update profiles set trial_ends_at = now() + interval '14 days' where trial_ends_at < now() + interval '14 days';
--
-- G.3  Also before launch (not SQL): remove the App Store introductory free
--      trial from the $12/yr product, so a Runner is not offered two trials
--      (the webhook records an App Store trial as status 'trial', which this
--      gate does not count as a membership). Set GIFT_CODE_SECRET and deploy
--      issue-gift-code (see docs/gift-codes-for-website.md).
--
-- 1. The switch is off and readable:
--   select * from public.app_settings;                     -- expect one row, enforce_membership = false, trial_days = 14
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<any-user-uuid>","role":"authenticated"}', true);
--   select enforce_membership from public.app_settings;    -- expect false
--   update public.app_settings set enforce_membership = true;   -- expect ERROR 42501 permission denied
--   rollback;
--
-- 2. Every profile has a trial end, and new sign-ups get one:
--   select count(*) from public.profiles where trial_ends_at is null;   -- expect 0
--   select tgname from pg_trigger where tgrelid = 'public.profiles'::regclass
--    and tgname in ('profiles_set_trial_end','profiles_guard_membership','profiles_membership_source');
--                                                         -- expect all three
--
-- 3. my_membership() with the switch off — never gated:
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   select public.my_membership();                         -- expect "enforce": false, "needs_membership": false
--   rollback;
--
-- 4. The gate, end to end, without touching the real switch (rolls back):
--   begin;
--   update public.app_settings set enforce_membership = true;
--   update public.profiles set trial_ends_at = now() - interval '1 day',
--          membership_status = 'trial', church_id = null
--    where id = '<test-runner-uuid>';
--   select * from public.issue_gift_codes(1, 12, 'test@example.com');      -- note the code
--   set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<test-runner-uuid>","role":"authenticated"}', true);
--   select public.my_membership();                         -- expect "needs_membership": true
--   select public.redeem_gift_code('nope');                -- expect {"ok": false, "reason": "not_recognized", ...}
--   select public.redeem_gift_code(lower('<code>'));       -- expect {"ok": true, "paid_until": <about a year out>}
--   select public.redeem_gift_code('<code>');              -- expect {"ok": false, "reason": "not_recognized", ...}  (single use)
--   select public.my_membership();                         -- expect "status": "active", "needs_membership": false
--   reset role;
--   -- a gift that has run out lapses:
--   update public.profiles set membership_paid_until = now() - interval '1 day' where id = '<test-runner-uuid>';
--   set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<test-runner-uuid>","role":"authenticated"}', true);
--   select public.my_membership();                         -- expect "needs_membership": true
--   reset role;
--   -- ...but a store purchase after it counts (what the webhook writes):
--   update public.profiles set membership_status = 'active' where id = '<test-runner-uuid>';
--   select membership_via_gift from public.profiles where id = '<test-runner-uuid>';   -- expect false
--   rollback;
--
-- 5. Rate limit — the 11th try in an hour is refused (rolls back):
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   select public.redeem_gift_code('AAAAAAAAAA') from generate_series(1, 11);
--                                                          -- expect 10 x not_recognized, then rate_limited
--   rollback;
--
-- 6. Refusals (each rolls back):
--    a. A client cannot read or write gift codes (expect ERROR 42501 permission denied):
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   select * from public.gift_codes;
--   rollback;
--    b. A client cannot mint codes (expect ERROR 42501 permission denied):
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   select public.issue_gift_codes(1, 12, null);
--   rollback;
--    c. A client cannot extend its own trial or gift time (expect ERROR 42501 permission denied):
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   update public.profiles set trial_ends_at = now() + interval '1 year' where id = auth.uid();
--   rollback;
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   update public.profiles set membership_paid_until = now() + interval '1 year' where id = auth.uid();
--   rollback;
--    d. Not signed in (expect ERROR 28000):
--   begin; set local role authenticated;
--   select public.redeem_gift_code('AAAAAAAAAA');
--   rollback;
--    e. Privileges (expect: false, false, true, true, true):
--   select has_function_privilege('authenticated', 'public.issue_gift_codes(integer,integer,text)', 'execute'),
--          has_table_privilege('authenticated', 'public.gift_codes', 'select'),
--          has_function_privilege('service_role', 'public.issue_gift_codes(integer,integer,text)', 'execute'),
--          has_function_privilege('authenticated', 'public.redeem_gift_code(text)', 'execute'),
--          has_function_privilege('authenticated', 'public.my_membership()', 'execute');
-- =============================================================================
