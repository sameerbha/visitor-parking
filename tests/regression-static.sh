#!/usr/bin/env bash
# Static regression check for the Visitors Parking App.
# Verifies every page/asset still loads, no stale register.html links remain,
# and the new staff-link / PWA references are in place after the landing-page
# restructure (register.html -> index.html, index.html -> portal.html).
#
# Usage:
#   cd "Visitors Parking App"
#   bash tests/regression-static.sh

set -uo pipefail
PORT=8080
BASE="http://localhost:$PORT"

echo "Starting local server on :$PORT ..."
python3 -m http.server "$PORT" >/tmp/vp-static-server.log 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null' EXIT
sleep 1

PASS=0
FAIL=0

check_status() {
  local path="$1"
  local expect="$2"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/$path")
  if [ "$code" = "$expect" ]; then
    echo "PASS  $path -> $code"
    PASS=$((PASS+1))
  else
    echo "FAIL  $path -> $code (expected $expect)"
    FAIL=$((FAIL+1))
  fi
}

check_contains() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if curl -s "$BASE/$path" | grep -q -- "$pattern"; then
    echo "PASS  $label"
    PASS=$((PASS+1))
  else
    echo "FAIL  $label"
    FAIL=$((FAIL+1))
  fi
}

check_not_contains() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if curl -s "$BASE/$path" | grep -q -- "$pattern"; then
    echo "FAIL  $label (found stale reference)"
    FAIL=$((FAIL+1))
  else
    echo "PASS  $label"
    PASS=$((PASS+1))
  fi
}

echo "== Pages and assets return 200 =="
for f in index.html portal.html enforcement.html admin.html login.html change-password.html \
         platform-admin.html forgot-password.html reset-password.html staff-guide.html \
         manifest.webmanifest sw.js css/style.css js/app.js js/supabase-config.js icons/icon-192.png; do
  check_status "$f" 200
done

echo
echo "== Old register.html is gone =="
check_status register.html 404

echo
echo "== No stale register.html links remain in any page =="
for f in index.html portal.html enforcement.html admin.html login.html change-password.html; do
  check_not_contains "$f" "register.html" "$f has no register.html references"
done

echo
echo "== New structure markers present =="
check_contains index.html "staff-link" "index.html has the staff link"
check_contains manifest.webmanifest '"./index.html"' "manifest start_url points to index.html"
check_contains sw.js "./index.html" "sw.js precache/fallback points to index.html"

echo
echo "== Enforcement Patrol View markers present =="
check_contains enforcement.html "panel-patrol" "enforcement.html has the Patrol View panel"
check_contains enforcement.html "panel-flagged" "enforcement.html has the Flagged Vehicles tab"
check_contains enforcement.html "patrol-fab" "enforcement.html has the floating Flag button"

echo
echo "== Admin Registration History markers present =="
check_contains admin.html "panel-history" "admin.html has the Registration History panel"
check_contains admin.html "history-mode-plate" "admin.html has the plate/unit history toggle"
check_status patch-history-retention.sql 200

echo
echo "== Bug-fix markers present (exemption status + pass-count fix) =="
check_contains admin.html "getExemptionStatus" "admin.html uses the 3-state exemption status helper"
check_contains admin.html "upcoming: 'Upcoming'" "admin.html renders an Upcoming status badge"
check_contains admin.html 'value="upcoming"' "admin.html filter dropdown has an Upcoming option"
check_contains js/app.js "function getExemptionStatus" "app.js defines getExemptionStatus"
check_contains css/style.css ".status-upcoming" "style.css has the Upcoming badge style"
check_status patch-fix-pass-counting.sql 200

echo
echo "== Multi-tenant markers present =="
check_contains platform-admin.html "isPlatformAdmin" "platform-admin.html gates access with isPlatformAdmin()"
check_contains platform-admin.html "getTenants" "platform-admin.html lists tenants"
check_contains platform-admin.html "assignStaffToTenant" "platform-admin.html can assign staff to a tenant"
check_contains js/app.js "function getTenantBySubdomain" "app.js defines getTenantBySubdomain"
check_contains js/app.js "function isPlatformAdmin" "app.js defines isPlatformAdmin"
check_contains index.html "resolveTenantSubdomain" "index.html resolves tenant from hostname"
check_status patch-multi-tenant-schema.sql 200
check_status patch-multi-tenant-cutover.sql 200
check_contains enforcement.html "assigned to a building yet" "enforcement.html has a no-tenant empty state"
check_contains admin.html "assigned to a building yet" "admin.html has a no-tenant empty state"

