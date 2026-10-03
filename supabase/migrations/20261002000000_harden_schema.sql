-- ==============================================================================
-- Migration: 20261002000000_harden_schema.sql
-- Hardens the init schema: constraints, updated_at triggers, safe gapless
-- numbering, per-command RLS with WITH CHECK, GoBD locking, storage policies.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. CONSTRAINTS
-- ------------------------------------------------------------------------------
ALTER TABLE profiles
    ADD CONSTRAINT profiles_role_check CHECK (role IN ('owner', 'meister', 'geselle', 'buero'));

ALTER TABLE businesses
    ADD CONSTRAINT businesses_subscription_status_check
        CHECK (subscription_status IN ('trialing', 'active', 'past_due', 'canceled')),
    ADD CONSTRAINT businesses_vat_rate_check CHECK (default_vat_rate BETWEEN 0 AND 100),
    ADD CONSTRAINT businesses_hourly_rate_check CHECK (default_hourly_rate_cents >= 0);

ALTER TABLE jobs
    ADD CONSTRAINT jobs_status_check
        CHECK (status IN ('draft', 'quote_sent', 'in_progress', 'completed', 'invoiced', 'overflow_ready'));

ALTER TABLE documents
    ADD CONSTRAINT documents_doc_type_check CHECK (doc_type IN ('quote', 'invoice')),
    ADD CONSTRAINT documents_status_check CHECK (status IN ('draft', 'sent', 'paid', 'canceled')),
    ADD CONSTRAINT documents_vat_rate_check CHECK (vat_rate BETWEEN 0 AND 100),
    ADD CONSTRAINT documents_amounts_check CHECK (
        subtotal_labor_cents >= 0 AND subtotal_material_cents >= 0 AND total_net_cents >= 0
        AND total_net_cents = subtotal_labor_cents + subtotal_material_cents
        AND total_gross_cents = total_net_cents + vat_amount_cents
    );

-- The AI flow can produce a brand-new customer that has no customers row yet.
-- Keep a snapshot of the recipient on the document (also what GoBD wants: the
-- invoice must keep showing what was issued even if the customer is edited later).
ALTER TABLE documents ALTER COLUMN customer_id DROP NOT NULL;
ALTER TABLE documents ADD COLUMN recipient_snapshot JSONB;
ALTER TABLE documents
    ADD CONSTRAINT documents_recipient_check
        CHECK (customer_id IS NOT NULL OR recipient_snapshot IS NOT NULL);

COMMENT ON COLUMN capture_logs.ai_parsed_json IS 'Structured LLM output (validated by the process-capture Edge Function)';

-- ------------------------------------------------------------------------------
-- 2. updated_at TRIGGERS
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_businesses_updated_at BEFORE UPDATE ON businesses FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_profiles_updated_at   BEFORE UPDATE ON profiles   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_customers_updated_at  BEFORE UPDATE ON customers  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_jobs_updated_at       BEFORE UPDATE ON jobs       FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_documents_updated_at  BEFORE UPDATE ON documents  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ------------------------------------------------------------------------------
-- 3. RLS HELPERS (SECURITY DEFINER with a pinned search_path)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_user_business_id()
RETURNS UUID
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public, pg_temp
AS $$
    SELECT business_id FROM profiles WHERE id = auth.uid() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION get_user_role()
RETURNS TEXT
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public, pg_temp
AS $$
    SELECT role FROM profiles WHERE id = auth.uid() LIMIT 1;
$$;

-- ------------------------------------------------------------------------------
-- 4. RLS POLICIES: per command, with WITH CHECK
-- ------------------------------------------------------------------------------
DROP POLICY "Users view and manage their own business" ON businesses;
DROP POLICY "Users view and manage profiles in their business" ON profiles;
DROP POLICY "Users view and manage customers in their business" ON customers;
DROP POLICY "Users view and manage jobs in their business" ON jobs;
DROP POLICY "Users view and manage capture logs in their business" ON capture_logs;
DROP POLICY "Users view and manage documents in their business" ON documents;

-- businesses: created only through create_business_for_user(); never deleted by clients.
CREATE POLICY businesses_select ON businesses FOR SELECT TO authenticated
    USING (id = get_user_business_id());
CREATE POLICY businesses_update ON businesses FOR UPDATE TO authenticated
    USING (id = get_user_business_id() AND get_user_role() IN ('owner', 'buero'))
    WITH CHECK (id = get_user_business_id());

-- profiles: see colleagues, edit your own row, owners manage the others.
-- Role / business changes are additionally guarded by a trigger (below).
CREATE POLICY profiles_select ON profiles FOR SELECT TO authenticated
    USING (business_id = get_user_business_id());
CREATE POLICY profiles_update ON profiles FOR UPDATE TO authenticated
    USING (business_id = get_user_business_id() AND (id = auth.uid() OR get_user_role() = 'owner'))
    WITH CHECK (business_id = get_user_business_id());
CREATE POLICY profiles_delete ON profiles FOR DELETE TO authenticated
    USING (business_id = get_user_business_id() AND get_user_role() = 'owner' AND id <> auth.uid());

