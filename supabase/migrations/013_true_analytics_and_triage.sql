-- =============================================================================
-- The Trellis — 013_true_analytics_and_triage.sql  (Phase 3)
-- =============================================================================
-- One definition of "consistency", computed in the database, used everywhere:
-- the Runner's Trellis and dashboard, a Witness's view of that Runner, the
-- Cloud roster, Congregational Health, and the Cloud triage list. Replaces the
-- client-side generator in rhythm_analytics.dart (a seeded Random() baseline
-- with +/-3% nudges per check-in) and the hardcoded "Needs Attention" cards.
--
-- THE SCORING RULE
--   For each rhythm, over the trailing 180 days ending YESTERDAY:
--     opportunities = every day that rhythm was actually scheduled
--                     (daily: every day; weekly: its weekly_days; monthly: the
--                      1st; annual: Jan 1 — same recurrence as
--                      RuleItem.scheduledFor), counted only from the day the
--                      rhythm was created
--     hits          = opportunities answered "Yes"
--     rate          = hits / opportunities
--   An opportunity with no check-in is a MISS, not a gap — averaging only the
--   answered days would let someone who stops checking in keep a perfect
--   score. The Runner's score is the plain mean of their rhythms' rates
--   (every rhythm weighs the same; a rhythm with no opportunities yet is left
--   out rather than counted as 0).
--
--   One grace rule: the most recent day (yesterday, by the server clock) only
--   counts if it has been answered. The app can only report on "yesterday"
--   starting at the Runner's local midnight, and the server clock (UTC) can
--   be a day ahead of a Runner in the Americas — without this, they'd be
--   marked missing for a day they weren't yet able to report on.
--
--   Anchor streak ("drooping"): consecutive misses on an Anchor Rhythm counted
--   back from its newest countable opportunity, stopping at the first hit.
--   Three or more = drooping, same threshold as the app's three-miss rule.
--
-- PRIVACY: unchanged. A Cloud admin still gets no row-level access to
-- check_ins/rule_items — only the per-person aggregates the roster already
-- showed, and Congregational Health now refuses to show any rhythm that fewer
-- than 15 Runners hold (previously the k=15 floor applied to the church as a
-- whole, so a rhythm only one Runner had still surfaced that Runner's rate).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Internal building blocks (not callable by clients)
-- -----------------------------------------------------------------------------

-- Every scheduled opportunity for a Runner, resolved against their check-ins.
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
    and d.day >= ri.created_at::date
    and case ri.frequency
          when 'daily'   then true
          when 'weekly'  then extract(isodow from d.day)::smallint = any (ri.weekly_days)
          when 'monthly' then extract(day from d.day) = 1
          when 'annual'  then extract(month from d.day) = 1 and extract(day from d.day) = 1
        end;
$$;

-- The 180-day score on its own (cheap enough to call per roster row).
create or replace function public._runner_score(p_runner_id uuid)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select avg(rate)
  from (
    select (count(*) filter (where hit))::numeric / nullif(count(*), 0) as rate
    from public._runner_resolved_days(p_runner_id, 180)
    where countable
    group by rule_item_id
  ) per_rhythm;
$$;

-- The full picture: score, per-rhythm stats, streaks, and chart buckets.
create or replace function public._runner_analytics(p_runner_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_last_day date := current_date - 1;
  v_rhythms  jsonb;
  v_score    numeric;
  v_drooping boolean;
  v_has_data boolean;
begin
  with days as materialized (
    select * from public._runner_resolved_days(p_runner_id, 360)
  ),
  items as (
    select id, title, is_anchor_rhythm, is_church_mandated
    from public.rule_items
    where runner_id = p_runner_id
  ),
  stats as (
    select rule_item_id,
           count(*) filter (where countable and day > v_last_day - 180) as scheduled,
           count(*) filter (where countable and hit and day > v_last_day - 180) as completed
    from days
    group by rule_item_id
  ),
  streak as (
    select rule_item_id, count(*) as misses
    from (
      select rule_item_id,
             bool_or(hit) over (
               partition by rule_item_id
               order by day desc
               rows between unbounded preceding and current row
             ) as seen_hit
      from days
      where countable and day > v_last_day - 180
    ) s
    where not seen_hit
    group by rule_item_id
  ),
  -- Oldest-first arrays of completion rates; null = nothing was scheduled in
  -- that bucket (before the rhythm existed, or a quiet week for a weekly one).
  weekly as (
    select it.id as rule_item_id, array_agg(b.rate order by b.idx desc) as series
    from items it
    cross join lateral (
      select g.idx,
             round((count(d.day) filter (where d.hit))::numeric / nullif(count(d.day), 0), 4) as rate
      from generate_series(0, 7) as g(idx)
      left join days d
        on d.rule_item_id = it.id and d.countable and ((v_last_day - d.day) / 7) = g.idx
      group by g.idx
    ) b
    group by it.id
  ),
  monthly as (
    select it.id as rule_item_id, array_agg(b.rate order by b.idx desc) as series
    from items it
    cross join lateral (
      select g.idx,
             round((count(d.day) filter (where d.hit))::numeric / nullif(count(d.day), 0), 4) as rate
      from generate_series(0, 5) as g(idx)
      left join days d
        on d.rule_item_id = it.id and d.countable and ((v_last_day - d.day) / 30) = g.idx
      group by g.idx
    ) b
    group by it.id
  ),
  quarterly as (
    select it.id as rule_item_id, array_agg(b.rate order by b.idx desc) as series
    from items it
    cross join lateral (
      select g.idx,
             round((count(d.day) filter (where d.hit))::numeric / nullif(count(d.day), 0), 4) as rate
      from generate_series(0, 3) as g(idx)
      left join days d
        on d.rule_item_id = it.id and d.countable and ((v_last_day - d.day) / 90) = g.idx
      group by g.idx
    ) b
    group by it.id
  )
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'rule_item_id', it.id,
             'title', it.title,
             'is_anchor', it.is_anchor_rhythm,
             'is_church_mandated', it.is_church_mandated,
             'scheduled', coalesce(s.scheduled, 0),
             'completed', coalesce(s.completed, 0),
             'completion_rate',
               case when coalesce(s.scheduled, 0) > 0
                    then round(s.completed::numeric / s.scheduled, 4) end,
             'consecutive_misses', coalesce(k.misses, 0),
             'weekly',    coalesce(to_jsonb(w.series), '[]'::jsonb),
             'monthly',   coalesce(to_jsonb(m.series), '[]'::jsonb),
             'quarterly', coalesce(to_jsonb(q.series), '[]'::jsonb)
           )
           order by it.title
         ), '[]'::jsonb)
    into v_rhythms
    from items it
    left join stats s     on s.rule_item_id = it.id
    left join streak k    on k.rule_item_id = it.id
    left join weekly w    on w.rule_item_id = it.id
    left join monthly m   on m.rule_item_id = it.id
    left join quarterly q on q.rule_item_id = it.id;

  select avg((r ->> 'completion_rate')::numeric)
    into v_score
    from jsonb_array_elements(v_rhythms) r
   where r ->> 'completion_rate' is not null;

  select exists (
           select 1 from jsonb_array_elements(v_rhythms) r
            where (r ->> 'is_anchor')::boolean
              and (r ->> 'consecutive_misses')::integer >= 3
         )
    into v_drooping;

  select exists (
           select 1 from public.check_ins
            where runner_id = p_runner_id and check_in_date > v_last_day - 180
         )
    into v_has_data;

  return jsonb_build_object(
    'score', coalesce(round(v_score, 4), 0),
    'has_data', v_has_data,
    'is_drooping', v_drooping,
    'window_days', 180,
    'as_of', v_last_day,
    'rhythms', v_rhythms
  );
