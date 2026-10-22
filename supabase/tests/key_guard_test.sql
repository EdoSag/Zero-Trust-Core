-- Runs after 00_supabase_stub.sql and every migration. Any failed check
-- raises, and psql -v ON_ERROR_STOP=1 fails the CI job.
create function pg_temp.expect_error(stmt text, msg text) returns void
language plpgsql as $$
begin
  execute stmt;
  raise exception 'expected failure: %', msg;
exception when others then
  if sqlerrm like 'expected failure:%' then raise; end if;
end $$;

insert into auth.users values
  ('00000000-0000-0000-0000-00000000000a', 'legacy@x.com'),
  ('00000000-0000-0000-0000-00000000000b', 'v2@x.com'),
  ('00000000-0000-0000-0000-00000000000c', 'other@x.com');
insert into public.profiles (id, salt) values
  ('00000000-0000-0000-0000-00000000000a', 'c2FsdA'),
  ('00000000-0000-0000-0000-00000000000c', 'c2FsdA');
insert into public.profiles (id, key_version, kdf_salt, kdf_params, wrapped_dek, recovery_wrapped_dek)
  values ('00000000-0000-0000-0000-00000000000b', 2, '\x01', '{}', '\x0a', '\x0b');

-- Legacy lookup, as anon before sign-in.
set role anon;
do $$ begin
  assert public.zt_needs_legacy_sign_in(' Legacy@X.com '), 'legacy account';
  assert not public.zt_needs_legacy_sign_in('v2@x.com'), 'v2 account';
  assert not public.zt_needs_legacy_sign_in('nobody@x.com'), 'unknown email';
end $$;
reset role;

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
update public.profiles set key_version = 2, kdf_salt = '\x01', kdf_params = '{}',
  wrapped_dek = '\x0a', recovery_wrapped_dek = '\x0b', legacy_dek = true
  where id = auth.uid();
do $$ begin
  assert public.zt_needs_legacy_sign_in('legacy@x.com'), 'mid-upgrade stays legacy';
end $$;
update public.profiles set auth_upgraded_at = now() where id = auth.uid();
do $$ begin
  assert not public.zt_needs_legacy_sign_in('legacy@x.com'), 'switched account';
end $$;

select pg_temp.expect_error($$update public.profiles set wrapped_dek = null where id = auth.uid()$$, 'remove wrapped_dek');
select pg_temp.expect_error($$update public.profiles set recovery_wrapped_dek = null where id = auth.uid()$$, 'remove recovery key');
select pg_temp.expect_error($$update public.profiles set key_version = 1 where id = auth.uid()$$, 'downgrade');
select pg_temp.expect_error($$update public.profiles set legacy_dek = false where id = auth.uid()$$, 'clear legacy flag');
select pg_temp.expect_error($$insert into public.profile_key_history (user_id) values (auth.uid())$$, 'client writes history');
select pg_temp.expect_error(
  $$insert into public.profiles (id, key_version, kdf_salt, kdf_params, wrapped_dek, recovery_wrapped_dek)
    values (auth.uid(), 2, '\x01', '{}', null, '\x0b')
    on conflict (id) do update set wrapped_dek = excluded.wrapped_dek$$,
  'upsert removing wrapped_dek');

-- A password change is allowed, kept in history, and can't undo the switch.
update public.profiles set wrapped_dek = '\x0c', auth_upgraded_at = null where id = auth.uid();
update public.profiles set updated_at = now() where id = auth.uid();
do $$ begin
  assert (select auth_upgraded_at is not null from public.profiles where id = auth.uid()), 'switch kept';
  assert (select count(*) from public.profile_key_history) = 1, 'one history row';
  assert (select wrapped_dek from public.profile_key_history) = '\x0a', 'old wrapping kept';
end $$;

-- Another user sees no history and can't change this row.
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
update public.profiles set wrapped_dek = '\x0d' where id = '00000000-0000-0000-0000-00000000000a';
do $$ begin
  assert (select count(*) from public.profile_key_history) = 0, 'history is private';
end $$;
reset role;
do $$ begin
  assert (select wrapped_dek from public.profiles where id = '00000000-0000-0000-0000-00000000000a') = '\x0c', 'untouched';
  for i in 1..60 loop
    update public.profiles set wrapped_dek = int4send(i) where id = '00000000-0000-0000-0000-00000000000a';
  end loop;
  assert (select count(*) from public.profile_key_history) = 50, 'capped at 50';
end $$;

delete from auth.users where id = '00000000-0000-0000-0000-00000000000a';
do $$ begin
  assert (select count(*) from public.profile_key_history) = 0, 'cascades with the user';
end $$;

\echo key_guard_test: all checks passed
