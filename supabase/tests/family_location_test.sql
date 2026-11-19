-- Runs after 00_supabase_stub.sql and every migration. ZT Family location
-- tables: only a circle's members read them, everyone writes only as
-- themselves, and rows go away with the member, the circle or the window.
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
create or replace function pg_temp.sig() returns bytea language sql as $$ select decode(repeat('51', 64), 'hex') $$;
create or replace function pg_temp.wrap() returns bytea language sql as $$ select decode(repeat('77', 80), 'hex') $$;
grant execute on all functions in schema pg_temp to authenticated;

-- m = mum (creates the circle), d = dad, x = stranger.
insert into auth.users values
  ('00000000-0000-0000-0000-00000000fa01', 'm@family.test'),
  ('00000000-0000-0000-0000-00000000fa02', 'd@family.test'),
  ('00000000-0000-0000-0000-00000000fa09', 'x@family.test');

set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000fa01');
select public.zt_create_space('00000000-0000-0000-0000-00000000f001', 'family', pg_temp.wrap(), pg_temp.sig());
-- A space of another app, to show it takes no location rows.
select public.zt_create_space('00000000-0000-0000-0000-00000000f002', 'tasks', pg_temp.wrap(), pg_temp.sig());

-- Dad is let in (set up directly: invites are covered by shared_spaces_test).
reset role;
insert into public.zt_space_members (space_id, user_id, role)
  values ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa02', 'member');
set role authenticated;

-- 1. Writing as yourself ------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-00000000fa01');
insert into public.family_latest (space_id, user_id, device_id, key_epoch, payload, signature)
  values ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa01',
          'pixel', 1, '\x01', pg_temp.sig());
-- The newest update replaces the row; the time is the server's.
insert into public.family_latest (space_id, user_id, device_id, key_epoch, payload, signature, sent_at)
  values ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa01',
          'pixel', 1, '\x02', pg_temp.sig(), '2001-01-01')
  on conflict (space_id, user_id, device_id) do update
    set payload = excluded.payload, signature = excluded.signature, key_epoch = excluded.key_epoch;
do $$ begin
  assert (select count(*) from public.family_latest) = 1, 'one latest row per device';
  assert (select payload from public.family_latest) = '\x02', 'latest row replaced';
  assert (select sent_at from public.family_latest) > now() - interval '1 minute',
    'sent_at is set by the server';
end $$;

insert into public.family_events (space_id, user_id, device_id, key_epoch, payload, signature, sent_at)
  values ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa01',
          'pixel', 1, '\x0a', pg_temp.sig(), '2001-01-01');
do $$ begin
  assert (select sent_at from public.family_events) > now() - interval '1 minute',
    'an event cannot be backdated';
end $$;

-- 2. Not in someone else's name ----------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-00000000fa02');
-- Dad naming Mum as the sender: the row is written as Dad.
insert into public.family_latest (space_id, user_id, device_id, key_epoch, payload, signature)
  values ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa01',
          'dads-phone', 1, '\x03', pg_temp.sig());
insert into public.family_events (space_id, user_id, device_id, key_epoch, payload, signature)
  values ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa01',
          'dads-phone', 1, '\x0b', pg_temp.sig());
do $$ begin
  assert (select user_id from public.family_latest where device_id = 'dads-phone')
    = '00000000-0000-0000-0000-00000000fa02', 'latest is written as the caller';
  assert (select user_id from public.family_events where device_id = 'dads-phone')
    = '00000000-0000-0000-0000-00000000fa02', 'event is written as the caller';
  -- Members read each other.
  assert (select count(*) from public.family_latest) = 2, 'dad sees both latest rows';
  assert (select count(*) from public.family_events) = 2, 'dad sees both events';
