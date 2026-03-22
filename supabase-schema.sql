-- ═══════════════════════════════════════════════════════
-- Visitors Parking Management — Supabase Schema
-- Run this in your Supabase SQL editor to set up the DB.
-- ═══════════════════════════════════════════════════════

-- Addresses / Buildings
CREATE TABLE addresses (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  lot_code    TEXT UNIQUE NOT NULL,
  full_name   TEXT GENERATED ALWAYS AS (name || ' (' || lot_code || ')') STORED,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Seed addresses
INSERT INTO addresses (name, lot_code) VALUES
  ('225 Sumach Street', '19864'),
  ('100 Queens Quay East', '20105'),
  ('55 Front Street West', '31202');

-- Visitor Registrations (24-hour)
CREATE TABLE visitor_registrations (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  address_id    UUID REFERENCES addresses(id) ON DELETE CASCADE,
  lot_code      TEXT NOT NULL,
  tenant_phone  TEXT NOT NULL,
  unit_number   TEXT NOT NULL,
  visitor_plate TEXT NOT NULL,
  registered_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at    TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours')
);

-- Index for fast lookups
CREATE INDEX idx_visitor_plate   ON visitor_registrations(visitor_plate);
CREATE INDEX idx_visitor_address ON visitor_registrations(address_id, expires_at);

-- Exemptions
CREATE TABLE exemptions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  address_id  UUID REFERENCES addresses(id) ON DELETE CASCADE,
  plate       TEXT NOT NULL,
  notes       TEXT,
  start_date  DATE NOT NULL,
  end_date    DATE NOT NULL,
  entered_by  TEXT NOT NULL,
  entry_date  DATE DEFAULT CURRENT_DATE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast plate lookups
CREATE INDEX idx_exemption_plate   ON exemptions(plate);
CREATE INDEX idx_exemption_address ON exemptions(address_id, start_date, end_date);

-- ── Row Level Security (RLS) ─────────────────────────────
-- Enable RLS on all tables
ALTER TABLE addresses              ENABLE ROW LEVEL SECURITY;
ALTER TABLE visitor_registrations  ENABLE ROW LEVEL SECURITY;
ALTER TABLE exemptions             ENABLE ROW LEVEL SECURITY;

-- Allow public read/write on visitor_registrations (residents register guests)
CREATE POLICY "Public can register visitors"
  ON visitor_registrations FOR INSERT
  TO anon WITH CHECK (true);

-- Allow authenticated staff to read visitor_registrations
CREATE POLICY "Staff can view registrations"
  ON visitor_registrations FOR SELECT
  TO authenticated USING (true);

-- Allow authenticated staff to delete registrations
CREATE POLICY "Staff can remove registrations"
  ON visitor_registrations FOR DELETE
  TO authenticated USING (true);

-- Only authenticated staff can manage exemptions
CREATE POLICY "Staff can view exemptions"    ON exemptions FOR SELECT TO authenticated USING (true);
CREATE POLICY "Staff can add exemptions"     ON exemptions FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Staff can update exemptions"  ON exemptions FOR UPDATE TO authenticated USING (true);
CREATE POLICY "Staff can delete exemptions"  ON exemptions FOR DELETE TO authenticated USING (true);

-- Addresses are readable by all
CREATE POLICY "Addresses are public"
  ON addresses FOR SELECT
  TO anon, authenticated USING (true);

-- ── Optional: Auto-cleanup of expired registrations ────────────────────────
-- You can schedule this with pg_cron (Supabase Cron):
-- SELECT cron.schedule('cleanup-expired', '0 * * * *',
--   'DELETE FROM visitor_registrations WHERE expires_at < NOW()');
