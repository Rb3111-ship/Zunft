-- Push message to the boss and the office when somebody adds a photo to a job, so the boss can
-- look at the work without opening every job. Uses the same Edge Function and phone list as the
-- appointment messages (20261023).
--
-- * Told: owner and buero of the business, never the person who took the photo.
-- * Not spammy: a person who takes ten photos in a row sends one message. A photo within 5 minutes
--   of an earlier photo by the same person on the same job sends nothing.
-- * A failure to notify never blocks saving the photo.

CREATE OR REPLACE FUNCTION send_photo_push(p_photo job_photos)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_secret TEXT;
    v_users  UUID[];
    v_title  TEXT;
BEGIN
    IF to_regnamespace('net') IS NULL OR to_regnamespace('vault') IS NULL THEN
        RETURN; -- not available here (tests)
    END IF;
    IF p_photo.created_by IS NOT NULL AND EXISTS (
        SELECT 1 FROM job_photos o
        WHERE o.job_id = p_photo.job_id AND o.created_by = p_photo.created_by AND o.id <> p_photo.id
          AND o.created_at > p_photo.created_at - interval '5 minutes' AND o.created_at <= p_photo.created_at
    ) THEN
        RETURN; -- the boss was just told about this person's photos on this job
    END IF;
    SELECT COALESCE(array_agg(id), '{}') INTO v_users FROM profiles
    WHERE business_id = p_photo.business_id AND role IN ('owner', 'buero')
      AND id IS DISTINCT FROM p_photo.created_by;
    IF cardinality(v_users) = 0 THEN
        RETURN;
    END IF;
    SELECT title INTO v_title FROM jobs WHERE id = p_photo.job_id;
    EXECUTE 'SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = ''notify_secret''' INTO v_secret;
    IF v_secret IS NULL THEN
        RETURN;
    END IF;
    PERFORM net.http_post(
        url := 'https://wwssjssjxurycxcshgey.supabase.co/functions/v1/notify-appointment',
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-notify-secret', v_secret),
        body := jsonb_build_object(
            'event', 'photo',
            'user_ids', to_jsonb(v_users),
            'photo', jsonb_build_object(
                'job_id', p_photo.job_id, 'job_title', COALESCE(v_title, ''),
                'author', COALESCE(p_photo.created_by_name, ''), 'kind', p_photo.kind))
    );
END;
$$;

CREATE OR REPLACE FUNCTION notify_photo_added()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    BEGIN
        PERFORM send_photo_push(NEW);
    EXCEPTION WHEN OTHERS THEN
        NULL; -- telling the boss is a convenience: saving the photo always wins
    END;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_job_photos_push AFTER INSERT ON job_photos
    FOR EACH ROW EXECUTE FUNCTION notify_photo_added();

REVOKE ALL ON FUNCTION send_photo_push(job_photos), notify_photo_added() FROM PUBLIC, anon, authenticated;
