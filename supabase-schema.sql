-- ═══════════════════════════════════════════════════════════════════
-- Visitors Parking Management — Supabase Schema  (v1.2.0)
-- Run this entire file in the Supabase SQL Editor (Project → SQL Editor).
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Tables ───────────────────────────────────────────────────────────────

CREATE TABLE addresses (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  lot_code   TEXT UNIQUE NOT NULL,
  full_name  TEXT GENERATED ALWAYS AS (name || ' (' || lot_code || ')') STORED,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE visitor_registrations (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  address_id    UUID REFERENCES addresses(id) ON DELETE CASCADE,
  lot_code      TEXT NOT NULL,
  tenant_phone  TEXT NOT NULL,
  unit_number   TEXT NOT NULL,
  visitor_plate TEXT NOT NULL,
  registered_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at    TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours')
);

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

INSERT INTO addresses (name, lot_code) VALUES
  ('225 Sumach Street', '10001');

-- ── 4. Row Level Security ────────────────────────────────────────────────────

ALTER TABLE addresses              ENABLE ROW LEVEL SECURITY;
ALTER TABLE visitor_registrations  ENABLE ROW LEVEL SECURITY;
ALTER TABLE exemptions             ENABLE ROW LEVEL SECURITY;
ALTER TABLE unit_codes             ENABLE ROW LEVEL SECURITY;

-- Addresses: readable by everyone (needed by the resident registration form)
CREATE POLICY "Addresses are public"
  ON addresses FOR SELECT TO anon, authenticated USING (true);

-- Visitor registrations: public page inserts may run as either anon or
-- authenticated if the browser already has a Supabase session cached.
CREATE POLICY "Public can register visitors"
  ON visitor_registrations FOR INSERT TO anon, authenticated WITH CHECK (true);

-- Staff can read and delete registrations
CREATE POLICY "Staff can view registrations"
  ON visitor_registrations FOR SELECT TO authenticated USING (true);
CREATE POLICY "Staff can remove registrations"
  ON visitor_registrations FOR DELETE TO authenticated USING (true);

-- Exemptions: staff only
CREATE POLICY "Staff can view exemptions"   ON exemptions FOR SELECT TO authenticated USING (true);
CREATE POLICY "Staff can add exemptions"    ON exemptions FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Staff can update exemptions" ON exemptions FOR UPDATE TO authenticated USING (true);
CREATE POLICY "Staff can delete exemptions" ON exemptions FOR DELETE TO authenticated USING (true);

-- Unit codes: staff only for direct table access (residents use the RPC below)
CREATE POLICY "Staff can manage unit codes" ON unit_codes FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ── 5. RPC Functions ─────────────────────────────────────────────────────────
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

-- get_monthly_pass_stats: returns pass usage stats for a unit this month.
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
  SELECT COUNT(*) INTO v_total
  FROM visitor_registrations
  WHERE address_id = p_address_id
    AND UPPER(unit_number) = UPPER(p_unit_number)
    AND registered_at >= v_month_start
    AND registered_at <  v_month_end;

  SELECT json_object_agg(plate, day_count) INTO v_plate_days
  FROM (
    SELECT
      UPPER(REPLACE(visitor_plate, ' ', '')) AS plate,
      COUNT(DISTINCT registered_at::DATE)    AS day_count
    FROM visitor_registrations
    WHERE address_id = p_address_id
      AND UPPER(unit_number) = UPPER(p_unit_number)
      AND registered_at >= v_month_start
      AND registered_at <  v_month_end
    GROUP BY UPPER(REPLACE(visitor_plate, ' ', ''))
  ) t;

  RETURN json_build_object(
    'totalPasses',     v_total,
    'plateDays',       COALESCE(v_plate_days, '{}'::JSON),
    'remainingPasses', GREATEST(0, 10 - v_total),
    'maxPassesReached', v_total >= 10
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
  v_stats      JSON;
  v_norm_plate TEXT;
  v_days_used  INT;
BEGIN
  v_stats      := get_monthly_pass_stats(p_unit_number, p_address_id);
  v_norm_plate := UPPER(REPLACE(p_plate, ' ', ''));

  IF (v_stats->>'maxPassesReached')::BOOLEAN THEN
    RETURN json_build_object(
      'allowed', FALSE,
      'reason',  'Your unit has used all 10 visitor parking passes for this month. Passes reset on the 1st of next month.'
    );
  END IF;

  v_days_used := COALESCE((v_stats->'plateDays'->>v_norm_plate)::INT, 0);
  IF v_days_used >= 7 THEN
    RETURN json_build_object(
      'allowed', FALSE,
      'reason',  'Plate ' || p_plate || ' has already been registered for 7 days this month and cannot be registered again until next month.'
    );
  END IF;

  RETURN json_build_object('allowed', TRUE, 'reason', '');
END;
$$;
GRANT EXECUTE ON FUNCTION can_register_visitor TO anon;

-- ── 6. Optional: auto-cleanup of expired registrations (pg_cron) ────────────
-- Uncomment in Supabase Dashboard → Database → Extensions → enable pg_cron,
-- then run this to delete expired rows every hour:
--
-- SELECT cron.schedule('cleanup-expired', '0 * * * *',
--   'DELETE FROM visitor_registrations WHERE expires_at < NOW()');
