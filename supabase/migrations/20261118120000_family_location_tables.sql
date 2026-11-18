-- ZT Family (phase L0): where family members' sealed location updates live.
--
-- A family circle is a shared space (core v10) of app 'family'. Its name,
-- places and settings are ordinary encrypted space items. Location is
-- different: it changes every few minutes, so it gets two narrow tables
-- instead of going through item sync.
--
--   family_latest  one row per member device: the newest update. The map
--                  reads this.
--   family_events  history: location points, arrivals, check-ins, SOS.
--                  Kept for the circle's history window, then deleted.
--
-- The server stores ciphertext only. `payload` is sealed on the phone for
-- the circle's members; `signature` is by the sending device's key, which
-- the circle's encrypted member list vouches for. What the server does
-- know is in the columns: who is in which circle, and when each device
-- sent something.
--
-- Nobody can write in someone else's name: rows are inserted as the
-- signed-in account, `user_id` and `sent_at` are set by the server, and a
-- row goes away with its member (leaving, removal, account deletion) or
-- its circle.

-- 1. Tables -------------------------------------------------------------------

create table if not exists public.family_latest (
  space_id   uuid        not null,
  user_id    uuid        not null,
  device_id  text        not null check (length(device_id) between 1 and 100),
  key_epoch  int         not null check (key_epoch >= 1),
  payload    bytea       not null check (octet_length(payload) between 1 and 2048),
  signature  bytea       not null check (octet_length(signature) between 64 and 80),
  sent_at    timestamptz not null default now(),
  primary key (space_id, user_id, device_id),
  foreign key (space_id, user_id)
    references public.zt_space_members (space_id, user_id) on delete cascade
);

create table if not exists public.family_events (
  id         uuid        primary key default gen_random_uuid(),
  space_id   uuid        not null,
  user_id    uuid        not null,
  device_id  text        not null check (length(device_id) between 1 and 100),
  key_epoch  int         not null check (key_epoch >= 1),
  payload    bytea       not null check (octet_length(payload) between 1 and 4096),
  signature  bytea       not null check (octet_length(signature) between 64 and 80),
  sent_at    timestamptz not null default now(),
  foreign key (space_id, user_id)
    references public.zt_space_members (space_id, user_id) on delete cascade
);
create index if not exists family_events_space_sent
  on public.family_events (space_id, sent_at);
create index if not exists family_events_member_sent
  on public.family_events (space_id, user_id, sent_at);

-- How many days of history a circle keeps (default 7 when it has no row).
create table if not exists public.family_settings (
  space_id     uuid        primary key references public.zt_spaces (id) on delete cascade,
  history_days int         not null default 7 check (history_days between 1 and 30),
  updated_at   timestamptz not null default now()
);

-- 2. Who may see and write what ----------------------------------------------

alter table public.family_latest   enable row level security;
alter table public.family_events   enable row level security;
alter table public.family_settings enable row level security;

create policy family_latest_member_read on public.family_latest
  for select to authenticated using (public.zt_space_role(space_id) is not null);
create policy family_latest_own_insert on public.family_latest
  for insert to authenticated
  with check ((select auth.uid()) = user_id and public.zt_space_role(space_id) is not null);
create policy family_latest_own_update on public.family_latest
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id and public.zt_space_role(space_id) is not null);
-- Turning sharing off removes the device's last location for everyone.
create policy family_latest_own_delete on public.family_latest
  for delete to authenticated using ((select auth.uid()) = user_id);

create policy family_events_member_read on public.family_events
  for select to authenticated using (public.zt_space_role(space_id) is not null);
create policy family_events_own_insert on public.family_events
  for insert to authenticated
  with check ((select auth.uid()) = user_id and public.zt_space_role(space_id) is not null);
-- A member can erase their own history. Nobody can edit an event.
create policy family_events_own_delete on public.family_events
  for delete to authenticated using ((select auth.uid()) = user_id);

create policy family_settings_member_read on public.family_settings
  for select to authenticated using (public.zt_space_role(space_id) is not null);

revoke all on public.family_latest, public.family_events, public.family_settings from anon;
revoke truncate on public.family_latest, public.family_events, public.family_settings
  from authenticated;
revoke update on public.family_events from authenticated;
-- Settings change through family_set_history_days only.
revoke insert, update, delete on public.family_settings from authenticated;

-- 3. Server-side rules on every write ----------------------------------------

