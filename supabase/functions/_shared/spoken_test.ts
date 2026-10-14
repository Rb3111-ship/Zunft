import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import type { Draft } from "./draft.ts";
import { markTranslated, parseSpoken, SPOKEN_LANGUAGES, spokenLanguageName, spokenPrompt, SpokenError } from "./spoken.ts";

const draft = (): Draft => ({
  title: "Steckdosen",
  document_type: "invoice",
  customer_hint: { name: null, address: null },
  line_items: [
    { type: "labor", description: "Arbeit", quantity: 2, unit: "Std", unit_price_net_cents: 6500, requires_confirmation: false },
    { type: "material", description: "Steckdose", quantity: 3, unit: "Stk", unit_price_net_cents: 1500, requires_confirmation: false },
  ],
  warnings: ["Materialpreis fehlt"],
});

Deno.test("spoken: German and unknown codes use the normal German path", () => {
  assertEquals(spokenLanguageName("de"), null);
  assertEquals(spokenLanguageName(undefined), null);
  assertEquals(spokenLanguageName("xx"), null);
  assertEquals(spokenLanguageName("toString"), null); // no inherited object keys
  assertEquals(spokenLanguageName(12), null);
});

Deno.test("spoken: every app language except German has a name", () => {
  for (const c of ["en", "tr", "ar", "sq", "pl", "ro", "ru", "uk", "hr", "sr", "bg", "fa"]) {
    assertEquals(typeof SPOKEN_LANGUAGES[c], "string", c);
  }
  assertEquals(spokenLanguageName("ar"), "Arabisch");
});

Deno.test("spoken: the prompt names the language, the form and the safety rule", () => {
  const a = spokenPrompt("Albanisch", true);
  assertEquals(a.includes("Albanisch"), true);
  assertEquals(a.includes("gesprochen"), true);
  assertEquals(a.includes("SICHERHEIT"), true);
  assertEquals(spokenPrompt("Albanisch", false).includes("geschrieben"), true);
});

Deno.test("spoken: the answer of the model is checked", () => {
  assertEquals(parseSpoken({ original: " سلام ", german: " Hallo " }, 100), { original: "سلام", german: "Hallo" });
  assertEquals(parseSpoken({ original: "x", german: "y".repeat(50) }, 10).german.length, 10);
  assertThrows(() => parseSpoken(null, 10), SpokenError);
  assertThrows(() => parseSpoken({ original: "x" }, 10), SpokenError);
  assertThrows(() => parseSpoken({ original: "x", german: "   " }, 10), SpokenError);
  assertThrows(() => parseSpoken({ original: 1, german: "y" }, 10), SpokenError);
});

Deno.test("spoken: a translated note must be checked: every position confirmed, one clear warning", () => {
  const d = markTranslated(draft(), "Arabisch");
  assertEquals(d.line_items.every((i) => i.requires_confirmation), true);
  assertEquals(d.warnings.length, 2);
  assertEquals(d.warnings[0].includes("Arabisch"), true);
  assertEquals(d.warnings[1], "Materialpreis fehlt");
  // numbers and text of the positions are untouched
  assertEquals(d.line_items[1].quantity, 3);
  assertEquals(d.line_items[1].unit_price_net_cents, 1500);
  // marking twice does not repeat the warning
  assertEquals(markTranslated(d, "Arabisch").warnings.length, 2);
  // the original draft object is not changed
  const original = draft();
  markTranslated(original, "Arabisch");
  assertEquals(original.line_items[0].requires_confirmation, false);
});
