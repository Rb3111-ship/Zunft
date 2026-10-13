-- Hourly rate per person, for billing tracked working time. A meister is often billed at a higher
-- hourly rate than a geselle. A person without a rate uses the business's default rate.
--
-- Kept apart from profiles on purpose: colleagues can read each other's profiles, but a billing
-- rate is for the boss and the office only. Only the owner sets rates.

CREATE TABLE member_rates (
    user_id           UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
    business_id       UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    hourly_rate_cents INT NOT NULL CHECK (hourly_rate_cents BETWEEN 0 AND 100000),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_member_rates_business ON member_rates (business_id);
CREATE TRIGGER trg_member_rates_updated_at BEFORE UPDATE ON member_rates
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE member_rates ENABLE ROW LEVEL SECURITY;

-- Readable by the boss and the office. Written only through set_member_rate().
CREATE POLICY member_rates_select ON member_rates FOR SELECT TO authenticated
    USING (business_id = get_user_business_id() AND is_manager());

-- Sets (or, with NULL, removes) the hourly rate of a person of the business. Owner only.
CREATE OR REPLACE FUNCTION set_member_rate(p_user UUID, p_cents INT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_business UUID := get_user_business_id();
BEGIN
    IF auth.uid() IS NULL OR v_business IS NULL OR get_user_role() <> 'owner' THEN
        RAISE EXCEPTION 'not allowed';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_user AND business_id = v_business) THEN
        RAISE EXCEPTION 'person not found';
    END IF;
    IF p_cents IS NULL THEN
        DELETE FROM member_rates WHERE user_id = p_user;
    ELSE
        INSERT INTO member_rates (user_id, business_id, hourly_rate_cents)
        VALUES (p_user, v_business, p_cents)
        ON CONFLICT (user_id) DO UPDATE SET hourly_rate_cents = EXCLUDED.hourly_rate_cents;
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION set_member_rate(UUID, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION set_member_rate(UUID, INT) TO authenticated;
