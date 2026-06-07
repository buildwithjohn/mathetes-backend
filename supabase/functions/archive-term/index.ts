// archive-term
// Scheduled. Archives house/discipler/DM chat history a set interval after an
// academic term ends, per the pastoral guardrail ("term-end chat archive resets
// are automatic"). Archiving is a SOFT delete (sets messages.deleted_at) so a
// report trail and moderation history survive; nothing is hard-deleted here.
//
// Safety: defaults to a DRY RUN. It only mutates when ARCHIVE_CONFIRM=true, so a
// misconfigured schedule can never silently wipe a term of conversations. The
// term boundary comes from TERM_END_DATE (ISO date) and ARCHIVE_AFTER_DAYS
// (default 60). Announcements are never archived.
import { serviceClient, json } from "../_shared/supabase.ts";

Deno.serve(async () => {
  const termEnd = Deno.env.get("TERM_END_DATE"); // e.g. "2026-07-31"
  if (!termEnd) {
    return json({ skipped: "TERM_END_DATE not set" });
  }
  const afterDays = Number(Deno.env.get("ARCHIVE_AFTER_DAYS") ?? "60");
  const confirm = Deno.env.get("ARCHIVE_CONFIRM") === "true";

  const cutoff = new Date(`${termEnd}T00:00:00Z`);
  const archiveOnOrAfter = new Date(cutoff.getTime() + afterDays * 86_400_000);
  const now = new Date();

  if (now < archiveOnOrAfter) {
    return json({
      skipped: "archive window not reached",
      term_end: termEnd,
      archive_on: archiveOnOrAfter.toISOString().slice(0, 10),
    });
  }

  const supabase = serviceClient();

  // Messages from archivable chat kinds, created on/before term end, not yet
  // soft-deleted.
  const { data: chats } = await supabase
    .from("chats")
    .select("id")
    .in("kind", ["house_group", "discipler", "dm"]);
  const chatIds = (chats ?? []).map((c) => c.id);
  if (chatIds.length === 0) return json({ archived: 0 });

  const { count } = await supabase
    .from("messages")
    .select("id", { count: "exact", head: true })
    .in("chat_id", chatIds)
    .lte("created_at", cutoff.toISOString())
    .is("deleted_at", null);

  if (!confirm) {
    return json({ dry_run: true, would_archive: count ?? 0, term_end: termEnd });
  }

  const { error } = await supabase
    .from("messages")
    .update({ deleted_at: now.toISOString() })
    .in("chat_id", chatIds)
    .lte("created_at", cutoff.toISOString())
    .is("deleted_at", null);
  if (error) return json({ error: error.message }, 500);

  return json({ archived: count ?? 0, term_end: termEnd });
});
