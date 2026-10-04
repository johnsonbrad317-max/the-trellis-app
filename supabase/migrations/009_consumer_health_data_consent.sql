-- =============================================================================
-- 009 — MHMDA (Washington My Health My Data Act) collection consent.
-- =============================================================================
-- A persisted record that a Runner affirmatively consented before The
-- Trellis ever collected their Consumer Health Data (spiritual rhythms,
-- prayer requests, check-ins). Set once, from
-- health_data_consent_screen.dart, between account creation and the first
-- write to rule_items/prayer_items/check_ins — see
-- RunnerProfile.recordConsumerHealthDataConsent and
-- role_selection_screen.dart's _beginJourney.
--
-- No new RLS policy needed: profiles_update_self (init_schema.sql) already
-- lets an authenticated user update their own row, same as every other
-- self-service profile field (has_committed_rule, calendar_connected, …).
alter table public.profiles
  add column if not exists consumer_health_data_consent boolean not null default false;
