-- Leitweg-ID: the routing address of a public-sector customer (Behörde, Kommune, public body). It is
-- the "buyer reference" of an XRechnung, the invoice format the public sector asks for.
--
-- The customer holds it; an issued document freezes it (and the buyer's e-mail) in its
-- recipient_snapshot like the name and address, so an XRechnung can be made from the stored
-- document later. Format: 2-12 digits, optional "-" and up to 30 letters or digits, "-" and 2 check
-- digits (the check digits themselves are not verified here).

ALTER TABLE customers ADD COLUMN leitweg_id TEXT
    CHECK (leitweg_id IS NULL OR leitweg_id ~ '^[0-9]{2,12}(-[0-9A-Za-z]{1,30})?-[0-9]{2}$');

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
        'address', NULLIF(LEFT(TRIM(COALESCE(v_recipient->>'address', '')), 200), ''),
        -- the Leitweg-ID of a public-sector customer (the buyer reference of an XRechnung) and the
        -- buyer's e-mail address, frozen with the document like the name and address
        'buyer_reference', NULLIF(LEFT(TRIM(COALESCE(v_recipient->>'buyer_reference', '')), 46), ''),
        'email', NULLIF(LEFT(TRIM(COALESCE(v_recipient->>'email', '')), 120), '')
    );
    IF v_recipient->>'buyer_reference' IS NOT NULL
       AND v_recipient->>'buyer_reference' !~ '^[0-9]{2,12}(-[0-9A-Za-z]{1,30})?-[0-9]{2}$' THEN
        RAISE EXCEPTION 'invalid buyer reference (Leitweg-ID)';
    END IF;

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
