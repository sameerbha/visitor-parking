-- ═══════════════════════════════════════════════════════════════════
-- Patch: Duplicate Plate / Extend Flow
-- Run this in Supabase → SQL Editor → New query
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. check_plate_active ─────────────────────────────────────────
-- Called when a resident submits the registration form.
-- Returns the current active registration for a plate (if any)
-- so the UI can show the extend prompt with the current expiry time.
-- SECURITY DEFINER lets anon query registrations without a SELECT policy.

CREATE OR REPLACE FUNCTION check_plate_active(
  p_plate      TEXT,
  p_address_id UUID
)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_reg RECORD;
BEGIN
  SELECT id, unit_number, expires_at
  INTO v_reg
  FROM visitor_registrations
  WHERE address_id = p_address_id
    AND UPPER(REPLACE(visitor_plate, ' ', '')) = UPPER(REPLACE(p_plate, ' ', ''))
    AND expires_at > NOW()
  ORDER BY expires_at DESC
  LIMIT 1;

  IF v_reg.id IS NULL THEN
    RETURN json_build_object('active', FALSE);
  END IF;

  RETURN json_build_object(
    'active',       TRUE,
    'unit_number',  v_reg.unit_number,
    'expires_at',   v_reg.expires_at
  );
END;
$$;
GRANT EXECUTE ON FUNCTION check_plate_active TO anon;


-- ── 2. extend_visitor_registration ───────────────────────────────
-- Called when a resident confirms they want to extend.
-- Validates:
--   (a) the unit code is correct
--   (b) the active registration belongs to the same unit (only original unit can extend)
--   (c) the unit still has monthly passes available (extension counts as a new pass)
-- If all pass: extends expires_at by 24 hours on the existing row.

CREATE OR REPLACE FUNCTION extend_visitor_registration(
  p_plate       TEXT,
  p_address_id  UUID,
  p_unit_number TEXT,
  p_code        TEXT
)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_code_valid  BOOLEAN;
  v_reg         RECORD;
  v_pass_check  JSON;
  v_new_expires TIMESTAMPTZ;
BEGIN
  -- 1. Validate unit code
  SELECT validate_unit_code(p_unit_number, p_address_id, p_code) INTO v_code_valid;
  IF NOT v_code_valid THEN
    RETURN json_build_object('extended', FALSE,
      'error', 'Incorrect unit number or code.');
  END IF;

  -- 2. Find the active registration for this plate at this address
  SELECT id, unit_number, expires_at
  INTO v_reg
  FROM visitor_registrations
  WHERE address_id = p_address_id
    AND UPPER(REPLACE(visitor_plate, ' ', '')) = UPPER(REPLACE(p_plate, ' ', ''))
    AND expires_at > NOW()
  ORDER BY expires_at DESC
  LIMIT 1;

  IF v_reg.id IS NULL THEN
    RETURN json_build_object('extended', FALSE,
      'error', 'The registration has expired. Please register as a new visitor.');
  END IF;

  -- 3. Only the original registering unit can extend
  IF UPPER(v_reg.unit_number) != UPPER(p_unit_number) THEN
    RETURN json_build_object('extended', FALSE,
      'error', 'This plate was registered by unit ' || UPPER(v_reg.unit_number) ||
               '. Only that unit can extend the registration.');
  END IF;

  -- 4. Check monthly pass limit (extension counts as a new pass)
  SELECT can_register_visitor(p_unit_number, p_address_id, p_plate) INTO v_pass_check;
  IF NOT (v_pass_check->>'allowed')::BOOLEAN THEN
    RETURN json_build_object('extended', FALSE, 'error', v_pass_check->>'reason');
  END IF;

  -- 5. Extend by 24 hours from current expiry time
  v_new_expires := v_reg.expires_at + INTERVAL '24 hours';

  UPDATE visitor_registrations
  SET expires_at = v_new_expires
  WHERE id = v_reg.id;

  RETURN json_build_object(
    'extended',      TRUE,
    'new_expires_at', v_new_expires,
    'error',         ''
  );
END;
$$;
GRANT EXECUTE ON FUNCTION extend_visitor_registration TO anon;
