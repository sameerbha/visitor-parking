/**
 * Visitors Parking Management — Shared Data Layer
 * Uses localStorage in demo mode.
 * Replace these functions with Supabase/API calls when ready to deploy.
 */

// ─── Demo Seed Data ────────────────────────────────────────────────────────

const DEMO_ADDRESSES = [
  { id: '1', name: '225 Sumach Street', lot_code: '10001', full_name: '225 Sumach Street (10001)' },
];

const DEMO_EXEMPTIONS = [
  { id:'e1', address_id:'1', plate:'016NLA',   notes:'GUEST 809W',                 start_date:'2022-10-01', end_date:'2022-10-02', entered_by:'BuildingStaff', entry_date:'2023-02-09' },
  { id:'e2', address_id:'1', plate:'085AXPY',  notes:'Kone Elevator',              start_date:'2022-07-19', end_date:'2022-07-20', entered_by:'BuildingStaff', entry_date:'2022-07-19' },
  { id:'e3', address_id:'1', plate:'09KEWAL',  notes:'2507 visitor',               start_date:'2023-08-01', end_date:'2023-08-02', entered_by:'BuildingStaff', entry_date:'2023-08-01' },
  { id:'e4', address_id:'1', plate:'223NHF',   notes:'Realtor',                    start_date:'2025-01-09', end_date:'2025-01-10', entered_by:'BuildingStaff', entry_date:'2025-01-09' },
  { id:'e5', address_id:'1', plate:'3315ZY',   notes:'Resident Guest',             start_date:'2023-06-02', end_date:'2023-06-03', entered_by:'BuildingStaff', entry_date:'2023-06-02' },
  { id:'e6', address_id:'1', plate:'59CF18',   notes:'visitor 911E',               start_date:'2023-06-03', end_date:'2023-06-04', entered_by:'BuildingStaff', entry_date:'2023-06-03' },
  { id:'e7', address_id:'1', plate:'792FRV',   notes:'Daniels Contractor',         start_date:'2022-10-21', end_date:'2022-10-22', entered_by:'BuildingStaff', entry_date:'2022-10-21' },
  { id:'e8', address_id:'1', plate:'EXEMPT01', notes:'Active Contractor - AC Repair', start_date:'2026-03-01', end_date:'2026-03-31', entered_by:'BuildingStaff', entry_date:'2026-03-01' },
];

function makeDemoVisitors() {
  const now = Date.now();
  return [
    { id:'v1', address_id:'1', lot_code:'10001', tenant_phone:'4161234567', unit_number:'W403', visitor_plate:'ABCD123',  registered_at: new Date(now - 2*3600000).toISOString(), expires_at: new Date(now + 22*3600000).toISOString() },
    { id:'v2', address_id:'1', lot_code:'10001', tenant_phone:'4169876543', unit_number:'1204', visitor_plate:'XYZ789',   registered_at: new Date(now - 5*3600000).toISOString(), expires_at: new Date(now + 19*3600000).toISOString() },
    { id:'v3', address_id:'1', lot_code:'10001', tenant_phone:'4165559999', unit_number:'802',  visitor_plate:'MNOP456',  registered_at: new Date(now - 26*3600000).toISOString(), expires_at: new Date(now - 2*3600000).toISOString() },
  ];
}

// Passwords are stored as SHA-256 hashes — plaintext never lives in code or localStorage.
// Hash shown here is pre-computed; the browser re-hashes on every login attempt.
const DEMO_USERS = [
  { id:'u1', email:'staff@condo.com',     passwordHash:'d3ad9315b7be5dd53b31a273b3b3aba5defe700808305aa16a3062b76658a791', role:'staff', name:'Building Staff' },
  { id:'u2', email:'admin@condo.com',     passwordHash:'240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', role:'admin', name:'Admin'          },
  { id:'u3', email:'concierge@condo.com', passwordHash:'d3ad9315b7be5dd53b31a273b3b3aba5defe700808305aa16a3062b76658a791', role:'staff', name:'Concierge'      },
];

// Unit codes — one code per unit, used by residents to authenticate on the registration form
const DEMO_UNIT_CODES = [
  { id:'uc1', address_id:'1', unit_number:'W403', code:'MAPLE1', created_by:'BuildingStaff', created_date:'2026-01-01', last_reset:'2026-01-01' },
  { id:'uc2', address_id:'1', unit_number:'1204', code:'PARK22', created_by:'BuildingStaff', created_date:'2026-01-01', last_reset:'2026-01-01' },
  { id:'uc3', address_id:'1', unit_number:'802',  code:'GUEST3', created_by:'BuildingStaff', created_date:'2026-01-01', last_reset:'2026-01-01' },
];

