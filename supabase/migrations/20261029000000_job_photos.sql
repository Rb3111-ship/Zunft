-- Photos on a job (before / after / other): proof of the state of the work. The picture file lives in
-- the private "captures" bucket under "<business>/<person>/photos/<id>.jpg" (so it counts against
-- the storage of the plan and is refused when that is full or the subscription has ended); this
-- table says which job it belongs to.
--
-- Who sees a photo: whoever can see the job (the boss and the office all of them, an employee only
-- those of the jobs they are assigned to). Who adds: the same people. Who removes: the boss, the
-- office, or the person who took it. Rows are written and removed only through the functions below.

CREATE TABLE job_photos (
    id           UUID PRIMARY KEY,
    business_id  UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    job_id       UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    kind         TEXT NOT NULL CHECK (kind IN ('before', 'after', 'other')),
    storage_path TEXT NOT NULL CHECK (char_length(storage_path) BETWEEN 10 AND 300),
    created_by   UUID REFERENCES profiles(id) ON DELETE SET NULL,
    created_by_name TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_job_photos_job ON job_photos (job_id, created_at);
CREATE INDEX idx_job_photos_business ON job_photos (business_id);

ALTER TABLE job_photos ENABLE ROW LEVEL SECURITY;

CREATE POLICY job_photos_select ON job_photos FOR SELECT TO authenticated
    USING (business_id = get_user_business_id() AND can_see_job(job_id));

-- No new photos for a business whose subscription has ended (see enforce_subscription()).
CREATE TRIGGER trg_job_photos_subscription BEFORE INSERT ON job_photos
    FOR EACH ROW EXECUTE FUNCTION enforce_subscription();

-- Stores the row of a photo the phone has uploaded. Repeating the call with the same id changes
-- nothing (the phone retries after a lost connection).
CREATE OR REPLACE FUNCTION add_job_photo(p_id UUID, p_job UUID, p_kind TEXT, p_path TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_business UUID := get_user_business_id();
    v_row job_photos;
BEGIN
    IF auth.uid() IS NULL OR v_business IS NULL THEN
        RAISE EXCEPTION 'not allowed';
    END IF;
    IF NOT can_see_job(p_job) THEN
        RAISE EXCEPTION 'job not found';
    END IF;
    IF p_kind NOT IN ('before', 'after', 'other') THEN
        RAISE EXCEPTION 'invalid kind';
    END IF;
    -- The file must be one this person uploaded for this business.
    IF p_path IS NULL OR p_path LIKE '%..%'
       OR p_path NOT LIKE v_business::TEXT || '/' || auth.uid()::TEXT || '/photos/%' THEN
        RAISE EXCEPTION 'invalid path';
    END IF;
    SELECT * INTO v_row FROM job_photos WHERE id = p_id;
    IF FOUND THEN
        IF v_row.business_id <> v_business THEN
            RAISE EXCEPTION 'not allowed';
        END IF;
        RETURN to_jsonb(v_row);
    END IF;
    INSERT INTO job_photos (id, business_id, job_id, kind, storage_path, created_by, created_by_name)
    VALUES (p_id, v_business, p_job, p_kind, p_path, auth.uid(),
            (SELECT full_name FROM profiles WHERE id = auth.uid()))
    RETURNING * INTO v_row;
    RETURN to_jsonb(v_row);
END;
$$;

-- Removes the row of a photo and returns the file's path, so the phone can delete the file too.
CREATE OR REPLACE FUNCTION delete_job_photo(p_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_row job_photos;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'not allowed';
    END IF;
    SELECT * INTO v_row FROM job_photos WHERE id = p_id AND business_id = get_user_business_id();
    IF NOT FOUND OR NOT (is_manager() OR v_row.created_by = auth.uid()) THEN
        RAISE EXCEPTION 'not allowed';
    END IF;
    DELETE FROM job_photos WHERE id = p_id;
    RETURN v_row.storage_path;
END;
$$;

REVOKE ALL ON FUNCTION add_job_photo(UUID, UUID, TEXT, TEXT), delete_job_photo(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION add_job_photo(UUID, UUID, TEXT, TEXT), delete_job_photo(UUID) TO authenticated;

-- The file itself may be removed by the boss, the office, and the person who uploaded it.
CREATE POLICY captures_photo_delete ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'captures'
           AND (storage.foldername(name))[1] = get_user_business_id()::TEXT
           AND (storage.foldername(name))[3] = 'photos'
           AND ((storage.foldername(name))[2] = auth.uid()::TEXT OR is_manager()));
