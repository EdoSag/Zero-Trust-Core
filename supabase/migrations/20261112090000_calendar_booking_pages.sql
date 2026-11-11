-- K15: ZT Calendar booking pages ("Book 30 min with Edo").
--
-- Edo chose instant bookings (2026-11-11): the owner's phone uploads busy
-- times (start and end only, never titles) and the server answers visitors
-- and holds a slot at once, like Google's appointment schedules. What the
-- server learns, beyond what it already knew:
--   * each booking page's settings (title, length, working hours, time zone),
--     which visitors see anyway;
--   * when the owner is busy, for the next 60 days;
--   * when bookings start and end.
-- It never sees who booked or why: the visitor's name, email and note are
-- sealed in the browser to the page's public key (P-256 ECDH, HKDF-SHA256,
-- AES-256-GCM) and only the owner's phone holds the private key.
--
-- Visitors are not signed in. They only reach the data through the three
-- security definer functions at the end (granted to anon): read one page's
-- open slots, book one, and see or cancel their own booking with the token
-- they got when booking. The tables themselves are closed to anon.

-- Pages ----------------------------------------------------------------------
create table if not exists public.zt_booking_pages (
  id           text primary key check (id ~ '^[A-Za-z0-9_-]{16,32}$'),
  owner        uuid not null references auth.users(id) on delete cascade,
  title        text not null check (char_length(title) between 1 and 80),
  host_name    text not null default '' check (char_length(host_name) <= 80),
  description  text not null default '' check (char_length(description) <= 500),
  duration_min int  not null check (duration_min between 5 and 480),
  step_min     int  not null default 30 check (step_min in (5, 10, 15, 20, 30, 60)),
  buffer_min   int  not null default 0 check (buffer_min between 0 and 240),
  notice_min   int  not null default 240 check (notice_min between 0 and 43200),
  horizon_days int  not null default 30 check (horizon_days between 1 and 60),
  time_zone    text not null,
  -- {"1": [[540, 1020]], ...}: ISO weekday (1 = Monday) to minute ranges.
  hours        jsonb not null,
  -- Uncompressed P-256 point (65 bytes), standard base64.
  public_key   text not null check (public_key ~ '^[A-Za-z0-9+/]{87}=$'),
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists zt_booking_pages_owner on public.zt_booking_pages (owner);

create or replace function public.zt_booking_pages_guard()
returns trigger language plpgsql set search_path = '' as $$
declare
  v_day text;
  v_ranges jsonb;
begin
  if tg_op = 'UPDATE' and (new.id is distinct from old.id or new.owner is distinct from old.owner) then
    raise exception 'a booking page keeps its id and owner' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' and (select count(*) from public.zt_booking_pages where owner = new.owner) >= 10 then
    raise exception using errcode = 'P0001', message = 'zt_booking_page_limit';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = new.time_zone) then
    raise exception 'unknown time zone %', new.time_zone using errcode = '22023';
  end if;
  if jsonb_typeof(new.hours) <> 'object' then
    raise exception 'hours must be an object' using errcode = '22023';
  end if;
  for v_day, v_ranges in select key, value from jsonb_each(new.hours) loop
    if v_day not in ('1', '2', '3', '4', '5', '6', '7') or jsonb_typeof(v_ranges) <> 'array'
       or jsonb_array_length(v_ranges) > 6
       or exists (select 1 from jsonb_array_elements(v_ranges) r
                  where jsonb_typeof(r) <> 'array' or jsonb_array_length(r) <> 2
                     or jsonb_typeof(r -> 0) <> 'number' or jsonb_typeof(r -> 1) <> 'number'
                     or (r ->> 0)::numeric <> floor((r ->> 0)::numeric)
                     or (r ->> 1)::numeric <> floor((r ->> 1)::numeric)
                     or (r ->> 0)::int < 0 or (r ->> 1)::int > 1440
                     or (r ->> 0)::int >= (r ->> 1)::int) then
      raise exception 'bad hours for day %', v_day using errcode = '22023';
    end if;
  end loop;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists zt_booking_pages_guard on public.zt_booking_pages;
create trigger zt_booking_pages_guard before insert or update on public.zt_booking_pages
  for each row execute function public.zt_booking_pages_guard();

