/**
 * Visitors Parking Management — Data Layer (Supabase)
 *
 * All data functions are async and talk to Supabase.
 * Auth uses Supabase Auth (users are managed in the Supabase dashboard).
 * Utility/helper functions at the bottom remain synchronous.
 *
 * Requires (loaded before this file in every HTML page):
 *   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
 *   <script src="js/supabase-config.js"></script>
 */

// ─── Supabase client ────────────────────────────────────────────────────────

if (typeof supabase === 'undefined' || typeof SUPABASE_URL === 'undefined') {
  console.error('[app.js] Supabase CDN or supabase-config.js not loaded. Check script order in your HTML.');
}

// Pages that only ever need to act as an anonymous visitor (index.html) can
// set `window.SB_ANON_ONLY = true` before this script loads. That client
// never reads or writes the persisted auth session, so it can't accidentally
// inherit a staff login that happens to be sitting in the same browser's
// localStorage (which is shared across every page on the same origin) and
// send requests as `authenticated` instead of `anon`. Staff pages omit the
// flag and keep the normal persisted session so login carries across pages.
const _sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, window.SB_ANON_ONLY
  ? { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } }
  : {});

// ─── Addresses ──────────────────────────────────────────────────────────────

async function getAddresses() {
  const { data, error } = await _sb.from('addresses').select('*').order('name');
  if (error) { console.error('getAddresses:', error); return []; }
  return data;
}

async function getAddressById(id) {
  const { data, error } = await _sb.from('addresses').select('*').eq('id', id).single();
  if (error) return null;
  return data;
}

async function getAddressByLotCode(lotCode) {
  const { data, error } = await _sb.from('addresses').select('*').eq('lot_code', lotCode).single();
  if (error) return null;
  return data;
}

// Resident-facing tenant resolution: given a subdomain (e.g. 'dueast'),
// return that tenant's addresses. Anon-readable — used before anyone logs
// in, to figure out which building(s) a hostname belongs to.
async function getTenantBySubdomain(subdomain) {
  const { data, error } = await _sb.from('tenants').select('*').eq('subdomain', subdomain).single();
  if (error) return null;
  return data;
}

async function getAddressesByTenantId(tenantId) {
  const { data, error } = await _sb.from('addresses').select('*').eq('tenant_id', tenantId).order('name');
  if (error) { console.error('getAddressesByTenantId:', error); return []; }
  return data;
}

// ─── Visitor Registrations ──────────────────────────────────────────────────

async function getActiveVisitors(addressId) {
  const { data, error } = await _sb
    .from('visitor_registrations')
    .select('*')
    .eq('address_id', addressId)
    .gt('expires_at', new Date().toISOString())
    .order('registered_at', { ascending: false });
  // Throw rather than swallow: callers on flaky connections (e.g. an
  // underground garage) need to tell "fetch failed" apart from
  // "genuinely zero active visitors" so they can keep showing the last
  // known list instead of blanking out.
  if (error) { console.error('getActiveVisitors:', error); throw error; }
  return data;
}

async function addVisitorRegistration(data) {
  // Deliberately no .select() here. Chaining .select() asks PostgREST to
  // hand back the inserted row, which also requires that row to pass a
  // SELECT policy — but anon has no SELECT policy on this table (only
  // authenticated staff do, scoped to their tenant). Requesting the row
  // back would make an otherwise-valid anon insert fail with the exact
  // same "violates row-level security policy" error as a genuinely bad
  // insert, which is what was happening here. Nothing calling this
  // function actually uses the returned row, so there's no reason to ask
  // for it back.
  const { error } = await _sb
    .from('visitor_registrations')
    .insert(data);
  if (error) throw error;
}

async function deleteVisitorRegistration(id) {
  const { error } = await _sb.from('visitor_registrations').delete().eq('id', id);
  if (error) throw error;
}

// ─── Registration History (Admin) ───────────────────────────────────────────
// Unlike getActiveVisitors(), these are not filtered by expiry — they return
// the full history for a plate or unit, active and expired alike, so staff
// can answer "how has this plate/unit used its permits over time." Backed
// by the same RLS policy that already grants authenticated staff full read
// access to visitor_registrations; no schema change needed for this to work.

async function getPlateHistory(plate, addressId) {
  const norm = plate.replace(/\s/g, '').toUpperCase();
  const { data, error } = await _sb
    .from('visitor_registrations')
    .select('*')
    .eq('address_id', addressId)
    .ilike('visitor_plate', norm)
    .order('registered_at', { ascending: false });
  if (error) { console.error('getPlateHistory:', error); return []; }
  return data;
}

