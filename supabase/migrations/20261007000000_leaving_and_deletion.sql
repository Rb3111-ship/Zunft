-- ==============================================================================
-- Migration: 20261007000000_leaving_and_deletion.sql
--
-- One business per account. A person's account belongs to THEM (their own e-mail), not to the
-- business, so the business can end the link but never the account:
--
--   remove_member()    the owner ends the link. The person keeps their account and can start
--                      their own business (e.g. go solo) or join another one.
--   leave_business()   the same, started by the person.
--   delete_my_account()  erasure of the account itself (required by the app stores and the GDPR).
--
-- Notes the person recorded stay with the job (the business needs its work records), but they no
-- longer point to a live profile, so the author's name is kept as text on the note itself.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. The author's name travels with the note
-- ------------------------------------------------------------------------------
ALTER TABLE capture_logs ADD COLUMN created_by_name TEXT;

UPDATE capture_logs c SET created_by_name = p.full_name
  FROM profiles p WHERE p.id = c.created_by AND c.created_by_name IS NULL;

CREATE OR REPLACE FUNCTION set_note_author_name()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.created_by IS NOT NULL AND NEW.created_by_name IS NULL THEN
        SELECT full_name INTO NEW.created_by_name FROM profiles WHERE id = NEW.created_by;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_capture_logs_author_name BEFORE INSERT ON capture_logs
    FOR EACH ROW EXECUTE FUNCTION set_note_author_name();

COMMENT ON COLUMN capture_logs.created_by_name IS 'Author name at the time of recording; stays when the person leaves';

-- ------------------------------------------------------------------------------
-- 2. Ending the link
-- ------------------------------------------------------------------------------
-- Deleting the profile row ends everything at once: no business id, no role, job assignments go
-- with it (cascade). Their notes, customers and invitations stay (the foreign keys just let go).
CREATE OR REPLACE FUNCTION remove_member(p_user UUID)
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
        RAISE EXCEPTION 'the owner cannot be removed';
    END IF;
    DELETE FROM profiles WHERE id = p_user;
END;
$$;

CREATE OR REPLACE FUNCTION leave_business()
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_role TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'not authenticated';
    END IF;
    SELECT role INTO v_role FROM profiles WHERE id = auth.uid();
    IF NOT FOUND THEN
        RAISE EXCEPTION 'not a member of a business';
    END IF;
    IF v_role = 'owner' THEN
        RAISE EXCEPTION 'the owner cannot leave';
    END IF;
    DELETE FROM profiles WHERE id = auth.uid();
END;
$$;

-- ------------------------------------------------------------------------------
-- 3. Deleting the account itself
-- ------------------------------------------------------------------------------
-- Employees (and people who registered but never joined a business) can erase their account.
-- An OWNER cannot do it from the app: the business's invoices must be kept for years by law
-- (GoBD), so closing a business is a deliberate, supported step, not a button.
CREATE OR REPLACE FUNCTION delete_my_account()
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_role TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'not authenticated';
    END IF;
    SELECT role INTO v_role FROM profiles WHERE id = auth.uid();
    IF v_role = 'owner' THEN
        RAISE EXCEPTION 'the owner cannot delete the account';
    END IF;
    DELETE FROM profiles WHERE id = auth.uid();
    DELETE FROM auth.users WHERE id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION set_note_author_name(), remove_member(UUID), leave_business(), delete_my_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION remove_member(UUID), leave_business(), delete_my_account() TO authenticated;