-- Busy times -----------------------------------------------------------------
-- One row per owner: [[start_ms, end_ms], ...] for the next 60 days, replaced
-- whenever the owner's calendar changes. No titles, no calendars.
create table if not exists public.zt_booking_busy (
  owner      uuid primary key references auth.users(id) on delete cascade,
  blocks     jsonb not null default '[]'::jsonb
             check (jsonb_typeof(blocks) = 'array' and jsonb_array_length(blocks) <= 5000),
  updated_at timestamptz not null default now()
);

create or replace function public.zt_booking_busy_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and new.owner is distinct from old.owner then
    raise exception 'busy times keep their owner' using errcode = '42501';
  end if;
  if exists (select 1 from jsonb_array_elements(new.blocks) b
             where jsonb_typeof(b) <> 'array' or jsonb_array_length(b) <> 2
                or jsonb_typeof(b -> 0) <> 'number' or jsonb_typeof(b -> 1) <> 'number'
                or (b ->> 0)::numeric < 0 or (b ->> 0)::numeric >= (b ->> 1)::numeric
                or (b ->> 1)::numeric > 32503680000000) then
    raise exception 'busy blocks are [start_ms, end_ms] pairs' using errcode = '22023';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists zt_booking_busy_guard on public.zt_booking_busy;
create trigger zt_booking_busy_guard before insert or update on public.zt_booking_busy
  for each row execute function public.zt_booking_busy_guard();

