// SQL tests for the Zunft migrations, run on PGlite (Postgres in WASM).
// PGlite has no Supabase auth/storage schema and no PostGIS, so the harness stubs those;
// the RLS, trigger and numbering logic under test is the real migration SQL.
import { test, before } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { PGlite } from "@electric-sql/pglite";

const here = dirname(fileURLToPath(import.meta.url));
const migrationsDir = join(here, "..", "migrations");

const STUBS = `
  CREATE ROLE anon NOLOGIN;
  CREATE ROLE authenticated NOLOGIN;
  CREATE ROLE service_role NOLOGIN;
  CREATE SCHEMA auth;
  CREATE TABLE auth.users (id UUID PRIMARY KEY);
  CREATE FUNCTION auth.uid() RETURNS UUID LANGUAGE sql STABLE AS
    $$ SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  CREATE SCHEMA storage;
  CREATE TABLE storage.buckets (id TEXT PRIMARY KEY, name TEXT, public BOOLEAN);
  CREATE TABLE storage.objects (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, bucket_id TEXT, name TEXT, metadata JSONB);
  ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
  CREATE FUNCTION storage.foldername(name TEXT) RETURNS TEXT[] LANGUAGE sql IMMUTABLE AS
    $$ SELECT (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1] $$;
  -- Supabase grants EXECUTE on every new public function to anon and authenticated by name.
  -- Reproduce that, so the tests see what the hosted database does (not Postgres's own default).
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated;
`;

const GRANTS = `
  GRANT USAGE ON SCHEMA public, auth, storage TO anon, authenticated;
  GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
  GRANT ALL ON ALL TABLES IN SCHEMA storage TO authenticated;
  GRANT SELECT ON auth.users TO authenticated;
`;

/** Adapt the init migration to PGlite: no extensions, geography becomes text. */
function adaptForPglite(sql) {
  return sql
    .replace(/CREATE EXTENSION[^;]*;/g, "")
    .replace(/GEOGRAPHY\(Point, 4326\)/g, "TEXT")
    .replace(/CREATE INDEX idx_businesses_location[^;]*;/, "");
}

let db;
const A = "11111111-1111-1111-1111-111111111111"; // user of business A (owner)
const B = "22222222-2222-2222-2222-222222222222"; // user of business B (owner)
const A2 = "33333333-3333-3333-3333-333333333333"; // geselle in business A
let bizA, bizB;

async function as(userId, fn) {
  await db.exec(`SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub', '${userId}', false);`);
  try {
    return await fn();
  } finally {
    await db.exec(`RESET ROLE; SELECT set_config('request.jwt.claim.sub', '', false);`);
  }
}

before(async () => {
  db = new PGlite();
  await db.exec(STUBS);
  // The nightly job needs pg_cron / pg_net / Vault, which PGlite does not have: it is not part of the schema logic.
  for (const f of readdirSync(migrationsDir).filter((f) => f.endsWith(".sql") && !f.includes("schedule_purge")).sort()) {
    await db.exec(adaptForPglite(readFileSync(join(migrationsDir, f), "utf8")));
  }
  await db.exec(GRANTS);
  await db.exec(`INSERT INTO auth.users VALUES ('${A}'), ('${B}'), ('${A2}')`);

  bizA = (await as(A, () => db.query(`SELECT create_business_for_user('Firma A', 'Anna A') AS id`))).rows[0].id;
  bizB = (await as(B, () => db.query(`SELECT create_business_for_user('Firma B', 'Bernd B') AS id`))).rows[0].id;
  // Colleague (owner onboarding of staff is a later feature, so insert as superuser)
  await db.query(`INSERT INTO profiles (id, business_id, full_name, role) VALUES ($1, $2, 'Gesa', 'geselle')`, [A2, bizA]);
});

const rejects = (p, re) => assert.rejects(p, re);

test("onboarding creates business + owner profile; second call is refused", async () => {
  const roles = await db.query(`SELECT role FROM profiles WHERE id = $1`, [A]);
  assert.equal(roles.rows[0].role, "owner");
  await rejects(as(A, () => db.query(`SELECT create_business_for_user('Zweit', 'Anna')`)), /already belongs/);
});

test("anon-like caller (no uid) cannot create a business", async () => {
  await rejects(db.query(`SELECT create_business_for_user('X', 'Y')`), /not authenticated/);
});

test("tenants cannot see each other's rows", async () => {
  await as(A, () => db.query(`INSERT INTO customers (business_id, name) VALUES ($1, 'Müller')`, [bizA]));
  await as(B, () => db.query(`INSERT INTO customers (business_id, name) VALUES ($1, 'Schmidt')`, [bizB]));
  const seenByA = await as(A, () => db.query(`SELECT name FROM customers`));
  assert.deepEqual(seenByA.rows.map((r) => r.name), ["Müller"]);
  const bizSeenByB = await as(B, () => db.query(`SELECT id FROM businesses`));
  assert.deepEqual(bizSeenByB.rows.map((r) => r.id), [bizB]);
});

test("cannot insert into another business", async () => {
  await rejects(
    as(A, () => db.query(`INSERT INTO customers (business_id, name) VALUES ($1, 'Fremd')`, [bizB])),
    /row-level security/,
  );
});

test("job cannot reference a customer of another business", async () => {
  const cB = (await db.query(`SELECT id FROM customers WHERE business_id = $1`, [bizB])).rows[0].id;
  await rejects(
    as(A, () => db.query(`INSERT INTO jobs (business_id, customer_id, title) VALUES ($1, $2, 'Hack')`, [bizA, cB])),
    /row-level security/,
  );
});

test("a non-owner cannot promote themselves; an owner can change others' roles", async () => {
  await rejects(as(A2, () => db.query(`UPDATE profiles SET role = 'owner' WHERE id = $1`, [A2])), /only an owner/);
  await as(A, () => db.query(`UPDATE profiles SET role = 'meister' WHERE id = $1`, [A2]));
  const r = await db.query(`SELECT role FROM profiles WHERE id = $1`, [A2]);
  assert.equal(r.rows[0].role, "meister");
});

test("owner cannot change their own role or move a profile to another business", async () => {
  await rejects(as(A, () => db.query(`UPDATE profiles SET role = 'geselle' WHERE id = $1`, [A])), /own role/);
  await rejects(as(A, () => db.query(`UPDATE profiles SET business_id = $1 WHERE id = $2`, [bizB, A2])), /row-level security|cannot be changed/);
});

test("capture_logs are append-only for clients", async () => {
  await as(A, () => db.query(`INSERT INTO capture_logs (business_id, raw_transcript) VALUES ($1, 'x')`, [bizA]));
  const upd = await as(A, () => db.query(`UPDATE capture_logs SET raw_transcript = 'changed'`));
  assert.equal(upd.affectedRows, 0);
  const del = await as(A, () => db.query(`DELETE FROM capture_logs`));
  assert.equal(del.affectedRows, 0);
});

// Runs as the table owner but with a logged-in user's identity: for calling functions that
// are no longer granted to clients (the numbering function) the way create_document() does.
async function asUser(userId, fn) {
  await db.exec(`SELECT set_config('request.jwt.claim.sub', '${userId}', false);`);
  try {
    return await fn();
  } finally {
    await db.exec(`SELECT set_config('request.jwt.claim.sub', '', false);`);
  }
}

test("document numbers are sequential per business/type/year", async () => {
  const n = (biz, user, type, year) =>
    asUser(user, async () => (await db.query(`SELECT get_next_document_number($1, $2, $3) AS n`, [biz, type, year])).rows[0].n);
  assert.equal(await n(bizA, A, "invoice", 2026), "RE-2026-0001");
  assert.equal(await n(bizA, A, "invoice", 2026), "RE-2026-0002");
  assert.equal(await n(bizA, A, "quote", 2026), "ANG-2026-0001");
  assert.equal(await n(bizA, A, "invoice", 2027), "RE-2027-0001");
  assert.equal(await n(bizB, B, "invoice", 2026), "RE-2026-0001");
});

test("numbering refuses another tenant's business id and unknown types", async () => {
  await rejects(asUser(A, () => db.query(`SELECT get_next_document_number($1, 'invoice', 2026)`, [bizB])), /not allowed/);
  await rejects(asUser(A, () => db.query(`SELECT get_next_document_number($1, 'memo', 2026)`, [bizA])), /unknown document type/);
});

test("a rolled-back number is reused (no gaps from failed saves)", async () => {
  await db.exec(`BEGIN`);
  await asUser(A, () => db.query(`SELECT get_next_document_number($1, 'invoice', 2030)`, [bizA]));
  await db.exec(`ROLLBACK`);
  const r = await asUser(A, () => db.query(`SELECT get_next_document_number($1, 'invoice', 2030) AS n`, [bizA]));
  assert.equal(r.rows[0].n, "RE-2030-0001");
});

test("logged-in clients cannot call the numbering function directly", async () => {
  await rejects(as(A, () => db.query(`SELECT get_next_document_number($1, 'invoice', 2026)`, [bizA])), /permission denied/);
});

// ---- create_document -----------------------------------------------------------------

const C = "44444444-4444-4444-4444-444444444444"; // owner of business C: complete data, used for documents
let bizC;
const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const item = (over = {}) => ({ type: "labor", description: "Steckdose montiert", quantity: 2, unit: "Std", unit_price_net_cents: 6800, ...over });
const payload = (n, over = {}) => ({
  id: uuid(n),
  doc_type: "invoice",
  title: "Steckdose Keller",
  recipient_snapshot: { name: "Thomas Müller", address: "Elbchaussee 118, 22763 Hamburg" },
  line_items: [item(), item({ type: "material", description: "Doppelsteckdose", quantity: 1, unit: "Stk", unit_price_net_cents: 4000 })],
  ...over,
});
const create = (user, p) => as(user, async () => (await db.query(`SELECT create_document($1::jsonb) AS d`, [JSON.stringify(p)])).rows[0].d);

