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

  // Remove every object under {user_id}/ in every bucket, recursing into
  // folders (list() returns folders as entries with a null id).
  const removeUnder = async (bucket: string, prefix: string) => {
    const { data: entries } = await admin.storage.from(bucket).list(prefix, { limit: 1000 });
    const files: string[] = [];
    for (const entry of entries ?? []) {
      const path = `${prefix}/${entry.name}`;
      if (entry.id === null) await removeUnder(bucket, path);
      else files.push(path);
    }
    if (files.length) await admin.storage.from(bucket).remove(files);
  };
  const { data: buckets } = await admin.storage.listBuckets();
  for (const bucket of buckets ?? []) await removeUnder(bucket.id, user.id);

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) return new Response(deleteError.message, { status: 500 });
  return new Response(null, { status: 204 });
});
