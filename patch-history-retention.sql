-- ═══════════════════════════════════════════════════════════════════
-- Migration: 3-year retention for visitor_registrations
--
-- Registration history (active + expired) now feeds the Admin > Registration
-- History screen, so rows are no longer deleted on expiry. This sets a
-- deliberate retention limit instead of keeping everything forever by
-- default: a nightly job permanently deletes any registration older than
-- 3 years, measured from when it was registered (not when it expired).
--
-- Run this once in the Supabase SQL Editor (Project → SQL Editor).
-- Safe to re-run — scheduling a job with the same name updates it in place.
-- ═══════════════════════════════════════════════════════════════════

-- 1. Enable the pg_cron extension (no-op if already enabled).
--    If this errors with a permissions message, enable it instead via
--    Supabase Dashboard → Database → Extensions → search "pg_cron" → Enable,
--    then re-run just the cron.schedule() call below.
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 2. Schedule the nightly purge — runs at 3:00 AM server time every day.
SELECT cron.schedule(
  'purge-visitor-registrations-3yr',
  '0 3 * * *',
  $$DELETE FROM visitor_registrations WHERE registered_at < NOW() - INTERVAL '3 years'$$
);

-- ── Verifying it worked ──────────────────────────────────────────────
-- List scheduled jobs:
--   SELECT * FROM cron.job;
-- List recent run history once it's had a chance to run:
--   SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;

-- ── To remove this job later ─────────────────────────────────────────
--   SELECT cron.unschedule('purge-visitor-registrations-3yr');
