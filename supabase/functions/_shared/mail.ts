// Account emails sent by edge functions, through Brevo's API (the same
// account as the auth emails' SMTP). Function secrets: BREVO_API_KEY, and
// optionally ZT_MAIL_FROM, a sender verified in Brevo (default
// no-reply@zerotrust.bz). Without the key nothing is sent and this returns
// false. Never logs the address.
export async function sendMail(to: string, subject: string, html: string): Promise<boolean> {
  const apiKey = Deno.env.get("BREVO_API_KEY");
  if (!apiKey) return false;
  const res = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: { "api-key": apiKey, "content-type": "application/json", accept: "application/json" },
    body: JSON.stringify({
      sender: { name: "Zero-Trust", email: Deno.env.get("ZT_MAIL_FROM") ?? "no-reply@zerotrust.bz" },
      to: [{ email: to }],
      subject,
      htmlContent: html,
      // Account email: no open or click tracking.
      headers: { "X-Mailin-Track": "0", "X-Mailin-Track-Clicks": "0", "X-Mailin-Track-Opens": "0" },
    }),
  });
  if (!res.ok) throw new Error(`Brevo ${res.status}`);
  return true;
}

/** Escapes text for HTML (an email address shown in an email). */
export const escapeHtml = (s: string) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");

/** Seconds since the session's last password sign-in, from its verified
 * JWT's `amr` claim (unlike `iat`, token refreshes don't move it). */
export function secondsSincePasswordSignIn(jwt: string): number {
  let signedInAt = 0;
  try {
    const payload = JSON.parse(atob(jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
    for (const entry of payload.amr ?? []) {
      if (entry.method === "password") signedInAt = Math.max(signedInAt, entry.timestamp ?? 0);
    }
  } catch (_) {
    // Treated as no recent sign-in.
  }
  return Date.now() / 1000 - signedInAt;
}
