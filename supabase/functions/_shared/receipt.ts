// Pure helpers for reading a photographed receipt (Beleg): turns the untrusted model output into a
// validated draft of material lines. No network or Deno APIs, so it can be unit tested
// (see receipt_test.ts).
//
// The model only READS what is printed (amounts as printed, VAT info). Everything that is
// arithmetic - net from gross, unit price from line total, the cross-check against the printed
// total - is done here in code, never by the model.

import { type Draft, DraftValidationError, type LineItem, UNITS, validateDraft } from "./draft.ts";

export interface ReceiptMeta {
  supplier: string | null;
  receipt_date: string | null; // yyyy-MM-dd
  receipt_number: string | null;
  /** The total printed on the receipt, in cents (as printed: usually gross). */
  total_printed_cents: number | null;
  prices_include_vat: boolean;
  vat_rate_percent: number;
  /** True when net prices were calculated from gross prices. */
  converted_from_gross: boolean;
}

export interface ReceiptResult {
  draft: Draft;
  meta: ReceiptMeta;
  /** Short readable summary, stored as the "transcript" of the note. */
  summary: string;
}

const MAX_LINES = 50;
const DEFAULT_VAT = 19;

function cleanStr(v: unknown, max: number): string | null {
  if (typeof v !== "string") return null;
  const t = v.trim().slice(0, max);
  return t || null;
}

function cents(v: unknown): number | null {
  const n = Number(v);
  return v !== null && v !== undefined && v !== "" && Number.isFinite(n) ? Math.round(n) : null;
}

function euro(c: number): string {
  return (c / 100).toFixed(2).replace(".", ",") + " €";
}

export function buildReceiptDraft(raw: unknown): ReceiptResult {
  if (!raw || typeof raw !== "object") throw new DraftValidationError("receipt is not an object");
  const r = raw as Record<string, unknown>;
  if (r.is_receipt === false) throw new DraftValidationError("not a receipt");
  if (!Array.isArray(r.line_items) || r.line_items.length === 0) throw new DraftValidationError("no lines on the receipt");

  const warnings: string[] = [];
  const includesVat = r.prices_include_vat === true;

  let vat = r.vat_rate_percent === null || r.vat_rate_percent === undefined ? NaN : Number(r.vat_rate_percent);
  if (!Number.isFinite(vat) || vat < 0 || vat > 30) {
    vat = DEFAULT_VAT;
    if (includesVat) warnings.push("Der MwSt.-Satz war auf dem Beleg nicht lesbar: 19 % angenommen. Bitte prüfen.");
  }

  const items: LineItem[] = [];
  let printedSum = 0;
  let allTotalsKnown = true;

  for (const [i, it] of (r.line_items as unknown[]).slice(0, MAX_LINES).entries()) {
    if (!it || typeof it !== "object") continue;
    const o = it as Record<string, unknown>;
    const description = cleanStr(o.description, 200);
    let quantity = Number(o.quantity);
    if (!Number.isFinite(quantity) || quantity <= 0) quantity = 1;
    const printedUnit = cents(o.unit_price_cents);
    const printedTotal = cents(o.line_total_cents);

    // The unit price as printed; if only the line total is printed, derive it.
    let unitGross = printedUnit ?? (printedTotal !== null ? Math.round(printedTotal / quantity) : null);
    if (!description || unitGross === null || unitGross <= 0) {
      warnings.push(`Zeile ${i + 1}${description ? ` („${description.slice(0, 40)}“)` : ""} wurde nicht übernommen (kein lesbarer Preis).`);
      allTotalsKnown = false;
      continue;
    }
    printedSum += printedTotal ?? Math.round(quantity * unitGross);
    if (printedTotal === null && printedUnit === null) allTotalsKnown = false;

    const net = includesVat ? Math.round(unitGross / (1 + vat / 100)) : unitGross;
    const unit = (UNITS as readonly string[]).includes(String(o.unit)) && o.unit !== "Std" ? String(o.unit) : "Stk";
    items.push({
      type: "material",
      description,
      quantity,
      unit: unit as LineItem["unit"],
      unit_price_net_cents: net,
      requires_confirmation: false,
    });
  }

  if (items.length === 0) throw new DraftValidationError("no readable lines on the receipt");

  if (items.some((i) => /pfand/i.test(i.description))) {
    warnings.push("Der Beleg enthält Pfand. Bitte prüfen, ob dieser Posten abgerechnet werden soll.");
  }

  if (includesVat) warnings.push(`Preise laut Beleg inkl. ${vat} % MwSt.: Nettopreise wurden umgerechnet.`);

  // Cross-check against the total printed on the receipt.
  const totalPrinted = cents(r.total_printed_cents);
  if (totalPrinted !== null && totalPrinted > 0 && allTotalsKnown) {
    const diff = Math.abs(printedSum - totalPrinted);
    if (diff > Math.max(2, Math.round(totalPrinted * 0.01))) {
      warnings.push(
        `Die Positionen ergeben ${euro(printedSum)}, auf dem Beleg steht ${euro(totalPrinted)}. Bitte Beleg und Positionen vergleichen.`,
      );
      for (const item of items) item.requires_confirmation = true;
    }
  }
  if (r.line_items.length > MAX_LINES) warnings.push(`Nur die ersten ${MAX_LINES} Zeilen wurden übernommen.`);
  if (Array.isArray(r.problems)) {
    for (const p of r.problems.slice(0, 5)) {
      const t = cleanStr(p, 200);
      if (t) warnings.push(t);
    }
  }

  const supplier = cleanStr(r.supplier, 120);
  const dateRaw = cleanStr(r.receipt_date, 10);
  const date = dateRaw && /^\d{4}-\d{2}-\d{2}$/.test(dateRaw) ? dateRaw : null;
  const number = cleanStr(r.receipt_number, 60);

  const draft = validateDraft({
    title: supplier ? `Material: ${supplier}` : "Material laut Beleg",
    document_type: "invoice",
    customer_hint: { name: null, address: null },
    line_items: items,
    warnings,
  });

  const meta: ReceiptMeta = {
    supplier,
    receipt_date: date,
    receipt_number: number,
    total_printed_cents: totalPrinted,
    prices_include_vat: includesVat,
    vat_rate_percent: vat,
    converted_from_gross: includesVat,
  };

  const summary = [
    `Beleg${supplier ? ` von ${supplier}` : ""}`,
    date ? `vom ${date.slice(8, 10)}.${date.slice(5, 7)}.${date.slice(0, 4)}` : null,
    number ? `Nr. ${number}` : null,
    totalPrinted !== null ? `Gesamt ${euro(totalPrinted)}` : null,
  ].filter(Boolean).join(", ");

  return { draft, meta, summary };
}
