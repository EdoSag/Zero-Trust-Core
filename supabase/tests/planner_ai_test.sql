-- Runs after 00_supabase_stub.sql and every migration. R7: AI helper
-- counts, limits and the off switch.
create function pg_temp.ai_expect_error(stmt text, msg text) returns void
language plpgsql as $$
begin
  execute stmt;
  raise exception 'expected failure: %', msg;
exception when others then
  if sqlerrm like 'expected failure:%' then raise; end if;
end $$;

create function pg_temp.ai_month() returns date language sql as
  $$ select date_trunc('month', now() at time zone 'utc')::date $$;

insert into auth.users values ('00000000-0000-0000-0000-00000000ae01', 'ai@x.com'),
                              ('00000000-0000-0000-0000-00000000ae02', 'noai@x.com');
insert into public.zt_plans (id, rank, names, max_item_bytes, max_items, max_attachment_bytes, features)
values ('taiplan', 70, '{"en": "AI test"}', 1000, 50, 5000, '{planner}');
select public.zt_grant_plan('00000000-0000-0000-0000-00000000ae01', 'taiplan', null, 'test');

-- Off by default: nothing is available and every request is refused.
do $$ begin
  assert (select not enabled and monthly_limit = 300 and monthly_budget_usd = 20 from public.zt_ai_config),
    'off by default, 300 a month, $20 budget';
  assert public.zt_ai_take_request('00000000-0000-0000-0000-00000000ae01', pg_temp.ai_month()) = 'off', 'off refuses';
  assert (select count(*) from public.zt_ai_usage) = 0, 'nothing counted while off';
end $$;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000ae01';
do $$ begin
  assert (public.zt_planner_ai_status() ->> 'available')::boolean = false, 'hidden while off';
end $$;
-- Users can't switch it on, read the config, write usage or take requests.
select pg_temp.ai_expect_error($$update public.zt_ai_config set enabled = true$$, 'user switches it on');
select pg_temp.ai_expect_error($$select * from public.zt_ai_config$$, 'user reads config');
select pg_temp.ai_expect_error($$insert into public.zt_ai_usage (user_id, month) values (auth.uid(), '2026-01-01')$$, 'user writes usage');
select pg_temp.ai_expect_error($$select public.zt_ai_take_request(auth.uid(), '2026-11-01')$$, 'user takes a request');
select pg_temp.ai_expect_error($$select public.zt_ai_record_tokens(auth.uid(), '2026-11-01', 1, 1)$$, 'user records tokens');
reset role;

-- On, with a limit of 2.
update public.zt_ai_config set enabled = true, monthly_limit = 2;
do $$ begin
  assert public.zt_ai_take_request('00000000-0000-0000-0000-00000000ae02', pg_temp.ai_month()) = 'no_plan', 'free plan refused';
  assert public.zt_ai_take_request('00000000-0000-0000-0000-00000000ae01', pg_temp.ai_month()) = 'ok', 'first';
  perform public.zt_ai_record_tokens('00000000-0000-0000-0000-00000000ae01', pg_temp.ai_month(), 2000, 400);
  assert public.zt_ai_take_request('00000000-0000-0000-0000-00000000ae01', pg_temp.ai_month()) = 'ok', 'second';
  assert public.zt_ai_take_request('00000000-0000-0000-0000-00000000ae01', pg_temp.ai_month()) = 'limit', 'third is over the limit';
  -- The first is recorded at its real cost; the second still holds the
  -- reserve until its tokens come in.
  assert (select requests = 2 and input_tokens = 2000 and output_tokens = 400
            and cost_usd = 2000 * 0.10 / 1000000 + 400 * 0.50 / 1000000 + 0.005
            from public.zt_ai_usage where user_id = '00000000-0000-0000-0000-00000000ae01'),
    'counts, cost and the hold recorded';
  -- The second never reached the model: zeros release its hold.
  perform public.zt_ai_record_tokens('00000000-0000-0000-0000-00000000ae01', pg_temp.ai_month(), 0, 0);
  assert (select cost_usd = 2000 * 0.10 / 1000000 + 400 * 0.50 / 1000000
            from public.zt_ai_usage where user_id = '00000000-0000-0000-0000-00000000ae01'),
    'the hold released';
  -- Tokens of a request taken last month go to last month, not this one.
  insert into public.zt_ai_usage (user_id, month, requests, cost_usd)
  values ('00000000-0000-0000-0000-00000000ae01', '2026-01-01', 1, 0.005);
  perform public.zt_ai_record_tokens('00000000-0000-0000-0000-00000000ae01', '2026-01-01', 1000, 0);
  assert (select input_tokens = 1000 and cost_usd = 1000 * 0.10 / 1000000
            from public.zt_ai_usage
           where user_id = '00000000-0000-0000-0000-00000000ae01' and month = '2026-01-01'),
    'recorded in the month it was taken';
  assert (select input_tokens = 2000 from public.zt_ai_usage
           where user_id = '00000000-0000-0000-0000-00000000ae01' and month = pg_temp.ai_month()),
    'this month untouched';
  delete from public.zt_ai_usage where month = '2026-01-01';
end $$;

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000ae01';
do $$ begin
  assert (public.zt_planner_ai_status() ->> 'available')::boolean, 'available with the feature';
  assert (public.zt_planner_ai_status() ->> 'used')::int = 2, 'used this month';
  assert (public.zt_planner_ai_status() ->> 'limit')::int = 2, 'limit shown';
  assert (select count(*) from public.zt_ai_usage) = 1, 'own usage readable';
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000ae02';
do $$ begin
  assert (public.zt_planner_ai_status() ->> 'available')::boolean = false, 'not on the free plan';
  assert (select count(*) from public.zt_ai_usage) = 0, 'others'' usage hidden';
end $$;
reset role;

-- The month's budget stops everyone, counting what running requests hold:
-- with room for exactly two holds, a third request waits for real costs.
delete from public.zt_ai_usage;
update public.zt_ai_config set monthly_limit = 300, monthly_budget_usd = 0.01;
do $$ begin
  assert public.zt_ai_take_request('00000000-0000-0000-0000-00000000ae01', pg_temp.ai_month()) = 'ok', 'first hold';
  assert public.zt_ai_take_request('00000000-0000-0000-0000-00000000ae01', pg_temp.ai_month()) = 'ok', 'second hold';
  assert public.zt_ai_take_request('00000000-0000-0000-0000-00000000ae01', pg_temp.ai_month()) = 'budget',
    'running requests count against the budget';
  perform pg_temp.ai_expect_error(
    $q$select public.zt_ai_take_request('00000000-0000-0000-0000-00000000ae01', '2026-11-15')$q$,
    'a month must start on its first day');
end $$;
update public.zt_ai_config set enabled = false, monthly_limit = 300, monthly_budget_usd = 20;
delete from public.zt_ai_usage;
select public.zt_grant_plan('00000000-0000-0000-0000-00000000ae01', 'free');

\echo planner_ai_test: all checks passed
