// Pure checks for the change-email function (tested without a network).

/** A plausible address: one @, a dot in the domain, no spaces, <= 254. */
export function normalizeEmail(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const email = raw.trim().toLowerCase();
  if (email.length < 3 || email.length > 254) return null;
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return null;
  return email;
}

/** The new sign-in secret: base64 of 32 bytes (HKDF output). */
export function isAuthSecret(v: unknown): v is string {
  return typeof v === "string" && /^[A-Za-z0-9+/_-]{43}=?$/.test(v);
}

export const isCode = (v: unknown): v is string => typeof v === "string" && /^\d{6}$/.test(v);

/** Six random digits, without modulo bias. */
export function newCode(): string {
  const out: number[] = [];
  while (out.length < 6) {
    const [b] = crypto.getRandomValues(new Uint8Array(1));
    if (b < 250) out.push(b % 10);
  }
  return out.join("");
}

/** Postgres bytea hex of SHA-256("<userId>:<code>"). */
export async function codeHash(userId: string, code: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${userId}:${code}`));
  return "\\x" + [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export const CODE_MINUTES = 15;
export const MAX_ATTEMPTS = 5;
