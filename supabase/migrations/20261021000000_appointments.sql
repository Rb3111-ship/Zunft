-- Appointments (Termine): the calendar of the business. An appointment may belong to a job and a
-- customer, is assigned to one or more people, and has a start and an end. Absences (Urlaub, krank)
-- are appointments of kind 'absence'.
--
-- Who sees what: the boss and the office see every appointment of the business. An employee sees
-- the ones assigned to them (or created by them). Managers create and change appointments;
-- employees may create their own (if the owner allowed employees to create records) and may mark
-- an appointment assigned to them as done through set_appointment_status().

CREATE TABLE appointments (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id  UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    job_id       UUID REFERENCES jobs(id) ON DELETE SET NULL,
    customer_id  UUID REFERENCES customers(id) ON DELETE SET NULL,
    kind         TEXT NOT NULL DEFAULT 'job' CHECK (kind IN ('job', 'absence', 'other')),
    title        TEXT NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 200),
    location     TEXT CHECK (location IS NULL OR char_length(location) <= 300),
    notes        TEXT CHECK (notes IS NULL OR char_length(notes) <= 2000),
    starts_at    TIMESTAMPTZ NOT NULL,
    ends_at      TIMESTAMPTZ NOT NULL,
    status       TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned', 'done', 'canceled')),
    assignee_ids UUID[] NOT NULL DEFAULT '{}' CHECK (cardinality(assignee_ids) <= 20),
    created_by   UUID REFERENCES profiles(id) ON DELETE SET NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (ends_at > starts_at),
    CHECK (ends_at - starts_at <= INTERVAL '31 days')
);
CREATE INDEX idx_appointments_business_start ON appointments (business_id, starts_at);
CREATE INDEX idx_appointments_assignees ON appointments USING GIN (assignee_ids);
CREATE INDEX idx_appointments_job ON appointments (job_id) WHERE job_id IS NOT NULL;

CREATE TRIGGER trg_appointments_updated_at BEFORE UPDATE ON appointments
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_appointments_created_by BEFORE INSERT ON appointments
    FOR EACH ROW EXECUTE FUNCTION set_created_by();

-- The people on an appointment must be active members of the same business, and a job or customer
-- must belong to it too. (A policy cannot check array elements as readably as a trigger can.)
CREATE OR REPLACE FUNCTION check_appointment()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM unnest(NEW.assignee_ids) u
        WHERE NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = u AND p.business_id = NEW.business_id AND p.active)) THEN
        RAISE EXCEPTION 'person not found';
    END IF;
    IF NEW.job_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM jobs j WHERE j.id = NEW.job_id AND j.business_id = NEW.business_id) THEN
        RAISE EXCEPTION 'job not found';
    END IF;
    IF NEW.customer_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM customers c WHERE c.id = NEW.customer_id AND c.business_id = NEW.business_id) THEN
        RAISE EXCEPTION 'customer not found';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_appointments_check BEFORE INSERT OR UPDATE ON appointments
    FOR EACH ROW EXECUTE FUNCTION check_appointment();

-- Someone who is given an appointment for a job must be able to open that job: assign them to it
-- and touch the job and customer so their phone picks them up ("updated since" sync).
CREATE OR REPLACE FUNCTION appointment_assign_job()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_customer UUID;
BEGIN
    IF NEW.job_id IS NULL OR cardinality(NEW.assignee_ids) = 0 THEN
        RETURN NEW;
    END IF;
    INSERT INTO job_assignments (job_id, user_id, business_id, assigned_by)
    SELECT NEW.job_id, u, NEW.business_id, auth.uid() FROM unnest(NEW.assignee_ids) u
    ON CONFLICT DO NOTHING;
    UPDATE jobs SET updated_at = NOW() WHERE id = NEW.job_id RETURNING customer_id INTO v_customer;
    IF v_customer IS NOT NULL THEN
        UPDATE customers SET updated_at = NOW() WHERE id = v_customer;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_appointments_assign_job AFTER INSERT OR UPDATE OF assignee_ids, job_id ON appointments
    FOR EACH ROW EXECUTE FUNCTION appointment_assign_job();

ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;

CREATE POLICY appointments_select ON appointments FOR SELECT TO authenticated
    USING (business_id = get_user_business_id()
           AND (is_manager() OR auth.uid() = ANY (assignee_ids) OR created_by = auth.uid()));

CREATE POLICY appointments_insert ON appointments FOR INSERT TO authenticated
    WITH CHECK (business_id = get_user_business_id()
                AND (is_manager()
                     OR (can_create_records() AND assignee_ids <@ ARRAY[auth.uid()])));

CREATE POLICY appointments_update ON appointments FOR UPDATE TO authenticated
    USING (business_id = get_user_business_id()
           AND (is_manager() OR (created_by = auth.uid() AND assignee_ids <@ ARRAY[auth.uid()])))
    WITH CHECK (business_id = get_user_business_id()
                AND (is_manager() OR assignee_ids <@ ARRAY[auth.uid()]));

CREATE POLICY appointments_delete ON appointments FOR DELETE TO authenticated
    USING (business_id = get_user_business_id()
           AND (is_manager() OR (created_by = auth.uid() AND assignee_ids <@ ARRAY[auth.uid()])));

-- An employee marks an appointment assigned to them as done (or back to planned): nothing else.
CREATE OR REPLACE FUNCTION set_appointment_status(p_id UUID, p_status TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_business UUID := get_user_business_id();
BEGIN
    IF auth.uid() IS NULL OR v_business IS NULL THEN
        RAISE EXCEPTION 'not allowed';
    END IF;
    IF p_status NOT IN ('planned', 'done', 'canceled') THEN
        RAISE EXCEPTION 'invalid status';
    END IF;
    IF p_status = 'canceled' AND NOT is_manager() THEN
        RAISE EXCEPTION 'not allowed';
    END IF;
    UPDATE appointments SET status = p_status
     WHERE id = p_id AND business_id = v_business
       AND (is_manager() OR auth.uid() = ANY (assignee_ids));
    IF NOT FOUND THEN
        RAISE EXCEPTION 'appointment not found';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION set_appointment_status(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION set_appointment_status(UUID, TEXT) TO authenticated;
REVOKE ALL ON FUNCTION check_appointment(), appointment_assign_job() FROM PUBLIC, anon, authenticated;
