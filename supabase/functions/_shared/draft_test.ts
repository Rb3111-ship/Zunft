import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { calculateSummary, DraftValidationError, rebuildResponse, validateDraft } from "./draft.ts";

const item = (over: Record<string, unknown> = {}) => ({
  type: "labor",
  description: "Steckdosenmontage",
  quantity: 2,
  unit: "Std",
  unit_price_net_cents: 6800,
  ...over,
});

const draft = (over: Record<string, unknown> = {}) => ({
  title: "Steckdose",
  document_type: "invoice",
  customer_match: { extracted_name: "Müller", confidence: "new", matched_customer_id: null },
  line_items: [item()],
  ...over,
});

Deno.test("summary matches the Flutter test values (labor 136, material 40, 19% VAT)", () => {
  const s = calculateSummary(
    [item() as never, item({ type: "material", unit: "Stk", quantity: 1, unit_price_net_cents: 4000 }) as never],
    19,
  );
  assertEquals(s.subtotal_labor_cents, 13600);
  assertEquals(s.subtotal_material_cents, 4000);
  assertEquals(s.total_net_cents, 17600);
  assertEquals(s.vat_amount_cents, 3344);
  assertEquals(s.total_gross_cents, 20944);
});

Deno.test("flat_fee counts as labor for § 35a", () => {
  const s = calculateSummary([item({ type: "flat_fee", unit: "Pauschal", quantity: 1, unit_price_net_cents: 3500 }) as never], 19);
  assertEquals(s.subtotal_labor_cents, 3500);
  assertEquals(s.subtotal_material_cents, 0);
});

Deno.test("fractional hours round to whole cents", () => {
  const s = calculateSummary([item({ quantity: 1.5 }) as never], 19);
  assertEquals(s.total_net_cents, 10200);
  assertEquals(s.vat_amount_cents, 1938);
});

Deno.test("valid draft passes", () => {
  assertEquals(validateDraft(draft(), []).line_items.length, 1);
});

Deno.test("empty or missing line_items is rejected", () => {
  assertThrows(() => validateDraft(draft({ line_items: [] }), []), DraftValidationError);
  assertThrows(() => validateDraft(draft({ line_items: undefined }), []), DraftValidationError);
});

Deno.test("bad types, units and numbers are rejected", () => {
  assertThrows(() => validateDraft(draft({ line_items: [item({ type: "gift" })] }), []), DraftValidationError);
  assertThrows(() => validateDraft(draft({ line_items: [item({ unit: "kg" })] }), []), DraftValidationError);
  assertThrows(() => validateDraft(draft({ line_items: [item({ quantity: -1 })] }), []), DraftValidationError);
  assertThrows(() => validateDraft(draft({ line_items: [item({ unit_price_net_cents: "abc" })] }), []), DraftValidationError);
});

Deno.test("customer id the model invented is dropped", () => {
  const d = validateDraft(
    draft({ customer_match: { extracted_name: "X", confidence: "exact", matched_customer_id: "not-ours" } }),
    [{ id: "real" }],
  );
  assertEquals(d.customer_match.matched_customer_id, null);
  assertEquals(d.customer_match.confidence, "new");
});

Deno.test("known customer id is kept", () => {
  const d = validateDraft(
    draft({ customer_match: { extracted_name: "X", confidence: "exact", matched_customer_id: "real" } }),
    [{ id: "real" }],
  );
  assertEquals(d.customer_match.matched_customer_id, "real");
});

Deno.test("rebuildResponse restores what the first call returned", () => {
  const res = rebuildResponse({
    job_id: "job-1",
    raw_transcript: "Steckdose im Keller",
    ai_parsed_json: {
      title: "Steckdose",
      document_type: "invoice",
      line_items: [],
      model: "gemini-2.5-flash-lite",
      financial_summary: { total_net_cents: 17600 },
    },
  });
  assertEquals(res.success, true);
  assertEquals(res.replayed, true);
  assertEquals(res.jobId, "job-1");
  assertEquals(res.transcript, "Steckdose im Keller");
  assertEquals(res.parsedData, { title: "Steckdose", document_type: "invoice", line_items: [] });
  assertEquals(res.financialSummary, { total_net_cents: 17600 });
});

Deno.test("rebuildResponse copes with a log row that has no parsed data", () => {
  const res = rebuildResponse({ job_id: null, raw_transcript: null, ai_parsed_json: null });
  assertEquals(res.parsedData, {});
  assertEquals(res.transcript, "");
  assertEquals(res.financialSummary, null);
});
