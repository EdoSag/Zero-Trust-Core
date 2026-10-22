-- zero_trust_core v4: the vault_items write guard also refuses rows dated
-- more than 10 minutes ahead of the server, so a phone whose clock runs
-- fast can't stamp an edit that beats every later edit on every device.
-- The refused write is skipped, like a stale one; the client keeps it and
-- it is accepted once the server's time catches up with its timestamp.
-- Matches ItemSyncEngine.maxClockSkew. Applied 2026-10-22.
create or replace function public.vault_items_set_synced_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return null;
  end if;
  if new.updated_at > now() + interval '10 minutes' then
    return null;
  end if;
  new.synced_at := clock_timestamp();
  return new;
end;
$$;
