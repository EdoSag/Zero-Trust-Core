// Receives opt-in crash reports (Z15). Deployed with JWT checks off: the
// apps send no account token on purpose, so a report can't be tied to
// anyone. Nothing about the request (IP, headers, body) is logged.
//
//   supabase functions deploy crash-report --no-verify-jwt
import { createClient } from "jsr:@supabase/supabase-js@2";
import { checkReport, MAX_BODY_BYTES } from "./crash_report.ts";

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "content-type, apikey, authorization, x-client-info",
};

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const reply = (status: number) => new Response(null, { status, headers: CORS });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return reply(204);
  if (req.method !== "POST") return reply(405);
  const raw = await req.text();
  if (raw.length > MAX_BODY_BYTES) return reply(413);
  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch (_) {
    return reply(400);
  }
  const report = checkReport(body);
  if (!report) return reply(400);
  const { data, error } = await admin.rpc("zt_record_crash_report", { p: report });
  if (error) return reply(500);
  // Daily cap reached: the phone keeps the report and tries again later.
  return reply(data === false ? 503 : 204);
});
