-- =============================================================================
-- The Trellis — 018_roster_score_permission_and_feedback_grants.sql
-- =============================================================================
-- Two permission fixes found in QA. Idempotent; safe to run more than once.
--
--   A. Cloud Roster: "permission denied for function _runner_score (42501)".
--
--      013 made church_roster an owner-rights view (so a Cloud admin can see
--      aggregate vitality without any row access to check_ins/rule_items), and
--      revoked EXECUTE on the internal _runner_score() from every client role on
--      the assumption the view would call it with the owner's rights. That
--      assumption was wrong for FUNCTIONS: Postgres checks a function's EXECUTE
--      privilege against the user running the query — the view owner's rights
--      cover the tables a view reads, not the functions it calls. So the roster
--      failed for every Cloud admin.
--
--      The obvious fix — just GRANT EXECUTE to authenticated — would be a leak:
--      _runner_score is SECURITY DEFINER, so any signed-in user could call it
--      through the API with ANY runner's id and read that person's consistency
--      score. So the grant ships together with an authorization check INSIDE the
--      function: it answers only for (a) the runner themself, (b) their active
--      Witness, or (c) the Cloud admin of the runner's church — exactly the
--      people who may already see that number — and returns NULL for anyone
--      else. The roster still works (the caller is the church's Cloud admin);
--      a stranger probing the function gets nothing.
--
--   B. Feedback: the submit-feedback Edge Function stores each note in
--      feedback_submissions with the service role. 016 created that table and
--      revoked client access, but never granted the service role access to it.
--      On a project whose default privileges don't auto-grant new public tables
--      to service_role, every insert fails with 42501 and the function answers
--      "Could not record feedback right now."
-- =============================================================================


-- -----------------------------------------------------------------------------
-- A. _runner_score: callable by signed-in users, but only answers for people the
--    caller is entitled to see.
-- -----------------------------------------------------------------------------
create or replace function public._runner_score(p_runner_id uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  -- auth.uid() is null for the service role / SQL editor, which may ask about
  -- anyone. For a signed-in caller, only the runner, their active Witness, or
  -- their church's Cloud admin get an answer.
  if auth.uid() is not null
     and p_runner_id is distinct from auth.uid()
     and not public.is_witness_of(p_runner_id)
     and not public.is_cloud_admin_of_runner(p_runner_id) then
    return null;
  end if;

  return (
    select avg(rate)
    from (
      select (count(*) filter (where hit))::numeric / nullif(count(*), 0) as rate
      from public._runner_resolved_days(p_runner_id, 180)
      where countable
      group by rule_item_id
    ) per_rhythm
  );
end;
$$;

revoke execute on function public._runner_score(uuid) from public, anon;
grant  execute on function public._runner_score(uuid) to authenticated;
-- (service_role keeps its own access. anon and PUBLIC stay locked out.)


-- -----------------------------------------------------------------------------
-- B. feedback_submissions: the Edge Function's service role must be able to use it
-- -----------------------------------------------------------------------------
-- Clients still have no access (016 revoked it and there are no policies); this
-- only gives the service role what it needs.
grant select, insert, update on public.feedback_submissions to service_role;


-- =============================================================================
-- Verification (SQL editor, dev branch)
-- =============================================================================
-- A. Roster — as a Cloud admin of a church that has members:
--      begin;
--      set local role authenticated;
--      select set_config('request.jwt.claims',
--        '{"sub":"<cloud-admin-uuid>","role":"authenticated"}', true);
--      select runner_name, vitality_score from church_roster;   -- rows, no 42501
--      select _runner_score('<a-member-of-that-church>');       -- a number (or null if unscored)
--      rollback;
--
--    As an ordinary user asking about someone they have no relationship to:
--      begin;
--      set local role authenticated;
--      select set_config('request.jwt.claims',
--        '{"sub":"<some-other-user-uuid>","role":"authenticated"}', true);
--      select _runner_score('<a-member-of-that-church>');       -- NULL, not a score
--      select _runner_score(auth.uid());                        -- their own: allowed
--      rollback;
--
--    The internal siblings stay locked to clients:
--      select has_function_privilege('authenticated',
--               'public._runner_analytics(uuid)', 'execute');   -- false
--      select has_function_privilege('anon',
--               'public._runner_score(uuid)', 'execute');       -- false
--
-- B. Feedback:
--      select has_table_privilege('service_role',
--               'public.feedback_submissions', 'insert');       -- true
--      select has_table_privilege('authenticated',
--               'public.feedback_submissions', 'select');       -- false
--      select to_regclass('public.feedback_submissions');       -- not null (016 ran)
-- =============================================================================
