-- Runs after 00_supabase_stub.sql and every migration. K-5 meeting polls:
-- owners manage their polls, guests (anon) only read one poll and vote
-- through the two functions, and edit only their own vote.
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
  ('00000000-0000-0000-0000-0000000c0001', 'owner@x.com'),
  ('00000000-0000-0000-0000-0000000c0002', 'other@x.com');

set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000c0001');
insert into public.zt_polls (id, owner, sealed, expires_at)
values ('pAAAAAAAAAAAAAAAAAA', '00000000-0000-0000-0000-0000000c0001', repeat('A', 80), now() + interval '30 days');
select pg_temp.expect_error($$insert into public.zt_polls (id, owner, sealed, expires_at)
  values ('pBBBBBBBBBBBBBBBBBB', '00000000-0000-0000-0000-0000000c0002', repeat('A', 80), now() + interval '1 day')$$,
  'poll for someone else', null);
select pg_temp.expect_error($$insert into public.zt_polls (id, owner, sealed, expires_at)
  values ('pCCCCCCCCCCCCCCCCCC', '00000000-0000-0000-0000-0000000c0001', repeat('A', 80), now() + interval '500 days')$$,
  'poll too long', 'a poll lasts at most 400 days');
select pg_temp.expect_error($$update public.zt_polls set id = 'pDDDDDDDDDDDDDDDDDD'$$,
  'poll keeps its id', 'a poll keeps its id and owner');
-- Owners can't write votes directly.
select pg_temp.expect_error($$insert into public.zt_poll_votes (poll_id, owner, sealed, edit_hash)
  values ('pAAAAAAAAAAAAAAAAAA', '00000000-0000-0000-0000-0000000c0001', repeat('V', 60), '\x00')$$,
  'owner inserts a vote', null);

-- Guests: the tables are closed, the functions work.
reset role;
set role anon;
select pg_temp.expect_error($$select * from public.zt_polls$$, 'anon reads polls', null);
select pg_temp.check(public.zt_poll('pZZZZZZZZZZZZZZZZZZ') is null, 'unknown poll is null');
select pg_temp.check(json_array_length(public.zt_poll('pAAAAAAAAAAAAAAAAAA')->'votes') = 0, 'no votes yet');
create temp table v as select public.zt_poll_vote('pAAAAAAAAAAAAAAAAAA', repeat('V', 60)) as r;
select pg_temp.check(json_array_length(public.zt_poll('pAAAAAAAAAAAAAAAAAA')->'votes') = 1, 'one vote');
-- Change it with its token; a wrong token is refused.
select pg_temp.expect_error(format($$select public.zt_poll_vote('pAAAAAAAAAAAAAAAAAA', repeat('W', 60), %L, 'wrong')$$,
  (select r->>'id' from v)), 'wrong edit token', 'zt_poll_invalid');
select public.zt_poll_vote('pAAAAAAAAAAAAAAAAAA', repeat('W', 60), (select (r->>'id')::uuid from v),
                           (select r->>'editToken' from v));
select pg_temp.check(public.zt_poll('pAAAAAAAAAAAAAAAAAA')->'votes'->0->>'sealed' = repeat('W', 60), 'vote changed');
select pg_temp.expect_error($$select public.zt_poll_vote('pAAAAAAAAAAAAAAAAAA', 'short')$$,
  'too short', 'zt_poll_invalid');

-- The owner reads votes; another account doesn't. A closed poll takes no votes.
reset role;
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000c0002');
select pg_temp.check((select count(*) from public.zt_poll_votes) = 0, 'other account sees no votes');
select pg_temp.check((select count(*) from public.zt_polls) = 0, 'other account sees no polls');
select pg_temp.as_user('00000000-0000-0000-0000-0000000c0001');
select pg_temp.check((select count(*) from public.zt_poll_votes) = 1, 'owner sees the vote');
update public.zt_polls set closed = true where id = 'pAAAAAAAAAAAAAAAAAA';
reset role;
set role anon;
select pg_temp.expect_error($$select public.zt_poll_vote('pAAAAAAAAAAAAAAAAAA', repeat('V', 60))$$,
  'closed poll', 'zt_poll_closed');
reset role;
-- Expired polls disappear for guests.
update public.zt_polls set expires_at = now() - interval '1 minute';
set role anon;
select pg_temp.check(public.zt_poll('pAAAAAAAAAAAAAAAAAA') is null, 'expired poll is gone');
reset role;

-- At most 30 live polls, also when an expired one is moved into the future.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000c0001');
insert into public.zt_polls (id, owner, sealed, expires_at)
select 'pLIMIT' || lpad(i::text, 12, '0'), '00000000-0000-0000-0000-0000000c0001',
       repeat('A', 80), now() + interval '1 day'
from generate_series(1, 30) i;
select pg_temp.expect_error($$insert into public.zt_polls (id, owner, sealed, expires_at)
  values ('pEEEEEEEEEEEEEEEEEE', '00000000-0000-0000-0000-0000000c0001', repeat('A', 80), now() + interval '1 day')$$,
  'a 31st live poll', 'zt_poll_limit');
select pg_temp.expect_error($$update public.zt_polls set expires_at = now() + interval '1 day'
  where id = 'pAAAAAAAAAAAAAAAAAA'$$, 'reviving an expired poll past the limit', 'zt_poll_limit');
-- Live polls can still be changed at the limit.
update public.zt_polls set closed = true where id = 'pLIMIT000000000001';
select pg_temp.check((select closed from public.zt_polls where id = 'pLIMIT000000000001'), 'closed at the limit');
reset role;
delete from public.zt_polls where id like 'pLIMIT%';
