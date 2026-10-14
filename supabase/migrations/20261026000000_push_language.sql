-- Push messages in the language of the person's app: each phone tells the server the app language
-- when it registers, and the Edge Function writes the message in it. Unknown codes count as German.

ALTER TABLE device_tokens ADD COLUMN language TEXT NOT NULL DEFAULT 'de';

DROP FUNCTION register_device_token(TEXT, TEXT);

CREATE OR REPLACE FUNCTION register_device_token(p_token TEXT, p_platform TEXT, p_language TEXT DEFAULT 'de')
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_business UUID := get_user_business_id();
    v_language TEXT := CASE WHEN p_language IN ('de', 'en', 'tr', 'ar', 'sq', 'pl', 'ro', 'ru', 'uk', 'hr', 'sr', 'bg', 'fa')
                            THEN p_language ELSE 'de' END;
BEGIN
    IF auth.uid() IS NULL OR v_business IS NULL THEN
        RAISE EXCEPTION 'not allowed';
    END IF;
    INSERT INTO device_tokens (token, user_id, business_id, platform, language)
    VALUES (p_token, auth.uid(), v_business, p_platform, v_language)
    ON CONFLICT (token) DO UPDATE
        SET user_id = EXCLUDED.user_id, business_id = EXCLUDED.business_id,
            platform = EXCLUDED.platform, language = EXCLUDED.language, updated_at = NOW();
END;
$$;

REVOKE ALL ON FUNCTION register_device_token(TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION register_device_token(TEXT, TEXT, TEXT) TO authenticated;
