-- ═══════════════════════════════════════════════════════════════════
-- Patch: Multi-tenant foundation — STEP 1 of 2 (additive, safe to run any time)
-- Run this in Supabase → SQL Editor → New query.
--
-- This step ONLY adds new tables/columns/functions and backfills existing
-- data. It does NOT change any existing RLS policy, so nothing about how
-- staff currently log in and see data changes yet. That happens in
-- patch-multi-tenant-cutover.sql (step 2), which you should NOT run until
-- you've completed the staff backfill instructions at the bottom of this
-- file — running step 2 before backfilling staff_access will lock every
-- current staff login out of their own data.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. New tables ────────────────────────────────────────────────────────────

-- A tenant is a paying customer (a condo corporation / management company).
-- A tenant can own multiple addresses (e.g. DuEast owns both its towers).
CREATE TABLE IF NOT EXISTS tenants (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT NOT NULL,
  subdomain    TEXT UNIQUE NOT NULL,          -- e.g. 'dueast' for dueast.regentparking.ca
  contact_text TEXT,                          -- e.g. "Contact Property Management at ..."
  status       TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','trial')),
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- Which staff logins belong to which tenant. A join table (not one-to-one)
-- so a single login could belong to more than one tenant later if a
-- management company ever runs multiple buildings under you.
CREATE TABLE IF NOT EXISTS staff_access (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id  UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, tenant_id)
);

