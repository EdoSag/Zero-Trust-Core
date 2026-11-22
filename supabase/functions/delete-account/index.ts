// Asks to delete the calling user's account (Z22). Nothing is deleted
// now: the account is scheduled for deletion in 7 days and an email (EN +
// HE) says when, with a "Keep my account" link. The account-deletion
// function deletes it for good once the 7 days are over.
//
// Answers 200 {"delete_after": "<ISO time>"}. Older app versions only check
// for a 2xx and then sign out, which is still right.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { hashToken, newToken } from "../_shared/delete_user.ts";
import { DELETION_HTML, DELETION_SUBJECT } from "../_shared/deletion_email.ts";

const GRACE_DAYS = 7;
const KEEP_URL = Deno.env.get("ZT_KEEP_ACCOUNT_URL") ?? "https://zerotrust.bz/account/keep/";

Deno.serve(async (req) => {
  const jwt = req.headers.get("Authorization")?.replace("Bearer ", "");
  if (!jwt) return new Response("Unauthorized", { status: 401 });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: { user }, error } = await admin.auth.getUser(jwt);
  if (error || !user) return new Response("Unauthorized", { status: 401 });

  // Require a password sign-in in the last few minutes, so a stolen or
  // long-lived session can't ask for the deletion. The token is verified
  // above; its `amr` claim records when each sign-in method was used, and
  // unlike `iat` it isn't moved by token refreshes.
  const RECENT_SECONDS = 10 * 60;
  let signedInAt = 0;
  try {
    const payload = JSON.parse(atob(
      jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"),
    ));
    for (const entry of payload.amr ?? []) {
      if (entry.method === "password") signedInAt = Math.max(signedInAt, entry.timestamp ?? 0);
    }
  } catch (_) {
    // Treated as no recent sign-in.
  }
  if (Date.now() / 1000 - signedInAt > RECENT_SECONDS) {
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
});

/** Sends through Brevo's API (the same account as the auth emails' SMTP).
 * Needs the function secret BREVO_API_KEY; ZT_MAIL_FROM must be a sender
 * verified in Brevo. */
async function sendDeletionEmail(to: string, when: Date, undoUrl: string): Promise<void> {
  const apiKey = Deno.env.get("BREVO_API_KEY");
  if (!apiKey) return;
  const fmt = (locale: string) =>
    new Intl.DateTimeFormat(locale, { dateStyle: "long", timeZone: "UTC" }).format(when);
  const html = DELETION_HTML
    .replaceAll("{{DATE_EN}}", fmt("en-GB"))
    .replaceAll("{{DATE_HE}}", fmt("he-IL"))
    .replaceAll("{{UNDO_URL}}", undoUrl);
  const res = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: { "api-key": apiKey, "content-type": "application/json", accept: "application/json" },
    body: JSON.stringify({
      sender: { name: "Zero-Trust", email: Deno.env.get("ZT_MAIL_FROM") ?? "no-reply@zerotrust.bz" },
      to: [{ email: to }],
      subject: DELETION_SUBJECT,
      htmlContent: html,
      // Account email: no open or click tracking.
      headers: { "X-Mailin-Track": "0", "X-Mailin-Track-Clicks": "0", "X-Mailin-Track-Opens": "0" },
    }),
  });
  if (!res.ok) throw new Error(`Brevo ${res.status}`);
}
