-- zero_trust_core v3 (part 1 of 5): protect the key row, and stop raw
-- passwords reaching Supabase. Applied 2026-10-22, in five parts.

-- 1. When the auth password became the derived secret. Null for pre-core
--    accounts and for upgrades that haven't switched it yet.
alter table public.profiles
  add column if not exists auth_upgraded_at timestamptz;
