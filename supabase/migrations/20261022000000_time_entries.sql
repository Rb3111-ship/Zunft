-- Time tracking (Zeiterfassung): who worked how long on which job. A timer is an entry without an
-- end; stopping it sets the end. Entries can be added and corrected by hand. When an invoice is
-- made the boss may bill the tracked time; the entries are then marked with the document and are
-- frozen (they must not be suggested twice or changed afterwards).
--
-- No location data is recorded. This is a working-time record for billing; whether it also meets
-- the legal duty to record working hours is a question for a lawyer, not something the app claims.
--
-- Who sees what: the boss and the office see every entry of the business and may change them
-- (until they are billed). An employee sees and changes only their own (until billed), on jobs
-- they can open.

CREATE TABLE time_entries (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id    UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    user_id        UUID REFERENCES profiles(id) ON DELETE SET NULL,
    user_name      TEXT,
    job_id         UUID REFERENCES jobs(id) ON DELETE SET NULL,
    appointment_id UUID REFERENCES appointments(id) ON DELETE SET NULL,
    started_at     TIMESTAMPTZ NOT NULL,
    ended_at       TIMESTAMPTZ,
    break_minutes  INT NOT NULL DEFAULT 0 CHECK (break_minutes BETWEEN 0 AND 1440),
    note           TEXT CHECK (note IS NULL OR char_length(note) <= 500),
    document_id    UUID REFERENCES documents(id),
    created_by     UUID REFERENCES profiles(id) ON DELETE SET NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (ended_at IS NULL OR ended_at > started_at),
    CHECK (ended_at IS NULL OR ended_at - started_at <= INTERVAL '24 hours'),
    CHECK (ended_at IS NULL OR break_minutes * 60 < EXTRACT(EPOCH FROM (ended_at - started_at)))
);
CREATE INDEX idx_time_entries_business_start ON time_entries (business_id, started_at);
CREATE INDEX idx_time_entries_job ON time_entries (job_id) WHERE job_id IS NOT NULL;
CREATE INDEX idx_time_entries_user ON time_entries (user_id, started_at);
-- One running timer per person.
CREATE UNIQUE INDEX uq_time_entries_running ON time_entries (user_id) WHERE ended_at IS NULL AND user_id IS NOT NULL;

CREATE TRIGGER trg_time_entries_updated_at BEFORE UPDATE ON time_entries
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_time_entries_created_by BEFORE INSERT ON time_entries
    FOR EACH ROW EXECUTE FUNCTION set_created_by();

-- The person, the job and the appointment must belong to the business; the person's name is kept
-- with the entry (the person may leave later, the entry stays).
CREATE OR REPLACE FUNCTION check_time_entry()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_name TEXT;
BEGIN
    IF TG_OP = 'INSERT' OR NEW.user_id IS DISTINCT FROM OLD.user_id THEN
        SELECT full_name INTO v_name FROM profiles WHERE id = NEW.user_id AND business_id = NEW.business_id AND active;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'person not found';
        END IF;
        NEW.user_name := v_name;
    END IF;
    IF NEW.job_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM jobs j WHERE j.id = NEW.job_id AND j.business_id = NEW.business_id) THEN
        RAISE EXCEPTION 'job not found';
    END IF;
    IF NEW.appointment_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM appointments a WHERE a.id = NEW.appointment_id AND a.business_id = NEW.business_id) THEN
        RAISE EXCEPTION 'appointment not found';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_time_entries_check BEFORE INSERT OR UPDATE ON time_entries
    FOR EACH ROW EXECUTE FUNCTION check_time_entry();

-- A billed entry is frozen for the app; only create_document() (not a client) may bill an entry.
CREATE OR REPLACE FUNCTION guard_time_entry()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF current_user = 'authenticated' THEN
        IF OLD.document_id IS NOT NULL THEN
            RAISE EXCEPTION 'this time entry has been billed and cannot be changed';
        END IF;
        IF TG_OP = 'UPDATE' AND NEW.document_id IS DISTINCT FROM OLD.document_id THEN
            RAISE EXCEPTION 'not allowed';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_time_entries_guard BEFORE UPDATE OR DELETE ON time_entries
    FOR EACH ROW EXECUTE FUNCTION guard_time_entry();

ALTER TABLE time_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY time_entries_select ON time_entries FOR SELECT TO authenticated
    USING (business_id = get_user_business_id() AND (is_manager() OR user_id = auth.uid()));

CREATE POLICY time_entries_insert ON time_entries FOR INSERT TO authenticated
    WITH CHECK (business_id = get_user_business_id()
                AND document_id IS NULL
                AND (is_manager()
                     OR (user_id = auth.uid() AND (job_id IS NULL OR can_see_job(job_id)))));

