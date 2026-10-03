-- ==============================================================================
-- Migration: 20261003000000_capture_idempotency.sql
-- The app sends a unique id with every voice note. If the phone loses signal right after the
-- server finished, the retry carries the same id and gets the stored result instead of
-- creating a second job and a second AI call.
-- ==============================================================================

ALTER TABLE capture_logs ADD COLUMN client_capture_id UUID;

-- One log per (business, client id). Rows without an id (older rows, tests) are unaffected.
CREATE UNIQUE INDEX uq_capture_logs_client_capture
    ON capture_logs (business_id, client_capture_id)
    WHERE client_capture_id IS NOT NULL;

COMMENT ON COLUMN capture_logs.client_capture_id IS
    'Idempotency key generated on the phone for each recording or typed note';
