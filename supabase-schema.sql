-- ═══════════════════════════════════════════════════════════════════
-- Visitors Parking Management — Supabase Schema  (v2.0.0 — multi-tenant)
-- Run this entire file in the Supabase SQL Editor (Project → SQL Editor).
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Tables ───────────────────────────────────────────────────────────────

-- A tenant is a paying customer — a condo corporation or management company.
-- A tenant can own multiple addresses (e.g. one tenant, two towers).
-- See patch-multi-tenant-schema.sql / patch-multi-tenant-cutover.sql for the
-- migration that added multi-tenancy to earlier single-tenant installs.
CREATE TABLE tenants (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name               TEXT NOT NULL,
  subdomain          TEXT UNIQUE NOT NULL,
  contact_text       TEXT,
  status             TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','trial')),
  -- Configurable per tenant — see Admin's Settings tab. Defaults match the
  -- original fixed limits so nothing changes until a tenant edits them.
  monthly_pass_limit INT NOT NULL DEFAULT 10 CHECK (monthly_pass_limit >= 1),
  plate_day_limit    INT NOT NULL DEFAULT 7  CHECK (plate_day_limit >= 1),
  created_at         TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE addresses (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  UUID REFERENCES tenants(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  lot_code   TEXT UNIQUE NOT NULL,
  full_name  TEXT GENERATED ALWAYS AS (name || ' (' || lot_code || ')') STORED,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Which staff logins belong to which tenant. A join table so one login could
-- belong to more than one tenant (e.g. a management company running several
-- buildings under Regent Parking).
CREATE TABLE staff_access (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id  UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, tenant_id)
);

-- Platform admins (Regent Parking staff) see and manage every tenant. A
-- simple allow-list — rows are only ever added manually in the SQL Editor.
CREATE TABLE platform_admins (
  user_id    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE visitor_registrations (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  address_id       UUID REFERENCES addresses(id) ON DELETE CASCADE,
  lot_code         TEXT NOT NULL,
  unit_number      TEXT NOT NULL,
  visitor_plate    TEXT NOT NULL,
  registered_at    TIMESTAMPTZ DEFAULT NOW(),
  expires_at       TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
  extension_count  INT NOT NULL DEFAULT 0
);
-- Note: no phone number field, by design — we don't collect or store
-- visitor/tenant phone numbers. See patch-remove-tenant-phone.sql for the
-- migration that dropped this column from earlier installs.
-- extension_count: incremented each time extend_visitor_registration() grants
-- another 24 hours on this same row. get_monthly_pass_stats() counts each
-- extension as its own pass, same as the original registration — see
-- patch-fix-pass-counting.sql for the migration that added this on existing
-- installs.

CREATE TABLE exemptions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  address_id  UUID REFERENCES addresses(id) ON DELETE CASCADE,
  plate       TEXT NOT NULL,
  notes       TEXT,
  start_date  DATE NOT NULL,
  end_date    DATE NOT NULL,
  entered_by  TEXT NOT NULL DEFAULT 'BuildingStaff',
  entry_date  DATE DEFAULT CURRENT_DATE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Unit codes: one per unit, used by residents to authenticate on the
-- registration form. Never exposed directly to unauthenticated clients.
CREATE TABLE unit_codes (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  address_id   UUID REFERENCES addresses(id) ON DELETE CASCADE,
  unit_number  TEXT NOT NULL,
  code         TEXT NOT NULL,
  created_by   TEXT NOT NULL DEFAULT 'BuildingStaff',
  created_date DATE DEFAULT CURRENT_DATE,
  last_reset   DATE DEFAULT CURRENT_DATE,
  UNIQUE(address_id, unit_number)
);

-- ── 2. Indexes ───────────────────────────────────────────────────────────────

CREATE INDEX idx_visitor_plate   ON visitor_registrations(visitor_plate);
CREATE INDEX idx_visitor_address ON visitor_registrations(address_id, expires_at);
CREATE INDEX idx_exemption_plate ON exemptions(plate);
CREATE INDEX idx_exemption_addr  ON exemptions(address_id, start_date, end_date);
CREATE INDEX idx_unitcode_addr   ON unit_codes(address_id, unit_number);

-- ── 3. Seed data ────────────────────────────────────────────────────────────

INSERT INTO tenants (name, subdomain) VALUES ('DuEast', 'dueast');

INSERT INTO addresses (tenant_id, name, lot_code) VALUES
  ((SELECT id FROM tenants WHERE subdomain = 'dueast'), '225 Sumach Street', '10001');

-- ── 4. Multi-tenant helper functions ────────────────────────────────────────
-- Used by the RLS policies below and callable directly by the app. All
-- SECURITY DEFINER so they can read staff_access/platform_admins/addresses
-- regardless of the calling user's own RLS visibility into those tables —
-- otherwise checking access would itself require access (circular).

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

-- get_tenant_staff: lists a tenant's staff with their email, for the
-- platform admin portal. staff_access only stores user_id — email lives in
-- auth.users, which the client can never query directly.
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

-- get_tenant_usage_stats: for the platform admin portal — registrations
-- this month, active units, and address count for one tenant.
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

-- reset_tenant_demo_data: platform-admin-only, hard-gated to status='trial'
-- tenants. Clears activity data (registrations, exemptions) so a demo
-- tenant can be reset before a sales call. Deliberately leaves unit_codes
-- and addresses alone — those are the demo's setup, not its mess.
CREATE OR REPLACE FUNCTION reset_tenant_demo_data(p_tenant_id UUID)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_status          TEXT;
  v_tenant_name     TEXT;
  v_reg_count       INT;
  v_exemption_count INT;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Only platform admins can reset demo data';
  END IF;

  SELECT status, name INTO v_status, v_tenant_name FROM tenants WHERE id = p_tenant_id;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Tenant not found';
  END IF;
  IF v_status <> 'trial' THEN
    RAISE EXCEPTION 'Only trial tenants can be reset this way — "%" is marked "%". Change its status to trial first if this is really meant to be a demo account.', v_tenant_name, v_status;
  END IF;

  WITH addr AS (SELECT id FROM addresses WHERE tenant_id = p_tenant_id)
  DELETE FROM visitor_registrations WHERE address_id IN (SELECT id FROM addr);
  GET DIAGNOSTICS v_reg_count = ROW_COUNT;

  WITH addr AS (SELECT id FROM addresses WHERE tenant_id = p_tenant_id)
  DELETE FROM exemptions WHERE address_id IN (SELECT id FROM addr);
  GET DIAGNOSTICS v_exemption_count = ROW_COUNT;

  RETURN json_build_object(
    'registrationsDeleted', v_reg_count,
    'exemptionsDeleted',    v_exemption_count
  );
END;
$$;
GRANT EXECUTE ON FUNCTION reset_tenant_demo_data TO authenticated;

-- bulk_regenerate_unit_codes: platform-admin-only. Bulk-generating unit codes
-- used to be available to any tenant staff member from Admin's Unit Codes
-- tab, merging into the existing list. It's now restricted to platform
-- admins and runs through a single atomic transaction rather than a
-- client-side delete-then-insert that could partially fail. Gated here, not
-- just by hiding the button, in case a tenant staff member ever calls the
-- RPC directly — the existing "Staff can manage their tenant unit codes"
-- policy on the table itself is untouched, so day-to-day single-code
-- add/edit/reset by tenant staff keeps working exactly as before.
--
-- The delete is scoped to the unit numbers in p_codes, not the whole
-- building — a two-tower building (e.g. E201-E1110 and W201-W2910 sharing
-- one address) can regenerate one tower's range without wiping the other's.
-- Re-running the exact same range you already generated still behaves like
-- a full replace of that range, since it's deleted then reinserted. Use
-- wipe_unit_codes() below to clear an entire building at once.
CREATE OR REPLACE FUNCTION bulk_regenerate_unit_codes(p_address_id UUID, p_codes JSONB)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_deleted  INT;
  v_inserted INT;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Only platform admins can bulk-regenerate unit codes';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM addresses WHERE id = p_address_id) THEN
    RAISE EXCEPTION 'Building not found';
  END IF;

  DELETE FROM unit_codes
  WHERE address_id = p_address_id
    AND unit_number IN (SELECT elem->>'unit_number' FROM jsonb_array_elements(p_codes) AS elem);
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  INSERT INTO unit_codes (address_id, unit_number, code)
  SELECT p_address_id, elem->>'unit_number', elem->>'code'
  FROM jsonb_array_elements(p_codes) AS elem;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  RETURN json_build_object('deleted', v_deleted, 'inserted', v_inserted);
END;
$$;
GRANT EXECUTE ON FUNCTION bulk_regenerate_unit_codes TO authenticated;

-- wipe_unit_codes: platform-admin-only, deletes every unit code for exactly
-- one building — never more than one address at a time, and never
-- tenant-wide. This is the deliberate "start completely fresh" action for
-- when bulk_regenerate_unit_codes's range-scoped delete isn't what you
-- want, e.g. tearing down a building's whole code list before re-numbering
-- it from scratch (new tower layout, wrong prefix scheme, etc.).
CREATE OR REPLACE FUNCTION wipe_unit_codes(p_address_id UUID)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_deleted      INT;
  v_address_name TEXT;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Only platform admins can wipe unit codes';
  END IF;

  SELECT name INTO v_address_name FROM addresses WHERE id = p_address_id;
  IF v_address_name IS NULL THEN
    RAISE EXCEPTION 'Building not found';
  END IF;

  DELETE FROM unit_codes WHERE address_id = p_address_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  RETURN json_build_object('deleted', v_deleted, 'address_name', v_address_name);
END;
$$;
GRANT EXECUTE ON FUNCTION wipe_unit_codes TO authenticated;

-- ── 5. Row Level Security ────────────────────────────────────────────────────

ALTER TABLE tenants                ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_access           ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform_admins        ENABLE ROW LEVEL SECURITY;
ALTER TABLE addresses              ENABLE ROW LEVEL SECURITY;
ALTER TABLE visitor_registrations  ENABLE ROW LEVEL SECURITY;
ALTER TABLE exemptions             ENABLE ROW LEVEL SECURITY;
ALTER TABLE unit_codes             ENABLE ROW LEVEL SECURITY;

-- Tenants: anon needs name/subdomain to resolve which tenant a hostname
-- belongs to before anyone logs in. Nothing in this table is sensitive.
CREATE POLICY "Anon can read tenants for subdomain resolution"
  ON tenants FOR SELECT TO anon USING (true);
CREATE POLICY "Staff can read their own tenant"
  ON tenants FOR SELECT TO authenticated USING (is_tenant_member(id));
CREATE POLICY "Platform admins manage tenants"
  ON tenants FOR ALL TO authenticated USING (is_platform_admin()) WITH CHECK (is_platform_admin());

-- staff_access / platform_admins: platform admins only. Regular staff never
-- read these tables directly — they go through SECURITY DEFINER functions.
CREATE POLICY "Platform admins manage staff access"
  ON staff_access FOR ALL TO authenticated USING (is_platform_admin()) WITH CHECK (is_platform_admin());
CREATE POLICY "Platform admins manage platform admins"
  ON platform_admins FOR ALL TO authenticated USING (is_platform_admin()) WITH CHECK (is_platform_admin());

-- Addresses: anon reads every address (needed by the resident registration
-- form before it knows which tenant it's on). Staff only see their own
-- tenant's addresses. Only platform admins create/edit/delete addresses.
CREATE POLICY "Anon can read addresses"
  ON addresses FOR SELECT TO anon USING (true);
CREATE POLICY "Staff can read their tenant addresses"
  ON addresses FOR SELECT TO authenticated USING (is_tenant_member(tenant_id));
CREATE POLICY "Platform admins manage addresses"
  ON addresses FOR ALL TO authenticated USING (is_platform_admin()) WITH CHECK (is_platform_admin());

-- Visitor registrations: public page inserts may run as either anon or
-- authenticated if the browser already has a Supabase session cached.
-- Staff can only see/remove registrations belonging to their own tenant.
CREATE POLICY "Public can register visitors"
  ON visitor_registrations FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY "Staff can view their tenant registrations"
  ON visitor_registrations FOR SELECT TO authenticated USING (has_tenant_access(address_id));
CREATE POLICY "Staff can remove their tenant registrations"
  ON visitor_registrations FOR DELETE TO authenticated USING (has_tenant_access(address_id));

-- Exemptions: staff can only manage exemptions for their own tenant.
CREATE POLICY "Staff can view their tenant exemptions"
  ON exemptions FOR SELECT TO authenticated USING (has_tenant_access(address_id));
CREATE POLICY "Staff can add their tenant exemptions"
  ON exemptions FOR INSERT TO authenticated WITH CHECK (has_tenant_access(address_id));
CREATE POLICY "Staff can update their tenant exemptions"
  ON exemptions FOR UPDATE TO authenticated USING (has_tenant_access(address_id));
CREATE POLICY "Staff can delete their tenant exemptions"
  ON exemptions FOR DELETE TO authenticated USING (has_tenant_access(address_id));

-- Unit codes: staff only for direct table access (residents use the RPC
-- below), scoped to their own tenant.
CREATE POLICY "Staff can manage their tenant unit codes"
  ON unit_codes FOR ALL TO authenticated
  USING (has_tenant_access(address_id)) WITH CHECK (has_tenant_access(address_id));

-- ── 6. Resident-facing RPC Functions ────────────────────────────────────────
-- These run with SECURITY DEFINER so they can bypass RLS when called by anon.

-- validate_unit_code: returns TRUE if the code matches, FALSE otherwise.
-- Unit codes are never returned to the client — only the boolean result.
CREATE OR REPLACE FUNCTION validate_unit_code(
  p_unit_number TEXT,
  p_address_id  UUID,
  p_code        TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_stored_code TEXT;
BEGIN
  SELECT code INTO v_stored_code
  FROM unit_codes
  WHERE address_id = p_address_id
    AND UPPER(unit_number) = UPPER(p_unit_number);

  IF v_stored_code IS NULL THEN
    RETURN FALSE;
  END IF;

  RETURN UPPER(v_stored_code) = UPPER(p_code);
END;
$$;
GRANT EXECUTE ON FUNCTION validate_unit_code TO anon;

-- get_monthly_pass_stats: returns pass usage stats for a unit this month,
-- using that unit's tenant's configured limits (Admin's Settings tab),
-- defaulting to 10/7 if an address somehow has no tenant.
CREATE OR REPLACE FUNCTION get_monthly_pass_stats(
  p_unit_number TEXT,
  p_address_id  UUID
)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_month_start TIMESTAMPTZ := date_trunc('month', NOW());
  v_month_end   TIMESTAMPTZ := date_trunc('month', NOW()) + INTERVAL '1 month';
  v_total       INT;
  v_plate_days  JSON;
  v_monthly_limit INT;
  v_plate_limit   INT;
BEGIN
  SELECT t.monthly_pass_limit, t.plate_day_limit
  INTO v_monthly_limit, v_plate_limit
  FROM addresses a
  JOIN tenants t ON t.id = a.tenant_id
  WHERE a.id = p_address_id;

  v_monthly_limit := COALESCE(v_monthly_limit, 10);
  v_plate_limit   := COALESCE(v_plate_limit, 7);

  -- Each row counts as (1 + its extension_count) passes — an extension
  -- consumes a pass just like the original registration did.
  SELECT COALESCE(SUM(1 + extension_count), 0) INTO v_total
  FROM visitor_registrations
  WHERE address_id = p_address_id
    AND UPPER(unit_number) = UPPER(p_unit_number)
    AND registered_at >= v_month_start
    AND registered_at <  v_month_end;

  SELECT json_object_agg(plate, day_count) INTO v_plate_days
  FROM (
    SELECT
      UPPER(REPLACE(visitor_plate, ' ', ''))    AS plate,
      SUM(1 + extension_count)::INT             AS day_count
    FROM visitor_registrations
    WHERE address_id = p_address_id
      AND UPPER(unit_number) = UPPER(p_unit_number)
      AND registered_at >= v_month_start
      AND registered_at <  v_month_end
    GROUP BY UPPER(REPLACE(visitor_plate, ' ', ''))
  ) t;

  RETURN json_build_object(
    'totalPasses',      v_total,
    'plateDays',        COALESCE(v_plate_days, '{}'::JSON),
    'remainingPasses',  GREATEST(0, v_monthly_limit - v_total),
    'maxPassesReached', v_total >= v_monthly_limit,
    'monthlyLimit',     v_monthly_limit,
    'plateLimit',       v_plate_limit
  );
END;
$$;
GRANT EXECUTE ON FUNCTION get_monthly_pass_stats TO anon;

-- can_register_visitor: checks both monthly limits and returns allowed/reason.
CREATE OR REPLACE FUNCTION can_register_visitor(
  p_unit_number TEXT,
  p_address_id  UUID,
  p_plate       TEXT
)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_stats       JSON;
  v_norm_plate  TEXT;
  v_days_used   INT;
  v_plate_limit INT;
BEGIN
  v_stats       := get_monthly_pass_stats(p_unit_number, p_address_id);
  v_norm_plate  := UPPER(REPLACE(p_plate, ' ', ''));
  v_plate_limit := COALESCE((v_stats->>'plateLimit')::INT, 7);

  IF (v_stats->>'maxPassesReached')::BOOLEAN THEN
    RETURN json_build_object(
      'allowed', FALSE,
      'reason',  'Your unit has used all ' || (v_stats->>'monthlyLimit') ||
                 ' visitor parking passes for this month. Passes reset on the 1st of next month.'
    );
  END IF;

  v_days_used := COALESCE((v_stats->'plateDays'->>v_norm_plate)::INT, 0);
  IF v_days_used >= v_plate_limit THEN
    RETURN json_build_object(
      'allowed', FALSE,
      'reason',  'Plate ' || p_plate || ' has already been registered for ' || v_plate_limit ||
                 ' days this month and cannot be registered again until next month.'
    );
  END IF;

  RETURN json_build_object('allowed', TRUE, 'reason', '');
END;
$$;
GRANT EXECUTE ON FUNCTION can_register_visitor TO anon;

-- update_tenant_limits: the only way to change a tenant's pass limits.
-- Any staff member of the tenant can call this — matches the existing
-- flat-access decision (no property-manager-vs-concierge tier). Bounded to
-- sane ranges so a typo can't accidentally disable registration entirely.
CREATE OR REPLACE FUNCTION update_tenant_limits(
  p_tenant_id          UUID,
  p_monthly_pass_limit INT,
  p_plate_day_limit    INT
)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  IF NOT is_tenant_member(p_tenant_id) THEN
    RAISE EXCEPTION 'Not authorized for this tenant';
  END IF;

  IF p_monthly_pass_limit < 1 OR p_monthly_pass_limit > 500 THEN
    RAISE EXCEPTION 'Monthly pass limit must be between 1 and 500';
  END IF;

  IF p_plate_day_limit < 1 OR p_plate_day_limit > 31 THEN
    RAISE EXCEPTION 'Plate day limit must be between 1 and 31';
  END IF;

  UPDATE tenants
  SET monthly_pass_limit = p_monthly_pass_limit,
      plate_day_limit    = p_plate_day_limit
  WHERE id = p_tenant_id;

  RETURN json_build_object(
    'monthlyPassLimit', p_monthly_pass_limit,
    'plateDayLimit',    p_plate_day_limit
  );
END;
$$;
GRANT EXECUTE ON FUNCTION update_tenant_limits TO authenticated;

-- ── 7. Retention: visitor_registrations is kept for 3 years ─────────────────
-- Registration history (active + expired) is intentionally NOT deleted on
-- expiry — Admin > Registration History reads the full history for a plate
-- or unit. Instead, a scheduled job permanently deletes rows older than
-- 3 years. See patch-history-retention.sql to set this up (one-time, via
-- the Supabase SQL Editor).
