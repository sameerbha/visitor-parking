# Changelog — Visitors Parking Management System

All changes to this project are documented here in reverse chronological order.

---

## [2.2.2] — 2026-08-06

### Gold brand accent + tenant badge across the app

Connects the app's own UI to the marketing site's navy/gold identity without a full reskin of the resident registration or staff pages, which stay task-focused rather than "landing page" styled.

- **Wordmark:** every "Regent Parking" logo/heading across `index.html`, `portal.html`, `login.html`, `change-password.html`, `enforcement.html`, `admin.html`, and `platform-admin.html` now renders "Parking" in the marketing site's gold (`--gold`/`--gold-light`, matching `regent-parking-marketing/css/style.css` exactly, not the separate navy/gold mockup that was proposed).
- **Tenant badge:** a small pill next to the wordmark shows which building the current session is for — on `index.html` (the resident registration page) and `enforcement.html`/`admin.html` (staff, next to the header logo), reusing each page's existing `currentAddress` context. Not added to `platform-admin.html`, `portal.html`, `login.html`, or `change-password.html`, since none of those pages have a single-building context to show.
- New CSS: `--gold`/`--gold-light` variables, `.gold-accent`/`.gold-accent-dark` (light gold for dark backgrounds, darker gold for white backgrounds), `.tenant-badge`.

**Files changed:** `css/style.css`, `index.html`, `enforcement.html`, `admin.html`, `portal.html`, `login.html`, `change-password.html`, `platform-admin.html`, `CHANGELOG.md`

---

## [2.2.1] — 2026-08-05

### Domain correction: regentparking.ca, not .net

The registered domain is `regentparking.ca`. Updated `index.html`'s hostname-based tenant resolution (`resolveTenantSubdomain()`) and related comments/docs accordingly. Earlier changelog entries in this file referencing `.net` reflect what was true when written and are left as historical record.

**Files changed:** `index.html`, `patch-multi-tenant-schema.sql`, `platform-admin.html`, `README.md`, `CHANGELOG.md`

---

## [2.2.0] — 2026-08-05

### Configurable per-tenant pass limits

The monthly-passes-per-unit (10) and days-per-plate (7) limits were hardcoded across every tenant. They're now per-tenant settings.

- **New `⚙️ Settings` tab in Admin** — any staff member of a tenant can view and change their own account's `monthly_pass_limit` and `plate_day_limit`. Applies across every building under that tenant, not per-building. Bounded server-side (1–500 and 1–31 respectively) so a typo can't accidentally disable registration.
- **`get_monthly_pass_stats()` and `can_register_visitor()`** now read the calling address's tenant's configured limits instead of hardcoded values, and the "limit reached" messages interpolate the tenant's actual numbers instead of always saying "10" or "7."
- **`index.html`'s pass-usage bars** now render against the tenant's actual limit (via new `monthlyLimit`/`plateLimit` fields on the stats response) instead of assuming 10/7.
- **New RPC `update_tenant_limits`** is the only way to change these — checks tenant membership and validates ranges before writing.
- Existing tenants default to 10/7 (the original fixed values) until they change it — `patch-tenant-limits.sql` backfills this with zero behavior change on existing installs.

**Files changed:** `supabase-schema.sql`, `patch-tenant-limits.sql` (new), `js/app.js`, `index.html`, `admin.html`, `tests/regression-static.sh`, `tests/regression-functional.mjs`, `README.md`, `CHANGELOG.md`

---

## [2.1.0] — 2026-08-05

### Rebrand: Regent Parking

The product now has a public name — "Regent Parking" — consistent across every tenant, not white-labeled per building. Updated page titles and header branding on `index.html`, `portal.html`, `enforcement.html`, `admin.html`, `platform-admin.html`, `login.html`, `change-password.html`, and `manifest.webmanifest`. The resident registration page now shows "Regent Parking" as the product name with "Visitor Registration" as a tagline, followed by the existing dynamic building line ("Registering at 225 Sumach Street") — the tenant's own building context is unchanged, it now just sits under the product's brand instead of a generic "Visitor Parking" label.

