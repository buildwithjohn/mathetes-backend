// paystack-manage-recurring
// User-initiated (verify_jwt = true). Lets a giver cancel / pause / resume their
// OWN recurring mandate. Paystack has no native "pause", so pause = disable the
// subscription (status 'paused') and resume = enable it (status 'active');
// cancel = disable (status 'cancelled'). Ownership is enforced before any
// Paystack call; the secret key stays server-side.
//
// Body: { recurring_id: string, action: 'cancel' | 'pause' | 'resume' }
import { createClient } from "jsr:@supabase/supabase-js@2";
import { serviceClient, json } from "../_shared/supabase.ts";

const PAYSTACK = "https://api.paystack.co";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const secret = Deno.env.get("PAYSTACK_SECRET_KEY");
  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  if (!secret || !url || !anon) return json({ error: "server not configured" }, 500);

  // Identify the caller.
  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
  const { data: { user }, error: uErr } = await userClient.auth.getUser();
  if (uErr || !user) return json({ error: "unauthorized" }, 401);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "invalid JSON" }, 400); }
  const recurringId = String(body.recurring_id ?? "");
  const action = String(body.action ?? "");
  if (!recurringId) return json({ error: "recurring_id required" }, 400);
  if (!["cancel", "pause", "resume"].includes(action)) return json({ error: "action must be cancel|pause|resume" }, 400);

  const svc = serviceClient();

  // Resolve caller profile and load the mandate; enforce ownership.
  const { data: profile } = await svc.from("user_profiles").select("id").eq("auth_id", user.id).maybeSingle();
  if (!profile) return json({ error: "no profile" }, 400);

  const { data: rec } = await svc.from("giving_recurring")
    .select("id, user_id, status, paystack_subscription_code, paystack_email_token")
    .eq("id", recurringId).maybeSingle();
  if (!rec) return json({ error: "mandate not found" }, 404);
  if (rec.user_id !== profile.id) return json({ error: "not your mandate" }, 403);

  const enable = action === "resume";
  const endpoint = enable ? "enable" : "disable";

  // Only call Paystack if the subscription actually exists there.
  if (rec.paystack_subscription_code && rec.paystack_email_token) {
    const res = await fetch(`${PAYSTACK}/subscription/${endpoint}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${secret}`, "Content-Type": "application/json" },
      body: JSON.stringify({ code: rec.paystack_subscription_code, token: rec.paystack_email_token }),
    });
    const j = await res.json().catch(() => ({}));
    if (!res.ok || j.status === false) {
      return json({ error: "paystack update failed", detail: j.message }, 502);
    }
  }
  // (If the subscription isn't active yet on Paystack, we still update our state;
  //  the webhook reconciles once it exists.)

  const newStatus = action === "cancel" ? "cancelled" : action === "pause" ? "paused" : "active";
  const patch: Record<string, unknown> = { status: newStatus };
  if (action === "cancel") patch.cancelled_at = new Date().toISOString();

  const { error: upErr } = await svc.from("giving_recurring").update(patch).eq("id", recurringId);
  if (upErr) return json({ error: upErr.message }, 500);

  return json({ ok: true, recurring_id: recurringId, status: newStatus });
});
