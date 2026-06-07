// daily-content-publish
// Scheduled (cron, ~00:01 UTC). Flips scheduled content whose publish_date has
// arrived to 'published', then notifies each parish's members about today's
// Word of the Day. Inserting the notification rows triggers send-push.
//
// Idempotent: only freshly-published WOTD produce notifications, and we guard
// against re-notifying if the job runs more than once in a day.
import { serviceClient, json } from "../_shared/supabase.ts";

Deno.serve(async () => {
  const supabase = serviceClient();
  const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD (UTC)

  // 1. Publish anything scheduled for today or earlier.
  await supabase
    .from("devotionals")
    .update({ status: "published" })
    .eq("status", "scheduled")
    .lte("publish_date", today);

  const { data: publishedWotd } = await supabase
    .from("word_of_day")
    .update({ status: "published" })
    .eq("status", "scheduled")
    .lte("publish_date", today)
    .select("id, parish_id, verse_ref, publish_date");

  // Also pick up WOTD already published for today (covers content created as
  // 'published' directly), so members still get the morning notification.
  const { data: todaysWotd } = await supabase
    .from("word_of_day")
    .select("id, parish_id, verse_ref, publish_date")
    .eq("status", "published")
    .eq("publish_date", today);

  const wotdByParish = new Map<string, { id: string; verse_ref: string }>();
  for (const w of [...(publishedWotd ?? []), ...(todaysWotd ?? [])]) {
    wotdByParish.set(w.parish_id, { id: w.id, verse_ref: w.verse_ref });
  }

  let notified = 0;
  for (const [parishId, wotd] of wotdByParish) {
    const { data: members } = await supabase
      .from("user_profiles")
      .select("id")
      .eq("parish_id", parishId);
    if (!members || members.length === 0) continue;

    // Skip members who already have today's WOTD notification (re-run guard).
    const { data: already } = await supabase
      .from("notifications")
      .select("user_id")
      .eq("type", "system")
      .eq("target_id", wotd.id);
    const seen = new Set((already ?? []).map((a) => a.user_id));

    const rows = members
      .filter((m) => !seen.has(m.id))
      .map((m) => ({
        user_id: m.id,
        type: "system",
        title: "Today's Word",
        preview: wotd.verse_ref,
        target_id: wotd.id,
        target_url: `mathetes://word/${today}`,
      }));

    if (rows.length > 0) {
      const { error } = await supabase.from("notifications").insert(rows);
      if (!error) notified += rows.length;
    }
  }

  return json({ date: today, parishes_notified: wotdByParish.size, notifications: notified });
});