A separate marketing site for regentparking.net (the bare domain, no subdomain) is being built as its own deploy — see `regent-parking-marketing/` — and is intentionally decoupled from this app; nothing about how tenants or residents use this app changes.

**Files changed:** `index.html`, `portal.html`, `enforcement.html`, `admin.html`, `platform-admin.html`, `login.html`, `change-password.html`, `manifest.webmanifest`, `css/style.css`, `CHANGELOG.md`, `README.md`

---

## [2.0.0] — 2026-08-05

### Multi-tenant foundation: tenants, tenant-scoped staff access, Platform Admin portal

DuEast's owner is planning to sell this app to other condo buildings under a new brand (Regent Parking), with each customer on its own subdomain (e.g. `dueast.regentparking.net`). This release makes the single-tenant app safe to run for more than one unrelated customer on the same Supabase project — the previous architecture had no boundary preventing one building's staff from seeing another's residents' plates.

- **New `tenants` table**, sitting above `addresses`. A tenant is the paying customer (a condo corporation or management company); a tenant can own multiple addresses (e.g. DuEast's two towers). DuEast becomes tenant #1 via backfill.
- **New `staff_access` table** maps a staff login to the tenant(s) they belong to. **New `platform_admins` table** is a simple allow-list for cross-tenant management — seeded manually via the SQL Editor, same as the very first staff account ever was.
- **RLS rewrite:** `addresses`, `visitor_registrations`, `exemptions`, and `unit_codes` policies for the `authenticated` role now check tenant membership (`has_tenant_access()` / `is_tenant_member()`) instead of "any logged-in staff sees everything." The anon-facing resident flow is untouched — those policies were never tenant-restricted.
- **New `platform-admin.html`:** create tenants, add buildings under a tenant, assign staff (by Supabase user ID — account creation stays manual in the Supabase dashboard for now), and view basic per-tenant usage (registrations this month, active units, building count). Gated by `is_platform_admin()`.
- **Hostname-based tenant resolution** on `index.html`: resolves the tenant from the URL's hostname (`dueastparking.netlify.app` mapped explicitly; `<subdomain>.regentparking.net` resolved from the subdomain) instead of always defaulting to "the first address in the whole system," which was a latent bug once more than one address could exist. `?lot=` still works as a manual override.
- **Graceful empty state:** a staff login with no tenant assigned now sees a clear "contact your administrator" message in Enforcement/Admin instead of silently empty tables.
- **Two-step migration** (`patch-multi-tenant-schema.sql` then `patch-multi-tenant-cutover.sql`) so existing staff logins are backfilled into `staff_access` before tenant-scoped RLS is actually turned on — additive first, enforcement second, to avoid locking anyone out mid-migration.
- **Known test gap:** the functional regression script runs entirely as the anon role and can't exercise the new tenant-scoped staff policies. Verifying tenant isolation after the cutover requires a manual check — log in as an existing staff account and confirm the expected data still shows.
- **Deliberately not built yet:** self-service tenant signup, automated billing, and any permission tier between "platform admin" and "any staff member of a tenant." Both are reasonable additions on top of this foundation later, not blockers today.

**Files changed:** `supabase-schema.sql`, `patch-multi-tenant-schema.sql` (new), `patch-multi-tenant-cutover.sql` (new), `platform-admin.html` (new), `js/app.js`, `index.html`, `enforcement.html`, `admin.html`, `css/style.css`, `tests/regression-static.sh`, `tests/regression-functional.mjs`, `README.md`, `CHANGELOG.md`

---

## [1.10.1] — 2026-08-04

### Bug fix: extending a registration didn't move the pass counters

Board feedback caught that extending a plate's registration left "Monthly passes used" and "Days registered (this plate)" unchanged, even though the app's own copy said an extension uses one of the unit's passes.

- **Root cause:** `extend_visitor_registration()` only updated `expires_at` on the existing row — it never inserted a new row and never touched `registered_at`, so `get_monthly_pass_stats()` (which counts rows registered this month) had nothing new to count. In practice this also meant nothing capped how many times a plate could be extended.
- **Fix:** added an `extension_count` column to `visitor_registrations`, incremented on each extend. `get_monthly_pass_stats()` now counts `(1 + extension_count)` per row instead of a flat row count, so each extension counts as a pass — and the existing 7-day-per-plate cap in `can_register_visitor()` now actually applies to extensions, not just new registrations. `patch-fix-pass-counting.sql` (new) migrates existing installs.
- **Tests extended:** `regression-functional.mjs` now compares pass stats before and after an extend and fails if the counters don't move.

**Files changed:** `supabase-schema.sql`, `patch-extend-registration.sql`, `patch-fix-pass-counting.sql` (new), `tests/regression-functional.mjs`, `CHANGELOG.md`

---

### Bug fix: exemptions with a future start date showed as "Expired"

Board feedback flagged two exemptions with date ranges entirely in the future showing a red "Expired" badge in Admin.

- **Root cause:** `isActive()` only ever returns true/false (`start_date <= today && end_date >= today`). The exemptions table collapsed both "not started yet" and "already ended" into the same "Expired" label — there was no third state.
- **Fix:** added `getExemptionStatus()`, a three-state version (`active` / `upcoming` / `expired`) used only for display in Admin's exemptions table, filter dropdown, and CSV export. `isActive()` itself is unchanged and still gates enforcement.html's Patrol View, where "not active today" is the only thing that should matter.

**Files changed:** `js/app.js`, `admin.html`, `css/style.css`, `tests/regression-static.sh`, `CHANGELOG.md`

---

## [1.10.0] — 2026-07-23

### Admin: Registration History, with a 3-year retention policy

In response to management's question about surfacing plate/unit permit history (raised alongside the board's original security review), Admin now has a "📜 Registration History" tab.

