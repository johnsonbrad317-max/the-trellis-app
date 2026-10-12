-- =============================================================================
-- The Trellis — 033_prayer_sharing.sql   (share a prayer with chosen Witnesses,
--                                          and tell them right away)
-- =============================================================================
-- Run after 032. Idempotent — safe to run more than once. Uses 011's
-- notify_push_engine (Vault secret push_engine_webhook_secret) and needs the
-- push-notification-engine deployed with the new 'prayer_shared' event.
--
--   A. prayer_items.shared_with — which Witnesses see a shared prayer: their
--      profile ids, or NULL for all of them (every prayer shared so far, and
--      any Witness who pairs later). share_with_witnesses stays the switch.
--   B. The Witness's read and "prayed / answered" policies honor it.
--   C. prayer_share_notices — one row per Witness a prayer has just been
--      shared with (on adding it shared, switching sharing on, or adding a
--      Witness to it). Each row is a push: "<Runner> shared a prayer request".
--      Editing a prayer that is already shared does not notify again.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- A. Who it is shared with
-- -----------------------------------------------------------------------------
alter table public.prayer_items
  add column if not exists shared_with uuid[];

comment on column public.prayer_items.shared_with is
  'When share_with_witnesses: the Witness profile ids who see it, or null for '
  'every active Witness. Ignored while share_with_witnesses is false.';


-- -----------------------------------------------------------------------------
-- B. Policies
-- -----------------------------------------------------------------------------
drop policy if exists "prayer_items_select_own_or_shared" on public.prayer_items;
create policy "prayer_items_select_own_or_shared"
  on public.prayer_items for select
  to authenticated
  using (
    runner_id = auth.uid()
    or (
      share_with_witnesses
      and public.is_witness_of(runner_id)
      and (shared_with is null or auth.uid() = any (shared_with))
    )
  );

drop policy if exists "prayer_items_update_shared_by_witness" on public.prayer_items;
create policy "prayer_items_update_shared_by_witness"
  on public.prayer_items for update
  to authenticated
  using (
    share_with_witnesses
    and public.is_witness_of(runner_id)
    and (shared_with is null or auth.uid() = any (shared_with))
  )
  with check (
    share_with_witnesses
    and public.is_witness_of(runner_id)
    and (shared_with is null or auth.uid() = any (shared_with))
  );
-- (021's guard_prayer_item_update already stops a Witness changing anything
--  but prayed / answered, shared_with included.)


-- -----------------------------------------------------------------------------
-- C. Telling the Witnesses
-- -----------------------------------------------------------------------------
create table if not exists public.prayer_share_notices (
  id             uuid primary key default gen_random_uuid(),
  prayer_item_id uuid not null references public.prayer_items (id) on delete cascade,
  runner_id      uuid not null references public.profiles (id) on delete cascade,
  witness_id     uuid not null references public.profiles (id) on delete cascade,
  created_at     timestamptz not null default now()
);

comment on table public.prayer_share_notices is
  'One row per Witness a prayer was just shared with; each insert sends that '
  'Witness a push (push-notification-engine, event prayer_shared). No client access.';

create index if not exists prayer_share_notices_prayer_idx
  on public.prayer_share_notices (prayer_item_id);

alter table public.prayer_share_notices enable row level security;
revoke all on public.prayer_share_notices from public, anon, authenticated;
grant  all on public.prayer_share_notices to service_role;

-- The active Witnesses of p_runner who would see a prayer shared with p_ids
-- (null = all of them).
create or replace function public._prayer_audience(p_runner uuid, p_shared boolean, p_ids uuid[])
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select wp.witness_id
    from public.witness_pairings wp
   where p_shared
     and wp.runner_id = p_runner
     and wp.status = 'active'
     and (p_ids is null or wp.witness_id = any (p_ids));
$$;

revoke execute on function public._prayer_audience(uuid, boolean, uuid[]) from public, anon, authenticated;

-- After a prayer is added or changed: whoever can see it now and could not
-- before gets a notice row (and so a push). Never fails the prayer's write.
create or replace function public.notice_prayer_shared()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not new.share_with_witnesses or new.is_answered then
    return new;
  end if;

  insert into public.prayer_share_notices (prayer_item_id, runner_id, witness_id)
  select new.id, new.runner_id, w
    from public._prayer_audience(new.runner_id, new.share_with_witnesses, new.shared_with) w
  except
  select new.id, new.runner_id, w
    from public._prayer_audience(
           new.runner_id,
           case when tg_op = 'UPDATE' then old.share_with_witnesses else false end,
           case when tg_op = 'UPDATE' then old.shared_with else null end
         ) w;

  return new;
exception when others then
  raise warning 'notice_prayer_shared failed: % (SQLSTATE %)', sqlerrm, sqlstate;
  return new;
end;
$$;

revoke execute on function public.notice_prayer_shared() from public, anon, authenticated;

drop trigger if exists prayer_items_notice_shared on public.prayer_items;
create trigger prayer_items_notice_shared
  after insert or update of share_with_witnesses, shared_with on public.prayer_items
  for each row execute function public.notice_prayer_shared();

drop trigger if exists notify_push_on_prayer_share on public.prayer_share_notices;
create trigger notify_push_on_prayer_share
  after insert on public.prayer_share_notices
  for each row execute function public.notify_push_engine('prayer_shared');


-- =============================================================================
-- Checks (by hand, in the SQL editor)
-- =============================================================================
--   select column_name from information_schema.columns
--    where table_name = 'prayer_items' and column_name = 'shared_with';        -- one row
--   select has_table_privilege('authenticated', 'public.prayer_share_notices', 'select'); -- false
--
-- After sharing a prayer in the app:
--   select * from public.prayer_share_notices order by created_at desc limit 5;
-- =============================================================================
