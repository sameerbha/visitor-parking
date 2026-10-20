-- ═══════════════════════════════════════════════════════════════════
-- Test: optional per-tenant re-registration cooldown
--
-- Run this in the Supabase SQL Editor any time after
-- patch-reregistration-cooldown.sql (or a fresh supabase-schema.sql,
-- which already has the cooldown check built into can_register_visitor()).
--
-- Entirely wrapped in BEGIN/ROLLBACK — it creates one throwaway tenant,
-- one throwaway building, and a handful of throwaway registrations, then
-- rolls all of it back at the end, whether every assertion passes or the
-- very first one fails. Nothing here ever touches real tenant data.
--
-- Expected output: a NOTICE for each of the 6 cases below as it passes,
-- ending with "ALL 6 ASSERTIONS PASSED". If anything is wrong, you'll get
-- an EXCEPTION naming exactly which case failed and what it got back
-- instead, and the whole block (and the transaction) aborts right there.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

DO $$
DECLARE
  v_tenant_id  UUID;
  v_address_id UUID;
  v_result     JSON;
BEGIN
  -- ── Setup: one throwaway tenant + building, cooldown on at 72 hours ──
  INSERT INTO tenants (name, subdomain, reregistration_cooldown_enabled, reregistration_cooldown_hours)
  VALUES ('__test_cooldown_tenant__', '__test-cooldown-' || substr(gen_random_uuid()::TEXT, 1, 8), TRUE, 72)
  RETURNING id INTO v_tenant_id;

  INSERT INTO addresses (tenant_id, name, lot_code)
  VALUES (v_tenant_id, '__Test Building__', '__test-lot-' || substr(gen_random_uuid()::TEXT, 1, 8))
  RETURNING id INTO v_address_id;

  -- Every case below controls expires_at as an offset from
  -- "NOW() - 72 hours" (NOW() is stable for the whole transaction in
  -- Postgres, so these are deterministic, not a race against the clock):
  --   expires_at = NOW() - 72h + offset   =>   cooldown_until = NOW() + offset
  -- so a positive offset means "cooldown_until is still in the future"
  -- (blocked) and a zero/negative offset means "cooldown_until has
  -- already passed" (allowed).

  -- ═══ Case 1: well within the cooldown window (1 hour still left) ═══
  INSERT INTO visitor_registrations (address_id, lot_code, unit_number, visitor_plate, registered_at, expires_at)
  VALUES (v_address_id, 'TESTLOT', '101', 'COOL001', NOW() - INTERVAL '71 hours' - INTERVAL '24 hours', NOW() - INTERVAL '71 hours');

  v_result := can_register_visitor('101', v_address_id, 'COOL001');
  IF (v_result->>'allowed')::BOOLEAN IS NOT FALSE THEN
    RAISE EXCEPTION 'FAIL (case 1 — within cooldown): expected blocked, got %', v_result;
  END IF;
  IF v_result->>'cooldownUntil' IS NULL THEN
    RAISE EXCEPTION 'FAIL (case 1 — within cooldown): expected cooldownUntil to be present, got %', v_result;
  END IF;
  RAISE NOTICE 'PASS (case 1 — within cooldown): blocked, reason: %', v_result->>'reason';

  -- ═══ Case 2: exactly at the cutoff instant → must be allowed ═══
  -- "Not inclusive" is read here as: the blocked span runs up to but not
  -- including the exact cutoff moment itself.
  INSERT INTO visitor_registrations (address_id, lot_code, unit_number, visitor_plate, registered_at, expires_at)
  VALUES (v_address_id, 'TESTLOT', '101', 'COOL002', NOW() - INTERVAL '72 hours' - INTERVAL '24 hours', NOW() - INTERVAL '72 hours');

  v_result := can_register_visitor('101', v_address_id, 'COOL002');
  IF (v_result->>'allowed')::BOOLEAN IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL (case 2 — exact cutoff instant): expected allowed, got %', v_result;
  END IF;
  RAISE NOTICE 'PASS (case 2 — exact cutoff instant): allowed';

  -- ═══ Case 3: one second past the cutoff → must be allowed ═══
  INSERT INTO visitor_registrations (address_id, lot_code, unit_number, visitor_plate, registered_at, expires_at)
  VALUES (v_address_id, 'TESTLOT', '101', 'COOL003', NOW() - INTERVAL '72 hours 1 second' - INTERVAL '24 hours', NOW() - INTERVAL '72 hours 1 second');

  v_result := can_register_visitor('101', v_address_id, 'COOL003');
  IF (v_result->>'allowed')::BOOLEAN IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL (case 3 — 1 second past cutoff): expected allowed, got %', v_result;
  END IF;
  RAISE NOTICE 'PASS (case 3 — 1 second past cutoff): allowed';

  -- ═══ Case 4: one second BEFORE the cutoff → must still be blocked ═══
  INSERT INTO visitor_registrations (address_id, lot_code, unit_number, visitor_plate, registered_at, expires_at)
  VALUES (v_address_id, 'TESTLOT', '101', 'COOL004', NOW() - INTERVAL '24 hours' + INTERVAL '1 second', NOW() + INTERVAL '1 second' - INTERVAL '72 hours');

  v_result := can_register_visitor('101', v_address_id, 'COOL004');
  IF (v_result->>'allowed')::BOOLEAN IS NOT FALSE THEN
    RAISE EXCEPTION 'FAIL (case 4 — 1 second before cutoff): expected still blocked, got %', v_result;
  END IF;
  RAISE NOTICE 'PASS (case 4 — 1 second before cutoff): still blocked';

  -- ═══ Case 5: a DIFFERENT plate, same unit, while COOL001 (case 1) is
  -- still mid-cooldown → must be completely unaffected ═══
  v_result := can_register_visitor('101', v_address_id, 'FRESH99');
  IF (v_result->>'allowed')::BOOLEAN IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL (case 5 — different plate, same unit): expected allowed, got %', v_result;
  END IF;
  RAISE NOTICE 'PASS (case 5 — different plate, same unit): registers freely';

  -- ═══ Case 6: feature disabled tenant-wide → even a plate deep in what
  -- would be its cooldown window (COOL001 again) must now be allowed ═══
  UPDATE tenants SET reregistration_cooldown_enabled = FALSE WHERE id = v_tenant_id;

  v_result := can_register_visitor('101', v_address_id, 'COOL001');
  IF (v_result->>'allowed')::BOOLEAN IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL (case 6 — feature disabled): expected allowed, got %', v_result;
  END IF;
  RAISE NOTICE 'PASS (case 6 — feature disabled): no cooldown applied at all';

  RAISE NOTICE '✓ ALL 6 ASSERTIONS PASSED';
END $$;

ROLLBACK;