echo
echo "== Configurable pass limits markers present =="
check_contains admin.html "panel-settings" "admin.html has the Settings panel"
check_contains admin.html "updateTenantLimits" "admin.html can save tenant pass limits"
check_contains js/app.js "function updateTenantLimits" "app.js defines updateTenantLimits"
check_contains js/app.js "function getTenantById" "app.js defines getTenantById"
check_contains index.html "monthlyLimit" "index.html reads the dynamic monthly limit"
check_status patch-tenant-limits.sql 200

echo
echo "== Bulk unit code generator markers present (platform-admin-only, full rewrite) =="
check_not_contains admin.html "openBulkModal" "admin.html no longer has the Bulk Generate button/modal"
check_contains admin.html "Platform Admin" "admin.html points staff to Platform Admin for bulk setup"
check_contains platform-admin.html "openBulkCodesModal" "platform-admin.html has the Bulk Generate button/modal"
check_contains platform-admin.html "previewBulkCodes" "platform-admin.html builds a preview before rewriting codes"
check_contains platform-admin.html "confirmBulkCodesRewrite" "platform-admin.html rewrites codes via the confirm step"
check_contains js/app.js "function bulkRegenerateUnitCodes" "app.js defines bulkRegenerateUnitCodes"
check_not_contains js/app.js "function bulkUpsertUnitCodes" "app.js no longer defines the old upsert-based bulk helper"
check_contains js/app.js "function randomUnitCode" "app.js defines the shared randomUnitCode helper"
check_contains js/app.js "UNIT_CODE_LETTERS" "app.js defines a letters-only unit code charset"
check_contains js/app.js "UNIT_CODE_NUMBERS" "app.js defines a numbers-only unit code charset"
check_contains platform-admin.html "bg-charset" "platform-admin.html lets admins choose letters/numbers/both for bulk codes"
check_status patch-bulk-regenerate-unit-codes.sql 200

echo
echo "== Range-scoped bulk regenerate + Wipe All markers present =="
check_contains js/app.js "function wipeUnitCodes" "app.js defines wipeUnitCodes"
check_contains platform-admin.html "wipe-all-codes-btn" "platform-admin.html has the Wipe All Codes button"
check_contains platform-admin.html "confirm-wipe-all-codes-btn" "platform-admin.html has the Wipe All confirm step"
check_contains platform-admin.html "Replace This Range" "platform-admin.html labels the scoped action, not a full building wipe"
check_status patch-scoped-bulk-regenerate-and-wipe-codes.sql 200

echo
echo "== Building edit + tenant status markers present =="
check_contains platform-admin.html "address-edit-modal" "platform-admin.html has the Edit Building modal"
check_contains js/app.js "function updateAddress" "app.js defines updateAddress"
check_contains platform-admin.html "tenant-status-select" "platform-admin.html has the tenant status selector"
check_contains js/app.js "function updateTenantStatus" "app.js defines updateTenantStatus"

echo
echo "== Self-service password reset markers present =="
check_contains login.html "forgot-password.html" "login.html links to Forgot Password"
check_contains js/app.js "function requestPasswordReset" "app.js defines requestPasswordReset"
check_status forgot-password.html 200
check_status reset-password.html 200

echo
echo "== Password policy + modal accessibility markers present =="
check_contains js/app.js "MIN_PASSWORD_LENGTH" "app.js defines the shared MIN_PASSWORD_LENGTH constant"
check_not_contains change-password.html "Minimum 6 characters" "change-password.html no longer shows the old 6-character hint"
check_contains js/app.js "initModalAccessibility" "app.js wires up Escape-to-close modal accessibility"

echo
echo "== Reset Demo Data markers present =="
check_contains platform-admin.html "reset-demo-btn" "platform-admin.html has the Reset Demo Data button"
check_contains platform-admin.html "trial" "platform-admin.html gates the reset button to trial tenants"
check_contains js/app.js "function resetTenantDemoData" "app.js defines resetTenantDemoData"
check_status patch-reset-demo-data.sql 200

