// paystack-initialize
// User-initiated (verify_jwt = true). Creates a PENDING donation (one-time) or a
// PENDING recurring mandate + Paystack plan, calls Paystack to start the
// transaction, and returns the checkout authorization_url. The Paystack SECRET
// key stays here; the client only ever receives the checkout URL + reference.
//
// Body: { fund_id?, amount_kobo, kind: 'one_time' | 'recurring',
//         interval?: 'weekly'|'monthly'|'quarterly'|'annually',
//         anonymous?: boolean, note?: string, callback_url?: string }
import { createClient } from "jsr:@supabase/supabase-js@2";
import { serviceClient, json } from "../_shared/supabase.ts";

const PAYSTACK = "https://api.paystack.co";

function genRef(): string {
  return "gv_" + crypto.randomUUID().replace(/-/g, "");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const secret = Deno.env.get("PAYSTACK_SECRET_KEY");
  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  if (!secret || !url || !anon) return json({ error: "server not configured" }, 500);

  // Identify the caller from their JWT.
  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
  const { data: { user }, error: uErr } = await userClient.auth.getUser();
  if (uErr || !user) return json({ error: "unauthorized" }, 401);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "invalid JSON" }, 400); }

  const amount = Number(body.amount_kobo);
  const kind = body.kind === "recurring" ? "recurring" : "one_time";
  const fundId = (body.fund_id as string) ?? null;
  const anonymous = body.anonymous === true;
  const note = (body.note as string) ?? null;
  const callbackUrl = (body.callback_url as string) ?? undefined;
  if (!Number.isInteger(amount) || amount <= 0) return json({ error: "amount_kobo must be a positive integer (kobo)" }, 400);

  const svc = serviceClient();

  // Resolve the caller's profile + parish.
  const { data: profile, error: pErr } = await svc
    .from("user_profiles").select("id, parish_id").eq("auth_id", user.id).maybeSingle();
  if (pErr || !profile) return json({ error: "no profile" }, 400);

  // Validate the fund (if supplied) is active and in the caller's parish.
  if (fundId) {
    const { data: fund } = await svc
      .from("giving_funds").select("id, active, parish_id").eq("id", fundId).maybeSingle();
    if (!fund || fund.active !== true || fund.parish_id !== profile.parish_id) {
      return json({ error: "invalid or inactive fund" }, 400);
    }
  }

  const email = user.email ?? `${profile.id}@no-email.mathetes.app`;

  if (kind === "recurring") {
    const interval = String(body.interval ?? "monthly");
    if (!["weekly", "monthly", "quarterly", "annually"].includes(interval)) {
      return json({ error: "invalid interval" }, 400);
    }
    // 1) Create a Paystack plan for this mandate.
    const planRes = await fetch(`${PAYSTACK}/plan`, {
      method: "POST",
      headers: { Authorization: `Bearer ${secret}`, "Content-Type": "application/json" },
      body: JSON.stringify({ name: `Mathetes giving ${interval} ${amount}`, interval, amount }),
    });
    const planJson = await planRes.json();
    if (!planRes.ok || !planJson.status) return json({ error: "paystack plan failed", detail: planJson.message }, 502);
    const planCode = planJson.data.plan_code;

    // 2) Record the pending mandate.
    const { data: rec, error: rErr } = await svc.from("giving_recurring").insert({
      parish_id: profile.parish_id, user_id: profile.id, fund_id: fundId,
      amount_kobo: amount, interval, anonymous, note,
      paystack_plan_code: planCode, status: "pending",
    }).select("id").single();
    if (rErr) return json({ error: rErr.message }, 500);

    // 3) Initialize a transaction tied to the plan (creates the subscription on first charge).
    const initRes = await fetch(`${PAYSTACK}/transaction/initialize`, {
      method: "POST",
      headers: { Authorization: `Bearer ${secret}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        email, amount, plan: planCode, callback_url: callbackUrl,
        metadata: { recurring_id: rec.id, profile_id: profile.id, parish_id: profile.parish_id, fund_id: fundId, kind: "recurring" },
      }),
    });
    const initJson = await initRes.json();
    if (!initRes.ok || !initJson.status) return json({ error: "paystack init failed", detail: initJson.message }, 502);
    // access_code is returned so the client may use the Paystack inline/popup SDK
    // (resumeTransaction) instead of opening authorization_url; either works.
    return json({
      authorization_url: initJson.data.authorization_url,
      access_code: initJson.data.access_code,
      reference: initJson.data.reference,
      recurring_id: rec.id,
    });
  }

  // one_time
  const reference = genRef();
  const { error: dErr } = await svc.from("donations").insert({
    parish_id: profile.parish_id, user_id: profile.id, fund_id: fundId,
    amount_kobo: amount, kind: "one_time", status: "pending", reference, anonymous, note,
  });
  if (dErr) return json({ error: dErr.message }, 500);

  const initRes = await fetch(`${PAYSTACK}/transaction/initialize`, {
    method: "POST",
    headers: { Authorization: `Bearer ${secret}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      email, amount, reference, callback_url: callbackUrl,
      metadata: { profile_id: profile.id, parish_id: profile.parish_id, fund_id: fundId, kind: "one_time" },
    }),
  });
  const initJson = await initRes.json();
  if (!initRes.ok || !initJson.status) {
    await svc.from("donations").update({ status: "abandoned" }).eq("reference", reference);
    return json({ error: "paystack init failed", detail: initJson.message }, 502);
  }
  // authorization_url for the redirect flow; access_code for the inline SDK.
  return json({
    authorization_url: initJson.data.authorization_url,
    access_code: initJson.data.access_code,
    reference,
  });
});
