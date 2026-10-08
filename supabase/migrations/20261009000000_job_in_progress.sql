-- A job moves from "Entwurf" to "In Arbeit" by itself when its first note arrives, so nobody has
-- to maintain the status by hand.
CREATE OR REPLACE FUNCTION mark_job_in_progress() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NEW.job_id IS NOT NULL THEN
        UPDATE jobs SET status = 'in_progress' WHERE id = NEW.job_id AND status = 'draft';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION mark_job_in_progress() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_capture_logs_job_in_progress AFTER INSERT ON capture_logs
    FOR EACH ROW EXECUTE FUNCTION mark_job_in_progress();
