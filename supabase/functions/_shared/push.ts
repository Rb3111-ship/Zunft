// Pure helpers for the push messages about appointments: the wording, the Google sign-in
// (a signed JWT exchanged for an access token) and the reading of FCM errors. No network and no
// Deno-only APIs except WebCrypto (available in Deno and Node), so it can be unit tested
// (see push_test.ts).

export type PushEvent = "new" | "changed" | "canceled" | "removed" | "deleted";

export interface PushAppointment {
  id: string;
  title: string;
  starts_at: string; // ISO timestamp
  location?: string | null;
}

export interface PushText {
  title: string;
  body: string;
}

const EVENTS: readonly string[] = ["new", "changed", "canceled", "removed", "deleted"];

export function isPushEvent(v: unknown): v is PushEvent {
  return typeof v === "string" && EVENTS.includes(v);
}

/** "Mo 12.10. 08:00" in the time zone of the business (never the server's). */
export function whenLabel(iso: string, timeZone = "Europe/Berlin"): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  const parts = new Intl.DateTimeFormat("de-DE", {
    timeZone,
    weekday: "short",
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(d);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
  const weekday = get("weekday").replace(".", "");
  return `${weekday} ${get("day")}.${get("month")}. ${get("hour")}:${get("minute")}`;
}

function clip(s: string, max: number): string {
  const t = s.trim();
  return t.length > max ? t.slice(0, max - 1) + "…" : t;
}

/** The notification text. The title says what happened, the body says which appointment. */
export function pushText(event: PushEvent, a: PushAppointment, timeZone = "Europe/Berlin"): PushText {
  const place = (a.location ?? "").trim();
  const what = `${whenLabel(a.starts_at, timeZone)} · ${clip(a.title, 80)}${place ? `, ${clip(place, 60)}` : ""}`;
  switch (event) {
    case "new":
      return { title: "Neuer Termin", body: what };
    case "changed":
      return { title: "Termin geändert", body: what };
    case "canceled":
      return { title: "Termin abgesagt", body: what };
    case "removed":
      return { title: "Termin entfällt für dich", body: what };
    case "deleted":
      return { title: "Termin gelöscht", body: what };
  }
}

export function base64Url(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

/** The PEM text of a Google service-account private key as the bytes WebCrypto wants (PKCS #8). */
export function pemToPkcs8(pem: string): Uint8Array {
  const body = pem.replace(/-----BEGIN [A-Z ]+-----/, "").replace(/-----END [A-Z ]+-----/, "").replace(/\s+/g, "");
  const bin = atob(body);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

/** Reads the service account from the secret (base64 of the JSON file) and checks its shape. */
export function parseServiceAccount(b64: string | undefined | null): ServiceAccount {
  if (!b64) throw new Error("FCM service account secret is missing");
  let json: unknown;
  try {
    json = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))));
  } catch {
    throw new Error("FCM service account secret is not valid");
  }
  const o = json as Record<string, unknown>;
  if (typeof o?.client_email !== "string" || typeof o?.private_key !== "string" || typeof o?.project_id !== "string") {
    throw new Error("FCM service account secret lacks client_email, private_key or project_id");
  }
  return { client_email: o.client_email, private_key: o.private_key, project_id: o.project_id };
}

/** The signed request that is exchanged for a one-hour access token at Google. */
export async function signGoogleJwt(sa: ServiceAccount, nowSeconds: number): Promise<string> {
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64Url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  }));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`)));
  return `${header}.${claims}.${base64Url(sig)}`;
}

/** The FCM v1 message for one phone. */
export function fcmMessage(token: string, text: PushText, a: PushAppointment, event: PushEvent) {
  return {
    message: {
      token,
      notification: { title: text.title, body: text.body },
      data: { type: "appointment", event, appointment_id: a.id },
      android: { priority: "HIGH", notification: { channel_id: "appointments_push" } },
    },
  };
}

/**
 * Does this FCM answer mean the phone address is dead (app uninstalled, token expired)? Then the
 * token is deleted. Other errors (a hiccup at Google) keep the token.
 */
export function isDeadToken(status: number, body: unknown): boolean {
  if (status === 404) return true;
  const o = body as { error?: { status?: string; details?: { errorCode?: string }[] } } | undefined;
  const codes = (o?.error?.details ?? []).map((d) => d.errorCode);
  return codes.includes("UNREGISTERED") || (status === 400 && o?.error?.status === "INVALID_ARGUMENT" && codes.includes("INVALID_ARGUMENT"));
}

/** A timing-safe comparison for the shared secret header. */
export function secretsMatch(given: string, expected: string): boolean {
  if (!expected || given.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < given.length; i++) diff |= given.charCodeAt(i) ^ expected.charCodeAt(i);
  return diff === 0;
}
