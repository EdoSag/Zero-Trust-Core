-- Z22: account deletion waits 7 days and can be undone.
\set ON_ERROR_STOP 1
insert into auth.users values ('00000000-0000-0000-0000-0000000de101', 'del1@x.com'),
                              ('00000000-0000-0000-0000-0000000de102', 'del2@x.com');

do $$
declare
  v_first timestamptz;
begin
  v_first := public.zt_schedule_account_deletion('00000000-0000-0000-0000-0000000de101', '\x01');
  assert v_first between now() + interval '7 days' - interval '1 minute'
                     and now() + interval '7 days' + interval '1 minute', '7 days out';
  -- Asking again keeps the date and replaces the undo token.
  assert public.zt_schedule_account_deletion('00000000-0000-0000-0000-0000000de101', '\x02') = v_first,
    'asking again never postpones it';
  assert not public.zt_cancel_account_deletion_by_token('\x01'), 'the old link stops working';
  assert (select count(*) from public.zt_due_account_deletions()) = 0, 'nothing due yet';
  begin
    perform public.zt_schedule_account_deletion('00000000-0000-0000-0000-0000000de102', '\x03', 0);
    assert false, '0 days accepted';
  exception when raise_exception then null;
  end;
end $$;

-- The person sees their own row (date only) and can keep the account.
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000de102';
do $$ begin
  assert (select count(*) from public.zt_account_deletions) = 0, 'others'' rows hidden';
  assert not public.zt_cancel_account_deletion(), 'nothing to cancel';
  begin
    perform undo_token_hash from public.zt_account_deletions;
    assert false, 'token hash readable';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.zt_schedule_account_deletion('00000000-0000-0000-0000-0000000de102', '\x04');
    assert false, 'users can schedule directly';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.zt_due_account_deletions();
    assert false, 'users can list due deletions';
  exception when insufficient_privilege then null;
  end;
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000de101';
do $$ begin
  assert (select count(*) from public.zt_account_deletions) = 1, 'own row visible';
  assert (select delete_after from public.zt_account_deletions) > now(), 'with its date';
  assert public.zt_cancel_account_deletion(), 'kept';
  assert (select count(*) from public.zt_account_deletions) = 0, 'gone';
end $$;
reset role;
reset request.jwt.claim.sub;

-- The email link works once; due rows are listed; the purge secret check
-- fails closed without Vault.
do $$ begin
  perform public.zt_schedule_account_deletion('00000000-0000-0000-0000-0000000de102', '\x05');
  assert public.zt_cancel_account_deletion_by_token('\x05'), 'link keeps the account';
  assert not public.zt_cancel_account_deletion_by_token('\x05'), 'only once';
  perform public.zt_schedule_account_deletion('00000000-0000-0000-0000-0000000de102', '\x06');
  update public.zt_account_deletions set delete_after = now() - interval '1 hour';
  assert (select array_agg(u) from public.zt_due_account_deletions() u)
    = array['00000000-0000-0000-0000-0000000de102'::uuid], 'due';
  assert not public.zt_check_account_purge_secret(repeat('x', 40)), 'no Vault, no purge';
  perform public.zt_request_account_purge(); -- warns, does nothing
  -- Deleting the auth user (what the function does) removes the row.
  delete from auth.users where id = '00000000-0000-0000-0000-0000000de102';
  assert (select count(*) from public.zt_account_deletions) = 0, 'cascades';
end $$;
delete from auth.users where id = '00000000-0000-0000-0000-0000000de101';

\echo account_deletion_test: all checks passed
