-- =============================================================================
-- 007 — Mandatory data-sharing consent gate for Witness pairing
-- (witness_pairing_code_screen.dart).
--
-- Pairing with a Runner who belongs to a church puts the Witness's own name
-- into that church's Cloud Roster (public.church_roster's `witnesses`
-- array — see init_schema.sql section 16), the moment the witness_pairings
-- row exists. A Witness needs to see that ahead of time and explicitly
-- consent before the pairing is created, not discover it after the fact.
-- =============================================================================

-- Persists whether the Witness actually consented, so "verifies this
-- consent" (the backend-enforcement requirement) has a real row to check
-- against rather than trusting the client's one-time claim.
alter table public.witness_pairings
  add column if not exists church_data_consent boolean not null default false;

-- Read-only pre-flight lookup: lets the client show the church name and the
-- consent callout *before* the pairing is finalized, without consuming the
-- code. Same trust level as redeem_pairing_code itself — anyone holding a
-- valid code can already learn the Runner's full identity by redeeming it,
-- so revealing just a church name for an unredeemed code first adds no new
-- exposure.
create or replace function public.check_pairing_code(p_code text)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_runner_id   uuid;
  v_church_id   uuid;
  v_church_name text;
begin
  select runner_id into v_runner_id
    from public.pairing_codes
   where code = upper(trim(p_code)) and not is_redeemed and expires_at > now();

  if v_runner_id is null then
    return jsonb_build_object('valid', false);
  end if;

  select p.church_id, c.name
    into v_church_id, v_church_name
    from public.profiles p
    left join public.churches c on c.id = p.church_id
   where p.id = v_runner_id;

  return jsonb_build_object(
    'valid', true,
    'church_id', v_church_id,
    'church_name', v_church_name
  );
end;
$$;

grant execute on function public.check_pairing_code(text) to authenticated;

-- Mirrors RunnerProfile.redeemPairingCode: now also enforces that a Runner
-- affiliated with a church can't be paired with unless the Witness passed
-- p_consent — the client only does that once the required checkbox
-- (see witness_pairing_code_screen.dart) is ticked, but this function is
-- the actual gate: a client that skips the UI check gets rejected here too.
--
-- The consent check runs after the UPDATE that claims the code but before
-- the witness_pairings INSERT; raising an exception rolls back the whole
-- function call, including that UPDATE, so a rejected attempt leaves the
-- code unredeemed and the Witness can retry with consent instead of the
-- code being silently burned.
--
-- Adding a parameter changes the function's signature, so `create or
-- replace` alone would leave the old 1-argument version callable
-- side-by-side (any client still on it would bypass the consent check
-- entirely) — it has to be dropped explicitly first.
drop function if exists public.redeem_pairing_code(text);

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
  update public.pairing_codes
     set is_redeemed = true, redeemed_by = auth.uid(), redeemed_at = now()
   where code = upper(trim(p_code)) and not is_redeemed and expires_at > now()
   returning runner_id into v_runner_id;

  if v_runner_id is null then
    return false;
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

grant execute on function public.redeem_pairing_code(text, boolean) to authenticated;
