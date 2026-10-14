import { assert, assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import {
  base64Url,
  fcmMessage,
  isDeadToken,
  isPushEvent,
  parseServiceAccount,
  pemToPkcs8,
  PUSH_LANGUAGES,
  pushLanguage,
  pushText,
  secretsMatch,
  signGoogleJwt,
  whenLabel,
} from "./push.ts";

const appt = { id: "a1", title: "Steckdose Keller", starts_at: "2026-10-12T06:00:00Z", location: "Elbchaussee 118, 22763 Hamburg" };

Deno.test("the time is shown in the time zone of the business, not the server's", () => {
  assertEquals(whenLabel("2026-10-12T06:00:00Z"), "Mo 12.10. 08:00"); // summer time: UTC+2
  assertEquals(whenLabel("2026-01-12T06:00:00Z"), "Mo 12.01. 07:00"); // winter time: UTC+1
  assertEquals(whenLabel("2026-10-12T22:30:00Z"), "Di 13.10. 00:30"); // past midnight in Berlin
  assertEquals(whenLabel("nonsense"), "");
});

Deno.test("each event has its own title; the body names the appointment, time and place", () => {
  assertEquals(pushText("new", appt), { title: "Neuer Termin", body: "Mo 12.10. 08:00 · Steckdose Keller, Elbchaussee 118, 22763 Hamburg" });
  assertEquals(pushText("changed", appt).title, "Termin geändert");
  assertEquals(pushText("canceled", appt).title, "Termin abgesagt");
  assertEquals(pushText("removed", appt).title, "Termin entfällt für dich");
  assertEquals(pushText("deleted", appt).title, "Termin gelöscht");
});

Deno.test("without a place nothing odd is printed; very long texts are cut", () => {
  assertEquals(pushText("new", { ...appt, location: null }).body, "Mo 12.10. 08:00 · Steckdose Keller");
  assertEquals(pushText("new", { ...appt, location: "  " }).body, "Mo 12.10. 08:00 · Steckdose Keller");
  const long = pushText("new", { ...appt, title: "x".repeat(200), location: null }).body;
  assert(long.length < 120 && long.includes("…"));
});

Deno.test("only the five known events are accepted", () => {
  for (const e of ["new", "changed", "canceled", "removed", "deleted"]) assert(isPushEvent(e));
  for (const e of ["", "NEW", "update", 3, null, undefined]) assert(!isPushEvent(e));
});

Deno.test("base64url has no padding or + and /", () => {
  assertEquals(base64Url("{\"alg\":\"RS256\"}"), "eyJhbGciOiJSUzI1NiJ9");
  assertEquals(base64Url(new Uint8Array([251, 255, 254])), "-__-");
});

Deno.test("the service account secret is checked: missing, garbage, and incomplete are refused", () => {
  assertThrows(() => parseServiceAccount(undefined), Error, "missing");
  assertThrows(() => parseServiceAccount("%%%"), Error);
  assertThrows(() => parseServiceAccount(btoa(JSON.stringify({ client_email: "x" }))), Error, "lacks");
  const ok = parseServiceAccount(btoa(JSON.stringify({ client_email: "a@b.iam", private_key: "k", project_id: "p", extra: 1 })));
  assertEquals(ok, { client_email: "a@b.iam", private_key: "k", project_id: "p" });
});

async function testKeyPem(): Promise<{ pem: string; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let bin = "";
  for (const b of der) bin += String.fromCharCode(b);
  const lines = btoa(bin).match(/.{1,64}/g)!.join("\n");
  return { pem: `-----BEGIN PRIVATE KEY-----\n${lines}\n-----END PRIVATE KEY-----\n`, publicKey: pair.publicKey };
}

Deno.test("the Google sign-in request is a JWT with the right claims and a signature that verifies", async () => {
  const { pem, publicKey } = await testKeyPem();
  const jwt = await signGoogleJwt({ client_email: "fcm@zunft.iam.gserviceaccount.com", private_key: pem, project_id: "zunft" }, 1_800_000_000);
  const [h, c, s] = jwt.split(".");
  assertEquals(JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(h.replaceAll("-", "+").replaceAll("_", "/")), (x) => x.charCodeAt(0)))), { alg: "RS256", typ: "JWT" });
  const claims = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(c.replaceAll("-", "+").replaceAll("_", "/")), (x) => x.charCodeAt(0))));
  assertEquals(claims.iss, "fcm@zunft.iam.gserviceaccount.com");
  assertEquals(claims.scope, "https://www.googleapis.com/auth/firebase.messaging");
  assertEquals(claims.aud, "https://oauth2.googleapis.com/token");
  assertEquals(claims.exp - claims.iat, 3600);
  const sig = Uint8Array.from(atob(s.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - (s.length % 4)) % 4)), (x) => x.charCodeAt(0));
  assert(await crypto.subtle.verify("RSASSA-PKCS1-v1_5", publicKey, sig, new TextEncoder().encode(`${h}.${c}`)));
});

