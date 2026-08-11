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
         platform-admin.html \
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
echo "== Bulk unit code generator markers present =="
check_contains admin.html "openBulkModal" "admin.html has the Bulk Generate button/modal"
check_contains admin.html "previewBulkCodes" "admin.html builds a preview before saving bulk codes"
check_contains admin.html "bulk-preview-tbody" "admin.html has the bulk preview table"
check_contains js/app.js "function bulkUpsertUnitCodes" "app.js defines bulkUpsertUnitCodes"

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
echo "== Summary: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