CREATE OR REPLACE FUNCTION guard_profile_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.business_id IS DISTINCT FROM OLD.business_id THEN
        RAISE EXCEPTION 'profiles.business_id cannot be changed';
    END IF;
    IF NEW.role IS DISTINCT FROM OLD.role AND get_user_role() IS DISTINCT FROM 'owner' THEN
        RAISE EXCEPTION 'only an owner can change roles';
    END IF;
    IF NEW.role IS DISTINCT FROM OLD.role AND OLD.id = auth.uid() THEN
        RAISE EXCEPTION 'you cannot change your own role';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_profiles_guard BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION guard_profile_update();

-- customers
CREATE POLICY customers_select ON customers FOR SELECT TO authenticated
    USING (business_id = get_user_business_id());
CREATE POLICY customers_insert ON customers FOR INSERT TO authenticated
    WITH CHECK (business_id = get_user_business_id());
CREATE POLICY customers_update ON customers FOR UPDATE TO authenticated
    USING (business_id = get_user_business_id())
    WITH CHECK (business_id = get_user_business_id());
CREATE POLICY customers_delete ON customers FOR DELETE TO authenticated
    USING (business_id = get_user_business_id() AND get_user_role() IN ('owner', 'meister', 'buero'));

-- jobs: referenced customer must belong to the same business.
CREATE POLICY jobs_select ON jobs FOR SELECT TO authenticated
    USING (business_id = get_user_business_id());
CREATE POLICY jobs_insert ON jobs FOR INSERT TO authenticated
    WITH CHECK (
        business_id = get_user_business_id()
        AND (customer_id IS NULL OR EXISTS (
            SELECT 1 FROM customers c WHERE c.id = customer_id AND c.business_id = jobs.business_id))
    );
CREATE POLICY jobs_update ON jobs FOR UPDATE TO authenticated
    USING (business_id = get_user_business_id())
    WITH CHECK (
        business_id = get_user_business_id()
        AND (customer_id IS NULL OR EXISTS (
            SELECT 1 FROM customers c WHERE c.id = customer_id AND c.business_id = jobs.business_id))
    );
CREATE POLICY jobs_delete ON jobs FOR DELETE TO authenticated
    USING (business_id = get_user_business_id() AND get_user_role() IN ('owner', 'meister', 'buero'));

-- capture_logs: append-only audit trail (no UPDATE / DELETE for clients).
CREATE POLICY capture_logs_select ON capture_logs FOR SELECT TO authenticated
    USING (business_id = get_user_business_id());
CREATE POLICY capture_logs_insert ON capture_logs FOR INSERT TO authenticated
    WITH CHECK (
        business_id = get_user_business_id()
        AND (job_id IS NULL OR EXISTS (
            SELECT 1 FROM jobs j WHERE j.id = job_id AND j.business_id = capture_logs.business_id))
    );

-- documents: locked (GoBD) documents are immutable; see trigger below.
CREATE POLICY documents_select ON documents FOR SELECT TO authenticated
    USING (business_id = get_user_business_id());
CREATE POLICY documents_insert ON documents FOR INSERT TO authenticated
    WITH CHECK (
        business_id = get_user_business_id()
        AND (customer_id IS NULL OR EXISTS (
            SELECT 1 FROM customers c WHERE c.id = customer_id AND c.business_id = documents.business_id))
        AND (job_id IS NULL OR EXISTS (
            SELECT 1 FROM jobs j WHERE j.id = job_id AND j.business_id = documents.business_id))
    );
CREATE POLICY documents_update ON documents FOR UPDATE TO authenticated
    USING (business_id = get_user_business_id() AND NOT is_gobd_locked)
    WITH CHECK (
        business_id = get_user_business_id()
        AND (customer_id IS NULL OR EXISTS (
            SELECT 1 FROM customers c WHERE c.id = customer_id AND c.business_id = documents.business_id))
        AND (job_id IS NULL OR EXISTS (
            SELECT 1 FROM jobs j WHERE j.id = job_id AND j.business_id = documents.business_id))
    );
CREATE POLICY documents_delete ON documents FOR DELETE TO authenticated
    USING (business_id = get_user_business_id() AND status = 'draft' AND NOT is_gobd_locked);

CREATE OR REPLACE FUNCTION guard_document_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.is_gobd_locked THEN
            RAISE EXCEPTION 'document % is GoBD-locked and cannot be deleted', OLD.doc_number;
        END IF;
        RETURN OLD;
    END IF;

    IF OLD.is_gobd_locked THEN
        RAISE EXCEPTION 'document % is GoBD-locked and cannot be changed', OLD.doc_number;
    END IF;
    IF NEW.business_id IS DISTINCT FROM OLD.business_id
       OR NEW.doc_type IS DISTINCT FROM OLD.doc_type
       OR NEW.doc_number IS DISTINCT FROM OLD.doc_number THEN
        RAISE EXCEPTION 'business_id, doc_type and doc_number are immutable';
    END IF;
    IF NEW.is_gobd_locked AND NEW.gobd_locked_at IS NULL THEN
        NEW.gobd_locked_at := NOW();
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_documents_guard BEFORE UPDATE OR DELETE ON documents
    FOR EACH ROW EXECUTE FUNCTION guard_document_change();

