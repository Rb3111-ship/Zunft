// Called by the database (pg_net, from a trigger on appointments) when a person must be told about
// an appointment. Looks up the phones of those people and sends a push message through Firebase
// Cloud Messaging. Not callable by app users: it needs the shared secret in x-notify-secret.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  fcmMessage,
  isDeadToken,
  isPushEvent,
  parseServiceAccount,
  pushLanguage,
  pushText,
  secretsMatch,
  signGoogleJwt,
} from "../_shared/push.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

let cached: { token: string; until: number } | null = null;

async function accessToken(): Promise<{ token: string; projectId: string }> {
  const sa = parseServiceAccount(Deno.env.get("FCM_SERVICE_ACCOUNT_B64"));
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.until > now + 60) return { token: cached.token, projectId: sa.project_id };
  const jwt = await signGoogleJwt(sa, now);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  if (!res.ok) throw new Error(`Google sign-in failed: ${res.status}`);
  const j = await res.json();
  cached = { token: j.access_token as string, until: now + Number(j.expires_in ?? 3000) };
  return { token: cached.token, projectId: sa.project_id };
}

Deno.serve(async (req) => {
  const given = req.headers.get("x-notify-secret") ?? "";
  if (!secretsMatch(given, Deno.env.get("NOTIFY_SECRET") ?? "")) return new Response("Forbidden", { status: 403 });

  let body: { event?: unknown; user_ids?: unknown; appointment?: Record<string, unknown> };
  try {
    body = await req.json();
  } catch {
    return new Response("Bad request", { status: 400 });
  }
  const a = body.appointment;
  const users = Array.isArray(body.user_ids) ? body.user_ids.filter((u): u is string => typeof u === "string" && UUID_RE.test(u)) : [];
  if (!isPushEvent(body.event) || !a || typeof a.id !== "string" || typeof a.title !== "string" || typeof a.starts_at !== "string") {
    return new Response("Bad request", { status: 400 });
  }
  if (users.length === 0) return new Response(JSON.stringify({ sent: 0 }), { headers: { "Content-Type": "application/json" } });

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: rows, error } = await supabase.from("device_tokens").select("token, language").in("user_id", users);
  if (error) {
    console.error("[notify-appointment] tokens:", error);
    return new Response("Error", { status: 500 });
  }
  const phones = (rows ?? []).map((r) => ({ token: r.token as string, language: pushLanguage(r.language) }));
  const tokens = phones.map((p) => p.token);
  if (tokens.length === 0) return new Response(JSON.stringify({ sent: 0 }), { headers: { "Content-Type": "application/json" } });

  const appt = { id: a.id, title: a.title, starts_at: a.starts_at, location: typeof a.location === "string" ? a.location : null };

  let sent = 0;
  let dead = 0;
  try {
    const { token: access, projectId } = await accessToken();
    for (const { token: t, language } of phones) {
      const text = pushText(body.event, appt, "Europe/Berlin", language); // in the language of that phone
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
        body: JSON.stringify(fcmMessage(t, text, appt, body.event)),
      });
      if (res.ok) {
        sent++;
      } else {
        const answer = await res.json().catch(() => undefined);
        if (isDeadToken(res.status, answer)) {
          dead++;
          await supabase.from("device_tokens").delete().eq("token", t);
        } else {
          console.error("[notify-appointment] FCM answered", res.status, JSON.stringify(answer));
        }
      }
    }
  } catch (err) {
    console.error("[notify-appointment] failed:", err);
    return new Response("Error", { status: 502 });
  }
  return new Response(JSON.stringify({ sent, dead }), { headers: { "Content-Type": "application/json" } });
});
