-- Stornorechnung: a wrong invoice is never edited or deleted (GoBD). It is cancelled by a NEW
-- document (type 'cancellation', number ST-JJJJ-NNNN) that repeats the invoice with negative
-- amounts and names the original. The original gets the status 'canceled'. The notes of the job
-- are released again, so a corrected invoice can be made from them.

ALTER TABLE documents DROP CONSTRAINT documents_doc_type_check;
ALTER TABLE documents
    ADD CONSTRAINT documents_doc_type_check CHECK (doc_type IN ('quote', 'invoice', 'cancellation'));
ALTER TABLE document_counters DROP CONSTRAINT document_counters_doc_type_check;
ALTER TABLE document_counters
    ADD CONSTRAINT document_counters_doc_type_check CHECK (doc_type IN ('quote', 'invoice', 'cancellation'));

-- Amounts are never negative, except on a cancellation, where all of them are.
ALTER TABLE documents DROP CONSTRAINT documents_amounts_check;
ALTER TABLE documents ADD CONSTRAINT documents_amounts_check CHECK (
    total_net_cents = subtotal_labor_cents + subtotal_material_cents
    AND total_gross_cents = total_net_cents + vat_amount_cents
    AND (doc_type = 'cancellation'
         OR (subtotal_labor_cents >= 0 AND subtotal_material_cents >= 0 AND total_net_cents >= 0))
    AND (doc_type <> 'cancellation'
         OR (subtotal_labor_cents <= 0 AND subtotal_material_cents <= 0 AND total_net_cents <= 0))
);

ALTER TABLE documents ADD COLUMN cancels_document_id UUID REFERENCES documents(id);
COMMENT ON COLUMN documents.cancels_document_id IS 'For a cancellation: the invoice it cancels';
-- An invoice can be cancelled only once.
CREATE UNIQUE INDEX uq_documents_cancels ON documents (cancels_document_id) WHERE cancels_document_id IS NOT NULL;

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

    v_prefix := CASE p_doc_type WHEN 'quote' THEN 'ANG' WHEN 'invoice' THEN 'RE' WHEN 'cancellation' THEN 'ST' END;
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
REVOKE EXECUTE ON FUNCTION get_next_document_number(UUID, TEXT, INT) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION guard_document_insert()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_parts TEXT[];
    v_prefix TEXT := CASE NEW.doc_type WHEN 'invoice' THEN 'RE' WHEN 'cancellation' THEN 'ST' ELSE 'ANG' END;
    v_last INT;
BEGIN
    v_parts := regexp_match(NEW.doc_number, '^(RE|ANG|ST)-(\d{4})-(\d+)$');
    IF v_parts IS NULL THEN
        RAISE EXCEPTION 'invalid document number %', NEW.doc_number;
    END IF;
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

-- Input: {id: uuid of the new Stornorechnung, original_id: uuid of the invoice}.
-- Returns {cancellation: <row>, original: <row>}. Repeating the call with the same id returns the same result.
CREATE OR REPLACE FUNCTION cancel_document(p JSONB)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_business_id UUID := get_user_business_id();
    v_id          UUID := NULLIF(p->>'id', '')::UUID;
    v_orig_id     UUID := NULLIF(p->>'original_id', '')::UUID;
    v_orig        documents%ROWTYPE;
    v_existing    documents%ROWTYPE;
    v_row         documents%ROWTYPE;
    v_items       JSONB;
    v_number      TEXT;
    v_today       DATE := CURRENT_DATE;
BEGIN
    IF auth.uid() IS NULL OR v_business_id IS NULL OR NOT is_manager() THEN
        RAISE EXCEPTION 'not allowed';
    END IF;
    IF v_id IS NULL OR v_orig_id IS NULL THEN
        RAISE EXCEPTION 'id and original_id are required';
    END IF;

    SELECT * INTO v_existing FROM documents WHERE id = v_id;
    IF FOUND THEN
        IF v_existing.business_id <> v_business_id THEN RAISE EXCEPTION 'not allowed'; END IF;
        SELECT * INTO v_orig FROM documents WHERE id = v_existing.cancels_document_id;
        RETURN jsonb_build_object('cancellation', to_jsonb(v_existing), 'original', to_jsonb(v_orig));
    END IF;

    SELECT * INTO v_orig FROM documents WHERE id = v_orig_id AND business_id = v_business_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'document not found'; END IF;
    IF v_orig.doc_type <> 'invoice' THEN RAISE EXCEPTION 'only invoices can be cancelled'; END IF;
    IF v_orig.status = 'paid' THEN RAISE EXCEPTION 'invoice is already paid'; END IF;
    IF v_orig.status NOT IN ('issued', 'sent') THEN RAISE EXCEPTION 'invoice is already cancelled'; END IF;

    SELECT COALESCE(jsonb_agg(
               (item - 'unit_price_net_cents' - 'total_net_cents')
               || jsonb_build_object(
                    'unit_price_net_cents', -((item->>'unit_price_net_cents')::BIGINT),
                    'total_net_cents', -((item->>'total_net_cents')::BIGINT))
               ORDER BY ord), '[]'::JSONB)
      INTO v_items
      FROM jsonb_array_elements(v_orig.line_items) WITH ORDINALITY AS t(item, ord);

    v_number := get_next_document_number(v_business_id, 'cancellation', EXTRACT(YEAR FROM v_today)::INT);

    INSERT INTO documents (
        id, business_id, job_id, customer_id, doc_type, doc_number, status, title,
        date_issued, date_due, delivery_period,
        subtotal_labor_cents, subtotal_material_cents, total_net_cents,
        vat_rate, vat_amount_cents, total_gross_cents,
        line_items, recipient_snapshot, is_gobd_locked, cancels_document_id
    ) VALUES (
        v_id, v_business_id, v_orig.job_id, v_orig.customer_id, 'cancellation', v_number, 'issued',
        'Stornierung der Rechnung ' || v_orig.doc_number || ' vom ' || TO_CHAR(v_orig.date_issued, 'DD.MM.YYYY'),
        v_today, NULL, v_orig.delivery_period,
        -v_orig.subtotal_labor_cents, -v_orig.subtotal_material_cents, -v_orig.total_net_cents,
        v_orig.vat_rate, -v_orig.vat_amount_cents, -v_orig.total_gross_cents,
        v_items, v_orig.recipient_snapshot, TRUE, v_orig.id
    ) RETURNING * INTO v_row;

    UPDATE documents SET status = 'canceled' WHERE id = v_orig.id RETURNING * INTO v_orig;

    -- Release the notes that were billed, and reopen the job: a corrected invoice can be made from them.
    UPDATE capture_logs SET document_id = NULL WHERE document_id = v_orig.id AND business_id = v_business_id;
    IF v_orig.job_id IS NOT NULL THEN
        UPDATE jobs SET status = 'in_progress' WHERE id = v_orig.job_id AND status = 'invoiced';
    END IF;

    RETURN jsonb_build_object('cancellation', to_jsonb(v_row), 'original', to_jsonb(v_orig));
END;
$$;
REVOKE ALL ON FUNCTION cancel_document(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION cancel_document(JSONB) TO authenticated;
