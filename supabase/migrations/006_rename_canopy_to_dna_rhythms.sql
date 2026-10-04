-- =============================================================================
-- 006 — Rename "Canopy Rhythms" to "DNA Rhythms" (canopy_rhythm.dart ->
-- dna_rhythm.dart). Cosmetic rename only, no behavior change: the table,
-- its index, its RLS policies, and the two functions that reference it all
-- move from canopy_rhythms -> dna_rhythms so the schema matches the Flutter
-- client's DnaRhythm model.
-- =============================================================================

alter table public.canopy_rhythms rename to dna_rhythms;

alter index public.canopy_rhythms_church_idx rename to dna_rhythms_church_idx;

alter policy "canopy_rhythms_select_own_church"
  on public.dna_rhythms rename to "dna_rhythms_select_own_church";

alter policy "canopy_rhythms_write_own_church_admin"
  on public.dna_rhythms rename to "dna_rhythms_write_own_church_admin";

alter policy "canopy_rhythms_update_own_church_admin"
  on public.dna_rhythms rename to "dna_rhythms_update_own_church_admin";

alter policy "canopy_rhythms_delete_own_church_admin"
  on public.dna_rhythms rename to "dna_rhythms_delete_own_church_admin";


-- Mirrors RunnerProfile.redeemChurchCode: validates + marks a code
-- redeemed, locks the caller's church affiliation, and injects that
-- church's DNA Rhythms into the caller's Rule of Life as real,
-- church-mandated (never personal-anchor) rows — all in one transaction, so
-- a client never needs UPDATE rights on church_codes directly.
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


-- Mirrors cloud_insights_screen.dart's kAnonymityThreshold exactly: below 15
-- actively-tracked Runners, per-rhythm aggregates could be reverse-engineered
-- back to an individual, so nothing but the locked-state count is returned.
--
-- SECURITY DEFINER is what makes this safe to expose at all: it's the one
-- sanctioned path that reads across every Runner's check_ins in a church,
-- bypassing check_ins' own RLS internally — but only ever returns an
-- aggregate (title + rounded completion rate), never a raw row, and only
-- once the k=15 floor is met. Raw check-in rows stay exactly as
-- inaccessible to a Cloud Admin as check_ins' RLS policies say.
create or replace function public.get_congregational_health(p_church_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_threshold          constant integer := 15;
  v_tracked_runner_count integer;
  v_metrics            jsonb;
begin
  if not public.is_cloud_admin_of_church(p_church_id) then
    raise exception 'Not authorized to view Congregational Health for this church.';
  end if;

  -- "Actively tracking" = at least one real check-in in the trailing 30
  -- days, same window the metrics themselves are computed over.
  select count(distinct ci.runner_id)
    into v_tracked_runner_count
    from public.check_ins ci
    join public.profiles p on p.id = ci.runner_id
   where p.church_id = p_church_id
     and ci.check_in_date >= (current_date - interval '30 days');

  if v_tracked_runner_count < v_threshold then
    return jsonb_build_object(
      'is_locked', true,
      'tracked_runner_count', v_tracked_runner_count,
      'threshold', v_threshold,
      'metrics', '[]'::jsonb
    );
  end if;

  select coalesce(jsonb_agg(
           jsonb_build_object(
             'title', m.title,
             'completion_rate', m.completion_rate,
             'is_dna_rhythm', m.is_dna_rhythm
           )
           order by m.is_dna_rhythm desc, m.completion_rate asc
         ), '[]'::jsonb)
    into v_metrics
    from (
      select
        ri.title,
        round(avg(case when ci.answered_yes then 1 else 0 end)::numeric, 4) as completion_rate,
        bool_or(cr.id is not null) as is_dna_rhythm
      from public.check_ins ci
      join public.rule_items ri on ri.id = ci.rule_item_id
      join public.profiles p on p.id = ci.runner_id
      left join public.dna_rhythms cr
        on cr.church_id = p_church_id and cr.title = ri.title
      where p.church_id = p_church_id
        and ci.check_in_date >= (current_date - interval '30 days')
      group by ri.title
    ) m;

  return jsonb_build_object(
    'is_locked', false,
    'tracked_runner_count', v_tracked_runner_count,
    'threshold', v_threshold,
    'metrics', v_metrics
  );
end;
$$;
