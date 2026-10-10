import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import { DraftValidationError } from "./draft.ts";
import { buildReceiptDraft } from "./receipt.ts";

const line = (over: Record<string, unknown> = {}) => ({
  description: "NYM-J 3x1,5 Kabel",
  quantity: 50,
  unit: "m",
  unit_price_cents: 119,
  line_total_cents: 5950,
  ...over,
});

const receipt = (over: Record<string, unknown> = {}) => ({
  is_receipt: true,
  supplier: "Elektro Großhandel Nord",
  receipt_date: "2026-10-07",
  receipt_number: "R-4711",
  prices_include_vat: false,
  vat_rate_percent: 19,
  total_printed_cents: 5950,
  line_items: [line()],
  ...over,
});

Deno.test("net prices on the receipt are taken as they are", () => {
  const r = buildReceiptDraft(receipt());
  assertEquals(r.draft.line_items.length, 1);
  assertEquals(r.draft.line_items[0].type, "material");
  assertEquals(r.draft.line_items[0].unit, "m");
  assertEquals(r.draft.line_items[0].unit_price_net_cents, 119);
  assertEquals(r.draft.warnings, []);
  assertEquals(r.meta.supplier, "Elektro Großhandel Nord");
  assertEquals(r.draft.title, "Material: Elektro Großhandel Nord");
  assertEquals(r.summary, "Beleg von Elektro Großhandel Nord, vom 07.10.2026, Nr. R-4711, Gesamt 59,50 €");
});

Deno.test("gross prices are converted to net in code, with a note", () => {
  const r = buildReceiptDraft(receipt({
    prices_include_vat: true,
    total_printed_cents: 1190,
    line_items: [line({ description: "Schalter", quantity: 1, unit: "Stk", unit_price_cents: 1190, line_total_cents: 1190 })],
  }));
  assertEquals(r.draft.line_items[0].unit_price_net_cents, 1000);
  assert(r.draft.warnings.some((w) => w.includes("umgerechnet")));
  assertEquals(r.meta.converted_from_gross, true);
});

Deno.test("the unit price is derived from the line total when only that is printed", () => {
  const r = buildReceiptDraft(receipt({
    total_printed_cents: 3000,
    line_items: [line({ quantity: 3, unit: "Stk", unit_price_cents: null, line_total_cents: 3000 })],
  }));
  assertEquals(r.draft.line_items[0].unit_price_net_cents, 1000);
});

Deno.test("lines add up to a different total: warn and ask for confirmation", () => {
  const r = buildReceiptDraft(receipt({ total_printed_cents: 9999 }));
  assert(r.draft.warnings.some((w) => w.includes("weicht") || w.includes("ergeben")));
  assertEquals(r.draft.line_items[0].requires_confirmation, true);
});

Deno.test("a small rounding difference is not a warning", () => {
  const r = buildReceiptDraft(receipt({ total_printed_cents: 5951 }));
  assertEquals(r.draft.warnings, []);
});

Deno.test("lines without a usable price are dropped, and the user is told", () => {
  const r = buildReceiptDraft(receipt({
    total_printed_cents: null,
    line_items: [line(), line({ description: "Rabatt", unit_price_cents: -500, line_total_cents: -500 }), line({ description: "?", unit_price_cents: null, line_total_cents: null })],
  }));
  assertEquals(r.draft.line_items.length, 1);
  assertEquals(r.draft.warnings.filter((w) => w.includes("nicht übernommen")).length, 2);
});

Deno.test("an unreadable VAT rate on a gross receipt falls back to 19 % and says so", () => {
  const r = buildReceiptDraft(receipt({ prices_include_vat: true, vat_rate_percent: null, total_printed_cents: 5950 }));
  assert(r.draft.warnings.some((w) => w.includes("19 %")));
});

Deno.test("hours are not a unit for material", () => {
  const r = buildReceiptDraft(receipt({ line_items: [line({ unit: "Std" })] }));
  assertEquals(r.draft.line_items[0].unit, "Stk");
});

Deno.test("a photo that is not a receipt, or has no lines, is refused", () => {
  assertThrows(() => buildReceiptDraft({ is_receipt: false }), DraftValidationError);
  assertThrows(() => buildReceiptDraft(receipt({ line_items: [] })), DraftValidationError);
  assertThrows(() => buildReceiptDraft(receipt({ line_items: [line({ unit_price_cents: null, line_total_cents: null })] })), DraftValidationError);
  assertThrows(() => buildReceiptDraft("nonsense"), DraftValidationError);
});

