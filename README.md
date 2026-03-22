# Visitors Parking Management System

A multi-portal web app for managing visitor parking at condominium buildings.

## Portals

| Portal | File | Access |
|--------|------|--------|
| Resident Registration | `register.html` | Public (no login) |
| Visitor Enforcement | `enforcement.html` | Staff login required |
| Exemptions Management | `exemptions.html` | Staff login required |

---

## Running Locally

The app is pure HTML/CSS/JavaScript — no build step required.

**Option 1 — Python (recommended):**
```bash
cd "VIsitors Parking App"
python3 -m http.server 8080
# Open http://localhost:8080
```

**Option 2 — Node.js:**
```bash
npx serve .
```

**Option 3 — VS Code:**
Install the "Live Server" extension, right-click `index.html` → Open with Live Server.

---

## Demo Credentials

| Email | Password | Role |
|-------|----------|------|
| staff@condo.com | demo123 | Staff |
| admin@condo.com | admin123 | Admin |
| concierge@condo.com | demo123 | Staff |

---

## Project Structure

```
VIsitors Parking App/
├── index.html           ← Landing page (all 3 portal links)
├── register.html        ← Portal 1: Resident registration (mobile-friendly)
├── enforcement.html     ← Portal 2: Visitor enforcement (staff)
├── exemptions.html      ← Portal 3: Exemptions management (staff)
├── login.html           ← Staff login page
├── css/
│   └── style.css        ← All styles
├── js/
│   └── app.js           ← All data functions + utilities (localStorage demo mode)
├── supabase-schema.sql  ← Database schema for production deployment
└── README.md
```

---

## Connecting to Supabase (Production)

When ready to deploy with a real backend:

1. Create a free project at [supabase.com](https://supabase.com)
2. Run `supabase-schema.sql` in your Supabase SQL editor
3. Get your **Project URL** and **anon key** from Project Settings → API
4. In `js/app.js`, replace the localStorage functions with Supabase calls:

```javascript
// Example: replace getActiveVisitors() with:
const { data } = await supabase
  .from('visitor_registrations')
  .select('*')
  .eq('address_id', addressId)
  .gt('expires_at', new Date().toISOString())
  .order('registered_at', { ascending: false });
```

5. For authentication, replace `loginUser()` with `supabase.auth.signInWithPassword()`

---

## Deploying to the Web

Once connected to Supabase, deploy to any static host:

- **Netlify:** Drag & drop the folder at netlify.com/drop
- **Vercel:** `npx vercel` from the project directory
- **GitHub Pages:** Push to a repo, enable Pages in Settings

---

## Customization

**Adding a new building:**
In demo mode, edit the `DEMO_ADDRESSES` array in `js/app.js`.
In production, add a row to the `addresses` table in Supabase.

**Changing registration duration:**
In `js/app.js`, find `24*3600000` in `addVisitorRegistration()` and change to your desired hours.

**Adding staff accounts:**
In demo mode, add entries to `DEMO_USERS` in `js/app.js`.
In production, use Supabase Authentication to manage users.
