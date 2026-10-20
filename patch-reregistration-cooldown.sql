-- ═══════════════════════════════════════════════════════════════════
-- Patch: optional, per-tenant re-registration cooldown
-- Run once in the Supabase SQL Editor on any existing install.
-- Safe to re-run — every statement is idempotent (IF NOT EXISTS / OR REPLACE).
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. New columns on tenants ────────────────────────────────────────────────
-- Off by default for every existing tenant — nothing changes until a tenant's
-- own staff turns this on from Admin > Settings. When enabled, the SAME
-- plate can't register again at one of this tenant's buildings until
-- reregistration_cooldown_hours after its most recent stay's expires_at —
-- see can_register_visitor() below for the actual enforcement, and
-- update_tenant_reregistration_cooldown() for how a tenant configures it.
ALTER TABLE tenants
  ADD COLUMN IF NOT EXISTS reregistration_cooldown_enabled BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE tenants
  ADD COLUMN IF NOT EXISTS reregistration_cooldown_hours INT NOT NULL DEFAULT 72
    CHECK (reregistration_cooldown_hours BETWEEN 1 AND 720);

-- ── 2. can_register_visitor: add the cooldown check ──────────────────────────
-- Same function that already gates registration on monthly pass limits and
-- the per-plate day cap — this adds the new cooldown check ahead of those,
-- since "this vehicle literally isn't eligible yet" is a harder stop than a
-- pass-count message. Checked by address_id + plate only, never
-- unit_number, so a different vehicle from the same unit is never affected,
-- and the same plate is blocked regardless of which unit tries to
-- re-register it. "Not inclusive" per the spec that requested this: the
-- cooldown clock starts the instant the stay's expires_at passes, not from
-- the original registration — so the total blocked span is the 24-hour stay
-- plus the full cooldown length, not the cooldown alone.
CREATE OR REPLACE FUNCTION can_register_visitor(
  p_unit_number TEXT,
  p_address_id  UUID,
  p_plate       TEXT
)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_stats            JSON;
  v_norm_plate       TEXT;
  v_days_used        INT;
  v_plate_limit      INT;
  v_cooldown_enabled BOOLEAN;
  v_cooldown_hours   INT;
  v_last_expires_at  TIMESTAMPTZ;
  v_cooldown_until   TIMESTAMPTZ;
BEGIN
  v_norm_plate := UPPER(REPLACE(p_plate, ' ', ''));

  SELECT t.reregistration_cooldown_enabled, t.reregistration_cooldown_hours
  INTO v_cooldown_enabled, v_cooldown_hours
  FROM addresses a
  JOIN tenants t ON t.id = a.tenant_id
  WHERE a.id = p_address_id;

  IF v_cooldown_enabled THEN
    SELECT MAX(expires_at) INTO v_last_expires_at
    FROM visitor_registrations
    WHERE address_id = p_address_id
      AND UPPER(REPLACE(visitor_plate, ' ', '')) = v_norm_plate;

    IF v_last_expires_at IS NOT NULL THEN
      v_cooldown_until := v_last_expires_at + make_interval(hours => v_cooldown_hours);
      IF NOW() < v_cooldown_until THEN
        -- cooldownUntil is the raw timestamp the client formats in the
        -- resident's own local time (same pattern as the existing
        -- "already registered, extend?" flow) — reason is a plain-text
        -- fallback only, for any caller that doesn't special-case this field.
        RETURN json_build_object(
          'allowed',       FALSE,
          'reason',        'This vehicle is still in its re-registration cooldown period for this building and can''t be registered again yet.',
          'cooldownUntil', v_cooldown_until
        );
      END IF;
    END IF;
  END IF;

  v_stats       := get_monthly_pass_stats(p_unit_number, p_address_id);
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

-- ── 3. update_tenant_reregistration_cooldown RPC ─────────────────────────────
-- Self-serve by any of the tenant's own staff, same as update_tenant_limits
-- — this is a policy setting like monthly pass limits, not a migration-
-- sensitive onboarding action, so it doesn't need Platform Admin.
CREATE OR REPLACE FUNCTION update_tenant_reregistration_cooldown(
  p_tenant_id      UUID,
  p_enabled        BOOLEAN,
  p_cooldown_hours INT
)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  IF NOT is_tenant_member(p_tenant_id) THEN
    RAISE EXCEPTION 'Not authorized for this tenant';
  END IF;

  IF p_cooldown_hours < 1 OR p_cooldown_hours > 720 THEN
    RAISE EXCEPTION 'Cooldown length must be between 1 and 720 hours (30 days)';
  END IF;

  UPDATE tenants
  SET reregistration_cooldown_enabled = p_enabled,
      reregistration_cooldown_hours   = p_cooldown_hours
  WHERE id = p_tenant_id;

  RETURN json_build_object(
    'enabled',       p_enabled,
    'cooldownHours', p_cooldown_hours
  );
END;
$$;
GRANT EXECUTE ON FUNCTION update_tenant_reregistration_cooldown TO authenticated;

-- No RLS or policy changes needed: the two new columns on tenants are
-- covered by whatever SELECT access a caller already has to that tenant row
-- (get_tenant_by_subdomain, getTenantById, etc.), and the only way to change
-- them is the RPC above, which does its own is_tenant_member() check.
