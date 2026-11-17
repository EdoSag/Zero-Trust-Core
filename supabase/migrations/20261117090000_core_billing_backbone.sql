-- zero_trust_core (Z25, part 3): the billing backbone.
--
-- Turns verified store events into the account's plan. No payment provider
-- is connected yet: Google Play and Paddle each get a small edge function
-- later that verifies the store's message and then calls
-- zt_apply_billing_event(). Everything here is additive: three new
-- objects, two new nullable columns on zt_subscriptions, and owner-only
-- functions. Nobody's plan changes.
--
-- Safety rules this file enforces in the database, not in app code:
--   * Only the service role (edge functions) can record payments. Apps can
--     never grant themselves a plan.
--   * Every store event is applied at most once (unique per source and
--     event id), so retried webhooks are harmless.
--   * Events that arrive out of order never move a subscription back in
--     time.
--   * A store subscription belongs to the first account it was linked to.
--     A purchase token replayed from another account is refused and logged.
--   * No card, name, address or email is stored: only the store's opaque
--     references, the product, status and dates.

-- 1. Products --------------------------------------------------------------

-- What can be bought where, and which plan it gives. Public: the apps
-- read it to ask their store for prices.
create table if not exists public.zt_billing_products (
  id                  text        primary key check (id ~ '^[a-z][a-z0-9_]{1,63}$'),
  plan_id             text        not null references public.zt_plans(id),
  source              text        not null check (source in
                        ('google_play', 'app_store', 'web')),
  -- Google Play: '<subscription id>:<base plan id>'. App Store: product id.
  -- Web (Paddle): price id.
  provider_product_id text        not null,
  period              text        not null check (period in ('month', 'year')),
  -- Off until the product exists in the store and should be offered.
  active              boolean     not null default false,
  created_at          timestamptz not null default now(),
  unique (source, provider_product_id)
);
alter table public.zt_billing_products enable row level security;
create policy zt_billing_products_read on public.zt_billing_products
  for select to anon, authenticated using (active);
revoke insert, update, delete, truncate on public.zt_billing_products
  from anon, authenticated;

-- The Google Play subscription to create in Play Console: id `zt_plus`
-- with base plans `monthly` and `yearly`. Off until they exist there.
insert into public.zt_billing_products (id, plan_id, source, provider_product_id, period)
values ('plus_monthly_play', 'plus', 'google_play', 'zt_plus:monthly', 'month'),
       ('plus_yearly_play',  'plus', 'google_play', 'zt_plus:yearly',  'year')
on conflict (id) do nothing;

-- 2. Subscriptions remember what they came from -----------------------------

alter table public.zt_subscriptions
  add column if not exists product_id text references public.zt_billing_products(id),
  -- The store's time for the newest event applied. Older events are ignored.
  add column if not exists provider_updated_at timestamptz;

-- 3. Event log --------------------------------------------------------------

-- Every store message, applied or not, with the outcome. For support,
-- audits and the nightly check. Never readable by apps.
create table if not exists public.zt_billing_events (
  id                bigint      generated always as identity primary key,
  source            text        not null check (source in
                      ('google_play', 'app_store', 'web')),
  -- The store's id for this message (Play: Pub/Sub message id or a
  -- 'verify:' id from the app's purchase check; Paddle: event id).
  provider_event_id text        not null,
  event_type        text        not null,
  provider_ref      text,
  user_id           uuid        references auth.users(id) on delete set null,
  -- When the store says it happened.
  occurred_at       timestamptz not null,
  received_at       timestamptz not null default now(),
  -- applied | duplicate (never stored) | stale | owner_mismatch |
  -- unknown_product | no_user | ignored
  result            text        not null,
  -- Non-personal facts only (product, status, period end, store codes).
  detail            jsonb       not null default '{}'::jsonb,
  unique (source, provider_event_id)
);
create index if not exists zt_billing_events_ref
  on public.zt_billing_events (source, provider_ref);
create index if not exists zt_billing_events_received
  on public.zt_billing_events (received_at);
alter table public.zt_billing_events enable row level security;
revoke all on public.zt_billing_events from anon, authenticated;

-- 4. Applying an event --------------------------------------------------------

-- The one way a paid subscription changes. Called by the billing edge
-- functions with the service role AFTER they verified the message with the
-- store. Returns the outcome (see zt_billing_events.result).
--
-- p_user is the account the purchase is for, when known (the app's own
-- purchase check, or the account id the app attached to the purchase).
-- Store notifications that carry no account update existing rows only.
--
-- Two first events for the same new purchase at the same moment: the second
-- fails on the unique (source, provider_ref) key and rolls back, including
-- its event row, so the store's retry applies it cleanly.
create or replace function public.zt_apply_billing_event(
  p_source      text,
  p_event_id    text,
  p_event_type  text,
  p_occurred_at timestamptz,
  p_provider_ref text,
  p_product     text,
  p_status      text,
  p_period_end  timestamptz,
  p_user        uuid  default null,
  p_detail      jsonb default '{}'::jsonb)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_product public.zt_billing_products;
  v_sub     public.zt_subscriptions;
  v_result  text;
