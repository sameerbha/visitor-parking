-- ═══════════════════════════════════════════════════════════════════
-- Patch: Bulk Regenerate Unit Codes (platform-admin-only)
-- Run this in Supabase → SQL Editor → New query. Safe to re-run.
--
-- Bulk-generating unit codes used to be available to any tenant staff
-- member from Admin's Unit Codes tab, and merged into the existing list
-- (new codes added, existing ones left alone unless explicitly checked).
-- It's now moved to Platform Admin, restricted to platform admins only,
-- and changed to a full wipe-and-replace: every existing unit code for the
-- chosen building is deleted, then the newly generated set is inserted, in
-- one atomic transaction.
--
-- Gated here at the RPC level, not just by removing the button from
-- admin.html — the existing "Staff can manage their tenant unit codes"
-- policy on the unit_codes table is untouched, so a tenant staff member
-- can still add/edit/reset individual codes exactly as before. Only this
-- specific bulk-rewrite path is platform-admin-only.
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

  DELETE FROM unit_codes WHERE address_id = p_address_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  INSERT INTO unit_codes (address_id, unit_number, code)
  SELECT p_address_id, elem->>'unit_number', elem->>'code'
  FROM jsonb_array_elements(p_codes) AS elem;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  RETURN json_build_object('deleted', v_deleted, 'inserted', v_inserted);
END;
$$;
GRANT EXECUTE ON FUNCTION bulk_regenerate_unit_codes TO authenticated;