test("setup: business C is complete, business B is not", async () => {
  await db.exec(`INSERT INTO auth.users VALUES ('${C}')`);
  bizC = (await as(C, () => db.query(`SELECT create_business_for_user('Firma C', 'Carla C') AS id`))).rows[0].id;
  await db.query(
    `UPDATE businesses SET address_street = 'Hauptstr. 1', address_zip = '20095', address_city = 'Hamburg',
       tax_number = '48/123/45678', default_vat_rate = 19 WHERE id = $1`, [bizC]);
});

test("create_document stores a locked, numbered document with server-computed totals", async () => {
  const d = await create(C, payload(1, { line_items: [
    item(), // labor 2 x 68,00 = 136,00
    item({ type: "flat_fee", description: "Anfahrt", quantity: 1, unit: "Pauschal", unit_price_net_cents: 3500 }),
    item({ type: "material", description: "Doppelsteckdose", quantity: 1, unit: "Stk", unit_price_net_cents: 4000 }),
  ] }));

  assert.match(d.doc_number, /^RE-\d{4}-0001$/);
  assert.equal(d.status, "issued");
  assert.equal(d.is_gobd_locked, true);
  assert.ok(d.gobd_locked_at);
  assert.equal(d.business_id, bizC);
  assert.equal(d.subtotal_labor_cents, 17100); // labor + flat fee
  assert.equal(d.subtotal_material_cents, 4000);
  assert.equal(d.total_net_cents, 21100);
  assert.equal(d.vat_amount_cents, 4009); // 21100 * 19 %
  assert.equal(d.total_gross_cents, 25109);
  assert.equal(d.recipient_snapshot.name, "Thomas Müller");
  assert.equal(d.title, "Steckdose Keller");
  assert.equal(d.line_items[0].total_net_cents, 13600);
});

test("totals and VAT rate sent by the client are ignored", async () => {
  const d = await create(C, payload(2, { total_gross_cents: 1, vat_rate: 0, subtotal_labor_cents: 999999, doc_number: "RE-1999-0001" }));
  assert.equal(d.vat_rate, 19);
  assert.equal(d.total_net_cents, 17600);
  assert.equal(d.total_gross_cents, 20944);
  assert.notEqual(d.doc_number, "RE-1999-0001");
});

test("a retry with the same id returns the same document and consumes no new number", async () => {
  const first = await create(C, payload(3));
  const again = await create(C, payload(3));
  assert.equal(again.id, first.id);
  assert.equal(again.doc_number, first.doc_number);
  const next = await create(C, payload(4));
  const num = (x) => Number(x.doc_number.split("-")[2]);
  assert.equal(num(next), num(first) + 1); // no gap, no duplicate
});

test("another business cannot read or reuse a document id", async () => {
  await rejects(create(B, payload(3)), /not allowed/);
});

test("numbers continue per type and are separate for quotes", async () => {
  const q = await create(C, payload(5, { doc_type: "quote" }));
  assert.match(q.doc_number, /^ANG-\d{4}-0001$/);
});

test("invalid input is rejected (including missing fields, which a naive NOT IN would let through)", async () => {
  const bad = {
    "unknown type": payload(10, { doc_type: "memo" }),
    "missing type": payload(11, { doc_type: undefined }),
    "no line items": payload(12, { line_items: [] }),
    "missing line items": payload(13, { line_items: undefined }),
    "line items not an array": payload(14, { line_items: "x" }),
    "bad item type": payload(15, { line_items: [item({ type: "gift" })] }),
    "missing item type": payload(16, { line_items: [item({ type: undefined })] }),
    "bad unit": payload(17, { line_items: [item({ unit: "kg" })] }),
    "missing unit": payload(18, { line_items: [item({ unit: undefined })] }),
    "empty description": payload(19, { line_items: [item({ description: "  " })] }),
    "zero quantity": payload(20, { line_items: [item({ quantity: 0 })] }),
    "negative quantity": payload(21, { line_items: [item({ quantity: -1 })] }),
    "negative price": payload(22, { line_items: [item({ unit_price_net_cents: -5 })] }),
    "fractional cents": payload(23, { line_items: [item({ unit_price_net_cents: 10.5 })] }),
    "absurd price": payload(24, { line_items: [item({ unit_price_net_cents: 99999999 })] }),
    "51 items": payload(25, { line_items: Array.from({ length: 51 }, () => item()) }),
    "no recipient": payload(26, { recipient_snapshot: undefined }),
    "blank recipient name": payload(27, { recipient_snapshot: { name: "  " } }),
    "date far in the past": payload(28, { date_issued: "2001-01-01" }),
    "date far in the future": payload(29, { date_issued: "2999-01-01" }),
    "due before issue": payload(30, { date_issued: "2026-01-10", date_due: "2026-01-01" }),
  };
  const before = (await db.query(`SELECT COUNT(*)::int AS n FROM documents WHERE business_id = $1`, [bizC])).rows[0].n;
  for (const [name, p] of Object.entries(bad)) {
    await assert.rejects(create(C, p), undefined, `should reject: ${name}`);
  }
  const after = (await db.query(`SELECT COUNT(*)::int AS n FROM documents WHERE business_id = $1`, [bizC])).rows[0].n;
  assert.equal(after, before, "nothing stored for rejected requests");
});

test("a rejected request does not consume an invoice number", async () => {
  const ok1 = await create(C, payload(40));
  await assert.rejects(create(C, payload(41, { line_items: [] })));
  const ok2 = await create(C, payload(42));
  const num = (x) => Number(x.doc_number.split("-")[2]);
  assert.equal(num(ok2), num(ok1) + 1);
});

test("invoices over 250 EUR need the recipient's address; small ones and quotes do not", async () => {
  const noAddress = { name: "Laufkunde" };
  // 4 h x 68,00 = 272,00 net -> 323,68 gross, over the 250 EUR limit
  const big = [item({ quantity: 4 })];
  await assert.rejects(create(C, payload(50, { recipient_snapshot: noAddress, line_items: big })), /address is required/);
  await create(C, payload(53, { line_items: big })); // with an address it is fine
  // 100,00 net -> 119,00 gross, under the limit
  const small = await create(C, payload(51, { recipient_snapshot: noAddress, line_items: [item({ quantity: 1, unit_price_net_cents: 10000 })] }));
  assert.equal(small.total_gross_cents, 11900);
  await create(C, payload(52, { doc_type: "quote", recipient_snapshot: noAddress }));
});

test("an invoice needs complete business data (address and tax number); a quote does not", async () => {
  await assert.rejects(create(B, payload(60)), /business address is incomplete/);
  await db.query(`UPDATE businesses SET address_street = 'X 1', address_zip = '20095', address_city = 'Hamburg' WHERE id = $1`, [bizB]);
  await assert.rejects(create(B, payload(61)), /tax number or VAT id is required/);
  await create(B, payload(62, { doc_type: "quote" }));
});

test("references to another business's customer or job are refused", async () => {
  const foreignCustomer = (await db.query(`SELECT id FROM customers WHERE business_id = $1 LIMIT 1`, [bizA])).rows[0].id;
  await assert.rejects(create(C, payload(70, { customer_id: foreignCustomer })), /customer does not belong/);
  const foreignJob = (await db.query(`INSERT INTO jobs (business_id, title) VALUES ($1, 'fremd') RETURNING id`, [bizA])).rows[0].id;
  await assert.rejects(create(C, payload(71, { job_id: foreignJob })), /job does not belong/);
});

test("clients cannot insert documents directly", async () => {
  await rejects(
    as(C, () => db.query(
      `INSERT INTO documents (business_id, doc_type, doc_number, recipient_snapshot) VALUES ($1, 'invoice', 'RE-2026-9999', '{"name":"x"}')`, [bizC])),
    /row-level security|never issued/, // either guard may fire first; the point is that it is refused
  );
});

test("a locked document's content cannot be changed, but its status can move forward", async () => {
  const d = await create(C, payload(80));
  const upd = (sql, params = []) => as(C, () => db.query(sql, [d.id, ...params]));

  // content is frozen, for the owner too
  await rejects(upd(`UPDATE documents SET total_gross_cents = 1 WHERE id = $1`), /GoBD-locked/);
  await rejects(upd(`UPDATE documents SET line_items = '[]' WHERE id = $1`), /GoBD-locked/);
  await rejects(upd(`UPDATE documents SET recipient_snapshot = '{"name":"Anderer"}' WHERE id = $1`), /GoBD-locked/);
  await rejects(upd(`UPDATE documents SET doc_number = 'RE-HACK' WHERE id = $1`), /GoBD-locked/);
  await rejects(upd(`UPDATE documents SET is_gobd_locked = FALSE WHERE id = $1`), /GoBD-locked/);

  // pdf path and status workflow are allowed
  await upd(`UPDATE documents SET pdf_url = 'biz/RE.pdf' WHERE id = $1`);
  await upd(`UPDATE documents SET status = 'sent' WHERE id = $1`);
  await upd(`UPDATE documents SET status = 'paid' WHERE id = $1`);
  const row = (await db.query(`SELECT status, pdf_url FROM documents WHERE id = $1`, [d.id])).rows[0];
  assert.deepEqual(row, { status: "paid", pdf_url: "biz/RE.pdf" });

  // no way back
  await rejects(upd(`UPDATE documents SET status = 'issued' WHERE id = $1`), /status cannot change/);
  await rejects(upd(`UPDATE documents SET status = 'draft' WHERE id = $1`), /status cannot change/);
  await rejects(upd(`UPDATE documents SET status = 'canceled' WHERE id = $1`), /status cannot change/);
});

