-- Storage included in a plan: recordings, receipt photos and PDFs count against the limit of the
-- business. The limit is set by us (like seat_limit), never by the app. New uploads of recordings
-- and receipts are refused once the limit is reached; issued documents (PDFs of invoices) are
-- always stored, because an invoice must never be blocked by a full storage.

ALTER TABLE businesses ADD COLUMN storage_limit_mb INT NOT NULL DEFAULT 1024 CHECK (storage_limit_mb BETWEEN 1 AND 10000000);
COMMENT ON COLUMN businesses.storage_limit_mb IS 'Storage included in the plan, in MB. Changed by us (billing), never by clients.';

CREATE OR REPLACE FUNCTION guard_business_plan()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF (NEW.seat_limit IS DISTINCT FROM OLD.seat_limit OR NEW.storage_limit_mb IS DISTINCT FROM OLD.storage_limit_mb)
       AND current_user = 'authenticated' THEN
        RAISE EXCEPTION 'the plan cannot be changed from the app';
    END IF;
    IF NEW.employees_can_create IS DISTINCT FROM OLD.employees_can_create
       AND current_user = 'authenticated' AND get_user_role() <> 'owner' THEN
        RAISE EXCEPTION 'not allowed: only the owner can change this';
    END IF;
    RETURN NEW;
END;
$$;

-- Bytes stored for a business in the two private buckets (files live under "<business id>/...").
CREATE OR REPLACE FUNCTION storage_usage_bytes(p_business UUID)
RETURNS BIGINT
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, storage, pg_temp
AS $$
    SELECT COALESCE(SUM((metadata->>'size')::BIGINT), 0)::BIGINT
      FROM storage.objects
     WHERE bucket_id IN ('captures', 'documents')
       AND name LIKE p_business::TEXT || '/%';
$$;
REVOKE ALL ON FUNCTION storage_usage_bytes(UUID) FROM PUBLIC, anon, authenticated;

-- What the app shows: {used_bytes, limit_bytes} of the caller's own business.
CREATE OR REPLACE FUNCTION storage_status()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_business UUID := get_user_business_id();
    v_limit INT;
BEGIN
    IF auth.uid() IS NULL OR v_business IS NULL THEN
        RAISE EXCEPTION 'not allowed';
    END IF;
    SELECT storage_limit_mb INTO v_limit FROM businesses WHERE id = v_business;
    RETURN jsonb_build_object(
        'used_bytes', storage_usage_bytes(v_business),
        'limit_bytes', v_limit::BIGINT * 1024 * 1024);
END;
$$;
REVOKE ALL ON FUNCTION storage_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION storage_status() TO authenticated;

-- Used inside the upload policy.
CREATE OR REPLACE FUNCTION storage_has_room()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(
        (SELECT storage_usage_bytes(b.id) < b.storage_limit_mb::BIGINT * 1024 * 1024
           FROM businesses b WHERE b.id = get_user_business_id()),
        FALSE);
$$;
REVOKE ALL ON FUNCTION storage_has_room() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION storage_has_room() TO authenticated;

DROP POLICY captures_insert ON storage.objects;
CREATE POLICY captures_insert ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'captures' AND (storage.foldername(name))[1] = get_user_business_id()::TEXT
                AND storage_has_room());