end $$;
-- Dad can't change or delete Mum's rows (the policies hide them from his
-- update and delete, so nothing happens).
update public.family_latest set payload = '\xff' where device_id = 'pixel';
delete from public.family_latest where device_id = 'pixel';
delete from public.family_events where device_id = 'pixel';
do $$ begin
  assert (select payload from public.family_latest where device_id = 'pixel') = '\x02',
    'another member''s latest row is untouched';
  assert (select count(*) from public.family_events where device_id = 'pixel') = 1,
    'another member''s event is untouched';
end $$;
-- Nobody edits an event, not even their own.
select pg_temp.expect_error(
  $$update public.family_events set payload = '\xff'$$, 'event update', null);
-- A row can't be moved to another device or circle.
select pg_temp.expect_error(
  $$update public.family_latest set device_id = 'other' where device_id = 'dads-phone'$$,
  'latest row moved', 'family_row_moved');

-- 3. Checks on the row --------------------------------------------------------
-- An old key is refused, like for shared items.
select pg_temp.expect_error(
  $$insert into public.family_events (space_id, user_id, device_id, key_epoch, payload, signature)
    values ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa02',
            'dads-phone', 2, '\x0c', pg_temp.sig())$$,
  'stale key epoch', 'zt_space_key_stale');
select pg_temp.expect_error(
  $$insert into public.family_events (space_id, user_id, device_id, key_epoch, payload, signature)
    values ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa02',
            'dads-phone', 1, decode(repeat('00', 4097), 'hex'), pg_temp.sig())$$,
  'oversized event', null);
select pg_temp.expect_error(
  $$insert into public.family_latest (space_id, user_id, device_id, key_epoch, payload, signature)
    values ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa02',
            'tablet', 1, decode(repeat('00', 2049), 'hex'), pg_temp.sig())$$,
  'oversized latest', null);
select pg_temp.expect_error(
  $$insert into public.family_latest (space_id, user_id, device_id, key_epoch, payload, signature)
    values ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa02',
            'tablet', 1, '\x01', '\x00')$$,
  'short signature', null);
-- Only Family circles take location rows.
select pg_temp.as_user('00000000-0000-0000-0000-00000000fa01');
select pg_temp.expect_error(
  $$insert into public.family_latest (space_id, user_id, device_id, key_epoch, payload, signature)
    values ('00000000-0000-0000-0000-00000000f002', '00000000-0000-0000-0000-00000000fa01',
            'pixel', 1, '\x01', pg_temp.sig())$$,
  'location in a Tasks space', 'family_not_a_circle');

-- 4. Strangers ----------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-00000000fa09');
do $$ begin
  assert (select count(*) from public.family_latest) = 0, 'stranger sees no latest rows';
  assert (select count(*) from public.family_events) = 0, 'stranger sees no events';
  assert (select count(*) from public.family_settings) = 0, 'stranger sees no settings';
end $$;
select pg_temp.expect_error(
  $$insert into public.family_latest (space_id, user_id, device_id, key_epoch, payload, signature)
    values ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa09',
            'spy', 1, '\x01', pg_temp.sig())$$,
  'stranger writes latest', null);
select pg_temp.expect_error(
  $$insert into public.family_events (space_id, user_id, device_id, key_epoch, payload, signature)
    values ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa09',
            'spy', 1, '\x01', pg_temp.sig())$$,
  'stranger writes an event', null);
select pg_temp.expect_error(
  $$select public.family_set_history_days('00000000-0000-0000-0000-00000000f001', 3)$$,
  'stranger sets history', 'zt_not_space_admin');
set role anon;
select pg_temp.expect_error($$select count(*) from public.family_latest$$, 'anon reads latest', null);
select pg_temp.expect_error($$select count(*) from public.family_events$$, 'anon reads events', null);
set role authenticated;

-- 5. History window -----------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-00000000fa02');
select pg_temp.expect_error(
  $$select public.family_set_history_days('00000000-0000-0000-0000-00000000f001', 3)$$,
  'member sets history', 'zt_not_space_admin');