test("a locked document cannot be deleted by anyone", async () => {
  const d = await create(C, payload(81));
  const del = await as(C, () => db.query(`DELETE FROM documents WHERE id = $1`, [d.id]));
  assert.equal(del.affectedRows, 0); // RLS: only unlocked drafts are deletable
  await rejects(db.query(`DELETE FROM documents WHERE id = $1`, [d.id]), /GoBD-locked/); // trigger, even for the owner role
});

test("another business cannot change a document's status", async () => {
  const d = await create(C, payload(82));
  const r = await as(B, () => db.query(`UPDATE documents SET status = 'paid' WHERE id = $1`, [d.id]));
  assert.equal(r.affectedRows, 0);
});

test("the insert guard rejects numbers the counter never issued", async () => {
  const ins = (number, type = "invoice") => db.query(
    `INSERT INTO documents (business_id, doc_type, doc_number, recipient_snapshot) VALUES ($1, $2, $3, '{"name":"x"}')`,
    [bizC, type, number]);
  await rejects(ins("RE-2026-9999"), /never issued/);
  await rejects(ins("RE-ABC"), /invalid document number/);
  await rejects(ins("ANG-2026-0001"), /does not match type/);
});

test("stored amounts must add up (check constraint)", async () => {
  const num = await asUser(C, async () => (await db.query(`SELECT get_next_document_number($1, 'invoice', 2031) AS n`, [bizC])).rows[0].n);
  await rejects(
    db.query(
      `INSERT INTO documents (business_id, doc_type, doc_number, recipient_snapshot, subtotal_labor_cents, total_net_cents)
       VALUES ($1, 'invoice', $2, '{"name":"x"}', 100, 999)`, [bizC, num]),
    /documents_amounts_check/,
  );
});

test("updated_at moves on update", async () => {
  const before = (await db.query(`SELECT updated_at FROM customers WHERE business_id = $1`, [bizA])).rows[0].updated_at;
  await new Promise((r) => setTimeout(r, 15));
  await as(A, () => db.query(`UPDATE customers SET city = 'Hamburg' WHERE business_id = $1`, [bizA]));
  const after = (await db.query(`SELECT updated_at FROM customers WHERE business_id = $1`, [bizA])).rows[0].updated_at;
  assert.ok(after > before);
});

test("storage: only the own business folder is readable/writable", async () => {
  await as(A, () => db.query(`INSERT INTO storage.objects (bucket_id, name) VALUES ('captures', $1)`, [`${bizA}/rec1.m4a`]));
  await rejects(
    as(A, () => db.query(`INSERT INTO storage.objects (bucket_id, name) VALUES ('captures', $1)`, [`${bizB}/rec1.m4a`])),
    /row-level security/,
  );
  await db.query(`INSERT INTO storage.objects (bucket_id, name) VALUES ('captures', $1)`, [`${bizB}/secret.m4a`]);
  const seen = await as(A, () => db.query(`SELECT name FROM storage.objects WHERE bucket_id = 'captures'`));
  assert.deepEqual(seen.rows.map((r) => r.name), [`${bizA}/rec1.m4a`]);
});

test("capture idempotency: the same client id cannot be logged twice in one business", async () => {
  const id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const ins = (biz, user) =>
    as(user, () => db.query(`INSERT INTO capture_logs (business_id, client_capture_id) VALUES ($1, $2)`, [biz, id]));
  await ins(bizA, A);
  await rejects(ins(bizA, A), /uq_capture_logs_client_capture/);
  // another business may reuse the same id (ids are only unique per business)
  await ins(bizB, B);
});

test("capture idempotency: logs without a client id are not restricted", async () => {
  const ins = () => as(A, () => db.query(`INSERT INTO capture_logs (business_id, raw_transcript) VALUES ($1, 'no key')`, [bizA]));
  await ins();
  await ins();
});

// ---- job notes: several notes per job, one document, no double billing --------------------

const D = "55555555-5555-4555-8555-555555555555"; // second worker in business C
let jobC, noteIds = [];
const addNote = (user, job, text) =>
  as(user, async () => (await db.query(
    `INSERT INTO capture_logs (business_id, job_id, raw_transcript, created_by)
     VALUES ($1, $2, $3, $4) RETURNING id`, [bizC, job, text, user])).rows[0].id);
const openNotes = (job) => db.query(
  `SELECT id, raw_transcript FROM capture_logs WHERE job_id = $1 AND document_id IS NULL AND discarded_at IS NULL ORDER BY created_at, id`, [job]);

test("job notes: setup with two workers and three notes on one job", async () => {
  await db.exec(`INSERT INTO auth.users VALUES ('${D}')`);
  await db.query(`INSERT INTO profiles (id, business_id, full_name, role) VALUES ($1, $2, 'Dirk', 'geselle')`, [D, bizC]);
  jobC = (await db.query(`INSERT INTO jobs (business_id, title) VALUES ($1, 'Schiller Bad') RETURNING id`, [bizC])).rows[0].id;
  await as(C, () => db.query(`SELECT set_job_assignees($1, ARRAY[$2]::uuid[])`, [jobC, D])); // Dirk works on this job
  noteIds = [await addNote(C, jobC, "Montag"), await addNote(D, jobC, "Dienstag"), await addNote(C, jobC, "Mittwoch")];
  assert.equal((await openNotes(jobC)).rows.length, 3);
});

test("job notes: a colleague can read the notes and sees who wrote them", async () => {
  const rows = await as(D, () => db.query(
    `SELECT c.raw_transcript, p.full_name FROM capture_logs c JOIN profiles p ON p.id = c.created_by WHERE c.job_id = $1 ORDER BY c.raw_transcript`, [jobC]));
  assert.deepEqual(rows.rows.map((r) => r.full_name).sort(), ["Carla C", "Carla C", "Dirk"]);
});

test("job notes: a note cannot be attributed to a colleague or created as already invoiced", async () => {
  await rejects(as(D, () => db.query(
    `INSERT INTO capture_logs (business_id, job_id, created_by) VALUES ($1, $2, $3)`, [bizC, jobC, C])), /row-level security/);
  await rejects(as(D, () => db.query(
    `INSERT INTO capture_logs (business_id, job_id, created_by, discarded_at) VALUES ($1, $2, $3, now())`, [bizC, jobC, D])), /row-level security/);
});

test("job notes: another business cannot discard a note", async () => {
  await rejects(as(B, () => db.query(`SELECT discard_capture_log($1)`, [noteIds[0]])), /not found|not allowed/);
  assert.equal((await openNotes(jobC)).rows.length, 3);
});

test("job notes: a colleague can discard a note; it disappears from the open list but stays logged", async () => {
  await as(D, () => db.query(`SELECT discard_capture_log($1)`, [noteIds[2]]));
  assert.deepEqual((await openNotes(jobC)).rows.map((r) => r.raw_transcript), ["Montag", "Dienstag"]);
  const kept = await db.query(`SELECT discarded_at FROM capture_logs WHERE id = $1`, [noteIds[2]]);
  assert.ok(kept.rows[0].discarded_at);
  await rejects(as(D, () => db.query(`SELECT discard_capture_log($1)`, [noteIds[2]])), /not found/);
});

test("job notes: create_document uses up exactly the notes it was given", async () => {
  const d = await create(C, payload(101, { job_id: jobC, capture_log_ids: [noteIds[0]] }));
  const used = await db.query(`SELECT id, document_id FROM capture_logs WHERE job_id = $1 ORDER BY raw_transcript`, [jobC]);
  const byId = Object.fromEntries(used.rows.map((r) => [r.id, r.document_id]));
  assert.equal(byId[noteIds[0]], d.id);   // given -> used up
  assert.equal(byId[noteIds[1]], null);   // not given -> still open
  assert.equal(byId[noteIds[2]], null);   // discarded -> untouched
  assert.deepEqual((await openNotes(jobC)).rows.map((r) => r.raw_transcript), ["Dienstag"]);
});

test("job notes: a used note cannot be discarded, and a retry does not change anything", async () => {
  await rejects(as(C, () => db.query(`SELECT discard_capture_log($1)`, [noteIds[0]])), /already invoiced|not found/);
  const again = await create(C, payload(101, { job_id: jobC, capture_log_ids: [noteIds[0], noteIds[1]] }));
  assert.equal(again.id, uuid(101));
  // the retry returned the stored document and did NOT grab the second note
  assert.deepEqual((await openNotes(jobC)).rows.map((r) => r.raw_transcript), ["Dienstag"]);
});

test("job notes: notes of another job or business are not touched", async () => {
  const otherJob = (await db.query(`INSERT INTO jobs (business_id, title) VALUES ($1, 'Anderer Auftrag') RETURNING id`, [bizC])).rows[0].id;
  const foreign = await addNote(C, otherJob, "gehört woanders hin");
  await create(C, payload(102, { job_id: jobC, capture_log_ids: [foreign, noteIds[1]] }));
  const rows = await db.query(`SELECT id, document_id FROM capture_logs WHERE id IN ($1, $2)`, [foreign, noteIds[1]]);
  const byId = Object.fromEntries(rows.rows.map((r) => [r.id, r.document_id]));
  assert.equal(byId[foreign], null);
  assert.equal(byId[noteIds[1]], uuid(102));
});

test("job notes: a document without a job ignores capture_log_ids", async () => {
  const n = await addNote(C, jobC, "neu");
  await create(C, payload(103, { capture_log_ids: [n] }));
  const row = await db.query(`SELECT document_id FROM capture_logs WHERE id = $1`, [n]);
  assert.equal(row.rows[0].document_id, null);
});

// ---- teams: roles, assignments, visibility, invitations, seats -----------------------------

