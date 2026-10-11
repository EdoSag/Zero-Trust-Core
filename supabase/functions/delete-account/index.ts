// Deletes the calling user's account. Every row referencing auth.users
// cascades (profiles, vault_items, legacy encrypted_* tables); storage
// objects under {user_id}/ are removed first.
import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const jwt = req.headers.get("Authorization")?.replace("Bearer ", "");
  if (!jwt) return new Response("Unauthorized", { status: 401 });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: { user }, error } = await admin.auth.getUser(jwt);
  if (error || !user) return new Response("Unauthorized", { status: 401 });

  // Remove every object under {user_id}/ in every bucket. Each round lists
  // the first page, recurses into folders (entries with a null id) and
  // removes the files, until the prefix is empty, so folders of any size
  // are covered. Any storage error aborts before the auth user is deleted,
  // so a retry can finish the cleanup instead of orphaning files.
  const PAGE = 1000;
  const MAX_ROUNDS = 10_000;
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

  try {
    const { data: buckets, error: bucketsError } = await admin.storage.listBuckets();
    if (bucketsError) throw bucketsError;
    for (const bucket of buckets ?? []) await removeUnder(bucket.id, user.id);
  } catch (e) {
    return new Response(`Storage cleanup failed: ${(e as Error).message}`, { status: 500 });
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) return new Response(deleteError.message, { status: 500 });
  return new Response(null, { status: 204 });
});
