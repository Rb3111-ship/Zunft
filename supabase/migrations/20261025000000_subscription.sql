-- Subscription: who may use the paid features.
--
-- One subscription per BUSINESS (a self-employed person is a business with 1 seat; a company is a
-- business with N seats, paid by the owner; workers follow the status of the business).
-- All of this is changed by us (billing / Stripe webhook / by hand), never by the app.
--
-- When access has ended the business is READ-ONLY, not locked out: everything can still be read and
-- exported, existing records can still be edited and an issued invoice can still be cancelled (an
-- invoice must be kept and corrected by law, GoBD). What stops is creating anything new: customers,
-- jobs, notes and receipts (these cost AI money), appointments, working time, quotes and invoices.
--
-- States:
--   trialing  free until trial_ends_at
--   active    paid; paid_until = end of the paid period (NULL = no end, e.g. a pilot customer)
--   past_due  a payment failed; works for 7 more days after paid_until, then read-only
--   canceled  works until paid_until, then read-only
--
-- By hand, for example:
--   UPDATE businesses SET subscription_status = 'active', paid_until = NULL WHERE id = '...';   -- free for good
--   UPDATE businesses SET subscription_status = 'trialing', trial_ends_at = now() - interval '1 day' WHERE id = '...'; -- test the lock

-- (subscription_status with its check already exists since the first migration)
ALTER TABLE businesses
    ADD COLUMN trial_ends_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '14 days'),
    ADD COLUMN paid_until TIMESTAMPTZ,
    ADD COLUMN stripe_customer_id TEXT,
    ADD COLUMN stripe_subscription_id TEXT;

COMMENT ON COLUMN businesses.subscription_status IS 'trialing | active | past_due | canceled. Changed by us (billing), never by clients.';

-- Everybody who exists today keeps working: they are the test and pilot businesses.
UPDATE businesses SET subscription_status = 'active', paid_until = NULL;

-- The app must not be able to give itself a subscription.
CREATE OR REPLACE FUNCTION guard_business_plan()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF (NEW.seat_limit IS DISTINCT FROM OLD.seat_limit
        OR NEW.storage_limit_mb IS DISTINCT FROM OLD.storage_limit_mb
        OR NEW.subscription_status IS DISTINCT FROM OLD.subscription_status
        OR NEW.trial_ends_at IS DISTINCT FROM OLD.trial_ends_at
        OR NEW.paid_until IS DISTINCT FROM OLD.paid_until
        OR NEW.stripe_customer_id IS DISTINCT FROM OLD.stripe_customer_id
        OR NEW.stripe_subscription_id IS DISTINCT FROM OLD.stripe_subscription_id)
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

-- 'full' | 'grace' (a payment is late, still works) | 'readonly'
CREATE OR REPLACE FUNCTION subscription_access(p_business UUID)
RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE((
        SELECT CASE b.subscription_status
            WHEN 'trialing' THEN CASE WHEN b.trial_ends_at >= now() THEN 'full' ELSE 'readonly' END
            WHEN 'active' THEN CASE
                WHEN b.paid_until IS NULL OR b.paid_until >= now() THEN 'full'
                WHEN b.paid_until + interval '7 days' >= now() THEN 'grace'
                ELSE 'readonly' END
            WHEN 'past_due' THEN CASE
                WHEN b.paid_until IS NOT NULL AND b.paid_until + interval '7 days' >= now() THEN 'grace'
                ELSE 'readonly' END
            WHEN 'canceled' THEN CASE WHEN b.paid_until IS NOT NULL AND b.paid_until >= now() THEN 'full' ELSE 'readonly' END
            ELSE 'readonly' END
          FROM businesses b WHERE b.id = p_business), 'readonly');
$$;
REVOKE ALL ON FUNCTION subscription_access(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION business_writable(p_business UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$ SELECT subscription_access(p_business) <> 'readonly' $$;
REVOKE ALL ON FUNCTION business_writable(UUID) FROM PUBLIC, anon, authenticated;

-- What the app and the Edge Functions ask: the caller's own business.
CREATE OR REPLACE FUNCTION subscription_status()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_business UUID := get_user_business_id();
    b businesses;
BEGIN
    IF auth.uid() IS NULL OR v_business IS NULL THEN
        RAISE EXCEPTION 'not allowed';
    END IF;
    SELECT * INTO b FROM businesses WHERE id = v_business;
    RETURN jsonb_build_object(
        'status', b.subscription_status,
        'access', subscription_access(v_business),
        'trial_ends_at', b.trial_ends_at,
        'paid_until', b.paid_until,
        'grace_ends_at', CASE WHEN b.paid_until IS NULL THEN NULL ELSE b.paid_until + interval '7 days' END,
        'seat_limit', b.seat_limit);
END;
$$;
REVOKE ALL ON FUNCTION subscription_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION subscription_status() TO authenticated;

-- The lock itself: no NEW record for a business whose access has ended. Only people who are
-- signed in are checked (our own server jobs, running with the service key, are not).
CREATE OR REPLACE FUNCTION enforce_subscription()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NOT NULL AND NOT business_writable(NEW.business_id) THEN
        RAISE EXCEPTION 'subscription_expired' USING ERRCODE = 'P0402';
    END IF;
    RETURN NEW;
END;
$$;

-- Documents: quotes and invoices need a subscription, a cancellation (Storno) never does.
CREATE OR REPLACE FUNCTION enforce_subscription_documents()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.doc_type <> 'cancellation' AND auth.uid() IS NOT NULL AND NOT business_writable(NEW.business_id) THEN
        RAISE EXCEPTION 'subscription_expired' USING ERRCODE = 'P0402';
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION enforce_subscription() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION enforce_subscription_documents() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_customers_subscription BEFORE INSERT ON customers FOR EACH ROW EXECUTE FUNCTION enforce_subscription();
CREATE TRIGGER trg_jobs_subscription BEFORE INSERT ON jobs FOR EACH ROW EXECUTE FUNCTION enforce_subscription();
CREATE TRIGGER trg_capture_logs_subscription BEFORE INSERT ON capture_logs FOR EACH ROW EXECUTE FUNCTION enforce_subscription();
CREATE TRIGGER trg_appointments_subscription BEFORE INSERT ON appointments FOR EACH ROW EXECUTE FUNCTION enforce_subscription();
CREATE TRIGGER trg_time_entries_subscription BEFORE INSERT ON time_entries FOR EACH ROW EXECUTE FUNCTION enforce_subscription();
CREATE TRIGGER trg_documents_subscription BEFORE INSERT ON documents FOR EACH ROW EXECUTE FUNCTION enforce_subscription_documents();

-- New recordings and receipt photos are refused as well (they would only be wasted storage).
CREATE OR REPLACE FUNCTION storage_has_room()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(
        (SELECT storage_usage_bytes(b.id) < b.storage_limit_mb::BIGINT * 1024 * 1024
                AND subscription_access(b.id) <> 'readonly'
           FROM businesses b WHERE b.id = get_user_business_id()),
        FALSE);
$$;
REVOKE ALL ON FUNCTION storage_has_room() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION storage_has_room() TO authenticated;