async function getUnitHistory(unitNumber, addressId) {
  const { data, error } = await _sb
    .from('visitor_registrations')
    .select('*')
    .eq('address_id', addressId)
    .ilike('unit_number', unitNumber.trim())
    .order('registered_at', { ascending: false });
  if (error) { console.error('getUnitHistory:', error); return []; }
  return data;
}

// ─── Exemptions ─────────────────────────────────────────────────────────────

async function getExemptions(addressId) {
  const { data, error } = await _sb
    .from('exemptions')
    .select('*')
    .eq('address_id', addressId)
    .order('entry_date', { ascending: false });
  if (error) { console.error('getExemptions:', error); return []; }
  return data;
}

async function addExemption(data) {
  const { data: row, error } = await _sb.from('exemptions').insert(data).select().single();
  if (error) throw error;
  return row;
}

async function updateExemption(id, data) {
  const { data: row, error } = await _sb.from('exemptions').update(data).eq('id', id).select().single();
  if (error) throw error;
  return row;
}

async function deleteExemption(id) {
  const { error } = await _sb.from('exemptions').delete().eq('id', id);
  if (error) throw error;
}

// ─── Unit Codes ─────────────────────────────────────────────────────────────

async function getUnitCodes(addressId) {
  const { data, error } = await _sb
    .from('unit_codes')
    .select('*')
    .eq('address_id', addressId)
    .order('unit_number');
  if (error) { console.error('getUnitCodes:', error); return []; }
  return data;
}

async function getUnitCode(unitNumber, addressId) {
  const { data, error } = await _sb
    .from('unit_codes')
    .select('*')
    .eq('address_id', addressId)
    .ilike('unit_number', unitNumber)
    .single();
  if (error) return null;
  return data;
}

async function addUnitCode(data) {
  const { data: row, error } = await _sb.from('unit_codes').insert(data).select().single();
  if (error) throw error;
  return row;
}

async function updateUnitCode(id, data) {
  const payload = { ...data, last_reset: todayStr() };
  const { data: row, error } = await _sb.from('unit_codes').update(payload).eq('id', id).select().single();
  if (error) throw error;
  return row;
}

async function deleteUnitCode(id) {
  const { error } = await _sb.from('unit_codes').delete().eq('id', id);
  if (error) throw error;
}

// Bulk-generate: inserts new unit codes and overwrites existing ones in a
// single round trip. `rows` is [{ address_id, unit_number, code }, ...] —
// the caller (Admin's Bulk Generate modal) decides per-row whether an
// already-coded unit should be included here at all.
async function bulkUpsertUnitCodes(rows) {
  const { data, error } = await _sb
    .from('unit_codes')
    .upsert(rows, { onConflict: 'address_id,unit_number' })
    .select();
  if (error) throw error;
  return data;
}

// ─── Validation (RPC — runs server-side, never exposes raw codes) ───────────

/**
 * Validates the unit code entered by a resident.
 * Uses a SECURITY DEFINER RPC so the codes table is never readable by anon.
 */
async function validateUnitCode(unitNumber, enteredCode, addressId) {
  const { data, error } = await _sb.rpc('validate_unit_code', {
    p_unit_number: unitNumber,
    p_address_id:  addressId,
    p_code:        enteredCode,
  });
  if (error) return { valid: false, error: 'Could not verify unit code. Please try again.' };
  if (!data)  return { valid: false, error: 'Unit number not found or code is incorrect.' };
  return { valid: true };
}

async function getMonthlyPassStats(unitNumber, addressId) {
  const { data, error } = await _sb.rpc('get_monthly_pass_stats', {
    p_unit_number: unitNumber,
    p_address_id:  addressId,
  });
  if (error) return { totalPasses: 0, plateDays: {}, remainingPasses: 10, maxPassesReached: false };
  return data;
}

async function canRegisterVisitor(unitNumber, plate, addressId) {
  const { data, error } = await _sb.rpc('can_register_visitor', {
    p_unit_number: unitNumber,
    p_address_id:  addressId,
    p_plate:       plate,
  });
  if (error) return { allowed: false, reason: 'Could not verify registration limits. Please try again.' };
  return data;
}

// ─── Extend registration (resident portal) ───────────────────────────────────

async function checkPlateActive(plate, addressId) {
  const { data, error } = await _sb.rpc('check_plate_active', {
    p_plate:       plate,
    p_address_id:  addressId,
  });
  if (error) return { active: false };
  return data;
}

async function extendVisitorRegistration(plate, addressId, unitNumber, code) {
  const { data, error } = await _sb.rpc('extend_visitor_registration', {
    p_plate:       plate,
    p_address_id:  addressId,
    p_unit_number: unitNumber,
    p_code:        code,
  });
  if (error) return { extended: false, error: error.message };
  return data;
}

// ─── Plate check (staff enforcement) ────────────────────────────────────────

