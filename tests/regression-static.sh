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
echo "== Summary: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
