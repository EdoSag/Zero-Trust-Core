// The second half of Z22, deployed with JWT checks off:
//
//   supabase functions deploy account-deletion --no-verify-jwt
//
// POST {"action": "keep", "token": "<from the email link>"}
//   Cancels a scheduled deletion. 200 {"kept": true}, or 404 when the link
//   is unknown (already used, replaced by a newer email, or too late).
//
// POST {"action": "purge"} with header x-zt-purge-secret
//   Deletes every account whose 7 days are over. Called hourly by pg_cron
//   (public.zt_request_account_purge); the secret is in Vault only.
//
// Nothing about the request is logged.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { deleteUserNow, hashToken } from "../_shared/delete_user.ts";

const CORS = {
  "access-control-allow-origin": "https://zerotrust.bz",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "content-type",
};

const json = (status: number, body?: unknown) =>
  body === undefined
    ? new Response(null, { status, headers: CORS })
    : Response.json(body, { status, headers: CORS });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return json(204);
  if (req.method !== "POST") return json(405);
  let body: { action?: unknown; token?: unknown };
  try {
    const raw = await req.text();
    if (raw.length > 1024) return json(413);
    body = JSON.parse(raw);
  } catch (_) {
    return json(400);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  if (body.action === "keep") {
    const token = body.token;
    if (typeof token !== "string" || !/^[A-Za-z0-9_-]{43}$/.test(token)) return json(400);
    const { data, error } = await admin.rpc("zt_cancel_account_deletion_by_token", {
      p_token_hash: await hashToken(token),
    });
    if (error) return json(500);
    return data === true ? json(200, { kept: true }) : json(404, { kept: false });
  }

  if (body.action === "purge") {
    const { data: ok } = await admin.rpc("zt_check_account_purge_secret", {
      p_secret: req.headers.get("x-zt-purge-secret") ?? "",
    });
    if (ok !== true) return json(401);
    const { data: due, error } = await admin.rpc("zt_due_account_deletions", { p_limit: 50 });
    if (error) return json(500);
    let deleted = 0, failed = 0;
    for (const userId of (due ?? []) as string[]) {
      // Claimed one at a time, just before deleting: "Keep my account" in
      // the meantime wins (the claim fails), and once claimed, keeping is
      // refused, so a kept account is never deleted.
      const { data: claimed, error: claimError } = await admin.rpc(
        "zt_claim_account_deletion",
        { p_user: userId },
      );
      if (claimError) {
        failed++;
        continue;
      }
      if (claimed !== true) continue;
      try {
        await deleteUserNow(admin, userId);
        deleted++;
      } catch (_) {
        // Some files may be gone already, so it stays claimed (no longer
        // keepable) and the next hourly run finishes it.
        failed++;
      }
    }
    return json(200, { deleted, failed });
  }

  return json(400);
});
