// Asks to delete the calling user's account (Z22). Nothing is deleted
// now: the account is scheduled for deletion in 7 days and an email (EN +
// HE) says when, with a "Keep my account" link. The account-deletion
// function deletes it for good once the 7 days are over.
//
// Answers 200 {"delete_after": "<ISO time>"}. Older app versions only check
// for a 2xx and then sign out, which is still right.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { withSessionCors } from "../_shared/cors.ts";
import { hashToken, newToken } from "../_shared/delete_user.ts";
import { DELETION_HTML, DELETION_SUBJECT } from "../_shared/deletion_email.ts";
import { secondsSincePasswordSignIn, sendMail } from "../_shared/mail.ts";

const GRACE_DAYS = 7;
const KEEP_URL = Deno.env.get("ZT_KEEP_ACCOUNT_URL") ?? "https://zerotrust.bz/account/keep/";

Deno.serve(withSessionCors(async (req) => {
  const jwt = req.headers.get("Authorization")?.replace("Bearer ", "");
  if (!jwt) return new Response("Unauthorized", { status: 401 });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: { user }, error } = await admin.auth.getUser(jwt);
  if (error || !user) return new Response("Unauthorized", { status: 401 });

  // Require a password sign-in in the last few minutes, so a stolen or
  // long-lived session can't ask for the deletion.
  if (secondsSincePasswordSignIn(jwt) > 10 * 60) {
    return new Response("Sign in again to delete your account", { status: 403 });
  }

  const token = newToken();
  const { data: deleteAfter, error: scheduleError } = await admin.rpc(
    "zt_schedule_account_deletion",
    { p_user: user.id, p_token_hash: await hashToken(token), p_days: GRACE_DAYS },
  );
  if (scheduleError || typeof deleteAfter !== "string") {
    return new Response("Could not schedule the deletion", { status: 500 });
  }

  // Best effort: the deletion is scheduled either way, and every app shows
  // it with a "Keep my account" button after sign-in.
  if (user.email) {
    try {
      await sendDeletionEmail(user.email, new Date(deleteAfter), `${KEEP_URL}#${token}`);
    } catch (_) {
      // Not logged: the address must not end up in function logs.
    }
  }
  return Response.json({ delete_after: deleteAfter });
}));

async function sendDeletionEmail(to: string, when: Date, undoUrl: string): Promise<void> {
  const fmt = (locale: string) =>
    new Intl.DateTimeFormat(locale, { dateStyle: "long", timeZone: "UTC" }).format(when);
  await sendMail(
    to,
    DELETION_SUBJECT,
    DELETION_HTML
      .replaceAll("{{DATE_EN}}", fmt("en-GB"))
      .replaceAll("{{DATE_HE}}", fmt("he-IL"))
      .replaceAll("{{UNDO_URL}}", undoUrl),
  );
}