select pg_temp.expect_error(
  $$insert into public.family_settings (space_id, history_days)
    values ('00000000-0000-0000-0000-00000000f001', 30)$$,
  'direct settings insert', null);
select pg_temp.expect_error(
  $$select public.family_purge_history()$$, 'member runs the cleanup', null);
select pg_temp.as_user('00000000-0000-0000-0000-00000000fa01');
select pg_temp.expect_error(
  $$select public.family_set_history_days('00000000-0000-0000-0000-00000000f001', 31)$$,
  'history over 30 days', 'family_bad_history_days');
select pg_temp.expect_error(
  $$select public.family_set_history_days('00000000-0000-0000-0000-00000000f001', 0)$$,
  'history under a day', 'family_bad_history_days');
select pg_temp.expect_error(
  $$select public.family_set_history_days('00000000-0000-0000-0000-00000000f002', 3)$$,
  'history on a Tasks space', 'family_not_a_circle');

-- Default window is 7 days: an 8-day-old event goes, a 6-day-old one stays.
reset role;
alter table public.family_events disable trigger user;
alter table public.family_latest disable trigger user;
insert into public.family_events (space_id, user_id, device_id, key_epoch, payload, signature, sent_at)
  values ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa01',
          'old-8', 1, '\x01', pg_temp.sig(), now() - interval '8 days'),
         ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa01',
          'old-6', 1, '\x01', pg_temp.sig(), now() - interval '6 days'),
         ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa01',
          'old-2', 1, '\x01', pg_temp.sig(), now() - interval '2 days');
insert into public.family_latest (space_id, user_id, device_id, key_epoch, payload, signature, sent_at)
  values ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa01',
          'lost-phone', 1, '\x01', pg_temp.sig(), now() - interval '31 days');
alter table public.family_events enable trigger user;
alter table public.family_latest enable trigger user;
select public.family_purge_history();
do $$ begin
  assert not exists (select 1 from public.family_events where device_id = 'old-8'),
    '8-day-old event purged at the default 7 days';
  assert exists (select 1 from public.family_events where device_id = 'old-6'),
    '6-day-old event kept';
  assert not exists (select 1 from public.family_latest where device_id = 'lost-phone'),
    'a device silent for 30 days is dropped from the map';
  assert exists (select 1 from public.family_latest where device_id = 'pixel'),
    'a live device stays';
end $$;
-- The owner shortens the window to 3 days.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000fa01');
select public.family_set_history_days('00000000-0000-0000-0000-00000000f001', 3);
select public.family_set_history_days('00000000-0000-0000-0000-00000000f001', 3);
do $$ begin
  assert (select history_days from public.family_settings) = 3, 'history window saved once';
end $$;
-- More than 7 days needs Plus (the `family` feature).
select pg_temp.expect_error(
  $$select public.family_set_history_days('00000000-0000-0000-0000-00000000f001', 30)$$,
  'free owner keeps 30 days', 'family_needs_plus');
reset role;
select public.zt_grant_plan('00000000-0000-0000-0000-00000000fa01', 'plus', null, 'family test');
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000fa01');
select public.family_set_history_days('00000000-0000-0000-0000-00000000f001', 30);
do $$ begin
  assert (select history_days from public.family_settings) = 30, 'Plus owner keeps 30 days';
end $$;
reset role;
delete from public.zt_subscriptions where user_id = '00000000-0000-0000-0000-00000000fa01';
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000fa01');
-- Plus ended: the 30 days stay, can be shortened, but not lengthened again.
select public.family_set_history_days('00000000-0000-0000-0000-00000000f001', 14);
do $$ begin
  assert (select history_days from public.family_settings) = 14, 'shortened after Plus ended';
end $$;
select pg_temp.expect_error(
  $$select public.family_set_history_days('00000000-0000-0000-0000-00000000f001', 20)$$,
  'lengthened after Plus ended', 'family_needs_plus');
