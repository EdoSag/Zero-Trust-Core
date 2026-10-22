-- Runs after 00_supabase_stub.sql and every migration. The vault_items
-- write guard: stale and far-future writes are skipped, others land.
insert into auth.users values ('00000000-0000-0000-0000-0000000000d1', 'sync@x.com');
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d1';

insert into public.vault_items (user_id, app, item_id, data_blob, updated_at)
  values (auth.uid(), 'notes', 'n1', '\x01', now());
do $$ begin
  -- Older write: skipped.
  insert into public.vault_items (user_id, app, item_id, data_blob, updated_at)
    values (auth.uid(), 'notes', 'n1', '\x02', now() - interval '1 hour')
    on conflict (user_id, app, item_id) do update
      set data_blob = excluded.data_blob, updated_at = excluded.updated_at;
  assert (select data_blob from public.vault_items where item_id = 'n1') = '\x01', 'stale skipped';

  -- Far-future write: skipped, for an update and for a new row.
  insert into public.vault_items (user_id, app, item_id, data_blob, updated_at)
    values (auth.uid(), 'notes', 'n1', '\x03', now() + interval '1 day')
    on conflict (user_id, app, item_id) do update
      set data_blob = excluded.data_blob, updated_at = excluded.updated_at;
  assert (select data_blob from public.vault_items where item_id = 'n1') = '\x01', 'future update skipped';
  insert into public.vault_items (user_id, app, item_id, data_blob, updated_at)
    values (auth.uid(), 'notes', 'n2', '\x04', now() + interval '1 day');
  assert not exists (select 1 from public.vault_items where item_id = 'n2'), 'future insert skipped';

  -- A few minutes ahead (ordinary skew) and newer: lands.
  insert into public.vault_items (user_id, app, item_id, data_blob, updated_at)
    values (auth.uid(), 'notes', 'n1', '\x05', now() + interval '5 minutes')
    on conflict (user_id, app, item_id) do update
      set data_blob = excluded.data_blob, updated_at = excluded.updated_at;
  assert (select data_blob from public.vault_items where item_id = 'n1') = '\x05', 'newer lands';
end $$;
reset role;

\echo vault_items_test: all checks passed
