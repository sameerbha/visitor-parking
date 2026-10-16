-- ═══════════════════════════════════════════════════════════════════
-- Patch: optional per-building visitor spot selection (e.g. V1–V20)
-- Run once in the Supabase SQL Editor on any existing install.
-- Safe to re-run — every statement is idempotent (IF NOT EXISTS / OR REPLACE).
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. New columns ───────────────────────────────────────────────────────────

-- A building has visitor spot selection enabled when visitor_spot_prefix is
-- NOT NULL. All three are nullable and kept in sync together — either all
-- set (enabled) or all NULL (disabled) — enforced by the CHECK constraint
-- below rather than relying on the app to never send a partial update.
ALTER TABLE addresses ADD COLUMN IF NOT EXISTS visitor_spot_prefix TEXT;
ALTER TABLE addresses ADD COLUMN IF NOT EXISTS visitor_spot_start  INT;
ALTER TABLE addresses ADD COLUMN IF NOT EXISTS visitor_spot_end    INT;

DO $$ BEGIN
  ALTER TABLE addresses ADD CONSTRAINT visitor_spot_config_consistent CHECK (
    (visitor_spot_prefix IS NULL AND visitor_spot_start IS NULL AND visitor_spot_end IS NULL)
    OR (visitor_spot_prefix IS NOT NULL AND visitor_spot_start IS NOT NULL AND visitor_spot_end IS NOT NULL
        AND visitor_spot_start >= 1 AND visitor_spot_end >= visitor_spot_start
        AND (visitor_spot_end - visitor_spot_start) < 500)
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- The spot a resident picked at registration, e.g. "V5". NULL for buildings
-- that don't use this feature, and for every registration made before it
-- existed. Purely informational — see the trigger below for what "required
-- when the building has it configured" actually means; there is no check
-- anywhere that prevents two registrations from naming the same spot.
ALTER TABLE visitor_registrations ADD COLUMN IF NOT EXISTS spot TEXT;

-- ── 2. Server-side validation (never trust the dropdown alone) ──────────────
-- Mirrors how unit codes are validated server-side rather than trusting
-- whatever the browser submits. Runs on INSERT only — extending a
-- registration (extend_visitor_registration) only ever touches expires_at
-- and extension_count on the existing row, so a building that narrows its
-- spot range later can't retroactively break an extend on an older row.

CREATE OR REPLACE FUNCTION validate_visitor_spot()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_prefix TEXT;
  v_start  INT;
  v_end    INT;
  v_num    INT;
BEGIN
  SELECT visitor_spot_prefix, visitor_spot_start, visitor_spot_end
  INTO v_prefix, v_start, v_end
  FROM addresses WHERE id = NEW.address_id;

  IF v_prefix IS NULL THEN
    IF NEW.spot IS NOT NULL THEN
      RAISE EXCEPTION 'This building does not use visitor spot selection';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.spot IS NULL OR NEW.spot = '' THEN
    RAISE EXCEPTION 'A visitor parking spot is required for this building';
  END IF;

  IF NOT starts_with(NEW.spot, v_prefix) THEN
    RAISE EXCEPTION 'Invalid visitor spot: %', NEW.spot;
  END IF;

  BEGIN
    v_num := substring(NEW.spot FROM char_length(v_prefix) + 1)::INT;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Invalid visitor spot: %', NEW.spot;
  END;

  IF v_num < v_start OR v_num > v_end THEN
    RAISE EXCEPTION 'Visitor spot % is out of range for this building', NEW.spot;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_visitor_spot ON visitor_registrations;
CREATE TRIGGER trg_validate_visitor_spot
  BEFORE INSERT ON visitor_registrations
  FOR EACH ROW EXECUTE FUNCTION validate_visitor_spot();

-- ── 3. update_address_visitor_spots RPC ─────────────────────────────────────
-- Lets a building's own staff turn this on/off and set the range themselves
-- — unlike bulk unit code generation, this isn't a migration-sensitive
-- onboarding action, so it doesn't need to go through Platform Admin.
-- Gated by has_tenant_access(), the same helper exemptions/unit_codes
-- already use, not is_platform_admin().
CREATE OR REPLACE FUNCTION update_address_visitor_spots(
  p_address_id UUID,
  p_prefix     TEXT,
  p_start      INT,
  p_end        INT
)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  IF NOT has_tenant_access(p_address_id) THEN
    RAISE EXCEPTION 'Not authorized for this building';
  END IF;

  IF p_prefix IS NULL THEN
    UPDATE addresses
    SET visitor_spot_prefix = NULL, visitor_spot_start = NULL, visitor_spot_end = NULL
    WHERE id = p_address_id;
    RETURN json_build_object('enabled', FALSE);
  END IF;

  IF trim(p_prefix) = '' THEN
    RAISE EXCEPTION 'Prefix cannot be blank';
  END IF;
  IF length(p_prefix) > 5 THEN
    RAISE EXCEPTION 'Prefix must be 5 characters or fewer';
  END IF;
  IF p_start IS NULL OR p_end IS NULL OR p_start < 1 OR p_end < p_start THEN
    RAISE EXCEPTION 'Enter a valid first and last spot number (last must be greater than or equal to first)';
  END IF;
  IF (p_end - p_start + 1) > 500 THEN
    RAISE EXCEPTION 'A building can have at most 500 visitor spots configured';
  END IF;

  UPDATE addresses
  SET visitor_spot_prefix = p_prefix,
      visitor_spot_start  = p_start,
      visitor_spot_end    = p_end
  WHERE id = p_address_id;

  RETURN json_build_object(
    'enabled', TRUE,
    'prefix',  p_prefix,
    'start',   p_start,
    'end',     p_end,
    'count',   p_end - p_start + 1
  );
END;
$$;
GRANT EXECUTE ON FUNCTION update_address_visitor_spots TO authenticated;

-- No RLS or policy changes needed: "Anon can read addresses" and "Staff can
-- read their tenant addresses" already cover whole rows, so the three new
-- columns are automatically visible wherever the rest of an address already
-- is (the resident registration page, Admin, Platform Admin). The existing
-- "Public can register visitors" INSERT policy is unchanged — the new
-- trigger above does the actual enforcement, at the database level, not RLS.
