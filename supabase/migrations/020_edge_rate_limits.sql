-- =============================================================================
-- 020 — Rate limiting for Edge Functions (first user: calendar-availability)
-- =============================================================================
-- Run after 019. Safe to re-run.
--
-- Why a table: Edge Functions run as many short-lived instances, so an
-- in-memory counter would give every instance its own allowance. One row per
-- (key, time window) in Postgres is shared by all of them, and the increment
-- below is a single atomic statement, so two simultaneous requests can never
-- both read "9 of 10" and both be let through.
--
-- Model: fixed windows. A window is `p_window_seconds` long, aligned to the
-- epoch. The caller is allowed `p_limit` hits per window. Fixed windows can let
-- through up to twice the limit across a window boundary; for "stop a client
-- hammering the calendar provider" that is fine, and it keeps the counter to a
-- single row per window.
--
-- Access: clients (anon / authenticated) can neither read the table nor call
-- the function. Only the Edge Functions' service role can. Keys are chosen by
-- the function (e.g. 'calendar-availability:<user-uuid>:minute'), never by a
-- client.
-- =============================================================================

create table if not exists public.edge_rate_limits (
  bucket_key   text        not null,
  window_start timestamptz not null,
  hits         integer     not null default 0,
  primary key (bucket_key, window_start)
);

-- Used by the opportunistic clean-up in edge_rate_limit_hit.
create index if not exists edge_rate_limits_window_start_idx
  on public.edge_rate_limits (window_start);

-- RLS on with no policies = no access for clients, even if a grant is ever
-- added by mistake. (The service role bypasses RLS.)
alter table public.edge_rate_limits enable row level security;

revoke all on public.edge_rate_limits from public, anon, authenticated;
grant select, insert, update, delete on public.edge_rate_limits to service_role;


-- -----------------------------------------------------------------------------
-- edge_rate_limit_hit(key, limit, window) -> (allowed, current_hits, retry_after_seconds)
-- -----------------------------------------------------------------------------
-- Counts one request against `p_key` in the current window and says whether it
-- is within `p_limit`. Requests over the limit are counted too (so a client
-- that keeps retrying stays blocked rather than sneaking in at the window edge
-- — the window simply ends). `retry_after_seconds` is 0 when allowed, otherwise
-- the whole seconds until the current window ends (at least 1).
create or replace function public.edge_rate_limit_hit(
  p_key            text,
  p_limit          integer,
  p_window_seconds integer
)
returns table (allowed boolean, current_hits integer, retry_after_seconds integer)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_now          timestamptz := clock_timestamp();
  v_window_start timestamptz;
  v_window_end   timestamptz;
  v_hits         integer;
begin
  if p_key is null or length(p_key) = 0 or length(p_key) > 200 then
    raise exception 'invalid rate limit key' using errcode = '22023';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100000 then
    raise exception 'invalid rate limit' using errcode = '22023';
  end if;
  if p_window_seconds is null or p_window_seconds < 1 or p_window_seconds > 86400 then
    raise exception 'invalid rate limit window' using errcode = '22023';
  end if;

  v_window_start := to_timestamp(
    floor(extract(epoch from v_now) / p_window_seconds) * p_window_seconds
  );
  v_window_end := v_window_start + make_interval(secs => p_window_seconds);

  insert into public.edge_rate_limits as r (bucket_key, window_start, hits)
  values (p_key, v_window_start, 1)
  on conflict (bucket_key, window_start)
  do update set hits = r.hits + 1
  returning r.hits into v_hits;

  -- Housekeeping: about one call in a hundred removes windows older than two
  -- days (longer than any window we allow), so the table stays small without
  -- needing a scheduled job.
  if random() < 0.01 then
    delete from public.edge_rate_limits where window_start < v_now - interval '2 days';
  end if;

  allowed := v_hits <= p_limit;
  current_hits := v_hits;
  retry_after_seconds := case
    when allowed then 0
    else greatest(1, ceil(extract(epoch from (v_window_end - v_now)))::integer)
  end;
  return next;
end;
$$;

revoke all on function public.edge_rate_limit_hit(text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.edge_rate_limit_hit(text, integer, integer) to service_role;


-- =============================================================================
-- Verification (SQL editor)
-- =============================================================================
-- 1. The limiter counts and then blocks (limit 3 per 60 s) — run as one batch;
--    expect: true, true, true, false (with retry_after_seconds between 1 and 60).
--      select * from public.edge_rate_limit_hit('selftest', 3, 60);
--      select * from public.edge_rate_limit_hit('selftest', 3, 60);
--      select * from public.edge_rate_limit_hit('selftest', 3, 60);
--      select * from public.edge_rate_limit_hit('selftest', 3, 60);
--      delete from public.edge_rate_limits where bucket_key = 'selftest';
--
-- 2. Clients are locked out — all four must be false:
--      select has_function_privilege('anon',
--               'public.edge_rate_limit_hit(text,integer,integer)', 'execute'),
--             has_function_privilege('authenticated',
--               'public.edge_rate_limit_hit(text,integer,integer)', 'execute'),
--             has_table_privilege('anon',          'public.edge_rate_limits', 'select'),
--             has_table_privilege('authenticated', 'public.edge_rate_limits', 'select');
--
-- 3. The Edge Functions can use it — both true:
--      select has_function_privilege('service_role',
--               'public.edge_rate_limit_hit(text,integer,integer)', 'execute'),
--             has_table_privilege('service_role', 'public.edge_rate_limits', 'insert');
-- =============================================================================
