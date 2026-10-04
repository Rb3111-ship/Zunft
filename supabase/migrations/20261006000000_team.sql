-- ==============================================================================
-- Migration: 20261006000000_team.sql
--
-- Teams: one kind of account, a business with a seat limit, and roles.
--
--   owner, buero  = "managers": see everything, assign jobs, issue documents.
--                   (Only the owner invites people and manages the team.)
--   meister, geselle = employees: see only the jobs assigned to them (and the customers of those
--                   jobs), record notes. They cannot see or issue invoices.
--   A self-employed person is simply an owner with one seat.
--
-- All of this is enforced here, in the database (row level security), not just hidden in screens.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Columns
-- ------------------------------------------------------------------------------
ALTER TABLE profiles   ADD COLUMN active BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE businesses ADD COLUMN seat_limit INT NOT NULL DEFAULT 1 CHECK (seat_limit BETWEEN 1 AND 10000);
ALTER TABLE customers  ADD COLUMN created_by UUID REFERENCES profiles(id) ON DELETE SET NULL;

COMMENT ON COLUMN profiles.active IS 'FALSE = access switched off (e.g. the employee left). Their notes stay.';
COMMENT ON COLUMN businesses.seat_limit IS 'How many active people the plan allows. Changed by us (billing), never by clients.';

-- ------------------------------------------------------------------------------
-- 2. Helpers. An inactive person has no business and no role: every policy then says no.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_user_business_id()
RETURNS UUID
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public, pg_temp
AS $$
    SELECT business_id FROM profiles WHERE id = auth.uid() AND active LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION get_user_role()
RETURNS TEXT
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public, pg_temp
AS $$
    SELECT role FROM profiles WHERE id = auth.uid() AND active LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION is_manager()
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(get_user_role() IN ('owner', 'buero'), FALSE);
$$;

-- ------------------------------------------------------------------------------
-- 3. Job assignments
-- ------------------------------------------------------------------------------
CREATE TABLE job_assignments (
    job_id      UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    assigned_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
    PRIMARY KEY (job_id, user_id)
);
CREATE INDEX idx_job_assignments_user ON job_assignments (user_id);
ALTER TABLE job_assignments ENABLE ROW LEVEL SECURITY;

-- Managers see all assignments of their business, everyone else only their own.
-- Nobody writes directly: set_job_assignees() and the job-creation trigger do it.
CREATE POLICY job_assignments_select ON job_assignments FOR SELECT TO authenticated
    USING (business_id = get_user_business_id() AND (is_manager() OR user_id = auth.uid()));

CREATE OR REPLACE FUNCTION can_see_job(p_job UUID)
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM jobs j
        WHERE j.id = p_job
          AND j.business_id = get_user_business_id()
          AND (is_manager() OR EXISTS (
                SELECT 1 FROM job_assignments a WHERE a.job_id = j.id AND a.user_id = auth.uid()))
    );
$$;

-- An employee who creates a job in the field sees it (is assigned to it) right away.
CREATE OR REPLACE FUNCTION assign_creator_to_job()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NOT NULL AND EXISTS (
        SELECT 1 FROM profiles WHERE id = auth.uid() AND business_id = NEW.business_id AND active) THEN
        INSERT INTO job_assignments (job_id, user_id, business_id, assigned_by)
        VALUES (NEW.id, auth.uid(), NEW.business_id, auth.uid())
        ON CONFLICT DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_jobs_assign_creator AFTER INSERT ON jobs FOR EACH ROW EXECUTE FUNCTION assign_creator_to_job();

CREATE OR REPLACE FUNCTION set_created_by()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.created_by IS NULL THEN NEW.created_by := auth.uid(); END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_customers_created_by BEFORE INSERT ON customers FOR EACH ROW EXECUTE FUNCTION set_created_by();

-- ------------------------------------------------------------------------------
-- 4. Visibility policies
-- ------------------------------------------------------------------------------
-- profiles: always see your own row (so a switched-off person can be told why), plus colleagues.
DROP POLICY profiles_select ON profiles;
CREATE POLICY profiles_select ON profiles FOR SELECT TO authenticated
    USING (id = auth.uid() OR business_id = get_user_business_id());

-- jobs
DROP POLICY jobs_select ON jobs;
DROP POLICY jobs_update ON jobs;
DROP POLICY jobs_delete ON jobs;
CREATE POLICY jobs_select ON jobs FOR SELECT TO authenticated
    USING (business_id = get_user_business_id() AND can_see_job(id));
CREATE POLICY jobs_update ON jobs FOR UPDATE TO authenticated
    USING (business_id = get_user_business_id() AND can_see_job(id))
    WITH CHECK (
        business_id = get_user_business_id()
        AND (customer_id IS NULL OR EXISTS (
            SELECT 1 FROM customers c WHERE c.id = customer_id AND c.business_id = jobs.business_id))
    );
