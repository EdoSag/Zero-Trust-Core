-- Runs after 00_supabase_stub.sql and every migration. Z24 shared spaces:
-- who can see and change what, invites, key rotation, members leaving.
create or replace function pg_temp.expect_error(stmt text, msg text, want text) returns void
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
create or replace function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u, false);
$$;
grant execute on function pg_temp.expect_error(text, text, text) to authenticated;
grant execute on function pg_temp.as_user(text) to authenticated;

-- a = parent who creates the space, b = other parent, c = babysitter,
-- x = stranger.
insert into auth.users values
  ('00000000-0000-0000-0000-00000000aa01', 'a@x.com'),
  ('00000000-0000-0000-0000-00000000aa02', 'b@x.com'),
  ('00000000-0000-0000-0000-00000000aa03', 'c@x.com'),
  ('00000000-0000-0000-0000-00000000aa09', 'x@x.com');

-- 64-byte stand-ins for signatures and 80-byte ones for wrapped keys.
create or replace function pg_temp.sig() returns bytea language sql as $$ select decode(repeat('51', 64), 'hex') $$;
create or replace function pg_temp.wrap() returns bytea language sql as $$ select decode(repeat('77', 80), 'hex') $$;
create or replace function pg_temp.wrap64() returns text language sql as $$ select translate(encode(decode(repeat('77', 80), 'hex'), 'base64'), E'\n', '') $$;
create or replace function pg_temp.sig64() returns text language sql as $$ select translate(encode(decode(repeat('51', 64), 'hex'), 'base64'), E'\n', '') $$;
grant execute on all functions in schema pg_temp to authenticated;

set role authenticated;

-- 1. Creating a space ---------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa01');
select public.zt_create_space('00000000-0000-0000-0000-0000000005a1', 'meds', pg_temp.wrap(), pg_temp.sig());
do $$ begin
  assert (select role from public.zt_space_members) = 'admin', 'creator is admin';
  assert (select count(*) from public.zt_space_keys) = 1, 'creator has epoch 1 key';
  assert (select key_epoch from public.zt_spaces) = 1, 'epoch 1';
end $$;

-- Clients can't write membership or keys directly.
select pg_temp.expect_error(
  $$insert into public.zt_space_members (space_id, user_id, role)
    values ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-00000000aa09', 'admin')$$,
  'direct member insert', null);
select pg_temp.expect_error(
  $$update public.zt_spaces set key_epoch = 5$$, 'direct space update', null);
select pg_temp.expect_error(
  $$delete from public.zt_space_items$$, 'direct item delete', null);

-- An item from the admin, and an admin-only one.
insert into public.zt_space_items (space_id, item_id, key_epoch, data_blob, signature)
  values ('00000000-0000-0000-0000-0000000005a1', 'child', 1, '\x01', pg_temp.sig());
insert into public.zt_space_items (space_id, item_id, key_epoch, data_blob, signature, admin_only)
  values ('00000000-0000-0000-0000-0000000005a1', 'med1', 1, '\x02', pg_temp.sig(), true);
do $$ begin
  assert (select author_id from public.zt_space_items where item_id = 'child')
         = '00000000-0000-0000-0000-00000000aa01', 'author set by server';
  assert (select item_count from public.zt_spaces) = 2, 'usage counted';
end $$;

-- 2. A stranger sees nothing and can't write ------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa09');
do $$ begin
  assert (select count(*) from public.zt_spaces) = 0, 'stranger: no spaces';
  assert (select count(*) from public.zt_space_items) = 0, 'stranger: no items';
  assert (select count(*) from public.zt_space_members) = 0, 'stranger: no members';
  assert (select count(*) from public.zt_space_keys) = 0, 'stranger: no keys';
end $$;
select pg_temp.expect_error(
  $$insert into public.zt_space_items (space_id, item_id, key_epoch, data_blob, signature)
    values ('00000000-0000-0000-0000-0000000005a1', 'evil', 1, '\x09', pg_temp.sig())$$,
  'stranger insert', null);
