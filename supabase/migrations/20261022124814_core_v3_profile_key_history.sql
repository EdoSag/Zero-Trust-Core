-- zero_trust_core v3 (part 3 of 5): protect the key row, and stop raw
-- passwords reaching Supabase. Applied 2026-10-22, in five parts.

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