echo
echo "== Invite Staff by Email markers present =="
check_contains platform-admin.html "inviteStaffToTenant" "platform-admin.html invites staff by email"
check_not_contains platform-admin.html "s-userid" "platform-admin.html no longer asks for a raw Supabase user ID"
check_contains js/app.js "function inviteStaffToTenant" "app.js defines inviteStaffToTenant"
check_contains js/app.js "function setInitialPassword" "app.js defines setInitialPassword"
check_status accept-invite.html 200
check_status netlify/functions/invite-staff.mjs 200
check_status package.json 200
check_contains js/app.js "tenantName" "app.js threads tenantName into the invite request"
check_contains netlify/functions/invite-staff.mjs "tenant_name" "invite-staff.mjs passes tenant_name into invite metadata"

echo
echo "== reCAPTCHA markers present (invisible, score-based) =="
check_contains index.html "grecaptcha.execute" "index.html requests an invisible reCAPTCHA token before submit"
check_not_contains index.html "g-recaptcha" "index.html has no leftover checkbox widget markup"
check_not_contains index.html "captcha_answer" "index.html no longer has the math captcha input"
check_contains js/app.js "function verifyRecaptcha" "app.js defines verifyRecaptcha"
check_not_contains js/app.js "function generateCaptcha" "app.js no longer defines the math captcha generator"
check_contains netlify/functions/verify-recaptcha.mjs "MIN_SCORE" "verify-recaptcha.mjs checks the reCAPTCHA score threshold"
check_status netlify/functions/verify-recaptcha.mjs 200

echo
echo "== In-app Staff Guide markers present =="
check_contains staff-guide.html "requireAuth('staff-guide.html')" "staff-guide.html is gated behind requireAuth"
check_contains staff-guide.html "support@regentparking.ca" "staff-guide.html points staff to support@regentparking.ca"
check_contains portal.html "staff-guide.html" "portal.html links to the staff guide"
check_contains enforcement.html "staff-guide.html" "enforcement.html links to the staff guide"
check_contains admin.html "staff-guide.html" "admin.html links to the staff guide"
check_contains login.html "New here?" "login.html has sign-in/invite help reachable without logging in first"

echo
echo "== Visitor Spots markers present =="
check_contains supabase-schema.sql "visitor_spot_prefix" "supabase-schema.sql has the visitor spot columns on addresses"
check_contains supabase-schema.sql "validate_visitor_spot" "supabase-schema.sql defines the server-side spot validation trigger"
check_contains supabase-schema.sql "update_address_visitor_spots" "supabase-schema.sql defines update_address_visitor_spots"
check_status patch-visitor-spots.sql 200
check_contains js/app.js "function buildVisitorSpotList" "app.js defines buildVisitorSpotList"
check_contains js/app.js "function updateAddressVisitorSpots" "app.js defines updateAddressVisitorSpots"
check_contains admin.html "panel-visitorspots" "admin.html has the Visitor Spots panel"
check_contains admin.html "tab-visitorspots" "admin.html has the Visitor Spots tab"
check_contains admin.html "updateAddressVisitorSpots" "admin.html can save a building's visitor spot config"
check_contains index.html "spot-group" "index.html has the (conditionally shown) visitor spot dropdown"
check_contains index.html "buildVisitorSpotList" "index.html builds the spot dropdown from the address config"
check_contains enforcement.html "<th>Spot</th>" "enforcement.html Valid Plates table has a Spot column"
check_contains enforcement.html "'Spot'" "enforcement.html CSV export includes Spot"

echo
echo "== Re-registration Cooldown markers present =="
check_contains supabase-schema.sql "reregistration_cooldown_enabled" "supabase-schema.sql has the cooldown columns on tenants"
check_contains supabase-schema.sql "reregistration_cooldown_hours" "supabase-schema.sql has the configurable cooldown-hours column"
check_contains supabase-schema.sql "update_tenant_reregistration_cooldown" "supabase-schema.sql defines update_tenant_reregistration_cooldown"
check_contains supabase-schema.sql "cooldownUntil" "supabase-schema.sql's can_register_visitor returns cooldownUntil"
check_status patch-reregistration-cooldown.sql 200
check_status test-reregistration-cooldown.sql 200
check_contains js/app.js "function updateTenantReregistrationCooldown" "app.js defines updateTenantReregistrationCooldown"
check_contains admin.html "cd-enabled" "admin.html has the cooldown enable checkbox"
check_contains admin.html "updateTenantReregistrationCooldown" "admin.html can save the cooldown setting"
check_contains index.html "cooldownUntil" "index.html handles a cooldown-blocked registration"
check_contains staff-guide.html "re-registration cooldown" "staff-guide.html documents the cooldown setting"

echo
echo "== Summary: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
