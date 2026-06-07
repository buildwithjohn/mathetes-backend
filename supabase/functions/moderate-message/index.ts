// moderate-message
// Triggered by a Database Webhook on INSERT into public.messages.
// Runs the message body through the OpenAI Moderation API. If flagged, the
// message is soft-deleted and the decision is recorded in moderation_log.
import { serviceClient, json, type WebhookPayload } from "../_shared/supabase.ts";

interface MessageRow {
  id: string;
  body: string | null;
  kind: string;
  deleted_at: string | null;
}

const MODERATION_URL = "https://api.openai.com/v1/moderations";

// Map OpenAI category -> our severity bucket.
const HIGH = new Set(["sexual/minors", "self-harm/intent", "violence/graphic"]);
const MEDIUM = new Set(["self-harm", "harassment/threatening", "hate/threatening", "violence"]);

Deno.serve(async (req) => {
  let payload: WebhookPayload<MessageRow>;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid JSON" }, 400);
  }

  const m = payload.record;
  if (payload.type !== "INSERT" || payload.table !== "messages" || !m) {
    return json({ skipped: true });
  }
  // Only moderate user text; nothing to scan on system/voice/image-only rows.
  if (!m.body || m.body.trim() === "" || m.kind === "system" || m.deleted_at) {
    return json({ skipped: "nothing to moderate" });
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) return json({ error: "OPENAI_API_KEY not set" }, 500);

  const res = await fetch(MODERATION_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${apiKey}` },
    body: JSON.stringify({ model: "omni-moderation-latest", input: m.body }),
  });
  if (!res.ok) {
    return json({ error: `moderation API ${res.status}` }, 502);
  }
  const data = await res.json();
  const result = data?.results?.[0];
  if (!result || !result.flagged) {
    return json({ flagged: false });
  }

  const flags: string[] = Object.entries(result.categories ?? {})
    .filter(([, v]) => v === true)
    .map(([k]) => k);
  const severity = flags.some((f) => HIGH.has(f))
    ? "high"
    : flags.some((f) => MEDIUM.has(f))
    ? "medium"
    : "low";

  const supabase = serviceClient();

  // Soft-delete the offending message.
  await supabase
    .from("messages")
    .update({ deleted_at: new Date().toISOString() })
    .eq("id", m.id);

  // Log every flagged category for moderator review.
  await supabase.from("moderation_log").insert(
    flags.map((flag) => ({
      message_id: m.id,
      flag,
      severity,
      action_taken: "soft_deleted",
    })),
  );

  return json({ flagged: true, flags, severity });
});
