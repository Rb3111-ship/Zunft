-- Which payment reminders were sent for which invoice, so the app can say "reminded on 12.10." and
-- nobody (boss or office) reminds the same customer twice by accident.
--
-- Append-only: rows are written by record_payment_reminder() and never changed or deleted by
-- clients. Only the boss and the office see them. Sending a reminder is never blocked by an ended
-- subscription: it is how a business gets its money.

CREATE TABLE payment_reminders (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    sent_by     UUID REFERENCES profiles(id) ON DELETE SET NULL,
    sent_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_payment_reminders_document ON payment_reminders (document_id, sent_at DESC);
CREATE INDEX idx_payment_reminders_business ON payment_reminders (business_id);

ALTER TABLE payment_reminders ENABLE ROW LEVEL SECURITY;

CREATE POLICY payment_reminders_select ON payment_reminders FOR SELECT TO authenticated
    USING (business_id = get_user_business_id() AND is_manager());

-- Notes that a reminder for an OPEN invoice of the caller's business was sent now.
CREATE OR REPLACE FUNCTION record_payment_reminder(p_document UUID)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_business UUID := get_user_business_id();
    v_at TIMESTAMPTZ := NOW();
BEGIN
    IF auth.uid() IS NULL OR v_business IS NULL OR NOT is_manager() THEN
        RAISE EXCEPTION 'not allowed';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM documents
         WHERE id = p_document AND business_id = v_business
           AND doc_type = 'invoice' AND status IN ('issued', 'sent')) THEN
        RAISE EXCEPTION 'no open invoice of this business';
    END IF;
    INSERT INTO payment_reminders (business_id, document_id, sent_by, sent_at)
    VALUES (v_business, p_document, auth.uid(), v_at);
    RETURN v_at;
END;
$$;
REVOKE ALL ON FUNCTION record_payment_reminder(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION record_payment_reminder(UUID) TO authenticated;