// ─── Storage helpers ───────────────────────────────────────────────────────

function initDemoData() {
  if (!localStorage.getItem('vp_initialized')) {
    // First-ever load: seed everything
    localStorage.setItem('vp_addresses',   JSON.stringify(DEMO_ADDRESSES));
    localStorage.setItem('vp_exemptions',  JSON.stringify(DEMO_EXEMPTIONS));
    localStorage.setItem('vp_visitors',    JSON.stringify(makeDemoVisitors()));
    localStorage.setItem('vp_unit_codes',  JSON.stringify(DEMO_UNIT_CODES));
    localStorage.setItem('vp_users',       JSON.stringify(DEMO_USERS));
    localStorage.setItem('vp_initialized', 'true');
  } else {
    // Migration: always overwrite addresses with the current single-building list
    localStorage.setItem('vp_addresses', JSON.stringify(DEMO_ADDRESSES));

    // Migration: seed vp_unit_codes if missing (v1.1.1)
    if (!localStorage.getItem('vp_unit_codes')) {
      localStorage.setItem('vp_unit_codes', JSON.stringify(DEMO_UNIT_CODES));
    }

    // Migration: seed vp_users if missing, or if they still have plaintext passwords (v1.2.0)
    const storedUsers = JSON.parse(localStorage.getItem('vp_users') || '[]');
    const hasPlaintext = storedUsers.some(u => u.password !== undefined);
    if (!localStorage.getItem('vp_users') || hasPlaintext) {
      localStorage.setItem('vp_users', JSON.stringify(DEMO_USERS));
    }
  }
}

function store(key)       { initDemoData(); return JSON.parse(localStorage.getItem(key) || '[]'); }
function save(key, value) { localStorage.setItem(key, JSON.stringify(value)); }

// ─── Addresses ─────────────────────────────────────────────────────────────

function getAddresses()        { return store('vp_addresses'); }
function getAddressById(id)    { return getAddresses().find(a => a.id === id) || null; }
function getAddressByLotCode(c){ return getAddresses().find(a => a.lot_code === c) || null; }

function addAddress(data) {
  const list = getAddresses();
  const entry = { id:'a'+Date.now(), ...data };
  list.push(entry); save('vp_addresses', list); return entry;
}
function deleteAddress(id) { save('vp_addresses', getAddresses().filter(a => a.id !== id)); }

// ─── Visitor Registrations ─────────────────────────────────────────────────

function getActiveVisitors(addressId) {
  const now = new Date();
  return store('vp_visitors')
    .filter(v => v.address_id === addressId && new Date(v.expires_at) > now)
    .sort((a,b) => new Date(b.registered_at) - new Date(a.registered_at));
}

function addVisitorRegistration(data) {
  const all   = store('vp_visitors');
  const entry = { id:'v'+Date.now(), ...data, registered_at: new Date().toISOString(), expires_at: new Date(Date.now()+24*3600000).toISOString() };
  all.push(entry); save('vp_visitors', all); return entry;
}

function deleteVisitorRegistration(id) { save('vp_visitors', store('vp_visitors').filter(v => v.id !== id)); }

// ─── Exemptions ────────────────────────────────────────────────────────────

function getExemptions(addressId) {
  return store('vp_exemptions')
    .filter(e => e.address_id === addressId)
    .sort((a,b) => b.entry_date.localeCompare(a.entry_date));
}

function addExemption(data) {
  const all   = store('vp_exemptions');
  const entry = { id:'e'+Date.now(), entry_date: todayStr(), ...data };
  all.push(entry); save('vp_exemptions', all); return entry;
}

function updateExemption(id, data) {
  const all = store('vp_exemptions');
  const idx = all.findIndex(e => e.id === id);
  if (idx !== -1) { all[idx] = { ...all[idx], ...data }; save('vp_exemptions', all); return all[idx]; }
  return null;
}

function deleteExemption(id) { save('vp_exemptions', store('vp_exemptions').filter(e => e.id !== id)); }

// ─── Unit Codes ────────────────────────────────────────────────────────────

function getUnitCodes(addressId) {
  return store('vp_unit_codes')
    .filter(u => u.address_id === addressId)
    .sort((a, b) => a.unit_number.localeCompare(b.unit_number));
}

function getUnitCode(unitNumber, addressId) {
  const norm = unitNumber.trim().toUpperCase();
  return store('vp_unit_codes')
    .find(u => u.address_id === addressId && u.unit_number.toUpperCase() === norm) || null;
}

function addUnitCode(data) {
  const all   = store('vp_unit_codes');
  const entry = { id:'uc'+Date.now(), created_date: todayStr(), last_reset: todayStr(), ...data };
  all.push(entry); save('vp_unit_codes', all); return entry;
}

