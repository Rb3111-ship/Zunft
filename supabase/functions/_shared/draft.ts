// Pure helpers for process-capture: validation of the LLM output and § 35a totals.
// No network or Deno APIs here so it can be unit tested (see draft_test.ts).

export const LINE_TYPES = ["labor", "material", "flat_fee"] as const;
export const UNITS = ["Std", "Stk", "m", "Pauschal"] as const;
export const DOC_TYPES = ["quote", "invoice"] as const;

const MAX_LINE_ITEMS = 50;
const MAX_QUANTITY = 100_000;
const MAX_UNIT_PRICE_CENTS = 10_000_000; // 100.000,00 EUR

export interface LineItem {
  type: (typeof LINE_TYPES)[number];
  description: string;
  quantity: number;
  unit: (typeof UNITS)[number];
  unit_price_net_cents: number;
  requires_confirmation: boolean;
}

export interface Draft {
  title: string;
  document_type: (typeof DOC_TYPES)[number];
  /** Only a hint for the user ("Müller" was mentioned). The customer is chosen in the app, never by the AI. */
  customer_hint: {
    name: string | null;
    address: string | null;
  };
  line_items: LineItem[];
  warnings: string[];
}

export interface FinancialSummary {
  subtotal_labor_cents: number;
  subtotal_material_cents: number;
  total_net_cents: number;
  vat_rate: number;
  vat_amount_cents: number;
  total_gross_cents: number;
}

export class DraftValidationError extends Error {}

function fail(msg: string): never {
  throw new DraftValidationError(msg);
}

function str(v: unknown, field: string, max: number, required = true): string {
  if (typeof v !== "string") {
    if (required) fail(`${field} must be a string`);
    return "";
  }
  const t = v.trim();
  if (required && !t) fail(`${field} is empty`);
  return t.slice(0, max);
}

function oneOf<T extends string>(v: unknown, allowed: readonly T[], field: string): T {
  if (typeof v !== "string" || !(allowed as readonly string[]).includes(v)) {
    fail(`${field} must be one of ${allowed.join(", ")}`);
  }
  return v as T;
}

/** Validates and normalizes untrusted model output. Throws DraftValidationError. */
export function validateDraft(raw: unknown): Draft {
  if (!raw || typeof raw !== "object") fail("draft is not an object");
  const r = raw as Record<string, unknown>;

  if (!Array.isArray(r.line_items) || r.line_items.length === 0) fail("line_items must be a non-empty array");
  if (r.line_items.length > MAX_LINE_ITEMS) fail("too many line_items");

  const line_items: LineItem[] = r.line_items.map((it, i) => {
    if (!it || typeof it !== "object") fail(`line_items[${i}] is not an object`);
    const o = it as Record<string, unknown>;
    const quantity = Number(o.quantity);
    const price = Number(o.unit_price_net_cents);
    if (!Number.isFinite(quantity) || quantity <= 0 || quantity > MAX_QUANTITY) fail(`line_items[${i}].quantity invalid`);
    if (!Number.isFinite(price) || price < 0 || price > MAX_UNIT_PRICE_CENTS) fail(`line_items[${i}].unit_price_net_cents invalid`);
    return {
      type: oneOf(o.type, LINE_TYPES, `line_items[${i}].type`),
      description: str(o.description, `line_items[${i}].description`, 200),
      quantity,
      unit: oneOf(o.unit, UNITS, `line_items[${i}].unit`),
      unit_price_net_cents: Math.round(price),
      requires_confirmation: o.requires_confirmation === true,
    };
  });

  // The customer is fixed by the job the note belongs to. Whatever name the speaker mentions is
  // kept as a hint only, so a wrong or ambiguous name can never pick a customer.
  const hint = (r.customer_hint ?? {}) as Record<string, unknown>;
  const hintName = typeof hint.name === "string" ? hint.name.trim().slice(0, 120) : "";
  const hintAddress = typeof hint.address === "string" ? hint.address.trim().slice(0, 200) : "";

  const warnings = Array.isArray(r.warnings)
    ? r.warnings.filter((w): w is string => typeof w === "string").map((w) => w.slice(0, 300)).slice(0, 20)
    : [];

  return {
    title: str(r.title, "title", 120),
    document_type: oneOf(r.document_type, DOC_TYPES, "document_type"),
    customer_hint: { name: hintName || null, address: hintAddress || null },
    line_items,
    warnings,
  };
}

/**
 * Rebuilds the API response from a stored capture_logs row, for a retried request that
 * carries a capture id we have already processed.
 */
export function rebuildResponse(row: {
  job_id: string | null;
  raw_transcript: string | null;
  ai_parsed_json: Record<string, unknown> | null;
}) {
  const stored = row.ai_parsed_json ?? {};
  // deno-lint-ignore no-unused-vars
  const { financial_summary, model, ...parsedData } = stored as Record<string, unknown>;
  return {
    success: true,
    replayed: true,
    jobId: row.job_id,
    transcript: row.raw_transcript ?? "",
    parsedData,
    financialSummary: financial_summary ?? null,
  };
}

/**
 * § 35a EStG split. Labor and flat fees (Anfahrt etc.) are service costs; only
 * material is excluded. Mirrors FinancialSummary.calculate in the Flutter app
 * (draft_models.dart) - keep both in sync.
 */
export function calculateSummary(items: LineItem[], vatRate: number): FinancialSummary {
  let labor = 0;
  let material = 0;
  for (const item of items) {
    const total = Math.round(item.quantity * item.unit_price_net_cents);
    if (item.type === "labor" || item.type === "flat_fee") labor += total;
    else material += total;
  }
  const net = labor + material;
  const vat = Math.round((net * vatRate) / 100);
  return {
    subtotal_labor_cents: labor,
    subtotal_material_cents: material,
    total_net_cents: net,
    vat_rate: vatRate,
    vat_amount_cents: vat,
    total_gross_cents: net + vat,
  };
}
