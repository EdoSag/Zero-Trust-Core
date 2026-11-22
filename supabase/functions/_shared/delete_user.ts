// Deletes an account for good: every storage object under {user_id}/ in
// every bucket first, then the auth user (every row referencing auth.users
// cascades). Any storage error aborts before the auth user is deleted, so a
// retry can finish the cleanup instead of orphaning files.
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const PAGE = 1000;
const MAX_ROUNDS = 10_000;

export async function deleteUserNow(admin: SupabaseClient, userId: string): Promise<void> {
  // Each round lists the first page, recurses into folders (entries with a
  // null id) and removes the files, until the prefix is empty, so folders
  // of any size are covered.
  const removeUnder = async (bucket: string, prefix: string): Promise<void> => {
    for (let round = 0; round < MAX_ROUNDS; round++) {
      const { data: entries, error } = await admin.storage.from(bucket)
        .list(prefix, { limit: PAGE });
      if (error) throw error;
      if (!entries || entries.length === 0) return;
      const files: string[] = [];
      for (const entry of entries) {
        const path = `${prefix}/${entry.name}`;
        if (entry.id === null) await removeUnder(bucket, path);
        else files.push(path);
      }
      if (files.length) {
        const { error: removeError } = await admin.storage.from(bucket).remove(files);
        if (removeError) throw removeError;
      }
    }
    throw new Error(`Could not empty ${bucket}/${prefix}`);
  };

  const { data: buckets, error: bucketsError } = await admin.storage.listBuckets();
  if (bucketsError) throw bucketsError;
  for (const bucket of buckets ?? []) await removeUnder(bucket.id, userId);

  const { error } = await admin.auth.admin.deleteUser(userId);
  if (error) throw error;
}

/** SHA-256 of an undo token, as stored (the token itself is never kept). */
export async function hashToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return "\\x" + [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** 32 random bytes, base64url without padding. */
export function newToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_")
    .replace(/=+$/, "");
}
