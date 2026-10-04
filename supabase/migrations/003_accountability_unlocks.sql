-- =============================================================================
-- The Trellis — 003_accountability_unlocks.sql
-- =============================================================================
-- Canopy Rhythm unlock requests. A Runner can't delete or un-anchor a
-- church-mandated rhythm on their own (rule_items.is_church_mandated — see
-- init_schema.sql, and rule_builder_screen.dart's _isLocked) — only their
-- church could previously retire one. This adds a real path: the Runner
-- asks a specific Witness for permission instead.
--
-- Flow:
--   1. Runner taps "Remove Lock" -> inserts a 'pending' row here (RLS, B).
--   2. A database trigger (see 004_universal_webhooks.sql) notifies the
--      universal push-notification-engine Edge Function on INSERT, which
--      pushes a notification to the Witness.
--   3. Witness taps Approve/Deny -> updates the row's status (RLS, B).
--   4. A trigger (part C) cascades an 'approved' decision into
--      rule_items.is_church_mandated = false automatically — the Witness
--      never needs direct write access to rule_items just to approve one
--      of these.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- A. Table
-- -----------------------------------------------------------------------------
create table if not exists public.pending_unlock_requests (
  id            uuid primary key default gen_random_uuid(),
  runner_id     uuid not null references public.profiles (id) on delete cascade,
  witness_id    uuid not null references public.profiles (id) on delete cascade,
  rule_item_id  uuid not null references public.rule_items (id) on delete cascade,
  status        text not null default 'pending'
                  check (status in ('pending', 'approved', 'denied')),
  requested_at  timestamptz not null default now(),
  resolved_at   timestamptz
);
comment on table public.pending_unlock_requests is
  'A Runner asking a specific Witness for permission to unlock (and then '
  'freely edit/remove) a Canopy Rhythm. See the notify-unlock-request Edge '
  'Function and the apply_unlock_request_approval trigger below.';

create index if not exists pending_unlock_requests_witness_idx
  on public.pending_unlock_requests (witness_id, status);
create index if not exists pending_unlock_requests_runner_idx
  on public.pending_unlock_requests (runner_id, status);

-- Only one open request per rhythm at a time. The Flutter client also
-- disables "Remove Lock" once it sees a pending row for that item, but this
-- is the actual guarantee — belt-and-suspenders against a double-tap or a
-- second device.
create unique index if not exists pending_unlock_requests_one_open_per_item
  on public.pending_unlock_requests (rule_item_id)
  where status = 'pending';


-- -----------------------------------------------------------------------------
-- B. RLS
-- -----------------------------------------------------------------------------
alter table public.pending_unlock_requests enable row level security;

-- Runner: insert and view their own requests. witness_id must actually be
-- one of the Runner's own active Witnesses — otherwise a Runner could name
-- an arbitrary account as "witness_id" and hand them approval power over
-- their own rhythms.
create policy "unlock_requests_insert_by_runner"
  on public.pending_unlock_requests for insert
  to authenticated
  with check (
    runner_id = auth.uid()
    and exists (
      select 1 from public.witness_pairings
      where runner_id = auth.uid()
        and witness_id = pending_unlock_requests.witness_id
        and status = 'active'
    )
  );

create policy "unlock_requests_select_by_runner"
  on public.pending_unlock_requests for select
  to authenticated
  using (runner_id = auth.uid());

-- Witness: view and update (approve/deny) requests addressed to them.
create policy "unlock_requests_select_by_witness"
  on public.pending_unlock_requests for select
  to authenticated
  using (witness_id = auth.uid());

create policy "unlock_requests_update_by_witness"
  on public.pending_unlock_requests for update
  to authenticated
  using (witness_id = auth.uid() and status = 'pending')
  with check (witness_id = auth.uid());

-- This is a fresh table — 002's blanket GRANT only covered the tables that
-- existed when it ran, not tables created afterward. Same class of bug as
-- the very first thing 002 had to fix; not repeating it here.
grant select, insert, update on public.pending_unlock_requests to authenticated;


-- -----------------------------------------------------------------------------
-- C. Guard + cascade triggers
-- -----------------------------------------------------------------------------
-- The UPDATE policy above only restricts *which rows* a Witness can touch,
-- not *what* they change them to. Without this, a buggy or malicious client
-- could reassign runner_id/rule_item_id, or jump straight to an arbitrary
-- status string. This locks an update down to exactly "pending ->
-- approved/denied", nothing else, and stamps resolved_at itself so the
-- client can't spoof it.
create or replace function public.enforce_unlock_request_update()
returns trigger
language plpgsql
as $$
begin
  if old.status <> 'pending' then
    raise exception 'This request has already been resolved.';
  end if;
  if new.status not in ('approved', 'denied') then
    raise exception 'A pending request can only become approved or denied.';
  end if;
  if new.runner_id <> old.runner_id
     or new.witness_id <> old.witness_id
     or new.rule_item_id <> old.rule_item_id
     or new.requested_at <> old.requested_at then
    raise exception 'Only status may change on an unlock request.';
  end if;

  new.resolved_at := now();
  return new;
end;
$$;

drop trigger if exists enforce_unlock_request_update on public.pending_unlock_requests;
create trigger enforce_unlock_request_update
  before update on public.pending_unlock_requests
  for each row execute function public.enforce_unlock_request_update();

-- Cascades an approval into the actual rhythm. security definer (runs as
-- the table owner, bypassing RLS) so the Witness's own grants never need to
-- extend to rule_items just to approve an unlock — same reasoning as every
-- other cross-account write in this app (see 002's cloud-access RPCs).
create or replace function public.apply_unlock_request_approval()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'approved' and old.status = 'pending' then
    update public.rule_items
       set is_church_mandated = false
     where id = new.rule_item_id;
  end if;
  return new;
end;
$$;

drop trigger if exists apply_unlock_request_approval on public.pending_unlock_requests;
create trigger apply_unlock_request_approval
  after update on public.pending_unlock_requests
  for each row execute function public.apply_unlock_request_approval();


-- -----------------------------------------------------------------------------
-- D. Realtime — the Flutter client subscribes to INSERTs (Witness side, so
--    a new request appears without a manual reload) and UPDATEs (Runner
--    side, so "Pending Witness Approval" clears the moment it's resolved).
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pending_unlock_requests'
  ) then
    alter publication supabase_realtime add table public.pending_unlock_requests;
  end if;
end $$;


-- -----------------------------------------------------------------------------
-- E. FCM device token — where the universal push-notification-engine Edge
--    Function (see supabase/migrations/004_universal_webhooks.sql) looks up
--    a profile's device to deliver to. One token per account, matching
--    "save that token to the user's profiles row" — a real trade-off
--    against a one-row-per-device table (signing in on a second device
--    silently replaces the first device's delivery target), accepted here
--    for simplicity. profiles already has a self-update RLS policy from
--    init_schema.sql, so no new policy is needed for this column.
--
--    NOTE: this column alone does not make push notifications work end to
--    end — the Flutter client still has to obtain a device token (via
--    firebase_messaging, wired up separately) and write it here. See the
--    Flutter implementation notes delivered alongside 004 for what's
--    included vs. what's left.
-- -----------------------------------------------------------------------------
alter table public.profiles add column if not exists fcm_token text;


-- =============================================================================
-- Deployment notes (not SQL — nothing below this line runs in the editor)
-- =============================================================================
-- Nothing to deploy from this file alone. The Edge Function, its secrets,
-- and the triggers that call it all live in 004_universal_webhooks.sql —
-- run this file first, then that one.
-- =============================================================================
