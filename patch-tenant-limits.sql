-- ═══════════════════════════════════════════════════════════════════
-- Patch: Configurable per-tenant pass limits
-- Run this in Supabase → SQL Editor → New query.
--
-- The monthly-passes-per-unit (10) and days-per-plate (7) limits were
-- hardcoded. This makes them per-tenant settings, editable from Admin's
-- new Settings tab, defaulting to the existing 10/7 so nothing changes
-- for an existing tenant until they actually change it.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. New columns on tenants ────────────────────────────────────────────────
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS monthly_pass_limit INT NOT NULL DEFAULT 10 CHECK (monthly_pass_limit >= 1);
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS plate_day_limit    INT NOT NULL DEFAULT 7  CHECK (plate_day_limit >= 1);

-- ── 2. get_monthly_pass_stats now reads the tenant's own limit ─────────────
-- Also returns monthlyLimit/plateLimit so the client can render the right
-- denominator instead of assuming 10/7.
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

  -- Address without a tenant (shouldn't happen post-migration) falls back
  -- to the original defaults rather than erroring.
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

-- ── 3. can_register_visitor uses the tenant's plate_day_limit ─────────────
CREATE OR REPLACE FUNCTION can_register_visitor(
  p_unit_number TEXT,
  p_address_id  UUID,
  p_plate       TEXT
)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_stats      JSON;
  v_norm_plate TEXT;
  v_days_used  INT;
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

-- ── 4. update_tenant_limits — the only way Admin can change these ─────────
-- Any staff member of the tenant can call this (matches the existing
-- flat-access decision — no property-manager-vs-concierge tier). Values are
-- bounded to sane ranges so a typo can't accidentally disable registration
-- entirely (e.g. a limit of 0).
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

COMMIT;
