-- Runs after 00_supabase_stub.sql and every migration. Z17 storage limits,
-- tombstone purge, and the Z18 advisor fixes.
create function pg_temp.expect_error(stmt text, msg text, want text) returns void
language plpgsql as $$
begin
  execute stmt;
  raise exception 'expected failure: %', msg;
exception when others then
  if sqlerrm like 'expected failure:%' then raise; end if;
  if want is not null and sqlerrm <> want then
    raise exception '%: got "%", wanted "%"', msg, sqlerrm, want;
  end if;
end $$;

insert into auth.users values ('00000000-0000-0000-0000-0000000000e1', 'quota@x.com'),
                              ('00000000-0000-0000-0000-0000000000e2', 'big@x.com');
-- A small limit for e1 so the test doesn't need 50 MB.
insert into public.zt_storage_limits (user_id, max_item_bytes, max_items, max_attachment_bytes)
  values ('00000000-0000-0000-0000-0000000000e1', 100, 3, 10);

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000e1';

insert into public.vault_items (user_id, app, item_id, data_blob)
  values (auth.uid(), 'notes', 'q1', decode(repeat('aa', 40), 'hex')),
         (auth.uid(), 'notes', 'q2', decode(repeat('aa', 40), 'hex'));
do $$ begin
  assert (select item_bytes from public.zt_storage_usage) = 80, 'bytes counted';
  assert (select item_count from public.zt_storage_usage) = 2, 'items counted';
  assert (select (public.zt_my_storage() ->> 'max_item_bytes')::int) = 100, 'override seen';
end $$;

-- Growing past the byte limit is refused; the whole statement rolls back.
select pg_temp.expect_error(
  $$insert into public.vault_items (user_id, app, item_id, data_blob)
    values (auth.uid(), 'notes', 'q3', decode(repeat('aa', 30), 'hex'))$$,
  'over byte limit', 'zt_storage_full');
select pg_temp.expect_error(
  $$update public.vault_items set data_blob = decode(repeat('aa', 70), 'hex'), updated_at = now() where item_id = 'q1'$$,
  'growing update over limit', 'zt_storage_full');
do $$ begin
  assert (select item_bytes from public.zt_storage_usage) = 80, 'refused write not counted';
end $$;

-- Shrinking and deleting are always allowed, and free space.
update public.vault_items set data_blob = null, deleted = true, updated_at = now() where item_id = 'q2';
do $$ begin
  assert (select item_bytes from public.zt_storage_usage) = 40, 'tombstone frees bytes';
end $$;
insert into public.vault_items (user_id, app, item_id, data_blob)
  values (auth.uid(), 'notes', 'q3', decode(repeat('aa', 30), 'hex'));

-- Item count limit (3: q1, q2 tombstone, q3).
select pg_temp.expect_error(
  $$insert into public.vault_items (user_id, app, item_id, data_blob) values (auth.uid(), 'notes', 'q4', '\x01')$$,
  'over item limit', 'zt_storage_full');

-- A tombstone for an item the server never had is still taken when full.
insert into public.vault_items (user_id, app, item_id, deleted)
  values (auth.uid(), 'notes', 'q9', true);
delete from public.vault_items where item_id = 'q9';

-- A write the stale-write guard skips is not counted.
insert into public.vault_items (user_id, app, item_id, data_blob, updated_at)
  values (auth.uid(), 'notes', 'q3', '\x01', now() - interval '1 day')
  on conflict (user_id, app, item_id) do update
    set data_blob = excluded.data_blob, updated_at = excluded.updated_at;
do $$ begin
  assert (select item_bytes from public.zt_storage_usage) = 70, 'skipped write not counted';
end $$;

-- Clients can't edit their usage or limits.
select pg_temp.expect_error($$update public.zt_storage_usage set item_bytes = 0$$, 'client edits usage', null);
select pg_temp.expect_error($$insert into public.zt_storage_limits (user_id, max_item_bytes) values (auth.uid(), 1e12)$$, 'client raises limit', null);
select pg_temp.expect_error($$select public.zt_purge_tombstones()$$, 'client purges', null);
select pg_temp.expect_error($$select public.vault_items_track_usage()$$, 'client calls trigger fn', null);

