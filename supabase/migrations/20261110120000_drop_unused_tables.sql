-- Remove database objects that no app or core version reads or writes.
--
-- Checked against the main branch of every Zero-Trust app on 2026-11-10:
--   encrypted_sms            0 rows, never used by any app
--   encrypted_note_items     0 rows, old per-note table, no code reads it
--   encrypted_contact_items  0 rows, old per-contact table, no code reads it
--   PostGIS                  only TimeSpot used it (schema dropped 2026-11-10);
--                            no geometry/geography column is left anywhere.
--                            Takes spatial_ref_sys, geometry_columns and
--                            geography_columns with it, which also clears the
--                            Supabase advisor warnings about spatial_ref_sys.
--
-- Kept on purpose: encrypted_vault, encrypted_tasks, encrypted_task_items,
-- encrypted_notes, encrypted_contacts and the contactsProfilePictures bucket.
-- The current Fitness, Tasks, Notes and Contacts builds still read them to
-- import data from before the core.

drop table if exists public.encrypted_sms;
drop table if exists public.encrypted_note_items;
drop table if exists public.encrypted_contact_items;

-- Dropping the extension also drops spatial_ref_sys and the zt_read_only
-- trigger that 20261110090200_advisor_fixes put on it. The trigger drop below
-- only matters where spatial_ref_sys is not part of PostGIS (the test stub).
drop extension if exists postgis;
drop trigger if exists zt_read_only on public.spatial_ref_sys;
drop function if exists public.zt_spatial_ref_sys_read_only();
