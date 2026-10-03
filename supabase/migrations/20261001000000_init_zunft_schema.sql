-- ==============================================================================
-- Migration: 20261001000000_init_zunft_schema.sql
-- Project: Zunft (AI Back-Office for German Handwerk)
-- Target: Supabase Postgres (EU Frankfurt) with PostGIS & RLS
-- ==============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- ------------------------------------------------------------------------------
-- 1. BUSINESSES (Handwerksbetriebe)
-- ------------------------------------------------------------------------------
CREATE TABLE businesses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,                                -- e.g. "Elektro Meister Hamburg GmbH"
    trade_category TEXT NOT NULL DEFAULT 'elektro',     -- 'elektro', 'shk', 'maler', 'dachdecker', 'tischler'
    owner_name TEXT NOT NULL,
    tax_number TEXT,                                   -- Steuernummer (e.g. "48/123/45678")
    vat_id TEXT,                                       -- USt-IdNr (e.g. "DE123456789")
    iban TEXT,                                         -- IBAN für Rechnungen
    bic TEXT,                                          -- BIC
    bank_name TEXT,
    phone TEXT,
    email TEXT,
    website TEXT,
    address_street TEXT,
    address_zip TEXT,
    address_city TEXT,
    
    -- PostGIS geography point (WGS84 lon, lat) for Phase 3 radius search & overflow matching
    location GEOGRAPHY(Point, 4326),
    
    -- Defaults in integer cents
    default_hourly_rate_cents INT NOT NULL DEFAULT 6500, -- 65,00 €/Std
    default_vat_rate NUMERIC(4,2) NOT NULL DEFAULT 19.00,
    subscription_status TEXT NOT NULL DEFAULT 'trialing', -- 'trialing', 'active', 'past_due', 'canceled'
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Spatial index for radius matching
CREATE INDEX idx_businesses_location ON businesses USING GIST(location);

-- ------------------------------------------------------------------------------
-- 2. PROFILES (Staff linked to Supabase Auth)
-- ------------------------------------------------------------------------------
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    phone TEXT,
    role TEXT NOT NULL DEFAULT 'owner', -- 'owner', 'meister', 'geselle', 'buero'
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_profiles_business_id ON profiles(business_id);

-- ------------------------------------------------------------------------------
-- 3. CUSTOMERS (Kundenstamm)
-- ------------------------------------------------------------------------------
CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    salutation TEXT DEFAULT 'Herr',                     -- 'Herr', 'Frau', 'Firma'
    name TEXT NOT NULL,                                -- Nachname oder Firmenname (z.B. "Müller" oder "Hausverwaltung Alster GmbH")
    first_name TEXT,                                   -- Vorname (z.B. "Thomas")
    email TEXT,
    phone TEXT,
    street TEXT,
    zip TEXT,
    city TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_customers_business_id ON customers(business_id);
CREATE INDEX idx_customers_name ON customers(business_id, name);

-- ------------------------------------------------------------------------------
-- 4. JOBS (Aufträge)
-- ------------------------------------------------------------------------------
CREATE TABLE jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
    title TEXT NOT NULL,                               -- e.g. "Steckdoseninstallation Keller"
    description TEXT,
    status TEXT NOT NULL DEFAULT 'draft',              -- 'draft', 'quote_sent', 'in_progress', 'completed', 'invoiced', 'overflow_ready'
    location GEOGRAPHY(Point, 4326),                   -- Einsatzort / Baustelle
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_jobs_business_id ON jobs(business_id);
CREATE INDEX idx_jobs_customer_id ON jobs(customer_id);
CREATE INDEX idx_jobs_status ON jobs(business_id, status);

-- ------------------------------------------------------------------------------
-- 5. CAPTURE LOGS (Sprachaufnahmen & KI-Extraktionen)
-- ------------------------------------------------------------------------------
CREATE TABLE capture_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_id UUID REFERENCES jobs(id) ON DELETE CASCADE,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    audio_storage_path TEXT,
    photo_storage_paths TEXT[] DEFAULT ARRAY[]::TEXT[],
    raw_transcript TEXT,
    ai_parsed_json JSONB,                              -- Structured output from Claude
    confidence_flags JSONB DEFAULT '{}'::JSONB,        -- Warnings/missing price flags
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_capture_logs_job_id ON capture_logs(job_id);
CREATE INDEX idx_capture_logs_business_id ON capture_logs(business_id);