Deno.test("an invalid date is ignored; the supplier is optional", () => {
  const r = buildReceiptDraft(receipt({ supplier: null, receipt_date: "gestern" }));
  assertEquals(r.meta.receipt_date, null);
  assertEquals(r.draft.title, "Material laut Beleg");
});

Deno.test("a deposit (Pfand) line is kept but flagged for the boss", () => {
  const r = buildReceiptDraft(receipt({
    total_printed_cents: 6950,
    line_items: [line(), line({ description: "Pfand Kabeltrommel", quantity: 1, unit: "Stk", unit_price_cents: 1000, line_total_cents: 1000 })],
  }));
  assertEquals(r.draft.line_items.length, 2);
  assert(r.draft.warnings.some((w) => w.includes("Pfand")));
});

const bauhaus = (over: Record<string, unknown> = {}) => receipt({
  supplier: "BAUHAUS",
  prices_include_vat: true, // the model's wrong guess: the receipt has a subtotal line
  total_printed_cents: 6962,
  vat_total_cents: 1112,
  line_items: [
    line({ description: "Steckdose EAN: 4008224532107", quantity: 2, unit: "Stk", unit_price_cents: 895, line_total_cents: 1790 }),
    line({ description: "NYM-J Kabel", quantity: 15, unit: "m", unit_price_cents: 129, line_total_cents: 1935 }),
    line({ description: "Abzweigdose", quantity: 1, unit: "Stk", unit_price_cents: 349, line_total_cents: 349 }),
    line({ description: "LS-Schalter", quantity: 2, unit: "Stk", unit_price_cents: 429, line_total_cents: 858 }),
    line({ description: "Rohr", quantity: 1, unit: "Stk", unit_price_cents: 219, line_total_cents: 219 }),
    line({ description: "Kabelschellen", quantity: 1, unit: "Stk", unit_price_cents: 699, line_total_cents: 699 }),
  ],
  ...over,
});

Deno.test("subtotal + VAT = total: prices are net, nothing is converted (Bauhaus receipt)", () => {
  const r = buildReceiptDraft(bauhaus());
  assertEquals(r.draft.line_items[0].unit_price_net_cents, 895);
  assertEquals(r.draft.line_items[0].description, "Steckdose");
  assertEquals(r.meta.prices_include_vat, false);
  assert(r.draft.warnings.some((w) => w.includes("Nettopreise (Zwischensumme")));
  assert(!r.draft.warnings.some((w) => w.includes("verglichen") || w.includes("vergleichen")));
  assert(r.draft.line_items.every((i) => !i.requires_confirmation));
});

Deno.test("lines add up to the total: prices are gross even if the model said net", () => {
  const r = buildReceiptDraft(bauhaus({
    prices_include_vat: false,
    total_printed_cents: 5850,
    vat_total_cents: 934,
  }));
  assertEquals(r.meta.prices_include_vat, true);
  assertEquals(r.draft.line_items[0].unit_price_net_cents, 752); // 8,95 / 1,19
});

import { receiptKey } from "./receipt.ts";

const meta = (over: Record<string, unknown> = {}) => ({
  supplier: "BAUHAUS Hamburg-Wandsbek",
  receipt_date: "2026-10-07",
  receipt_number: "58473",
  total_printed_cents: 6962,
  prices_include_vat: false,
  vat_rate_percent: 19,
  converted_from_gross: false,
  ...over,
});

Deno.test("the same receipt read twice gets the same key, even if the supplier text differs", () => {
  const a = receiptKey(meta());
  const b = receiptKey(meta({ supplier: "Bauhaus" }));
  assert(a !== null && a.withNumber);
  assertEquals(a!.key, b!.key); // with a receipt number the supplier is not part of the key
});

Deno.test("another amount, date or number gives another key", () => {
  const base = receiptKey(meta())!.key;
  assert(receiptKey(meta({ total_printed_cents: 6963 }))!.key !== base);
  assert(receiptKey(meta({ receipt_date: "2026-10-08" }))!.key !== base);
  assert(receiptKey(meta({ receipt_number: "58474" }))!.key !== base);
});

Deno.test("without a receipt number the key is weaker (first word of the supplier)", () => {
  const k = receiptKey(meta({ receipt_number: null }));
  assertEquals(k!.withNumber, false);
  assertEquals(k!.key, receiptKey(meta({ receipt_number: null, supplier: "BAUHAUS Fachcentrum" }))!.key);
});

Deno.test("too little read: no key (nothing to compare)", () => {
  assertEquals(receiptKey(meta({ total_printed_cents: null })), null);
  assertEquals(receiptKey(meta({ receipt_date: null })), null);
  assertEquals(receiptKey(meta({ receipt_number: null, supplier: null })), null);
});
