-- zero_trust_core v2: additive only. Existing apps keep working unchanged.
-- Applied 2026-10-18. The encrypted_vault policy fix that was part 3 is
-- deferred: see supabase/deferred/encrypted_vault_insert_policy.sql.

-- 1. profiles: key hierarchy columns (legacy `salt` stays for migration).
alter table public.profiles
  add column if not exists kdf_salt bytea,                 -- derived from email, see zt_crypto Kdf.saltForEmail
  add column if not exists kdf_params jsonb,
  add column if not exists key_version int not null default 1,
  add column if not exists wrapped_dek bytea,
  add column if not exists recovery_wrapped_dek bytea,
  add column if not exists legacy_dek boolean not null default false,  -- DEK is the adopted pre-core key
  add column if not exists pending_wrapped_dek bytea,                   -- in-flight password change
  add column if not exists pending_kdf_params jsonb,
  add column if not exists created_at timestamptz not null default now();

-- Legacy rows without a salt must stay valid once v2 rows stop writing it.
alter table public.profiles alter column salt drop not null;

-- 2. One per-item table for every app.
create table if not exists public.vault_items (
  user_id    uuid        not null references auth.users(id) on delete cascade,
  app        text        not null check (app ~ '^[a-z_]+$'),
  item_id    text        not null,
  data_blob  bytea,                 -- sealed box under the app key; null when deleted
  signature  bytea,
  device_id  text,
  updated_at timestamptz not null default now(),
  deleted    boolean     not null default false,
  primary key (user_id, app, item_id),
  check (deleted or data_blob is not null)
);

create index if not exists vault_items_user_app_updated
  on public.vault_items (user_id, app, updated_at desc);

alter table public.vault_items enable row level security;

drop policy if exists vault_items_owner_all on public.vault_items;
create policy vault_items_owner_all on public.vault_items
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

alter publication supabase_realtime add table public.vault_items;
