// Changes the signed-in account's email address (Z14). Two calls, both
// with the user's session and a password sign-in in the last 30 minutes
// (the app signs in again with the password first):
//
// POST {"action": "start", "new_email": "..."}
//   Emails a 6-digit code to the new address (valid 15 minutes). 204;
//   409 when the address already has an account; 400 when it isn't valid.
//
// POST {"action": "finish", "code": "123456", "auth_secret": "..."}
//   With the right code, switches the email AND the Supabase password (the
//   sign-in secret derived from the password and the new email) in one
//   admin call, so there is no moment when neither address signs in. Then
//   tells the old address. 200 {"email": "..."}; 400 wrong code (5 tries),
//   410 expired or no change started, 409 address taken meanwhile.
//
// Nothing about the request is logged.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  EMAIL_CHANGED_HTML,
  EMAIL_CHANGED_SUBJECT,
  EMAIL_CODE_HTML,
  EMAIL_CODE_SUBJECT,
} from "../_shared/email_change_email.ts";
import { escapeHtml, secondsSincePasswordSignIn, sendMail } from "../_shared/mail.ts";
import {
  CODE_MINUTES,
  codeHash,
  isAuthSecret,
  isCode,
  MAX_ATTEMPTS,
  newCode,
  normalizeEmail,
} from "./email_change.ts";

const text = (status: number, body: string) => new Response(body, { status });

Deno.serve(async (req) => {
  if (req.method !== "POST") return text(405, "POST only");
  const jwt = req.headers.get("Authorization")?.replace("Bearer ", "");
  if (!jwt) return text(401, "Unauthorized");
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: { user }, error } = await admin.auth.getUser(jwt);
  if (error || !user) return text(401, "Unauthorized");
  if (secondsSincePasswordSignIn(jwt) > 30 * 60) {
    return text(403, "Sign in again to change your email");
  }

  let body: Record<string, unknown>;
  try {
    const raw = await req.text();
    if (raw.length > 2048) return text(413, "Too large");
    body = JSON.parse(raw);
  } catch (_) {
    return text(400, "Bad request");
  }

  if (body.action === "start") {
    const email = normalizeEmail(body.new_email);
    if (!email) return text(400, "Not a valid email address");
    if (email === user.email?.toLowerCase()) return text(400, "That is already your email");
    const { data: taken, error: takenError } = await admin.rpc("zt_email_in_use", { p_email: email });
    if (takenError) return text(500, "Try again");
    if (taken) return text(409, "That email already has an account");
    const code = newCode();
    const { error: saveError } = await admin.from("zt_email_changes").upsert({
      user_id: user.id,
      new_email: email,
      code_hash: await codeHash(user.id, code),
      expires_at: new Date(Date.now() + CODE_MINUTES * 60_000).toISOString(),
      attempts: 0,
    });
    if (saveError) return text(500, "Try again");
    try {
      const sent = await sendMail(
        email,
        EMAIL_CODE_SUBJECT,
        EMAIL_CODE_HTML.replaceAll("{{NEW_EMAIL}}", escapeHtml(email)).replaceAll("{{CODE}}", code),
      );
      if (!sent) return text(503, "Email is not set up");
    } catch (_) {
      return text(502, "Could not send the email");
    }
    return new Response(null, { status: 204 });
  }

  if (body.action === "finish") {
    if (!isCode(body.code) || !isAuthSecret(body.auth_secret)) return text(400, "Bad request");
    const { data: row, error: readError } = await admin.from("zt_email_changes")
      .select("new_email, code_hash, expires_at, attempts").eq("user_id", user.id).maybeSingle();
    if (readError) return text(500, "Try again");
    if (!row || new Date(row.expires_at).getTime() < Date.now() || row.attempts >= MAX_ATTEMPTS) {
      return text(410, "The code expired. Ask for a new one");
    }
    if (row.code_hash !== await codeHash(user.id, body.code)) {
      await admin.from("zt_email_changes").update({ attempts: row.attempts + 1 })
        .eq("user_id", user.id);
      return text(400, "Wrong code");
    }
    const oldEmail = user.email;
    const { error: updateError } = await admin.auth.admin.updateUserById(user.id, {
      email: row.new_email,
      email_confirm: true,
      password: body.auth_secret,
    });
    if (updateError) {
      const taken = /already|registered|exists/i.test(updateError.message);
      return text(taken ? 409 : 500, taken ? "That email already has an account" : "Try again");
    }
    await admin.from("zt_email_changes").delete().eq("user_id", user.id);
    if (oldEmail) {
      try {
        await sendMail(
          oldEmail,
          EMAIL_CHANGED_SUBJECT,
          EMAIL_CHANGED_HTML.replaceAll("{{NEW_EMAIL}}", escapeHtml(row.new_email)),
        );
      } catch (_) {
        // Best effort; the change is done.
      }
    }
    return Response.json({ email: row.new_email });
  }

  return text(400, "Bad request");
});
