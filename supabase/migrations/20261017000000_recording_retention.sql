-- Recording retention: the audio of a voice note is only raw material. The note text and the
-- positions stay (they are the basis of the invoice); the audio file is deleted a number of days
-- after the job is closed (invoiced or completed). The business may SHORTEN the period, never
-- lengthen it (CHECK <= 90). A daily job calls the Edge Function `purge-recordings`.

-- 1. When was a job closed? (exact time, not updated_at, which changes with every edit)
ALTER TABLE jobs ADD COLUMN closed_at TIMESTAMPTZ;
UPDATE jobs SET closed_at = updated_at WHERE status IN ('completed', 'invoiced');

CREATE OR REPLACE FUNCTION set_job_closed_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.status IN ('completed', 'invoiced') THEN
        IF TG_OP = 'INSERT' OR OLD.status NOT IN ('completed', 'invoiced') OR NEW.closed_at IS NULL THEN
            NEW.closed_at := NOW();
        ELSE
            NEW.closed_at := OLD.closed_at; -- completed -> invoiced keeps the first closing time
        END IF;
    ELSE
        NEW.closed_at := NULL;              -- reopened
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_jobs_closed_at BEFORE INSERT OR UPDATE OF status ON jobs
    FOR EACH ROW EXECUTE FUNCTION set_job_closed_at();

-- 2. Per business setting and the mark on the note
ALTER TABLE businesses ADD COLUMN recording_retention_days INT NOT NULL DEFAULT 90
    CHECK (recording_retention_days BETWEEN 7 AND 90);
COMMENT ON COLUMN businesses.recording_retention_days IS 'Days after the job is closed until the audio is deleted. The business may shorten it, never go above 90.';

ALTER TABLE capture_logs ADD COLUMN audio_deleted_at TIMESTAMPTZ;

-- 3. What is due (used by the Edge Function with the service role only)
CREATE OR REPLACE FUNCTION recordings_due_for_deletion(p_limit INT DEFAULT 200)
RETURNS TABLE (id UUID, audio_storage_path TEXT)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT c.id, c.audio_storage_path
      FROM capture_logs c
      JOIN jobs j ON j.id = c.job_id
      JOIN businesses b ON b.id = c.business_id
     WHERE c.audio_storage_path IS NOT NULL
       AND c.audio_deleted_at IS NULL
       AND j.closed_at IS NOT NULL
       AND j.closed_at < NOW() - make_interval(days => b.recording_retention_days)
     ORDER BY j.closed_at
     LIMIT p_limit;
$$;
REVOKE ALL ON FUNCTION recordings_due_for_deletion(INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION recordings_due_for_deletion(INT) TO service_role;

CREATE OR REPLACE FUNCTION mark_recordings_deleted(p_ids UUID[])
RETURNS VOID
LANGUAGE sql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    UPDATE capture_logs SET audio_deleted_at = NOW() WHERE id = ANY(p_ids) AND audio_deleted_at IS NULL;
$$;
REVOKE ALL ON FUNCTION mark_recordings_deleted(UUID[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mark_recordings_deleted(UUID[]) TO service_role;

REVOKE ALL ON FUNCTION set_job_closed_at() FROM PUBLIC, anon, authenticated;
