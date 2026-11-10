-- zero_trust_core v0.9 (Z17, part 2 of 3): server cleanup of deleted items.
--
-- A deleted item stays in vault_items as a tombstone (no data, just the id)
-- so every device learns about the delete. After 180 days the tombstone is
-- removed. A device that hasn't synced for longer than that does a full
-- re-sync next time (ItemSyncEngine.tombstoneRetention) and drops anything
-- the server no longer has, so nothing comes back from the dead.
--
-- Only rows with deleted = true are ever removed. Live items and the legacy
-- encrypted_* tables are never touched.

create or replace function public.zt_purge_tombstones(
  p_older_than interval default interval '180 days')
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  v_count bigint;
begin
  if p_older_than < interval '30 days' then
    raise exception 'zt_purge_tombstones: keep tombstones at least 30 days';
  end if;
  delete from public.vault_items
   where deleted
     and synced_at < now() - p_older_than;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
-- Only the scheduler (and the project owner) may run it.
revoke execute on function public.zt_purge_tombstones(interval) from public, anon, authenticated;

-- Daily at 03:17 UTC, where pg_cron is available (it is on Supabase; the
-- plain Postgres in CI has no pg_cron, so there the job is just skipped).
do $outer$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('zt-purge-tombstones', '17 3 * * *',
                          'select public.zt_purge_tombstones()');
  end if;
end;
$outer$;
