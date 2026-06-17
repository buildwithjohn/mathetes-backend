// paystack-webhook
// Paystack-initiated (verify_jwt = false). Verifies the x-paystack-signature
// (HMAC-SHA512 of the raw body with the secret key), logs every event for audit
// + idempotency, and records giving outcomes. Service-role; never trusts the
// payload without a valid signature.
//
// Handled events:
//   charge.success            -> mark/insert a successful donation
//   subscription.create       -> activate the recurring mandate
//   invoice.payment_failed    -> flag the mandate 'attention'
//   subscription.disable /
//   subscription.not_renew    -> cancel the mandate
import { createHmac } from "node:crypto";
import { serviceClient, json } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const secret = Deno.env.get("PAYSTACK_SECRET_KEY");
  if (!secret) return json({ error: "server not configured" }, 500);

  const raw = await req.text();
  const sig = req.headers.get("x-paystack-signature") ?? "";
  const expected = createHmac("sha512", secret).update(raw).digest("hex");
  const valid = sig.length === expected.length && sig === expected;

  let event: any;
  try { event = JSON.parse(raw); } catch { return json({ error: "invalid JSON" }, 400); }

  const svc = serviceClient();
  const data = event?.data ?? {};
  const paystackId = data?.id ? String(data.id) : null;
  const reference = data?.reference ?? null;

  // Log every event (idempotency key = data.id where present).
  await svc.from("paystack_events").insert({
    event_type: event?.event ?? "unknown",
    reference, paystack_id: paystackId, signature_valid: valid,
    processed: false, payload: event,
  }).select("id").maybeSingle();

  // Never act on an unverified payload.
  if (!valid) return json({ error: "invalid signature" }, 401);

  // Idempotency: if we've already processed this exact event id, stop.
  if (paystackId) {
    const { count } = await svc.from("paystack_events")
      .select("id", { count: "exact", head: true })
      .eq("paystack_id", paystackId).eq("processed", true);
    if ((count ?? 0) > 0) return json({ ok: true, deduped: true });
  }

  const meta = data?.metadata ?? {};
  try {
    switch (event.event) {
      case "charge.success": {
        const channel = data?.channel ?? null;
        const fees = data?.fees ?? null;
        const amount = data?.amount ?? null;
        // Match the pending one-time donation by our reference.
        const { data: existing } = await svc.from("donations").select("id").eq("reference", reference).maybeSingle();
        if (existing) {
          await svc.from("donations").update({
            status: "success", paid_at: new Date().toISOString(),
            channel, fees_kobo: fees, paystack_reference: reference,
          }).eq("id", existing.id);
        } else if (meta?.recurring_id || meta?.kind === "recurring" || data?.plan) {
          // A recurring cycle charge (Paystack generated its own reference).
          await svc.from("donations").insert({
            parish_id: meta.parish_id, user_id: meta.profile_id, fund_id: meta.fund_id ?? null,
            recurring_id: meta.recurring_id ?? null, amount_kobo: amount, kind: "recurring",
            status: "success", reference: reference, paystack_reference: reference,
            channel, fees_kobo: fees, paid_at: new Date().toISOString(),
          });
        }
        break;
      }
      case "subscription.create": {
        const planCode = data?.plan?.plan_code ?? data?.plan;
        const patch: Record<string, unknown> = {
          status: "active",
          paystack_subscription_code: data?.subscription_code ?? null,
          paystack_customer_code: data?.customer?.customer_code ?? null,
          paystack_email_token: data?.email_token ?? null,
          next_payment_at: data?.next_payment_date ?? null,
          started_at: new Date().toISOString(),
        };
        if (meta?.recurring_id) {
          await svc.from("giving_recurring").update(patch).eq("id", meta.recurring_id);
        } else if (planCode) {
          await svc.from("giving_recurring").update(patch).eq("paystack_plan_code", planCode).eq("status", "pending");
        }
        break;
      }
      case "invoice.payment_failed": {
        const subCode = data?.subscription?.subscription_code ?? data?.subscription_code;
        if (subCode) await svc.from("giving_recurring").update({ status: "attention" }).eq("paystack_subscription_code", subCode);
        break;
      }
      case "subscription.disable":
      case "subscription.not_renew": {
        const subCode = data?.subscription_code;
        if (subCode) {
          await svc.from("giving_recurring").update({
            status: "cancelled", cancelled_at: new Date().toISOString(),
          }).eq("paystack_subscription_code", subCode);
        }
        break;
      }
      default:
        // Unhandled event: logged above, nothing to do.
        break;
    }
    if (paystackId) {
      await svc.from("paystack_events").update({ processed: true, processed_at: new Date().toISOString() })
        .eq("paystack_id", paystackId);
    }
    return json({ ok: true });
  } catch (e) {
    if (paystackId) await svc.from("paystack_events").update({ error: String(e) }).eq("paystack_id", paystackId);
    return json({ error: "processing failed" }, 500);
  }
});
