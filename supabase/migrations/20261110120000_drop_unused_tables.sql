-- Remove the tables from before the core, and other objects nothing uses.
--
-- Checked against the main branch of every Zero-Trust app on 2026-11-10.
-- Edo is the only user and runs the latest releases, so the old-data imports
-- are finished; he chose to drop the old tables (project thread, 2026-11-10).
--   encrypted_sms, encrypted_note_items, encrypted_contact_items
--                            0 rows, never read by any app
--   encrypted_vault, encrypted_tasks, encrypted_task_items, encrypted_notes,
--   encrypted_contacts       pre-core data; the apps' import code treats a
--                            missing table as "nothing to import"
--   contactsProfilePictures  storage policies of the old Contacts photo bucket
--                            (the bucket itself is removed in the dashboard;
--                            Supabase refuses direct deletes from storage)
--   PostGIS                  only TimeSpot used it (schema dropped 2026-11-10);
--                            takes spatial_ref_sys, geometry_columns and
--                            geography_columns with it.

drop table if exists public.encrypted_sms;
drop table if exists public.encrypted_note_items;
drop table if exists public.encrypted_contact_items;
drop table if exists public.encrypted_vault;
drop table if exists public.encrypted_task_items;
drop table if exists public.encrypted_tasks;
drop table if exists public.encrypted_notes;
drop table if exists public.encrypted_contacts;

drop policy if exists "Users can upload own contact photos" on storage.objects;
drop policy if exists "Users can read own contact photos" on storage.objects;
drop policy if exists "Users can update own contact photos" on storage.objects;
drop policy if exists "Users can delete own contact photos" on storage.objects;

-- Dropping the extension also drops spatial_ref_sys and the zt_read_only
-- trigger that 20261110090200_advisor_fixes put on it. Where spatial_ref_sys
-- is a plain table (the test stub), drop the trigger by hand.
drop extension if exists postgis;
do $$
begin
  if to_regclass('public.spatial_ref_sys') is not null then
    drop trigger if exists zt_read_only on public.spatial_ref_sys;
  end if;
end;
$$;
drop function if exists public.zt_spatial_ref_sys_read_only();
