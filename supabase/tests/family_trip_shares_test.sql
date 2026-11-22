-- Runs after 00_supabase_stub.sql and every migration. ZT Family L-1
-- "share my trip" links: owners write only their own sealed rows, anyone
-- with the id reads a running share and nothing else, rows end on time.
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
grant execute on all functions in schema pg_temp to anon, authenticated;

insert into auth.users values
  ('00000000-0000-0000-0000-00000000ab01', 'owner@trip.test'),
  ('00000000-0000-0000-0000-00000000ab02', 'other@trip.test');

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000ab01';

-- Owner is the server's, a share lasts at most 4 hours.
insert into public.family_trip_shares (id, owner, payload, expires_at)
  values ('AAAAAAAAAAAAAAAAAAAAAA', '00000000-0000-0000-0000-00000000ab02',
          'sealed-1', now() + interval '1 day');
do $$ begin
  assert (select owner from public.family_trip_shares where id = 'AAAAAAAAAAAAAAAAAAAAAA')
    = '00000000-0000-0000-0000-00000000ab01', 'owner forced to the caller';
  assert (select expires_at <= created_at + interval '4 hours'
            from public.family_trip_shares where id = 'AAAAAAAAAAAAAAAAAAAAAA'),
    'capped at 4 hours';
end $$;

select pg_temp.expect_error($$insert into public.family_trip_shares (id, payload, expires_at)
  values ('EEEEEEEEEEEEEEEEEEEEEE', 'x', now() - interval '1 minute')$$,
  'already ended', 'family_trip_ended');
insert into public.family_trip_shares (id, payload, expires_at)
  values ('BBBBBBBBBBBBBBBBBBBBBB', 'sealed-2', now() + interval '1 hour'),
         ('CCCCCCCCCCCCCCCCCCCCCC', 'sealed-3', now() + interval '1 hour');
select pg_temp.expect_error($$insert into public.family_trip_shares (id, payload, expires_at)
  values ('DDDDDDDDDDDDDDDDDDDDDD', 'x', now() + interval '1 hour')$$,
  'fourth running share', 'family_too_many_trips');
select pg_temp.expect_error($$insert into public.family_trip_shares (id, payload, expires_at)
  values ('not a good id', 'x', now() + interval '1 hour')$$, 'bad id', null);

-- Updating the sealed position works; moving it to another id doesn't.
update public.family_trip_shares set payload = 'sealed-1b' where id = 'AAAAAAAAAAAAAAAAAAAAAA';
select pg_temp.expect_error($$update public.family_trip_shares set id = 'FFFFFFFFFFFFFFFFFFFFFF'
  where id = 'AAAAAAAAAAAAAAAAAAAAAA'$$, 'move id', 'family_trip_moved');

-- Someone else sees and changes nothing.
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000ab02';
do $$ begin
  assert (select count(*) from public.family_trip_shares) = 0, 'others list nothing';
end $$;
update public.family_trip_shares set payload = 'hijack';
delete from public.family_trip_shares;
reset role;
do $$ begin
  assert (select count(*) from public.family_trip_shares) = 3, 'others delete nothing';
  assert (select payload from public.family_trip_shares where id = 'AAAAAAAAAAAAAAAAAAAAAA') = 'sealed-1b',
    'others change nothing';
end $$;

-- Anyone with the link reads a running share, by id only.
set role anon;
do $$ begin
  assert (select payload from public.family_trip_get('AAAAAAAAAAAAAAAAAAAAAA')) = 'sealed-1b', 'link reads';
  assert not exists (select 1 from public.family_trip_get('ZZZZZZZZZZZZZZZZZZZZZZ')), 'unknown id';
end $$;
select pg_temp.expect_error($$select * from public.family_trip_shares$$, 'anon lists', null);
reset role;

-- Ended shares stop showing and are purged; rows go with the account.
alter table public.family_trip_shares disable trigger family_trip_guard;
update public.family_trip_shares set expires_at = now() - interval '1 minute'
  where id = 'BBBBBBBBBBBBBBBBBBBBBB';
alter table public.family_trip_shares enable trigger family_trip_guard;
set role anon;
do $$ begin
  assert not exists (select 1 from public.family_trip_get('BBBBBBBBBBBBBBBBBBBBBB')), 'ended share hidden';
end $$;
reset role;
do $$ begin
  assert public.family_purge_trips() = 1, 'purge removes the ended share';
end $$;
delete from auth.users where id = '00000000-0000-0000-0000-00000000ab01';
do $$ begin
  assert (select count(*) from public.family_trip_shares) = 0, 'rows go with the account';
end $$;

\echo family_trip_shares_test: all checks passed
