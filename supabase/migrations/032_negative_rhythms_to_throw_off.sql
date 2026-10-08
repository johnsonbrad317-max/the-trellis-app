-- =============================================================================
-- The Trellis — 032_negative_rhythms_to_throw_off.sql
-- =============================================================================
-- Run after 031. Idempotent — safe to run more than once.
--
-- A rhythm named as something NOT to do ("No Checking Work Email After Hours",
-- "Abstain from Alcohol") was being asked as "Did you no checking…?". Those
-- belong with the sins to throw off, asked as "Did you avoid ___?". The app now
-- sorts them there when they are added (RuleItem sortRhythm, and the presets
-- moved); this moves the ones already saved: the leading "No" / "Avoid" /
-- "Abstain from" / "Refrain from" / "Don't" / "Do not" comes off the title,
-- the rest is lower-cased (it is read mid-sentence), and it becomes a daily
-- throw-off like every other. Church (DNA) rhythms are left alone.
--
-- Past check-ins on these rhythms are kept as they are.
-- =============================================================================

with sorted as (
  select id,
         lower(btrim(regexp_replace(
           title,
           '^\s*(avoid|no|abstain from|refrain from|don''t|don’t|do not)\s+',
           '',
           'i'
         ))) as new_title
    from public.rule_items
   where not is_throw_off
     and not is_church_mandated
     and dna_rhythm_id is null
     and title ~* '^\s*(avoid|no|abstain from|refrain from|don''t|don’t|do not)\s+\S'
)
update public.rule_items r
   set title        = s.new_title,
       is_throw_off = true,
       frequency    = 'daily',
       weekly_days  = '{}'
  from sorted s
 where r.id = s.id;

-- Check (expect no rows):
--   select id, title from public.rule_items
--    where not is_throw_off and title ~* '^\s*(avoid|no|abstain from|refrain from|don''t|do not)\s';
