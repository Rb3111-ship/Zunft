-- Job photo files whose row is gone (the job was deleted, the photo was removed while the phone was
-- offline, a phone gave up halfway): they still count against the storage of the business, so the
-- daily purge job removes them. A row is the proof that a file belongs somewhere; a file in the
-- photos folder without a row for more than 7 days is an orphan (7 days, because a phone without
-- signal can upload the file and send the row much later).
--
-- A photo has a second, small file next to it: "<id>.jpg" and "<id>_t.jpg" (the thumbnail).

CREATE OR REPLACE FUNCTION orphan_photo_files(p_limit INT DEFAULT 200)
RETURNS TABLE (name TEXT)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, storage, pg_temp
AS $$
    SELECT o.name
      FROM storage.objects o
     WHERE o.bucket_id = 'captures'
       AND o.name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/photos/[0-9a-f-]{36}(_t)?\.jpg$'
       AND o.created_at < NOW() - INTERVAL '7 days'
       AND NOT EXISTS (
           SELECT 1 FROM job_photos p
            WHERE p.storage_path = o.name
               OR regexp_replace(p.storage_path, '\.jpg$', '_t.jpg') = o.name)
     LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 200), 1000));
$$;

-- Only our own purge job (service role) may list them.
REVOKE ALL ON FUNCTION orphan_photo_files(INT) FROM PUBLIC, anon, authenticated;