-- Platform admins (you) can see and manage every tenant. A simple allow-list —
-- there is no self-service way to add rows here; it's done manually in the
-- SQL Editor (see the bottom of this file), same as the very first staff
-- account ever was.
CREATE TABLE IF NOT EXISTS platform_admins (
  user_id    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── 2. addresses gets a tenant ───────────────────────────────────────────────

ALTER TABLE addresses ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE;

-- ── 3. Backfill: DuEast becomes tenant #1 ────────────────────────────────────
-- Safe to re-run — ON CONFLICT / WHERE NULL guards make this a no-op the
-- second time.

INSERT INTO tenants (name, subdomain, contact_text)
VALUES ('DuEast', 'dueast', NULL)
ON CONFLICT (subdomain) DO NOTHING;

UPDATE addresses
SET tenant_id = (SELECT id FROM tenants WHERE subdomain = 'dueast')
WHERE tenant_id IS NULL;

-- ── 4. Helper functions used by RLS policies (step 2) and the app ───────────
-- All SECURITY DEFINER so they can read staff_access/platform_admins/addresses
-- internally regardless of the calling user's own RLS visibility into those
-- tables — otherwise checking access would require access, which is circular.

CREATE OR REPLACE FUNCTION is_platform_admin()
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE
AS $$
  SELECT EXISTS (SELECT 1 FROM platform_admins WHERE user_id = auth.uid());
$$;
GRANT EXECUTE ON FUNCTION is_platform_admin TO authenticated;

CREATE OR REPLACE FUNCTION is_tenant_member(p_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE
AS $$
  SELECT is_platform_admin() OR EXISTS (
    SELECT 1 FROM staff_access WHERE user_id = auth.uid() AND tenant_id = p_tenant_id
  );
$$;
GRANT EXECUTE ON FUNCTION is_tenant_member TO authenticated;

CREATE OR REPLACE FUNCTION has_tenant_access(p_address_id UUID)
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE
AS $$
  SELECT is_platform_admin() OR EXISTS (
    SELECT 1 FROM addresses a
    JOIN staff_access sa ON sa.tenant_id = a.tenant_id
    WHERE a.id = p_address_id AND sa.user_id = auth.uid()
  );
$$;
GRANT EXECUTE ON FUNCTION has_tenant_access TO authenticated;

-- ── 5a. List a tenant's staff with their email, for the platform admin
-- portal. staff_access only stores user_id — email lives in auth.users,
-- which the client can never query directly, so this SECURITY DEFINER
-- function looks it up on the portal's behalf.

CREATE OR REPLACE FUNCTION get_tenant_staff(p_tenant_id UUID)
RETURNS TABLE (staff_access_id UUID, user_id UUID, email TEXT, created_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  IF NOT is_tenant_member(p_tenant_id) THEN
    RAISE EXCEPTION 'Not authorized for this tenant';
  END IF;

  RETURN QUERY
    SELECT sa.id, sa.user_id, u.email::TEXT, sa.created_at
    FROM staff_access sa
    JOIN auth.users u ON u.id = sa.user_id
    WHERE sa.tenant_id = p_tenant_id
    ORDER BY u.email;
END;
$$;
GRANT EXECUTE ON FUNCTION get_tenant_staff TO authenticated;

-- ── 5. Per-tenant usage stats, for the platform admin portal ─────────────────

CREATE OR REPLACE FUNCTION get_tenant_usage_stats(p_tenant_id UUID)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_month_start TIMESTAMPTZ := date_trunc('month', NOW());
  v_registrations_this_month INT;
  v_active_units INT;
  v_address_count INT;
BEGIN
  IF NOT is_tenant_member(p_tenant_id) THEN
    RAISE EXCEPTION 'Not authorized for this tenant';
  END IF;

  SELECT COUNT(*) INTO v_registrations_this_month
  FROM visitor_registrations vr
  JOIN addresses a ON a.id = vr.address_id
  WHERE a.tenant_id = p_tenant_id
    AND vr.registered_at >= v_month_start;

  SELECT COUNT(*) INTO v_active_units
  FROM unit_codes uc
  JOIN addresses a ON a.id = uc.address_id
  WHERE a.tenant_id = p_tenant_id;

  SELECT COUNT(*) INTO v_address_count
  FROM addresses WHERE tenant_id = p_tenant_id;

  RETURN json_build_object(
    'registrationsThisMonth', v_registrations_this_month,
    'activeUnits',            v_active_units,
    'addressCount',           v_address_count
  );
END;
$$;
GRANT EXECUTE ON FUNCTION get_tenant_usage_stats TO authenticated;

-- ── 6. RLS for the new tables ────────────────────────────────────────────────

ALTER TABLE tenants       ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_access  ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform_admins ENABLE ROW LEVEL SECURITY;

-- tenants: anon needs to read subdomain/name (the resident-facing page
-- resolves its tenant from the URL's hostname before anyone logs in).
-- Nothing in this table is sensitive — no plates, no unit codes, no codes.
DROP POLICY IF EXISTS "Anon can read tenants for subdomain resolution" ON tenants;
CREATE POLICY "Anon can read tenants for subdomain resolution"
  ON tenants FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "Staff can read their own tenant" ON tenants;
CREATE POLICY "Staff can read their own tenant"
  ON tenants FOR SELECT TO authenticated USING (is_tenant_member(id));

DROP POLICY IF EXISTS "Platform admins manage tenants" ON tenants;
CREATE POLICY "Platform admins manage tenants"
  ON tenants FOR ALL TO authenticated USING (is_platform_admin()) WITH CHECK (is_platform_admin());

-- staff_access / platform_admins: platform admins only. Regular staff never
-- read these tables directly — get_tenant_usage_stats() and the app's own
-- "which tenant am I" check go through SECURITY DEFINER functions instead.
DROP POLICY IF EXISTS "Platform admins manage staff access" ON staff_access;
CREATE POLICY "Platform admins manage staff access"
  ON staff_access FOR ALL TO authenticated USING (is_platform_admin()) WITH CHECK (is_platform_admin());

DROP POLICY IF EXISTS "Platform admins manage platform admins" ON platform_admins;
CREATE POLICY "Platform admins manage platform admins"
  ON platform_admins FOR ALL TO authenticated USING (is_platform_admin()) WITH CHECK (is_platform_admin());

-- addresses: platform admins can create/edit/delete addresses (building
-- staff never create buildings). The existing "Addresses are public" SELECT
-- policy is untouched here — that gets replaced with the tenant-scoped
-- version in step 2, once staff_access is backfilled.
DROP POLICY IF EXISTS "Platform admins manage addresses" ON addresses;
CREATE POLICY "Platform admins manage addresses"
  ON addresses FOR ALL TO authenticated USING (is_platform_admin()) WITH CHECK (is_platform_admin());

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- NEXT STEPS — do these before running patch-multi-tenant-cutover.sql
-- ═══════════════════════════════════════════════════════════════════
--
-- 1. Find your existing staff logins' user IDs. Run this separately:
--
--      SELECT id, email FROM auth.users ORDER BY email;
--
-- 2. Find your own user ID from that list, and make yourself the first
--    platform admin:
--
--      INSERT INTO platform_admins (user_id) VALUES ('paste-your-user-id-here');
--
-- 3. Backfill every EXISTING staff login onto the DuEast tenant, so nobody
--    loses access once step 2 turns on tenant-scoped RLS. Repeat the INSERT
--    for each staff user ID from step 1 (your own included, unless you'd
--    rather rely on the platform-admin override, which already sees
--    everything — but adding yourself here too doesn't hurt):
--
--      INSERT INTO staff_access (user_id, tenant_id)
--      VALUES (
--        'paste-a-staff-user-id-here',
--        (SELECT id FROM tenants WHERE subdomain = 'dueast')
--      );
--
-- 4. Once every current staff login has a staff_access row, run
--    patch-multi-tenant-cutover.sql.
-- ═══════════════════════════════════════════════════════════════════
