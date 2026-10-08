-- Setting of the business: may employees (Meister, Geselle) create their own customers and jobs?
-- Off by default. Only the owner can change it. Boss and office can always create both.
ALTER TABLE businesses ADD COLUMN employees_can_create BOOLEAN NOT NULL DEFAULT FALSE;
COMMENT ON COLUMN businesses.employees_can_create IS
    'If true, Meister and Geselle may create customers and jobs. Managers always may. Changed by the owner only.';

CREATE OR REPLACE FUNCTION guard_business_plan()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.seat_limit IS DISTINCT FROM OLD.seat_limit AND current_user = 'authenticated' THEN
        RAISE EXCEPTION 'the plan cannot be changed from the app';
    END IF;
    IF NEW.employees_can_create IS DISTINCT FROM OLD.employees_can_create
       AND current_user = 'authenticated' AND get_user_role() <> 'owner' THEN
        RAISE EXCEPTION 'not allowed: only the owner can change this';
    END IF;
    RETURN NEW;
END;
$$;

-- Can the caller create customers and jobs?
CREATE OR REPLACE FUNCTION can_create_records()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT is_manager() OR COALESCE(
        (SELECT employees_can_create FROM businesses WHERE id = get_user_business_id()), FALSE);
$$;
REVOKE ALL ON FUNCTION can_create_records() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION can_create_records() TO authenticated;

DROP POLICY customers_insert ON customers;
CREATE POLICY customers_insert ON customers FOR INSERT TO authenticated
    WITH CHECK (business_id = get_user_business_id() AND can_create_records());

DROP POLICY jobs_insert ON jobs;
CREATE POLICY jobs_insert ON jobs FOR INSERT TO authenticated
    WITH CHECK (
        business_id = get_user_business_id()
        AND can_create_records()
        AND (customer_id IS NULL OR EXISTS (
            SELECT 1 FROM customers c WHERE c.id = customer_id AND c.business_id = jobs.business_id))
    );
