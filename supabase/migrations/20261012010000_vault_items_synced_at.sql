-- Server-assigned receive time for vault_items, so clients page pulls on a
-- clock they don't control, and a guard so stale writes can't win.
-- NOT APPLIED.
alter table public.vault_items
  add column if not exists synced_at timestamptz not null default now();

create or replace function public.vault_items_set_synced_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  -- Last writer wins on the client's updated_at: an older write (a device
  -- that hasn't pulled yet) never replaces a newer row. Skipping it is
  -- safe; that device pulls the newer row and reports its own as a conflict.
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return null;
  end if;
  new.synced_at := clock_timestamp();
  return new;
end;
$$;

drop trigger if exists vault_items_synced_at on public.vault_items;
create trigger vault_items_synced_at
  before insert or update on public.vault_items
  for each row execute function public.vault_items_set_synced_at();

create index if not exists vault_items_user_app_synced
  on public.vault_items (user_id, app, synced_at);
