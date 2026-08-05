-- ═══════════════════════════════════════════════════════════════════
-- Patch: Multi-tenant foundation — STEP 2 of 2 (the actual cutover)
-- Run this in Supabase → SQL Editor → New query.
--
-- DO NOT RUN THIS until:
--   1. patch-multi-tenant-schema.sql has been run, AND
--   2. every current staff login has a row in staff_access (see the
--      instructions at the bottom of that file).
--
-- This replaces "any logged-in staff sees everything" with "staff only see
-- their own tenant's data." If you run this before backfilling staff_access,
-- every current staff login will see empty tables until you fix it — not
-- destructive, but confusing and worth avoiding.
--
-- Right after running this, log in as an existing staff account and confirm
-- the Enforcement and Admin portals still show DuEast's data as before.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ── addresses ────────────────────────────────────────────────────────────────
-- Anon (residents) still need to read every address to resolve their
-- building from the URL — that policy is split out separately so it isn't
-- accidentally tied to the staff-only tenant scoping below.
DROP POLICY IF EXISTS "Addresses are public" ON addresses;

DROP POLICY IF EXISTS "Anon can read addresses" ON addresses;
CREATE POLICY "Anon can read addresses"
  ON addresses FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "Staff can read their tenant addresses" ON addresses;
CREATE POLICY "Staff can read their tenant addresses"
  ON addresses FOR SELECT TO authenticated USING (is_tenant_member(tenant_id));

-- ── visitor_registrations ────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Public can register visitors" ON visitor_registrations;
CREATE POLICY "Public can register visitors"
  ON visitor_registrations FOR INSERT TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Staff can view registrations" ON visitor_registrations;
CREATE POLICY "Staff can view their tenant registrations"
  ON visitor_registrations FOR SELECT TO authenticated USING (has_tenant_access(address_id));

DROP POLICY IF EXISTS "Staff can remove registrations" ON visitor_registrations;
CREATE POLICY "Staff can remove their tenant registrations"
  ON visitor_registrations FOR DELETE TO authenticated USING (has_tenant_access(address_id));

-- ── exemptions ───────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Staff can view exemptions" ON exemptions;
CREATE POLICY "Staff can view their tenant exemptions"
  ON exemptions FOR SELECT TO authenticated USING (has_tenant_access(address_id));

DROP POLICY IF EXISTS "Staff can add exemptions" ON exemptions;
CREATE POLICY "Staff can add their tenant exemptions"
  ON exemptions FOR INSERT TO authenticated WITH CHECK (has_tenant_access(address_id));

DROP POLICY IF EXISTS "Staff can update exemptions" ON exemptions;
CREATE POLICY "Staff can update their tenant exemptions"
  ON exemptions FOR UPDATE TO authenticated USING (has_tenant_access(address_id));

DROP POLICY IF EXISTS "Staff can delete exemptions" ON exemptions;
CREATE POLICY "Staff can delete their tenant exemptions"
  ON exemptions FOR DELETE TO authenticated USING (has_tenant_access(address_id));

-- ── unit_codes ───────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Staff can manage unit codes" ON unit_codes;
CREATE POLICY "Staff can manage their tenant unit codes"
  ON unit_codes FOR ALL TO authenticated
  USING (has_tenant_access(address_id)) WITH CHECK (has_tenant_access(address_id));

COMMIT;

-- ── Verify ────────────────────────────────────────────────────────────────
-- SELECT policyname, cmd, roles FROM pg_policies
-- WHERE tablename IN ('addresses','visitor_registrations','exemptions','unit_codes')
-- ORDER BY tablename, cmd;
