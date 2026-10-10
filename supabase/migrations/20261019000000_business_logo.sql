-- Logo on the PDF: the image lives in the private "documents" bucket under "<business id>/logo/...".
-- Only the path is stored here; the app downloads it (and caches it) when it builds a PDF.
ALTER TABLE businesses ADD COLUMN logo_path TEXT
    CHECK (logo_path IS NULL OR logo_path LIKE id::TEXT || '/logo/%');
COMMENT ON COLUMN businesses.logo_path IS 'Storage path of the logo in the documents bucket, or NULL.';
