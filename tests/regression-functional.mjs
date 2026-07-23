#!/usr/bin/env node
// Functional regression test for the Visitors Parking App's Supabase layer.
//
// Exercises the exact RPCs/tables js/app.js calls, in the same order the
// registration form uses them: validate_unit_code, can_register_visitor,
// insert into visitor_registrations, get_monthly_pass_stats,
// check_plate_active, extend_visitor_registration.
//
// Uses plain fetch (no npm install needed — Node 18+ has fetch built in)
// against your REAL Supabase project, reading the URL/anon key straight out
// of js/supabase-config.js.
//
// This WILL create one real visitor_registrations row (and one extension of
// it) using the test plate you provide. Use a plate you can recognize and
// don't mind seeing in the enforcement portal for the next 24 hours — it
// expires on its own like any other registration.
//
// Usage:
//   node tests/regression-functional.mjs <lotCode> <unitNumber> <unitCode> [testPlate]
//
// Example:
//   node tests/regression-functional.mjs 10001 W403 JVJJLG QATEST01

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const configPath = join(__dirname, '..', 'js', 'supabase-config.js');

const [, , lotCode, unitNumber, unitCode, testPlateArg] = process.argv;

if (!lotCode || !unitNumber || !unitCode) {
  console.error('Usage: node tests/regression-functional.mjs <lotCode> <unitNumber> <unitCode> [testPlate]');
  process.exit(1);
}

const testPlate = (testPlateArg || 'QATEST01').toUpperCase();

const configSrc = readFileSync(configPath, 'utf8');
const urlMatch = configSrc.match(/SUPABASE_URL\s*=\s*['"]([^'"]+)['"]/);
const keyMatch = configSrc.match(/SUPABASE_ANON_KEY\s*=\s*['"]([^'"]+)['"]/);

if (!urlMatch || !keyMatch) {
  console.error('Could not find SUPABASE_URL / SUPABASE_ANON_KEY in js/supabase-config.js');
  process.exit(1);
}

const SUPABASE_URL = urlMatch[1];
const ANON_KEY = keyMatch[1];

const headers = {
  apikey: ANON_KEY,
  Authorization: `Bearer ${ANON_KEY}`,
  'Content-Type': 'application/json',
};

let pass = 0;
let fail = 0;

function report(label, ok, detail) {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${label}${detail ? ' — ' + detail : ''}`);
  ok ? pass++ : fail++;
  return ok;
}

async function rpc(name, body) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => null);
  return { ok: res.ok, status: res.status, data };
}

function finish() {
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exitCode = fail === 0 ? 0 : 1;
}

async function main() {
  console.log(`Testing against unit ${unitNumber}, lot ${lotCode}, plate ${testPlate}\n`);

  // 1. Find the address for this lot code (mirrors getAddressByLotCode)
  const addrRes = await fetch(
    `${SUPABASE_URL}/rest/v1/addresses?lot_code=eq.${encodeURIComponent(lotCode)}&select=id,name`,
    { headers }
  );
  const addresses = await addrRes.json();
  const address = Array.isArray(addresses) ? addresses[0] : null;
  if (!report('Address found for lot code', !!address, address?.name)) return finish();
  const addressId = address.id;

  // 2. validate_unit_code — mirrors what the form does on submit
  const validate = await rpc('validate_unit_code', {
    p_unit_number: unitNumber,
    p_address_id: addressId,
    p_code: unitCode,
  });
  if (!report('validate_unit_code accepts the unit code', validate.ok && validate.data === true)) return finish();

  // 3. can_register_visitor — monthly/day limit check
  const canReg = await rpc('can_register_visitor', {
    p_unit_number: unitNumber,
    p_address_id: addressId,
    p_plate: testPlate,
  });
  report('can_register_visitor responds', canReg.ok, JSON.stringify(canReg.data));

  // 4. Insert the registration (mirrors addVisitorRegistration)
  const insertRes = await fetch(`${SUPABASE_URL}/rest/v1/visitor_registrations`, {
    method: 'POST',
    headers: { ...headers, Prefer: 'return=representation' },
    body: JSON.stringify({
      address_id: addressId,
      lot_code: lotCode,
      tenant_phone: '555-0100',
      unit_number: unitNumber,
      visitor_plate: testPlate,
    }),
  });
  const inserted = await insertRes.json().catch(() => null);
  const registrationOk = report(
    'Registration inserted',
    insertRes.ok && Array.isArray(inserted) && !!inserted[0]?.id,
    insertRes.ok ? `expires ${inserted?.[0]?.expires_at}` : JSON.stringify(inserted)
  );
  if (!registrationOk) return finish();

  // 5. get_monthly_pass_stats reflects the new registration
  const stats = await rpc('get_monthly_pass_stats', {
    p_unit_number: unitNumber,
    p_address_id: addressId,
  });
  report(
    'get_monthly_pass_stats reflects the new registration',
    stats.ok && stats.data?.totalPasses >= 1,
    JSON.stringify(stats.data)
  );

  // 6. check_plate_active — resubmitting the same plate should show it active
  const active = await rpc('check_plate_active', {
    p_plate: testPlate,
    p_address_id: addressId,
  });
  if (!report(
    'check_plate_active detects the plate as active',
    active.ok && active.data?.active === true,
    JSON.stringify(active.data)
  )) return finish();

  // 7. extend_visitor_registration — the "extend by 24 hours" flow
  const extend = await rpc('extend_visitor_registration', {
    p_plate: testPlate,
    p_address_id: addressId,
    p_unit_number: unitNumber,
    p_code: unitCode,
  });
  report(
    'extend_visitor_registration extends the expiry',
    extend.ok && extend.data?.extended === true,
    JSON.stringify(extend.data)
  );

  finish();
  console.log(`\nNote: this created a real visitor_registrations row for plate ${testPlate} / unit ${unitNumber}.`);
  console.log('It expires on its own in ~24 hours, or delete it now via the Admin/Enforcement portal.');
}

main().catch((err) => {
  console.error('Unexpected error:', err);
  process.exit(1);
});
