-- =============================================================================
-- The Trellis — 026_witness_nudges.sql   (a Witness hears when a Runner goes silent)
-- =============================================================================
-- Run AFTER 025. Idempotent — safe to run more than once.
--
-- Why: until now a Witness was pushed only when something HAPPENED — a missed
-- Anchor Rhythm in a check-in, a request, the weekly roll-up, a deleted
-- account. A Runner who simply stopped checking in, never set up a Rule of
-- Life, or deleted the app produced no push at all, because the Runner's daily
-- reminders live on their own phone and the server never hears from it. This
-- file gives the server two ways to notice silence.
--
-- What this file does, in plain English:
--
--   A. profiles.last_seen_at — when the person last opened the app — and
--      profiles.app_removed_at — when their phone's push token was reported
--      gone (the app was probably deleted). Clients can read both and write
--      neither.
--
--   B. touch_last_seen() — the app calls it on launch, sign-in and every return
--      to the foreground. Records "seen now" and clears app_removed_at. Cheap:
--      does nothing if it already ran in the last 10 minutes.
--
--   C. Table witness_nudges: one row per (Runner, Witness, kind, episode), so
--      each episode is announced exactly once. Each new row pushes the Witness
--      (push-notification-engine, event `witness_nudge`). No client can read or
--      write it.
--
--   D. generate_witness_nudges() — daily at 15:00 UTC (pg_cron job
--      trellis-witness-nudges) — writes two kinds of rows for every ACTIVE
--      pairing:
--        rule_not_committed  paired 2+ days and still no Rule of Life; once per
--                            week until it is done;
--        quiet               committed, but no check-in for 2+ days while
--                            something was due; once at 2 days and once more at
--                            7 days, per silence.
--
--   E. App removed. Daily at 14:00 UTC (pg_cron job trellis-presence-probe) the
--      push engine is asked to send a silent, data-only push to every Runner
--      not seen for two days. When FCM answers that the token no longer
--      belongs to an installed app, record_app_removed() clears the token,
--      sets app_removed_at and writes an `app_removed` nudge for each of the
--      Runner's Witnesses. NOT INSTANT: Apple reports a deleted app to FCM
--      some hours — sometimes a day or more — after the fact, and the probe
--      only runs daily for Runners quiet for two days, so a Witness hears
--      "may have stepped away" within a few days, not the same minute.
--
--   F. Documents the new notification_preferences key quiet_runner_alerts.
--
--   G. Grants restated for every new function.
--
--   H. Verification queries (bottom of the file).
--
-- ALSO REQUIRED ALONGSIDE THIS FILE (not SQL):
--   * Redeploy the push engine (it learns `witness_nudge` and the
--     `presence_probe` action, and now clears tokens FCM reports as gone):
--       supabase functions deploy push-notification-engine --no-verify-jwt
--   * Sections D.3 and E.4 need pg_cron (021 E.5 needed it too), and E needs
--     pg_net and the Vault secret push_engine_webhook_secret, both already in
--     use by every push trigger since 011. Without pg_cron the rest of this file
--     still applies and the DO blocks print what to do.
--   * The app build that calls touch_last_seen(). Until a Runner runs that
--     build, last_seen_at stays empty and the probe simply checks them daily
--     (a silent push; nothing appears on their phone). Older builds already
--     ignore an unknown data-only message.
--
-- RE-RUNNING OLDER FILES: nothing here is re-created by an earlier file. The
-- profiles guard for the two new columns is its own trigger (A.3) rather than a
-- line in guard_profile_update, because 019 re-creates that guard and a re-run
-- of 019 would silently drop the line (the same reasoning as 021 B and 025 B).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- A. profiles.last_seen_at and profiles.app_removed_at
-- -----------------------------------------------------------------------------
-- A.1  The columns.
alter table public.profiles
  add column if not exists last_seen_at timestamptz;

alter table public.profiles
  add column if not exists app_removed_at timestamptz;

comment on column public.profiles.last_seen_at is
  'When this person last opened the app (launch, sign-in or return to the '
  'foreground), to within about 10 minutes. Written only by touch_last_seen(), '
  'never by a client directly. Null = not seen since 026 (or never).';

comment on column public.profiles.app_removed_at is
  'When push-notification-engine was told by FCM that this person''s device '
  'token is gone — most often because the app was deleted. Set (and fcm_token '
  'cleared) by record_app_removed(); cleared by touch_last_seen() the next time '
  'the app is opened. Never written by a client.';

