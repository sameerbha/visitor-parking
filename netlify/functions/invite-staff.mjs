// Invite Staff by Email
//
// Called from Platform Admin's "Assign Staff" modal. This is the one piece
// of onboarding a new tenant's staff that genuinely can't happen from the
// browser alone — creating a Supabase Auth user requires the service_role
// key, which must never be shipped to the client. This function holds that
// key server-side and does two things in one step: creates (or finds) the
// Supabase Auth user for the given email, and links them to the tenant via
// staff_access — so nobody ever needs to open the Supabase dashboard to
// onboard a new tenant's staff.
//
// Requires two environment variables set in Netlify's dashboard for this
// site (Site configuration -> Environment variables) — NOT in any file in
// this repo:
//   SUPABASE_URL              (same value as js/supabase-config.js)
//   SUPABASE_SERVICE_ROLE_KEY (Supabase dashboard -> Project Settings ->
//                               API -> service_role secret key. This key
//                               bypasses every RLS policy — treat it like a
//                               master password. Never put it in a file
//                               that gets committed to git.)

import { createClient } from '@supabase/supabase-js';

export default async (req) => {
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  const SUPABASE_URL = process.env.SUPABASE_URL;
  const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
    return json({ error: 'Server is missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY. Set these in Netlify -> Site configuration -> Environment variables, then redeploy.' }, 500);
  }

  let body;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid request body.' }, 400);
  }

  const email = (body.email || '').trim().toLowerCase();
  const tenantId = body.tenantId;
  const tenantName = (body.tenantName || '').trim(); // building name, threaded into the invite email via user_metadata
  const origin = body.origin; // the browser's own origin, so the invite email links back to wherever the admin was working from
  if (!email || !tenantId) {
    return json({ error: 'email and tenantId are required.' }, 400);
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return json({ error: 'That doesn’t look like a valid email address.' }, 400);
  }

  const authHeader = req.headers.get('authorization') || '';
  const token = authHeader.replace(/^Bearer\s+/i, '');
  if (!token) {
    return json({ error: 'Missing authorization.' }, 401);
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // Verify the caller is a real, currently-logged-in user before doing
  // anything privileged. This uses the service-role client purely to
  // validate the JWT they sent — it does not by itself grant them anything.
  const { data: callerData, error: callerErr } = await admin.auth.getUser(token);
  if (callerErr || !callerData?.user) {
    return json({ error: 'Invalid or expired session — please refresh and try again.' }, 401);
  }
  const callerId = callerData.user.id;

  // Authorization: the caller must be either a platform admin, or already
  // have access to this specific tenant (so an existing tenant staff member
  // can invite a colleague onto their own tenant, not just a platform admin).
  const { data: adminRow } = await admin.from('platform_admins').select('user_id').eq('user_id', callerId).maybeSingle();
  let authorized = !!adminRow;
  if (!authorized) {
    const { data: accessRow } = await admin.from('staff_access').select('id').eq('user_id', callerId).eq('tenant_id', tenantId).maybeSingle();
    authorized = !!accessRow;
  }
  if (!authorized) {
    return json({ error: 'You do not have access to invite staff for this tenant.' }, 403);
  }

  const redirectTo = origin ? origin.replace(/\/$/, '') + '/accept-invite.html' : undefined;

  // data becomes auth.users.user_metadata, which the Supabase invite email
  // template can read as {{ .Data.tenant_name }} to greet the recipient with
  // the actual building name instead of a generic message.
  const inviteOptions = {};
  if (redirectTo) inviteOptions.redirectTo = redirectTo;
  if (tenantName) inviteOptions.data = { tenant_name: tenantName };

  const { data: invited, error: inviteErr } = await admin.auth.admin.inviteUserByEmail(
    email,
    Object.keys(inviteOptions).length ? inviteOptions : undefined
  );

  if (inviteErr) {
    // Most common non-error case: this person already has a Supabase login
    // (e.g. staff at another building under the same tenant, or being added
    // to a second tenant). Look them up and just link them instead of
    // failing outright.
    const alreadyExists = inviteErr.status === 422 || /already registered|already exists/i.test(inviteErr.message || '');
    if (!alreadyExists) {
      return json({ error: inviteErr.message || 'Could not send invite.' }, 400);
    }

    const existingUser = await findUserByEmail(admin, email);
    if (!existingUser) {
      return json({ error: inviteErr.message || 'Could not send invite.' }, 400);
    }

    const { error: linkErr } = await admin.from('staff_access').insert({ user_id: existingUser.id, tenant_id: tenantId });
    if (linkErr && !/duplicate/i.test(linkErr.message || '')) {
      return json({ error: linkErr.message }, 400);
    }
    return json({ ok: true, existingUser: true });
  }

  const { error: linkErr } = await admin.from('staff_access').insert({ user_id: invited.user.id, tenant_id: tenantId });
  if (linkErr) {
    return json({ error: linkErr.message }, 400);
  }

  return json({ ok: true, existingUser: false });
};

// supabase-js has no "get user by email" call on the admin API, only
// list-and-filter — fine at the scale a manually-onboarded multi-tenant
// product like this runs at.
async function findUserByEmail(admin, email) {
  let page = 1;
  for (;;) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 200 });
    if (error || !data?.users?.length) return null;
    const match = data.users.find(u => (u.email || '').toLowerCase() === email);
    if (match) return match;
    if (data.users.length < 200) return null;
    page += 1;
  }
}

function json(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export const config = { path: '/api/invite-staff' };