Deno.test("a broken private key fails clearly instead of sending garbage", async () => {
  await assertRejects(() => signGoogleJwt({ client_email: "a", private_key: "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----", project_id: "p" }, 1));
  assertEquals(pemToPkcs8("-----BEGIN PRIVATE KEY-----\nAQID\n-----END PRIVATE KEY-----").length, 3);
});

Deno.test("the FCM message carries the text, the appointment id for the app, and a high priority", () => {
  const m = fcmMessage("tok123", { title: "T", body: "B" }, appt, "new");
  assertEquals(m.message.token, "tok123");
  assertEquals(m.message.notification, { title: "T", body: "B" });
  assertEquals(m.message.data, { type: "appointment", event: "new", appointment_id: "a1" });
  assertEquals(m.message.android.priority, "HIGH");
});

Deno.test("a dead phone address is recognised; a hiccup at Google is not", () => {
  assert(isDeadToken(404, undefined));
  assert(isDeadToken(404, { error: { status: "NOT_FOUND" } }));
  assert(isDeadToken(400, { error: { status: "INVALID_ARGUMENT", details: [{ errorCode: "INVALID_ARGUMENT" }] } }));
  assert(isDeadToken(200, { error: { details: [{ errorCode: "UNREGISTERED" }] } }));
  assert(!isDeadToken(500, { error: { status: "INTERNAL" } }));
  assert(!isDeadToken(429, { error: { status: "RESOURCE_EXHAUSTED" } }));
  assert(!isDeadToken(400, { error: { status: "INVALID_ARGUMENT", details: [{ errorCode: "SOMETHING_ELSE" }] } }));
});

Deno.test("the shared secret: equal passes; empty, different or other length does not", () => {
  assert(secretsMatch("abc123", "abc123"));
  assert(!secretsMatch("", ""));
  assert(!secretsMatch("abc124", "abc123"));
  assert(!secretsMatch("abc", "abc123"));
});

Deno.test("push language: unknown codes count as German", () => {
  assertEquals(pushLanguage("tr"), "tr");
  assertEquals(pushLanguage("xx"), "de");
  assertEquals(pushLanguage(undefined), "de");
  assertEquals(pushLanguage("toString"), "de");
  assertEquals(PUSH_LANGUAGES.length, 13);
});

Deno.test("push language: every language has all five titles, different from each other", () => {
  const events = ["new", "changed", "canceled", "removed", "deleted"] as const;
  for (const lang of PUSH_LANGUAGES) {
    const titles = events.map((e) => pushText(e, appt, "Europe/Berlin", lang).title);
    assertEquals(new Set(titles).size, 5, lang);
    for (const t of titles) assertEquals(t.trim().length > 0, true, lang);
  }
});

Deno.test("push language: the title and the weekday follow the language, the numbers stay", () => {
  assertEquals(pushText("new", appt, "Europe/Berlin", "en").title, "New appointment");
  assertEquals(pushText("canceled", appt, "Europe/Berlin", "tr").title, "Randevu iptal edildi");
  assertEquals(pushText("new", appt, "Europe/Berlin", "ar").title, "موعد جديد");
  // 12 October 2026 is a Monday
  assertEquals(whenLabel("2026-10-12T06:00:00Z", "Europe/Berlin", "en"), "Mon 12.10. 08:00");
  assertEquals(whenLabel("2026-10-12T06:00:00Z", "Europe/Berlin", "de"), "Mo 12.10. 08:00");
  for (const lang of PUSH_LANGUAGES) {
    const label = whenLabel("2026-10-12T06:00:00Z", "Europe/Berlin", lang);
    assertEquals(/12\.10\. 08:00$/.test(label), true, `${lang}: ${label}`); // Western digits everywhere
    assertEquals(label.split(" ")[0].length > 0, true, lang);
  }
  // the German text is unchanged by the new parameter
  assertEquals(pushText("new", appt).title, "Neuer Termin");
});