const E = "66666666-6666-4666-8666-666666666666"; // office (buero) in business C
const F = "77777777-7777-4777-8777-777777777777"; // second employee in business C
const G = "88888888-8888-4888-8888-888888888888"; // newcomer without a business
const H = "99999999-9999-4999-8999-999999999999"; // second newcomer
let jobX, jobY, custX, custY;
const one = async (user, sql, params = []) => (await as(user, () => db.query(sql, params))).rows;
const ids = (rows) => rows.map((r) => r.id).sort();

test("team: setup (an office person, two employees, two jobs with customers)", async () => {
  for (const u of [E, F, G, H]) await db.exec(`INSERT INTO auth.users VALUES ('${u}')`);
  await db.query(`INSERT INTO profiles (id, business_id, full_name, role) VALUES ($1, $2, 'Elke Büro', 'buero'), ($3, $2, 'Frank', 'geselle')`, [E, bizC, F]);
  custX = (await db.query(`INSERT INTO customers (business_id, name) VALUES ($1, 'Kunde X') RETURNING id`, [bizC])).rows[0].id;
  custY = (await db.query(`INSERT INTO customers (business_id, name) VALUES ($1, 'Kunde Y') RETURNING id`, [bizC])).rows[0].id;
  jobX = (await db.query(`INSERT INTO jobs (business_id, customer_id, title) VALUES ($1, $2, 'Job X') RETURNING id`, [bizC, custX])).rows[0].id;
  jobY = (await db.query(`INSERT INTO jobs (business_id, customer_id, title) VALUES ($1, $2, 'Job Y') RETURNING id`, [bizC, custY])).rows[0].id;
  await as(C, () => db.query(`SELECT set_job_assignees($1, ARRAY[$2]::uuid[])`, [jobX, F]));
});

test("team: managers see every job; an employee sees only the jobs assigned to them", async () => {
  const all = ids(await one(C, `SELECT id FROM jobs`));
  assert.ok(all.includes(jobX) && all.includes(jobY));
  assert.deepEqual(ids(await one(E, `SELECT id FROM jobs WHERE id IN ($1, $2)`, [jobX, jobY])), ids([{ id: jobX }, { id: jobY }]));
  assert.deepEqual(await one(F, `SELECT id FROM jobs WHERE id IN ($1, $2)`, [jobX, jobY]), [{ id: jobX }]);
});

test("team: an employee cannot touch a job that is not theirs", async () => {
  const upd = await as(F, () => db.query(`UPDATE jobs SET title = 'gehackt' WHERE id = $1`, [jobY]));
  assert.equal(upd.affectedRows, 0);
  const del = await as(F, () => db.query(`DELETE FROM jobs WHERE id = $1`, [jobY]));
  assert.equal(del.affectedRows, 0);
  await rejects(addNote(F, jobY, "fremder Auftrag"), /row-level security/);
});

test("team: customers - an employee sees those of their jobs, not the others", async () => {
  assert.deepEqual(await one(F, `SELECT id FROM customers WHERE id IN ($1, $2)`, [custX, custY]), [{ id: custX }]);
  assert.equal((await one(E, `SELECT id FROM customers WHERE id IN ($1, $2)`, [custX, custY])).length, 2);
});

test("team: (setup) the owner allows employees to create customers and jobs", async () => {
  await db.query(`UPDATE businesses SET employees_can_create = true WHERE id = $1`, [bizC]);
});

test("team: an employee sees the customers they created themselves", async () => {
  const mine = (await one(F, `INSERT INTO customers (business_id, name) VALUES ($1, 'Frank Kunde') RETURNING id, created_by`, [bizC]))[0];
  assert.equal(mine.created_by, F);
  assert.equal((await one(F, `SELECT id FROM customers WHERE id = $1`, [mine.id])).length, 1);
  assert.equal((await one(D, `SELECT id FROM customers WHERE id = $1`, [mine.id])).length, 0); // not on Dirks jobs
  assert.equal((await one(C, `SELECT id FROM customers WHERE id = $1`, [mine.id])).length, 1);
});

test("team: a job created by an employee is assigned to them at once; the boss sees it too", async () => {
  // like the app does it: an upsert without RETURNING (the assignment is made by a trigger after the insert)
  const j = uuid(301);
  await as(F, () => db.query(`INSERT INTO jobs (id, business_id, title) VALUES ($1, $2, 'Frank im Feld')`, [j, bizC]));
  assert.equal((await one(F, `SELECT id FROM jobs WHERE id = $1`, [j])).length, 1);
  assert.equal((await one(D, `SELECT id FROM jobs WHERE id = $1`, [j])).length, 0);
  assert.equal((await one(C, `SELECT id FROM jobs WHERE id = $1`, [j])).length, 1);
});

test("team: (setup) back to the default: employees may not create", async () => {
  await db.query(`UPDATE businesses SET employees_can_create = false WHERE id = $1`, [bizC]);
});

test("team: assigning is for managers; only active colleagues of the same business can be assigned", async () => {
  await rejects(as(F, () => db.query(`SELECT set_job_assignees($1, ARRAY[$2]::uuid[])`, [jobX, F])), /not allowed/);
  await rejects(as(C, () => db.query(`SELECT set_job_assignees($1, ARRAY[$2]::uuid[])`, [jobX, A])), /person not found/); // another business
  await rejects(as(B, () => db.query(`SELECT set_job_assignees($1, ARRAY[$2]::uuid[])`, [jobX, B])), /job not found|not allowed/);
  await as(E, () => db.query(`SELECT set_job_assignees($1, ARRAY[$2, $3]::uuid[])`, [jobY, D, F])); // the office may assign
  assert.equal((await one(D, `SELECT id FROM jobs WHERE id = $1`, [jobY])).length, 1);
});

test("team: unassigning takes the job away again; the list is replaced, not added to", async () => {
  await as(C, () => db.query(`SELECT set_job_assignees($1, ARRAY[$2]::uuid[])`, [jobY, D]));
  assert.equal((await one(F, `SELECT id FROM jobs WHERE id = $1`, [jobY])).length, 0);
  assert.equal((await one(D, `SELECT id FROM jobs WHERE id = $1`, [jobY])).length, 1);
  await as(C, () => db.query(`SELECT set_job_assignees($1, ARRAY[]::uuid[])`, [jobY]));
  assert.equal((await one(D, `SELECT id FROM jobs WHERE id = $1`, [jobY])).length, 0);
});

test("team: assigning refreshes updated_at of the job and its customer, so the phone picks them up", async () => {
  const before = (await db.query(`SELECT j.updated_at AS j, c.updated_at AS c FROM jobs j JOIN customers c ON c.id = j.customer_id WHERE j.id = $1`, [jobY])).rows[0];
  await db.query(`SELECT pg_sleep(0.01)`);
  await as(C, () => db.query(`SELECT set_job_assignees($1, ARRAY[$2]::uuid[])`, [jobY, D]));
  const after = (await db.query(`SELECT j.updated_at AS j, c.updated_at AS c FROM jobs j JOIN customers c ON c.id = j.customer_id WHERE j.id = $1`, [jobY])).rows[0];
  assert.ok(after.j > before.j && after.c > before.c);
});

test("team: an employee sees only their own assignments; managers see all", async () => {
  const mine = await one(D, `SELECT user_id FROM job_assignments`);
  assert.ok(mine.length > 0 && mine.every((r) => r.user_id === D));
  assert.ok((await one(C, `SELECT DISTINCT user_id FROM job_assignments`)).length > 1);
  await rejects(as(D, () => db.query(`INSERT INTO job_assignments (job_id, user_id, business_id) VALUES ($1, $2, $3)`, [jobX, D, bizC])), /row-level security/);
});

test("team: notes follow the job - an employee cannot read notes of other jobs", async () => {
  const n = await addNote(C, jobX, "nur für Frank");
  assert.equal((await one(F, `SELECT id FROM capture_logs WHERE id = $1`, [n])).length, 1);
  assert.equal((await one(D, `SELECT id FROM capture_logs WHERE id = $1`, [n])).length, 0);
  await rejects(as(D, () => db.query(`SELECT discard_capture_log($1)`, [n])), /not found/);
});

test("team: documents are for boss and office only", async () => {
  await create(C, payload(201));
  assert.ok((await one(C, `SELECT id FROM documents`)).length > 0);
  assert.ok((await one(E, `SELECT id FROM documents`)).length > 0);
  assert.equal((await one(F, `SELECT id FROM documents`)).length, 0);
  assert.equal((await one(D, `SELECT id FROM documents`)).length, 0);
  await rejects(create(F, payload(202)), /not allowed/);
  const upd = await as(F, () => db.query(`UPDATE documents SET status = 'paid'`));
  assert.equal(upd.affectedRows, 0);
  const d = await create(E, payload(203)); // the office may issue
  assert.match(d.doc_number, /^RE-/);
});

test("team: PDFs and other peoples recordings are protected in storage", async () => {
  // recordings live at <business>/<user>/<note>.m4a
  await db.query(`INSERT INTO storage.objects (bucket_id, name) VALUES ('documents', $1), ('captures', $2), ('captures', $3)`,
    [`${bizC}/RE-1.pdf`, `${bizC}/${F}/mine.m4a`, `${bizC}/${D}/dirks.m4a`]);
  const names = async (u, bucket) => (await one(u, `SELECT name FROM storage.objects WHERE bucket_id = $1 ORDER BY name`, [bucket])).map((r) => r.name);
  assert.deepEqual(await names(C, "documents"), [`${bizC}/RE-1.pdf`]);
  assert.deepEqual(await names(F, "documents"), []);
  assert.deepEqual(await names(F, "captures"), [`${bizC}/${F}/mine.m4a`]);  // only the own recording
  assert.equal((await names(C, "captures")).length, 2);                  // the boss hears everything
  await rejects(as(F, () => db.query(`INSERT INTO storage.objects (bucket_id, name) VALUES ('documents', $1)`, [`${bizC}/fake.pdf`])), /row-level security/);
  // uploading a recording into the business folder is allowed
  await as(F, () => db.query(`INSERT INTO storage.objects (bucket_id, name) VALUES ('captures', $1)`, [`${bizC}/${F}/neu.m4a`]));
});