-- ------------------------------------------------------------------------------
-- 5. ONBOARDING: create a business + owner profile atomically
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_business_for_user(
    p_business_name TEXT,
    p_owner_name TEXT,
    p_trade_category TEXT DEFAULT 'elektro'
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_business_id UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'not authenticated';
    END IF;
    IF EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
        RAISE EXCEPTION 'user already belongs to a business';
    END IF;
    IF COALESCE(TRIM(p_business_name), '') = '' OR COALESCE(TRIM(p_owner_name), '') = '' THEN
        RAISE EXCEPTION 'business name and owner name are required';
    END IF;

    INSERT INTO businesses (name, owner_name, trade_category)
    VALUES (TRIM(p_business_name), TRIM(p_owner_name), p_trade_category)
    RETURNING id INTO v_business_id;

    INSERT INTO profiles (id, business_id, full_name, role)
    VALUES (auth.uid(), v_business_id, TRIM(p_owner_name), 'owner');

    RETURN v_business_id;
END;
$$;

-- ------------------------------------------------------------------------------
-- 6. GAPLESS, CONCURRENCY-SAFE DOCUMENT NUMBERING
-- ------------------------------------------------------------------------------
-- One counter row per business / type / year. The upsert takes a row lock, so
-- concurrent callers serialize, and because the increment lives in the caller's
-- transaction a rollback also rolls the number back (no gaps from failed saves).
-- Call it only when a document is FINALIZED, never for drafts.
CREATE TABLE document_counters (
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    doc_type    TEXT NOT NULL CHECK (doc_type IN ('quote', 'invoice')),
    year        INT  NOT NULL CHECK (year BETWEEN 2000 AND 2200),
    last_number INT  NOT NULL DEFAULT 0 CHECK (last_number >= 0),
    PRIMARY KEY (business_id, doc_type, year)
);
ALTER TABLE document_counters ENABLE ROW LEVEL SECURITY;  -- no policies: only the function touches it

-- Seed counters from any existing documents so numbers never repeat.
INSERT INTO document_counters (business_id, doc_type, year, last_number)
SELECT business_id, doc_type,
       SUBSTRING(doc_number FROM '-(\d{4})-')::INT,
       MAX(SUBSTRING(doc_number FROM '-(\d+)$')::INT)
FROM documents
WHERE doc_number ~ '^[A-Z]+-\d{4}-\d+$'
GROUP BY business_id, doc_type, SUBSTRING(doc_number FROM '-(\d{4})-')::INT
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION get_next_document_number(
    p_business_id UUID,
    p_doc_type TEXT,
    p_year INT DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INT
)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_prefix TEXT;
    v_next INT;
BEGIN
    IF auth.uid() IS NULL OR p_business_id IS DISTINCT FROM get_user_business_id() THEN
        RAISE EXCEPTION 'not allowed for this business';
    END IF;

    v_prefix := CASE p_doc_type WHEN 'quote' THEN 'ANG' WHEN 'invoice' THEN 'RE' END;
    IF v_prefix IS NULL THEN
        RAISE EXCEPTION 'unknown document type %', p_doc_type;
    END IF;

    INSERT INTO document_counters AS dc (business_id, doc_type, year, last_number)
    VALUES (p_business_id, p_doc_type, p_year, 1)
    ON CONFLICT (business_id, doc_type, year)
    DO UPDATE SET last_number = dc.last_number + 1
    RETURNING last_number INTO v_next;

    RETURN v_prefix || '-' || p_year || '-' || LPAD(v_next::TEXT, 4, '0');
END;
$$;

-- ------------------------------------------------------------------------------
-- 7. FUNCTION PRIVILEGES: never callable by anon
-- ------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION get_user_business_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION get_user_role() FROM PUBLIC;
REVOKE ALL ON FUNCTION create_business_for_user(TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION get_next_document_number(UUID, TEXT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_user_business_id() TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_role() TO authenticated;
GRANT EXECUTE ON FUNCTION create_business_for_user(TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_next_document_number(UUID, TEXT, INT) TO authenticated;

-- ------------------------------------------------------------------------------
-- 8. STORAGE: private buckets, files live under "<business_id>/..."
-- (process-capture relies on this prefix.)
-- ------------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('captures', 'captures', FALSE), ('documents', 'documents', FALSE)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY captures_select ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'captures' AND (storage.foldername(name))[1] = get_user_business_id()::TEXT);
CREATE POLICY captures_insert ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'captures' AND (storage.foldername(name))[1] = get_user_business_id()::TEXT);

CREATE POLICY documents_files_select ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'documents' AND (storage.foldername(name))[1] = get_user_business_id()::TEXT);
CREATE POLICY documents_files_insert ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'documents' AND (storage.foldername(name))[1] = get_user_business_id()::TEXT);
CREATE POLICY documents_files_update ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'documents' AND (storage.foldername(name))[1] = get_user_business_id()::TEXT)
    WITH CHECK (bucket_id = 'documents' AND (storage.foldername(name))[1] = get_user_business_id()::TEXT);
