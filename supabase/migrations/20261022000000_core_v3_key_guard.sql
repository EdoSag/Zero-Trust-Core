-- zero_trust_core v3: protect the key row, and stop raw passwords reaching
-- Supabase. Additive; existing apps keep working unchanged.
-- NOT APPLIED. Must be live before any app ships core v0.3, or pre-core
-- accounts can't sign in to upgrade.

-- 1. When the auth password became the derived secret. Null for pre-core
--    accounts and for upgrades that haven't switched it yet.
alter table public.profiles
  add column if not exists auth_upgraded_at timestamptz;

-- 2. Asked before sign-in: may the client try the raw password? Only for a
--    pre-core account that hasn't switched yet. Unknown emails and v2
--    accounts get false, so this reveals nothing about them; it does reveal
--    that an email has a not-yet-upgraded pre-core account, a set that only
--    shrinks.
create or replace function public.zt_needs_legacy_sign_in(p_email text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from auth.users u
    join public.profiles p on p.id = u.id
    where lower(u.email) = lower(trim(p_email))
      and p.salt is not null
      and p.auth_upgraded_at is null
      and (p.wrapped_dek is null or p.legacy_dek)
  );
$$;

revoke all on function public.zt_needs_legacy_sign_in(text) from public;
grant execute on function public.zt_needs_legacy_sign_in(text)
  to anon, authenticated;

-- 3. Every replaced key row is kept, so a buggy client or a stolen session
--    that overwrites the keys can be rolled back instead of costing the user
--    their data. Clients can read their own history but never write it.
create table if not exists public.profile_key_history (
  id                   bigint generated always as identity primary key,
  user_id              uuid        not null references auth.users(id) on delete cascade,
  replaced_at          timestamptz not null default now(),
  key_version          int,
  kdf_salt             bytea,
  kdf_params           jsonb,
  wrapped_dek          bytea,
  recovery_wrapped_dek bytea,
  legacy_dek           boolean,
  pending_wrapped_dek  bytea,
  pending_kdf_params   jsonb
);

create index if not exists profile_key_history_user
  on public.profile_key_history (user_id, replaced_at desc);

alter table public.profile_key_history enable row level security;

create policy profile_key_history_owner_read on public.profile_key_history
  for select to authenticated
  using ((select auth.uid()) = user_id);

revoke insert, update, delete on public.profile_key_history
  from anon, authenticated;

-- 4. Refuse writes that would destroy key material. Changing keys stays
--    allowed (password change, recovery-key rotation); erasing them,
--    downgrading the version or dropping the legacy flag does not.
create or replace function public.profiles_guard_keys()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.wrapped_dek is not null and new.wrapped_dek is null
     or old.recovery_wrapped_dek is not null and new.recovery_wrapped_dek is null
     or old.kdf_salt is not null and new.kdf_salt is null
     or old.kdf_params is not null and new.kdf_params is null then
    raise exception 'profiles: key material cannot be removed'
      using errcode = 'check_violation';
  end if;
  if new.key_version < old.key_version then
    raise exception 'profiles: key_version cannot go down'
      using errcode = 'check_violation';
  end if;
  if old.legacy_dek and not new.legacy_dek then
    raise exception 'profiles: legacy_dek cannot be cleared'
      using errcode = 'check_violation';
  end if;
  -- Once switched, an account never goes back to raw-password sign-in.
  new.auth_upgraded_at := coalesce(old.auth_upgraded_at, new.auth_upgraded_at);
  return new;
end;
$$;

create or replace trigger profiles_guard_keys
  before update on public.profiles
  for each row execute function public.profiles_guard_keys();

create or replace function public.profiles_keep_key_history()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (old.key_version, old.kdf_salt, old.kdf_params, old.wrapped_dek,
      old.recovery_wrapped_dek, old.legacy_dek, old.pending_wrapped_dek,
      old.pending_kdf_params)
     is distinct from
     (new.key_version, new.kdf_salt, new.kdf_params, new.wrapped_dek,
      new.recovery_wrapped_dek, new.legacy_dek, new.pending_wrapped_dek,
      new.pending_kdf_params)
     and old.wrapped_dek is not null then
    insert into public.profile_key_history (
      user_id, key_version, kdf_salt, kdf_params, wrapped_dek,
      recovery_wrapped_dek, legacy_dek, pending_wrapped_dek, pending_kdf_params)
    values (
      old.id, old.key_version, old.kdf_salt, old.kdf_params, old.wrapped_dek,
      old.recovery_wrapped_dek, old.legacy_dek, old.pending_wrapped_dek,
      old.pending_kdf_params);
    -- Keep the newest 50 per user.
    delete from public.profile_key_history h
    where h.user_id = old.id
      and h.id not in (
        select id from public.profile_key_history
        where user_id = old.id
        order by id desc
        limit 50);
  end if;
  return null;
end;
$$;

create or replace trigger profiles_keep_key_history
  after update on public.profiles
  for each row execute function public.profiles_keep_key_history();

-- profiles has no delete policy, so clients can't remove the row either;
-- it goes only with the auth user (delete-account Edge Function).
