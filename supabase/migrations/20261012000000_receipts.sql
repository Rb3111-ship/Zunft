-- Receipts (Belege): a photographed receipt is a note on a job like a voice note. Its image path
-- lives in capture_logs.photo_storage_paths (private "captures" bucket). The hash of the image is
-- kept to warn when the same receipt is added twice.
ALTER TABLE capture_logs ADD COLUMN image_sha256 TEXT;
CREATE INDEX idx_capture_logs_image_hash ON capture_logs (business_id, image_sha256) WHERE image_sha256 IS NOT NULL;
COMMENT ON COLUMN capture_logs.image_sha256 IS 'SHA-256 of the receipt image; used to detect duplicates';
