-- Runs after 00_supabase_stub.sql and every migration. K15 booking pages:
-- what visitors (anon) can reach, slots, booking, cancelling, owner rules.
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
create or replace function pg_temp.check(ok boolean, msg text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'check failed: %', msg; end if;
end $$;
grant execute on all functions in schema pg_temp to authenticated, anon;

insert into auth.users values
  ('00000000-0000-0000-0000-0000000b0001', 'host@x.com'),
  ('00000000-0000-0000-0000-0000000b0002', 'other@x.com');

-- A key-shaped placeholder (65 bytes, base64).
create or replace function pg_temp.pk() returns text language sql as $$
  select translate(encode(decode(repeat('04', 65), 'hex'), 'base64'), E'\n', '') $$;
create or replace function pg_temp.sealed() returns text language sql as $$
  select repeat('A', 120) $$;
grant execute on all functions in schema pg_temp to authenticated, anon;

-- Every day 00:00-24:00 in UTC, 60-minute slots on the hour, no notice, so the
-- test doesn't depend on the clock.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000b0001');
insert into public.zt_booking_pages (id, owner, title, host_name, duration_min, step_min, notice_min,
                                     horizon_days, time_zone, hours, public_key)
values ('page-aaaaaaaaaaaaaaaa', '00000000-0000-0000-0000-0000000b0001', 'Chat', 'Host', 60, 60, 0, 3,
        'UTC', '{"1":[[0,1440]],"2":[[0,1440]],"3":[[0,1440]],"4":[[0,1440]],"5":[[0,1440]],"6":[[0,1440]],"7":[[0,1440]]}',
        pg_temp.pk());

-- Bad settings are refused.
select pg_temp.expect_error($$insert into public.zt_booking_pages (id, owner, title, duration_min, time_zone, hours, public_key)
  values ('page-bbbbbbbbbbbbbbbb', '00000000-0000-0000-0000-0000000b0001', 'X', 30, 'Mars/Base', '{}', pg_temp.pk())$$,
  'unknown time zone', null);
select pg_temp.expect_error($$insert into public.zt_booking_pages (id, owner, title, duration_min, time_zone, hours, public_key)
  values ('page-bbbbbbbbbbbbbbbb', '00000000-0000-0000-0000-0000000b0001', 'X', 30, 'UTC', '{"8":[[0,60]]}', pg_temp.pk())$$,
  'weekday 8', null);
select pg_temp.expect_error($$insert into public.zt_booking_pages (id, owner, title, duration_min, time_zone, hours, public_key)
  values ('page-bbbbbbbbbbbbbbbb', '00000000-0000-0000-0000-0000000b0001', 'X', 30, 'UTC', '{"1":[[600,60]]}', pg_temp.pk())$$,
  'end before start', null);
select pg_temp.expect_error($$insert into public.zt_booking_pages (id, owner, title, duration_min, time_zone, hours, public_key)
  values ('page-bbbbbbbbbbbbbbbb', '00000000-0000-0000-0000-0000000b0002', 'X', 30, 'UTC', '{}', pg_temp.pk())$$,
  'page for someone else', null);

-- No busy times uploaded yet: no slots.
reset role;
set role anon;
select pg_temp.check(json_array_length(public.zt_booking_page('page-aaaaaaaaaaaaaaaa') -> 'slots') = 0,
  'no slots before busy times exist');
select pg_temp.check(public.zt_booking_page('page-nonexistentxxxx') is null, 'unknown page is null');

-- Anon can't read the tables.
select pg_temp.expect_error('select * from public.zt_booking_pages', 'anon reads pages', null);
select pg_temp.expect_error('select * from public.zt_booking_busy', 'anon reads busy', null);
select pg_temp.expect_error('select * from public.zt_bookings', 'anon reads bookings', null);
reset role;

-- The host is busy for the next 2 hours from the next full hour.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000b0001');
insert into public.zt_booking_busy (owner, blocks)
select '00000000-0000-0000-0000-0000000b0001',
       jsonb_build_array(jsonb_build_array(
         (extract(epoch from date_trunc('hour', now()) + interval '1 hour') * 1000)::bigint,
         (extract(epoch from date_trunc('hour', now()) + interval '3 hours') * 1000)::bigint));
select pg_temp.expect_error($$update public.zt_booking_busy set blocks = '[[5, 1]]'$$, 'reversed block', null);
select pg_temp.expect_error($$update public.zt_booking_busy set blocks = '["x"]'$$, 'bad block', null);
reset role;