begin
  if p_source is null or p_event_id is null or p_occurred_at is null
     or p_provider_ref is null then
    raise exception 'zt_apply_billing_event: source, event id, time and reference are required';
  end if;

  -- Claim the event first: a retried message stops here.
  insert into public.zt_billing_events
    (source, provider_event_id, event_type, provider_ref, user_id, occurred_at, result, detail)
  values (p_source, p_event_id, coalesce(p_event_type, 'unknown'), p_provider_ref,
          p_user, p_occurred_at, 'pending', coalesce(p_detail, '{}'::jsonb))
  on conflict (source, provider_event_id) do nothing;
  if not found then
    return 'duplicate';
  end if;

  select * into v_sub from public.zt_subscriptions
   where source = p_source and provider_ref = p_provider_ref
   for update;

  if p_status is null or p_status not in
       ('active', 'grace', 'on_hold', 'canceled', 'expired') then
    v_result := 'ignored';
  else
    select * into v_product from public.zt_billing_products
     where source = p_source and provider_product_id = p_product;
    if v_product.id is null then
      v_result := 'unknown_product';
    elsif v_sub.id is not null then
      if p_user is not null and p_user <> v_sub.user_id then
        v_result := 'owner_mismatch';
      elsif v_sub.provider_updated_at is not null
            and p_occurred_at < v_sub.provider_updated_at then
        v_result := 'stale';
      else
        update public.zt_subscriptions
           set plan_id = v_product.plan_id,
               product_id = v_product.id,
               status = p_status,
               current_period_end = p_period_end,
               provider_updated_at = p_occurred_at,
               updated_at = now()
         where id = v_sub.id;
        v_result := 'applied';
      end if;
    elsif p_user is null
          or not exists (select 1 from auth.users where id = p_user) then
      v_result := 'no_user';
    else
      insert into public.zt_subscriptions
        (user_id, plan_id, product_id, source, status, provider_ref,
         current_period_end, provider_updated_at)
      values (p_user, v_product.plan_id, v_product.id, p_source, p_status,
              p_provider_ref, p_period_end, p_occurred_at);
      v_result := 'applied';
    end if;
  end if;

  update public.zt_billing_events
     set result = v_result,
         user_id = case when v_result = 'owner_mismatch' then p_user
                        else coalesce(v_sub.user_id, p_user) end
   where source = p_source and provider_event_id = p_event_id;
  return v_result;
end;
$$;
revoke execute on function public.zt_apply_billing_event(
  text, text, text, timestamptz, text, text, text, timestamptz, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.zt_apply_billing_event(
  text, text, text, timestamptz, text, text, text, timestamptz, uuid, jsonb)
  to service_role;

-- 5. Nightly check ------------------------------------------------------------

-- Store subscriptions to re-check with the store: those near or past their
-- period end, and any not updated for a week. The nightly job asks the
-- store about each and feeds the answer to zt_apply_billing_event, which
-- covers missed or lost webhooks.
create or replace function public.zt_billing_due_for_check(p_limit int default 200)
returns table (subscription_id uuid, source text, provider_ref text, product text)
language sql stable security definer set search_path = '' as $$
  select s.id, s.source, s.provider_ref, p.provider_product_id
    from public.zt_subscriptions s
    left join public.zt_billing_products p on p.id = s.product_id
   where s.source <> 'manual'
     and s.status in ('active', 'grace', 'on_hold', 'canceled')
     and (s.current_period_end is null
          or s.current_period_end < now() + interval '1 day'
          or s.updated_at < now() - interval '7 days')
   order by s.updated_at
   limit greatest(1, least(p_limit, 1000));
$$;
revoke execute on function public.zt_billing_due_for_check(int)
  from public, anon, authenticated;
grant execute on function public.zt_billing_due_for_check(int) to service_role;

-- Marks store subscriptions whose paid time (plus the same 3 days of slack
-- as zt_plan_for) is over as expired. Tidy-up only: zt_plan_for already
-- stops counting them. Manual grants are left to the owner. Returns how
-- many rows changed.
create or replace function public.zt_billing_expire_lapsed()
returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  update public.zt_subscriptions
     set status = 'expired', updated_at = now()
   where source <> 'manual'
     and status in ('active', 'grace', 'on_hold', 'canceled')
     and current_period_end + interval '3 days' < now();
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke execute on function public.zt_billing_expire_lapsed()
  from public, anon, authenticated;
grant execute on function public.zt_billing_expire_lapsed() to service_role;

-- Deletes event log rows older than 13 months (enough for a yearly
-- renewal and its refund window).
create or replace function public.zt_billing_purge_events()
returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  delete from public.zt_billing_events
   where received_at < now() - interval '13 months';
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke execute on function public.zt_billing_purge_events()
  from public, anon, authenticated;
grant execute on function public.zt_billing_purge_events() to service_role;

-- 6. Owner views (SQL editor) ---------------------------------------------------

-- How many accounts are on each plan, by store and status.
create or replace view public.zt_billing_summary
  with (security_invoker = true) as
  select s.plan_id, s.source, s.status, count(*) as subscriptions
    from public.zt_subscriptions s
   group by s.plan_id, s.source, s.status;
revoke all on public.zt_billing_summary from anon, authenticated;

-- Events that need a human look (refused or unmatched) from the last 30 days.
create or replace view public.zt_billing_problems
  with (security_invoker = true) as
  select e.received_at, e.source, e.event_type, e.result, e.provider_ref,
         e.user_id, e.detail
    from public.zt_billing_events e
   where e.result in ('owner_mismatch', 'unknown_product', 'no_user', 'ignored')
     and e.received_at > now() - interval '30 days'
   order by e.received_at desc;
revoke all on public.zt_billing_problems from anon, authenticated;