-- Only circles of the Family app take location rows; the sender and the
-- time are the server's, never the phone's; and a new row must be sealed
-- under the circle's current key, so a removed member's old key is useless.
create or replace function public.family_rows_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_app   text;
  v_epoch int;
begin
  select s.app, s.key_epoch into v_app, v_epoch
    from public.zt_spaces s where s.id = new.space_id;
  if v_app is distinct from 'family' then
    raise exception 'family_not_a_circle' using errcode = 'P0001';
  end if;
  if new.key_epoch <> v_epoch then
    raise exception 'zt_space_key_stale' using errcode = 'P0001';
  end if;
  if tg_op = 'UPDATE' then
    if new.space_id <> old.space_id or new.user_id <> old.user_id
       or new.device_id <> old.device_id then
      raise exception 'family_row_moved' using errcode = 'P0001';
    end if;
  end if;
  -- A signed-in phone writes as itself. (The database owner, with no
  -- account, is the migration or a test setting rows up.)
  if (select auth.uid()) is not null then
    new.user_id := (select auth.uid());
  end if;
  new.sent_at := now();
  return new;
end;
$$;
revoke execute on function public.family_rows_guard() from public, anon, authenticated;

drop trigger if exists family_latest_guard on public.family_latest;
create trigger family_latest_guard
  before insert or update on public.family_latest
  for each row execute function public.family_rows_guard();

-- History is capped per member so one phone can't fill the database:
-- 1200 events an hour is one every 3 seconds, far above live sharing.
create or replace function public.family_events_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_recent bigint;
begin
  select count(*) into v_recent from public.family_events e
   where e.space_id = new.space_id and e.user_id = new.user_id
     and e.sent_at > now() - interval '1 hour';
  if v_recent >= 1200 then
    raise exception 'family_too_many_events' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke execute on function public.family_events_guard() from public, anon, authenticated;

drop trigger if exists family_events_guard on public.family_events;
create trigger family_events_guard
  before insert on public.family_events
  for each row execute function public.family_rows_guard();
drop trigger if exists family_events_rate on public.family_events;
create trigger family_events_rate
  before insert on public.family_events
  for each row execute function public.family_events_guard();

-- 4. Functions the app calls --------------------------------------------------

-- An owner sets how long the circle keeps history (1 to 30 days). Shorter
-- takes effect at the next cleanup.
create or replace function public.family_set_history_days(p_space uuid, p_days int)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then
    raise exception 'zt_not_signed_in' using errcode = 'P0001';
  end if;
  if public.zt_space_role(p_space) is distinct from 'admin' then
    raise exception 'zt_not_space_admin' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.zt_spaces where id = p_space and app = 'family') then
    raise exception 'family_not_a_circle' using errcode = 'P0001';
  end if;
  if p_days is null or p_days < 1 or p_days > 30 then
    raise exception 'family_bad_history_days' using errcode = 'P0001';
  end if;
  insert into public.family_settings (space_id, history_days)
    values (p_space, p_days)
  on conflict (space_id) do update
    set history_days = excluded.history_days, updated_at = now();
end;
$$;
revoke execute on function public.family_set_history_days(uuid, int) from public, anon;
grant execute on function public.family_set_history_days(uuid, int) to authenticated;

-- 5. Cleanup ------------------------------------------------------------------

-- Deletes history older than each circle's window, and "latest" rows from
-- devices silent for 30 days (a phone that was replaced or wiped). The
-- server can do this without reading anything: it only looks at sent_at.
create or replace function public.family_purge_history()
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  v_events bigint;
  v_latest bigint;
begin
  delete from public.family_events e
   where e.sent_at < now() - make_interval(days => coalesce(
           (select s.history_days from public.family_settings s
             where s.space_id = e.space_id), 7));
  get diagnostics v_events = row_count;
  delete from public.family_latest l
   where l.sent_at < now() - interval '30 days';
  get diagnostics v_latest = row_count;
  return v_events + v_latest;
end;
$$;
revoke execute on function public.family_purge_history() from public, anon, authenticated;

-- Hourly at minute 23, where pg_cron is available (it is on Supabase; the
-- plain Postgres in CI has none, so there the job is just skipped).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('family-purge-history', '23 * * * *',
                          'select public.family_purge_history()');
  end if;
end $$;

-- 6. Live updates -------------------------------------------------------------

-- Realtime respects the read policies above: only a circle's members get
-- its rows.
alter publication supabase_realtime add table
  public.family_latest, public.family_events;
