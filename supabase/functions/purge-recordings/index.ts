// Daily job (pg_cron -> pg_net): deletes the audio files of voice notes whose job was closed longer
// ago than the business's retention period (default 90 days). The note text and positions stay.
// It also removes job photo files that no photo row points to any more (orphans).
// Not callable by app users: it needs the shared secret in the x-cron-secret header.
import { createClient } from "jsr:@supabase/supabase-js@2";

const BATCH = 200;

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("CRON_SECRET");
  const given = req.headers.get("x-cron-secret") ?? "";
  if (!secret || !constantTimeEqual(secret, given)) return new Response("Forbidden", { status: 403 });

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  let deleted = 0;
  let failed = 0;
  // Several rounds, so a backlog is cleared; stop when nothing is left or after a safe number.
  for (let round = 0; round < 10; round++) {
    const { data: due, error } = await supabase.rpc("recordings_due_for_deletion", { p_limit: BATCH });
    if (error) {
      console.error("[purge-recordings] listing failed:", error);
      return new Response("Error", { status: 500 });
    }
    if (!due || due.length === 0) break;

    const ids: string[] = [];
    for (const row of due as { id: string; audio_storage_path: string }[]) {
      const { error: rmErr } = await supabase.storage.from("captures").remove([row.audio_storage_path]);
      if (rmErr) {
        failed++;
        console.error("[purge-recordings] could not remove a file:", rmErr);
      } else {
        ids.push(row.id); // removing a file that is already gone is not an error
      }
    }
    if (ids.length > 0) {
      const { error: markErr } = await supabase.rpc("mark_recordings_deleted", { p_ids: ids });
      if (markErr) {
        console.error("[purge-recordings] could not mark:", markErr);
        return new Response("Error", { status: 500 });
      }
      deleted += ids.length;
    }
    if (ids.length === 0) break; // nothing could be removed: do not loop forever
  }

  // Photo files without a row (job deleted, photo removed while a phone was offline) still count
  // against the storage: remove them too.
  let photosRemoved = 0;
  for (let round = 0; round < 5; round++) {
    const { data: orphans, error } = await supabase.rpc("orphan_photo_files", { p_limit: BATCH });
    if (error) {
      console.error("[purge-recordings] listing photo files failed:", error);
      break;
    }
    if (!orphans || orphans.length === 0) break;
    const names = (orphans as { name: string }[]).map((o) => o.name);
    const { error: rmErr } = await supabase.storage.from("captures").remove(names);
    if (rmErr) {
      console.error("[purge-recordings] could not remove photo files:", rmErr);
      break;
    }
    photosRemoved += names.length;
  }

  return new Response(JSON.stringify({ deleted, failed, photosRemoved }), { headers: { "Content-Type": "application/json" } });
});