- **Look up by plate or unit:** a small toggle switches the search between the two; results show every registration for that plate/unit — active and expired — most recent first, with an Export CSV option matching the pattern used elsewhere in the app.
- **No schema change needed to read it.** Staff accounts already had full read access to `visitor_registrations` regardless of expiry via the existing RLS policy — this was a missing screen, not a missing permission.
- **3-year retention, not indefinite by default.** Previously nothing deleted expired registrations automatically, so history was being kept forever by omission rather than by decision. `patch-history-retention.sql` (new) enables `pg_cron` and schedules a nightly job that permanently deletes any registration older than 3 years, measured from its registration date. This applies to `visitor_registrations` only — the exemptions log is unaffected, per this round's explicit scope.
- **Tests extended:** `regression-static.sh` checks the new tab and migration file exist; `regression-functional.mjs` now also verifies a test registration is retrievable through the same plate/unit history queries the new screen uses.

**Files changed:** `admin.html`, `js/app.js`, `css/style.css`, `supabase-schema.sql`, `patch-history-retention.sql` (new), `tests/regression-static.sh`, `tests/regression-functional.mjs`, `README.md`, `CHANGELOG.md`

---

## [1.9.4] — 2026-07-22

### Tab bar: 2x2 grid instead of horizontal scroll on mobile

With four tabs (Valid Plates, Patrol View, Flagged, Plate Lookup), a horizontally-scrolling tab bar on phones in the iPhone SE/12/13/14 or Galaxy S22/S23 range hid at least one tab off-screen with only a sliver visible — easy to miss entirely, and scrolling isn't an expected gesture for primary navigation. Replaced with a 2x2 wrapped grid: all four tabs visible at once, no scrolling, ~44px minimum tap height maintained.

**Files changed:** `css/style.css`, `CHANGELOG.md`

---

## [1.9.3] — 2026-07-22

### Bug fix: other pages silently loading index.html