// ---- plans, invitations, switching people off

test("plan: new businesses start with one seat; clients cannot change the plan", async () => {
  const lim = (await db.query(`SELECT seat_limit FROM businesses WHERE id = $1`, [bizA])).rows[0].seat_limit;
  assert.equal(lim, 1);
  await rejects(as(A, () => db.query(`UPDATE businesses SET seat_limit = 50 WHERE id = $1`, [bizA])), /plan cannot be changed/);
  await db.query(`UPDATE businesses SET seat_limit = 1 WHERE id = $1`, [bizA]); // the server side may
});

test("invites: only the owner; the seat limit counts people and open invitations", async () => {
  await db.query(`UPDATE businesses SET seat_limit = 4 WHERE id = $1`, [bizC]); // C, D, E, F are active already
  await rejects(as(C, () => db.query(`SELECT create_invite('geselle')`)), /no free seat/);
  await db.query(`UPDATE businesses SET seat_limit = 6 WHERE id = $1`, [bizC]);
  await rejects(as(E, () => db.query(`SELECT create_invite('geselle')`)), /not allowed/);   // office: no
  await rejects(as(F, () => db.query(`SELECT create_invite('geselle')`)), /not allowed/);   // employee: no
  await rejects(as(C, () => db.query(`SELECT create_invite('owner')`)), /invalid role/);
  const inv = (await one(C, `SELECT create_invite('geselle') AS i`))[0].i;
  assert.match(inv.code, /^[A-HJ-NP-Z2-9]{8}$/);
  assert.equal(inv.role, "geselle");
  await as(C, () => db.query(`SELECT create_invite('buero')`)); // the second open invitation fills the last seat
  await rejects(as(C, () => db.query(`SELECT create_invite('geselle')`)), /no free seat/);
});

test("invites: only the owner can list them", async () => {
  assert.ok((await one(C, `SELECT id FROM invites`)).length >= 2);
  assert.equal((await one(E, `SELECT id FROM invites`)).length, 0);
  assert.equal((await one(F, `SELECT id FROM invites`)).length, 0);
  assert.equal((await one(B, `SELECT id FROM invites`)).length, 0);
  await rejects(as(C, () => db.query(`INSERT INTO invites (business_id, code, role, expires_at) VALUES ($1, 'ZZZZZZZZ', 'geselle', now() + interval '1 day')`, [bizC])), /row-level security/);
});

test("join: a new person joins with the code and gets the invited role; the code works once", async () => {
  const code = (await db.query(`SELECT code FROM invites WHERE business_id = $1 AND role = 'geselle' AND used_at IS NULL LIMIT 1`, [bizC])).rows[0].code;
  await rejects(as(G, () => db.query(`SELECT join_business($1, '  ')`, [code])), /name is required/);
  const biz = (await one(G, `SELECT join_business($1, 'Gerd Neu') AS b`, [code.toLowerCase()]))[0].b; // case does not matter
  assert.equal(biz, bizC);
  const p = (await db.query(`SELECT role, active, full_name FROM profiles WHERE id = $1`, [G])).rows[0];
  assert.deepEqual(p, { role: "geselle", active: true, full_name: "Gerd Neu" });
  await rejects(as(H, () => db.query(`SELECT join_business($1, 'Hans')`, [code])), /invalid invitation/); // used
  // the new employee sees no jobs until assigned
  assert.equal((await one(G, `SELECT id FROM jobs WHERE business_id = $1`, [bizC])).length, 0);
});

test("join: unknown, expired and revoked codes all fail with the same message; members cannot join a second business", async () => {
  await rejects(as(H, () => db.query(`SELECT join_business('NOSUCHCD', 'Hans')`)), /invalid invitation/);
  const open = (await db.query(`SELECT id, code FROM invites WHERE business_id = $1 AND used_at IS NULL AND revoked_at IS NULL`, [bizC])).rows[0];
  await db.query(`UPDATE invites SET expires_at = now() - interval '1 minute' WHERE id = $1`, [open.id]);
  await rejects(as(H, () => db.query(`SELECT join_business($1, 'Hans')`, [open.code])), /invalid invitation/);
  await db.query(`UPDATE invites SET expires_at = now() + interval '1 day' WHERE id = $1`, [open.id]);
  await rejects(as(F, () => db.query(`SELECT revoke_invite($1)`, [open.id])), /not allowed/);
  await as(C, () => db.query(`SELECT revoke_invite($1)`, [open.id]));
  await rejects(as(H, () => db.query(`SELECT join_business($1, 'Hans')`, [open.code])), /invalid invitation/);
  await rejects(as(F, () => db.query(`SELECT join_business('ABCDEFGH', 'Frank')`)), /already belongs/);
});

test("join: the seat limit is checked again when the code is used", async () => {
  // active now: C, D, E, F, G = 5
  await db.query(`UPDATE businesses SET seat_limit = 6 WHERE id = $1`, [bizC]);
  const inv = (await one(C, `SELECT create_invite('meister') AS i`))[0].i;
  await db.query(`UPDATE businesses SET seat_limit = 5 WHERE id = $1`, [bizC]); // the plan was reduced meanwhile
  await rejects(as(H, () => db.query(`SELECT join_business($1, 'Hans')`, [inv.code])), /no free seat/);
  await db.query(`UPDATE businesses SET seat_limit = 6 WHERE id = $1`, [bizC]);
  await as(H, () => db.query(`SELECT join_business($1, 'Hans')`, [inv.code]));
  assert.equal((await db.query(`SELECT role FROM profiles WHERE id = $1`, [H])).rows[0].role, "meister");
});

test("switching off: the person loses all access at once, but their notes stay", async () => {
  const own = await addNote(F, jobX, "Franks letzte Notiz");
  await rejects(as(F, () => db.query(`SELECT set_member_active($1, false)`, [D])), /not allowed/); // employee: no
  await as(C, () => db.query(`SELECT set_member_active($1, false)`, [F]));

  assert.equal((await one(F, `SELECT id FROM jobs`)).length, 0);
  assert.equal((await one(F, `SELECT id FROM customers`)).length, 0);
  assert.equal((await one(F, `SELECT id FROM capture_logs`)).length, 0);
  await rejects(addNote(F, jobX, "heimlich"), /row-level security/);
  // ...but they can still read their own profile, so the app can say why
  const me = await one(F, `SELECT active FROM profiles WHERE id = $1`, [F]);
  assert.deepEqual(me, [{ active: false }]);
  // the notes stay for the boss
  assert.equal((await one(C, `SELECT id FROM capture_logs WHERE id = $1`, [own])).length, 1);
});

test("switching off: not the owner, not yourself, not another business; no direct update by clients", async () => {
  await rejects(as(C, () => db.query(`SELECT set_member_active($1, false)`, [C])), /owner cannot be switched off/);
  await rejects(as(C, () => db.query(`SELECT set_member_active($1, false)`, [A])), /person not found/);
  await rejects(as(C, () => db.query(`UPDATE profiles SET active = false WHERE id = $1`, [D])), /set_member_active/);
});

test("switching on again needs a free seat, and a switched-off person is not counted", async () => {
  // active: C, D, E, G, H = 5 of 6, F is off
  await as(C, () => db.query(`SELECT set_member_active($1, true)`, [F]));            // 6 of 6
  await rejects(as(C, () => db.query(`SELECT create_invite('geselle')`)), /no free seat/);
  await as(C, () => db.query(`SELECT set_member_active($1, false)`, [F]));           // 5 of 6
  await as(C, () => db.query(`SELECT create_invite('geselle')`));                    // a seat is free again
  await rejects(as(C, () => db.query(`SELECT set_member_active($1, true)`, [F])), /no free seat/); // the open invitation holds it
});

// ---- leaving: the account belongs to the person, the link to the business can be ended ------

const J = "aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa"; // registered, never joined anything

test("leaving: a note keeps its author's name, even after the person is gone", async () => {
  await db.query(`UPDATE businesses SET seat_limit = 10 WHERE id = $1`, [bizC]);
  await as(C, () => db.query(`SELECT set_job_assignees($1, ARRAY[$2]::uuid[])`, [jobX, G]));
  const n = await addNote(G, jobX, "Gerds Notiz");
  const row = (await db.query(`SELECT created_by_name FROM capture_logs WHERE id = $1`, [n])).rows[0];
  assert.equal(row.created_by_name, "Gerd Neu"); // set by the database, not by the client
  noteIds.push(n);
});

test("leaving: only the owner can remove people - not the office, not an employee", async () => {
  await rejects(as(E, () => db.query(`SELECT remove_member($1)`, [G])), /not allowed/);
  await rejects(as(F, () => db.query(`SELECT remove_member($1)`, [G])), /not allowed/);
  await rejects(as(C, () => db.query(`SELECT remove_member($1)`, [C])), /owner cannot be removed/);
  await rejects(as(C, () => db.query(`SELECT remove_member($1)`, [A])), /person not found/); // other business
});

