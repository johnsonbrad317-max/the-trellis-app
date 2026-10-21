-- =============================================================================
-- The Trellis — 036_starter_rules_save.sql   (starter Rules with a throw-off)
-- =============================================================================
-- Run after 035. Idempotent — safe to run more than once. Fixes the installed
-- iPhone builds at once; the next build fixes it in the app as well.
--
-- Choosing a starter Rule saves all its rhythms in one insert. The app sent
-- is_throw_off only on the throw-off rows, and in a batch PostgREST sets a
-- column that some rows leave out to NULL in the others. is_throw_off is NOT
-- NULL, so every starter Rule that includes a throw-off (five of the seven)
-- failed to save with "Couldn't add that Rule."
--
-- 024's guard_rule_item_insert, plus one line: a missing is_throw_off means
-- "not a throw-off". BEFORE triggers run before NOT NULL is checked, so the
-- row now saves.
-- =============================================================================

create or replace function public.guard_rule_item_insert()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.is_throw_off := coalesce(new.is_throw_off, false);
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
-- (021's rule_items_guard_insert BEFORE INSERT trigger already calls this.)

-- Check: as a new Runner in the app, choose "Working Parent" -> it saves.
