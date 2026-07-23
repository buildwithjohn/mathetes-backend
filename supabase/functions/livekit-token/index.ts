// livekit-token
//
// Issues a short-lived LiveKit room token only to an active member of the
// Circle that owns the requested prayer meeting. The LiveKit API secret never
// leaves this Edge Function; clients receive a signed, room-scoped JWT only.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { json, serviceClient } from "../_shared/supabase.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function response(body: unknown, status = 200): Response {
  const base = json(body, status);
  for (const [key, value] of Object.entries(CORS)) base.headers.set(key, value);
  return base;
}

function base64url(value: Uint8Array | string): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

async function signJwt(header: Record<string, unknown>, payload: Record<string, unknown>, secret: string): Promise<string> {
  const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(signingInput)));
  return `${signingInput}.${base64url(signature)}`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return response({ error: "method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const livekitUrl = Deno.env.get("LIVEKIT_URL");
  const livekitApiKey = Deno.env.get("LIVEKIT_API_KEY");
  const livekitApiSecret = Deno.env.get("LIVEKIT_API_SECRET");
  if (!url || !anonKey || !livekitUrl || !livekitApiKey || !livekitApiSecret) {
    return response({ error: "LiveKit is not configured" }, 503);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(url, anonKey, {
    auth: { persistSession: false },
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) return response({ error: "unauthorized" }, 401);

  let meetingId: string;
  try {
    const body = await req.json();
    meetingId = typeof body.meeting_id === "string" ? body.meeting_id : "";
  } catch {
    return response({ error: "invalid JSON" }, 400);
  }
  if (!meetingId) return response({ error: "meeting_id is required" }, 400);

  const svc = serviceClient();
  const { data: profile, error: profileError } = await svc
    .from("user_profiles")
    .select("id, name, parish_id, status")
    .eq("auth_id", user.id)
    .maybeSingle();
  if (profileError || !profile || profile.status !== "active") {
    return response({ error: "active membership required" }, 403);
  }

  const { data: meeting, error: meetingError } = await svc
    .from("circle_meetings")
    .select("id, chat_id, parish_id, title, mode, status, room_name")
    .eq("id", meetingId)
    .maybeSingle();
  if (meetingError || !meeting || meeting.status !== "live" || meeting.parish_id !== profile.parish_id) {
    return response({ error: "live meeting not found" }, 404);
  }

  const { data: membership } = await svc
    .from("chat_members")
    .select("user_id")
    .eq("chat_id", meeting.chat_id)
    .eq("user_id", profile.id)
    .maybeSingle();
  if (!membership) return response({ error: "you are not a member of this Circle" }, 403);

  const now = Math.floor(Date.now() / 1000);
  const allowedSources = meeting.mode === "audio" ? ["microphone"] : ["microphone", "camera"];
  const token = await signJwt(
    { alg: "HS256", typ: "JWT" },
    {
      iss: livekitApiKey,
      sub: profile.id,
      name: profile.name || "Mathetes member",
      nbf: now - 5,
      exp: now + 15 * 60,
      metadata: JSON.stringify({ profile_id: profile.id, meeting_id: meeting.id }),
      video: {
        room: meeting.room_name,
        roomJoin: true,
        canPublish: true,
        canPublishData: true,
        canPublishSources: allowedSources,
        canSubscribe: true,
      },
    },
    livekitApiSecret,
  );

  return response({
    token,
    url: livekitUrl,
    room: meeting.room_name,
    meeting: { id: meeting.id, title: meeting.title, mode: meeting.mode },
    expires_at: new Date((now + 15 * 60) * 1000).toISOString(),
  });
});
