-- ═══════════════════════════════════════════════════════════════════
-- Patch: Reset Demo Data
-- Run this in Supabase → SQL Editor → New query. Safe to re-run.
--
-- Adds a platform-admin-only RPC that clears a tenant's activity data
-- (visitor registrations and exemptions) so a demo/trial tenant can be
-- reset to a clean slate before a sales call, without touching Supabase
-- directly.
--
-- Deliberately does NOT delete unit_codes or addresses — those represent
-- the demo's actual setup (which units exist, what their codes are), and
-- wiping them would make the demo tenant unusable until someone rebuilt
-- it. Only the "mess" that accumulates from actually using the demo
-- (test registrations, test exemptions) gets cleared.
--
-- Hard-gated server-side to tenants with status = 'trial', not just
-- hidden client-side — this is a destructive bulk delete, so the tenant
-- itself has to be explicitly marked as a trial/demo account before this
-- will do anything, regardless of who calls it or how.
-- ═══════════════════════════════════════════════════════════════════

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

-- ═══════════════════════════════════════════════════════════════════
-- After running this, mark your demo tenant as a trial so the Reset
-- button in Platform Admin will actually work on it:
--
--   UPDATE tenants SET status = 'trial' WHERE subdomain = 'demo';
--
-- (Replace 'demo' with whatever subdomain you actually gave it.)
-- ═══════════════════════════════════════════════════════════════════