CREATE POLICY jobs_delete ON jobs FOR DELETE TO authenticated
    USING (business_id = get_user_business_id() AND can_see_job(id) AND get_user_role() IN ('owner', 'meister', 'buero'));

-- customers: managers see all; an employee sees the customers of the jobs they can see, and the
-- ones they created themselves.
DROP POLICY customers_select ON customers;
DROP POLICY customers_update ON customers;
DROP POLICY customers_delete ON customers;
CREATE POLICY customers_select ON customers FOR SELECT TO authenticated
    USING (
        business_id = get_user_business_id()
        AND (is_manager() OR created_by = auth.uid()
             OR EXISTS (SELECT 1 FROM jobs j WHERE j.customer_id = customers.id))  -- jobs: already filtered by RLS
    );
CREATE POLICY customers_update ON customers FOR UPDATE TO authenticated
    USING (
        business_id = get_user_business_id()
        AND (is_manager() OR created_by = auth.uid()
             OR EXISTS (SELECT 1 FROM jobs j WHERE j.customer_id = customers.id))
    )
    WITH CHECK (business_id = get_user_business_id());
CREATE POLICY customers_delete ON customers FOR DELETE TO authenticated
    USING (business_id = get_user_business_id() AND is_manager());

-- capture_logs (the notes): visible with the job. Written only for jobs the writer can see.
DROP POLICY capture_logs_select ON capture_logs;
DROP POLICY capture_logs_insert ON capture_logs;
CREATE POLICY capture_logs_select ON capture_logs FOR SELECT TO authenticated
    USING (
        business_id = get_user_business_id()
        AND ((job_id IS NULL AND is_manager()) OR (job_id IS NOT NULL AND can_see_job(job_id)))
    );
CREATE POLICY capture_logs_insert ON capture_logs FOR INSERT TO authenticated
    WITH CHECK (
        business_id = get_user_business_id()
        AND (created_by IS NULL OR created_by = auth.uid())
        AND document_id IS NULL
        AND discarded_at IS NULL
        AND (job_id IS NULL OR can_see_job(job_id))
    );

CREATE OR REPLACE FUNCTION discard_capture_log(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL OR get_user_business_id() IS NULL THEN
        RAISE EXCEPTION 'not allowed';
    END IF;
    UPDATE capture_logs
       SET discarded_at = NOW()
     WHERE id = p_id
       AND business_id = get_user_business_id()
       AND (job_id IS NULL OR can_see_job(job_id))
       AND document_id IS NULL
       AND discarded_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'note not found or already invoiced';
    END IF;
END;
$$;

-- documents: boss and office only.
DROP POLICY documents_select ON documents;
DROP POLICY documents_update ON documents;
DROP POLICY documents_delete ON documents;
CREATE POLICY documents_select ON documents FOR SELECT TO authenticated
    USING (business_id = get_user_business_id() AND is_manager());
CREATE POLICY documents_update ON documents FOR UPDATE TO authenticated
    USING (business_id = get_user_business_id() AND is_manager())
    WITH CHECK (business_id = get_user_business_id() AND is_manager());
CREATE POLICY documents_delete ON documents FOR DELETE TO authenticated
    USING (business_id = get_user_business_id() AND is_manager() AND status = 'draft' AND NOT is_gobd_locked);

-- storage: PDFs for managers only; recordings readable by the person who made them and by managers.
DROP POLICY documents_files_select ON storage.objects;
DROP POLICY documents_files_insert ON storage.objects;
DROP POLICY documents_files_update ON storage.objects;
DROP POLICY captures_select ON storage.objects;
CREATE POLICY documents_files_select ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'documents' AND is_manager() AND (storage.foldername(name))[1] = get_user_business_id()::TEXT);
CREATE POLICY documents_files_insert ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'documents' AND is_manager() AND (storage.foldername(name))[1] = get_user_business_id()::TEXT);
CREATE POLICY documents_files_update ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'documents' AND is_manager() AND (storage.foldername(name))[1] = get_user_business_id()::TEXT)
    WITH CHECK (bucket_id = 'documents' AND is_manager() AND (storage.foldername(name))[1] = get_user_business_id()::TEXT);
CREATE POLICY captures_select ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'captures' AND (storage.foldername(name))[1] = get_user_business_id()::TEXT
           AND (is_manager() OR owner = auth.uid()));

