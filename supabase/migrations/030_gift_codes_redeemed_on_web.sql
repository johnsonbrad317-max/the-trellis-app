-- =============================================================================
-- The Trellis — 030_gift_codes_redeemed_on_web.sql   (App Store rule 3.1.1)
-- =============================================================================
-- Run AFTER 029. Idempotent — safe to run more than once.
--
-- Why: Apple does not let an app unlock paid features with "its own
-- mechanisms … such as license keys" (App Review Guideline 3.1.1). A gift code
-- bought on the website and typed into the iPhone app reads exactly like one.
-- What Apple does allow (3.1.3(b), Multiplatform Services) is an account that
-- already has a membership bought on the web, as long as the same membership
-- is also sold in the app ($12/yr). So a gift is now redeemed ON THE WEBSITE,
-- against the recipient's Trellis account email, and the app only ever sees
-- the result: an active membership on the account. The app has no code field.
--
--   A. _apply_gift_months(uid, months) — the stacking logic from 029's
--      redeem_gift_code, shared.
--   B. redeem_gift_code_for_email(code, email) — service role only, called by
--      the redeem-gift-code Edge Function for the website.
--   C. redeem_gift_code(text) — the in-app path — is dropped.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- A. Add gift months to an account (internal)
-- -----------------------------------------------------------------------------
create or replace function public._apply_gift_months(p_uid uuid, p_months integer)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile    public.profiles%rowtype;
  v_paid_until timestamptz;
begin
  select * into v_profile from public.profiles where id = p_uid for update;
  if not found then
    raise exception 'No profile for that account.' using errcode = 'P0002';
  end if;

  -- Gift time stacks: it starts from whichever is later, now or the end of
  -- any gift time still left.
  v_paid_until := greatest(coalesce(v_profile.membership_paid_until, now()), now())
                  + make_interval(months => p_months);

  if v_profile.membership_status = 'active' and not v_profile.membership_via_gift then
    -- Already active from the App Store or a church code: leave that alone
    -- and simply bank the gift time (it counts once the other one lapses).
    update public.profiles
       set membership_paid_until = v_paid_until
     where id = p_uid;
  else
    update public.profiles
       set membership_status = 'active',
           membership_paid_until = v_paid_until
     where id = p_uid;
    -- Separate statement, AFTER the status write: 029's C.4 clears the
    -- marker on every status write, including the one just above.
    update public.profiles
       set membership_via_gift = true
     where id = p_uid;
  end if;

  return v_paid_until;
end;
$$;


-- -----------------------------------------------------------------------------
-- B. Website: redeem a code for the account with this email
-- -----------------------------------------------------------------------------
-- Returns {"ok": true,  "paid_until": "<timestamptz>"}
--      or {"ok": false, "reason": "not_recognized" | "no_account" | "rate_limited"}
-- The code is checked FIRST and is only spent when an account was found, so
-- someone who mistypes their email keeps their code. Only someone holding a
-- valid, unspent code learns whether an email has an account. At most 10
-- attempts per email per hour (020's shared counter).
create or replace function public.redeem_gift_code_for_email(p_code text, p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code       text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_email      text := lower(btrim(coalesce(p_email, '')));
  v_months     integer;
  v_uid        uuid;
  v_allowed    boolean;
  v_retry      integer;
  v_paid_until timestamptz;
begin
  if v_email = '' or length(v_email) > 320 then
    return jsonb_build_object('ok', false, 'reason', 'no_account');
  end if;

  select r.allowed, r.retry_after_seconds
    into v_allowed, v_retry
    from public.edge_rate_limit_hit('redeem-gift-code-web:' || v_email, 10, 3600) r;
  if not coalesce(v_allowed, false) then
    return jsonb_build_object(
      'ok', false, 'reason', 'rate_limited', 'retry_after_seconds', coalesce(v_retry, 3600)
    );
  end if;

  -- Lock the unspent code so two redemptions cannot both win.
  select months into v_months
    from public.gift_codes
   where code = v_code and redeemed_at is null
   for update;
  if v_months is null then
    return jsonb_build_object('ok', false, 'reason', 'not_recognized');
  end if;

  select u.id into v_uid
    from auth.users u
    join public.profiles p on p.id = u.id
   where lower(u.email) = v_email
   limit 1;
  if v_uid is null then
    return jsonb_build_object('ok', false, 'reason', 'no_account');
  end if;

  update public.gift_codes
     set redeemed_by = v_uid, redeemed_at = now()
   where code = v_code;

  v_paid_until := public._apply_gift_months(v_uid, v_months);
  return jsonb_build_object('ok', true, 'paid_until', v_paid_until);
end;
$$;


-- -----------------------------------------------------------------------------
-- C. The in-app redemption path is gone
-- -----------------------------------------------------------------------------
drop function if exists public.redeem_gift_code(text);

comment on table public.gift_codes is
  'Gift memberships sold on unhinderedlives.com. Single use: redeemed_at is set '
  'once and never cleared (redeemed_by goes null if that account is deleted; '
  'the code stays spent). No client access at all — issued by '
  'issue_gift_codes() and redeemed by redeem_gift_code_for_email(), both '
  'service role only, via the issue-gift-code / redeem-gift-code Edge Functions.';


-- -----------------------------------------------------------------------------
-- Grants: none of this is reachable from the app.
-- -----------------------------------------------------------------------------
revoke execute on function public._apply_gift_months(uuid, integer)        from public, anon, authenticated;
grant  execute on function public._apply_gift_months(uuid, integer)        to service_role;
revoke execute on function public.redeem_gift_code_for_email(text, text)   from public, anon, authenticated;
grant  execute on function public.redeem_gift_code_for_email(text, text)   to service_role;


-- =============================================================================
-- Checks (run by hand in the SQL editor; nothing below changes data)
-- =============================================================================
--   select has_function_privilege('authenticated', 'public.redeem_gift_code_for_email(text,text)', 'execute'),  -- false
--          has_function_privilege('service_role',  'public.redeem_gift_code_for_email(text,text)', 'execute'),  -- true
--          to_regprocedure('public.redeem_gift_code(text)');                                                     -- null
--
-- End to end (spends a real code):
--   select * from public.issue_gift_codes(1, 12, 'you@example.com');            -- note the code
--   select public.redeem_gift_code_for_email('<code>', 'nobody@example.com');    -- no_account, code unspent
--   select public.redeem_gift_code_for_email('<code>', '<your Trellis email>');  -- ok
--   select public.redeem_gift_code_for_email('<code>', '<your Trellis email>');  -- not_recognized
-- =============================================================================
