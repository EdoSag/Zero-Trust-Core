-- Calendar Planner, phase R7: the optional AI helper (design:
-- reports/zt-planner-design.md, section 8). OFF until the owner switches
-- it on: `enabled` starts false and the edge function also needs the
-- ANTHROPIC_API_KEY secret.
--
-- Only counts are stored (requests, tokens, cost), never text. The phone
-- sends the text to the `planner-ai` edge function, which checks the plan,
-- the user's monthly limit and the project's monthly budget here, forwards
-- the request and records the counts.

-- One row of settings, read and written by the owner only (SQL editor).
create table if not exists public.zt_ai_config (
  id boolean primary key default true check (id),
  enabled boolean not null default false,
  -- Requests per user per calendar month (UTC).
  monthly_limit int not null default 300 check (monthly_limit >= 0),
  -- Total spend for all users per calendar month, in US dollars; at or
  -- above it every request is refused until the next month.
  monthly_budget_usd numeric(10, 2) not null default 20 check (monthly_budget_usd >= 0),
  -- Prices of the model in use, US dollars per million tokens.
  input_usd_per_mtok numeric(10, 4) not null default 0.10,
  output_usd_per_mtok numeric(10, 4) not null default 0.50
);
insert into public.zt_ai_config (id) values (true) on conflict (id) do nothing;
alter table public.zt_ai_config enable row level security;
revoke all on public.zt_ai_config from anon, authenticated;

-- Per user and month: how many requests, tokens and dollars. No text.
create table if not exists public.zt_ai_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  month date not null,
  requests int not null default 0,
  input_tokens bigint not null default 0,
  output_tokens bigint not null default 0,
  cost_usd numeric(12, 6) not null default 0,
  primary key (user_id, month)
);
alter table public.zt_ai_usage enable row level security;
revoke insert, update, delete, truncate on public.zt_ai_usage from anon, authenticated;
drop policy if exists zt_ai_usage_own on public.zt_ai_usage;
create policy zt_ai_usage_own on public.zt_ai_usage
  for select to authenticated using (user_id = (select auth.uid()));
create index if not exists zt_ai_usage_month on public.zt_ai_usage (month);

-- What the app shows: whether the helper is available to this account and
-- how much of the month's allowance is used. The app hides every AI
-- control unless `available` is true.
create or replace function public.zt_planner_ai_status()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'available', c.enabled and coalesce(
      (select 'planner' = any (p.features) or '*' = any (p.features)
         from public.zt_plans p
        where p.id = public.zt_plan_for((select auth.uid()))), false),
    'used', coalesce(
      (select u.requests from public.zt_ai_usage u
        where u.user_id = (select auth.uid())
          and u.month = date_trunc('month', now() at time zone 'utc')::date), 0),
    'limit', c.monthly_limit)
  from public.zt_ai_config c;
$$;
revoke execute on function public.zt_planner_ai_status() from public, anon;
grant execute on function public.zt_planner_ai_status() to authenticated;

-- Takes one request for [p_user] if allowed: 'ok', or why not ('off',
-- 'no_plan', 'limit', 'budget'). Counts the request at once, so parallel
-- calls can't pass the limit. Edge function only.
create or replace function public.zt_ai_take_request(p_user uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  c public.zt_ai_config;
  v_month date := date_trunc('month', now() at time zone 'utc')::date;
  v_used int;
begin
  select * into c from public.zt_ai_config where id;
  if c is null or not c.enabled then return 'off'; end if;
  if c.monthly_limit <= 0 then return 'limit'; end if;
  if not coalesce(
      (select 'planner' = any (p.features) or '*' = any (p.features)
         from public.zt_plans p where p.id = public.zt_plan_for(p_user)), false) then
    return 'no_plan';
  end if;
  if (select coalesce(sum(cost_usd), 0) from public.zt_ai_usage where month = v_month)
      >= c.monthly_budget_usd then
    return 'budget';
  end if;
  insert into public.zt_ai_usage as u (user_id, month, requests)
  values (p_user, v_month, 1)
  on conflict (user_id, month) do update set requests = u.requests + 1
    where u.requests < c.monthly_limit
  returning requests into v_used;
  if v_used is null then return 'limit'; end if;
  return 'ok';
end;
$$;
revoke execute on function public.zt_ai_take_request(uuid) from public, anon, authenticated;
grant execute on function public.zt_ai_take_request(uuid) to service_role;

-- Records the tokens a request used, priced with the config. Edge function only.
create or replace function public.zt_ai_record_tokens(p_user uuid, p_input bigint, p_output bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare
  c public.zt_ai_config;
begin
  select * into c from public.zt_ai_config where id;
  update public.zt_ai_usage
     set input_tokens = input_tokens + greatest(p_input, 0),
         output_tokens = output_tokens + greatest(p_output, 0),
         cost_usd = cost_usd
           + greatest(p_input, 0) * c.input_usd_per_mtok / 1000000
           + greatest(p_output, 0) * c.output_usd_per_mtok / 1000000
   where user_id = p_user
     and month = date_trunc('month', now() at time zone 'utc')::date;
end;
$$;
revoke execute on function public.zt_ai_record_tokens(uuid, bigint, bigint) from public, anon, authenticated;
grant execute on function public.zt_ai_record_tokens(uuid, bigint, bigint) to service_role;