select pg_temp.expect_error(
  $$select public.zt_create_space_invite('00000000-0000-0000-0000-0000000001a1',
      '00000000-0000-0000-0000-0000000005a1', 'admin', sha256('\x00'::bytea))$$,
  'stranger invites', 'zt_not_space_admin');

-- 3. Inviting b (admin) and c (member) ----------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa01');
select public.zt_create_space_invite('00000000-0000-0000-0000-0000000001b1',
  '00000000-0000-0000-0000-0000000005a1', 'admin', sha256('\xb0b0'::bytea));
select public.zt_create_space_invite('00000000-0000-0000-0000-0000000001c1',
  '00000000-0000-0000-0000-0000000005a1', 'member', sha256('\xc0c0'::bytea));
select pg_temp.expect_error(
  $$select public.zt_create_space_invite('00000000-0000-0000-0000-0000000001d1',
      '00000000-0000-0000-0000-0000000005a1', 'member', sha256('\x01'::bytea), interval '60 days')$$,
  'invite too long', 'zt_invite_invalid');

-- A wrong token is refused; the right one answers once.
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa09');
select pg_temp.expect_error(
  $$select public.zt_answer_space_invite('00000000-0000-0000-0000-0000000001b1', '\xdead', '\x01')$$,
  'wrong token', 'zt_invite_invalid');
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa02');
do $$ declare r json; begin
  r := public.zt_answer_space_invite('00000000-0000-0000-0000-0000000001b1', '\xb0b0', '\xabcd');
  assert r ->> 'app' = 'meds', 'answer returns the app';
  assert r ->> 'invited_by' = '00000000-0000-0000-0000-00000000aa01', 'answer returns inviter';
  assert (select count(*) from public.zt_space_invites) = 1, 'invitee sees the invite they answered';
  assert (select count(*) from public.zt_space_items) = 0, 'not a member yet: no items';
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa09');
select pg_temp.expect_error(
  $$select public.zt_answer_space_invite('00000000-0000-0000-0000-0000000001b1', '\xb0b0', '\x01')$$,
  'answered twice', 'zt_invite_invalid');

-- Only an admin confirms, and the current epoch must be included.
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa02');
select pg_temp.expect_error(
  format($$select public.zt_confirm_space_invite('00000000-0000-0000-0000-0000000001b1',
    '[{"epoch":1,"wrapped_key":"%s","signature":"%s"}]')$$, pg_temp.wrap64(), pg_temp.sig64()),
  'invitee confirms self', 'zt_not_space_admin');
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa01');
select pg_temp.expect_error(
  format($$select public.zt_confirm_space_invite('00000000-0000-0000-0000-0000000001b1',
    '[{"epoch":2,"wrapped_key":"%s","signature":"%s"}]')$$, pg_temp.wrap64(), pg_temp.sig64()),
  'wrong epoch', 'zt_space_keys_mismatch');
select public.zt_confirm_space_invite('00000000-0000-0000-0000-0000000001b1',
  format('[{"epoch":1,"wrapped_key":"%s","signature":"%s"}]', pg_temp.wrap64(), pg_temp.sig64())::jsonb);

select pg_temp.as_user('00000000-0000-0000-0000-00000000aa03');
select public.zt_answer_space_invite('00000000-0000-0000-0000-0000000001c1', '\xc0c0', '\xabcd');
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa01');
select public.zt_confirm_space_invite('00000000-0000-0000-0000-0000000001c1',
  format('[{"epoch":1,"wrapped_key":"%s","signature":"%s"}]', pg_temp.wrap64(), pg_temp.sig64())::jsonb);
do $$ begin
  assert (select count(*) from public.zt_space_members) = 3, 'three members';
  assert (select count(*) from public.zt_space_keys) = 1, 'a sees only own key';
end $$;