function updateUnitCode(id, data) {
  const all = store('vp_unit_codes');
  const idx = all.findIndex(u => u.id === id);
  if (idx !== -1) { all[idx] = { ...all[idx], ...data, last_reset: todayStr() }; save('vp_unit_codes', all); return all[idx]; }
  return null;
}

function deleteUnitCode(id) { save('vp_unit_codes', store('vp_unit_codes').filter(u => u.id !== id)); }

/**
 * Validates a unit code entered on the registration form.
 * Returns { valid: true } or { valid: false, error: '...' }
 */
function validateUnitCode(unitNumber, enteredCode, addressId) {
  const record = getUnitCode(unitNumber, addressId);
  if (!record) return { valid: false, error: 'Unit number not found or not set up for this building.' };
  if (record.code.trim().toUpperCase() !== enteredCode.trim().toUpperCase()) {
    return { valid: false, error: 'Incorrect unit code. Please try again.' };
  }
  return { valid: true };
}

// ─── Monthly Pass Validation ────────────────────────────────────────────────
// Rules:
//   1. A unit may register a maximum of 10 visitor passes per calendar month.
//   2. Any single licence plate may be registered on no more than 7 distinct
//      calendar days per month (per unit).
//   3. Once either limit is reached, no further passes may be issued.

/**
 * Returns monthly statistics for a given unit.
 * { totalPasses, plateDays, remainingPasses, maxPassesReached }
 *   plateDays: { 'PLATE': <number of distinct days registered this month> }
 */
function getMonthlyPassStats(unitNumber, addressId) {
  const now        = new Date();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();
  const monthEnd   = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59).toISOString();
  const normUnit   = unitNumber.trim().toUpperCase();

  const monthly = store('vp_visitors').filter(v =>
    v.address_id === addressId &&
    v.unit_number.toUpperCase() === normUnit &&
    v.registered_at >= monthStart &&
    v.registered_at <= monthEnd
  );

  // Count distinct calendar days each plate was registered this month
  const plateDaySets = {};
  monthly.forEach(v => {
    const plate = v.visitor_plate.replace(/\s/g, '').toUpperCase();
    const day   = v.registered_at.split('T')[0];
    if (!plateDaySets[plate]) plateDaySets[plate] = new Set();
    plateDaySets[plate].add(day);
  });

  const plateDays = {};
  Object.entries(plateDaySets).forEach(([plate, days]) => { plateDays[plate] = days.size; });

  return {
    totalPasses:     monthly.length,
    plateDays,
    remainingPasses: Math.max(0, 10 - monthly.length),
    maxPassesReached: monthly.length >= 10,
  };
}

/**
 * Checks whether a new registration is allowed for the given unit + plate.
 * Returns { allowed: true } or { allowed: false, reason: '...' }
 */
function canRegisterVisitor(unitNumber, plate, addressId) {
  const stats      = getMonthlyPassStats(unitNumber, addressId);
  const normPlate  = plate.replace(/\s/g, '').toUpperCase();

  if (stats.maxPassesReached) {
    return {
      allowed: false,
      reason: 'Your unit has used all 10 visitor parking passes for this month. Passes reset on the 1st of next month.'
    };
  }

  const daysUsed = stats.plateDays[normPlate] || 0;
  if (daysUsed >= 7) {
    return {
      allowed: false,
      reason: `Plate ${plate} has already been registered for 7 days this month. This plate cannot be registered again until next month.`
    };
  }

  return { allowed: true };
}

// ─── Plate Validation ──────────────────────────────────────────────────────

function checkPlate(plate, addressId) {
  const norm  = plate.replace(/\s/g,'').toUpperCase();
  const today = todayStr();

  const visitor = getActiveVisitors(addressId)
    .find(v => v.visitor_plate.replace(/\s/g,'').toUpperCase() === norm);
  if (visitor) return { valid:true, reason:'Registered Visitor', detail:'Unit ' + visitor.unit_number };

  const exempt = getExemptions(addressId)
    .find(e => e.plate.replace(/\s/g,'').toUpperCase() === norm && e.start_date <= today && e.end_date >= today);
  if (exempt) return { valid:true, reason:'Exempted Vehicle', detail:exempt.notes };

  return { valid:false, reason:'Not registered — vehicle is not authorized' };
}

// ─── Auth ──────────────────────────────────────────────────────────────────

/**
 * Hash a plaintext password with SHA-256 using the browser's Web Crypto API.
 * Returns a hex string. Never stores or transmits plaintext.
 */