async function checkPlate(plate, addressId) {
  const norm  = plate.replace(/\s/g, '').toUpperCase();
  const today = todayStr();

  const { data: visitors } = await _sb
    .from('visitor_registrations')
    .select('unit_number')
    .eq('address_id', addressId)
    .ilike('visitor_plate', norm)
    .gt('expires_at', new Date().toISOString())
    .limit(1);

  if (visitors && visitors.length > 0) {
    return { valid: true, reason: 'Registered Visitor', detail: 'Unit ' + visitors[0].unit_number };
  }

  const { data: exempts } = await _sb
    .from('exemptions')
    .select('notes')
    .eq('address_id', addressId)
    .ilike('plate', norm)
    .lte('start_date', today)
    .gte('end_date', today)
    .limit(1);

  if (exempts && exempts.length > 0) {
    return { valid: true, reason: 'Exempted Vehicle', detail: exempts[0].notes };
  }

  return { valid: false, reason: 'Not registered — vehicle is not authorized' };
}

// ─── Auth (Supabase Auth) ────────────────────────────────────────────────────

async function getCurrentUser() {
  const { data: { user } } = await _sb.auth.getUser();
  if (!user) return null;
  return {
    id:    user.id,
    email: user.email,
    name:  user.user_metadata?.name || user.email,
    role:  user.user_metadata?.role || 'staff',
  };
}

async function loginUser(email, password) {
  const { data, error } = await _sb.auth.signInWithPassword({ email, password });
  if (error) return { success: false, error: 'Invalid email or password.' };
  const u = data.user;
  return {
    success: true,
    user: {
      id:    u.id,
      email: u.email,
      name:  u.user_metadata?.name || u.email,
      role:  u.user_metadata?.role || 'staff',
    },
  };
}

async function logoutUser() {
  await _sb.auth.signOut();
}

async function changePassword(userId, currentPassword, newPassword) {
  // Re-authenticate to verify current password before allowing the change
  const { data: { user } } = await _sb.auth.getUser();
  if (!user) return { success: false, error: 'Not authenticated.' };

  const { error: verifyError } = await _sb.auth.signInWithPassword({
    email:    user.email,
    password: currentPassword,
  });
  if (verifyError) return { success: false, error: 'Current password is incorrect.' };

  if (newPassword.length < 6) return { success: false, error: 'New password must be at least 6 characters.' };

  const { error } = await _sb.auth.updateUser({ password: newPassword });
  if (error) return { success: false, error: error.message };
  return { success: true };
}

// For accept-invite.html only. A freshly-invited user arrives with a
// temporary session from the invite link's token, not a real password yet —
// there's nothing to verify against, unlike changePassword() above.
async function setInitialPassword(newPassword) {
  if (newPassword.length < 6) return { success: false, error: 'Password must be at least 6 characters.' };
  const { error } = await _sb.auth.updateUser({ password: newPassword });
  if (error) return { success: false, error: error.message };
  return { success: true };
}

async function requireAuth(redirectBack) {
  const user = await getCurrentUser();
  if (!user) {
    const from = redirectBack || window.location.pathname.split('/').pop();
    window.location.href = 'login.html?from=' + encodeURIComponent(from);
    return null;
  }
  return user;
}

// ─── Platform Admin (Regent Parking — cross-tenant management) ──────────────

async function isPlatformAdmin() {
  const { data, error } = await _sb.rpc('is_platform_admin');
  if (error) return false;
  return data === true;
}

async function getTenants() {
  const { data, error } = await _sb.from('tenants').select('*').order('name');
  if (error) { console.error('getTenants:', error); return []; }
  return data;
}

async function getTenantById(tenantId) {
  const { data, error } = await _sb.from('tenants').select('*').eq('id', tenantId).single();
  if (error) { console.error('getTenantById:', error); return null; }
  return data;
}

// Used by Admin's Settings tab (tenant-scoped, any staff member of the
// tenant can call this — RLS/the RPC itself enforces that).
async function updateTenantLimits(tenantId, monthlyPassLimit, plateDayLimit) {
  const { data, error } = await _sb.rpc('update_tenant_limits', {
    p_tenant_id: tenantId,
    p_monthly_pass_limit: monthlyPassLimit,
    p_plate_day_limit: plateDayLimit,
  });
  if (error) throw error;
  return data;
}

async function createTenant(data) {
  const { data: row, error } = await _sb.from('tenants').insert(data).select().single();
  if (error) throw error;
  return row;
}

async function createAddress(data) {
  const { data: row, error } = await _sb.from('addresses').insert(data).select().single();
  if (error) throw error;
  return row;
}

async function getTenantStaff(tenantId) {
  const { data, error } = await _sb.rpc('get_tenant_staff', { p_tenant_id: tenantId });
  if (error) { console.error('getTenantStaff:', error); return []; }
  return data;
}

