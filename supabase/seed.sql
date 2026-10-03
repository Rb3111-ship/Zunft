-- ==============================================================================
-- Seed Data: supabase/seed.sql
-- Scenario: Electricians in Hamburg (Elektro Meister Hamburg)
-- ==============================================================================

-- 1. Create Demo Business
INSERT INTO businesses (
    id,
    name,
    trade_category,
    owner_name,
    tax_number,
    vat_id,
    iban,
    bic,
    bank_name,
    phone,
    email,
    website,
    address_street,
    address_zip,
    address_city,
    location,
    default_hourly_rate_cents,
    default_vat_rate,
    subscription_status
) VALUES (
    'b0000000-0000-0000-0000-000000000001',
    'Elektrotechnik Hansa Meisterbetrieb',
    'elektro',
    'Thorsten Krause',
    '48/215/09871',
    'DE319827364',
    'DE89200411550123456789',
    'COBADEFFXXX',
    'Commerzbank Hamburg',
    '+49 40 55443322',
    'info@elektro-hansa-hh.de',
    'https://elektro-hansa-hh.de',
    'Große Elbstraße 142',
    '22767',
    'Hamburg',
    -- Geography Point in Hamburg Altona (Longitude, Latitude)
    ST_SetSRID(ST_MakePoint(9.9356, 53.5441), 4326),
    6800, -- 68,00 € / Std
    19.00,
    'active'
);

-- 2. Create Sample Customers in Hamburg
INSERT INTO customers (
    id,
    business_id,
    salutation,
    name,
    first_name,
    email,
    phone,
    street,
    zip,
    city,
    notes
) VALUES 
(
    'c0000000-0000-0000-0000-000000000001',
    'b0000000-0000-0000-0000-000000000001',
    'Herr',
    'Müller',
    'Thomas',
    'thomas.mueller@alster-mail.de',
    '+49 171 1234567',
    'Elbchaussee 118',
    '22763',
    'Hamburg',
    'Einfamilienhaus, Kellerzugang über Gartenseite'
),
(
    'c0000000-0000-0000-0000-000000000002',
    'b0000000-0000-0000-0000-000000000001',
    'Frau',
    'Schmidt',
    'Sabine',
    's.schmidt@hamburg-immobilien.de',
    '+49 40 88776655',
    'Mühlenkamp 34',
    '22303',
    'Hamburg',
    'Altbauwohnung 3. OG, Klingel Schmidt/Weber'
),
(
    'c0000000-0000-0000-0000-000000000003',
    'b0000000-0000-0000-0000-000000000001',
    'Firma',
    'Café Alsterperle GmbH',
    'Geschäftsleitung',
    'kontakt@alsterperle-hh.de',
    '+49 40 44332211',
    'Eduard-Rhein-Ufer 1',
    '22087',
    'Hamburg',
    'Gastronomiebetrieb, Anlieferung & Arbeiten bitte vor 11:00 Uhr'
);
