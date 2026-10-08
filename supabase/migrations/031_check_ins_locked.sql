-- =============================================================================
-- The Trellis — 031_check_ins_locked.sql   (a day's check-in is locked in)
-- =============================================================================
-- Run after 030. Idempotent — safe to run more than once.
--
-- Until now the app saved check-ins with an UPSERT, so a Runner could open
-- the Daily Check-In again and resubmit the same day with different answers.
-- A check-in is now locked in once given: the app INSERTs, and this file takes
-- away the Runner's ability to change a row afterwards. A second submission
-- for the same day hits the (rule_item_id, check_in_date) unique key and is
-- refused; the app shows the answers already given instead.
--
-- Older TestFlight builds still upsert: on a day already checked in they now
-- get an error ("Network error — couldn't submit") instead of overwriting.
-- First-time check-ins from those builds are unaffected (an upsert with no
-- conflict is a plain insert).
-- =============================================================================

drop policy if exists "check_ins_update_own" on public.check_ins;
revoke update on public.check_ins from authenticated, anon;

-- Check (expect false):
--   select has_table_privilege('authenticated', 'public.check_ins', 'update');
