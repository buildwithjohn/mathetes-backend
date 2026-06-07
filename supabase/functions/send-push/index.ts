// send-push
// Triggered by a Database Webhook on INSERT into public.notifications.
// Looks up the recipient's Expo push tokens, honours their per-type push
// preference, and delivers via the Expo Push API. Invalid tokens are pruned.
import { serviceClient, json, type WebhookPayload } from "../_shared/supabase.ts";

interface NotificationRow {
  id: string;
  user_id: string;
  type: string;
  title: string;
  preview: string | null;
  target_url: string | null;
}

interface ExpoMessage {
  to: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
  sound: "default";
}

const EXPO_PUSH_URL = "https://exp.host/--/api/v2/push/send";

Deno.serve(async (req) => {
  let payload: WebhookPayload<NotificationRow>;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid JSON" }, 400);
  }

  const n = payload.record;
  if (payload.type !== "INSERT" || payload.table !== "notifications" || !n) {
    return json({ skipped: true });
  }

  const supabase = serviceClient();

  // Respect an explicit push opt-out for this notification type.
  const { data: pref } = await supabase
    .from("notification_preferences")
    .select("enabled")
    .eq("user_id", n.user_id)
    .eq("type", n.type)
    .eq("channel", "push")
    .maybeSingle();
  if (pref && pref.enabled === false) {
    return json({ skipped: "push disabled for type" });
  }

  const { data: tokens, error } = await supabase
    .from("push_tokens")
    .select("expo_token")
    .eq("user_id", n.user_id);
  if (error) return json({ error: error.message }, 500);
  if (!tokens || tokens.length === 0) return json({ skipped: "no tokens" });

  const messages: ExpoMessage[] = tokens.map((t) => ({
    to: t.expo_token,
    title: n.title,
    body: n.preview ?? "",
    data: { notificationId: n.id, type: n.type, url: n.target_url },
    sound: "default",
  }));

  const res = await fetch(EXPO_PUSH_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "Accept-Encoding": "gzip, deflate",
    },
    body: JSON.stringify(messages),
  });
  const result = await res.json().catch(() => ({}));

  // Prune tokens Expo reports as unregistered/invalid.
  const tickets = result?.data ?? [];
  const dead: string[] = [];
  tickets.forEach((ticket: { status?: string; details?: { error?: string } }, i: number) => {
    if (ticket?.status === "error" && ticket?.details?.error === "DeviceNotRegistered") {
      dead.push(messages[i].to);
    }
  });
  if (dead.length > 0) {
    await supabase.from("push_tokens").delete().in("expo_token", dead);
  }

  return json({ sent: messages.length, pruned: dead.length });
});
