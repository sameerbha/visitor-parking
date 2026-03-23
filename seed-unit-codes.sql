-- ═══════════════════════════════════════════════════════════════════
-- Seed Unit Codes — 225 Sumach Street
-- West Tower: W201–W2910  (floors 2–29, units 01–10) = 280 units
-- East Tower: E201–E1110  (floors 2–11, units 01–10) = 100 units
-- Total: 380 units
--
-- Run this in Supabase → SQL Editor → New query
-- ═══════════════════════════════════════════════════════════════════

-- Step 1: Temporary helper to generate a random 6-char parking code
-- Uses only unambiguous characters (no O/0, I/1, etc.)
CREATE OR REPLACE FUNCTION _gen_parking_code()
RETURNS TEXT LANGUAGE sql AS $$
  SELECT string_agg(
    substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', (floor(random() * 32) + 1)::int, 1),
    ''
  )
  FROM generate_series(1, 6);
$$;

-- Step 2: West Tower — floors 2 to 29, units 01 to 10
-- Produces: W201, W202 … W210, W301 … W2910
INSERT INTO unit_codes (address_id, unit_number, code, created_by, created_date, last_reset)
SELECT
  a.id,
  'W' || f || lpad(u::text, 2, '0'),
  _gen_parking_code(),
  'BuildingStaff',
  CURRENT_DATE,
  CURRENT_DATE
FROM (SELECT id FROM addresses WHERE lot_code = '10001') a,
     generate_series(2, 29) AS f,
     generate_series(1, 10) AS u;

-- Step 3: East Tower — floors 2 to 11, units 01 to 10
-- Produces: E201, E202 … E210, E301 … E1110
INSERT INTO unit_codes (address_id, unit_number, code, created_by, created_date, last_reset)
SELECT
  a.id,
  'E' || f || lpad(u::text, 2, '0'),
  _gen_parking_code(),
  'BuildingStaff',
  CURRENT_DATE,
  CURRENT_DATE
FROM (SELECT id FROM addresses WHERE lot_code = '10001') a,
     generate_series(2, 11) AS f,
     generate_series(1, 10) AS u;

-- Step 4: Clean up the helper function
DROP FUNCTION _gen_parking_code();

-- Step 5: Verify — should show 380 rows
SELECT
  COUNT(*)                                          AS total_units,
  COUNT(*) FILTER (WHERE unit_number LIKE 'W%')    AS west_units,
  COUNT(*) FILTER (WHERE unit_number LIKE 'E%')    AS east_units
FROM unit_codes;

-- Optional: preview a sample of the generated codes
-- SELECT unit_number, code FROM unit_codes ORDER BY unit_number LIMIT 20;
