# Regent Parking — Pre-GA UX & Feature-Gap Audit

Date: 2026-08-11
Scope: code-based review of every page and flow in the app (`index.html`, `portal.html`, `login.html`, `change-password.html`, `accept-invite.html`, `enforcement.html`, `admin.html`, `platform-admin.html`, `css/style.css`, `js/app.js`, and the marketing site). Live-rendering/screenshot pass was not available this run (Claude in Chrome wasn't connected) — findings are grounded in the actual code, not assumptions or the README's claims.

Effort key: **Quick win** (a few lines, hours) · **Medium** (a real feature, under a day) · **Big bet** (multi-day, architecturally significant)

---

## Live verification addendum (added after this audit)

Checked the actual live pages (`dueastparking.netlify.app`, `regentparking.ca`) via browser. Overall visual polish is strong — the navy/gold branding is consistent between the marketing site and the app, the pricing page correctly shows $139/mo billed annually, and the invisible reCAPTCHA badge is visibly present and working on the registration page.

Two things confirmed live, not just in code:

- **#9 (no loading state) is real and visible.** A screenshot taken immediately on page load shows the registration form fully interactive with no building name shown; a screenshot taken 2 seconds later shows the gold "225 Sumach Street" badge has appeared. There's a genuine window where a fast resident could submit before the tenant resolves.
- **#5 (low placeholder contrast) is visible at a glance** — "Enter your unit's parking code" and "E.G. ABCD 123" are both noticeably faint against the white card, exactly as flagged.

**Limitation:** attempts to force a true narrow mobile viewport (390px) didn't take — the screenshot tool kept returning a ~1328px-wide capture regardless of the resize call, so the mobile-specific CSS breakpoints (e.g. `.form-row` collapsing, the removed narrow-screen scaling rule) weren't directly visually verified this pass. The card-based centered layout looks the same shape at this width as it presumably does narrower, which is a good sign, but if mobile fidelity matters before GA, worth a manual check on an actual phone.

Also worth noting live: `login.html` genuinely has no "Forgot password" link (#14), and `portal.html`'s "Exemptions Management" card copy is confirmed stale in the rendered page, not just the source (#12).

---

## Top 5 picks before GA

1. **Fix the "stuck on Loading…" empty state** in `admin.html`/`enforcement.html` for any tenant with zero buildings (#23) — a real bug, and every newly onboarded tenant hits it before their first address is added. Quick win.
2. **Add self-service password reset for staff** (#14, #36) — right now a locked-out guard or concierge has no way back in except someone editing the database. Directly undercuts the "non-technical partner runs this day-to-day" goal. Medium.
3. **Give residents a receipt and a way to check/cancel their own registration** (#28, #29) — currently there's no confirmation email, and the only way to see an existing registration is to re-enter everything. Biggest resident-trust gap. Medium/big.
4. **Branded invite email + printable unit-code handout sheet** (#35, #33) — both quick wins, and both directly polish the exact motion you'll repeat for every new building you onboard.
5. **Basic audit trail for registration deletes and tenant/setting changes** (#40, scoped down from the full version) — the marketing pitch promises "an answer, whenever the board asks"; today there's no way to answer "who deleted this and why."

---

## SECTION 1 — UX/Design Critique

### css/style.css (site-wide)

1. **Gold heading text fails contrast on the lighter part of the blue gradient.** `.gold-accent` (`#D4AF5A`) over the `#1565c0` stop of `.resident-portal`'s gradient computes to ~2.75:1 — fails WCAG AA. Used in `index.html`'s h1. Quick win: darken the gold or reposition the heading.
2. **Gold-on-white heading text is below the AA floor everywhere it's used.** `.gold-accent-dark` (`#B8912F`) on white computes to ~2.94:1 (needs 3:1). Reused in `portal.html`, `login.html`, `accept-invite.html`, `platform-admin.html` headers. Quick win, touches a shared class on 4+ pages.
3. **Dead CSS.** `.login-demo-hint` is fully styled but unreferenced by any HTML file — leftover from the old localStorage demo mode. Quick win: delete.
4. **Repeated inline styles instead of a shared class.** `text-transform:uppercase;letter-spacing:2px;font-weight:600` is hand-copied inline in at least 6 places (`index.html:60`, `admin.html:153,207,265`, `enforcement.html:146,176`). Quick win: extract to `.input-plate`.
5. **Placeholder text contrast is very low** (`#adb5bd` on white, ~2.1:1) — hard to read, including the resident's only guidance text on the unit-code field. Quick win: darken to `#8a929a`.
6. **Small tap targets on action buttons used from phones.** `.btn-sm` renders ~26–30px tall, below the ~44px recommended minimum, and is the class used for every row-level action in tables meant to be used in the field. Medium: bump min-height inside the mobile media query.
7. **No focus-trap, no Escape-to-close, no focus return on any modal.** None of the 8+ modal instances handle `Escape`, and only 3 of ~11 modals move focus into the first field on open; none restore focus on close. Medium.

### index.html (public resident registration — used almost exclusively on phones)

8. **Unit code field is `type="password"`.** It's a shared building code, not a secret — this triggers password-manager save prompts and gets announced as "password" by screen readers. Quick win: `type="text"`, optional show/hide toggle.
9. **No loading state while resolving the tenant/address.** The form is fully interactive before `currentAddress` resolves; a fast tap on Submit gets a scary "Building not found" error that's actually just a timing race. Quick win: disable Submit until resolved.
10. **"Register Another Vehicle" clears the unit number too**, not just the code/plate — a resident registering a second guest has to retype it. Quick win.
11. **No escalation after repeated wrong-code attempts.** Same generic error every time; concierge contact info only lives in the static footer. Quick win: surface it contextually after 2-3 failures.

### portal.html

12. **Stale card copy** — the "Exemptions Management" card description doesn't mention Unit Codes, Bulk Generate, History, or Settings, all of which now live behind the same link. Quick win.
13. **No nav entry point to Platform Admin**, even for signed-in platform admins — it's only reachable by typing the URL. Its own nav is also missing the "Resident Portal ↗" link every other staff page has. Medium.

### login.html

14. **No "Forgot password" link anywhere**, and no password-reset flow exists in the codebase at all. A locked-out staff member has no self-service path back in.
15. **One-size-fits-all post-login redirect** (`enforcement.html` if no `?from=`) — a platform admin with no tenant staff access lands on a confusing "not assigned to a building" screen. Quick/medium: check `isPlatformAdmin()` and redirect accordingly.

### change-password.html

16. **Inline-style sprawl** instead of a named class, inconsistent with how every other page composes layout. Quick win.
17. **Hardcoded "← Back to Enforcement"** regardless of the user's actual access. Quick win: link to `portal.html`.
18. **Weak password policy** — 6-character minimum, no complexity check, for an account that controls building codes and can delete other residents' registrations.

### accept-invite.html

19. Actually the best-executed auth page — real loading state and a real expired/invalid-link error state. Worth using as the template for the other auth pages' missing states.

### enforcement.html

20. **Inconsistent confirmation pattern** — "Clear list" (flagged vehicles) confirms before wiping data; "↺ Reset checks" performs an equally irreversible action with zero confirmation. Quick win: match the guard.
21. **No pagination on the valid-plates table** — full re-render via `innerHTML` every 30s. Fine at DuEast's current size; a scale risk once buildings/tenants grow.
22. Empty states here are genuinely good ("No active registrations," "No results," "No vehicles flagged yet") — calling out as a positive pattern to replicate elsewhere.

### admin.html

23. **Confirmed bug: table titles get stuck on "Loading…" forever for a tenant with zero buildings.** The "not assigned to a building yet" banner shows correctly, but the tables below it stay blank with a permanently wrong title and no footer text — same pattern in `enforcement.html`. Quick win: hide the table sections entirely when there are no addresses.
24. **No export/print for Unit Codes**, only for Exemptions and History, despite the export utility already existing and wired up elsewhere. Quick win.
25. Otherwise this page's empty states are genuinely good — calling out as another positive pattern.

### platform-admin.html

26. **Addresses table has no edit or delete controls at all** — a typo'd building name or lot code can never be fixed from the UI. Medium.
27. **No way to change a tenant's status (trial → active) from the UI** — only creation sets it; converting a paying customer requires a direct database edit.

---

## SECTION 2 — GA-Readiness Feature Gaps

### (a) Resident trust & registration flow

28. **No confirmation email/SMS after registering, and no contact field exists to send one to** — the payload has no phone/email at all. Medium/big: schema change + notification integration.
29. **No way to view or cancel an existing registration without re-entering everything.** If a guest cancels, the pass stays counted against the unit's monthly quota with no resident-facing release path. Medium.
30. **No expiry reminder before the 24-hour window lapses** — real risk of a forgotten guest's car getting flagged. Big bet (needs scheduled notifications).
31. Repeats #11 from a trust angle, not just a copy angle.

### (b) Property manager evaluating/onboarding

32. **No self-serve trial signup or in-product checkout** — confirmed deliberate per README, flagging only because GA is imminent and the polished pricing page implies a snappier path than "email us." Big bet.
33. **No printable/exportable unit-code handout sheet** — directly relevant to onboarding any new building. Quick win.
34. **No way to edit a tenant's/building's details after creation** (ties to #26/#27) — onboarding typos require a database edit. Medium.
35. **No visibly branded invite email** — `tenantName` is threaded into the metadata for this exact purpose, but nothing customizes Supabase's default template yet. Quick/medium — dashboard edit, no app code change.

### (c) Security guard / staff daily use

36. **No self-service password reset for staff** — a recurring operational cost, not a one-time setup gap. Medium (Supabase Auth already supports this; needs a `forgot-password.html`/`reset-password.html` pair).
37. **Patrol state (checked plates, flagged vehicles) is per-device, local-only, and never reaches the server.** Two guards on two phones don't see each other's progress, and clearing a phone's storage loses the flagged list with no durable record. Real operational/audit gap for a security tool. Big bet.
38. **No bridge between "Flag Unregistered Vehicle" and "Add Exemption"** — a guard finding a legitimate-but-unregistered vehicle has to leave Patrol View and retype the plate in Admin. Medium.

### (d) Business operating at scale

39. **No cross-tenant health dashboard** — Platform Admin's Tenants table shows only Name/Subdomain/Status/Building count; no aggregate view of activity, staff counts, or last-active timestamps across tenants. Medium/big.
40. **No audit/activity log** — no record of who edited/deleted a registration, removed staff, or changed tenant settings. Directly at odds with the marketing pitch's promise of "an answer, whenever the board asks." Big bet.
41. **No self-serve billing** — no payment integration anywhere; `tenant.status` is a manually-set flag with no invoice/subscription visibility. Big bet.
42. **Uniform 6-character password minimum for every staff account, every tenant, every role** — worth revisiting at multi-tenant scale.
43. **No frontend error monitoring** — every failure path bottoms out in `console.error`, with no way to know a resident-facing error is happening in the wild short of a complaint.

---

**Note on scope:** the flat staff-permission tier and lack of a property-manager-vs-concierge role split are documented, deliberate trade-offs already made by the team — not re-flagged as gaps here, but worth keeping in mind alongside #39/#40 as the natural next layer once a second or third real tenant is onboarded.
