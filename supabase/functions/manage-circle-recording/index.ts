// manage-circle-recording
//
// Starts/stops LiveKit Egress for a private Circle meeting and issues short
// lived R2 download URLs. Both the LiveKit and R2 credentials stay in Edge
// secrets. Every action resolves the caller's active profile and Circle role
// again; no client-supplied room name or storage key is trusted.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { json, serviceClient } from "../_shared/supabase.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function reply(body: unknown, status = 200): Response {
  const response = json(body, status);
  for (const [key, value] of Object.entries(CORS)) response.headers.set(key, value);
  return response;
}

function base64url(value: Uint8Array | string): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function hex(value: Uint8Array): string {
  return Array.from(value, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function hmac(key: Uint8Array | string, value: string): Promise<Uint8Array> {
  const keyBytes = typeof key === "string" ? new TextEncoder().encode(key) : key;
  // Deno's WebCrypto types require a concrete ArrayBuffer rather than the
  // broader ArrayBufferLike carried by a Uint8Array.
  const rawKey = keyBytes.buffer.slice(keyBytes.byteOffset, keyBytes.byteOffset + keyBytes.byteLength) as ArrayBuffer;
  const cryptoKey = await crypto.subtle.importKey("raw", rawKey, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(value)));
}

async function livekitToken(apiKey: string, apiSecret: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const payload = base64url(JSON.stringify({ iss: apiKey, nbf: now - 5, exp: now + 5 * 60, video: { roomRecord: true } }));
  return `${header}.${payload}.${base64url(await hmac(apiSecret, `${header}.${payload}`))}`;
}

function toEgressUrl(livekitUrl: string): string {
  const parsed = new URL(livekitUrl);
  parsed.protocol = parsed.protocol === "wss:" ? "https:" : parsed.protocol === "ws:" ? "http:" : parsed.protocol;
  parsed.pathname = "/twirp/livekit.Egress";
  return parsed.toString().replace(/\/$/, "");
}

async function egressRequest(method: string, body: Record<string, unknown>, apiKey: string, apiSecret: string, livekitUrl: string): Promise<Record<string, unknown>> {
  const result = await fetch(`${toEgressUrl(livekitUrl)}/${method}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${await livekitToken(apiKey, apiSecret)}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const parsed = await result.json().catch(() => ({}));
  if (!result.ok) throw new Error(typeof parsed?.message === "string" ? parsed.message : "LiveKit recording request failed");
  return parsed as Record<string, unknown>;
}

async function notifyCircleMembers(args: {
  svc: ReturnType<typeof serviceClient>;
  chatId: string;
  senderId: string;
  title: string;
  preview: string;
  targetUrl: string;
}) {
  // `create_notification` respects an in-app opt-out and the notification
  // insert trigger handles remote push delivery. Circle mutes are honoured
  // here because these notifications are not tied to a normal chat message.
  const { data: members } = await args.svc
    .from("chat_members")
    .select("user_id, muted")
    .eq("chat_id", args.chatId)
    .eq("muted", false);
  await Promise.all((members ?? [])
    .filter((member) => member.user_id !== args.senderId)
    .map((member) => args.svc.rpc("create_notification", {
      p_user: member.user_id,
      p_type: "system",
      p_title: args.title,
      p_preview: args.preview,
      p_target_id: args.chatId,
      p_target_url: args.targetUrl,
    })));
}

function awsDate(date: Date): { day: string; timestamp: string } {
  const pad = (n: number) => String(n).padStart(2, "0");
  const day = `${date.getUTCFullYear()}${pad(date.getUTCMonth() + 1)}${pad(date.getUTCDate())}`;
  return { day, timestamp: `${day}T${pad(date.getUTCHours())}${pad(date.getUTCMinutes())}${pad(date.getUTCSeconds())}Z` };
}

function encodedKey(key: string): string {
  return key.split("/").map(encodeURIComponent).join("/");
}

async function r2DownloadUrl(args: { endpoint: string; bucket: string; key: string; accessKey: string; secret: string }): Promise<string> {
  const endpoint = new URL(args.endpoint);
  const { day, timestamp } = awsDate(new Date());
  const credentialScope = `${day}/auto/s3/aws4_request`;
  const canonicalUri = `/${encodeURIComponent(args.bucket)}/${encodedKey(args.key)}`;
  const query = new URLSearchParams({
    "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
    "X-Amz-Credential": `${args.accessKey}/${credentialScope}`,
    "X-Amz-Date": timestamp,
    "X-Amz-Expires": "900",
    "X-Amz-SignedHeaders": "host",
  });
  const canonicalQuery = [...query.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`).join("&");
  const canonicalHeaders = `host:${endpoint.host}\n`;
  const canonicalRequest = `GET\n${canonicalUri}\n${canonicalQuery}\n${canonicalHeaders}\nhost\nUNSIGNED-PAYLOAD`;
  const hashedRequest = hex(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonicalRequest))));
  const stringToSign = `AWS4-HMAC-SHA256\n${timestamp}\n${credentialScope}\n${hashedRequest}`;
  const dateKey = await hmac(`AWS4${args.secret}`, day);
  const regionKey = await hmac(dateKey, "auto");
  const serviceKey = await hmac(regionKey, "s3");
  const signingKey = await hmac(serviceKey, "aws4_request");
  const signature = hex(await hmac(signingKey, stringToSign));
  return `${endpoint.origin}${canonicalUri}?${canonicalQuery}&X-Amz-Signature=${signature}`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reply({ error: "method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const livekitUrl = Deno.env.get("LIVEKIT_URL");
  const livekitApiKey = Deno.env.get("LIVEKIT_API_KEY");
  const livekitApiSecret = Deno.env.get("LIVEKIT_API_SECRET");
  const r2Endpoint = Deno.env.get("R2_ENDPOINT");
  const r2Bucket = Deno.env.get("R2_BUCKET");
  const r2AccessKey = Deno.env.get("R2_ACCESS_KEY_ID");
  const r2Secret = Deno.env.get("R2_SECRET_ACCESS_KEY");
  if (!url || !anonKey || !livekitUrl || !livekitApiKey || !livekitApiSecret || !r2Endpoint || !r2Bucket || !r2AccessKey || !r2Secret) {
    return reply({ error: "recording is not configured" }, 503);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(url, anonKey, { auth: { persistSession: false }, global: { headers: { Authorization: authHeader } } });
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) return reply({ error: "unauthorized" }, 401);

  let body: { action?: string; meeting_id?: string; recording_id?: string };
  try { body = await req.json(); } catch { return reply({ error: "invalid JSON" }, 400); }
  const action = body.action;
  if (!["start", "stop", "refresh", "url"].includes(action ?? "")) return reply({ error: "invalid action" }, 400);

  const svc = serviceClient();
  const { data: profile } = await svc.from("user_profiles").select("id, parish_id, status").eq("auth_id", user.id).maybeSingle();
  if (!profile || profile.status !== "active") return reply({ error: "active membership required" }, 403);

  const resolveMeeting = async (meetingId: string) => {
    const { data: meeting } = await svc.from("circle_meetings")
      .select("id, chat_id, parish_id, title, mode, status, room_name")
      .eq("id", meetingId).maybeSingle();
    if (!meeting || meeting.parish_id !== profile.parish_id) return null;
    const { data: membership } = await svc.from("chat_members")
      .select("role").eq("chat_id", meeting.chat_id).eq("user_id", profile.id).maybeSingle();
    return membership ? { meeting, role: membership.role } : null;
  };

  if (action === "start") {
    if (!body.meeting_id) return reply({ error: "meeting_id is required" }, 400);
    const resolved = await resolveMeeting(body.meeting_id);
    if (!resolved || resolved.meeting.status !== "live") return reply({ error: "live meeting not found" }, 404);
    if (!["owner", "admin"].includes(resolved.role)) return reply({ error: "Circle admin required" }, 403);

    const { data: existing } = await svc.from("circle_recordings")
      .select("id, status").eq("meeting_id", resolved.meeting.id).in("status", ["recording", "processing"]).maybeSingle();
    if (existing) return reply({ error: "this meeting is already being recorded", recording_id: existing.id }, 409);

    const recordingId = crypto.randomUUID();
    const extension = resolved.meeting.mode === "audio" ? "mp3" : "mp4";
    const storageKey = `circle-recordings/${resolved.meeting.chat_id}/${resolved.meeting.id}/${recordingId}.${extension}`;
    const request: Record<string, unknown> = {
      room_name: resolved.meeting.room_name,
      file_outputs: [{
        filepath: storageKey,
        file_type: resolved.meeting.mode === "audio" ? "MP3" : "MP4",
        s3: { access_key: r2AccessKey, secret: r2Secret, bucket: r2Bucket, endpoint: r2Endpoint, region: "auto", force_path_style: true },
      }],
    };
    if (resolved.meeting.mode === "audio") request.audio_only = true;
    else request.layout = "speaker";

    try {
      const egress = await egressRequest("StartRoomCompositeEgress", request, livekitApiKey, livekitApiSecret, livekitUrl);
      const egressId = typeof egress.egress_id === "string" ? egress.egress_id : null;
      if (!egressId) throw new Error("LiveKit did not return a recording id");
      const { error: insertError } = await svc.from("circle_recordings").insert({
        id: recordingId, meeting_id: resolved.meeting.id, chat_id: resolved.meeting.chat_id,
        parish_id: resolved.meeting.parish_id, created_by: profile.id, title: resolved.meeting.title,
        media_kind: resolved.meeting.mode, egress_id: egressId, storage_key: storageKey, status: "recording",
      });
      if (insertError) {
        // Avoid leaving an inaccessible, billable egress running if the
        // database record could not be created (for example, a race with
        // another Circle admin).
        await egressRequest("StopEgress", { egress_id: egressId }, livekitApiKey, livekitApiSecret, livekitUrl).catch(() => {});
        throw insertError;
      }
      await notifyCircleMembers({
        svc,
        chatId: resolved.meeting.chat_id,
        senderId: profile.id,
        title: "This meeting is being recorded",
        preview: `${resolved.meeting.title} will be saved privately for Circle members.`,
        targetUrl: `mathetes://meeting/${resolved.meeting.id}`,
      });
      return reply({ id: recordingId, status: "recording" });
    } catch (error) {
      return reply({ error: error instanceof Error ? error.message : "could not start recording" }, 502);
    }
  }

  const recordingId = body.recording_id;
  if (!recordingId) return reply({ error: "recording_id is required" }, 400);
  const { data: recording } = await svc.from("circle_recordings")
    .select("id, meeting_id, chat_id, parish_id, status, egress_id, storage_key")
    .eq("id", recordingId).maybeSingle();
  if (!recording || recording.parish_id !== profile.parish_id) return reply({ error: "recording not found" }, 404);
  const { data: membership } = await svc.from("chat_members").select("role")
    .eq("chat_id", recording.chat_id).eq("user_id", profile.id).maybeSingle();
  if (!membership) return reply({ error: "you are not a member of this Circle" }, 403);

  if (action === "url") {
    if (recording.status !== "ready") return reply({ error: "recording is still processing" }, 409);
    const downloadUrl = await r2DownloadUrl({ endpoint: r2Endpoint, bucket: r2Bucket, key: recording.storage_key, accessKey: r2AccessKey, secret: r2Secret });
    return reply({ url: downloadUrl, expires_in_seconds: 900 });
  }

  if (!["owner", "admin"].includes(membership.role)) return reply({ error: "Circle admin required" }, 403);
  if (action === "stop") {
    if (recording.status !== "recording") return reply({ error: "recording is not active" }, 409);
    try {
      await egressRequest("StopEgress", { egress_id: recording.egress_id }, livekitApiKey, livekitApiSecret, livekitUrl);
      await svc.from("circle_recordings").update({ status: "processing", stopped_at: new Date().toISOString() }).eq("id", recording.id);
      await notifyCircleMembers({
        svc,
        chatId: recording.chat_id,
        senderId: profile.id,
        title: "Recording is being saved",
        preview: "Your Circle teaching will appear when processing is complete.",
        targetUrl: `mathetes://circle/${recording.chat_id}`,
      });
      return reply({ id: recording.id, status: "processing" });
    } catch (error) {
      return reply({ error: error instanceof Error ? error.message : "could not stop recording" }, 502);
    }
  }

  // Egress uploads asynchronously. Circle admins poll this only while the app
  // is open; a later webhook can call the same status mapping if desired.
  try {
    const result = await egressRequest("ListEgress", { egress_id: recording.egress_id }, livekitApiKey, livekitApiSecret, livekitUrl);
    const items = Array.isArray(result.items) ? result.items as Record<string, unknown>[] : [];
    const info = items[0];
    const status = String(info?.status ?? "");
    if (status === "EGRESS_COMPLETE") {
      const file = Array.isArray(info?.file_results) ? (info.file_results as Record<string, unknown>[])[0] : null;
      await svc.from("circle_recordings").update({
        status: "ready", ready_at: new Date().toISOString(),
        duration_seconds: file && typeof file.duration === "number" ? Math.round(file.duration / 1_000_000_000) : null,
        size_bytes: file && typeof file.size === "number" ? file.size : null,
      }).eq("id", recording.id);
      return reply({ id: recording.id, status: "ready" });
    }
    if (["EGRESS_FAILED", "EGRESS_ABORTED", "EGRESS_LIMIT_REACHED"].includes(status)) {
      await svc.from("circle_recordings").update({ status: "failed", failure_reason: status, stopped_at: new Date().toISOString() }).eq("id", recording.id);
      return reply({ id: recording.id, status: "failed" });
    }
    return reply({ id: recording.id, status: recording.status });
  } catch (error) {
    return reply({ error: error instanceof Error ? error.message : "could not refresh recording" }, 502);
  }
});