CREATE POLICY time_entries_update ON time_entries FOR UPDATE TO authenticated
    USING (business_id = get_user_business_id() AND (is_manager() OR user_id = auth.uid()))
    WITH CHECK (business_id = get_user_business_id()
                AND (is_manager()
                     OR (user_id = auth.uid() AND (job_id IS NULL OR can_see_job(job_id)))));

CREATE POLICY time_entries_delete ON time_entries FOR DELETE TO authenticated
    USING (business_id = get_user_business_id() AND (is_manager() OR user_id = auth.uid()));

REVOKE ALL ON FUNCTION check_time_entry(), guard_time_entry() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_document(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_business_id UUID := get_user_business_id();
    v_business    businesses%ROWTYPE;
    v_id          UUID;
    v_existing    documents%ROWTYPE;
    v_type        TEXT;
    v_issued      DATE;
    v_due         DATE;
    v_customer_id UUID;
    v_job_id      UUID;
    v_recipient   JSONB;
    v_item        JSONB;
    v_items       JSONB := '[]'::JSONB;
    v_qty         NUMERIC;
    v_price       NUMERIC;
    v_line        BIGINT;
    v_labor       BIGINT := 0;
    v_material    BIGINT := 0;
    v_net         BIGINT;
    v_vat_amount  BIGINT;
    v_gross       BIGINT;
    v_number      TEXT;
    v_row         documents%ROWTYPE;
BEGIN
    -- Only the boss and the office issue documents (employees record notes, nothing more).
    IF auth.uid() IS NULL OR v_business_id IS NULL OR NOT is_manager() THEN
        RAISE EXCEPTION 'not allowed';
    END IF;

    v_id := NULLIF(p->>'id', '')::UUID;
    IF v_id IS NULL THEN
        RAISE EXCEPTION 'id is required';
    END IF;

    -- Idempotent retry: the phone lost the answer, asks again with the same id.
    SELECT * INTO v_existing FROM documents WHERE id = v_id;
    IF FOUND THEN
        IF v_existing.business_id <> v_business_id THEN
            RAISE EXCEPTION 'not allowed';
        END IF;
        RETURN to_jsonb(v_existing);
    END IF;

    SELECT * INTO v_business FROM businesses WHERE id = v_business_id;

    v_type := p->>'doc_type';
    IF COALESCE(v_type, '') NOT IN ('quote', 'invoice') THEN
        RAISE EXCEPTION 'doc_type must be quote or invoice';
    END IF;

    v_issued := COALESCE(NULLIF(p->>'date_issued', '')::DATE, CURRENT_DATE);
    IF v_issued < CURRENT_DATE - 365 OR v_issued > CURRENT_DATE + 30 THEN
        RAISE EXCEPTION 'date_issued is out of range';
    END IF;
    v_due := NULLIF(p->>'date_due', '')::DATE;
    IF v_due IS NOT NULL AND v_due < v_issued THEN
        RAISE EXCEPTION 'date_due is before date_issued';
    END IF;

    v_recipient := p->'recipient_snapshot';
    IF v_recipient IS NULL OR jsonb_typeof(v_recipient) <> 'object'
       OR COALESCE(TRIM(v_recipient->>'name'), '') = '' THEN
        RAISE EXCEPTION 'recipient name is required';
    END IF;
    v_recipient := jsonb_build_object(
        'name', LEFT(TRIM(v_recipient->>'name'), 120),
        'address', NULLIF(LEFT(TRIM(COALESCE(v_recipient->>'address', '')), 200), '')
    );

    -- References must belong to the caller's business.
    v_customer_id := NULLIF(p->>'customer_id', '')::UUID;
    IF v_customer_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM customers WHERE id = v_customer_id AND business_id = v_business_id) THEN
        RAISE EXCEPTION 'customer does not belong to this business';
    END IF;
    v_job_id := NULLIF(p->>'job_id', '')::UUID;
    IF v_job_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM jobs WHERE id = v_job_id AND business_id = v_business_id) THEN
        RAISE EXCEPTION 'job does not belong to this business';
    END IF;

    -- Line items: validate each, compute its total.
    -- NULL-safe on purpose: NULL NOT IN (...) is NULL, which an IF treats as false and would skip the check.
    IF COALESCE(jsonb_typeof(p->'line_items'), '') <> 'array' THEN
        RAISE EXCEPTION 'line_items must be an array';
    END IF;
    IF jsonb_array_length(p->'line_items') NOT BETWEEN 1 AND 50 THEN
        RAISE EXCEPTION 'line_items must contain 1 to 50 entries';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p->'line_items') LOOP
        IF COALESCE(v_item->>'type', '') NOT IN ('labor', 'material', 'flat_fee') THEN
            RAISE EXCEPTION 'invalid line item type';
        END IF;
        IF COALESCE(v_item->>'unit', '') NOT IN ('Std', 'Stk', 'm', 'Pauschal') THEN
            RAISE EXCEPTION 'invalid line item unit';
        END IF;
        IF COALESCE(TRIM(v_item->>'description'), '') = '' THEN
            RAISE EXCEPTION 'line item description is required';
        END IF;
        v_qty := (v_item->>'quantity')::NUMERIC;
        v_price := (v_item->>'unit_price_net_cents')::NUMERIC;
        IF v_qty IS NULL OR v_qty <= 0 OR v_qty > 100000 THEN
            RAISE EXCEPTION 'invalid line item quantity';
        END IF;
        IF v_price IS NULL OR v_price < 0 OR v_price > 10000000 OR v_price <> TRUNC(v_price) THEN
            RAISE EXCEPTION 'invalid line item price';
        END IF;

        v_line := ROUND(v_qty * v_price);
        -- Ã‚Â§ 35a EStG: labor and flat fees (Anfahrt etc.) are service costs; only material is excluded.
        IF v_item->>'type' IN ('labor', 'flat_fee') THEN
            v_labor := v_labor + v_line;
        ELSE
            v_material := v_material + v_line;
        END IF;

        v_items := v_items || jsonb_build_object(
            'type', v_item->>'type',
            'description', LEFT(TRIM(v_item->>'description'), 200),
            'quantity', v_qty,
            'unit', v_item->>'unit',
            'unit_price_net_cents', v_price::BIGINT,
            'total_net_cents', v_line
        );
    END LOOP;

    v_net := v_labor + v_material;
    v_vat_amount := ROUND(v_net * v_business.default_vat_rate / 100);
    v_gross := v_net + v_vat_amount;

    IF v_type = 'invoice' THEN
        -- Ã‚Â§ 14 UStG: the sender's address and a tax number / USt-IdNr. must be on the invoice.
        IF COALESCE(TRIM(v_business.address_street), '') = ''
           OR COALESCE(TRIM(v_business.address_zip), '') = ''
           OR COALESCE(TRIM(v_business.address_city), '') = '' THEN
            RAISE EXCEPTION 'business address is incomplete';
        END IF;
        IF COALESCE(TRIM(v_business.tax_number), '') = '' AND COALESCE(TRIM(v_business.vat_id), '') = '' THEN
            RAISE EXCEPTION 'tax number or VAT id is required';
        END IF;
        -- Ã‚Â§ 33 UStDV: invoices up to 250 EUR gross may omit the recipient's address.
        IF v_gross > 25000 AND v_recipient->>'address' IS NULL THEN
            RAISE EXCEPTION 'recipient address is required for invoices over 250 EUR';
        END IF;
    END IF;

    -- Issue the number and store the document in this same transaction.
    v_number := get_next_document_number(v_business_id, v_type, EXTRACT(YEAR FROM v_issued)::INT);

    INSERT INTO documents (
        id, business_id, job_id, customer_id, doc_type, doc_number, status, title,
        date_issued, date_due, delivery_period,
        subtotal_labor_cents, subtotal_material_cents, total_net_cents,
        vat_rate, vat_amount_cents, total_gross_cents,
        line_items, recipient_snapshot, is_gobd_locked, e_invoice
    ) VALUES (
        v_id, v_business_id, v_job_id, v_customer_id, v_type, v_number, 'issued',
        NULLIF(LEFT(TRIM(COALESCE(p->>'title', '')), 120), ''),
        v_issued, v_due, NULLIF(LEFT(TRIM(COALESCE(p->>'delivery_period', '')), 100), ''),
        v_labor, v_material, v_net,
        v_business.default_vat_rate, v_vat_amount, v_gross,
        v_items, v_recipient, TRUE,
        v_type = 'invoice' AND COALESCE((p->>'e_invoice')::BOOLEAN, FALSE)
    ) RETURNING * INTO v_row;

    -- The voice notes of the job that went into this document are now used up: they must not
    -- appear again in the next invoice for the same job. Same transaction as the insert.
    IF v_job_id IS NOT NULL AND jsonb_typeof(p->'capture_log_ids') = 'array' THEN
        UPDATE capture_logs
           SET document_id = v_id
         WHERE business_id = v_business_id
           AND job_id = v_job_id
           AND document_id IS NULL
           AND discarded_at IS NULL
           AND id IN (SELECT jsonb_array_elements_text(p->'capture_log_ids')::UUID);
    END IF;

    -- The tracked working time that went into this document is used up the same way: finished
    -- entries of this job that the boss chose to bill. They must not be suggested again.
    IF v_job_id IS NOT NULL AND jsonb_typeof(p->'time_entry_ids') = 'array' THEN
        UPDATE time_entries
           SET document_id = v_id
         WHERE business_id = v_business_id
           AND job_id = v_job_id
           AND document_id IS NULL
           AND ended_at IS NOT NULL
           AND id IN (SELECT jsonb_array_elements_text(p->'time_entry_ids')::UUID);
    END IF;

    RETURN to_jsonb(v_row);
END;
$function$;

REVOKE ALL ON FUNCTION create_document(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_document(JSONB) TO authenticated;
