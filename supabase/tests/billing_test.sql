-- Runs after 00_supabase_stub.sql, every migration and plans_test.sql.
-- Z25 billing backbone.
create function pg_temp.billing_expect_error(stmt text, msg text) returns void
language plpgsql as $$
begin
  execute stmt;
  raise exception 'expected failure: %', msg;
exception when others then
  if sqlerrm like 'expected failure:%' then raise; end if;
end $$;

insert into auth.users values ('00000000-0000-0000-0000-0000000000b1', 'buyer@x.com'),
                              ('00000000-0000-0000-0000-0000000000b2', 'other@x.com');
-- A web product for the tests (the seeded Play products start switched off).
insert into public.zt_billing_products (id, plan_id, source, provider_product_id, period, active)
values ('plus_monthly_web', 'plus', 'web', 'pri_test_monthly', 'month', true);

-- Apps can read active products only, and change nothing.
set role anon;
do $$ begin
  assert (select count(*) from public.zt_billing_products) = 1, 'only active products';
  assert (select id from public.zt_billing_products) = 'plus_monthly_web', 'web product visible';
end $$;
reset role;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b1';
select pg_temp.billing_expect_error($$update public.zt_billing_products set active = true$$, 'client edits products');
select pg_temp.billing_expect_error($$select * from public.zt_billing_events$$, 'client reads events');
select pg_temp.billing_expect_error($$select * from public.zt_billing_summary$$, 'client reads summary');
select pg_temp.billing_expect_error(
  $$select public.zt_apply_billing_event('web', 'e0', 'x', now(), 'psub_1', 'pri_test_monthly', 'active', now() + interval '30 days', auth.uid())$$,
  'client applies a payment');
select pg_temp.billing_expect_error($$select * from public.zt_billing_due_for_check()$$, 'client lists due');
select pg_temp.billing_expect_error($$select public.zt_billing_expire_lapsed()$$, 'client expires');
reset role;

-- The service role (edge functions) records a purchase.
set role service_role;
do $$
declare r text;
begin
  r := public.zt_apply_billing_event('web', 'evt_1', 'subscription.created', now() - interval '1 hour',
         'psub_1', 'pri_test_monthly', 'active', now() + interval '30 days',
         '00000000-0000-0000-0000-0000000000b1', '{"price": "pri_test_monthly"}');
  assert r = 'applied', 'first event applied: ' || r;

  -- The same event again (webhook retry) does nothing.
  r := public.zt_apply_billing_event('web', 'evt_1', 'subscription.created', now() - interval '1 hour',
         'psub_1', 'pri_test_monthly', 'canceled', now(), null);
  assert r = 'duplicate', 'retry is a duplicate: ' || r;

  -- An older event arriving late is ignored.
  r := public.zt_apply_billing_event('web', 'evt_0', 'subscription.updated', now() - interval '2 hours',
         'psub_1', 'pri_test_monthly', 'expired', now() - interval '1 day', null);
  assert r = 'stale', 'older event is stale: ' || r;

  -- Someone replays the same subscription for another account.
  r := public.zt_apply_billing_event('web', 'evt_2', 'subscription.updated', now(),
         'psub_1', 'pri_test_monthly', 'active', now() + interval '60 days',
         '00000000-0000-0000-0000-0000000000b2');
  assert r = 'owner_mismatch', 'other account refused: ' || r;

  -- Unknown product and missing account are logged, not applied.
  r := public.zt_apply_billing_event('web', 'evt_3', 'subscription.created', now(),
         'psub_9', 'pri_unknown', 'active', now() + interval '30 days',
         '00000000-0000-0000-0000-0000000000b2');
  assert r = 'unknown_product', 'unknown product: ' || r;
  r := public.zt_apply_billing_event('web', 'evt_4', 'subscription.created', now(),
         'psub_8', 'pri_test_monthly', 'active', now() + interval '30 days', null);
  assert r = 'no_user', 'notification without an account for a new purchase: ' || r;
  r := public.zt_apply_billing_event('web', 'evt_5', 'subscription.paused', now(),
         'psub_1', 'pri_test_monthly', 'weird', null, null);
  assert r = 'ignored', 'unknown status: ' || r;
