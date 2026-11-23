// Signs this account in on another Zero-Trust app on the same phone (S-2,
// "sign in once per phone"). The app that is already signed in calls this
// with its session, after the person confirmed with fingerprint or
// password; it gets a one-time sign-in token (a magic-link token, made
// without sending any email) and hands it, sealed, to the asking app over
// Android's signature-checked handoff. That app signs in with
// `verifyOtp({token_hash, type: "magiclink"})` and gets its own session, so
// neither app signs the other out.
//
// POST (no body) -> 200 {"token_hash": "...", "type": "magiclink"}
//   401 without a valid session.
//
// The token is only good for one sign-in and expires with the project's
// OTP setting. A session from such a sign-in doesn't count as a password
// sign-in, so deleting the account or changing its email still asks for
// the password. Nothing about the request is logged.
//
//   supabase functions deploy sign-in-handoff
import { createClient } from "jsr:@supabase/supabase-js@2";
import { withSessionCors } from "../_shared/cors.ts";
import { handoffToken } from "./handoff.ts";

const text = (status: number, body: string) => new Response(body, { status });

Deno.serve(withSessionCors(async (req) => {
  if (req.method !== "POST") return text(405, "POST only");
  const jwt = req.headers.get("Authorization")?.replace("Bearer ", "");
  if (!jwt) return text(401, "Unauthorized");
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: { user }, error } = await admin.auth.getUser(jwt);
  if (error || !user) return text(401, "Unauthorized");
  if (!user.email) return text(400, "This account has no email");

  const { data, error: linkError } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email: user.email,
  });
  if (linkError) return text(500, "Try again");
  const token = handoffToken(user.id, data);
  if (!token) return text(500, "Try again");
  return Response.json(token, { headers: { "cache-control": "no-store" } });
}));
