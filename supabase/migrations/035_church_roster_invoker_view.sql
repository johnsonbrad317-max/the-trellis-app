-- =============================================================================
-- The Trellis — 035_church_roster_invoker_view.sql   (clears Supabase's
--                                                      "Security Definer View")
-- =============================================================================
-- Run after 034. Idempotent — safe to run more than once.
--
-- Supabase's Security Advisor flags public.church_roster as CRITICAL: since
-- 012/013 it has been an owner-rights (SECURITY DEFINER) view. It was not
-- leaking — every row is filtered by is_cloud_admin_of_church(), so a church
-- leader only ever sees their own church's members, and only name, contact,
-- one consistency number, last check-in date and consent-gated Witness
-- contact. But a security-definer view is the pattern the advisor exists to
-- catch, because its safety rests on that one WHERE clause.
--
-- Same rows, same columns, done the recommended way:
--
--   A. _church_roster_rows() — a SECURITY DEFINER function holding exactly the
--      013 query. It answers only for the church the caller administers.
--   B. church_roster becomes an ordinary caller-rights view over it
--      (security_invoker = true), so the app — every build, old and new — keeps
--      reading `church_roster` exactly as before.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- A. The rows, behind a function that checks who is asking
-- -----------------------------------------------------------------------------
create or replace function public._church_roster_rows()
returns table (
  runner_id           uuid,
  runner_name         text,
  church_id           uuid,
  last_check_in_date  date,
  vitality_score      numeric,
  witnesses           jsonb,
  runner_email        text,
  runner_phone_number text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.name,
    p.church_id,
    (
      select max(ci.check_in_date)
      from public.check_ins ci
      where ci.runner_id = p.id
    ),
    coalesce(public._runner_score(p.id), 0)::numeric,
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
    ), '[]'::jsonb),
    p.email,
    p.phone_number
  from public.profiles p
  where p.church_id is not null
    and public.is_cloud_admin_of_church(p.church_id);
$$;

comment on function public._church_roster_rows() is
  'The Cloud Roster for the church the caller administers (nothing for anyone '
  'else). Read through the church_roster view.';

revoke execute on function public._church_roster_rows() from public, anon;
grant  execute on function public._church_roster_rows() to authenticated;


-- -----------------------------------------------------------------------------
-- B. The view the app reads, now with the caller's rights
-- -----------------------------------------------------------------------------
-- Dropped and re-created rather than replaced: the columns now come from the
-- function, and nothing else in the database depends on this view.
drop view if exists public.church_roster;

create view public.church_roster
with (security_invoker = true)
as
select runner_id, runner_name, church_id, last_check_in_date, vitality_score,
       witnesses, runner_email, runner_phone_number
  from public._church_roster_rows();

comment on view public.church_roster is
  'Cloud Roster tab (church_roster_entry.dart). Caller-rights view over '
  '_church_roster_rows(), which returns only the caller''s own church.';

revoke all on public.church_roster from public, anon;
grant  select on public.church_roster to authenticated;


-- =============================================================================
-- Checks (by hand, in the SQL editor)
-- =============================================================================
--   select relname, reloptions from pg_class where relname = 'church_roster';
--     -- {security_invoker=true}
--   Then reload Advisors > Security Advisor: the church_roster issue is gone.
--   As a Cloud admin in the app, the Roster tab shows the same people as before.
-- =============================================================================
