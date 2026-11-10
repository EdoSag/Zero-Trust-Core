-- 20261110120000_drop_unused_tables: the unused tables and the PostGIS
-- leftovers are gone; the legacy tables the apps still import from stay.
do $$ begin
  assert to_regclass('public.encrypted_sms') is null, 'encrypted_sms dropped';
  assert to_regclass('public.encrypted_note_items') is null, 'encrypted_note_items dropped';
  assert to_regclass('public.encrypted_contact_items') is null, 'encrypted_contact_items dropped';
  assert not exists (select 1 from pg_extension where extname = 'postgis'), 'postgis dropped';
  assert to_regprocedure('public.zt_spatial_ref_sys_read_only()') is null, 'read-only trigger fn dropped';
  assert to_regclass('public.encrypted_vault') is not null, 'encrypted_vault kept';
end $$;

\echo drop_unused_tables_test: all checks passed