test("leaving: removal ends every link; the person keeps the account; their notes stay", async () => {
  const before = (await db.query(`SELECT seats_in_use($1) AS n`, [bizC])).rows[0].n;
  await as(C, () => db.query(`SELECT remove_member($1)`, [G]));

  assert.equal((await db.query(`SELECT 1 FROM profiles WHERE id = $1`, [G])).rows.length, 0); // no link
  assert.equal((await db.query(`SELECT 1 FROM job_assignments WHERE user_id = $1`, [G])).rows.length, 0);
  assert.equal((await db.query(`SELECT 1 FROM auth.users WHERE id = $1`, [G])).rows.length, 1); // the account stays
  assert.equal((await one(G, `SELECT id FROM jobs`)).length, 0);
  assert.equal((await one(G, `SELECT id FROM customers`)).length, 0);
  assert.equal((await one(G, `SELECT id FROM capture_logs`)).length, 0);
  assert.equal((await db.query(`SELECT seats_in_use($1) AS n`, [bizC])).rows[0].n, before - 1);

  const note = (await db.query(`SELECT created_by, created_by_name FROM capture_logs WHERE id = $1`, [noteIds.at(-1)])).rows[0];
  assert.deepEqual(note, { created_by: null, created_by_name: "Gerd Neu" }); // work record kept, with the name
  assert.equal((await one(C, `SELECT id FROM capture_logs WHERE id = $1`, [noteIds.at(-1)])).length, 1);
});

test("leaving: a removed person can go solo with their own business, completely separate", async () => {
  const biz = (await one(G, `SELECT create_business_for_user('Gerd Solo', 'Gerd Neu') AS id`))[0].id;
  assert.notEqual(biz, bizC);
  assert.equal((await db.query(`SELECT role FROM profiles WHERE id = $1`, [G])).rows[0].role, "owner");
  assert.equal((await db.query(`SELECT seat_limit FROM businesses WHERE id = $1`, [biz])).rows[0].seat_limit, 1);
  // still sees nothing of the old business
  assert.equal((await one(G, `SELECT id FROM jobs WHERE business_id = $1`, [bizC])).length, 0);
});

test("leaving: or join another business with an invitation", async () => {
  await as(C, () => db.query(`SELECT remove_member($1)`, [H]));
  await db.query(`UPDATE businesses SET seat_limit = 3 WHERE id = $1`, [bizA]);
  const inv = (await one(A, `SELECT create_invite('geselle') AS i`))[0].i;
  assert.equal((await one(H, `SELECT join_business($1, 'Hans')  AS b`, [inv.code]))[0].b, bizA);
});

test("leaving: an employee can leave on their own; the owner cannot", async () => {
  await rejects(as(C, () => db.query(`SELECT leave_business()`)), /owner cannot leave/);
  await rejects(as(J, () => db.query(`SELECT leave_business()`)), /not a member/);
  await as(D, () => db.query(`SELECT leave_business()`));
  assert.equal((await db.query(`SELECT 1 FROM profiles WHERE id = $1`, [D])).rows.length, 0);
  assert.equal((await one(D, `SELECT id FROM jobs`)).length, 0);
});

test("deleting the account: an employee erases it completely, notes stay without a live link", async () => {
  await as(C, () => db.query(`SELECT set_member_active($1, true)`, [F]));
  await as(C, () => db.query(`SELECT set_job_assignees($1, ARRAY[$2]::uuid[])`, [jobX, F]));
  const n = await addNote(F, jobX, "Franks Notiz vor dem Löschen");
  await as(F, () => db.query(`SELECT delete_my_account()`));

  assert.equal((await db.query(`SELECT 1 FROM auth.users WHERE id = $1`, [F])).rows.length, 0);
  assert.equal((await db.query(`SELECT 1 FROM profiles WHERE id = $1`, [F])).rows.length, 0);
  const note = (await db.query(`SELECT created_by, created_by_name FROM capture_logs WHERE id = $1`, [n])).rows[0];
  assert.equal(note.created_by, null);
  assert.equal(note.created_by_name, "Frank");
});

test("deleting the account: someone who never joined a business can erase it; an owner cannot", async () => {
  await db.exec(`INSERT INTO auth.users VALUES ('${J}')`);
  await as(J, () => db.query(`SELECT delete_my_account()`));
  assert.equal((await db.query(`SELECT 1 FROM auth.users WHERE id = $1`, [J])).rows.length, 0);
  await rejects(as(C, () => db.query(`SELECT delete_my_account()`)), /owner cannot delete/);
  assert.equal((await db.query(`SELECT 1 FROM profiles WHERE id = $1`, [C])).rows.length, 1);
});

test("leaving: nobody can call these functions without being logged in", async () => {
  await rejects(db.query(`SELECT remove_member($1)`, [D]), /not allowed/);
  await rejects(db.query(`SELECT leave_business()`), /not authenticated/);
  await rejects(db.query(`SELECT delete_my_account()`), /not authenticated/);
});

// ---- function privileges (Supabase grants EXECUTE to anon/authenticated by default) -------------

const asAnon = async (fn) => {
  await db.exec(`SET ROLE anon;`);
  try { return await fn(); } finally { await db.exec(`RESET ROLE;`); }
};

test("privileges: a person who is not logged in can call none of our functions", async () => {
  for (const sql of [
    `SELECT create_business_for_user('X', 'Y')`,
    `SELECT create_invite('geselle')`,
    `SELECT join_business('ABCDEFGH', 'X')`,
    `SELECT is_manager()`,
    `SELECT get_user_business_id()`,
    `SELECT leave_business()`,
    `SELECT delete_my_account()`,
  ]) {
    await rejects(asAnon(() => db.query(sql)), /permission denied for function/);
  }
});

test("privileges: logged-in clients cannot call internal helpers, e.g. ask about another business's seats", async () => {
  for (const sql of [
    `SELECT seats_in_use('${bizC}')`,
    `SELECT new_invite_code()`,
    `SELECT get_next_document_number('${bizC}', 'invoice', 2026)`,
  ]) {
    await rejects(as(B, () => db.query(sql)), /permission denied for function/);
  }
});

test("privileges: the functions meant for the app are still callable by logged-in people", async () => {
  assert.equal((await one(C, `SELECT is_manager() AS m`))[0].m, true);
  assert.equal((await one(F, `SELECT is_manager() AS m`))[0].m, false);
});

const W = "aaaaaaa1-0000-4000-8000-000000000001"; // employee, only for the tests below
const W2 = "aaaaaaa2-0000-4000-8000-000000000002"; // second employee
const M = "aaaaaaa3-0000-4000-8000-000000000003"; // office

test("setup for the calendar and time tests: two employees and an office person in business C", async () => {
  for (const u of [W, W2, M]) await db.exec(`INSERT INTO auth.users VALUES ('${u}')`);
  await db.query(
    `INSERT INTO profiles (id, business_id, full_name, role) VALUES ($1, $4, 'Frank', 'geselle'), ($2, $4, 'Dirk Zwei', 'geselle'), ($3, $4, 'Elke Zwei', 'buero')`,
    [W, W2, M, bizC]);
});

// ---- employees may create only when the owner allows it -------------------------------------

test("employees_can_create: off by default, only the owner can switch it on", async () => {
  await rejects(one(W, `INSERT INTO customers (business_id, name) VALUES ($1, 'Nicht erlaubt')`, [bizC]), /row-level security/);
  await rejects(as(M, () => db.query(`UPDATE businesses SET employees_can_create = true WHERE id = $1`, [bizC])), /only the owner/);
  await as(C, () => db.query(`UPDATE businesses SET employees_can_create = true WHERE id = $1`, [bizC]));
  await one(W, `INSERT INTO customers (business_id, name) VALUES ($1, 'Jetzt erlaubt')`, [bizC]);
  await as(C, () => db.query(`UPDATE businesses SET employees_can_create = false WHERE id = $1`, [bizC]));
});

// ---- customers: merging --------------------------------------------------------------------

test("customer merge: a customer is marked as merged into another, never into itself", async () => {
  const a = (await db.query(`INSERT INTO customers (business_id, name) VALUES ($1, 'Merge A') RETURNING id`, [bizC])).rows[0].id;
  const b = (await db.query(`INSERT INTO customers (business_id, name) VALUES ($1, 'Merge B') RETURNING id`, [bizC])).rows[0].id;
  await as(C, () => db.query(`UPDATE customers SET merged_into = $2 WHERE id = $1`, [b, a]));
  assert.equal((await db.query(`SELECT merged_into FROM customers WHERE id = $1`, [b])).rows[0].merged_into, a);
  await rejects(as(C, () => db.query(`UPDATE customers SET merged_into = id WHERE id = $1`, [a])), /customers_not_merged_into_self/);
});

// ---- jobs: when was it closed, and what that means for recordings ---------------------------

test("jobs.closed_at: set when the job is closed, kept when it goes from completed to invoiced, cleared when reopened", async () => {
  const j = (await db.query(`INSERT INTO jobs (business_id, title) VALUES ($1, 'Closing') RETURNING id`, [bizC])).rows[0].id;
  const closedAt = async () => (await db.query(`SELECT closed_at FROM jobs WHERE id = $1`, [j])).rows[0].closed_at;
  assert.equal(await closedAt(), null);
  await db.query(`UPDATE jobs SET status = 'completed' WHERE id = $1`, [j]);
  const first = await closedAt();
  assert.ok(first);
  await db.query(`SELECT pg_sleep(0.05)`);
  await db.query(`UPDATE jobs SET status = 'invoiced' WHERE id = $1`, [j]);
  assert.equal((await closedAt()).getTime(), first.getTime());
  await db.query(`UPDATE jobs SET status = 'in_progress' WHERE id = $1`, [j]);
  assert.equal(await closedAt(), null);
});

