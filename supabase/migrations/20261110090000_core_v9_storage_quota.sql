-- zero_trust_core v0.9 (Z17, part 1 of 3): per-user storage limits, so one
-- account can't fill the shared Supabase project.
--
-- Additive: two new tables, new functions, a new trigger on vault_items and
-- a new restrictive policy on storage.objects. No existing row, column or
-- policy is changed. Deleting is never refused, so an account over its
-- limit can always free space; legacy tables (encrypted_*) are not limited.
--
-- Errors a client sees (PostgREST 400, code P0001):
--   zt_item_too_large  one item's sealed blob is over the per-item cap
--   zt_storage_full    the account's synced data is over its limit
-- Core 0.9 pushes the rest of a batch and keeps refused items on the
-- device, marked as waiting, until space is freed or the limit raised.

-- What each account is using. Kept up to date by a trigger; clients read
-- their own row and never write it.
create table if not exists public.zt_storage_usage (
  user_id    uuid        primary key references auth.users(id) on delete cascade,
  item_bytes bigint      not null default 0,
  item_count bigint      not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.zt_storage_usage enable row level security;
create policy zt_storage_usage_owner_read on public.zt_storage_usage
  for select to authenticated using ((select auth.uid()) = user_id);
revoke insert, update, delete, truncate on public.zt_storage_usage from anon, authenticated;

-- Per-account overrides (a bigger plan later, Z25). Null columns use the
-- defaults in zt_storage_limits_for. Set by the project owner only.
create table if not exists public.zt_storage_limits (
  user_id              uuid        primary key references auth.users(id) on delete cascade,
  max_item_bytes       bigint,
  max_items            bigint,
  max_attachment_bytes bigint,
  note                 text,
  updated_at           timestamptz not null default now()
);
alter table public.zt_storage_limits enable row level security;
create policy zt_storage_limits_owner_read on public.zt_storage_limits
  for select to authenticated using ((select auth.uid()) = user_id);
revoke insert, update, delete, truncate on public.zt_storage_limits from anon, authenticated;

-- The limits for one account. Defaults: 1 MiB per item, 50 MiB and
-- 100,000 items of synced data, 500 MiB of attachments. Today the largest
-- account uses under 1 MiB in about 500 items.
create or replace function public.zt_storage_limits_for(p_user uuid)
returns table (max_blob_bytes bigint, max_item_bytes bigint, max_items bigint,
               max_attachment_bytes bigint)
language sql stable set search_path = '' as $$
  select 1048576::bigint,
         coalesce(l.max_item_bytes, 52428800),
         coalesce(l.max_items, 100000),
         coalesce(l.max_attachment_bytes, 524288000)
  from (select 1) d
  left join public.zt_storage_limits l on l.user_id = p_user;
$$;
-- Runs as the caller: a signed-in user sees only their own override (RLS),
-- so asking about anyone else returns the defaults.
revoke execute on function public.zt_storage_limits_for(uuid) from public, anon;
grant execute on function public.zt_storage_limits_for(uuid) to authenticated;

-- Keeps zt_storage_usage in step with vault_items and refuses growth past
-- the limits. AFTER, so rows the write guard skipped are never counted.
create or replace function public.vault_items_track_usage()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_user  uuid;
  v_bytes bigint;
  v_count bigint;
  v_usage public.zt_storage_usage;
  v_lim   record;
begin
  if tg_op = 'INSERT' then
    v_user  := new.user_id;
    v_bytes := coalesce(octet_length(new.data_blob), 0);
    v_count := 1;
  elsif tg_op = 'UPDATE' then
    v_user  := new.user_id;
    v_bytes := coalesce(octet_length(new.data_blob), 0)
             - coalesce(octet_length(old.data_blob), 0);
    v_count := 0;
  else
    -- Delete (tombstone purge, or the account being deleted): never
    -- refused, and never creates a row, so a cascade from auth.users
    -- leaves nothing behind.
    update public.zt_storage_usage
       set item_bytes = greatest(item_bytes - coalesce(octet_length(old.data_blob), 0), 0),
           item_count = greatest(item_count - 1, 0),
           updated_at = now()
     where user_id = old.user_id;
    return null;
  end if;

  insert into public.zt_storage_usage as s (user_id, item_bytes, item_count)
  values (v_user, greatest(v_bytes, 0), v_count)
  on conflict (user_id) do update
     set item_bytes = greatest(s.item_bytes + v_bytes, 0),
         item_count = s.item_count + v_count,
         updated_at = now()
  returning * into v_usage;

  -- Shrinking, unchanged or a tombstone (also a new one, for an item that
  -- never reached the server): always allowed.
  if (v_bytes <= 0 and v_count = 0) or new.deleted then
    return null;
  end if;

  select * into v_lim from public.zt_storage_limits_for(v_user);
  if octet_length(new.data_blob) > v_lim.max_blob_bytes then
    raise exception using errcode = 'P0001', message = 'zt_item_too_large',
      detail = format('item %s is %s bytes; the limit is %s',
                      new.item_id, octet_length(new.data_blob), v_lim.max_blob_bytes);
  end if;
  if v_usage.item_bytes > v_lim.max_item_bytes
     or v_usage.item_count > v_lim.max_items then
    raise exception using errcode = 'P0001', message = 'zt_storage_full',
      detail = format('%s bytes in %s items; the limit is %s bytes, %s items',
                      v_usage.item_bytes, v_usage.item_count,
                      v_lim.max_item_bytes, v_lim.max_items);
  end if;
  return null;
end;
$$;
revoke execute on function public.vault_items_track_usage() from public, anon, authenticated;

-- Count what is already there, then start tracking, with writes held off
-- for the moment it takes so nothing is counted twice or missed.
do $$
begin
  lock table public.vault_items in share row exclusive mode;

  insert into public.zt_storage_usage (user_id, item_bytes, item_count)
  select user_id, coalesce(sum(octet_length(data_blob)), 0), count(*)
  from public.vault_items
  group by user_id
  on conflict (user_id) do nothing;

  drop trigger if exists vault_items_track_usage on public.vault_items;
  create trigger vault_items_track_usage
    after insert or update or delete on public.vault_items
    for each row execute function public.vault_items_track_usage();
end;
$$;

-- Attachments: a new or replaced file must fit in the account's limit
-- together with its other files. Runs as the uploader, so it only sees the
-- uploader's own files. When the size isn't known yet (Storage can check a
-- row before the upload finishes), the account must still be under its
-- limit, so the total passes it by at most one file (25 MB).
create or replace function public.zt_attachments_fit(p_name text, p_size bigint)
returns boolean language sql stable set search_path = '' as $$
  with others as (
    select coalesce(sum((o.metadata ->> 'size')::bigint), 0) as bytes
    from storage.objects o
    where o.bucket_id = 'zt-attachments'
      and (storage.foldername(o.name))[1] = (select auth.uid())::text
      and o.name <> p_name
  ), lim as (
    select max_attachment_bytes as max
    from public.zt_storage_limits_for((select auth.uid()))
  )
  select case when p_size is null then others.bytes < lim.max
              else others.bytes + p_size <= lim.max end
  from others, lim;
$$;
revoke execute on function public.zt_attachments_fit(text, bigint) from public, anon;
grant execute on function public.zt_attachments_fit(text, bigint) to authenticated;

-- Restrictive: applies on top of zt_attachments_insert_own / _update_own,
-- so replacing a file with a bigger one is limited too, and a smaller one
-- is allowed. Other buckets (Contacts' old photos, TimeSpot) are untouched.
create policy zt_attachments_within_limit on storage.objects
  as restrictive for insert to authenticated
  with check (bucket_id <> 'zt-attachments'
              or public.zt_attachments_fit(name, (metadata ->> 'size')::bigint));

create policy zt_attachments_update_within_limit on storage.objects
  as restrictive for update to authenticated
  using (true)
  with check (bucket_id <> 'zt-attachments'
              or public.zt_attachments_fit(name, (metadata ->> 'size')::bigint));

-- For the app's "Storage" row: what this account uses and may use. Runs as
-- the caller, so RLS limits it to the caller's own rows and files.
create or replace function public.zt_my_storage()
returns json language sql stable set search_path = '' as $$
  select json_build_object(
    'item_bytes',           coalesce(u.item_bytes, 0),
    'item_count',           coalesce(u.item_count, 0),
    'attachment_bytes',     (select coalesce(sum((o.metadata ->> 'size')::bigint), 0)
                             from storage.objects o
                             where o.bucket_id = 'zt-attachments'
                               and (storage.foldername(o.name))[1] = auth.uid()::text),
    'max_blob_bytes',       l.max_blob_bytes,
    'max_item_bytes',       l.max_item_bytes,
    'max_items',            l.max_items,
    'max_attachment_bytes', l.max_attachment_bytes)
  from public.zt_storage_limits_for(auth.uid()) l
  left join public.zt_storage_usage u on u.user_id = auth.uid()
  where auth.uid() is not null;
$$;
revoke execute on function public.zt_my_storage() from public, anon;
grant execute on function public.zt_my_storage() to authenticated;
