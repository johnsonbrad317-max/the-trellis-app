-- =============================================================================
-- 008 — Gate the Witness's contact info on church_roster behind consent.
-- =============================================================================
-- 002_grants_and_cloud_access.sql's church_roster (section F) added the
-- Witness's phone_number/email to the `witnesses` jsonb array unconditionally
-- — before 007_witness_church_consent.sql's church_data_consent column
-- existed to check. Now that every witness_pairings row records whether that
-- Witness actually consented to sharing those details with this church, the
-- view has to honor it: a Witness who paired before a Runner had a church
-- (or who was rejected by 007's server-side consent check) must show up on
-- the Roster with a name only, never contact info.
--
-- Runner contact fields (runner_email/runner_phone_number) are untouched —
-- that consent flow is specifically about a Witness sharing their own
-- details with a church they don't belong to, not the Runner's own
-- church-member data.
create or replace view public.church_roster
  with (security_invoker = true)
as
select
  p.id                                               as runner_id,
  p.name                                              as runner_name,
  p.church_id,
  (
    select max(ci.check_in_date)
    from public.check_ins ci
    where ci.runner_id = p.id
  )                                                    as last_check_in_date,
  coalesce((
    select avg(case when ci.answered_yes then 1 else 0 end)
    from public.check_ins ci
    join public.rule_items ri on ri.id = ci.rule_item_id
    where ri.runner_id = p.id
      and ci.check_in_date >= (current_date - interval '30 days')
  ), 0)                                                as vitality_score,
  coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', w.id,
      'name', w.name,
      'phone_number',
        case when wp.church_data_consent = true then w.phone_number else null end,
      'email',
        case when wp.church_data_consent = true then w.email else null end,
      -- Lets the UI show "consent pending" rather than an unexplained
      -- disabled button — distinguishes "hasn't consented" from "consented
      -- but has no phone/email on file", which a bare null can't.
      'consent', wp.church_data_consent
    ))
    from public.witness_pairings wp
    join public.profiles w on w.id = wp.witness_id
    where wp.runner_id = p.id and wp.status = 'active'
  ), '[]'::jsonb)                                      as witnesses,
  p.email                                              as runner_email,
  p.phone_number                                       as runner_phone_number
from public.profiles p
where p.role = 'runner';
