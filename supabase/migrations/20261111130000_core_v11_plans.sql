-- zero_trust_core v0.11 (Z25, part 1): plans and what each one allows.
--
-- Groundwork only: no payment provider, no prices. Every account stays on
-- the free plan, whose limits are exactly today's defaults, so nothing
-- changes for anyone until a paid plan is added and someone is put on it.
--
-- Additive: two new tables and new functions; zt_storage_limits_for (Z17)
-- is replaced with a version that also looks at the account's plan. No
-- existing row, column, policy or trigger is changed.
--
-- Who writes what:
--   zt_plans          the project owner (SQL editor). Everyone may read it.
--   zt_subscriptions  the project owner, or later a billing webhook (an edge
--                     function using the service role). Clients only read
--                     their own rows.
-- Payment details never reach this database: a row holds the store or
-- provider's opaque reference (an order id or customer id), never a card,
-- name or address.

-- 1. Plans --------------------------------------------------------------------

create table if not exists public.zt_plans (
  id                   text        primary key check (id ~ '^[a-z][a-z0-9_]{1,31}$'),
  -- Higher wins when an account has more than one active subscription.
  rank                 int         not null unique,
  -- Shown in the apps: {"en": "Plus", "he": "פלוס"}. Free has its own
  -- translated name in the apps, so this may stay empty for it.
  names                jsonb       not null default '{}'::jsonb,
  max_item_bytes       bigint      not null check (max_item_bytes > 0),
  max_items            bigint      not null check (max_items > 0),
  max_attachment_bytes bigint      not null check (max_attachment_bytes >= 0),
  -- Feature switches beyond storage, checked with zt_has_feature():
  -- e.g. 'drive', 'vpn', 'mail', 'family'. Free has none.
  features             text[]      not null default '{}',
  -- A retired plan keeps working for those already on it but is no longer
  -- offered.
  offered              boolean     not null default true,
  created_at           timestamptz not null default now()
);
alter table public.zt_plans enable row level security;
-- The catalogue is public: the apps and the website list it before sign-in.
create policy zt_plans_read on public.zt_plans
  for select to anon, authenticated using (true);
revoke insert, update, delete, truncate on public.zt_plans from anon, authenticated;

-- Free = the Z17 defaults: 50 MiB and 100,000 items of synced data, 500 MiB
-- of attachments.
insert into public.zt_plans (id, rank, max_item_bytes, max_items, max_attachment_bytes)
values ('free', 0, 52428800, 100000, 524288000)
on conflict (id) do nothing;

-- 2. Subscriptions ------------------------------------------------------------

