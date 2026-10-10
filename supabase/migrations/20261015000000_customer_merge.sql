-- Merging duplicate customers. The duplicate is not deleted: issued documents are frozen by law
-- (GoBD) and still point at it. It is marked as merged into the customer that is kept; the app hides
-- merged customers from lists and pickers and moves the jobs over.

ALTER TABLE customers ADD COLUMN merged_into UUID REFERENCES customers(id) ON DELETE SET NULL;
ALTER TABLE customers ADD CONSTRAINT customers_not_merged_into_self CHECK (merged_into IS NULL OR merged_into <> id);
CREATE INDEX idx_customers_merged_into ON customers(merged_into) WHERE merged_into IS NOT NULL;

COMMENT ON COLUMN customers.merged_into IS 'Set when this customer was merged into another one (kept for issued documents, hidden in the app).';