-- Attachments: a file must fit in the limit (10 bytes) with the others.
insert into storage.objects (bucket_id, name, metadata)
  values ('zt-attachments', '00000000-0000-0000-0000-0000000000e1/notes/a1', '{"size": 9}');
select pg_temp.expect_error(
  $$insert into storage.objects (bucket_id, name, metadata)
    values ('zt-attachments', '00000000-0000-0000-0000-0000000000e1/notes/a2', '{"size": 2}')$$,
  'attachments over limit', null);
-- Replacing a file with a bigger one is limited too; a smaller one is fine.
select pg_temp.expect_error(
  $$update storage.objects set metadata = '{"size": 50}' where name like '%/notes/a1'$$,
  'growing update over limit', null);
update storage.objects set metadata = '{"size": 8}' where name like '%/notes/a1';
do $$ begin
  assert (select (public.zt_my_storage() ->> 'attachment_bytes')::int) = 8, 'attachment bytes';
end $$;
-- Under the limit again: a file that fits goes in, one that doesn't is refused.
insert into storage.objects (bucket_id, name, metadata)
  values ('zt-attachments', '00000000-0000-0000-0000-0000000000e1/notes/a3', '{"size": 2}');
select pg_temp.expect_error(
  $$insert into storage.objects (bucket_id, name, metadata)
    values ('zt-attachments', '00000000-0000-0000-0000-0000000000e1/notes/a4', '{"size": 5}')$$,
  'new file that does not fit', null);

-- Another user: default limits, nothing of e1's visible.
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000e2';
do $$ begin
  assert (select (public.zt_my_storage() ->> 'item_bytes')::int) = 0, 'own usage only';
  assert (select (public.zt_my_storage() ->> 'max_item_bytes')::int) = 52428800, 'default limit';
  assert (select count(*) from public.zt_storage_usage) = 0, 'no other usage rows';
end $$;
-- Per-item cap (1 MiB) applies even with room to spare.
select pg_temp.expect_error(
  $$insert into public.vault_items (user_id, app, item_id, data_blob)
    values (auth.uid(), 'notes', 'big', decode(repeat('aa', 1048577), 'hex'))$$,
  'item over 1 MiB', 'zt_item_too_large');
insert into storage.objects (bucket_id, name, metadata)
  values ('zt-attachments', '00000000-0000-0000-0000-0000000000e2/notes/a1', '{"size": 12}');
reset role;

-- Tombstone purge: only old tombstones go, usage follows.
alter table public.vault_items disable trigger vault_items_synced_at;  -- it stamps synced_at
update public.vault_items set synced_at = now() - interval '200 days' where item_id in ('q1', 'q2');
alter table public.vault_items enable trigger vault_items_synced_at;
select public.zt_purge_tombstones();
do $$ begin
  assert (select count(*) from public.vault_items where item_id = 'q1') = 1, 'old live item kept';
  assert (select count(*) from public.vault_items where item_id = 'q2') = 0, 'old tombstone purged';
  assert (select item_count from public.zt_storage_usage
          where user_id = '00000000-0000-0000-0000-0000000000e1') = 2, 'purge updates count';
end $$;
select pg_temp.expect_error($$select public.zt_purge_tombstones(interval '1 day')$$, 'too short retention', null);

-- Deleting the account cascades cleanly and leaves no usage row behind.
delete from auth.users where id = '00000000-0000-0000-0000-0000000000e1';
do $$ begin
  assert not exists (select 1 from public.zt_storage_usage
                     where user_id = '00000000-0000-0000-0000-0000000000e1'), 'no orphan usage row';
end $$;

-- Advisor fixes.
set role anon;
select pg_temp.expect_error($$delete from public.spatial_ref_sys$$, 'anon deletes spatial_ref_sys', 'spatial_ref_sys is read-only');
select pg_temp.expect_error($$select public.profiles_keep_key_history()$$, 'anon calls trigger fn', null);
do $$ begin
  assert (select count(*) from public.spatial_ref_sys) = 1, 'reads still work';
end $$;
reset role;
set role authenticated;
select pg_temp.expect_error($$update public.spatial_ref_sys set auth_name = 'x'$$, 'authenticated edits spatial_ref_sys', 'spatial_ref_sys is read-only');
reset role;

\echo storage_quota_test: all checks passed