end;
$$;

-- Clients never call these directly; only the authorizing wrappers below and
-- owner-rights views do.
revoke execute on function public._runner_resolved_days(uuid, integer) from public, anon, authenticated;
revoke execute on function public._runner_score(uuid)                  from public, anon, authenticated;
revoke execute on function public._runner_analytics(uuid)              from public, anon, authenticated;


-- -----------------------------------------------------------------------------
-- 2. get_runner_analytics — a Runner's own season, or a Witness's view of it
-- -----------------------------------------------------------------------------
-- Omit p_runner_id for your own. A Witness may pass the id of a Runner they
-- are actively paired with — the same people who can already read that
-- Runner's rhythms and check-ins under RLS, so this reveals nothing new.
create or replace function public.get_runner_analytics(p_runner_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_target uuid := coalesce(p_runner_id, auth.uid());
begin
  if auth.uid() is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  if v_target <> auth.uid() and not public.is_witness_of(v_target) then
    raise exception 'Not authorized to view this Runner''s analytics.' using errcode = '42501';
  end if;

  return public._runner_analytics(v_target);
end;
$$;

revoke execute on function public.get_runner_analytics(uuid) from public, anon;
grant  execute on function public.get_runner_analytics(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- 3. get_cloud_triage — who in the church needs a pastoral touch, right now
-- -----------------------------------------------------------------------------
-- Live replacement for the hardcoded "Needs Attention" cards. Everything is
-- derived from the strict score above; thresholds mirror the app's own tiers
-- (below 0.45 is the "struggling" vine).
--
--   struggling     has data AND (score < 0.45 OR an Anchor Rhythm is drooping)
--   isolated       no active Witness, in the church 7+ days
--   dormant        no check-in for 7+ days (or none ever, in the church 7+ days)
--   witness_alerts Witnesses currently walking with a struggling Runner —
--                  contact details only where that pairing carries the
--                  Witness's consent to share them with the church (008)
--
-- Names and an aggregate score only; never a check-in answer.
create or replace function public.get_cloud_triage(p_church_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_struggle_below constant numeric := 0.45;
  v_stale_days     constant integer := 7;
begin
  if not public.is_cloud_admin_of_church(p_church_id) then
    raise exception 'Not authorized to view triage for this church.' using errcode = '42501';
  end if;

  return (
    with members as (
      select p.id, p.name,
             coalesce(cc.redeemed_at, p.created_at)::date as joined_on
      from public.profiles p
      left join lateral (
        select c.redeemed_at
        from public.church_codes c
        where c.redeemed_by = p.id and c.church_id = p_church_id
        order by c.redeemed_at desc
        limit 1
      ) cc on true
      where p.church_id = p_church_id
    ),
    scored as (
      select m.id, m.name, m.joined_on,
             (a.an ->> 'score')::numeric        as score,
             (a.an ->> 'has_data')::boolean     as has_data,
             (a.an ->> 'is_drooping')::boolean  as is_drooping,
             (select max(ci.check_in_date) from public.check_ins ci where ci.runner_id = m.id)
               as last_check_in,
             (select count(*) from public.witness_pairings wp
               where wp.runner_id = m.id and wp.status = 'active') as witness_count
      from members m
      cross join lateral (select public._runner_analytics(m.id) as an) a
    ),
    struggling as (
      select * from scored
      where has_data and (score < v_struggle_below or is_drooping)
    ),
    witness_alerts as (
      select w.id, w.name,
             count(*) as runner_count,
             bool_or(wp.church_data_consent) as consent,
             case when bool_or(wp.church_data_consent) then max(w.phone_number) end as phone_number,
             case when bool_or(wp.church_data_consent) then max(w.email) end as email
      from struggling s
      join public.witness_pairings wp on wp.runner_id = s.id and wp.status = 'active'
      join public.profiles w on w.id = wp.witness_id
      group by w.id, w.name
    )
    select jsonb_build_object(
      'struggling', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'runner_id', s.id, 'name', s.name,
                 'score', round(s.score, 4), 'is_drooping', s.is_drooping
               ) order by s.score, s.name)
        from struggling s
      ), '[]'::jsonb),
      'isolated', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'runner_id', s.id, 'name', s.name,
                 'days_in_church', current_date - s.joined_on
               ) order by s.joined_on, s.name)
        from scored s
        where s.witness_count = 0 and s.joined_on <= current_date - v_stale_days
      ), '[]'::jsonb),
      'dormant', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'runner_id', s.id, 'name', s.name,
                 'days_since_check_in',
                   case when s.last_check_in is null then null
                        else current_date - s.last_check_in end
               ) order by s.last_check_in nulls first, s.name)
        from scored s
        where (s.last_check_in is null and s.joined_on <= current_date - v_stale_days)
           or s.last_check_in < current_date - v_stale_days
      ), '[]'::jsonb),
      'witness_alerts', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'witness_id', a.id, 'name', a.name, 'runner_count', a.runner_count,
                 'consent', a.consent, 'phone_number', a.phone_number, 'email', a.email
               ) order by a.runner_count desc, a.name)
        from witness_alerts a
      ), '[]'::jsonb),
      'thresholds', jsonb_build_object(
        'struggling_below', v_struggle_below,
        'stale_days', v_stale_days
      )
    )
  );
