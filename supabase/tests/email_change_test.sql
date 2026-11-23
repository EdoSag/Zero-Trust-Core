-- Z14: the email-change table is the function's only; the in-use check
-- ignores case and spaces and is service-role only.
\set ON_ERROR_STOP 1
insert into auth.users values ('00000000-0000-0000-0000-0000000ec101', 'Taken@X.com');
insert into public.zt_email_changes (user_id, new_email, code_hash, expires_at)
values ('00000000-0000-0000-0000-0000000ec101', 'new@x.com', '\x01', now() - interval '2 days');
do $$ begin
  assert public.zt_email_in_use(' taken@x.COM '), 'case and spaces ignored';
  assert not public.zt_email_in_use('free@x.com'), 'free address';
  assert public.zt_purge_email_changes() = 1, 'old code purged';
end $$;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000ec101';
do $$ begin
  begin
    perform count(*) from public.zt_email_changes;
    assert false, 'users can read email changes';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.zt_email_in_use('taken@x.com');
    assert false, 'users can probe addresses';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
reset request.jwt.claim.sub;
delete from auth.users where id = '00000000-0000-0000-0000-0000000ec101';
\echo email_change_test: all checks passed
