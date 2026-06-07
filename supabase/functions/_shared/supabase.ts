// Shared helpers for Mathetes edge functions (Deno runtime).
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

// A service-role client: bypasses RLS. Only ever used server-side inside edge
// functions, never shipped to a client.
export function serviceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set");
  }
  return createClient(url, key, { auth: { persistSession: false } });
}

// Shape of a Supabase Database Webhook payload.
export interface WebhookPayload<T = Record<string, unknown>> {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  schema: string;
  record: T | null;
  old_record: T | null;
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