end;
$$;

revoke execute on function public.get_cloud_triage(uuid) from public, anon;
grant  execute on function public.get_cloud_triage(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- 4. Roster: vitality is now the same strict 180-day score
-- -----------------------------------------------------------------------------
-- Same columns, order, scoping and consent gating as 012 — only vitality_score
-- changes (it used to average answered days over 30, so a Runner who stopped
-- checking in kept their last good number).
create or replace view public.church_roster as
select
  p.id                                               as runner_id,
  p.name                                              as runner_name,
  p.church_id,
  (
    select max(ci.check_in_date)
    from public.check_ins ci
    where ci.runner_id = p.id
  )                                                    as last_check_in_date,
  coalesce(public._runner_score(p.id), 0)              as vitality_score,
  coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', w.id,
      'name', w.name,
      'phone_number',
        case when wp.church_data_consent = true then w.phone_number else null end,
      'email',
        case when wp.church_data_consent = true then w.email else null end,
      'consent', wp.church_data_consent
    ))
    from public.witness_pairings wp
    join public.profiles w on w.id = wp.witness_id
    where wp.runner_id = p.id and wp.status = 'active'
  ), '[]'::jsonb)                                      as witnesses,
  p.email                                              as runner_email,
  p.phone_number                                       as runner_phone_number
