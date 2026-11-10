-- Minimal stand-in for the Supabase pieces the migrations use (auth schema,
-- roles, realtime publication) plus the pre-core tables they alter, so CI
-- can run every migration on a plain Postgres.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
create schema auth;
create table auth.users (id uuid primary key, email text);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
create publication supabase_realtime;
create table public.profiles (id uuid primary key references auth.users(id) on delete cascade, salt text not null, updated_at timestamptz default now(), public_key bytea, encrypted_private_key bytea);
alter table public.profiles enable row level security;
create policy "ins" on public.profiles for insert with check (auth.uid() = id);
create policy "upd" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);
create policy "sel" on public.profiles for select using (auth.uid() = id);
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
alter default privileges in schema public grant select, insert, update, delete on tables to authenticated, anon;
create table public.encrypted_vault (id uuid, user_id uuid);
-- Old tables no app uses; 20261110120000_drop_unused_tables removes them.
create table public.encrypted_sms (id uuid, user_id uuid);
create table public.encrypted_note_items (id text, user_id uuid);
create table public.encrypted_contact_items (id uuid, user_id uuid);

-- Storage: buckets, objects and the folder helper the policies use.
create schema storage;
create table storage.buckets (id text primary key, name text not null, public boolean default false, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id), name text not null, owner uuid, metadata jsonb);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$ select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1] $$;
grant usage on schema storage to anon, authenticated;
grant select, insert, update, delete on storage.objects to authenticated;
grant select on storage.buckets to authenticated;

-- PostGIS's reference table, as Supabase ships it: no RLS, writable by the
-- API roles (it is owned by supabase_admin there).
create table public.spatial_ref_sys (srid int primary key, auth_name text);
insert into public.spatial_ref_sys values (4326, 'EPSG');
grant all on public.spatial_ref_sys to anon, authenticated;