async function hashPassword(plaintext) {
  const buf  = new TextEncoder().encode(plaintext);
  const hash = await crypto.subtle.digest('SHA-256', buf);
  return Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2,'0')).join('');
}

/**
 * Authenticate a user. Returns { success, user } or { success:false, error }.
 * Async because password hashing is async.
 */
async function loginUser(email, password) {
  initDemoData();
  const users = JSON.parse(localStorage.getItem('vp_users') || '[]');
  const user  = users.find(u => u.email.toLowerCase() === email.trim().toLowerCase());
  if (!user) return { success:false, error:'Invalid email or password' };
  const hash = await hashPassword(password);
  if (hash !== user.passwordHash) return { success:false, error:'Invalid email or password' };
  const session = { id:user.id, email:user.email, role:user.role, name:user.name };
  localStorage.setItem('vp_session', JSON.stringify(session));
  return { success:true, user:session };
}

/**
 * Change a user's password. Verifies current password before updating.
 * Returns { success } or { success:false, error }.
 */
async function changePassword(userId, currentPassword, newPassword) {
  const users = JSON.parse(localStorage.getItem('vp_users') || '[]');
  const idx   = users.findIndex(u => u.id === userId);
  if (idx === -1) return { success:false, error:'User not found.' };
  const currentHash = await hashPassword(currentPassword);
  if (currentHash !== users[idx].passwordHash) return { success:false, error:'Current password is incorrect.' };
  if (newPassword.length < 6) return { success:false, error:'New password must be at least 6 characters.' };
  users[idx].passwordHash = await hashPassword(newPassword);
  localStorage.setItem('vp_users', JSON.stringify(users));
  return { success:true };
}

function logoutUser() { localStorage.removeItem('vp_session'); }

function getCurrentUser() {
  const s = localStorage.getItem('vp_session');
  return s ? JSON.parse(s) : null;
}

// Redirect to login if not authenticated
function requireAuth(redirectBack) {
  const user = getCurrentUser();
  if (!user) {
    const from = redirectBack || window.location.pathname.split('/').pop();
    window.location.href = 'login.html?from=' + encodeURIComponent(from);
    return null;
  }
  return user;
}

// ─── Utilities ─────────────────────────────────────────────────────────────

function todayStr() { return new Date().toISOString().split('T')[0]; }

function isActive(exemption) {
  const t = todayStr();
  return exemption.start_date <= t && exemption.end_date >= t;
}

function formatDateTime(iso) {
  return new Date(iso).toLocaleString('en-CA', {
    year:'numeric', month:'short', day:'numeric',
    hour:'2-digit', minute:'2-digit', hour12:true
  });
}

function timeRemaining(expiresAt) {
  const diff = new Date(expiresAt) - new Date();
  if (diff <= 0) return 'Expired';
  const hrs  = Math.floor(diff / 3600000);
  const mins = Math.floor((diff % 3600000) / 60000);
  if (hrs > 0) return hrs + 'h ' + mins + 'm remaining';
  return mins + 'm remaining';
}

function plateBadge(plate) {
  return `<span class="plate-badge">${escapeHtml(plate)}</span>`;
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
    .replace(/"/g,'&quot;').replace(/'/g,'&#039;');
}

function generateCaptcha() {
  const a = Math.floor(Math.random() * 9) + 1;
  const b = Math.floor(Math.random() * 9) + 1;
  return { question:`${a} + ${b}`, answer:String(a + b) };
}

function exportCSV(rows, filename) {
  const csv  = rows.map(r => r.map(c => `"${String(c).replace(/"/g,'""')}"`).join(',')).join('\n');
  const blob = new Blob([csv], { type:'text/csv' });
  const url  = URL.createObjectURL(blob);
  const a    = document.createElement('a');
  a.href = url; a.download = filename; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function showAlert(msg, type='success') {
  const el = document.getElementById('flash-msg');
  if (!el) return;
  el.className = `alert alert-${type} flash-msg`;
  el.textContent = msg;
  el.style.display = 'block';
  setTimeout(() => { el.style.display = 'none'; }, 3500);
}

// Populate address dropdown
function populateAddressSelect(selectEl, onLoad) {
  const addrs = getAddresses();
  selectEl.innerHTML = addrs.map(a => `<option value="${a.id}">${escapeHtml(a.full_name)}</option>`).join('');
  if (addrs.length > 0 && onLoad) onLoad(addrs[0].id, addrs[0]);
}

// Render staff user badge in header
function renderUserBadge(user) {
  const badge = document.getElementById('user-badge');
  const logoutBtn = document.getElementById('logout-btn');
  if (badge) badge.textContent = user.name;
  if (logoutBtn) logoutBtn.addEventListener('click', () => { logoutUser(); window.location.href='login.html'; });
}
