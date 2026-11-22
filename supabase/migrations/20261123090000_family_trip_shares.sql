-- ZT Family (L-1): "Share my trip" links.
--
-- A member can share where they are for a limited time (an hour by default)
-- with anyone, by a link like https://zerotrust.bz/trip/#<id>.<key>.
-- The phone seals each update with AES-256-GCM under <key>, which is only
-- in the link after the #, so browsers never send it to a server. This
-- table holds the sealed text and when it stops being shown; the server
-- can't read where anyone is.
--
-- Anyone with the link reads the row through family_trip_get(id), which
-- returns nothing once the share has ended. Nobody can list rows. Expired
-- rows are deleted every 10 minutes, and a row goes with its account.
--
-- Safe to run again.

-- 1. Table --------------------------------------------------------------------

create table if not exists public.family_trip_shares (
  -- 16 random bytes, base64url without padding.
  id          text        primary key check (id ~ '^[A-Za-z0-9_-]{22}$'),
  owner       uuid        not null default auth.uid()
                          references auth.users (id) on delete cascade,
  payload     text        not null check (length(payload) between 1 and 4096),
  expires_at  timestamptz not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists family_trip_shares_owner
  on public.family_trip_shares (owner);
create index if not exists family_trip_shares_expires
  on public.family_trip_shares (expires_at);

-- 2. Who may do what ----------------------------------------------------------

alter table public.family_trip_shares enable row level security;

drop policy if exists family_trip_own_read on public.family_trip_shares;
create policy family_trip_own_read on public.family_trip_shares
  for select to authenticated using ((select auth.uid()) = owner);
drop policy if exists family_trip_own_insert on public.family_trip_shares;
create policy family_trip_own_insert on public.family_trip_shares
  for insert to authenticated with check ((select auth.uid()) = owner);
drop policy if exists family_trip_own_update on public.family_trip_shares;
create policy family_trip_own_update on public.family_trip_shares
  for update to authenticated
  using ((select auth.uid()) = owner)
  with check ((select auth.uid()) = owner);
drop policy if exists family_trip_own_delete on public.family_trip_shares;
create policy family_trip_own_delete on public.family_trip_shares
  for delete to authenticated using ((select auth.uid()) = owner);

revoke all on public.family_trip_shares from anon;
revoke truncate, references, trigger on public.family_trip_shares from authenticated;

-- 3. Server-side rules on every write ----------------------------------------

-- The owner and times are the server's. A share lasts at most 4 hours from
-- when it started, and an account has at most 3 running at once.
create or replace function public.family_trip_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_running bigint;
begin
  if (select auth.uid()) is not null then
    new.owner := (select auth.uid());
  end if;
  if tg_op = 'INSERT' then
    new.created_at := now();
    perform pg_advisory_xact_lock(
      hashtextextended('family_trip:' || new.owner::text, 0));
    select count(*) into v_running from public.family_trip_shares t
     where t.owner = new.owner and t.expires_at > now();
    if v_running >= 3 then
      raise exception 'family_too_many_trips' using errcode = 'P0001';
    end if;
  else
    if new.id <> old.id or new.owner <> old.owner then
      raise exception 'family_trip_moved' using errcode = 'P0001';
    end if;
    new.created_at := old.created_at;
    -- An ended share stays ended.
    if old.expires_at <= now() then
      raise exception 'family_trip_ended' using errcode = 'P0001';
    end if;
  end if;
  if new.expires_at <= now() then
    raise exception 'family_trip_ended' using errcode = 'P0001';
  end if;
  if new.expires_at > new.created_at + interval '4 hours' then
    new.expires_at := new.created_at + interval '4 hours';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
revoke execute on function public.family_trip_guard() from public, anon, authenticated;

drop trigger if exists family_trip_guard on public.family_trip_shares;
create trigger family_trip_guard
  before insert or update on public.family_trip_shares
  for each row execute function public.family_trip_guard();

-- 4. Reading a share by its link -----------------------------------------------

-- The trip page (zerotrust.bz/trip/) calls this with the id from the link.
-- Returns no row for an unknown or ended share.
create or replace function public.family_trip_get(p_id text)
returns table (payload text, expires_at timestamptz, updated_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select t.payload, t.expires_at, t.updated_at
    from public.family_trip_shares t
   where t.id = p_id and t.expires_at > now();
$$;
revoke execute on function public.family_trip_get(text) from public;
grant execute on function public.family_trip_get(text) to anon, authenticated;

-- 5. Cleanup ------------------------------------------------------------------

create or replace function public.family_purge_trips()
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  v_gone bigint;
begin
  delete from public.family_trip_shares where expires_at <= now();
  get diagnostics v_gone = row_count;
  return v_gone;
end;
$$;
revoke execute on function public.family_purge_trips() from public, anon, authenticated;

-- Every 10 minutes, where pg_cron is available (it is on Supabase).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('family-purge-trips', '*/10 * * * *',
                          'select public.family_purge_trips()');
  end if;
end $$;