-- ------------------------------------------------------------------------------
-- 5. Guards: clients cannot change the plan or switch people on/off directly
-- ------------------------------------------------------------------------------
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
    IF NEW.active IS DISTINCT FROM OLD.active AND current_user = 'authenticated' THEN
        RAISE EXCEPTION 'use set_member_active() to switch a person on or off';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION guard_business_plan()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.seat_limit IS DISTINCT FROM OLD.seat_limit AND current_user = 'authenticated' THEN
        RAISE EXCEPTION 'the plan cannot be changed from the app';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_businesses_plan_guard BEFORE UPDATE ON businesses FOR EACH ROW EXECUTE FUNCTION guard_business_plan();

-- ------------------------------------------------------------------------------
-- 6. Invitations
-- ------------------------------------------------------------------------------
CREATE TABLE invites (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    code        TEXT NOT NULL UNIQUE,
    role        TEXT NOT NULL CHECK (role IN ('buero', 'meister', 'geselle')),
    created_by  UUID REFERENCES profiles(id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at  TIMESTAMPTZ NOT NULL,
    used_by     UUID REFERENCES profiles(id) ON DELETE SET NULL,
    used_at     TIMESTAMPTZ,
    revoked_at  TIMESTAMPTZ
);
CREATE INDEX idx_invites_business ON invites (business_id);
ALTER TABLE invites ENABLE ROW LEVEL SECURITY;
CREATE POLICY invites_select ON invites FOR SELECT TO authenticated
    USING (business_id = get_user_business_id() AND get_user_role() = 'owner');

-- Seats in use: active people plus invitations that are still open.
CREATE OR REPLACE FUNCTION seats_in_use(p_business UUID)
RETURNS INT
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public, pg_temp
AS $$
    SELECT (SELECT COUNT(*) FROM profiles WHERE business_id = p_business AND active)::INT
         + (SELECT COUNT(*) FROM invites
             WHERE business_id = p_business AND used_at IS NULL AND revoked_at IS NULL AND expires_at > NOW())::INT;
$$;

-- A short code without look-alike characters (no 0/O, 1/I): easy to read out or type.
CREATE OR REPLACE FUNCTION new_invite_code()
RETURNS TEXT
LANGUAGE plpgsql VOLATILE
SET search_path = public, pg_temp
AS $$
DECLARE
    alphabet CONSTANT TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    raw TEXT := replace(gen_random_uuid()::TEXT, '-', '');
    result TEXT := '';
BEGIN
    FOR i IN 0..7 LOOP
        result := result || substr(alphabet, (get_byte(decode(substr(raw, i * 2 + 1, 2), 'hex'), 0) % 32) + 1, 1);
    END LOOP;
    RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION create_invite(p_role TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_business UUID := get_user_business_id();
    v_limit    INT;
    v_code     TEXT;
    v_expires  TIMESTAMPTZ := NOW() + INTERVAL '7 days';
    v_id       UUID;
BEGIN
    IF auth.uid() IS NULL OR v_business IS NULL OR get_user_role() <> 'owner' THEN
        RAISE EXCEPTION 'not allowed';
    END IF;
    IF COALESCE(p_role, '') NOT IN ('buero', 'meister', 'geselle') THEN
        RAISE EXCEPTION 'invalid role';
    END IF;
    SELECT seat_limit INTO v_limit FROM businesses WHERE id = v_business FOR UPDATE; -- serialize concurrent invites
    IF seats_in_use(v_business) >= v_limit THEN
        RAISE EXCEPTION 'no free seat';
    END IF;
    LOOP
        v_code := new_invite_code();
        EXIT WHEN NOT EXISTS (SELECT 1 FROM invites WHERE code = v_code);
    END LOOP;
    INSERT INTO invites (business_id, code, role, created_by, expires_at)
    VALUES (v_business, v_code, p_role, auth.uid(), v_expires)
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('id', v_id, 'code', v_code, 'role', p_role, 'expires_at', v_expires);
END;
$$;

CREATE OR REPLACE FUNCTION revoke_invite(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL OR get_user_role() <> 'owner' THEN
        RAISE EXCEPTION 'not allowed';
    END IF;
    UPDATE invites SET revoked_at = NOW()
     WHERE id = p_id AND business_id = get_user_business_id() AND used_at IS NULL AND revoked_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'invitation not found';
    END IF;
END;
$$;

-- Called by a freshly registered person (who has no business yet) with the code from the boss.
CREATE OR REPLACE FUNCTION join_business(p_code TEXT, p_full_name TEXT)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_invite invites%ROWTYPE;
    v_limit  INT;
    v_active INT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'not authenticated';
    END IF;
    IF EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
        RAISE EXCEPTION 'user already belongs to a business';
    END IF;
    IF COALESCE(TRIM(p_full_name), '') = '' THEN
        RAISE EXCEPTION 'name is required';
    END IF;

    SELECT * INTO v_invite FROM invites WHERE code = UPPER(TRIM(COALESCE(p_code, ''))) FOR UPDATE;
    -- One message for every failure, so codes cannot be probed.
    IF NOT FOUND OR v_invite.used_at IS NOT NULL OR v_invite.revoked_at IS NOT NULL OR v_invite.expires_at <= NOW() THEN
        RAISE EXCEPTION 'invalid invitation';
    END IF;

    SELECT seat_limit INTO v_limit FROM businesses WHERE id = v_invite.business_id FOR UPDATE;
    SELECT COUNT(*) INTO v_active FROM profiles WHERE business_id = v_invite.business_id AND active;
    IF v_active >= v_limit THEN
        RAISE EXCEPTION 'no free seat';
    END IF;

    INSERT INTO profiles (id, business_id, full_name, role)
    VALUES (auth.uid(), v_invite.business_id, TRIM(p_full_name), v_invite.role);
    UPDATE invites SET used_by = auth.uid(), used_at = NOW() WHERE id = v_invite.id;
    RETURN v_invite.business_id;
END;
$$;

CREATE OR REPLACE FUNCTION set_member_active(p_user UUID, p_active BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_business UUID := get_user_business_id();
    v_target   profiles%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL OR v_business IS NULL OR get_user_role() <> 'owner' THEN
        RAISE EXCEPTION 'not allowed';
    END IF;
    SELECT * INTO v_target FROM profiles WHERE id = p_user AND business_id = v_business;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'person not found';
    END IF;
    IF v_target.id = auth.uid() OR v_target.role = 'owner' THEN
        RAISE EXCEPTION 'the owner cannot be switched off';
    END IF;
    IF p_active AND NOT v_target.active THEN
        PERFORM 1 FROM businesses WHERE id = v_business FOR UPDATE;
        IF seats_in_use(v_business) >= (SELECT seat_limit FROM businesses WHERE id = v_business) THEN
            RAISE EXCEPTION 'no free seat';
        END IF;
    END IF;
    UPDATE profiles SET active = p_active WHERE id = p_user;
END;
$$;

-- ------------------------------------------------------------------------------
-- 7. Assigning jobs (managers only). Replaces the whole list of people on a job.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_job_assignees(p_job UUID, p_users UUID[])
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_business UUID := get_user_business_id();
    v_customer UUID;
BEGIN
    IF auth.uid() IS NULL OR v_business IS NULL OR NOT is_manager() THEN
        RAISE EXCEPTION 'not allowed';
    END IF;
    SELECT customer_id INTO v_customer FROM jobs WHERE id = p_job AND business_id = v_business;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'job not found';
    END IF;
    IF EXISTS (
        SELECT 1 FROM unnest(COALESCE(p_users, ARRAY[]::UUID[])) u
        WHERE NOT EXISTS (SELECT 1 FROM profiles WHERE id = u AND business_id = v_business AND active)) THEN
        RAISE EXCEPTION 'person not found';
    END IF;

    DELETE FROM job_assignments WHERE job_id = p_job AND NOT (user_id = ANY (COALESCE(p_users, ARRAY[]::UUID[])));
    INSERT INTO job_assignments (job_id, user_id, business_id, assigned_by)
    SELECT p_job, u, v_business, auth.uid() FROM unnest(COALESCE(p_users, ARRAY[]::UUID[])) u
    ON CONFLICT DO NOTHING;

    -- Phones fetch changes by "updated since": touch the job and its customer so the newly
    -- assigned person's phone picks them up even though they were last edited long ago.
    UPDATE jobs SET updated_at = NOW() WHERE id = p_job;
    IF v_customer IS NOT NULL THEN
        UPDATE customers SET updated_at = NOW() WHERE id = v_customer;
    END IF;
END;
$$;

-- ------------------------------------------------------------------------------
-- 8. Function privileges
-- ------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION is_manager(), can_see_job(UUID), seats_in_use(UUID), new_invite_code(),
    create_invite(TEXT), revoke_invite(UUID), join_business(TEXT, TEXT), set_member_active(UUID, BOOLEAN),
    set_job_assignees(UUID, UUID[]), discard_capture_log(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION is_manager(), can_see_job(UUID), create_invite(TEXT), revoke_invite(UUID),
    join_business(TEXT, TEXT), set_member_active(UUID, BOOLEAN), set_job_assignees(UUID, UUID[]),
    discard_capture_log(UUID) TO authenticated;

-- ------------------------------------------------------------------------------
-- 9. create_document: managers only
-- ------------------------------------------------------------------------------
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

    RETURN to_jsonb(v_row);
END;
$$;
