-- DEFERRED, NOT APPLIED: changes a policy on the pre-core Fitness table.
-- Harmless as is (the ALL policy masks the wrong column). Apply when the
-- Fitness app moves onto the core: move it into migrations/ with a new
-- timestamp.

-- Fix the wrong-column insert policy on the legacy Fitness table
--    (checked `id` instead of `user_id`; masked by the ALL policy).
drop policy if exists "Users can insert their own row" on public.encrypted_vault;
create policy "Users can insert their own row" on public.encrypted_vault
  for insert with check ((select auth.uid()) = user_id);
