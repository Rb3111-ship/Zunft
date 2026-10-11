-- Push messages for appointments: when the boss gives a worker an appointment, moves it, cancels it
-- or takes it away, the worker's phone is told even if the app is closed.
--
-- 1. device_tokens: the address of a phone at Google's push service (FCM). Only the two functions
--    below touch it; clients cannot read tokens.
-- 2. A trigger on appointments works out who must be told what and calls the Edge Function
--    `notify-appointment` (through pg_net) with a shared secret. A failure to notify never blocks
--    saving an appointment.

CREATE TABLE device_tokens (
    token       TEXT PRIMARY KEY CHECK (char_length(token) BETWEEN 20 AND 4096),
    user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    platform    TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_device_tokens_user ON device_tokens (user_id);
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY; -- no policies: reachable only through the functions

-- A phone registers itself. A token belongs to one person at a time: if another person signs in on
-- the same phone and registers, the token moves to them (the earlier person stops receiving).
CREATE OR REPLACE FUNCTION register_device_token(p_token TEXT, p_platform TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_business UUID := get_user_business_id();
BEGIN
    IF auth.uid() IS NULL OR v_business IS NULL THEN
        RAISE EXCEPTION 'not allowed';
    END IF;
    INSERT INTO device_tokens (token, user_id, business_id, platform)
    VALUES (p_token, auth.uid(), v_business, p_platform)
    ON CONFLICT (token) DO UPDATE
        SET user_id = EXCLUDED.user_id, business_id = EXCLUDED.business_id,
            platform = EXCLUDED.platform, updated_at = NOW();
END;
$$;

-- Whoever holds the phone (and so knows the token) may remove it, also when it belonged to the
-- previous user: used at sign-out and when push is switched off.
CREATE OR REPLACE FUNCTION unregister_device_token(p_token TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'not allowed';
    END IF;
    DELETE FROM device_tokens WHERE token = p_token;
END;
$$;

REVOKE ALL ON FUNCTION register_device_token(TEXT, TEXT), unregister_device_token(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION register_device_token(TEXT, TEXT), unregister_device_token(TEXT) TO authenticated;

-- ------------------------------------------------------------------------------------------------
-- Who is told what
-- ------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION uuid_array_minus(a UUID[], b UUID[])
RETURNS UUID[]
LANGUAGE sql IMMUTABLE
AS $$
    SELECT COALESCE(ARRAY(SELECT x FROM unnest(COALESCE(a, '{}')) x EXCEPT SELECT y FROM unnest(COALESCE(b, '{}')) y), '{}');
$$;

CREATE OR REPLACE FUNCTION send_appointment_push(p_event TEXT, p_row appointments, p_users UUID[])
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_secret TEXT;
BEGIN
    IF COALESCE(cardinality(p_users), 0) = 0 OR p_row.ends_at < NOW() THEN
        RETURN; -- nobody to tell, or it is already over
    END IF;
    IF to_regnamespace('net') IS NULL OR to_regnamespace('vault') IS NULL THEN
        RETURN; -- not available here (tests)
    END IF;
    EXECUTE 'SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = ''notify_secret''' INTO v_secret;
    IF v_secret IS NULL THEN
        RETURN;
    END IF;
    PERFORM net.http_post(
        url := 'https://wwssjssjxurycxcshgey.supabase.co/functions/v1/notify-appointment',
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-notify-secret', v_secret),
        body := jsonb_build_object(
            'event', p_event,
            'user_ids', to_jsonb(p_users),
            'appointment', jsonb_build_object(
                'id', p_row.id, 'title', p_row.title, 'starts_at', p_row.starts_at, 'location', p_row.location))
    );
END;
$$;

CREATE OR REPLACE FUNCTION notify_appointment_change()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor  UUID[] := CASE WHEN auth.uid() IS NULL THEN '{}'::UUID[] ELSE ARRAY[auth.uid()] END;
    v_added  UUID[];
    v_removed UUID[];
    v_kept   UUID[];
BEGIN
    BEGIN
        IF TG_OP = 'INSERT' THEN
            PERFORM send_appointment_push('new', NEW, uuid_array_minus(NEW.assignee_ids, v_actor));
        ELSIF TG_OP = 'DELETE' THEN
            PERFORM send_appointment_push('deleted', OLD, uuid_array_minus(OLD.assignee_ids, v_actor));
        ELSE
            IF NEW.status = 'canceled' AND OLD.status <> 'canceled' THEN
                PERFORM send_appointment_push('canceled', NEW,
                    uuid_array_minus(ARRAY(SELECT unnest(OLD.assignee_ids) UNION SELECT unnest(NEW.assignee_ids)), v_actor));
            ELSE
                v_added := uuid_array_minus(NEW.assignee_ids, OLD.assignee_ids);
                v_removed := uuid_array_minus(OLD.assignee_ids, NEW.assignee_ids);
                v_kept := uuid_array_minus(NEW.assignee_ids, v_added);
                IF OLD.status = 'canceled' AND NEW.status <> 'canceled' THEN
                    -- planned again: everyone on it is told it is on
                    PERFORM send_appointment_push('new', NEW, uuid_array_minus(NEW.assignee_ids, v_actor));
                ELSE
                    PERFORM send_appointment_push('new', NEW, uuid_array_minus(v_added, v_actor));
                    PERFORM send_appointment_push('removed', OLD, uuid_array_minus(v_removed, v_actor));
                    IF NEW.starts_at IS DISTINCT FROM OLD.starts_at OR NEW.ends_at IS DISTINCT FROM OLD.ends_at
                       OR NEW.location IS DISTINCT FROM OLD.location OR NEW.title IS DISTINCT FROM OLD.title THEN
                        PERFORM send_appointment_push('changed', NEW, uuid_array_minus(v_kept, v_actor));
                    END IF;
                END IF;
            END IF;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL; -- telling people is a convenience: saving the appointment always wins
    END;
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_appointments_push AFTER INSERT OR UPDATE OR DELETE ON appointments
    FOR EACH ROW EXECUTE FUNCTION notify_appointment_change();

REVOKE ALL ON FUNCTION uuid_array_minus(UUID[], UUID[]), send_appointment_push(TEXT, appointments, UUID[]),
    notify_appointment_change() FROM PUBLIC, anon, authenticated;
