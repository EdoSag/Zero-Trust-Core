// Checks what `auth.admin.generateLink` gave back before it goes to the app:
// a one-time sign-in token for the account that asked, and nothing else.

/** The part of a generateLink answer this function uses. */
export interface GeneratedLink {
  user?: { id?: string | null } | null;
  properties?: {
    hashed_token?: string | null;
    verification_type?: string | null;
  } | null;
}

/** What the app gets: it signs in with `verifyOtp({token_hash, type})`. */
export interface HandoffToken {
  token_hash: string;
  type: "magiclink";
}

/**
 * The token to hand to the other app, or null when the link isn't a
 * magic link for [userId] (generateLink looks the user up by email, so this
 * makes sure it found the same account).
 */
export function handoffToken(userId: string, link: GeneratedLink | null | undefined): HandoffToken | null {
  if (!link || link.user?.id !== userId) return null;
  const hash = link.properties?.hashed_token;
  const type = link.properties?.verification_type ?? "magiclink";
  if (typeof hash !== "string" || !/^[0-9a-f]{20,200}$/i.test(hash)) return null;
  if (type !== "magiclink") return null;
  return { token_hash: hash, type: "magiclink" };
}
