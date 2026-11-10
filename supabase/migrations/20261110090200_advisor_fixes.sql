-- Z18 (part 3 of 3 of the v0.9 database changes): Supabase security
-- advisor fixes for the shared project. The `timespot` schema belongs to a
-- separate app and is left alone here.

-- 1. profiles_keep_key_history is a trigger function. It never needed to be
--    callable over the API (/rest/v1/rpc/...). Triggers still fire: Postgres
--    checks EXECUTE only when a trigger is created.
revoke execute on function public.profiles_keep_key_history() from public, anon, authenticated;

-- 2. public.spatial_ref_sys comes with the PostGIS extension (used by
--    TimeSpot). It is owned by supabase_admin, so neither RLS nor REVOKE can
--    be applied from here, and anyone holding the public anon key could
--    insert, change or delete its rows over the REST API. Block writes from
--    the API roles with a statement trigger; reads (public EPSG reference
--    data) keep working and extension updates (run as admin) are unaffected.
create or replace function public.zt_spatial_ref_sys_read_only()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user in ('anon', 'authenticated') then
    raise exception 'spatial_ref_sys is read-only' using errcode = '42501';
  end if;
  return null;
end;
$$;
revoke execute on function public.zt_spatial_ref_sys_read_only() from public, anon, authenticated;

do $$
begin
  if to_regclass('public.spatial_ref_sys') is not null
     and not exists (select 1 from pg_trigger
                     where tgrelid = 'public.spatial_ref_sys'::regclass
                       and tgname = 'zt_read_only') then
    create trigger zt_read_only
      before insert or update or delete or truncate on public.spatial_ref_sys
      for each statement execute function public.zt_spatial_ref_sys_read_only();
  end if;
end;
$$;