create table if not exists public.zt_subscriptions (
  id                 uuid        primary key default gen_random_uuid(),
  user_id            uuid        not null references auth.users(id) on delete cascade,
  plan_id            text        not null references public.zt_plans(id),
  -- Where it was bought. 'manual' = given by the project owner (beta
  -- testers, family, refunds), no payment involved.
  source             text        not null check (source in
                       ('manual', 'google_play', 'app_store', 'web')),
  -- active   paid and current
  -- grace    a renewal payment failed; the store is retrying and the user
  --          keeps the plan meanwhile (Play's "grace period")
  -- on_hold  retries ran out; plan paused until the user fixes payment
  -- canceled will not renew; keeps the plan until current_period_end
  -- expired  over
  status             text        not null default 'active' check (status in
                       ('active', 'grace', 'on_hold', 'canceled', 'expired')),
  -- The store's or provider's reference (Play purchase token hash, App
  -- Store original transaction id, web provider subscription id). Null for
  -- manual grants.
  provider_ref       text,
  -- When the paid period ends. Null = no end (manual lifetime grant).
  current_period_end timestamptz,
  note               text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (source, provider_ref)
);
create index if not exists zt_subscriptions_user on public.zt_subscriptions (user_id);
alter table public.zt_subscriptions enable row level security;
create policy zt_subscriptions_owner_read on public.zt_subscriptions
  for select to authenticated using ((select auth.uid()) = user_id);
revoke insert, update, delete, truncate on public.zt_subscriptions from anon, authenticated;

-- The plan an account is on now: its highest-ranked subscription that
-- still counts, else free. Runs as the caller, so a signed-in user only
-- sees their own subscriptions (RLS); asking about anyone else gives free.
-- A few days of slack after current_period_end covers store renewals that
-- arrive late, so nobody drops to free overnight while a renewal is
-- processed.
create or replace function public.zt_plan_for(p_user uuid)
returns text language sql stable set search_path = '' as $$
  select coalesce(
    (select p.id
       from public.zt_subscriptions s
       join public.zt_plans p on p.id = s.plan_id
      where s.user_id = p_user
        and s.status in ('active', 'grace', 'canceled')
        and (s.current_period_end is null
             or s.current_period_end + interval '3 days' > now())
      order by p.rank desc
      limit 1),
    'free');
$$;
revoke execute on function public.zt_plan_for(uuid) from public, anon;
grant execute on function public.zt_plan_for(uuid) to authenticated;

-- 3. Limits now follow the plan ------------------------------------------------

-- Same columns as before (Z17). Order: a per-account override in
-- zt_storage_limits, then the account's plan, then the free plan. The
-- per-item cap stays 1 MiB on every plan (it protects sync, not storage).
create or replace function public.zt_storage_limits_for(p_user uuid)
returns table (max_blob_bytes bigint, max_item_bytes bigint, max_items bigint,
               max_attachment_bytes bigint)
language sql stable set search_path = '' as $$
  select 1048576::bigint,
         coalesce(l.max_item_bytes, p.max_item_bytes, 52428800),
         coalesce(l.max_items, p.max_items, 100000),
         coalesce(l.max_attachment_bytes, p.max_attachment_bytes, 524288000)
  from (select 1) d
  left join public.zt_plans p on p.id = public.zt_plan_for(p_user)
  left join public.zt_storage_limits l on l.user_id = p_user;
$$;
revoke execute on function public.zt_storage_limits_for(uuid) from public, anon;
grant execute on function public.zt_storage_limits_for(uuid) to authenticated;

-- 4. What the apps read -------------------------------------------------------

-- Whether the caller's plan includes a feature ('drive', 'vpn', ...). For
-- server-side checks in later features' policies and edge functions.
create or replace function public.zt_has_feature(p_feature text)
returns boolean language sql stable set search_path = '' as $$
  select coalesce(
    (select p_feature = any (p.features)
       from public.zt_plans p
      where p.id = public.zt_plan_for((select auth.uid()))),
    false);
$$;
revoke execute on function public.zt_has_feature(text) from public, anon;
grant execute on function public.zt_has_feature(text) to authenticated;

-- For the app's "Plan" row: the caller's plan, its names and features, and
-- the subscription behind it (if any). Null when signed out.
create or replace function public.zt_my_plan()
returns json language sql stable set search_path = '' as $$
  with me as (select (select auth.uid()) as uid),
  plan as (select p.* from public.zt_plans p, me where p.id = public.zt_plan_for(me.uid)),
  sub as (
    select s.* from public.zt_subscriptions s, me, plan
     where s.user_id = me.uid and s.plan_id = plan.id
       and s.status in ('active', 'grace', 'canceled')
       and (s.current_period_end is null
            or s.current_period_end + interval '3 days' > now())
     order by s.current_period_end desc nulls first
     limit 1)
  select json_build_object(
    'plan',               plan.id,
    'names',              plan.names,
    'features',           to_json(plan.features),
    'status',             (select status from sub),
    'source',             (select source from sub),
    'current_period_end', (select current_period_end from sub))
  from plan, me
  where me.uid is not null;
$$;
revoke execute on function public.zt_my_plan() from public, anon;
grant execute on function public.zt_my_plan() to authenticated;

-- 5. Owner tools (SQL editor only) --------------------------------------------

-- Put an account on a plan by hand (beta testers, family, support), e.g.
--   select public.zt_grant_plan('<user id>', 'plus', now() + interval '1 year', 'beta tester');
-- Null p_until = no end. Replaces any earlier manual grant for that account.
create or replace function public.zt_grant_plan(
  p_user uuid, p_plan text, p_until timestamptz default null, p_note text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from public.zt_subscriptions where user_id = p_user and source = 'manual';
  if p_plan <> 'free' then
    insert into public.zt_subscriptions (user_id, plan_id, source, current_period_end, note)
    values (p_user, p_plan, 'manual', p_until, p_note);
  end if;
end;
$$;
revoke execute on function public.zt_grant_plan(uuid, text, timestamptz, text)
  from public, anon, authenticated;
