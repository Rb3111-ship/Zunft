-- ==============================================================================
-- Migration: 20261004000000_document_workflow.sql
--
-- 1. create_document(): the ONLY way to create a quote/invoice. Validates everything, computes
--    the totals itself from the line items, issues the number and inserts the row in ONE
--    transaction. That is what makes numbers truly gapless: the number cannot be consumed
--    without a stored document, and a retry with the same id returns the same document.
-- 2. Locked (GoBD) documents keep their content frozen but may still move through the
--    status workflow (issued -> sent -> paid) and get their pdf_url set.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Status workflow: a numbered document is "issued", not a "draft"
-- ------------------------------------------------------------------------------
ALTER TABLE documents DROP CONSTRAINT documents_status_check;
ALTER TABLE documents
    ADD CONSTRAINT documents_status_check CHECK (status IN ('draft', 'issued', 'sent', 'paid', 'canceled'));

COMMENT ON COLUMN documents.pdf_url IS 'Storage path of the PDF in the private "documents" bucket';
COMMENT ON COLUMN documents.recipient_snapshot IS
    'Recipient as printed: {"name": "...", "address": "street, zip city"}. Frozen with the document.';

-- The subject line printed on the document (frozen with it).
ALTER TABLE documents ADD COLUMN title TEXT;

-- ------------------------------------------------------------------------------
-- 2. Clients can no longer INSERT documents directly
-- ------------------------------------------------------------------------------
DROP POLICY documents_insert ON documents;

-- Locked rows must stay updatable for status / pdf_url; the trigger restricts the columns.
DROP POLICY documents_update ON documents;
CREATE POLICY documents_update ON documents FOR UPDATE TO authenticated
    USING (business_id = get_user_business_id())
    WITH CHECK (business_id = get_user_business_id());

-- ------------------------------------------------------------------------------
-- 3. Guard trigger: frozen content, controlled status changes
-- ------------------------------------------------------------------------------
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
        -- Everything except status / pdf_url / updated_at is frozen (including the lock itself).
        IF (to_jsonb(NEW) - 'status' - 'pdf_url' - 'updated_at')
           IS DISTINCT FROM (to_jsonb(OLD) - 'status' - 'pdf_url' - 'updated_at') THEN
            RAISE EXCEPTION 'document % is GoBD-locked: only status and pdf_url may change', OLD.doc_number;
        END IF;

        IF NEW.status IS DISTINCT FROM OLD.status AND NOT (
               (OLD.status = 'issued' AND NEW.status IN ('sent', 'paid', 'canceled'))
            OR (OLD.status = 'sent'   AND NEW.status IN ('paid', 'canceled'))
        ) THEN
            RAISE EXCEPTION 'status cannot change from % to %', OLD.status, NEW.status;
        END IF;
        RETURN NEW;
    END IF;

    -- Not locked (only possible for rows created outside create_document): original rules.
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

-- Defense in depth on INSERT: the number must really have been issued by the counter, and
-- locked rows get their lock time. SECURITY DEFINER because the counter table has no policies.
CREATE OR REPLACE FUNCTION guard_document_insert()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_parts TEXT[];
    v_prefix TEXT := CASE NEW.doc_type WHEN 'invoice' THEN 'RE' ELSE 'ANG' END;
    v_last INT;
BEGIN
    v_parts := regexp_match(NEW.doc_number, '^(RE|ANG)-(\d{4})-(\d+)$');
    IF v_parts IS NULL THEN
        RAISE EXCEPTION 'invalid document number %', NEW.doc_number;
    END IF;
    -- (a CASE inside an IF condition would be cut off at its first THEN, hence the variable)
    IF v_parts[1] <> v_prefix THEN
        RAISE EXCEPTION 'document number % does not match type %', NEW.doc_number, NEW.doc_type;
    END IF;

    SELECT last_number INTO v_last FROM document_counters
    WHERE business_id = NEW.business_id AND doc_type = NEW.doc_type AND year = v_parts[2]::INT;
    IF v_last IS NULL OR v_parts[3]::INT > v_last THEN
        RAISE EXCEPTION 'document number % was never issued', NEW.doc_number;
    END IF;

    IF NEW.is_gobd_locked AND NEW.gobd_locked_at IS NULL THEN
        NEW.gobd_locked_at := NOW();
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_documents_insert_guard BEFORE INSERT ON documents
    FOR EACH ROW EXECUTE FUNCTION guard_document_insert();

-- ------------------------------------------------------------------------------
-- 4. create_document(): validate, compute, number, insert - atomically
-- ------------------------------------------------------------------------------
-- Input (jsonb): id, doc_type, title?, job_id?, customer_id?, date_issued?, date_due?, delivery_period?,
--   recipient_snapshot {name, address?}, line_items [{type, description, quantity, unit,
--   unit_price_net_cents}]. Totals and VAT rate are NOT taken from the client.
-- Returns the stored row as jsonb. A repeated call with the same id returns the same row.
CREATE OR REPLACE FUNCTION create_document(p JSONB)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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
    IF auth.uid() IS NULL OR v_business_id IS NULL THEN
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
        -- § 35a EStG: labor and flat fees (Anfahrt etc.) are service costs; only material is excluded.
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
        -- § 14 UStG: the sender's address and a tax number / USt-IdNr. must be on the invoice.
        IF COALESCE(TRIM(v_business.address_street), '') = ''
           OR COALESCE(TRIM(v_business.address_zip), '') = ''
           OR COALESCE(TRIM(v_business.address_city), '') = '' THEN
            RAISE EXCEPTION 'business address is incomplete';
        END IF;
        IF COALESCE(TRIM(v_business.tax_number), '') = '' AND COALESCE(TRIM(v_business.vat_id), '') = '' THEN
            RAISE EXCEPTION 'tax number or VAT id is required';
        END IF;
        -- § 33 UStDV: invoices up to 250 EUR gross may omit the recipient's address.
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
        line_items, recipient_snapshot, is_gobd_locked
    ) VALUES (
        v_id, v_business_id, v_job_id, v_customer_id, v_type, v_number, 'issued',
        NULLIF(LEFT(TRIM(COALESCE(p->>'title', '')), 120), ''),
        v_issued, v_due, NULLIF(LEFT(TRIM(COALESCE(p->>'delivery_period', '')), 100), ''),
        v_labor, v_material, v_net,
        v_business.default_vat_rate, v_vat_amount, v_gross,
        v_items, v_recipient, TRUE
    ) RETURNING * INTO v_row;

    RETURN to_jsonb(v_row);
END;
$$;

REVOKE ALL ON FUNCTION create_document(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_document(JSONB) TO authenticated;

-- get_next_document_number stays callable (it checks the business itself) but the app only
-- uses it through create_document(). Revoke direct use so a number can never be consumed
-- without a stored document.
REVOKE EXECUTE ON FUNCTION get_next_document_number(UUID, TEXT, INT) FROM authenticated;
