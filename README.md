# Visitors Parking Management System

A static multi-portal visitor parking app backed by Supabase.

The project includes:

- A public resident registration page
- A staff enforcement portal for plate lookup and active registrations
- A staff exemptions and unit-code management portal
- Supabase Auth for staff login
- Supabase RPC functions for secure resident validation and pass-limit checks

## Portals

| Portal | File | Access |
|--------|------|--------|
| Resident Registration | `register.html` | Public |
| Visitor Enforcement | `enforcement.html` | Staff login required |
| Exemptions + Unit Codes | `exemptions.html` | Staff login required |
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
├── register.html
├── enforcement.html
├── exemptions.html
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

- `addresses`
- `visitor_registrations`
- `exemptions`
- `unit_codes`
- Row Level Security policies
- RPC functions:
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
- `exemptions.html`
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
- Monthly unit limit of 10 visitor passes
- Per-plate limit of 7 registered days per month

Each successful registration is valid for 24 hours.

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
