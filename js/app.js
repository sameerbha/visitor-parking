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

const _sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

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

// ─── Visitor Registrations ──────────────────────────────────────────────────

async function getActiveVisitors(addressId) {
  const { data, error } = await _sb
    .from('visitor_registrations')
    .select('*')
    .eq('address_id', addressId)
    .gt('expires_at', new Date().toISOString())
    .order('registered_at', { ascending: false });
  if (error) { console.error('getActiveVisitors:', error); return []; }
  return data;
}

async function addVisitorRegistration(data) {
  const { data: row, error } = await _sb
    .from('visitor_registrations')
    .insert(data)
    .select()
    .single();
  if (error) throw error;
  return row;
}

async function deleteVisitorRegistration(id) {
  const { error } = await _sb.from('visitor_registrations').delete().eq('id', id);
  if (error) throw error;
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

async function requireAuth(redirectBack) {
  const user = await getCurrentUser();
  if (!user) {
    const from = redirectBack || window.location.pathname.split('/').pop();
    window.location.href = 'login.html?from=' + encodeURIComponent(from);
    return null;
  }
  return user;
}

// ─── Utilities ───────────────────────────────────────────────────────────────

function todayStr() { return new Date().toISOString().split('T')[0]; }

function isActive(exemption) {
  const t = todayStr();
  return exemption.start_date <= t && exemption.end_date >= t;
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