-- Bookings -------------------------------------------------------------------
-- status: new (waiting for the owner's phone), added (in the owner's
-- calendar; its busy times now cover it), cancel_requested (the visitor
-- cancelled after it was added; the phone removes the event), cancelled.
create table if not exists public.zt_bookings (
  id          uuid primary key default gen_random_uuid(),
  page_id     text not null references public.zt_booking_pages(id) on delete cascade,
  owner       uuid not null references auth.users(id) on delete cascade,
  starts_at   timestamptz not null,
  ends_at     timestamptz not null,
  status      text not null default 'new'
              check (status in ('new', 'added', 'cancel_requested', 'cancelled')),
  -- The visitor's details, sealed to the page's key. Cleared once the phone
  -- has added the booking.
  sealed      text check (char_length(sealed) <= 8000),
  cancel_hash bytea not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index if not exists zt_bookings_owner_status on public.zt_bookings (owner, status);
create index if not exists zt_bookings_page_start on public.zt_bookings (page_id, starts_at);

-- The owner (through the API) may only move a booking along: new -> added,
-- and cancel it; and may clear the sealed details. Everything else is fixed.
create or replace function public.zt_bookings_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user in ('anon', 'authenticated') then
    if new.id is distinct from old.id or new.page_id is distinct from old.page_id
       or new.owner is distinct from old.owner or new.starts_at is distinct from old.starts_at
       or new.ends_at is distinct from old.ends_at or new.cancel_hash is distinct from old.cancel_hash
       or new.created_at is distinct from old.created_at
       or (new.sealed is not null and new.sealed is distinct from old.sealed) then
      raise exception 'only a booking''s status can change' using errcode = '42501';
    end if;
    if new.status is distinct from old.status and not (
         (old.status = 'new' and new.status in ('added', 'cancelled'))
      or (old.status in ('added', 'cancel_requested') and new.status = 'cancelled')) then
      raise exception 'a booking can''t go from % to %', old.status, new.status using errcode = '42501';
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists zt_bookings_guard on public.zt_bookings;
create trigger zt_bookings_guard before update on public.zt_bookings
  for each row execute function public.zt_bookings_guard();

-- Row level security: owners only. Visitors use the functions below.
alter table public.zt_booking_pages enable row level security;
alter table public.zt_booking_busy enable row level security;
alter table public.zt_bookings enable row level security;

drop policy if exists zt_booking_pages_own on public.zt_booking_pages;
create policy zt_booking_pages_own on public.zt_booking_pages for all to authenticated
  using (owner = (select auth.uid())) with check (owner = (select auth.uid()));
drop policy if exists zt_booking_busy_own on public.zt_booking_busy;
create policy zt_booking_busy_own on public.zt_booking_busy for all to authenticated
  using (owner = (select auth.uid())) with check (owner = (select auth.uid()));
drop policy if exists zt_bookings_own_read on public.zt_bookings;
create policy zt_bookings_own_read on public.zt_bookings for select to authenticated
  using (owner = (select auth.uid()));
drop policy if exists zt_bookings_own_update on public.zt_bookings;
create policy zt_bookings_own_update on public.zt_bookings for update to authenticated
  using (owner = (select auth.uid())) with check (owner = (select auth.uid()));
drop policy if exists zt_bookings_own_delete on public.zt_bookings;
create policy zt_bookings_own_delete on public.zt_bookings for delete to authenticated
  using (owner = (select auth.uid()));

revoke all on public.zt_booking_pages, public.zt_booking_busy, public.zt_bookings from anon;
revoke insert on public.zt_bookings from authenticated;
grant select, insert, update, delete on public.zt_booking_pages, public.zt_booking_busy to authenticated;
grant select, update, delete on public.zt_bookings to authenticated;

-- Open slots -----------------------------------------------------------------
-- Start times of free slots on [p_page]: inside its working hours, at least
-- notice_min from now, within horizon_days and the 60 days the busy times
-- cover, clear of busy times and of bookings the phone hasn't added yet
-- (with buffer_min around each). No busy times uploaded = no slots.
create or replace function public.zt_booking_free_slots(p_page public.zt_booking_pages)
returns setof timestamptz language plpgsql stable security definer set search_path = '' as $$
declare
  v_busy  public.zt_booking_busy;
  v_now   timestamptz := now();
  v_until timestamptz;
  v_today date := (now() at time zone p_page.time_zone)::date;
  v_dur   interval := make_interval(mins => p_page.duration_min);
  v_buf   interval := make_interval(mins => p_page.buffer_min);
begin
  if not p_page.active then return; end if;
  select * into v_busy from public.zt_booking_busy where owner = p_page.owner;
  if not found then return; end if;
  v_until := least(v_now + make_interval(days => p_page.horizon_days),
                   v_busy.updated_at + interval '60 days');
  return query
  with taken as (
    select tstzrange(to_timestamp((b ->> 0)::numeric / 1000), to_timestamp((b ->> 1)::numeric / 1000)) as r
      from jsonb_array_elements(v_busy.blocks) b
     where to_timestamp((b ->> 1)::numeric / 1000) > v_now
    union all
    select tstzrange(k.starts_at, k.ends_at)
      from public.zt_bookings k
     where k.owner = p_page.owner and k.ends_at > v_now
       and (k.status = 'new' or (k.status = 'added' and k.updated_at >= v_busy.updated_at))
  ), candidates as (
    select ((v_today + d) + make_interval(mins => t)) at time zone p_page.time_zone as s
      from generate_series(0, p_page.horizon_days) d,
           jsonb_array_elements(coalesce(p_page.hours -> extract(isodow from v_today + d)::int::text, '[]'::jsonb)) h,
           generate_series((h ->> 0)::int, (h ->> 1)::int - p_page.duration_min, p_page.step_min) t
  )
  select distinct c.s from candidates c
   where c.s >= v_now + make_interval(mins => p_page.notice_min)
     and c.s + v_dur <= v_until
     and not exists (select 1 from taken
                      where taken.r && tstzrange(c.s - v_buf, c.s + v_dur + v_buf))
   order by c.s;
end;
$$;
revoke all on function public.zt_booking_free_slots(public.zt_booking_pages) from public, anon, authenticated;

-- Public: one page and its open slots, or null when there is no such active
-- page. Busy times never leave the server; only free start times do.
create or replace function public.zt_booking_page(p_page text)
returns json language plpgsql stable security definer set search_path = '' as $$
declare
  v_page public.zt_booking_pages;
begin
  select * into v_page from public.zt_booking_pages where id = p_page and active;
  if not found then return null; end if;
  return json_build_object(
    'id', v_page.id, 'title', v_page.title, 'hostName', v_page.host_name,
    'description', v_page.description, 'durationMin', v_page.duration_min,
    'timeZone', v_page.time_zone, 'publicKey', v_page.public_key,
    'slots', coalesce((select json_agg(s order by s) from public.zt_booking_free_slots(v_page) s), '[]'::json));
end;
$$;

-- Public: book [p_start] on [p_page]. [p_sealed] is the visitor's details,
-- sealed in the browser. Returns the booking id and a cancel token, which is
-- shown to the visitor once and only its hash is kept.
create or replace function public.zt_book_slot(p_page text, p_start timestamptz, p_sealed text)
returns json language plpgsql volatile security definer set search_path = '' as $$
declare
  v_page  public.zt_booking_pages;
  v_token text := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  v_id    uuid;
begin
  select * into v_page from public.zt_booking_pages where id = p_page and active;
  if not found then
    raise exception using errcode = 'P0001', message = 'zt_booking_page_gone';
  end if;
  if p_start is null or p_sealed is null or char_length(p_sealed) not between 40 and 8000 then
    raise exception using errcode = 'P0001', message = 'zt_booking_invalid';
  end if;
  -- One booking at a time per owner, so two visitors can't take the same slot.
  perform pg_advisory_xact_lock(hashtextextended('zt_booking:' || v_page.owner::text, 0));
  if (select count(*) from public.zt_bookings
       where page_id = p_page and created_at > now() - interval '1 hour') >= 10
     or (select count(*) from public.zt_bookings
          where owner = v_page.owner and status = 'new') >= 30 then
    raise exception using errcode = 'P0001', message = 'zt_booking_try_later';
  end if;
  if not exists (select 1 from public.zt_booking_free_slots(v_page) s where s = p_start) then
    raise exception using errcode = 'P0001', message = 'zt_booking_slot_taken';
  end if;
  insert into public.zt_bookings (page_id, owner, starts_at, ends_at, sealed, cancel_hash)
  values (p_page, v_page.owner, p_start, p_start + make_interval(mins => v_page.duration_min),
          p_sealed, sha256(convert_to(v_token, 'UTF8')))
  returning id into v_id;
  return json_build_object('id', v_id, 'cancelToken', v_token, 'start', p_start,
    'end', p_start + make_interval(mins => v_page.duration_min));
end;
$$;

-- Public: a visitor's own booking (with the token from booking), and
-- cancelling it. A booking the phone already added becomes cancel_requested;
-- the phone then removes the event.
create or replace function public.zt_booking_status(p_id uuid, p_token text)
returns json language plpgsql stable security definer set search_path = '' as $$
declare
  v_b public.zt_bookings;
  v_title text;
begin
  select * into v_b from public.zt_bookings where id = p_id;
  if not found or p_token is null
     or v_b.cancel_hash is distinct from sha256(convert_to(p_token, 'UTF8')) then
    raise exception using errcode = 'P0001', message = 'zt_booking_invalid';
  end if;
  select title into v_title from public.zt_booking_pages where id = v_b.page_id;
  return json_build_object('id', v_b.id, 'pageId', v_b.page_id, 'title', v_title,
    'start', v_b.starts_at, 'end', v_b.ends_at,
    'cancelled', v_b.status in ('cancelled', 'cancel_requested'));
end;
$$;

create or replace function public.zt_cancel_booking(p_id uuid, p_token text)
returns json language plpgsql volatile security definer set search_path = '' as $$
declare
  v_b public.zt_bookings;
begin
  select * into v_b from public.zt_bookings where id = p_id for update;
  if not found or p_token is null
     or v_b.cancel_hash is distinct from sha256(convert_to(p_token, 'UTF8')) then
    raise exception using errcode = 'P0001', message = 'zt_booking_invalid';
  end if;
  if v_b.starts_at <= now() then
    raise exception using errcode = 'P0001', message = 'zt_booking_past';
  end if;
  update public.zt_bookings
     set status = case status when 'new' then 'cancelled' when 'added' then 'cancel_requested' else status end,
         sealed = case status when 'new' then null else sealed end
   where id = p_id;
  return public.zt_booking_status(p_id, p_token);
end;
$$;

revoke all on function public.zt_booking_page(text) from public;
revoke all on function public.zt_book_slot(text, timestamptz, text) from public;
revoke all on function public.zt_booking_status(uuid, text) from public;
revoke all on function public.zt_cancel_booking(uuid, text) from public;
grant execute on function public.zt_booking_page(text) to anon, authenticated;
grant execute on function public.zt_book_slot(text, timestamptz, text) to anon, authenticated;
grant execute on function public.zt_booking_status(uuid, text) to anon, authenticated;
grant execute on function public.zt_cancel_booking(uuid, text) to anon, authenticated;

-- The owner's phone hears about new bookings at once.
do $$ begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'zt_bookings') then
    alter publication supabase_realtime add table public.zt_bookings;
  end if;
end $$;
