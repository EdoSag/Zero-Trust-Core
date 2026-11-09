-- zero_trust_core v0.7: the private bucket for encrypted attachments
-- (ZtAttachments). Files are client-side encrypted (AttachmentCipher); the
-- server only stores ciphertext at {user_id}/{app}/{attachment_id}.
-- Additive: no existing table, bucket or policy is changed. Contacts' old
-- `contactsProfilePictures` bucket stays as it is for pre-core builds.
-- 25 MB per object: 20 MB of plaintext plus encryption overhead.
insert into storage.buckets (id, name, public, file_size_limit)
values ('zt-attachments', 'zt-attachments', false, 26214400)
on conflict (id) do nothing;

-- Each user reads and writes only under their own id, and only in a
-- folder named after one of the suite's apps.
create policy "zt_attachments_select_own" on storage.objects
  for select to authenticated
  using (bucket_id = 'zt-attachments'
         and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "zt_attachments_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'zt-attachments'
              and (storage.foldername(name))[1] = (select auth.uid())::text
              and (storage.foldername(name))[2] in ('notes', 'tasks', 'fitness', 'contacts'));

-- Upsert (a retried upload) needs update as well as insert.
create policy "zt_attachments_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'zt-attachments'
         and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'zt-attachments'
              and (storage.foldername(name))[1] = (select auth.uid())::text
              and (storage.foldername(name))[2] in ('notes', 'tasks', 'fitness', 'contacts'));

create policy "zt_attachments_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'zt-attachments'
         and (storage.foldername(name))[1] = (select auth.uid())::text);
