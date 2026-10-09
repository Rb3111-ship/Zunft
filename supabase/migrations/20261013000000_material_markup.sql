-- Markup (Aufschlag) in percent that is added to the material bought on receipts when the receipt
-- positions go onto the customer's invoice. 0 = pass the cost on as it is.
ALTER TABLE businesses ADD COLUMN material_markup_percent NUMERIC(5,2) NOT NULL DEFAULT 0
    CHECK (material_markup_percent BETWEEN 0 AND 200);
COMMENT ON COLUMN businesses.material_markup_percent IS 'Aufschlag auf Material aus Belegen in Prozent';