test("recording retention: due 90 days after the job closed (or the shorter period the business chose), never longer than 90", async () => {
  const j = (await db.query(`INSERT INTO jobs (business_id, title, status) VALUES ($1, 'Retention', 'completed') RETURNING id`, [bizC])).rows[0].id;
  const c = (await db.query(
    `INSERT INTO capture_logs (business_id, job_id, audio_storage_path) VALUES ($1, $2, $3) RETURNING id`, [bizC, j, `${bizC}/x/r.m4a`])).rows[0].id;
  const due = async () => (await db.query(`SELECT id FROM recordings_due_for_deletion(1000) WHERE id = $1`, [c])).rows.length;
  assert.equal(await due(), 0); // just closed
  await db.query(`UPDATE jobs SET closed_at = NOW() - interval '89 days' WHERE id = $1`, [j]);
  assert.equal(await due(), 0);
  await db.query(`UPDATE jobs SET closed_at = NOW() - interval '91 days' WHERE id = $1`, [j]);
  assert.equal(await due(), 1);
  await db.query(`SELECT mark_recordings_deleted(ARRAY[$1]::uuid[])`, [c]);
  assert.equal(await due(), 0); // marked: not listed again
  assert.ok((await db.query(`SELECT audio_deleted_at FROM capture_logs WHERE id = $1`, [c])).rows[0].audio_deleted_at);

  await db.query(`UPDATE businesses SET recording_retention_days = 30 WHERE id = $1`, [bizC]);
  const c2 = (await db.query(
    `INSERT INTO capture_logs (business_id, job_id, audio_storage_path) VALUES ($1, $2, $3) RETURNING id`, [bizC, j, `${bizC}/x/r2.m4a`])).rows[0].id;
  await db.query(`UPDATE jobs SET closed_at = NOW() - interval '31 days' WHERE id = $1`, [j]);
  assert.equal((await db.query(`SELECT id FROM recordings_due_for_deletion(1000) WHERE id = $1`, [c2])).rows.length, 1);
  await rejects(db.query(`UPDATE businesses SET recording_retention_days = 365 WHERE id = $1`, [bizC]), /recording_retention_days/);
  await db.query(`UPDATE businesses SET recording_retention_days = 90 WHERE id = $1`, [bizC]);
});

test("recording retention: the purge functions are for the server only", async () => {
  await rejects(as(C, () => db.query(`SELECT * FROM recordings_due_for_deletion(10)`)), /permission denied/);
  await rejects(as(C, () => db.query(`SELECT mark_recordings_deleted(ARRAY[]::uuid[])`)), /permission denied/);
});

// ---- documents: the e-invoice flag ---------------------------------------------------------

test("e-invoice: the choice is stored with an invoice, never with a quote, and a cancellation copies it", async () => {
  const inv = await create(C, payload(401, { e_invoice: true }));
  assert.equal(inv.e_invoice, true);
  const plain = await create(C, payload(402));
  assert.equal(plain.e_invoice, false);
  const quote = await create(C, payload(403, { doc_type: "quote", e_invoice: true }));
  assert.equal(quote.e_invoice, false);
  const cancel = await as(C, async () =>
    (await db.query(`SELECT cancel_document($1::jsonb) AS d`, [JSON.stringify({ id: uuid(404), original_id: uuid(401) })])).rows[0].d);
  assert.equal(cancel.cancellation.e_invoice, true);
  assert.equal(cancel.cancellation.doc_type, "cancellation");
  // frozen with the document
  await rejects(db.query(`UPDATE documents SET e_invoice = true WHERE id = $1`, [uuid(402)]), /GoBD-locked/);
});

// ---- appointments ---------------------------------------------------------------------------

let apptX, apptC;

test("appointments: the boss plans one for an employee; the employee, the office and the boss see it, nobody else", async () => {
  apptX = uuid(501);
  await as(C, () => db.query(
    `INSERT INTO appointments (id, business_id, job_id, title, starts_at, ends_at, assignee_ids)
     VALUES ($1, $2, $3, 'Frank kommt', NOW() + interval '1 day', NOW() + interval '1 day 2 hours', ARRAY[$4]::uuid[])`, [apptX, bizC, jobY, W]));
  apptC = uuid(502);
  await as(C, () => db.query(
    `INSERT INTO appointments (id, business_id, title, starts_at, ends_at, assignee_ids)
     VALUES ($1, $2, 'Nur Chef', NOW() + interval '2 day', NOW() + interval '2 day 1 hour', ARRAY[$3]::uuid[])`, [apptC, bizC, C]));
  const see = async (u) => ids(await one(u, `SELECT id FROM appointments WHERE id IN ($1, $2)`, [apptX, apptC]));
  assert.deepEqual(await see(C), ids([{ id: apptX }, { id: apptC }]));
  assert.deepEqual(await see(M), ids([{ id: apptX }, { id: apptC }]));
  assert.deepEqual(await see(W), [apptX]);
  assert.deepEqual(await see(W2), []);
  assert.deepEqual(await see(B), []); // another business
});

test("appointments: the person on it is assigned to the job at once and can open it", async () => {
  assert.equal((await one(W, `SELECT id FROM jobs WHERE id = $1`, [jobY])).length, 1);
});

test("appointments: an employee cannot change or delete one; marking it done goes through set_appointment_status", async () => {
  assert.equal((await as(W, () => db.query(`UPDATE appointments SET title = 'gehackt' WHERE id = $1`, [apptX]))).affectedRows, 0);
  assert.equal((await as(W, () => db.query(`DELETE FROM appointments WHERE id = $1`, [apptX]))).affectedRows, 0);
  await one(W, `SELECT set_appointment_status($1, 'done')`, [apptX]);
  assert.equal((await db.query(`SELECT status FROM appointments WHERE id = $1`, [apptX])).rows[0].status, "done");
  await rejects(one(W, `SELECT set_appointment_status($1, 'canceled')`, [apptX]), /not allowed/);
  await rejects(one(W, `SELECT set_appointment_status($1, 'done')`, [apptC]), /not found/);
  await rejects(one(W, `SELECT set_appointment_status($1, 'bogus')`, [apptX]), /invalid status/);
});

test("appointments: people and jobs must belong to the business; the end must follow the start", async () => {
  const ins = (extra) => as(C, () => db.query(
    `INSERT INTO appointments (business_id, title, starts_at, ends_at, assignee_ids) VALUES ($1, 'x', ${extra})`, [bizC]));
  await rejects(ins(`NOW(), NOW() + interval '1 hour', ARRAY['${B}']::uuid[]`), /person not found/);
  await rejects(ins(`NOW(), NOW(), ARRAY[]::uuid[]`), /check/);
  await rejects(ins(`NOW(), NOW() + interval '32 days', ARRAY[]::uuid[]`), /check/);
});

test("appointments: an employee may plan only for themselves, and only if the owner allowed it", async () => {
  const mine = (who) => one(W, `INSERT INTO appointments (business_id, title, starts_at, ends_at, assignee_ids) VALUES ($1, 'selbst', NOW(), NOW() + interval '1 hour', ARRAY[$2]::uuid[])`, [bizC, who]);
  await rejects(mine(W), /row-level security/); // switch off
  await as(C, () => db.query(`UPDATE businesses SET employees_can_create = true WHERE id = $1`, [bizC]));
  await mine(W);
  await rejects(mine(W2), /row-level security/); // not for a colleague
  await as(C, () => db.query(`UPDATE businesses SET employees_can_create = false WHERE id = $1`, [bizC]));
});

test("appointments: the job and customer links are dropped, not the appointment, when they are deleted", async () => {
  const j = (await db.query(`INSERT INTO jobs (business_id, title) VALUES ($1, 'Wird gelöscht') RETURNING id`, [bizC])).rows[0].id;
  const a = (await db.query(
    `INSERT INTO appointments (business_id, job_id, title, starts_at, ends_at) VALUES ($1, $2, 'bleibt', NOW(), NOW() + interval '1 hour') RETURNING id`, [bizC, j])).rows[0].id;
  await db.query(`DELETE FROM jobs WHERE id = $1`, [j]);
  const row = (await db.query(`SELECT job_id FROM appointments WHERE id = $1`, [a])).rows[0];
  assert.equal(row.job_id, null);
});

// ---- working time ----------------------------------------------------------------------------

let jobT, entryF1, entryF2, entryC1;

test("time entries: an employee logs time on a job they can open; the name is stored; one running timer each", async () => {
  jobT = (await db.query(`INSERT INTO jobs (business_id, title) VALUES ($1, 'Zeitjob') RETURNING id`, [bizC])).rows[0].id;
  await as(C, () => db.query(`SELECT set_job_assignees($1, ARRAY[$2]::uuid[])`, [jobT, W]));
  entryF1 = uuid(601);
  await one(W, `INSERT INTO time_entries (id, business_id, user_id, job_id, started_at) VALUES ($1, $2, $3, $4, NOW() - interval '2 hours')`, [entryF1, bizC, W, jobT]);
  assert.equal((await db.query(`SELECT user_name FROM time_entries WHERE id = $1`, [entryF1])).rows[0].user_name, "Frank");
  await rejects(one(W, `INSERT INTO time_entries (business_id, user_id, job_id, started_at) VALUES ($1, $2, $3, NOW())`, [bizC, W, jobT]), /uq_time_entries_running/);
  await one(W, `UPDATE time_entries SET ended_at = NOW() WHERE id = $1`, [entryF1]);
  assert.ok((await db.query(`SELECT ended_at FROM time_entries WHERE id = $1`, [entryF1])).rows[0].ended_at);
});

test("time entries: not for a job that is not theirs, not for someone else; length and break are checked", async () => {
  const foreign = (await db.query(`INSERT INTO jobs (business_id, title) VALUES ($1, 'Nicht zugewiesen') RETURNING id`, [bizC])).rows[0].id;
  await rejects(one(W, `INSERT INTO time_entries (business_id, user_id, job_id, started_at, ended_at) VALUES ($1, $2, $3, NOW() - interval '3 hours', NOW() - interval '2 hours')`, [bizC, W, foreign]), /row-level security/);
  await rejects(one(W, `INSERT INTO time_entries (business_id, user_id, job_id, started_at, ended_at) VALUES ($1, $2, $3, NOW() - interval '3 hours', NOW() - interval '2 hours')`, [bizC, C, jobT]), /row-level security/);
  await rejects(one(W, `UPDATE time_entries SET ended_at = started_at + interval '25 hours' WHERE id = $1`, [entryF1]), /check/);
  await rejects(one(W, `UPDATE time_entries SET break_minutes = 600 WHERE id = $1`, [entryF1]), /check/);
  await one(W, `UPDATE time_entries SET break_minutes = 15 WHERE id = $1`, [entryF1]);
});

