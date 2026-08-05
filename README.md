# Regent Parking — Visitor Registration

A static, multi-tenant visitor parking app backed by Supabase. "Regent Parking" is the product's public name — shown consistently to every tenant, not white-labeled per building.

The project includes:

- A public resident registration page
- A staff enforcement portal for plate lookup and active registrations
- A staff exemptions and unit-code management portal
- A platform admin portal for managing tenants across the whole system (see [Multi-Tenancy](#multi-tenancy))
- Supabase Auth for staff login
- Supabase RPC functions for secure resident validation and pass-limit checks

The Regent Parking marketing site (`regentparking.ca`, no subdomain) is a separate deploy — see `regent-parking-marketing/` — and is not part of this app.

## Portals

| Portal | File | Access |
|--------|------|--------|
| Resident Registration | `index.html` | Public — this is the site homepage |
| Staff Portal (picker) | `portal.html` | Small "Staff" link on the registration page |
| Visitor Enforcement | `enforcement.html` | Staff login required |
| Exemptions + Unit Codes | `admin.html` | Staff login required |
| Platform Admin | `platform-admin.html` | Platform admin login required — see [Multi-Tenancy](#multi-tenancy) |
| Staff Login | `login.html` | Public |
| Change Password | `change-password.html` | Logged-in staff |

## Stack

- HTML, CSS, and vanilla JavaScript
- [Supabase](https://supabase.com) Postgres database
- Supabase Auth
- Supabase JavaScript client loaded from CDN

## Current Architecture

The live app is no longer in demo `localStorage` mode. The shared data layer in `js/app.js` talks directly to Supabase for:

- Addresses
- Visitor registrations
- Exemptions
- Unit codes
- Auth

Resident validation is handled server-side through Supabase RPCs so raw unit codes are never exposed to the browser.

## Project Structure

```text
VIsitors Parking App/
├── index.html
├── portal.html
├── enforcement.html
├── admin.html
├── platform-admin.html
├── login.html
├── change-password.html
├── css/
│   └── style.css
├── js/
│   ├── app.js
│   ├── supabase-config.example.js
│   └── supabase-config.js
├── supabase-schema.sql
├── seed-unit-codes.sql
├── CHANGELOG.md
└── README.md
```

## Important Note About This Repo

This repository currently contains two copies of the app:

- The root files, which are the ones your GitHub Pages site is serving
- A duplicate `visitor-parking/` folder

If you are deploying from GitHub Pages, update the root files unless you intentionally switch your Pages source later.

## Running Locally

The app has no build step.

### Python

```bash
cd "VIsitors Parking App"
python3 -m http.server 8080
```

Open [http://localhost:8080](http://localhost:8080).

### Node

```bash
npx serve .
```

## Supabase Setup

### 1. Create a Supabase project

Create a project in [Supabase](https://supabase.com), then copy:

- Project URL
- Publishable key / anon key

### 2. Configure the frontend

Copy the example config:

```bash
cp js/supabase-config.example.js js/supabase-config.js
```

Then replace the placeholder values in `js/supabase-config.js`.

Do not use your `service_role` key in the frontend.

### 3. Create the database schema

Run [supabase-schema.sql](/Users/sameerbhaidani/Documents/VIsitors%20Parking%20App/supabase-schema.sql) in the Supabase SQL Editor.

This creates:

- `tenants`
- `addresses`
- `staff_access`
- `platform_admins`
- `visitor_registrations`
- `exemptions`
- `unit_codes`
- Row Level Security policies (tenant-scoped for staff, public for anon)
- RPC functions:
  - `is_platform_admin`, `is_tenant_member`, `has_tenant_access` — multi-tenant access checks
  - `get_tenant_staff`, `get_tenant_usage_stats` — Platform Admin portal
  - `validate_unit_code`
  - `get_monthly_pass_stats`
  - `can_register_visitor`

### 4. Seed unit codes

Run [seed-unit-codes.sql](/Users/sameerbhaidani/Documents/VIsitors%20Parking%20App/seed-unit-codes.sql) after the schema file.

This seeds 380 units for lot code `10001`:

- West tower `W201` to `W2910`
- East tower `E201` to `E1110`

### 5. Create staff users

Create staff accounts in Supabase Auth for anyone who should access:

- `enforcement.html`
- `admin.html`
- `change-password.html`

The app uses `supabase.auth.signInWithPassword()`.

## Security Model

### Public residents can:

- Read addresses
- Insert visitor registrations
- Call RPCs that validate unit codes and monthly pass limits

### Staff users can:

- View and delete visitor registrations
- View, create, update, and delete exemptions
- View, create, update, and delete unit codes

### Unit codes are protected

Residents do not read the `unit_codes` table directly. The public registration page calls server-side RPC functions instead.

## Registration Rules

The resident registration page enforces:

- A valid building selected from the `?lot=` URL parameter
- CAPTCHA
- Correct unit code
- Valid plate format
- A monthly unit pass limit (10 by default — configurable per tenant, see below)
- A per-plate day limit (7 by default — configurable per tenant, see below)

Each successful registration is valid for 24 hours.

## Configurable Pass Limits

The monthly-passes-per-unit and days-per-plate limits are per-tenant settings, not fixed values — editable from Admin's "⚙️ Settings" tab by any staff member of that tenant (any building's staff can change it, consistent with the flat access decision — there's no separate property-manager tier). They apply across every building under that tenant's account, not per-building. Existing tenants default to 10/7, matching the original fixed behavior, until changed. Run [patch-tenant-limits.sql](/Users/sameerbhaidani/Documents/VIsitors%20Parking%20App/patch-tenant-limits.sql) once in the Supabase SQL Editor to add this to an existing install.

## Registration History & Retention

Admin has a "Registration History" tab that looks up the full history — active and expired — for a given plate or unit. This works with no schema change, since the existing RLS policy already grants authenticated staff full read access to `visitor_registrations` regardless of expiry.

Rows are kept for **3 years** from their registration date, after which a scheduled job permanently deletes them. Run [patch-history-retention.sql](/Users/sameerbhaidani/Documents/VIsitors%20Parking%20App/patch-history-retention.sql) once in the Supabase SQL Editor to set this up (enables `pg_cron` and schedules a nightly purge job). This does not apply to the `exemptions` table.

## Known-Issue Fixes (2026-08-04)

Two fixes from board feedback — run [patch-fix-pass-counting.sql](/Users/sameerbhaidani/Documents/VIsitors%20Parking%20App/patch-fix-pass-counting.sql) once in the Supabase SQL Editor on any existing install:

- **Extending a registration now counts toward monthly passes.** Previously an extension silently didn't move "Monthly passes used" or "Days registered (this plate)," and nothing capped repeat extensions. The patch adds an `extension_count` column and updates `get_monthly_pass_stats()`/`extend_visitor_registration()` accordingly.
- **Admin exemptions now show "Upcoming" for future-dated rows** instead of "Expired" — this one is a frontend-only fix (`js/app.js`, `admin.html`), no SQL to run.

## Multi-Tenancy

As of 2026-08-05 this app supports more than one customer ("tenant") sharing the same Supabase project. A **tenant** is the paying customer (a condo corporation or management company) and can own multiple **addresses** (buildings/towers). DuEast is tenant #1.

**Migrating an existing single-tenant install:**

1. Run [patch-multi-tenant-schema.sql](/Users/sameerbhaidani/Documents/VIsitors%20Parking%20App/patch-multi-tenant-schema.sql) — additive only, creates the `tenants`, `staff_access`, and `platform_admins` tables, adds `tenant_id` to `addresses`, and backfills a "DuEast" tenant. This does not change any existing RLS policy or affect current staff logins.
2. Follow the instructions at the bottom of that file to make yourself a platform admin and backfill every existing staff login into `staff_access` — this must happen before step 3, or existing staff will see empty screens once tenant scoping is enforced.
3. Run [patch-multi-tenant-cutover.sql](/Users/sameerbhaidani/Documents/VIsitors%20Parking%20App/patch-multi-tenant-cutover.sql) — this is the step that actually enforces tenant scoping on `addresses`, `visitor_registrations`, `exemptions`, and `unit_codes`. Log in as an existing staff account immediately after and confirm you still see the expected data.

**Platform Admin (`platform-admin.html`):** for managing tenants across the whole system — create a tenant, add buildings under it, assign staff (by Supabase user ID — account creation itself is still done manually in the Supabase dashboard), and view basic usage per tenant. Gated by the `platform_admins` allow-list table, checked via `is_platform_admin()`.

**Resident-facing tenant resolution:** `index.html` resolves which tenant a visit belongs to from the hostname (`dueastparking.netlify.app` is mapped explicitly; `<subdomain>.regentparking.ca` resolves from the subdomain itself), then defaults to that tenant's first address. The `?lot=` URL parameter still works as a manual override for a specific building, same as before.

**What's intentionally not built yet:** self-service tenant signup, automated billing, and any permission tier between "platform admin" and "any staff member of a tenant can do everything that tenant's staff can do." All straightforward to add later on top of this foundation, not blockers to running a second tenant today.

## Row Level Security Note

The `visitor_registrations` insert policy should allow both `anon` and `authenticated` roles. This matters because a browser may already have a cached Supabase session when loading the public registration page.

Expected policy:

```sql
CREATE POLICY "Public can register visitors"
  ON visitor_registrations
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);
```

## Deployment

This app can be deployed to any static host.

### GitHub Pages

1. Push the root app files to your repository
2. Enable GitHub Pages in repo settings
3. Confirm Pages is serving the root site you expect

If you update only the duplicate `visitor-parking/` folder, your live Pages site may not change.

## Updating GitHub

Typical flow:

```bash
git status
git add .
git commit -m "Update visitor parking app"
git push
```

## Troubleshooting

### Registration shows "Something went wrong"

Check:

- `js/supabase-config.js` has the correct project URL and anon key
- `supabase-schema.sql` has been run
- `seed-unit-codes.sql` has been run
- The `visitor_registrations` insert policy allows `anon, authenticated`
- The address row exists for the lot code in the URL

### Unit code looks correct but validation fails

Check:

- The unit exists in `unit_codes`
- The unit belongs to the same `address_id`
- `seed-unit-codes.sql` ran successfully

### Staff login fails

Check:

- The user exists in Supabase Auth
- The password is correct
- The browser is pointing at the right Supabase project

## Next Cleanup Recommendation

To reduce confusion, consider removing the duplicate `visitor-parking/` copy or making it the only deployable app directory.
