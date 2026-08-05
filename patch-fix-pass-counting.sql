-- ═══════════════════════════════════════════════════════════════════
-- Patch: Fix extend not counting toward monthly passes
-- Run this in Supabase → SQL Editor → New query
--
-- Bug: extend_visitor_registration() only updated expires_at on the
-- existing row. get_monthly_pass_stats() counts passes by COUNT(*) of
-- rows registered this month, so an extension — which doesn't insert a
-- new row — was invisible to that count. Result: "Monthly passes used"
-- and "Days registered (this plate)" never moved after an extension,
-- and nothing actually capped how many times a plate could be extended.
--
-- Fix: add an extension_count column, increment it on each extend, and
-- have get_monthly_pass_stats() count (1 + extension_count) per row
-- instead of just counting rows. This matches the behavior the code
-- already claimed ("this extension uses 1 of your unit's monthly
-- visitor passes") and the existing 7-day-per-plate cap in
-- can_register_visitor() now applies to extensions too.
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Add the column ─────────────────────────────────────────────
ALTER TABLE visitor_registrations
  ADD COLUMN IF NOT EXISTS extension_count INT NOT NULL DEFAULT 0;

-- ── 2. Replace get_monthly_pass_stats to count extensions ─────────
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
BEGIN
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
  ) sub;

  RETURN json_build_object(
    'totalPasses',       v_total,
    'maxPassesReached',  v_total >= 10,
    'plateDays',         COALESCE(v_plate_days, '{}'::JSON)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION get_monthly_pass_stats TO anon;

-- ── 3. Replace extend_visitor_registration to increment the count ──
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

  -- 5. Extend by 24 hours from current expiry time.
  -- extension_count increments so get_monthly_pass_stats() counts this
  -- extension as a pass, same as the check in step 4 already assumed.
  v_new_expires := v_reg.expires_at + INTERVAL '24 hours';

  UPDATE visitor_registrations
  SET expires_at = v_new_expires,
      extension_count = extension_count + 1
  WHERE id = v_reg.id;

  RETURN json_build_object(
    'extended',      TRUE,
    'new_expires_at', v_new_expires,
    'error',         ''
  );
END;
$$;
GRANT EXECUTE ON FUNCTION extend_visitor_registration TO anon;

-- ── 4. Verify ───────────────────────────────────────────────────────
-- SELECT visitor_plate, registered_at, expires_at, extension_count
-- FROM visitor_registrations
-- ORDER BY registered_at DESC LIMIT 10;