test("time entries: the boss adds time for a worker; each worker sees only their own, the boss and office see all", async () => {
  entryF2 = uuid(602);
  entryC1 = uuid(603);
  await one(C, `INSERT INTO time_entries (id, business_id, user_id, job_id, started_at, ended_at) VALUES ($1, $2, $3, $4, NOW() - interval '30 hours', NOW() - interval '28 hours')`, [entryF2, bizC, W, jobT]);
  await one(C, `INSERT INTO time_entries (id, business_id, user_id, job_id, started_at, ended_at) VALUES ($1, $2, $3, $4, NOW() - interval '10 hours', NOW() - interval '9 hours')`, [entryC1, bizC, C, jobT]);
  const mine = async (u) => ids(await one(u, `SELECT id FROM time_entries WHERE id IN ($1, $2, $3)`, [entryF1, entryF2, entryC1]));
  assert.deepEqual(await mine(W), ids([{ id: entryF1 }, { id: entryF2 }]));
  assert.equal((await mine(C)).length, 3);
  assert.equal((await mine(M)).length, 3);
  assert.deepEqual(await mine(W2), []);
  assert.deepEqual(await mine(B), []);
  assert.equal((await db.query(`SELECT created_by FROM time_entries WHERE id = $1`, [entryF2])).rows[0].created_by, C); // the worker can see who added it
});

test("time entries: billing marks the chosen finished entries and freezes them; a client cannot bill or unbill", async () => {
  const doc = await create(C, payload(610, { job_id: jobT, time_entry_ids: [entryF1, entryF2] }));
  const billed = (await db.query(`SELECT id FROM time_entries WHERE document_id = $1`, [doc.id])).rows.map((r) => r.id).sort();
  assert.deepEqual(billed, [entryF1, entryF2].sort());
  assert.equal((await db.query(`SELECT document_id FROM time_entries WHERE id = $1`, [entryC1])).rows[0].document_id, null); // not named: stays open
  await rejects(one(C, `UPDATE time_entries SET note = 'x' WHERE id = $1`, [entryF1]), /has been billed/);
  await rejects(one(W, `UPDATE time_entries SET note = 'x' WHERE id = $1`, [entryF1]), /has been billed/);
  await rejects(one(C, `DELETE FROM time_entries WHERE id = $1`, [entryF2]), /has been billed/);
  await rejects(one(C, `UPDATE time_entries SET document_id = $2 WHERE id = $1`, [entryC1, doc.id]), /not allowed/);
});

test("time entries: a running timer is never billed", async () => {
  const run = uuid(620);
  await one(C, `INSERT INTO time_entries (id, business_id, user_id, job_id, started_at) VALUES ($1, $2, $3, $4, NOW() - interval '1 hour')`, [run, bizC, C, jobT]);
  const doc = await create(C, payload(611, { job_id: jobT, time_entry_ids: [run] }));
  assert.equal((await db.query(`SELECT document_id FROM time_entries WHERE id = $1`, [run])).rows[0].document_id, null);
  assert.ok(doc.id);
});

test("privileges: the new functions are not open to people who are not logged in", async () => {
  for (const sql of [`SELECT set_appointment_status('${uuid(1)}', 'done')`]) {
    await rejects(asAnon(() => db.query(sql)), /permission denied for function/);
  }
});

// ---- push messages: phone addresses and the trigger --------------------------------------------

const TOK1 = "token-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const TOK2 = "token-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

test("push: a phone registers its address; clients cannot read the addresses", async () => {
  await one(W, `SELECT register_device_token($1, 'android')`, [TOK1]);
  assert.equal((await db.query(`SELECT user_id FROM device_tokens WHERE token = $1`, [TOK1])).rows[0].user_id, W);
  assert.deepEqual(await one(W, `SELECT token FROM device_tokens`), []); // no policy: nobody reads them
  assert.deepEqual(await one(C, `SELECT token FROM device_tokens`), []);
});

test("push: a token belongs to one person at a time (a second person on the same phone takes it over)", async () => {
  await one(W2, `SELECT register_device_token($1, 'android')`, [TOK1]);
  const rows = (await db.query(`SELECT user_id FROM device_tokens WHERE token = $1`, [TOK1])).rows;
  assert.equal(rows.length, 1);
  assert.equal(rows[0].user_id, W2);
});

test("push: whoever holds the phone can remove its token, also one that belonged to someone else", async () => {
  await one(W, `SELECT unregister_device_token($1)`, [TOK1]);
  assert.equal((await db.query(`SELECT token FROM device_tokens WHERE token = $1`, [TOK1])).rows.length, 0);
});

test("push: only people who are in a business can register; bad input is refused", async () => {
  const nobody = 'bbbbbbb1-0000-4000-8000-000000000001';
  await db.exec(`INSERT INTO auth.users VALUES ('${nobody}')`);
  await rejects(one(nobody, `SELECT register_device_token($1, 'android')`, [TOK2]), /not allowed/); // a person without a business
  await rejects(one(W, `SELECT register_device_token('short', 'android')`), /device_tokens_token_check|check/);
  await rejects(one(W, `SELECT register_device_token($1, 'windows')`, [TOK2]), /check/);
  await rejects(asAnon(() => db.query(`SELECT register_device_token($1, 'android')`, [TOK2])), /permission denied for function/);
  await rejects(asAnon(() => db.query(`SELECT unregister_device_token($1)`, [TOK2])), /permission denied for function/);
});

test("push: the notify trigger never blocks saving, changing or deleting an appointment (here the push service does not exist)", async () => {
  const id = uuid(701);
  await one(C, `INSERT INTO appointments (id, business_id, title, starts_at, ends_at, assignee_ids) VALUES ($1, $2, 'Push', NOW() + interval '1 day', NOW() + interval '1 day 1 hour', ARRAY[$3]::uuid[])`, [id, bizC, W]);
  await one(C, `UPDATE appointments SET assignee_ids = ARRAY[$2, $3]::uuid[], title = 'Push 2' WHERE id = $1`, [id, W, W2]);
  await one(C, `UPDATE appointments SET status = 'canceled' WHERE id = $1`, [id]);
  await one(C, `UPDATE appointments SET status = 'planned' WHERE id = $1`, [id]);
  await one(C, `DELETE FROM appointments WHERE id = $1`, [id]);
  assert.equal((await db.query(`SELECT id FROM appointments WHERE id = $1`, [id])).rows.length, 0);
});

test("push: the helper functions are internal", async () => {
  await rejects(one(C, `SELECT uuid_array_minus(ARRAY[]::uuid[], ARRAY[]::uuid[])`), /permission denied for function/);
  assert.deepEqual(
    (await db.query(`SELECT uuid_array_minus(ARRAY['${W}','${W2}']::uuid[], ARRAY['${W2}']::uuid[]) AS r`)).rows[0].r, [W]);
  assert.deepEqual((await db.query(`SELECT uuid_array_minus(NULL, ARRAY['${W}']::uuid[]) AS r`)).rows[0].r, []);
});

// ---- hourly rates per person --------------------------------------------------------------------

test("member rates: only the owner sets them; the boss and the office read them; employees do not", async () => {
  await one(C, `SELECT set_member_rate($1, 7500)`, [W]);
  assert.deepEqual((await one(C, `SELECT user_id, hourly_rate_cents FROM member_rates`)).map((r) => [r.user_id, r.hourly_rate_cents]), [[W, 7500]]);
  assert.equal((await one(M, `SELECT hourly_rate_cents FROM member_rates WHERE user_id = $1`, [W])).length, 1); // the office reads
  assert.deepEqual(await one(W, `SELECT hourly_rate_cents FROM member_rates`), []); // not even his own
  assert.deepEqual(await one(W2, `SELECT hourly_rate_cents FROM member_rates`), []);
  assert.deepEqual(await one(B, `SELECT hourly_rate_cents FROM member_rates`), []); // another business
  await rejects(one(M, `SELECT set_member_rate($1, 9000)`, [W]), /not allowed/); // the office may not set
  await rejects(one(W, `SELECT set_member_rate($1, 9000)`, [W]), /not allowed/); // nobody sets his own
  await rejects(as(C, () => db.query(`INSERT INTO member_rates (user_id, business_id, hourly_rate_cents) VALUES ($1, $2, 100)`, [W2, bizC])), /row-level security/);
});

test("member rates: change and remove; only people of the business; sane amounts", async () => {
  await one(C, `SELECT set_member_rate($1, 8000)`, [W]);
  assert.equal((await one(C, `SELECT hourly_rate_cents FROM member_rates WHERE user_id = $1`, [W]))[0].hourly_rate_cents, 8000);
  await one(C, `SELECT set_member_rate($1, NULL)`, [W]);
  assert.deepEqual(await one(C, `SELECT * FROM member_rates WHERE user_id = $1`, [W]), []);
  await rejects(one(C, `SELECT set_member_rate($1, 7000)`, [B]), /person not found/); // someone of another business
  await rejects(one(C, `SELECT set_member_rate($1, -1)`, [W]), /check/);
  await rejects(one(C, `SELECT set_member_rate($1, 100001)`, [W]), /check/);
  await rejects(asAnon(() => db.query(`SELECT set_member_rate($1, 100)`, [W])), /permission denied for function/);
});