`sw.js` registers with site-wide scope (registered from `index.html`, but a service worker's scope is the whole origin by default), and its navigation fallback didn't check which page it was falling back for — any failed fetch on any page fell back to serving the cached `index.html`. In practice this meant `enforcement.html` (and potentially `admin.html`, `login.html`, `portal.html`, `change-password.html`) could silently render the resident registration form instead of themselves on any network hiccup, looking exactly like an unexplained redirect back to the main screen.

- The navigate handler in `sw.js` now only applies its offline fallback when the request is actually for the app entry point (`/` or `index.html`). Every other page now behaves like a normal page load with no service worker interference if its fetch fails, instead of substituting a different page's content.
- Bumped `CACHE_VERSION` to force browsers carrying the old worker to install the fixed one.

**If you still see this after pulling the fix:** the old service worker may still be active in your browser. Hard-refresh, or clear it manually via DevTools → Application → Service Workers → Unregister (or just test in a private/incognito window), then reload.

**Files changed:** `sw.js`, `CHANGELOG.md`

---

## [1.9.2] — 2026-07-22

### Mobile readability pass

- **Flagged Vehicles:** plate and spot now render on their own lines with a clear size hierarchy (plate largest, spot second, description smallest), bumped further under the mobile breakpoint (plate 1.7rem, spot 1.25rem on phones) — legible at a glance instead of one small combined line.
- **Search inputs** (Valid Plates and Patrol View both use the same component): mobile padding/font-size increased and a minimum 48px height added, since the previous size carried over unchanged from desktop and was cramped on an iPhone 12/14 Pro Max.

**Files changed:** `enforcement.html`, `css/style.css`, `CHANGELOG.md`

---

## [1.9.1] — 2026-07-22

### Patrol View: mobile ergonomics rework

The first pass at making Flag Vehicle/Reset checks thumb-friendly overcorrected — full-width 48px buttons plus the inline flagged list pushed the actual plate list below the fold, defeating the point of a view meant for quickly scanning plates. Restructured instead of just resizing:

- **Flagged Vehicles is now its own tab** ("🚩 Flagged (N)"), not an inline section in Patrol View. Reviewing/copying/clearing flagged vehicles happens at the desk, not mid-walk, so it no longer competes with the scanning list for screen space.
- **Flag button is now a floating action button**, pinned to the bottom-right corner via `position:fixed`. It's reachable at any scroll position without taking up space in the content flow.
- **Reset checks is now a small text link** next to the counter — sized for an easy tap (~44px target via padding) without visually dominating the screen for an action used once per patrol.
- **Tab bar scrolls horizontally on mobile** rather than wrapping or clipping, now that there are four tabs.

**Files changed:** `enforcement.html`, `css/style.css`, `CHANGELOG.md`

---

## [1.9.0] — 2026-07-22

### Patrol View: flag unregistered vehicles

New "🚩 Flag Vehicle" action in Patrol View for logging cars found in the garage that aren't on the valid or exempt list, so staff can call it in to the city from the desk without relying on a paper notebook.

- **Quick-entry modal:** plate (required), spot/location (required), and an optional vehicle description (e.g. "Black SUV") — each entry is timestamped automatically.
- **Flagged list:** shown inline in Patrol View once at least one vehicle is flagged, most recent first, each with a one-tap Remove in case a car leaves before the sweep is done.
- **Copy list:** formats the flagged list as plain text (plate — spot — description — time) to the clipboard, meant to be read straight off the phone during the call to the city.
- **Local and session-only, by design:** flagged vehicles are stored in `localStorage` keyed by address and day — never sent to Supabase. Same data-minimization reasoning as the phone number removal above: there's no ongoing need to retain a log of strangers' plates once they've been called in, so the simplest thing is to not create a new place that data lives. A "Clear flagged list" button (with a confirmation prompt, since this one holds data staff may still need) resets it after the call.

**Files changed:** `enforcement.html`, `css/style.css`, `CHANGELOG.md`

---

## [1.8.0] — 2026-07-22

### Removed phone number collection entirely

We no longer ask residents for a phone number when registering a visitor, and no longer store one. This wasn't just a form field — the underlying column is being dropped from the database, so no phone numbers persist anywhere in the system going forward.

**Why:** data minimization — collecting personal information you don't have a clear operational need for is exactly the kind of thing a PIPEDA-style privacy review flags. Removing a field entirely is simpler than trying to secure, retain-limit, and eventually justify data nobody actually uses day to day.

- **`index.html`** — removed the "Your Phone Number" field, its validation, and its inclusion in the registration payload.
- **`enforcement.html`** — removed the Phone column from the Valid Plates table, the CSV export, and the search filter.
- **`supabase-schema.sql`** — `tenant_phone` removed from the `visitor_registrations` table definition (source of truth for new installs).
- **`patch-remove-tenant-phone.sql`** (new) — migration to run in the Supabase SQL Editor on existing databases: `ALTER TABLE visitor_registrations DROP COLUMN IF EXISTS tenant_phone;`. This permanently deletes any phone numbers already stored.
- **`tests/regression-functional.mjs`** — updated to stop sending a phone number in its test registration.

**Files changed:** `index.html`, `enforcement.html`, `supabase-schema.sql`, `patch-remove-tenant-phone.sql` (new), `tests/regression-functional.mjs`, `CHANGELOG.md`

---

## [1.7.0] — 2026-07-22

### Enforcement: Patrol View

New third tab on `enforcement.html`, alongside Valid Plates and Plate Lookup, built for concierge/security walking the physical garage on a phone rather than working from a desk.

- **Plates only, big and legible.** Strips the dense 7-column table down to just the plate (large monospace text) and unit number — nothing to parse, nothing to accidentally tap.
- **Tap to check off.** Tapping a row dims it with a strikethrough so staff can track which cars they've already confirmed while walking a row of parked vehicles. A counter shows "X of Y checked" and a "Reset checks" button clears it for the next round.
- **Persists per building per day.** Checked-off state is saved to `localStorage` keyed by address and date, so a dropped connection or accidental reload mid-patrol doesn't lose progress. It naturally resets the next day.
- **Same search, no destructive actions.** Carries over the existing plate/unit search but drops the Remove button — that stays a desk-only action.
- **Handles connection loss gracefully.** Underground garages are common dead zones. `getActiveVisitors()` now surfaces fetch errors instead of silently returning an empty list, so a failed refresh keeps showing the last successfully loaded plates with a "Connection issue — showing the last list that loaded successfully" note, instead of blanking the screen.
- **Exempt plates are included and clearly flagged.** Active exemptions (from the `exemptions` table, date-filtered client-side) are merged into the same alphabetical list as visitor registrations. Exempt rows get a blue left-accent and a persistent "EXEMPT" badge that stays visible even after the row is checked off, so staff can see at a glance not to ticket that plate — this was previously only checkable one plate at a time via the Plate Lookup tab.

**Files changed:** `enforcement.html`, `css/style.css`, `js/app.js`, `CHANGELOG.md`

---

## [1.6.0] — 2026-07-22

### Landing page restructure: registration form is now the homepage

Residents were landing on a 3-card portal picker and having to tap through to the registration form — an unnecessary step for the overwhelming majority of visitors to the site, who are residents registering a guest. The site is now structured around that primary task:

- **`index.html`** is now the visitor registration form (formerly `register.html`). This is what loads at the site root.
- **`portal.html`** (formerly `index.html`) now holds the 3-card staff/resident picker, reachable via a small "🔒 Staff" link added to the top-right corner of the registration page.
- All internal navigation updated to match: header logo links, "Resident Portal" links, and "Back to Home" / post-login redirects across `enforcement.html`, `admin.html`, `login.html`, `change-password.html`, and `portal.html` itself.
- **PWA updates:** `manifest.webmanifest` `start_url` and `sw.js` precache/offline-fallback references updated from `register.html` to `index.html`; service worker cache version bumped to force clients to pick up the new asset list.
- **Docs updated:** `DuEast-Visitor-Parking-Guide.html`/`.txt` no longer instruct residents to "tap Register a Visitor" — landing on the site now lands directly on the form.

**Files changed:** `index.html` (new, formerly `register.html`), `portal.html` (new, formerly `index.html`), `enforcement.html`, `admin.html`, `login.html`, `change-password.html`, `css/style.css`, `sw.js`, `manifest.webmanifest`, `DuEast-Visitor-Parking-Guide.html`, `DuEast-Visitor-Parking-Guide.txt`, `CHANGELOG.md`

---

## [1.5.0] — 2026-03-25

### Duplicate Plate / Extend Flow

When a resident tries to register a plate that is already actively registered, the system now intercepts and offers to extend the existing registration by 24 hours instead of creating a duplicate.

**Flow:**
1. Resident submits the form as normal
2. After unit code validation, the system checks if the plate is already active (`check_plate_active` RPC)
3. If active, an **extend prompt** replaces the form — showing the current expiry and the new expiry after extension
4. Resident clicks **"Extend by 24 Hours"** — the existing record's `expires_at` is pushed forward, no new booking created
5. Success screen shows the updated expiry time with pass usage bars
6. Resident can cancel and return to the form if they made a mistake

**Rules enforced server-side (`extend_visitor_registration` RPC):**
- Unit code must be valid
- Only the unit that originally registered the plate can extend it
- Extension counts as a new monthly pass (blocked if unit is at the 10/month limit)
- Unlimited extensions allowed (useful for long-stay guests)

**Files changed:** `patch-extend-registration.sql` (new — run in Supabase SQL Editor), `js/app.js`, `register.html`, `css/style.css`, `CHANGELOG.md`

**Required Supabase step:** Run `patch-extend-registration.sql` in the SQL Editor to add the two new RPC functions.

---

## [1.4.0] — 2026-03-23

### Success screen: colour-coded pass usage progress bars

The registration success screen now displays two animated progress bars showing how much of the monthly allowance the unit has used.

- **Monthly passes used** (X / 10) — tracks all visitor registrations for the unit this month
- **Days registered for this plate** (X / 7) — tracks how many distinct days this specific plate has been registered

Both bars transition **green → amber → red** as the limit approaches (>50% = amber, >80% = red). The count label matches the bar colour, and a "X remaining this month" line sits below each bar. When a limit is fully reached the label reads "No passes remaining this month" in red.

**Files changed:** `register.html`, `css/style.css`, `CHANGELOG.md`

---

## [1.3.0] — 2026-03-22

### Production: Full Supabase integration

All pages and the shared data layer have been fully migrated from localStorage demo mode to Supabase (PostgreSQL + Supabase Auth). The app is now production-ready.

**`supabase-schema.sql`** — Complete rewrite:
- Tables: `addresses`, `visitor_registrations`, `exemptions`, `unit_codes`
- Row Level Security (RLS) policies: anonymous users can insert visitor registrations; authenticated staff can read/write all tables
- Three SECURITY DEFINER RPCs (unit codes never exposed to the client):
  - `validate_unit_code(p_unit_number, p_address_id, p_code)` → boolean
  - `get_monthly_pass_stats(p_unit_number, p_address_id)` → JSON stats
  - `can_register_visitor(p_unit_number, p_address_id, p_plate)` → `{ allowed, reason }`
- Seed data: 225 Sumach Street, lot_code `10001`

**`js/app.js`** — Complete rewrite:
- All data functions are now `async` and talk directly to Supabase via the JS client
- Auth migrated to Supabase Auth (`signInWithPassword`, `signOut`, `updateUser`, `getUser`)
- `validateUnitCode`, `canRegisterVisitor`, `getMonthlyPassStats` now call server-side RPCs
- localStorage removed entirely

**`js/supabase-config.js`** (gitignored) — Placeholder config file; copy from `supabase-config.example.js` and fill in project URL + anon key.

**`js/supabase-config.example.js`** (committed) — Safe template for the above.

**`.gitignore`** — Added `js/supabase-config.js` and `.Rhistory`.

**HTML pages updated** — All five pages now load the Supabase CDN, config, and app scripts in the correct order. Page-init logic wrapped in `async () => { … }()` IIFEs; all data calls `await`ed; event handlers made `async`:
- `enforcement.html` ✓
- `exemptions.html` ✓
- `register.html` ✓
- `login.html` ✓
- `change-password.html` ✓

**Files changed:** `supabase-schema.sql`, `js/app.js`, `js/supabase-config.js` (new), `js/supabase-config.example.js` (new), `.gitignore`, `enforcement.html`, `exemptions.html`, `register.html`, `login.html`, `change-password.html`, `CHANGELOG.md`

---

## [1.0.0] — 2026-03-21

### Initial Build
Complete initial prototype of the Visitors Parking Management System.

**Files created:**
- `index.html` — Landing page with links to all three portals
- `register.html` — Portal 1: Resident visitor registration (mobile-friendly, math CAPTCHA, 24-hour registration)
- `enforcement.html` — Portal 2: Staff enforcement portal (active plate table, plate lookup, CSV export, auto-refresh)
- `exemptions.html` — Portal 3: Staff exemptions management portal (full CRUD, active/expired filter, CSV export)
- `login.html` — Staff authentication page
- `css/style.css` — Global stylesheet (navy/green theme, responsive)
- `js/app.js` — Shared data layer (localStorage demo mode, all CRUD functions, auth, utilities)
- `supabase-schema.sql` — PostgreSQL schema for production deployment on Supabase
- `README.md` — Setup and deployment instructions

**Architecture:**
- Pure HTML/CSS/JavaScript — no build tools or frameworks required
- Demo mode uses `localStorage` for all data persistence
- Designed to be swapped for Supabase backend when ready for production
- Staff portals protected by session-based auth guard (`requireAuth()`)

---

## [1.1.0] — 2026-03-21

### Registration Form: UI & field changes (`register.html`)
- **Removed** the Building / Lot dropdown field. The building is now determined silently from the `?lot=` URL parameter (e.g. `register.html?lot=19864`). The building name is shown in the page subtitle for confirmation. Falls back to the first address if no parameter is provided.
- **Removed** the placeholder text from the "Your Phone Number" field.
- **Removed** the placeholder text from the "Your Unit Number" field.
- **Added** new "Unit Code" field (password input) — residents must enter their unit's unique parking code to authenticate before registering a visitor. Hint text reads: *"Your unit code is provided by building management."*
- **Added** pass statistics box on the success screen, showing monthly passes used and days the registered plate has been registered this month.

### Registration Form: Validation rules (`register.html`, `js/app.js`)
- **Rule 1 — Monthly pass cap:** A unit may register a maximum of **10 visitor parking passes per calendar month**. On the 1st of each month the count resets.
- **Rule 2 — Per-plate day cap:** A single licence plate may be registered on no more than **7 distinct calendar days per month** (per unit). Registering the same plate twice on the same day counts as one day.
- **Rule 3:** Once either limit is reached, further registrations are blocked with a clear error message until the next month.
- Validation order: CAPTCHA → unit code → plate format → monthly limits.

### Unit Codes management (`js/app.js`, `exemptions.html`, `css/style.css`)
- **Added** unit codes data model to `app.js`: `getUnitCodes()`, `getUnitCode()`, `addUnitCode()`, `updateUnitCode()`, `deleteUnitCode()`, `validateUnitCode()`.
- **Added** monthly pass validation functions to `app.js`: `getMonthlyPassStats()`, `canRegisterVisitor()`.
- **Added** demo seed data for unit codes (`DEMO_UNIT_CODES`) covering units W403, 1204, 802 (address 1) and 301 (address 2).
- **Added** "Unit Codes" tab to `exemptions.html`:
  - Table shows unit number, code (highlighted badge), created by, created date, last reset date.
  - Staff can **add** a new unit code (with "Generate" button for random codes), **edit/reset** an existing code, and **delete** a code.
  - Duplicate unit numbers per address are blocked on creation.
  - The `+ Add` toolbar button dynamically switches between "Add Exemption" and "Add Unit Code" depending on the active tab.
- **Added** CSS for `.code-badge` and `.unit-codes-info` info banner.

**Files changed:** `js/app.js`, `register.html`, `exemptions.html`, `css/style.css`, `CHANGELOG.md`

---

## [1.2.0] — 2026-03-22

### Security: Hashed passwords, users in localStorage, Change Password feature

- **`login.html`** — Removed the demo credentials hint block entirely.
- **`js/app.js`** — `DEMO_USERS` now stores SHA-256 hashes. No plaintext password exists anywhere in the codebase or localStorage.
- **`js/app.js`** — Added `hashPassword()` using the browser's built-in Web Crypto API — no external dependencies.
- **`js/app.js`** — `loginUser()` is now async: hashes the entered password and compares against the stored hash.
- **`js/app.js`** — Added `changePassword()`: verifies current password before writing new hash to localStorage.
- **`js/app.js`** — `initDemoData()` seeds `vp_users` into localStorage and migrates any existing browsers with plaintext-password records.
- **`change-password.html`** — New page for logged-in staff to change their own password.
- **`enforcement.html` / `exemptions.html`** — Added 🔒 Password button in the staff header.

**Default credentials (first load only):** `staff@condo.com` / `demo123` — change via the 🔒 Password button after first login.

**Files changed:** `login.html`, `js/app.js`, `change-password.html` (new), `enforcement.html`, `exemptions.html`, `CHANGELOG.md`

---

## [1.1.3] — 2026-03-22

### UI: Move "+ Add" button into tab bar on Exemptions page

The "+ Add Exemption" button was floating alone in the toolbar above the tabs, which looked disconnected. It was also being hidden along with the address dropdown when there is only one building, making it unreachable.

- Moved the button into the tab bar, right-aligned using a flex spacer — tabs on the left, action button on the right
- Button label still switches dynamically between "+ Add Exemption" and "+ Add Unit Code" based on the active tab
- Removed the button from the toolbar so it is always visible regardless of the address dropdown visibility
- Added `.tab-bar-spacer` utility class to `style.css` for the flex push

**Files changed:** `exemptions.html`, `css/style.css`, `CHANGELOG.md`

---

## [1.1.2] — 2026-03-21

### Bug fix: Error messages not visible on mobile after pressing Submit

**Root cause:** The `#form-error` banner was positioned at the very top of the form, above all the input fields. On a phone, after filling in the form, the user's viewport is scrolled down to the Submit button. When a validation error occurred (e.g. wrong captcha answer, incorrect unit code), the error banner appeared off-screen at the top — leaving no visible feedback.

**Fixes applied:**

- **`register.html` — error banner relocated:** Moved `#form-error` from the top of the form to directly above the Submit button. Errors now appear right where the user's eyes are.
- **`register.html` — `showError()` helper:** All error display logic is now in a single `showError(msg)` function that sets the message and calls `scrollIntoView({ behavior:'smooth', block:'center' })` so the error is always visible.
- **`register.html` — success scroll:** After a successful registration, the success screen scrolls into view.

**Files changed:** `register.html`, `CHANGELOG.md`

---

## [1.1.1] — 2026-03-21

### Bug fix: Submit button did nothing on `register.html`

**Root cause:** `initDemoData()` in `js/app.js` only seeded `vp_unit_codes` on the very first page load (when `vp_initialized` was absent). Any browser that had loaded the v1.0.0 build already had `vp_initialized = 'true'` in localStorage, so the unit codes were never written. Every subsequent call to `validateUnitCode()` would immediately return "Unit number not found", but because the error appeared as a form validation failure — and the page may have been opened without seeing the first error render — users perceived the button as doing nothing.

**Fixes applied:**

- **`js/app.js` — localStorage migration:** Added an `else` branch to `initDemoData()` that checks for the presence of `vp_unit_codes` independently of the `vp_initialized` flag. If `vp_unit_codes` is missing (old data), the demo seed records are written immediately, unblocking validation for existing sessions.
- **`register.html` — defensive initialisation:** Wrapped the entire inline `<script>` block in a `try / catch`. Any JavaScript error thrown during page setup (e.g. a missing DOM element or a future regression) is now caught, logged to the browser console with a clear label, and shown to the user in the `#form-error` banner rather than silently preventing the submit listener from being attached.

**Files changed:** `js/app.js`, `register.html`, `CHANGELOG.md`

---

*Future changes will be appended above this line.*
