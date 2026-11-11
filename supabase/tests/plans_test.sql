-- Runs after 00_supabase_stub.sql and every migration. Z25 plans.
create function pg_temp.plans_expect_error(stmt text, msg text) returns void
language plpgsql as $$
begin
  execute stmt;
  raise exception 'expected failure: %', msg;
exception when others then
  if sqlerrm like 'expected failure:%' then raise; end if;
end $$;

insert into auth.users values ('00000000-0000-0000-0000-0000000000f1', 'paid@x.com'),
                              ('00000000-0000-0000-0000-0000000000f2', 'free@x.com');
insert into public.zt_plans (id, rank, names, max_item_bytes, max_items, max_attachment_bytes, features)
values ('plus', 10, '{"en": "Plus", "he": "פלוס"}', 120, 5, 1000, '{drive}'),
       ('max', 20, '{"en": "Max"}', 500, 50, 5000, '{drive,vpn}');

-- f1 has an expired Max and a current Plus: Plus counts.
insert into public.zt_subscriptions (user_id, plan_id, source, status, provider_ref, current_period_end)
values ('00000000-0000-0000-0000-0000000000f1', 'max', 'google_play', 'expired', 'tok1', now() - interval '10 days'),
       ('00000000-0000-0000-0000-0000000000f1', 'plus', 'web', 'active', 'sub_1', now() + interval '20 days');

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f1';
do $$ begin
  assert public.zt_plan_for(auth.uid()) = 'plus', 'current plan wins over expired';
  assert (select max_item_bytes from public.zt_storage_limits_for(auth.uid())) = 120, 'plan limit';
  assert (select max_blob_bytes from public.zt_storage_limits_for(auth.uid())) = 1048576, 'blob cap unchanged';
  assert public.zt_has_feature('drive'), 'plus has drive';
  assert not public.zt_has_feature('vpn'), 'plus has no vpn';
  assert (public.zt_my_plan() ->> 'plan') = 'plus', 'my plan';
  assert (public.zt_my_plan() ->> 'source') = 'web', 'my plan source';
  assert (public.zt_my_plan() -> 'names' ->> 'he') = 'פלוס', 'hebrew name';
  assert (select count(*) from public.zt_plans) = 3, 'catalogue readable';
  -- Someone else's plan can't be read: it looks free.
  assert public.zt_plan_for('00000000-0000-0000-0000-0000000000f2') = 'free', 'other user looks free';
end $$;

-- The plan's limit is enforced by the Z17 trigger.
insert into public.vault_items (user_id, app, item_id, data_blob)
  values (auth.uid(), 'notes', 'p1', decode(repeat('aa', 100), 'hex'));
select pg_temp.plans_expect_error(
  $$insert into public.vault_items (user_id, app, item_id, data_blob)
    values (auth.uid(), 'notes', 'p2', decode(repeat('aa', 30), 'hex'))$$,
  'over plan limit');

-- Clients can't change plans, subscriptions or grant themselves one.
select pg_temp.plans_expect_error($$insert into public.zt_subscriptions (user_id, plan_id, source) values (auth.uid(), 'max', 'manual')$$, 'client subscribes');
select pg_temp.plans_expect_error($$update public.zt_subscriptions set current_period_end = null$$, 'client extends');
select pg_temp.plans_expect_error($$update public.zt_plans set max_items = 1e9$$, 'client edits plan');
select pg_temp.plans_expect_error($$select public.zt_grant_plan(auth.uid(), 'max')$$, 'client grants plan');

-- A per-account override still beats the plan.
reset role;
insert into public.zt_storage_limits (user_id, max_item_bytes)
  values ('00000000-0000-0000-0000-0000000000f1', 10000);
set role authenticated;
do $$ begin
  assert (select max_item_bytes from public.zt_storage_limits_for(auth.uid())) = 10000, 'override wins';
  assert (select max_items from public.zt_storage_limits_for(auth.uid())) = 5, 'rest from plan';
end $$;

-- A lapsed period keeps the plan for 3 days, then free.
reset role;
update public.zt_subscriptions set current_period_end = now() - interval '2 days' where provider_ref = 'sub_1';
set role authenticated;
do $$ begin assert public.zt_plan_for(auth.uid()) = 'plus', 'slack after period end'; end $$;
reset role;
update public.zt_subscriptions set current_period_end = now() - interval '4 days' where provider_ref = 'sub_1';
set role authenticated;
do $$ begin
  assert public.zt_plan_for(auth.uid()) = 'free', 'lapsed drops to free';
  assert (select max_items from public.zt_storage_limits_for(auth.uid())) = 100000, 'free limits';
  assert not public.zt_has_feature('drive'), 'free has no drive';
end $$;

-- On hold: free until fixed.
reset role;
update public.zt_subscriptions set status = 'on_hold', current_period_end = now() + interval '5 days' where provider_ref = 'sub_1';
set role authenticated;
do $$ begin assert public.zt_plan_for(auth.uid()) = 'free', 'on hold is free'; end $$;

-- Owner grants: replace earlier manual grants; free removes them.
reset role;
select public.zt_grant_plan('00000000-0000-0000-0000-0000000000f2', 'plus', null, 'beta');
select public.zt_grant_plan('00000000-0000-0000-0000-0000000000f2', 'max', now() + interval '1 year', 'upgrade');
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f2';
do $$ begin
  assert (select count(*) from public.zt_subscriptions) = 1, 'one manual grant, own rows only';
  assert (public.zt_my_plan() ->> 'plan') = 'max', 'granted plan';
  assert public.zt_has_feature('vpn'), 'max has vpn';
end $$;
reset role;
select public.zt_grant_plan('00000000-0000-0000-0000-0000000000f2', 'free');
set role authenticated;
do $$ begin
  assert (public.zt_my_plan() ->> 'plan') = 'free', 'back to free';
  assert (public.zt_my_plan() ->> 'source') is null, 'no subscription';
end $$;

-- Signed out: nothing.
reset role;
set role anon;
select pg_temp.plans_expect_error($$select public.zt_my_plan()$$, 'anon reads plan');
do $$ begin assert (select count(*) from public.zt_plans) = 3, 'anon reads catalogue'; end $$;
reset role;

-- Deleting an account removes its subscriptions.
delete from auth.users where id = '00000000-0000-0000-0000-0000000000f2';
do $$ begin
  assert not exists (select 1 from public.zt_subscriptions
                      where user_id = '00000000-0000-0000-0000-0000000000f2'), 'cascade';
end $$;
\echo plans_test: all checks passed
