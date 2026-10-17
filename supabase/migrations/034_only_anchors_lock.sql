-- =============================================================================
-- The Trellis — 034_only_anchors_lock.sql   (only Anchor Rhythms are set)
-- =============================================================================
-- Run after 033. Idempotent — safe to run more than once.
--
-- Until now every rhythm became "set" a week after it counted: changing or
-- removing any of them needed a Witness to unlock it. That was too tight — a
-- fast moved to another day, or exercise dropped in a season with no room for
-- it, should not need permission. Now:
--
--   * Anchor Rhythms (and church DNA rhythms) are set exactly as before.
--   * Every other rhythm can be renamed, rescheduled, made an Anchor, or
--     removed at any time. Un-anchoring an Anchor still needs the Witness:
--     the rhythm is an Anchor until the change lands.
--   * Removing a rhythm that WOULD have been set leaves each active Witness a
--     one-time note in the app ("Brad removed a rhythm: Exercise for 30
--     Minutes") and a push that names no rhythm ("Brad removed a rhythm from
--     their Rule of Life."). Removing one in its first week, before
--     committing, or during a season-end week says nothing — that is tuning.
--
--   A. _rhythm_settled(...) — 024's "set" calendar, on its own.
--   B. rule_item_is_locked — the same calendar, for Anchors and DNA only.
--   C. witness_notices learns a second kind, 'rhythm_removed', with the
--      rhythm's title in a new `detail` column; get_my_witness_notices
--      returns it. Its push goes through the engine's 'rhythm_removed' event.
--   D. The note is written by an AFTER DELETE trigger, only for a delete the
--      Runner made from the app (not a church merge or retirement, not an
--      account deletion).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- A. When a rhythm has settled (024's rule, unchanged)
-- -----------------------------------------------------------------------------
create or replace function public._rhythm_settled(
  p_runner_id      uuid,
  p_created_at     timestamptz,
  p_unlocked_until timestamptz
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_committed    boolean;
  v_committed_at timestamptz;
  v_since        interval;
  v_into_season  interval;
begin
  select p.has_committed_rule, p.rule_committed_at
    into v_committed, v_committed_at
    from public.profiles p
   where p.id = p_runner_id;

  if not coalesce(v_committed, false) or v_committed_at is null then
    return false;
  end if;

  -- Season-end window: at least one full season since committing, and within
  -- the first 7 days of the current season.
  v_since := now() - v_committed_at;
  if v_since >= interval '180 days' then
    v_into_season := v_since
      - (interval '180 days' * floor(extract(epoch from v_since) / extract(epoch from interval '180 days')));
    if v_into_season < interval '7 days' then
      return false;
    end if;
  end if;

  return now() >= greatest(v_committed_at, p_created_at) + interval '7 days'
     and exists (
           select 1 from public.witness_pairings wp
            where wp.runner_id = p_runner_id and wp.status = 'active'
         )
     and not (p_unlocked_until is not null and p_unlocked_until > now());
end;
$$;

revoke execute on function public._rhythm_settled(uuid, timestamptz, timestamptz)
  from public, anon, authenticated;


-- -----------------------------------------------------------------------------
-- B. Locked = settled, for Anchors and church rhythms only
-- -----------------------------------------------------------------------------
create or replace function public.rule_item_is_locked(p_rule_item_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_runner_id      uuid;
  v_created_at     timestamptz;
  v_unlocked_until timestamptz;
  v_anchor         boolean;
  v_church         boolean;
begin
  select ri.runner_id, ri.created_at, ri.unlocked_until, ri.is_anchor_rhythm, ri.is_church_mandated
    into v_runner_id, v_created_at, v_unlocked_until, v_anchor, v_church
    from public.rule_items ri
   where ri.id = p_rule_item_id;

  if not found then
    return null;
  end if;

  if auth.uid() is not null
     and v_runner_id is distinct from auth.uid()
     and not public.is_witness_of(v_runner_id) then
    return null;
  end if;

  if not (coalesce(v_anchor, false) or coalesce(v_church, false)) then
    return false;
  end if;

  return public._rhythm_settled(v_runner_id, v_created_at, v_unlocked_until);
end;
$$;

revoke execute on function public.rule_item_is_locked(uuid) from public, anon;
grant  execute on function public.rule_item_is_locked(uuid) to authenticated, service_role;
-- (023/024's guard_rule_item_update and 021's guard_rule_item_delete already
--  ask this function, so they follow without being rewritten.)


-- -----------------------------------------------------------------------------
-- C. A second kind of Witness note
-- -----------------------------------------------------------------------------
alter table public.witness_notices
  add column if not exists detail text;

alter table public.witness_notices
  drop constraint if exists witness_notices_kind_known;
alter table public.witness_notices
  add constraint witness_notices_kind_known
  check (kind in ('runner_left', 'rhythm_removed'));

alter table public.witness_notices
  drop constraint if exists witness_notices_detail_short;
alter table public.witness_notices
  add constraint witness_notices_detail_short
  check (detail is null or length(detail) <= 200);

alter table public.witness_notices
  add column if not exists runner_id uuid references public.profiles (id) on delete cascade;

comment on column public.witness_notices.detail is
  'rhythm_removed: the removed rhythm''s title. Null for runner_left.';

-- The same note, now with its detail. (Dropped first: the return type changes.)
drop function if exists public.get_my_witness_notices();
create function public.get_my_witness_notices()
returns table (id uuid, kind text, runner_first_name text, detail text, created_at timestamptz)
language plpgsql
security definer
stable
set search_path = public
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'You must be signed in.'
      using errcode = '28000';
  end if;

  return query
    select n.id, n.kind, n.runner_first_name, n.detail, n.created_at
      from public.witness_notices n
     where n.witness_id = v_me
       and n.seen_at is null
       and n.created_at > now() - interval '30 days'
     order by n.created_at desc
     limit 20;
end;
$$;

comment on function public.get_my_witness_notices() is
  'The caller''s unseen witness_notices (id, kind, runner_first_name, detail, '
  'created_at), newest first, none older than 30 days, at most 20.';

revoke execute on function public.get_my_witness_notices() from public, anon;
grant  execute on function public.get_my_witness_notices() to authenticated;

-- A removed-rhythm note is also a push (the departure note's push is sent by
-- delete-account itself, so only this kind is wired here). The push names no
-- rhythm; the note in the app does.
drop trigger if exists notify_push_on_rhythm_removed on public.witness_notices;
create trigger notify_push_on_rhythm_removed
  after insert on public.witness_notices
  for each row
  when (new.kind = 'rhythm_removed')
  execute function public.notify_push_engine('rhythm_removed');


-- -----------------------------------------------------------------------------
-- D. Writing the note
-- -----------------------------------------------------------------------------
-- Security definer (a Runner cannot write witness_notices), and only ever
-- about the caller's own rhythm, to the caller's own active Witnesses, and
-- only when the rhythm had settled. At most 10 notes' worth an hour, so it
-- cannot be used to flood a Witness.
create or replace function public._note_rhythm_removed(
  p_runner_id      uuid,
  p_created_at     timestamptz,
  p_unlocked_until timestamptz,
  p_title          text,
  p_throw_off      boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_first   text;
  v_title   text := left(btrim(coalesce(p_title, '')), 190);
  v_allowed boolean;
begin
  if p_runner_id is null or p_runner_id is distinct from auth.uid() then
    return;
  end if;
  if not public._rhythm_settled(p_runner_id, p_created_at, p_unlocked_until) then
    return;
  end if;

  select r.allowed into v_allowed
    from public.edge_rate_limit_hit('rhythm-removed:' || p_runner_id::text, 10, 3600) r;
  if not coalesce(v_allowed, false) then
    return;
  end if;

  select public.departure_first_name(p.name) into v_first
    from public.profiles p where p.id = p_runner_id;

  insert into public.witness_notices (witness_id, kind, runner_first_name, detail, runner_id)
  select wp.witness_id,
         'rhythm_removed',
         coalesce(v_first, 'Your Runner'),
         case when p_throw_off then 'Avoid ' || v_title else v_title end,
         p_runner_id
    from public.witness_pairings wp
   where wp.runner_id = p_runner_id
     and wp.status = 'active';
end;
$$;

revoke execute on function public._note_rhythm_removed(uuid, timestamptz, timestamptz, text, boolean)
  from public, anon;
grant  execute on function public._note_rhythm_removed(uuid, timestamptz, timestamptz, text, boolean)
  to authenticated;

-- Invoker rights on purpose: current_user tells a delete the Runner made from
-- the app (authenticated) from one made inside a church merge or retirement
-- (those run as the definer) or by the service role (account deletion).
create or replace function public.note_rhythm_removed()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user = 'authenticated' and not old.is_church_mandated then
    begin
      perform public._note_rhythm_removed(
        old.runner_id, old.created_at, old.unlocked_until, old.title, old.is_throw_off
      );
    exception when others then
      -- A note that can't be written must never undo the removal.
      raise warning 'note_rhythm_removed failed: % (SQLSTATE %)', sqlerrm, sqlstate;
    end;
  end if;
  return old;
end;
$$;

drop trigger if exists rule_items_note_removed on public.rule_items;
create trigger rule_items_note_removed
  after delete on public.rule_items
  for each row execute function public.note_rhythm_removed();


-- =============================================================================
-- Checks (by hand)
-- =============================================================================
--   A non-Anchor rhythm a month old, Witness paired:
--     select public.rule_item_is_locked('<id>');                 -- false
--   An Anchor one:                                                    -- true
--   After removing the first from the app:
--     select kind, runner_first_name, detail from public.witness_notices
--      order by created_at desc limit 3;                              -- rhythm_removed
-- =============================================================================


-- -----------------------------------------------------------------------------
-- E. "Be done with work by 6 PM" read as "Did you be done with work…?"
-- -----------------------------------------------------------------------------
-- The preset and starter Rule now say "Finish work by 6 PM"; this renames the
-- ones already saved (the Runner's own rhythms only).
update public.rule_items
   set title = case when left(title, 1) = 'B' then 'Finish Work by 6 PM' else 'finish work by 6 PM' end
 where title ~* '^\s*be done with work by 6\s*pm\s*$'
   and not is_church_mandated;