from public.profiles p
where p.church_id is not null
  and public.is_cloud_admin_of_church(p.church_id);

alter view public.church_roster set (security_invoker = false);

revoke all on public.church_roster from anon;
revoke insert, update, delete on public.church_roster from authenticated;
grant  select on public.church_roster to authenticated;


-- -----------------------------------------------------------------------------
-- 5. Congregational Health: strict scoring + a per-rhythm privacy floor
-- -----------------------------------------------------------------------------
-- Same JSON shape the app already reads. Two changes:
--   * completion_rate counts unanswered scheduled days as misses (last 30 days)
--   * a rhythm appears only if at least `threshold` distinct Runners hold it —
--     the church-wide floor alone let a personal rhythm of one Runner through.
create or replace function public.get_congregational_health(p_church_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_threshold            constant integer := 15;
  v_tracked_runner_count integer;
  v_metrics              jsonb;
begin
  if not public.is_cloud_admin_of_church(p_church_id) then
    raise exception 'Not authorized to view Congregational Health for this church.';
  end if;

  -- "Actively tracking" = at least one real check-in in the trailing 30 days.
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
        round((count(*) filter (where d.hit))::numeric / nullif(count(*), 0), 4) as completion_rate,
        bool_or(cr.id is not null) as is_dna_rhythm
      from public.profiles p
      cross join lateral public._runner_resolved_days(p.id, 30) d
      join public.rule_items ri on ri.id = d.rule_item_id
      left join public.dna_rhythms cr
        on cr.church_id = p_church_id and cr.title = ri.title
      where p.church_id = p_church_id
        and d.countable
      group by ri.title
      having count(distinct ri.runner_id) >= v_threshold
    ) m;

  return jsonb_build_object(
    'is_locked', false,
    'tracked_runner_count', v_tracked_runner_count,
    'threshold', v_threshold,
    'metrics', v_metrics
  );
end;
$$;

revoke execute on function public.get_congregational_health(uuid) from public, anon;
grant  execute on function public.get_congregational_health(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- 6. A weekly rhythm must have days
-- -----------------------------------------------------------------------------
-- A weekly rhythm with no weekly_days is never scheduled, so under the scoring
-- rule it has no opportunities at all and drops out of the average — a way to
-- keep an Anchor Rhythm (or any rhythm) from ever being counted as missed.
-- 012 closed this for church DNA Rhythms; this closes it for everyone's own.
--
-- Legacy rows first: a weekly rhythm saved without days gets the weekday it
-- was created on (the closest thing to the Runner's intent we have), then the
-- rule is enforced for good. (Runs as the migration owner, so the guard
-- triggers on rule_items — which only block client writes — don't interfere.)
update public.rule_items
   set weekly_days = array[extract(isodow from created_at)::smallint]
 where frequency = 'weekly'
   and cardinality(weekly_days) = 0;

alter table public.rule_items
  drop constraint if exists rule_items_weekly_needs_days;
alter table public.rule_items
  add constraint rule_items_weekly_needs_days
  check (frequency <> 'weekly' or cardinality(weekly_days) > 0);


-- =============================================================================
-- Verification (SQL editor, dev branch)
-- =============================================================================
-- 0. select count(*) from rule_items
--     where frequency = 'weekly' and cardinality(weekly_days) = 0;        -- 0
--    update rule_items set weekly_days = '{}' where frequency = 'weekly';  -- ERROR (check constraint)
--
-- 1. Strictness — pick a Runner with a daily rhythm created > 30 days ago and
--    check one day by hand:
--      select * from _runner_resolved_days('<runner-uuid>', 10) order by day;
--    A scheduled day with no check_ins row must show countable = true,
--    hit = false (except the newest day, which is uncountable until answered).
--
-- 2. A Runner who has never checked in has score 0 / has_data false (the app
--    keeps the empty trellis for has_data = false):
--      select public._runner_analytics('<runner-uuid>') -> 'has_data';
--
-- 3. As a signed-in Runner: select get_runner_analytics();      -- own season
--    As their Witness:     select get_runner_analytics('<runner-uuid>');  -- ok
--    As anyone else:       select get_runner_analytics('<runner-uuid>');  -- 42501
--
-- 4. As a Cloud admin: select get_cloud_triage('<church-uuid>');
--    As a non-admin or another church's admin: ERROR 42501.
--
-- 5. Clients can't reach the internals:
--      select public._runner_score('<uuid>');   -- permission denied (as authenticated)
-- =============================================================================