-- ------------------------------------------------------------------------------
-- 6. DOCUMENTS (Angebote & Rechnungen nach GoBD & § 35a EStG)
-- ------------------------------------------------------------------------------
CREATE TABLE documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    job_id UUID REFERENCES jobs(id) ON DELETE SET NULL,
    customer_id UUID NOT NULL REFERENCES customers(id),
    
    doc_type TEXT NOT NULL,                            -- 'quote' (Angebot) or 'invoice' (Rechnung)
    doc_number TEXT NOT NULL,                          -- e.g. "ANG-2026-0001", "RE-2026-0001" (sequential)
    status TEXT NOT NULL DEFAULT 'draft',              -- 'draft', 'sent', 'paid', 'canceled'
    
    date_issued DATE NOT NULL DEFAULT CURRENT_DATE,
    date_due DATE,
    delivery_period TEXT,                              -- Leistungszeitraum (e.g. "01.10.2026" oder "September 2026")
    
    -- Monetary fields strictly in integer CENTS
    subtotal_labor_cents INT NOT NULL DEFAULT 0,       -- Lohnanteil nach § 35a EStG
    subtotal_material_cents INT NOT NULL DEFAULT 0,    -- Materialanteil
    total_net_cents INT NOT NULL DEFAULT 0,
    vat_rate NUMERIC(4,2) NOT NULL DEFAULT 19.00,
    vat_amount_cents INT NOT NULL DEFAULT 0,
    total_gross_cents INT NOT NULL DEFAULT 0,
    
    line_items JSONB NOT NULL DEFAULT '[]'::JSONB,     -- Line items array
    pdf_url TEXT,
    
    -- Compliance & Audit Trail (Phase 4 readiness)
    is_gobd_locked BOOLEAN NOT NULL DEFAULT FALSE,     -- Locked once finalized
    gobd_locked_at TIMESTAMPTZ,
    zugferd_xml_metadata JSONB,                        -- Pre-formatted for EN 16931 e-invoicing
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    CONSTRAINT unique_doc_number_per_business UNIQUE (business_id, doc_type, doc_number)
);

CREATE INDEX idx_documents_business_id ON documents(business_id);
CREATE INDEX idx_documents_customer_id ON documents(customer_id);
CREATE INDEX idx_documents_doc_number ON documents(business_id, doc_type, doc_number);

-- ------------------------------------------------------------------------------
-- 7. ROW LEVEL SECURITY (RLS) POLICIES
-- ------------------------------------------------------------------------------
ALTER TABLE businesses ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE capture_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;

-- Helper function: get current authenticated user's business_id
CREATE OR REPLACE FUNCTION get_user_business_id() 
RETURNS UUID AS $$
  SELECT business_id FROM profiles WHERE id = auth.uid() LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Policies for businesses
CREATE POLICY "Users view and manage their own business" ON businesses
  FOR ALL USING (id = get_user_business_id());

-- Policies for profiles
CREATE POLICY "Users view and manage profiles in their business" ON profiles
  FOR ALL USING (business_id = get_user_business_id());

-- Policies for customers
CREATE POLICY "Users view and manage customers in their business" ON customers
  FOR ALL USING (business_id = get_user_business_id());

-- Policies for jobs
CREATE POLICY "Users view and manage jobs in their business" ON jobs
  FOR ALL USING (business_id = get_user_business_id());

-- Policies for capture_logs
CREATE POLICY "Users view and manage capture logs in their business" ON capture_logs
  FOR ALL USING (business_id = get_user_business_id());

-- Policies for documents
CREATE POLICY "Users view and manage documents in their business" ON documents
  FOR ALL USING (business_id = get_user_business_id());

-- ------------------------------------------------------------------------------
-- 8. SEQUENTIAL NUMBERING FUNCTION (Gapless per business per year)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_next_document_number(
    p_business_id UUID,
    p_doc_type TEXT,
    p_year INT DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INT
)
RETURNS TEXT AS $$
DECLARE
    v_prefix TEXT;
    v_count INT;
    v_doc_number TEXT;
BEGIN
    IF p_doc_type = 'quote' THEN
        v_prefix := 'ANG';
    ELSIF p_doc_type = 'invoice' THEN
        v_prefix := 'RE';
    ELSE
        v_prefix := 'DOC';
    END IF;

    -- Count existing documents for this business, type, and year
    SELECT COUNT(*) + 1 INTO v_count
    FROM documents
    WHERE business_id = p_business_id
      AND doc_type = p_doc_type
      AND doc_number LIKE v_prefix || '-' || p_year || '-%';

    v_doc_number := v_prefix || '-' || p_year || '-' || LPAD(v_count::TEXT, 4, '0');
    RETURN v_doc_number;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
