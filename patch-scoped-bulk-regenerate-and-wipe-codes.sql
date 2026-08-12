-- ═══════════════════════════════════════════════════════════════════
-- Patch: Scope Bulk Regenerate to its range + add Wipe All Codes
-- Run this in Supabase → SQL Editor → New query. Safe to re-run.
--
-- Problem this fixes: bulk_regenerate_unit_codes previously deleted every
-- unit code for the whole building before inserting the new batch. That
-- breaks buildings with more than one tower sharing a single address (e.g.
-- 225 Sumach Street has West Tower W201-W2910 and East Tower E201-E1110 —
-- regenerating just the West range would have wiped every East code too).
--
-- Fix: the delete is now scoped to only the unit numbers being generated.
-- Regenerating West's range never touches East's codes, and vice versa.
-- Re-running the exact same range you already generated still behaves like
-- a full replace of that range — nothing changes for single-tower
-- buildings that always generate their whole range in one go.
--
-- New: wipe_unit_codes(p_address_id) — a separate, explicit "delete every
-- code for this one building" action, for when you actually want to start
-- completely fresh (e.g. re-numbering a building from scratch). Always
-- scoped to exactly one building, never a whole tenant.
-- ═══════════════════════════════════════════════════════════════════

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
