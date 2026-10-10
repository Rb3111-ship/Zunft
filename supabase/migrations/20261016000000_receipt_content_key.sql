-- Second duplicate check for receipts: the same receipt photographed twice is not the same file
-- (so image_sha256 differs), but the READ data is the same. receipt_key is built in the Edge
-- Function from receipt number (or supplier) + date + total.
ALTER TABLE capture_logs ADD COLUMN receipt_key TEXT;
CREATE INDEX idx_capture_logs_receipt_key ON capture_logs(receipt_key) WHERE receipt_key IS NOT NULL;
