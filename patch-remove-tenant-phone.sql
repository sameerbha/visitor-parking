-- ═══════════════════════════════════════════════════════════════════
-- Migration: remove tenant_phone from visitor_registrations
--
-- We no longer collect or store a resident's phone number as part of
-- visitor registration. Run this once in the Supabase SQL Editor
-- (Project → SQL Editor) against an existing database that still has
-- the tenant_phone column from earlier versions of this app.
--
-- This is a destructive, irreversible change: any phone numbers already
-- stored in this column will be permanently deleted when it is dropped.
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE visitor_registrations
  DROP COLUMN IF EXISTS tenant_phone;