-- 4. Roles on items --------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa03');
do $$ begin
  assert (select count(*) from public.zt_space_items) = 2, 'member reads items';
  assert (select count(*) from public.zt_space_keys) = 1, 'member sees only own key';
  assert (select count(*) from public.zt_space_invites) = 1, 'member sees only own invite';
end $$;
insert into public.zt_space_items (space_id, item_id, key_epoch, data_blob, signature)
  values ('00000000-0000-0000-0000-0000000005a1', 'dose1', 1, '\x03', pg_temp.sig());
select pg_temp.expect_error(
  $$update public.zt_space_items set data_blob = '\x09', updated_at = now() + interval '1 second'
    where item_id = 'med1'$$,
  'member edits admin-only item', 'zt_space_admin_only');
select pg_temp.expect_error(
  $$insert into public.zt_space_items (space_id, item_id, key_epoch, data_blob, signature, admin_only)
    values ('00000000-0000-0000-0000-0000000005a1', 'med2', 1, '\x03', pg_temp.sig(), true)$$,
  'member writes admin-only item', 'zt_space_admin_only');
select pg_temp.expect_error(
  $$select public.zt_create_space_invite('00000000-0000-0000-0000-0000000001e1',
      '00000000-0000-0000-0000-0000000005a1', 'member', sha256('\x01'::bytea))$$,
  'member invites', 'zt_not_space_admin');
-- Clock guards, as on vault_items.
insert into public.zt_space_items (space_id, item_id, key_epoch, data_blob, signature, updated_at)
  values ('00000000-0000-0000-0000-0000000005a1', 'dose1', 1, '\x04', pg_temp.sig(), now() - interval '1 hour')
  on conflict (space_id, item_id) do update
    set data_blob = excluded.data_blob, updated_at = excluded.updated_at;
do $$ begin
  assert (select data_blob from public.zt_space_items where item_id = 'dose1') = '\x03', 'stale write skipped';
end $$;

-- 5. Removing c rotates the key -----------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa02');
select pg_temp.expect_error(
  format($$select public.zt_remove_space_member('00000000-0000-0000-0000-0000000005a1',
    '00000000-0000-0000-0000-00000000aa03', 2,
    '[{"user_id":"00000000-0000-0000-0000-00000000aa01","wrapped_key":"%s","signature":"%s"}]')$$,
    pg_temp.wrap64(), pg_temp.sig64()),
  'rotation missing a member', 'zt_space_keys_mismatch');
select public.zt_remove_space_member('00000000-0000-0000-0000-0000000005a1',
  '00000000-0000-0000-0000-00000000aa03', 2,
  format('[{"user_id":"00000000-0000-0000-0000-00000000aa01","wrapped_key":"%1$s","signature":"%2$s"},
           {"user_id":"00000000-0000-0000-0000-00000000aa02","wrapped_key":"%1$s","signature":"%2$s"}]',
         pg_temp.wrap64(), pg_temp.sig64())::jsonb);
do $$ begin
  assert (select key_epoch from public.zt_spaces) = 2, 'epoch 2';
  assert not (select rotation_needed from public.zt_spaces), 'rotated in the same step';
  assert (select count(*) from public.zt_space_keys) = 2, 'b has epochs 1 and 2';
end $$;
-- Writes sealed under the old key are refused.
select pg_temp.expect_error(
  $$insert into public.zt_space_items (space_id, item_id, key_epoch, data_blob, signature)
    values ('00000000-0000-0000-0000-0000000005a1', 'dose2', 1, '\x05', pg_temp.sig())$$,
  'old epoch', 'zt_space_key_stale');
insert into public.zt_space_items (space_id, item_id, key_epoch, data_blob, signature)
  values ('00000000-0000-0000-0000-0000000005a1', 'dose2', 2, '\x05', pg_temp.sig());

-- c is out: no rows, no keys, no writes.
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa03');
do $$ begin
  assert (select count(*) from public.zt_space_items) = 0, 'removed: no items';
  assert (select count(*) from public.zt_space_keys) = 0, 'removed: no keys';
  assert (select count(*) from public.zt_spaces) = 0, 'removed: no space';