end $$;
reset role;

do $$ begin
  assert (select count(*) from public.zt_subscriptions where provider_ref = 'psub_1') = 1, 'one row';
  assert (select user_id from public.zt_subscriptions where provider_ref = 'psub_1')
         = '00000000-0000-0000-0000-0000000000b1', 'still the buyer''s';
  assert (select status from public.zt_subscriptions where provider_ref = 'psub_1') = 'active', 'still active';
  assert (select product_id from public.zt_subscriptions where provider_ref = 'psub_1') = 'plus_monthly_web', 'product kept';
  assert (select count(*) from public.zt_billing_events) = 6, 'six events logged (duplicate not stored)';
  assert (select count(*) from public.zt_billing_events where result = 'pending') = 0, 'no pending rows';
  assert (select user_id from public.zt_billing_events where provider_event_id = 'evt_2')
         = '00000000-0000-0000-0000-0000000000b2', 'mismatch logs the other account';
  assert (select count(*) from public.zt_billing_problems) = 4, 'problems view';
  assert (select subscriptions from public.zt_billing_summary
           where plan_id = 'plus' and source = 'web' and status = 'active') = 1, 'summary';
end $$;

-- The buyer now has Plus.
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b1';
do $$ begin
  assert (public.zt_my_plan() ->> 'plan') = 'plus', 'buyer on plus';
  assert (public.zt_my_plan() ->> 'source') = 'web', 'bought on the web';
end $$;
reset role;

-- A cancellation keeps Plus until the period ends; a later renewal applies.
set role service_role;
do $$ begin
  assert public.zt_apply_billing_event('web', 'evt_6', 'subscription.canceled', now() + interval '1 minute',
           'psub_1', 'pri_test_monthly', 'canceled', now() + interval '30 days', null) = 'applied';
end $$;
reset role;
set role authenticated;
do $$ begin assert (public.zt_my_plan() ->> 'status') = 'canceled', 'canceled but still plus'; end $$;
do $$ begin assert (public.zt_my_plan() ->> 'plan') = 'plus', 'plus until period end'; end $$;
reset role;

-- Nightly check: lists subscriptions near their end; expiry tidies up.
update public.zt_subscriptions set current_period_end = now() - interval '5 days', updated_at = now()
 where provider_ref = 'psub_1';
set role service_role;
do $$ begin
  assert (select count(*) from public.zt_billing_due_for_check()) >= 1, 'due for check';
  assert (select provider_ref from public.zt_billing_due_for_check() limit 1) = 'psub_1', 'sub_1 due';
  assert (select product from public.zt_billing_due_for_check() limit 1) = 'pri_test_monthly', 'product for the store call';
  assert public.zt_billing_expire_lapsed() = 1, 'one expired';
  assert (select count(*) from public.zt_billing_due_for_check()) = 0, 'nothing due after expiry';
  assert public.zt_billing_purge_events() = 0, 'recent events kept';
end $$;
reset role;
do $$ begin
  assert (select status from public.zt_subscriptions where provider_ref = 'psub_1') = 'expired', 'expired';
end $$;
set role authenticated;
do $$ begin assert (public.zt_my_plan() ->> 'plan') = 'free', 'back to free'; end $$;
reset role;

-- Manual grants are untouched by expiry.
select public.zt_grant_plan('00000000-0000-0000-0000-0000000000b2', 'plus', now() - interval '10 days', 'old beta');
set role service_role;
do $$ begin assert public.zt_billing_expire_lapsed() = 0, 'manual grant left alone'; end $$;
reset role;

-- Deleting an account keeps its event rows (without the account) and drops
-- its subscriptions.
delete from auth.users where id = '00000000-0000-0000-0000-0000000000b1';
do $$ begin
  assert not exists (select 1 from public.zt_subscriptions where provider_ref = 'psub_1'), 'subscription gone';
  assert (select count(*) from public.zt_billing_events where user_id is not null
           and user_id = '00000000-0000-0000-0000-0000000000b1') = 0, 'events unlinked';
end $$;
\echo billing_test: all checks passed
