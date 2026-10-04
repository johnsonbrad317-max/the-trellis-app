-- =============================================================================
-- The Trellis — 004_universal_webhooks.sql
-- =============================================================================
-- Wires three of this app's relational loops to the universal
-- push-notification-engine Edge Function (supabase/functions/
-- push-notification-engine/), via one reusable trigger function rather
-- than a Database Webhook created by hand in the Dashboard for each table —
-- run this file, and all three are live.
--
--   - Accountability Unlocks: pending_unlock_requests insert (003)
--   - Grace Nudges:           grace_nudges insert (init_schema.sql's
--                              check_ins_grace_nudge trigger is what
--                              actually decides "3 consecutive misses" and
--                              writes this row — hooking its insert here
--                              avoids re-deriving that logic)
--   - Meeting Proposals:      meetings insert (either side proposing)
--
-- A note on the bearer token below: it's this project's PUBLISHABLE (anon)
-- key, the same one already shipped inside the compiled Flutter app (see
-- lib/services/supabase_client.dart) — not a secret. It only satisfies the
-- platform's "every Edge Function invocation needs a valid JWT" requirement;
-- it grants the request no privilege on its own. All of the engine's actual
-- data access happens through the separate SUPABASE_SERVICE_ROLE_KEY, which
-- the platform injects straight into the function's environment and which
-- never appears in this file, in the Flutter app, or anywhere else.
-- =============================================================================

create extension if not exists pg_net;


-- -----------------------------------------------------------------------------
-- A. One trigger function, parameterized by event_type
-- -----------------------------------------------------------------------------
-- security definer so this runs as the function's owner regardless of
-- which role (Runner or Witness) performed the insert that fired it —
-- same reasoning as every other cross-account action in this app (see the
-- Cloud Access and unlock-approval RPCs/triggers in 002 and 003.
create or replace function public.notify_push_engine()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://qonsiliimbkcjmcnhonb.supabase.co/functions/v1/push-notification-engine',
    body := jsonb_build_object(
      'event_type', TG_ARGV[0],
      'table', TG_TABLE_NAME,
      'record', to_jsonb(NEW)
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer sb_publishable_xFFRtWf7381K4gK9aFlXPQ_sKNaTr8q'
    ),
    timeout_milliseconds := 5000
  );
  return new;
end;
$$;


-- -----------------------------------------------------------------------------
-- B. The three triggers
-- -----------------------------------------------------------------------------
drop trigger if exists notify_push_on_unlock_request on public.pending_unlock_requests;
create trigger notify_push_on_unlock_request
  after insert on public.pending_unlock_requests
  for each row execute function public.notify_push_engine('unlock_request');

drop trigger if exists notify_push_on_grace_nudge on public.grace_nudges;
create trigger notify_push_on_grace_nudge
  after insert on public.grace_nudges
  for each row execute function public.notify_push_engine('grace_nudge');

drop trigger if exists notify_push_on_meeting_proposal on public.meetings;
create trigger notify_push_on_meeting_proposal
  after insert on public.meetings
  for each row execute function public.notify_push_engine('meeting_proposal');


-- -----------------------------------------------------------------------------
-- C. Fix: a Runner couldn't see their own Witness's profile
-- -----------------------------------------------------------------------------
-- init_schema.sql's profiles_select_self_paired_or_roster policy only ever
-- let a WITNESS see their paired RUNNER's profile (via is_witness_of) — the
-- reverse direction was missing, so a Runner's own "Active Witnesses" list
-- (settings_witnesses.dart) and the unlock-request Witness picker
-- (rule_builder_screen.dart) both silently saw an empty witnesses list, no
-- error. Discovered live-testing the unlock-request feature; unrelated to
-- the webhooks above but bundled here so there's still just one file to run.
-- RLS SELECT policies are OR'd together, so this is purely additive.
drop policy if exists "profiles_select_own_witnesses" on public.profiles;
create policy "profiles_select_own_witnesses"
  on public.profiles for select
  to authenticated
  using (
    exists (
      select 1 from public.witness_pairings wp
      where wp.runner_id = auth.uid()
        and wp.witness_id = profiles.id
        and wp.status = 'active'
    )
  );


-- =============================================================================
-- Deployment notes (not SQL — nothing below this line runs in the editor)
-- =============================================================================
-- 1. Deploy the Edge Function:
--      supabase functions deploy push-notification-engine
--    or paste supabase/functions/push-notification-engine/index.ts into
--    Dashboard -> Edge Functions -> New Function if you don't have the CLI.
--
-- 2. Set its secrets (Dashboard -> Edge Functions ->
--    push-notification-engine -> Secrets, or `supabase secrets set`):
--      FCM_PROJECT_ID           your Firebase project ID
--      FCM_SERVICE_ACCOUNT_JSON the full JSON key of a service account with
--                                the "Firebase Cloud Messaging API" role
--    (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically
--    by the platform — you don't set those yourself.) See the separate
--    Firebase setup walkthrough for exactly how to get these two values.
--
-- 3. That's it — no Dashboard webhook to create. Test with, e.g.:
--      insert into pending_unlock_requests (runner_id, witness_id, rule_item_id)
--      values (...);
--    then check the function's logs (Dashboard -> Edge Functions ->
--    push-notification-engine -> Logs) for what it decided to do.
-- =============================================================================