set role anon;
create temp table slots as
  select (value #>> '{}')::timestamptz as s
    from json_array_elements(public.zt_booking_page('page-aaaaaaaaaaaaaaaa') -> 'slots');
select pg_temp.check((select count(*) from slots) > 10, 'slots exist');
select pg_temp.check(not exists (select 1 from slots
  where s in (date_trunc('hour', now()) + interval '1 hour', date_trunc('hour', now()) + interval '2 hours')),
  'busy hours are not offered');
select pg_temp.check(exists (select 1 from slots where s = date_trunc('hour', now()) + interval '3 hours'),
  'the hour after busy is offered');
select pg_temp.check(not exists (select 1 from slots where s < now()), 'no past slots');
select pg_temp.check(public.zt_booking_page('page-aaaaaaaaaaaaaaaa') ->> 'publicKey' = pg_temp.pk(), 'public key shown');
select pg_temp.check((public.zt_booking_page('page-aaaaaaaaaaaaaaaa')::jsonb ? 'owner') = false, 'owner not shown');

-- Booking holds the slot at once; a second visitor can't take it.
create temp table booked as
  select public.zt_book_slot('page-aaaaaaaaaaaaaaaa', date_trunc('hour', now()) + interval '4 hours', pg_temp.sealed()) as j;
select pg_temp.check((select (j ->> 'end')::timestamptz - (j ->> 'start')::timestamptz from booked) = interval '1 hour', 'booked an hour');
select pg_temp.expect_error($$select public.zt_book_slot('page-aaaaaaaaaaaaaaaa', date_trunc('hour', now()) + interval '4 hours', pg_temp.sealed())$$,
  'double booking', 'zt_booking_slot_taken');
select pg_temp.expect_error($$select public.zt_book_slot('page-aaaaaaaaaaaaaaaa', date_trunc('hour', now()) + interval '1 hour', pg_temp.sealed())$$,
  'booking a busy hour', 'zt_booking_slot_taken');
select pg_temp.expect_error($$select public.zt_book_slot('page-aaaaaaaaaaaaaaaa', date_trunc('hour', now()) + interval '5 hours 7 minutes', pg_temp.sealed())$$,
  'booking off the grid', 'zt_booking_slot_taken');
select pg_temp.expect_error($$select public.zt_book_slot('page-aaaaaaaaaaaaaaaa', date_trunc('hour', now()) + interval '5 hours', 'short')$$,
  'nothing sealed', 'zt_booking_invalid');
select pg_temp.check(not exists (select 1 from json_array_elements(public.zt_booking_page('page-aaaaaaaaaaaaaaaa') -> 'slots') v
  where (v #>> '{}')::timestamptz = date_trunc('hour', now()) + interval '4 hours'), 'booked slot no longer offered');

-- The visitor sees and cancels their booking only with the token.
select pg_temp.expect_error($$select public.zt_booking_status((select (j ->> 'id')::uuid from booked), 'wrong')$$,
  'status with a wrong token', 'zt_booking_invalid');
select pg_temp.expect_error($$select public.zt_cancel_booking((select (j ->> 'id')::uuid from booked), null)$$,
  'cancel without a token', 'zt_booking_invalid');
select pg_temp.check((public.zt_booking_status((select (j ->> 'id')::uuid from booked), (select j ->> 'cancelToken' from booked)) ->> 'title') = 'Chat',
  'status with the token');
reset role;

-- The owner sees it with its sealed details and adds it to the calendar.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000b0002');
select pg_temp.check((select count(*) from public.zt_bookings) = 0, 'others see no bookings');
select pg_temp.check((select count(*) from public.zt_booking_pages) = 0, 'others see no pages');
update public.zt_bookings set status = 'cancelled';
select pg_temp.as_user('00000000-0000-0000-0000-0000000b0001');
select pg_temp.check((select status from public.zt_bookings) = 'new', 'others can''t cancel');
select pg_temp.check((select sealed from public.zt_bookings) = pg_temp.sealed(), 'owner reads sealed details');
select pg_temp.expect_error($$update public.zt_bookings set starts_at = starts_at + interval '1 hour'$$, 'owner moves a booking', null);
select pg_temp.expect_error($$update public.zt_bookings set status = 'cancel_requested'$$, 'owner sets cancel_requested', null);
select pg_temp.expect_error($$insert into public.zt_bookings (page_id, owner, starts_at, ends_at, cancel_hash)
  values ('page-aaaaaaaaaaaaaaaa', '00000000-0000-0000-0000-0000000b0001', now(), now() + interval '1 hour', '\x00')$$,
  'owner inserts a booking', null);
update public.zt_bookings set status = 'added', sealed = null;
-- Until the phone uploads busy times again, the added booking still blocks
-- its slot.
reset role;
set role anon;
select pg_temp.check(not exists (select 1 from json_array_elements(public.zt_booking_page('page-aaaaaaaaaaaaaaaa') -> 'slots') v
  where (v #>> '{}')::timestamptz = date_trunc('hour', now()) + interval '4 hours'), 'added booking still blocks before busy upload');

-- Cancelling an added booking asks the phone to remove it.
select pg_temp.check((public.zt_cancel_booking((select (j ->> 'id')::uuid from booked), (select j ->> 'cancelToken' from booked)) ->> 'cancelled')::boolean,
  'visitor cancels');
reset role;
select pg_temp.check((select status from public.zt_bookings) = 'cancel_requested', 'cancel requested');
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000b0001');
update public.zt_bookings set status = 'cancelled';
select pg_temp.check((select status from public.zt_bookings) = 'cancelled', 'phone confirms cancel');

-- A paused page is gone for visitors.
update public.zt_booking_pages set active = false;
reset role;
set role anon;
select pg_temp.check(public.zt_booking_page('page-aaaaaaaaaaaaaaaa') is null, 'paused page hidden');
select pg_temp.expect_error($$select public.zt_book_slot('page-aaaaaaaaaaaaaaaa', date_trunc('hour', now()) + interval '6 hours', pg_temp.sealed())$$,
  'booking a paused page', 'zt_booking_page_gone');
reset role;

-- Deleting the account removes pages, busy times and bookings.
delete from auth.users where id = '00000000-0000-0000-0000-0000000b0001';
select pg_temp.check((select count(*) from public.zt_booking_pages) + (select count(*) from public.zt_booking_busy)
  + (select count(*) from public.zt_bookings) = 0, 'account deletion cascades');
