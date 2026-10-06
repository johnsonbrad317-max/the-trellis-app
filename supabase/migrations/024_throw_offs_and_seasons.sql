-- =============================================================================
-- 024  Sins to throw off, and the season-end week
-- =============================================================================
-- Two things the Rule of Life learned from the second beta round:
--
--   A. Hebrews 12:1 names two movements — throwing off what hinders, and running
--      with perseverance. The Rule of Life now has both: rhythms to practice
--      (the five categories, as before) and sins to throw off. A throw-off is
--      an ordinary rule_item with is_throw_off = true: the title is the blank in
--      "Avoid ___", the app always makes it daily, and the check-in asks "Did
--      you avoid ___?" so that "Yes" is growth for every rhythm alike. Scoring,
--      roll-ups, Anchor alerts and the Witness's view need no change: a kept
--      throw-off is a check_in with completed = true like any other.
--
--   B. A season of the Rule of Life is 180 days. Each time a season ends, the
--      whole Rule of Life opens for 7 days — the Runner may tweak it or leave it
--      as it is, without a Witness's approval — and is then set again for the
--      next season. 021's rule_item_is_locked learns that calendar; nothing else
--      about "set" changes (first-week settle, Witness unlocks, DNA Rhythms).
--
-- Idempotent. Re-creates rule_item_is_locked (021) and guard_rule_item_insert /
-- guard_rule_item_update (021, re-created in 023). If 021 or 023 is ever run
-- again, run this file again afterwards. Nothing in 019's allowlist changes.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- A. Sins to throw off
-- -----------------------------------------------------------------------------
-- A.1  The flag. Default false: every existing rhythm is a practice.
alter table public.rule_items
  add column if not exists is_throw_off boolean not null default false;

comment on column public.rule_items.is_throw_off is
  'A sin to throw off (Hebrews 12:1) rather than a practice to keep. The title '
  'is the blank in "Avoid ___"; the app keeps it daily and asks "Did you avoid '
  '___?" at check-in. Fixed when the rhythm is added.';

-- Reading: rule_items SELECT is table-wide (002), so the owner and their
-- Witness can already read it; stated anyway. Writing: a client sets it only at
-- insert (INSERT is table-wide too); A.2 keeps it from changing afterwards.
grant select (is_throw_off) on public.rule_items to authenticated;

-- A.2  023's guard_rule_item_update with is_throw_off added to the never-
--      changeable list. Everything 021 and 023 put there is kept, with the same
--      messages. Invoker-rights, as before: it has to see the real current_user.
create or replace function public.guard_rule_item_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.id                  is distinct from old.id
       or new.runner_id        is distinct from old.runner_id
       or new.category         is distinct from old.category
       or new.is_church_mandated is distinct from old.is_church_mandated
       or new.is_throw_off     is distinct from old.is_throw_off
       or new.created_at       is distinct from old.created_at
       or new.unlocked_until   is distinct from old.unlocked_until
       or new.dna_rhythm_id    is distinct from old.dna_rhythm_id then
      raise exception 'That field on a rhythm can''t be changed directly.'
        using errcode = '42501';
    end if;

    if    new.title            is distinct from old.title
       or new.frequency        is distinct from old.frequency
       or new.weekly_days      is distinct from old.weekly_days
       or new.is_anchor_rhythm is distinct from old.is_anchor_rhythm then

      if old.is_church_mandated then
        raise exception 'This is a DNA Rhythm; ask your Witness to unlock it first.'
          using errcode = '42501';
      end if;

      if coalesce(public.rule_item_is_locked(old.id), true) then
        raise exception 'This rhythm is set. Ask a Witness to unlock it before changing it.'
          using errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function public.guard_rule_item_update() from public, anon;
grant  execute on function public.guard_rule_item_update() to authenticated, service_role;
-- (011's rule_items_guard_update trigger already calls this.)

-- A.3  A throw-off is always daily. 023's guard_rule_item_insert plus two lines,
--      so a client cannot save a weekly or monthly throw-off by mistake (the app
--      never offers to).
create or replace function public.guard_rule_item_insert()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.created_at     := now();
    new.unlocked_until := null;
    new.dna_rhythm_id  := null;
  end if;
  if new.is_throw_off then
    new.frequency   := 'daily';
    new.weekly_days := '{}';
  end if;
  return new;
end;
$$;

revoke execute on function public.guard_rule_item_insert() from public, anon;
grant  execute on function public.guard_rule_item_insert() to authenticated, service_role;
-- (021's rule_items_guard_insert trigger already calls this.)


-- -----------------------------------------------------------------------------
-- B. The season-end week
-- -----------------------------------------------------------------------------
-- 021's rule_item_is_locked, with one more reason for "not locked": the Runner is
-- in a season-end window. Counting from rule_committed_at, a season is 180 days;
-- the first 7 days of every season after the first are open. (The first week of
-- the FIRST season is the settle period, already handled by the 7-day line.)
-- Same privilege and visibility rules as 021: answers only for the owner or one
-- of their active Witnesses, NULL to anyone else; the service role may ask about
-- any rhythm. The app mirrors this calendar in RuleItem.isSetAt.
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
  v_committed      boolean;
  v_committed_at   timestamptz;
  v_since          interval;
  v_into_season    interval;
begin
  select ri.runner_id, ri.created_at, ri.unlocked_until
    into v_runner_id, v_created_at, v_unlocked_until
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

  select p.has_committed_rule, p.rule_committed_at
    into v_committed, v_committed_at
    from public.profiles p
   where p.id = v_runner_id;

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

  return now() >= greatest(v_committed_at, v_created_at) + interval '7 days'
     and exists (
           select 1 from public.witness_pairings wp
            where wp.runner_id = v_runner_id and wp.status = 'active'
         )
     and not (v_unlocked_until is not null and v_unlocked_until > now());
end;
$$;

revoke execute on function public.rule_item_is_locked(uuid) from public, anon;
grant  execute on function public.rule_item_is_locked(uuid) to authenticated, service_role;


-- -----------------------------------------------------------------------------
-- C. Verification (SQL editor; nothing here changes data)
-- -----------------------------------------------------------------------------
-- 1. The column exists, defaults false, clients can read it:
--   select column_default from information_schema.columns
--    where table_name = 'rule_items' and column_name = 'is_throw_off';        -- false
--   select has_column_privilege('authenticated', 'public.rule_items', 'is_throw_off', 'select'); -- true
--
-- 2. A throw-off is forced daily on insert (rolled back):
--   begin;
--   insert into public.rule_items (runner_id, category, title, frequency, weekly_days, is_throw_off)
--   select id, 'body_purity', 'looking at pornography', 'weekly', '{1,3}', true
--     from public.profiles limit 1
--   returning frequency, weekly_days;                                        -- daily, {}
--   rollback;
--
-- 3. The season calendar (pure arithmetic, no rows needed) — expect
--    false, true, false, true, false:
--   select (i >= interval '180 days'
--           and (i - interval '180 days' * floor(extract(epoch from i) / extract(epoch from interval '180 days')))
--               < interval '7 days') as reopen
--     from unnest(array[
--       interval '3 days', interval '181 days', interval '200 days',
--       interval '362 days', interval '367 days 1 hour']) as i;
--
-- 4. Triggers still attached:
--   select tgname from pg_trigger where tgrelid = 'public.rule_items'::regclass and not tgisinternal;
--   -- includes rule_items_guard_insert and rule_items_guard_update