end $$;
select pg_temp.expect_error(
  $$insert into public.zt_space_items (space_id, item_id, key_epoch, data_blob, signature)
    values ('00000000-0000-0000-0000-0000000005a1', 'dose3', 2, '\x06', pg_temp.sig())$$,
  'removed member writes', null);

-- 6. Roles, leaving, account deletion -----------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa01');
select pg_temp.expect_error(
  $$select public.zt_set_space_role('00000000-0000-0000-0000-0000000005a1',
      '00000000-0000-0000-0000-00000000aa09', 'admin')$$,
  'role for a non-member', 'zt_space_keys_mismatch');
select public.zt_set_space_role('00000000-0000-0000-0000-0000000005a1',
  '00000000-0000-0000-0000-00000000aa02', 'member');
select pg_temp.expect_error(
  $$select public.zt_set_space_role('00000000-0000-0000-0000-0000000005a1',
      '00000000-0000-0000-0000-00000000aa01', 'member')$$,
  'demote the last admin', 'zt_last_admin');

-- a leaves: b becomes admin, and the key must be rotated.
select public.zt_leave_space('00000000-0000-0000-0000-0000000005a1');
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa02');
do $$ begin
  assert (select role from public.zt_space_members) = 'admin', 'remaining member promoted';
  assert (select rotation_needed from public.zt_spaces), 'rotation needed after leaving';
end $$;
select public.zt_rotate_space_key('00000000-0000-0000-0000-0000000005a1', 3,
  format('[{"user_id":"00000000-0000-0000-0000-00000000aa02","wrapped_key":"%s","signature":"%s"}]',
         pg_temp.wrap64(), pg_temp.sig64())::jsonb);
do $$ begin
  assert (select key_epoch from public.zt_spaces) = 3, 'epoch 3';
end $$;

-- Deleting the last member's account deletes the space and its items.
reset role;
delete from auth.users where id = '00000000-0000-0000-0000-00000000aa02';
do $$ begin
  assert (select count(*) from public.zt_spaces) = 0, 'empty space deleted';
  assert (select count(*) from public.zt_space_items) = 0, 'its items deleted';
  assert (select count(*) from public.zt_space_invites) = 0, 'its invites deleted';
end $$;

-- 7. Admin deletes a space ----------------------------------------------------
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa01');
select public.zt_create_space('00000000-0000-0000-0000-0000000005a2', 'meds', pg_temp.wrap(), pg_temp.sig());
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa09');
select pg_temp.expect_error(
  $$select public.zt_delete_space('00000000-0000-0000-0000-0000000005a2')$$,
  'stranger deletes', 'zt_not_space_admin');
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa01');
select public.zt_delete_space('00000000-0000-0000-0000-0000000005a2');
do $$ begin
  assert (select count(*) from public.zt_spaces) = 0, 'space deleted';
end $$;
reset role;

-- Shared tombstones are purged too.
insert into public.zt_spaces (id, app) values ('00000000-0000-0000-0000-0000000005a3', 'meds');
insert into public.zt_space_items (space_id, item_id, key_epoch, signature, deleted)
  values ('00000000-0000-0000-0000-0000000005a3', 'gone', 1, pg_temp.sig(), true);
update public.zt_space_items set synced_at = now() - interval '200 days';
-- The guard sets synced_at on every write, so backdate with it off.
alter table public.zt_space_items disable trigger zt_space_items_guard;
update public.zt_space_items set synced_at = now() - interval '200 days';
alter table public.zt_space_items enable trigger zt_space_items_guard;
do $$ begin
  assert public.zt_purge_tombstones() >= 1, 'purged';
  assert not exists (select 1 from public.zt_space_items), 'shared tombstone gone';
end $$;
delete from public.zt_spaces;
delete from auth.users where email in ('a@x.com', 'c@x.com', 'x@x.com');

\echo shared_spaces_test: all checks passed