-- A.2  011 grants profiles column by column, so new columns are invisible until
--      granted. Read yes, write no — the same shape as rule_committed_at (021 B)
--      and calendar_synced_at (025 B). Who can see WHICH rows is unchanged (the
--      person themselves, their Witnesses, their church's Cloud admin).
grant select (last_seen_at, app_removed_at) on public.profiles to authenticated;

-- A.3  Layer 2 for the missing UPDATE grant (the two-layer rule from 011): a
--      small invoker-rights trigger of its own, like 025's
--      guard_calendar_sync_update. touch_last_seen() and record_app_removed()
--      run as the function owner, so this never gets in their way.
create or replace function public.guard_presence_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.last_seen_at   is distinct from old.last_seen_at
       or new.app_removed_at is distinct from old.app_removed_at then
      raise exception 'That profile field can only be changed by The Trellis itself.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

-- (Grants: a trigger function cannot be called directly, and it fires inside
--  the client's own UPDATE — same reasoning as guard_rule_commit in 021 B.)
revoke execute on function public.guard_presence_update() from public, anon;
grant  execute on function public.guard_presence_update() to authenticated, service_role;

drop trigger if exists profiles_guard_presence on public.profiles;
create trigger profiles_guard_presence
  before update on public.profiles
  for each row execute function public.guard_presence_update();


-- -----------------------------------------------------------------------------
-- B. touch_last_seen — "I opened the app"
-- -----------------------------------------------------------------------------
-- Sets last_seen_at = now() and clears app_removed_at for the caller. The app
-- calls it at most twice an hour (lib/services/presence.dart); this side skips
-- the write anyway if the last one was under 10 minutes ago, unless there is an
-- app_removed_at to clear (the app is evidently installed again).
-- Errors: 28000 not signed in.
create or replace function public.touch_last_seen()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'You must be signed in.'
      using errcode = '28000';
  end if;

  update public.profiles
     set last_seen_at   = now(),
         app_removed_at = null
   where id = v_me
     and (last_seen_at is null
          or last_seen_at < now() - interval '10 minutes'
          or app_removed_at is not null);
end;
$$;

comment on function public.touch_last_seen() is
  'The caller opened the app: profiles.last_seen_at = now() and app_removed_at '
  'cleared. No write if already done within the last 10 minutes.';

revoke execute on function public.touch_last_seen() from public, anon;
grant  execute on function public.touch_last_seen() to authenticated;


-- -----------------------------------------------------------------------------
-- C. witness_nudges
-- -----------------------------------------------------------------------------
-- C.1  One row per thing a Witness is told. `episode_key` is what makes each
--      episode happen once: the unique constraint plus ON CONFLICT DO NOTHING
--      in every writer means a second attempt writes nothing and so pushes
--      nothing.
--        rule_not_committed  ISO week, e.g. '2026-41' (once a week)
--        quiet               'quiet-<last covered day>-2' or '...-7'
--        app_removed         the UTC date it was noticed, e.g. '2026-10-07'
--      `detail` carries numbers only (days_paired, days_quiet, days_since_seen)
--      — never a rhythm's name.
create table if not exists public.witness_nudges (
  id           uuid primary key default gen_random_uuid(),
  runner_id    uuid not null references public.profiles (id) on delete cascade,
  witness_id   uuid not null references public.profiles (id) on delete cascade,
  kind         text not null,
  episode_key  text not null,
  detail       jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now(),
  constraint witness_nudges_kind_known
    check (kind in ('rule_not_committed', 'quiet', 'app_removed')),
  constraint witness_nudges_once_per_episode
    unique (runner_id, witness_id, kind, episode_key)
);

comment on table public.witness_nudges is
  'Things a Witness is told about a Runner who has gone silent: no Rule of Life '
  'yet, no check-in for a while, or the app probably removed. One row per '
  'Runner/Witness/kind/episode; each new row triggers a witness_nudge push. '
  'Written only by generate_witness_nudges() and record_app_removed(). Clients '
  'have no access.';

create index if not exists witness_nudges_witness_idx
  on public.witness_nudges (witness_id, created_at desc);

-- C.2  RLS on with no policies, and no client grants at all: the Witness learns
--      of a nudge from the push, never by reading this table.
alter table public.witness_nudges enable row level security;

revoke all on public.witness_nudges from public, anon, authenticated;
grant  all on public.witness_nudges to service_role;

-- C.3  Each new row asks the push engine to tell the Witness — the same
--      trigger function every other notification uses (004, hardened in 011),
--      so a missing Vault secret or a network problem only skips the push; it
--      never undoes the row.
drop trigger if exists notify_push_on_witness_nudge on public.witness_nudges;
create trigger notify_push_on_witness_nudge
  after insert on public.witness_nudges
  for each row execute function public.notify_push_engine('witness_nudge');


-- -----------------------------------------------------------------------------
-- D. generate_witness_nudges — the daily look for silence
-- -----------------------------------------------------------------------------
-- D.1  What counts. Dates are UTC calendar days (the job runs at 15:00 UTC,
--      which is the same calendar day everywhere in the US).
--
--   rule_not_committed — an ACTIVE pairing at least 2 days old
--      (witness_pairings.paired_since) whose Runner has not committed a Rule of
--      Life. Episode = the ISO week, so the Witness is reminded once a week
--      until it is done. detail: {days_paired}.
--
--   quiet — an ACTIVE pairing whose Runner HAS committed, is not marked
--      app-removed (that push explains the silence better), and:
--        * "last covered day" = the later of their most recent check_in_date
--          and the day they committed. (A check-in on day D+1 reports on day
--          D, so a commitment on day C is treated like a check-in that covered
--          C — the first check-in is due the day after the first rhythm-day.)
--        * days_quiet = today - last covered day - 1, i.e. whole days since the
--          last check-in was made. Nothing at 0 or 1: today's check-in may
--          simply not have happened YET (the job runs mid-morning).
--        * at 2 or more, and only if at least one rhythm was actually due on a
--          day whose check-in is overdue (a day after the last covered day and
--          no later than the day before yesterday), by the same recurrence the
--          roll-up uses (021 E.2): daily; weekly on its weekly_days; monthly on
--          the 1st; annual on January 1st; never before the rhythm existed.
--          A Runner whose only rhythm is weekly is not "quiet" on the days in
--          between.
--      Episode = 'quiet-<last covered day>-2' while days_quiet is 2-6 and
--      'quiet-<last covered day>-7' from 7 on: each silence is announced at
--      most twice, and a new check-in starts a new episode. detail: {days_quiet}.
--
--   app_removed is not written here — see E.
--
--   The Witness's quiet_runner_alerts switch is honoured by the push engine,
--   not here: the row is written either way.
--
--   Returns how many rows were written. Running it twice on one day writes
--   nothing the second time.
--
--   SECURITY DEFINER because it reads every Runner's rhythms and check-ins.
--   Only the scheduled job (which runs as the database owner) and the service
--   role can call it.
create or replace function public.generate_witness_nudges()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'utc')::date;
  v_week  text := to_char(now() at time zone 'utc', 'IYYY-IW');
  v_rows  integer;
  v_total integer := 0;
begin
  -- a. No Rule of Life yet.
  insert into public.witness_nudges (runner_id, witness_id, kind, episode_key, detail)
  select wp.runner_id,
         wp.witness_id,
         'rule_not_committed',
         v_week,
         jsonb_build_object('days_paired', v_today - (wp.paired_since at time zone 'utc')::date)
    from public.witness_pairings wp
    join public.profiles p on p.id = wp.runner_id
   where wp.status = 'active'
     and wp.runner_id <> wp.witness_id
     and not p.has_committed_rule
     and wp.paired_since <= now() - interval '2 days'
  on conflict (runner_id, witness_id, kind, episode_key) do nothing;

  get diagnostics v_rows = row_count;
  v_total := v_total + v_rows;

  -- b. Gone quiet.
  insert into public.witness_nudges (runner_id, witness_id, kind, episode_key, detail)
  select q.runner_id,
         q.witness_id,
         'quiet',
         'quiet-' || to_char(q.covered, 'YYYY-MM-DD') || '-'
           || case when q.days_quiet >= 7 then '7' else '2' end,
         jsonb_build_object('days_quiet', q.days_quiet)
    from (
      select wp.runner_id,
             wp.witness_id,
             c.covered,
             v_today - c.covered - 1 as days_quiet
        from public.witness_pairings wp
        join public.profiles p on p.id = wp.runner_id
        cross join lateral (
          -- greatest() ignores a NULL, so no check-ins = the commit day.
          select greatest(
                   (p.rule_committed_at at time zone 'utc')::date,
                   (select max(ci.check_in_date)
                      from public.check_ins ci
                     where ci.runner_id = wp.runner_id)
                 ) as covered
        ) c
       where wp.status = 'active'
         and wp.runner_id <> wp.witness_id
         and p.has_committed_rule
         and p.rule_committed_at is not null
         and p.app_removed_at is null
    ) q
   where q.days_quiet >= 2
     and exists (
       select 1
         from public.rule_items ri
         cross join lateral (
           select q.covered + g.n as day
             from generate_series(1, (v_today - 2) - q.covered) as g(n)
         ) d
        where ri.runner_id = q.runner_id
          and d.day >= (ri.created_at at time zone 'utc')::date
          and case ri.frequency
                when 'daily'   then true
                when 'weekly'  then extract(isodow from d.day)::smallint = any (ri.weekly_days)
                when 'monthly' then extract(day from d.day) = 1
                when 'annual'  then extract(month from d.day) = 1 and extract(day from d.day) = 1
              end
     )
  on conflict (runner_id, witness_id, kind, episode_key) do nothing;

  get diagnostics v_rows = row_count;
  v_total := v_total + v_rows;

  return v_total;
end;
$$;

comment on function public.generate_witness_nudges() is
  'Daily (pg_cron trellis-witness-nudges): writes witness_nudges rows for active '
  'pairings whose Runner has no Rule of Life after 2 days (weekly) or has not '
  'checked in for 2+ days while something was due (at 2 and at 7 days). '
  'Returns rows written.';

revoke execute on function public.generate_witness_nudges() from public, anon, authenticated;
grant  execute on function public.generate_witness_nudges() to service_role;

-- D.2  Muting: the Witness's own profiles.notification_preferences key
--      quiet_runner_alerts (false = no push; absent or true = push). Checked by
--      the push engine — see F.

-- D.3  The schedule: every day at 15:00 UTC (10 a.m. US Central in summer,
--      9 a.m. in winter), job name `trellis-witness-nudges` — an hour after the
--      presence probe (E.4), so a Runner whose app turns out to be gone is
--      already marked and gets the "may have stepped away" push instead of
--      "hasn't checked in".
--
--      Wrapped so that a project without pg_cron still gets everything else in
--      this file (same pattern as 021 E.5 and 023 D.2). If the notice below
--      appears: Dashboard -> Database -> Extensions -> enable pg_cron, then run
--      this one DO block again.
do $do$
declare
  v_jobid bigint;
begin
  create extension if not exists pg_cron;

  -- Start clean: remove any earlier job of this name before scheduling.
  for v_jobid in
    select jobid from cron.job where jobname = 'trellis-witness-nudges'
  loop
    perform cron.unschedule(v_jobid);
  end loop;

  perform cron.schedule(
    'trellis-witness-nudges',
    '0 15 * * *',
    'select public.generate_witness_nudges();'
  );

  raise notice '026: Witness nudges scheduled (job trellis-witness-nudges, daily 15:00 UTC).';
exception when others then
  raise notice '026: the Witness nudge job was NOT scheduled: % (SQLSTATE %).', sqlerrm, sqlstate;
  raise notice '026: to fix: Dashboard -> Database -> Extensions -> enable pg_cron, then re-run the DO block in section D.3 of 026_witness_nudges.sql. Nothing else in this file depends on it.';
end
$do$;


-- -----------------------------------------------------------------------------
-- E. App removed — the daily presence probe
-- -----------------------------------------------------------------------------
-- How it fits together:
--   14:00 UTC  pg_cron runs request_presence_probe() (E.3), which POSTs
--              {"action":"presence_probe"} to push-notification-engine with the
--              same Vault secret every push trigger uses.
--   engine     asks presence_probe_candidates() (E.1) whom to probe and sends
--              each a silent data-only push. For every token FCM reports as
--              gone (UNREGISTERED, or INVALID_ARGUMENT about the token) it calls
--              record_app_removed() (E.2). If more than half of a run's tokens
--              (and more than three) come back gone, it assumes a configuration
--              problem and marks nobody.
--   engine     the same record_app_removed() is called whenever ANY ordinary
--              push finds its token gone.
--
-- E.1  Whom to probe: people with at least one ACTIVE pairing as the Runner, a
--      device token, not already marked app-removed, and not seen for two days
--      (last_seen_at, or — never seen since 026 — the account's creation).
--      Longest-unseen first, at most 500 a run.
create or replace function public.presence_probe_candidates(p_limit integer default 500)
returns table (profile_id uuid, fcm_token text)
language sql
security definer
stable
set search_path = public
as $$
  select p.id, p.fcm_token
    from public.profiles p
   where p.fcm_token is not null
     and length(p.fcm_token) > 0
     and p.app_removed_at is null
     and coalesce(p.last_seen_at, p.created_at) < now() - interval '2 days'
     and exists (
       select 1
         from public.witness_pairings wp
        where wp.runner_id = p.id
          and wp.witness_id <> p.id
          and wp.status = 'active'
     )
   order by coalesce(p.last_seen_at, p.created_at)
   limit least(greatest(coalesce(p_limit, 500), 1), 500);
$$;

comment on function public.presence_probe_candidates(integer) is
  'For push-notification-engine''s daily presence probe: Runners with an active '
  'pairing and a device token, not marked app-removed, not seen for 2 days. '
  'At most 500, longest-unseen first. Service role only.';

revoke execute on function public.presence_probe_candidates(integer) from public, anon, authenticated;
grant  execute on function public.presence_probe_candidates(integer) to service_role;

-- E.2  FCM says p_token is gone. Only if the profile still has THAT token (a
--      newer one means the app was reinstalled or moved to another phone in the
--      meantime — nothing to do):
--        * fcm_token is cleared (it will never work again) and app_removed_at
--          set;
--        * one app_removed row per ACTIVE Witness of this person as a Runner
--          (none if they are only ever a Witness), episode = today's UTC date.
--      Returns how many nudges were written (0 when the token had changed).
create or replace function public.record_app_removed(p_profile_id uuid, p_token text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_last_seen timestamptz;
  v_rows      integer;
begin
  if p_profile_id is null or p_token is null or length(p_token) = 0 then
    return 0;
  end if;

  update public.profiles
     set fcm_token      = null,
         app_removed_at = now()
   where id = p_profile_id
     and fcm_token = p_token
  returning last_seen_at into v_last_seen;

  if not found then
    return 0;
  end if;

  insert into public.witness_nudges (runner_id, witness_id, kind, episode_key, detail)
  select wp.runner_id,
         wp.witness_id,
         'app_removed',
         to_char(now() at time zone 'utc', 'YYYY-MM-DD'),
         jsonb_build_object(
           'days_since_seen',
           case when v_last_seen is null then null
                else (now() at time zone 'utc')::date - (v_last_seen at time zone 'utc')::date
           end
         )
    from public.witness_pairings wp
   where wp.runner_id = p_profile_id
     and wp.witness_id <> p_profile_id
     and wp.status = 'active'
  on conflict (runner_id, witness_id, kind, episode_key) do nothing;

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

comment on function public.record_app_removed(uuid, text) is
  'push-notification-engine: FCM reported p_token gone. If the profile still has '
  'that token: clear it, set app_removed_at, and write an app_removed '
  'witness_nudges row for each active Witness. Returns nudges written. Service '
  'role only.';

revoke execute on function public.record_app_removed(uuid, text) from public, anon, authenticated;
grant  execute on function public.record_app_removed(uuid, text) to service_role;

-- E.3  The call the scheduled job makes: one POST to the push engine through
--      pg_net, authenticated exactly like notify_push_engine() (011). A missing
--      Vault secret skips the run with a WARNING. pg_net does not wait for the
--      answer; the 2-minute timeout only bounds how long it keeps the
--      connection open (the probe sends 25 at a time and normally finishes in
--      seconds). Returns the pg_net request id, or null when skipped.
create or replace function public.request_presence_probe()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret     text;
  v_request_id bigint;
begin
  select decrypted_secret
    into v_secret
    from vault.decrypted_secrets
   where name = 'push_engine_webhook_secret'
   limit 1;

  if v_secret is null then
    raise warning 'request_presence_probe: Vault secret push_engine_webhook_secret is not set; skipping the presence probe.';
    return null;
  end if;

  select net.http_post(
    url := 'https://qonsiliimbkcjmcnhonb.supabase.co/functions/v1/push-notification-engine',
    body := jsonb_build_object('action', 'presence_probe'),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-trellis-webhook-secret', v_secret
    ),
    timeout_milliseconds := 120000
  ) into v_request_id;

  return v_request_id;
end;
$$;

comment on function public.request_presence_probe() is
  'Daily (pg_cron trellis-presence-probe): asks push-notification-engine to run '
  'its presence probe. Returns the pg_net request id, or null when the Vault '
  'secret is missing.';

revoke execute on function public.request_presence_probe() from public, anon, authenticated;
grant  execute on function public.request_presence_probe() to service_role;

-- E.4  The schedule: every day at 14:00 UTC (9 a.m. US Central in summer,
--      8 a.m. in winter), job name `trellis-presence-probe` — an hour before
--      the nudges (D.3). Wrapped like D.3.
do $do$
declare
  v_jobid bigint;
begin
  create extension if not exists pg_cron;

  for v_jobid in
    select jobid from cron.job where jobname = 'trellis-presence-probe'
  loop
    perform cron.unschedule(v_jobid);
  end loop;

  perform cron.schedule(
    'trellis-presence-probe',
    '0 14 * * *',
    'select public.request_presence_probe();'
  );

  raise notice '026: presence probe scheduled (job trellis-presence-probe, daily 14:00 UTC).';
exception when others then
  raise notice '026: the presence probe job was NOT scheduled: % (SQLSTATE %).', sqlerrm, sqlstate;
  raise notice '026: to fix: Dashboard -> Database -> Extensions -> enable pg_cron, then re-run the DO block in section E.4 of 026_witness_nudges.sql. Nothing else in this file depends on it.';
end
$do$;


-- -----------------------------------------------------------------------------
-- F. profiles.notification_preferences — the keys in use (021 G, plus one)
-- -----------------------------------------------------------------------------
--   quiet_runner_alerts   Witness. "Check-In Alerts": every witness_nudge push
--                         (no Rule of Life yet, gone quiet, app probably
--                         removed). false = the push engine does not send it;
--                         absent or true = it does. Existing profiles do not
--                         have the key, so they are ON.
comment on column public.profiles.notification_preferences is
  'JSON object of notification switches; a missing key means ON. Keys: '
  'anchor_rhythm_alerts (Witness), weekly_roll_up (Witness: receive the weekly '
  'roll-up push), quiet_runner_alerts (Witness: Check-In Alerts — a Runner gone '
  'quiet, without a Rule of Life, or whose app was probably removed), '
  'meeting_requests, prayer_reminders (on-device), check_in_reminder '
  '(on-device; absent = on).';


-- -----------------------------------------------------------------------------
-- G. Grants, all in one place
-- -----------------------------------------------------------------------------
--   client (authenticated)        touch_last_seen()
--   service role / pg_cron only   generate_witness_nudges()
--                                 presence_probe_candidates(integer)
--                                 record_app_removed(uuid, text)
--                                 request_presence_probe()
--   trigger function              guard_presence_update()
--   (not directly callable)
--   table                         witness_nudges: nobody but service_role
--   columns                       profiles.last_seen_at, app_removed_at:
--                                 clients read, never write
revoke execute on function public.touch_last_seen()                   from public, anon;
grant  execute on function public.touch_last_seen()                   to authenticated;
revoke execute on function public.generate_witness_nudges()           from public, anon, authenticated;
grant  execute on function public.generate_witness_nudges()           to service_role;
revoke execute on function public.presence_probe_candidates(integer)  from public, anon, authenticated;
grant  execute on function public.presence_probe_candidates(integer)  to service_role;
revoke execute on function public.record_app_removed(uuid, text)      from public, anon, authenticated;
grant  execute on function public.record_app_removed(uuid, text)      to service_role;
revoke execute on function public.request_presence_probe()            from public, anon, authenticated;
grant  execute on function public.request_presence_probe()            to service_role;
revoke execute on function public.guard_presence_update()             from public, anon;
grant  execute on function public.guard_presence_update()             to authenticated, service_role;
revoke all on public.witness_nudges from public, anon, authenticated;
grant  all on public.witness_nudges to service_role;


-- =============================================================================
-- H. VERIFICATION — run in the SQL editor and compare with "expect"
-- =============================================================================
-- Blocks that act as a signed-in user use `set local role` (as 018–025 do).
-- Replace the <...> placeholders with real test ids. A block that ends in an
-- expected ERROR must be run on its own: the error aborts that transaction, and
-- the `rollback;` on its last line cleans up. EVERY dry run here rolls back —
-- the witness_nudges rows AND the push requests their trigger queued in pg_net
-- are discarded, so nothing is sent.
--
-- 0. Privileges at a glance. Expect, in order:
--    false, true,  true     touch_last_seen: not anon; signed-in users; service role
--    false, false, true     generate_witness_nudges
--    false, false, true     presence_probe_candidates
--    false, false, true     record_app_removed
--    false, false, true     request_presence_probe
--    false, false, true     witness_nudges SELECT: no client; service role yes
--    false, false           witness_nudges INSERT for anon / authenticated
--    true,  false           last_seen_at: clients read, cannot write
--    true,  false           app_removed_at: clients read, cannot write
--
--   select has_function_privilege('anon',          'public.touch_last_seen()', 'execute'),
--          has_function_privilege('authenticated', 'public.touch_last_seen()', 'execute'),
--          has_function_privilege('service_role',  'public.touch_last_seen()', 'execute');
--   select has_function_privilege('anon',          'public.generate_witness_nudges()', 'execute'),
--          has_function_privilege('authenticated', 'public.generate_witness_nudges()', 'execute'),
--          has_function_privilege('service_role',  'public.generate_witness_nudges()', 'execute');
--   select has_function_privilege('anon',          'public.presence_probe_candidates(integer)', 'execute'),
--          has_function_privilege('authenticated', 'public.presence_probe_candidates(integer)', 'execute'),
--          has_function_privilege('service_role',  'public.presence_probe_candidates(integer)', 'execute');
--   select has_function_privilege('anon',          'public.record_app_removed(uuid,text)', 'execute'),
--          has_function_privilege('authenticated', 'public.record_app_removed(uuid,text)', 'execute'),
--          has_function_privilege('service_role',  'public.record_app_removed(uuid,text)', 'execute');
--   select has_function_privilege('anon',          'public.request_presence_probe()', 'execute'),
--          has_function_privilege('authenticated', 'public.request_presence_probe()', 'execute'),
--          has_function_privilege('service_role',  'public.request_presence_probe()', 'execute');
--   select has_table_privilege('anon',          'public.witness_nudges', 'select'),
--          has_table_privilege('authenticated', 'public.witness_nudges', 'select'),
--          has_table_privilege('service_role',  'public.witness_nudges', 'select');
--   select has_table_privilege('anon',          'public.witness_nudges', 'insert'),
--          has_table_privilege('authenticated', 'public.witness_nudges', 'insert');
--   select has_column_privilege('authenticated', 'public.profiles', 'last_seen_at', 'select'),
--          has_column_privilege('authenticated', 'public.profiles', 'last_seen_at', 'update');
--   select has_column_privilege('authenticated', 'public.profiles', 'app_removed_at', 'select'),
--          has_column_privilege('authenticated', 'public.profiles', 'app_removed_at', 'update');
--
-- 1. Structure. Expect: rls = true, 0 policies; the two constraints; the
--    triggers notify_push_on_witness_nudge (on witness_nudges) and
--    profiles_guard_presence (on profiles).
--   select c.relrowsecurity as rls,
--          (select count(*) from pg_policies where schemaname = 'public' and tablename = 'witness_nudges') as policies
--     from pg_class c where c.oid = 'public.witness_nudges'::regclass;
--   select conname, pg_get_constraintdef(oid) from pg_constraint
--    where conrelid = 'public.witness_nudges'::regclass and contype in ('c', 'u') order by 1;
--   select tgrelid::regclass, tgname from pg_trigger
--    where not tgisinternal
--      and tgname in ('notify_push_on_witness_nudge', 'profiles_guard_presence');
--
-- 2. The two jobs. Expect two rows: trellis-presence-probe `0 14 * * *` and
--    trellis-witness-nudges `0 15 * * *`, both active. If this errors with
--    "relation cron.job does not exist", pg_cron is not enabled — see D.3:
--   select jobid, jobname, schedule, command, active
--     from cron.job where jobname in ('trellis-presence-probe', 'trellis-witness-nudges')
--    order by jobname;
--   After the first day, how the runs went:
--   select j.jobname, d.status, d.return_message, d.start_time
--     from cron.job_run_details d join cron.job j on j.jobid = d.jobid
--    where j.jobname in ('trellis-presence-probe', 'trellis-witness-nudges')
--    order by d.start_time desc limit 10;
--
-- 3. touch_last_seen. As a signed-in user. Expect: a timestamp of "now" and
--    app_removed_at null; then the second touch leaves last_seen_at unchanged
--    (within 10 minutes); then the direct write is refused with ERROR 42501
--    permission denied (run that last statement in its own block).
--   begin;
--   update public.profiles set last_seen_at = now() - interval '3 days', app_removed_at = now()
--    where id = '<runner-uuid>';                                    -- as the editor: set the scene
--   set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   select public.touch_last_seen();
--   select last_seen_at, app_removed_at from public.profiles where id = auth.uid();
--   select public.touch_last_seen();
--   select last_seen_at from public.profiles where id = auth.uid();   -- same value as above
--   rollback;
--
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<runner-uuid>","role":"authenticated"}', true);
--   update public.profiles set last_seen_at = now() - interval '30 days' where id = auth.uid();   -- ERROR 42501
--   rollback;
--
--   Not signed in (expect ERROR 28000):
--   begin; set local role authenticated; select public.touch_last_seen(); rollback;
--
-- 4. generate_witness_nudges, dry run with made-up history. Use a Runner and a
--    Witness from your test accounts. Everything rolls back. The block makes
--    them actively paired for 5 days, gives the Runner a committed Rule of
--    Life (10 days ago) with one daily rhythm, and walks through the cases.
--   begin;
--   insert into public.witness_pairings (runner_id, witness_id, status, paired_since)
--   values ('<runner-uuid>', '<witness-uuid>', 'active', now() - interval '5 days')
--   on conflict (runner_id, witness_id) do update set status = 'active', paired_since = now() - interval '5 days';
--
--   -- 4a. Not committed: expect >= 1 (one rule_not_committed row per active
--   --     Witness), key = this ISO week, detail {"days_paired": 5}.
--   update public.profiles set has_committed_rule = false, rule_committed_at = null where id = '<runner-uuid>';
--   select public.generate_witness_nudges();
--   select kind, episode_key, detail from public.witness_nudges
--    where runner_id = '<runner-uuid>' and witness_id = '<witness-uuid>';
--   select public.generate_witness_nudges();                        -- 0 for this pair: once per week
--
--   -- 4b. Committed 10 days ago, last check-in about 5 days ago: expect one
--   --     quiet row with key 'quiet-<current_date - 5>-2' and {"days_quiet": 4}.
--   update public.profiles
--      set has_committed_rule = true, rule_committed_at = now() - interval '10 days', app_removed_at = null
--    where id = '<runner-uuid>';
--   delete from public.check_ins where runner_id = '<runner-uuid>';
--   insert into public.rule_items (runner_id, category, title, frequency, created_at)
--   values ('<runner-uuid>', 'abiding_prayer', '026 probe', 'daily', now() - interval '10 days');
--   insert into public.check_ins (runner_id, rule_item_id, check_in_date, answered_yes)
--   select '<runner-uuid>', id, current_date - 5, true
--     from public.rule_items where runner_id = '<runner-uuid>' and title = '026 probe';
--   select public.generate_witness_nudges();
--   select kind, episode_key, detail from public.witness_nudges
--    where runner_id = '<runner-uuid>' and witness_id = '<witness-uuid>' and kind = 'quiet';
--
--   -- 4c. No check-ins at all since committing 10 days ago: expect a new row
--   --     'quiet-<current_date - 10>-7' with {"days_quiet": 9}.
--   delete from public.check_ins where runner_id = '<runner-uuid>';
--   select public.generate_witness_nudges();
--   select kind, episode_key, detail from public.witness_nudges
--    where runner_id = '<runner-uuid>' and witness_id = '<witness-uuid>' and kind = 'quiet'
--    order by created_at;
--
--   -- 4d. Checked in yesterday (about the day before): expect 0 new quiet rows.
--   insert into public.check_ins (runner_id, rule_item_id, check_in_date, answered_yes)
--   select '<runner-uuid>', id, current_date - 1, true
--     from public.rule_items where runner_id = '<runner-uuid>' and title = '026 probe';
--   select public.generate_witness_nudges();                        -- 0
--
--   -- 4e. Quiet again, but the app is marked removed: expect 0 (quiet is skipped).
--   delete from public.check_ins where runner_id = '<runner-uuid>';
--   update public.profiles set rule_committed_at = now() - interval '4 days', app_removed_at = now()
--    where id = '<runner-uuid>';
--   select public.generate_witness_nudges();                        -- 0
--   rollback;
--
--   A Runner whose ONLY rhythm is weekly is not quiet on the days in between:
--   repeat 4b with frequency 'weekly' and weekly_days set to a weekday that has
--   not occurred in the last 3 days — expect no quiet row.
--
-- 5. record_app_removed, dry run. Expect: 0 for a wrong token (nothing
--    changes), then >= 1 (one app_removed row per active Witness) with
--    episode_key = today's date, fcm_token null and app_removed_at = now; a
--    second call returns 0 (the token is gone now).
--   begin;
--   update public.profiles set fcm_token = 'dry-run-token', app_removed_at = null where id = '<runner-uuid>';
--   select public.record_app_removed('<runner-uuid>', 'some-other-token');   -- 0
--   select public.record_app_removed('<runner-uuid>', 'dry-run-token');      -- >= 1 with an active Witness
--   select fcm_token is null as token_cleared, app_removed_at from public.profiles where id = '<runner-uuid>';
--   select kind, episode_key, detail from public.witness_nudges
--    where runner_id = '<runner-uuid>' and kind = 'app_removed';
--   select public.record_app_removed('<runner-uuid>', 'dry-run-token');      -- 0
--   rollback;
--
-- 6. presence_probe_candidates (read-only). Expect only Runners with an active
--    Witness, a token, no app_removed_at and not seen for 2 days. RIGHT AFTER
--    THIS MIGRATION that is every such Runner whose account is over 2 days
--    old (nobody has a last_seen_at yet); each drops off once they open the
--    new build.
--   select c.profile_id, p.name, p.last_seen_at, p.created_at
--     from public.presence_probe_candidates(500) c
--     join public.profiles p on p.id = c.profile_id;
--
-- 7. Clients cannot see or call any of it (expect ERROR 42501 permission
--    denied for each; run one at a time):
--   begin; set local role authenticated;
--   select set_config('request.jwt.claims', '{"sub":"<witness-uuid>","role":"authenticated"}', true);
--   select * from public.witness_nudges;
--   rollback;
--   (likewise: select public.generate_witness_nudges(); select * from
--    public.presence_probe_candidates(500); select public.record_app_removed(
--    '<runner-uuid>', 'x'); select public.request_presence_probe();)
--
-- 8. End to end (SENDS REAL PUSHES — only with test accounts). After the engine
--    is deployed:
--      a. Probe now instead of waiting for 14:00 UTC; then watch Edge Functions
--         -> push-notification-engine -> Logs for "presence probe: {...}":
--           select public.request_presence_probe();
--           select id, status_code, content from net._http_response order by id desc limit 1;
--      b. A real quiet / rule_not_committed push: run block 4 with `commit;`
--         instead of `rollback;` (then delete the '026 probe' rhythm by hand).
--      c. App removed: on a test Runner's phone, delete the app; wait a few
--         hours (Apple reports uninstalls to FCM lazily); make sure that
--         Runner's last_seen_at is over 2 days old (as the editor:
--         update public.profiles set last_seen_at = now() - interval '3 days'
--         where id = '<runner-uuid>';), then run 8a. Expect tokensGone 1 in the
--         log, the Runner's fcm_token null / app_removed_at set, and the
--         Witness's phone showing "<First> may have stepped away".
--
-- 9. The documented keys:
--   select col_description('public.profiles'::regclass,
--            (select attnum from pg_attribute
--              where attrelid = 'public.profiles'::regclass and attname = 'notification_preferences'));
-- =============================================================================
