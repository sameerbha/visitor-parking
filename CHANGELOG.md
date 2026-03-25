# Changelog — Visitors Parking Management System

All changes to this project are documented here in reverse chronological order.

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