select public.family_set_history_days('00000000-0000-0000-0000-00000000f001', 3);
reset role;
select public.family_purge_history();
do $$ begin
  assert not exists (select 1 from public.family_events where device_id = 'old-6'),
    '6-day-old event purged at 3 days';
  assert exists (select 1 from public.family_events where device_id = 'old-2'),
    '2-day-old event kept at 3 days';
end $$;

-- 6. Too many events ----------------------------------------------------------
alter table public.family_events disable trigger user;
insert into public.family_events (space_id, user_id, device_id, key_epoch, payload, signature)
  select '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa02',
         'flood', 1, '\x01', pg_temp.sig() from generate_series(1, 1200);
alter table public.family_events enable trigger user;
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000fa02');
select pg_temp.expect_error(
  $$insert into public.family_events (space_id, user_id, device_id, key_epoch, payload, signature)
    values ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa02',
            'dads-phone', 1, '\x01', pg_temp.sig())$$,
  'more than 1200 events in an hour', 'family_too_many_events');
-- Mum is not held back by Dad's flood.
select pg_temp.as_user('00000000-0000-0000-0000-00000000fa01');
insert into public.family_events (space_id, user_id, device_id, key_epoch, payload, signature)
  values ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa01',
          'pixel', 1, '\x0d', pg_temp.sig());

-- 7. Erasing and leaving ------------------------------------------------------
-- A member erases their own history and last location.
select pg_temp.as_user('00000000-0000-0000-0000-00000000fa02');
delete from public.family_events where user_id = '00000000-0000-0000-0000-00000000fa02';
delete from public.family_latest where user_id = '00000000-0000-0000-0000-00000000fa02';
do $$ begin
  assert not exists (select 1 from public.family_events
                      where user_id = '00000000-0000-0000-0000-00000000fa02'), 'own history erased';
  assert not exists (select 1 from public.family_latest
                      where user_id = '00000000-0000-0000-0000-00000000fa02'), 'own latest erased';
end $$;
insert into public.family_latest (space_id, user_id, device_id, key_epoch, payload, signature)
  values ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa02',
          'dads-phone', 1, '\x04', pg_temp.sig());
insert into public.family_events (space_id, user_id, device_id, key_epoch, payload, signature)
  values ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa02',
          'dads-phone', 1, '\x0e', pg_temp.sig());
-- Leaving takes every row of his with him, and he can't write any more.
select public.zt_leave_space('00000000-0000-0000-0000-00000000f001');
select pg_temp.expect_error(
  $$insert into public.family_latest (space_id, user_id, device_id, key_epoch, payload, signature)
    values ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000fa02',
            'dads-phone', 1, '\x05', pg_temp.sig())$$,
  'writing after leaving', null);
select pg_temp.as_user('00000000-0000-0000-0000-00000000fa01');
do $$ begin
  assert not exists (select 1 from public.family_latest
                      where user_id = '00000000-0000-0000-0000-00000000fa02'),
    'latest rows leave with the member';
  assert not exists (select 1 from public.family_events
                      where user_id = '00000000-0000-0000-0000-00000000fa02'),
    'history leaves with the member';
  assert exists (select 1 from public.family_latest
                  where user_id = '00000000-0000-0000-0000-00000000fa01'),
    'the others keep theirs';
end $$;
-- Deleting the circle deletes everything in it.
select public.zt_delete_space('00000000-0000-0000-0000-00000000f001');
reset role;
do $$ begin
  assert (select count(*) from public.family_latest) = 0, 'latest gone with the circle';
  assert (select count(*) from public.family_events) = 0, 'history gone with the circle';
  assert (select count(*) from public.family_settings) = 0, 'settings gone with the circle';
end $$;
-- Leave the database as the other tests expect it.
delete from public.zt_spaces where id = '00000000-0000-0000-0000-00000000f002';
delete from auth.users where id in (
  '00000000-0000-0000-0000-00000000fa01', '00000000-0000-0000-0000-00000000fa02',
  '00000000-0000-0000-0000-00000000fa09');
