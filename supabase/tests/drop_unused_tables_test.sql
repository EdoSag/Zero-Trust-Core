-- 20261110120000_drop_unused_tables: the pre-core tables and the PostGIS
-- leftovers are gone; the core tables stay.
do $$ begin
  assert to_regclass('public.encrypted_sms') is null, 'encrypted_sms dropped';
  assert to_regclass('public.encrypted_note_items') is null, 'encrypted_note_items dropped';
  assert to_regclass('public.encrypted_contact_items') is null, 'encrypted_contact_items dropped';
  assert to_regclass('public.encrypted_vault') is null, 'encrypted_vault dropped';
  assert to_regclass('public.encrypted_tasks') is null, 'encrypted_tasks dropped';
  assert to_regclass('public.encrypted_task_items') is null, 'encrypted_task_items dropped';
  assert to_regclass('public.encrypted_notes') is null, 'encrypted_notes dropped';
  assert to_regclass('public.encrypted_contacts') is null, 'encrypted_contacts dropped';
  assert not exists (select 1 from pg_extension where extname = 'postgis'), 'postgis dropped';
  assert to_regprocedure('public.zt_spatial_ref_sys_read_only()') is null, 'read-only trigger fn dropped';
  assert not exists (select 1 from pg_policy where polrelid = 'storage.objects'::regclass
                     and polname like '%contact photos'), 'old photo policies dropped';
  assert to_regclass('public.vault_items') is not null, 'vault_items kept';
  assert to_regclass('public.profiles') is not null, 'profiles kept';
end $$;

\echo drop_unused_tables_test: all checks passed
