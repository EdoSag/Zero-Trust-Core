-- Shared album files (ZT Gallery) and attachments for every app.
--
-- 1. zt-attachments accepted uploads only into the notes, tasks, fitness and
--    contacts folders, so ZT Camera's vault backup (folder `camera`) was
--    refused. Any app folder (lowercase letters and _) is accepted now. The
--    first folder is still the uploader's own id, so nobody can write into
--    someone else's files, and the quota policies are unchanged.
-- 2. Files of a shared space: `<uploader id>/space_<space id, 32 hex>/<file>`.
--    Only a member of that space may upload there, and every member may read
--    them (they are encrypted on the phone with keys kept inside the space's
--    items, so reading the file alone shows nothing). Only the uploader
--    deletes them; they count toward the uploader's storage.
--
-- Additive for the data: no object is moved or deleted.

create or replace function public.zt_is_space_folder_member(p_folder text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
begin
  if p_folder is null or p_folder !~ '^space_[0-9a-f]{32}$' then
    return false;
  end if;
  return exists (
    select 1 from public.zt_space_members m
    where m.space_id = substr(p_folder, 7)::uuid
      and m.user_id = (select auth.uid()));
end;
$$;
revoke execute on function public.zt_is_space_folder_member(text) from public, anon;
grant execute on function public.zt_is_space_folder_member(text) to authenticated;

-- Where the signed-in user may put a file: an app folder, or a space they
-- are a member of. Always under their own id.
create or replace function public.zt_attachment_folder_ok(p_name text)
returns boolean language sql stable set search_path = '' as $$
  select (storage.foldername(p_name))[1] = (select auth.uid())::text
     and array_length(storage.foldername(p_name), 1) = 2
     and (((storage.foldername(p_name))[2] ~ '^[a-z][a-z_]*$'
           and (storage.foldername(p_name))[2] !~ '^space_')
          or public.zt_is_space_folder_member((storage.foldername(p_name))[2]));
$$;
revoke execute on function public.zt_attachment_folder_ok(text) from public, anon;
grant execute on function public.zt_attachment_folder_ok(text) to authenticated;

drop policy if exists "zt_attachments_insert_own" on storage.objects;
create policy "zt_attachments_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'zt-attachments'
              and public.zt_attachment_folder_ok(name));

drop policy if exists "zt_attachments_update_own" on storage.objects;
create policy "zt_attachments_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'zt-attachments'
         and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'zt-attachments'
              and public.zt_attachment_folder_ok(name));

-- Members read each other's files in a space they share.
drop policy if exists "zt_attachments_select_space" on storage.objects;
create policy "zt_attachments_select_space" on storage.objects
  for select to authenticated
  using (bucket_id = 'zt-attachments'
         and public.zt_is_space_folder_member((storage.foldername(name))[2]));
