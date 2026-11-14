-- Runs after booking_pages_test.sql (same psql session, so its pg_temp
-- helpers exist). Free-slot fixes: buffers after meetings that just ended,
-- and working hours checked against real clock times.
insert into auth.users values ('00000000-0000-0000-0000-0000000b0003', 'buffer@x.com');

-- Every day all day in UTC, 15-minute meetings every 5 minutes, 30 minutes
-- of buffer, no notice.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000b0003');
insert into public.zt_booking_pages (id, owner, title, duration_min, step_min, buffer_min, notice_min,
                                     horizon_days, time_zone, hours, public_key)
values ('page-bbbbbbbbbbbbbbbb', '00000000-0000-0000-0000-0000000b0003', 'Buffer', 15, 5, 30, 0, 1,
        'UTC', '{"1":[[0,1440]],"2":[[0,1440]],"3":[[0,1440]],"4":[[0,1440]],"5":[[0,1440]],"6":[[0,1440]],"7":[[0,1440]]}',
        pg_temp.pk());
-- A meeting that ended 5 minutes ago.
insert into public.zt_booking_busy (owner, blocks)
select '00000000-0000-0000-0000-0000000b0003',
       jsonb_build_array(jsonb_build_array(
         (extract(epoch from now() - interval '1 hour') * 1000)::bigint,
         (extract(epoch from now() - interval '5 minutes') * 1000)::bigint));
reset role;

set role anon;
create temp table buffer_slots as
  select (value #>> '{}')::timestamptz as s
    from json_array_elements(public.zt_booking_page('page-bbbbbbbbbbbbbbbb') -> 'slots');
select pg_temp.check(not exists (select 1 from buffer_slots where s < now() + interval '25 minutes'),
  'buffer after a meeting that just ended still blocks');
select pg_temp.check(exists (select 1 from buffer_slots where s < now() + interval '35 minutes'),
  'slots open once the buffer has passed');
reset role;

-- Hours 02:00-03:00 in New York: every slot starts at 02:00 local and ends
-- by 03:00 local. (On the day clocks go forward, 02:00 doesn't exist and
-- that day has no slot.)
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000b0003');
update public.zt_booking_pages
   set time_zone = 'America/New_York', duration_min = 60, step_min = 60, buffer_min = 0, horizon_days = 60,
       hours = '{"1":[[120,180]],"2":[[120,180]],"3":[[120,180]],"4":[[120,180]],"5":[[120,180]],"6":[[120,180]],"7":[[120,180]]}'
 where id = 'page-bbbbbbbbbbbbbbbb';
reset role;
set role anon;
select pg_temp.check(not exists (
  select 1 from json_array_elements(public.zt_booking_page('page-bbbbbbbbbbbbbbbb') -> 'slots') v
   where ((v #>> '{}')::timestamptz at time zone 'America/New_York')::time <> '02:00'
      or (((v #>> '{}')::timestamptz + interval '1 hour') at time zone 'America/New_York')::time <> '03:00'),
  'slots stay inside working hours in local time');
reset role;
-- The check the function uses: a start skipped by the clock change doesn't
-- round-trip, so it isn't offered.
select pg_temp.check((('2027-03-14 02:00'::timestamp at time zone 'America/New_York') at time zone 'America/New_York')
  <> '2027-03-14 02:00'::timestamp, 'skipped local time does not round-trip');

delete from auth.users where id = '00000000-0000-0000-0000-0000000b0003';