// Manual fallback only — the Platform Admin UI now uses inviteStaffToTenant()
// below instead. Kept in case a raw Supabase user ID is ever the only thing
// on hand (e.g. from the Supabase dashboard directly) and the invite
// function isn't available for some reason.
async function assignStaffToTenant(userId, tenantId) {
  const { data, error } = await _sb.from('staff_access')
    .insert({ user_id: userId, tenant_id: tenantId }).select().single();
  if (error) throw error;
  return data;
}

// Invites a new staff login by email (or links an existing one) and grants
// them access to a tenant, in one step — no Supabase dashboard needed. Calls
// the invite-staff Netlify function, which holds the service_role key
// server-side; this client-side function just packages the request.
async function inviteStaffToTenant(email, tenantId) {
  const { data: sessionData } = await _sb.auth.getSession();
  const token = sessionData?.session?.access_token;
  if (!token) throw new Error('Your session has expired — please refresh and sign in again.');

  const res = await fetch('/api/invite-staff', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: 'Bearer ' + token,
    },
    body: JSON.stringify({ email, tenantId, origin: window.location.origin }),
  });

  let payload = null;
  try { payload = await res.json(); } catch { /* non-JSON error page, fall through */ }

  if (!res.ok) {
    throw new Error(payload?.error || 'Could not invite that email (server error ' + res.status + ').');
  }
  return payload;
}

async function removeStaffAccess(staffAccessId) {
  const { error } = await _sb.from('staff_access').delete().eq('id', staffAccessId);
  if (error) throw error;
  return true;
}

async function getTenantUsageStats(tenantId) {
  const { data, error } = await _sb.rpc('get_tenant_usage_stats', { p_tenant_id: tenantId });
  if (error) { console.error('getTenantUsageStats:', error); return null; }
  return data;
}

// Clears a trial/demo tenant's registrations and exemptions. Hard-gated
// server-side to status='trial' tenants — throws if called on anything
// else, regardless of who's calling it.
async function resetTenantDemoData(tenantId) {
  const { data, error } = await _sb.rpc('reset_tenant_demo_data', { p_tenant_id: tenantId });
  if (error) throw error;
  return data;
}

// ─── Utilities ───────────────────────────────────────────────────────────────

function todayStr() { return new Date().toISOString().split('T')[0]; }

function isActive(exemption) {
  const t = todayStr();
  return exemption.start_date <= t && exemption.end_date >= t;
}

// Three-state version for display purposes (Admin exemptions table).
// isActive() above stays a strict boolean — it's used at the gate
// (enforcement.html Patrol View) where "not active today" is all that
// matters. This distinguishes "hasn't started yet" from "already ended"
// so future-dated exemptions aren't mislabeled "Expired".
function getExemptionStatus(exemption) {
  const t = todayStr();
  if (exemption.start_date > t) return 'upcoming';
  if (exemption.end_date < t) return 'expired';
  return 'active';
}

function formatDateTime(iso) {
  return new Date(iso).toLocaleString('en-CA', {
    year: 'numeric', month: 'short', day: 'numeric',
    hour: '2-digit', minute: '2-digit', hour12: true,
  });
}

function timeRemaining(expiresAt) {
  const diff = new Date(expiresAt) - new Date();
  if (diff <= 0) return 'Expired';
  const hrs  = Math.floor(diff / 3600000);
  const mins = Math.floor((diff % 3600000) / 60000);
  return hrs > 0 ? hrs + 'h ' + mins + 'm remaining' : mins + 'm remaining';
}

function plateBadge(plate) {
  return '<span class="plate-badge">' + escapeHtml(plate) + '</span>';
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#039;');
}

function generateCaptcha() {
  const a = Math.floor(Math.random() * 9) + 1;
  const b = Math.floor(Math.random() * 9) + 1;
  return { question: a + ' + ' + b, answer: String(a + b) };
}

function exportCSV(rows, filename) {
  const csv  = rows.map(r => r.map(c => '"' + String(c).replace(/"/g, '""') + '"').join(',')).join('\n');
  const blob = new Blob([csv], { type: 'text/csv' });
  const url  = URL.createObjectURL(blob);
  const a    = document.createElement('a');
  a.href = url; a.download = filename; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function showAlert(msg, type = 'success') {
  const el = document.getElementById('flash-msg');
  if (!el) return;
  el.className   = 'alert alert-' + type + ' flash-msg';
  el.textContent = msg;
  el.style.display = 'block';
  setTimeout(() => { el.style.display = 'none'; }, 3500);
}

async function populateAddressSelect(selectEl) {
  const addrs = await getAddresses();
  selectEl.innerHTML = addrs.map(a =>
    '<option value="' + a.id + '">' + escapeHtml(a.full_name) + '</option>'
  ).join('');
  return addrs;
}
