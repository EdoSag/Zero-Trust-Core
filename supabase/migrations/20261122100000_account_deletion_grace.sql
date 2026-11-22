-- Z22: deleting an account waits 7 days. Until then the account works as
-- before, and the person can keep it from any app (sign in, tap "Keep my
-- account") or from the link in the email the delete-account function
-- sends. Afterwards the account-deletion function deletes it for good,
-- called hourly by pg_cron through pg_net.
--
-- Setup on the live project (once, see supabase/functions/account-deletion):
-- two Vault secrets, `zt_functions_url` and `zt_account_purge_secret`.

create table if not exists public.zt_account_deletions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  requested_at timestamptz not null default now(),
  delete_after timestamptz not null,
  -- SHA-256 of the undo link's token; the token itself is never stored.
  undo_token_hash bytea not null unique
);

alter table public.zt_account_deletions enable row level security;
revoke all on table public.zt_account_deletions from public, anon, authenticated;
-- The person sees their own pending deletion (when, not the token hash).
grant select (user_id, requested_at, delete_after)
  on public.zt_account_deletions to authenticated;
drop policy if exists zt_account_deletions_own on public.zt_account_deletions;
create policy zt_account_deletions_own on public.zt_account_deletions
  for select to authenticated using (user_id = (select auth.uid()));

-- Schedules (or re-schedules) a deletion. Asking again keeps the earlier
-- date and only replaces the undo token, so asking twice never postpones
-- the deletion and the newest email's link is the one that works.
create or replace function public.zt_schedule_account_deletion(
  p_user uuid, p_token_hash bytea, p_days integer default 7)
returns timestamptz language plpgsql security definer set search_path = '' as $$
declare
  v_after timestamptz;
begin
  if p_days < 1 or p_days > 30 then
    raise exception 'zt_schedule_account_deletion: 1 to 30 days';
  end if;
  insert into public.zt_account_deletions as d (user_id, delete_after, undo_token_hash)
  values (p_user, now() + make_interval(days => p_days), p_token_hash)
  on conflict (user_id) do update set undo_token_hash = excluded.undo_token_hash
  returning d.delete_after into v_after;
  return v_after;
end;
$$;

-- "Keep my account" in an app.
create or replace function public.zt_cancel_account_deletion()
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  delete from public.zt_account_deletions where user_id = (select auth.uid());
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

-- "Keep my account" from the email link (no session).
create or replace function public.zt_cancel_account_deletion_by_token(p_token_hash bytea)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  delete from public.zt_account_deletions where undo_token_hash = p_token_hash;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

-- Accounts whose 7 days are over, oldest first.
create or replace function public.zt_due_account_deletions(p_limit integer default 50)
returns setof uuid language sql stable security definer set search_path = '' as $$
  select user_id from public.zt_account_deletions
   where delete_after <= now()
   order by delete_after
   limit greatest(1, least(p_limit, 500));
$$;

-- The function proves the hourly call came from here, not from anyone who
-- found the URL: the secret lives only in Vault (and in the call).
create or replace function public.zt_check_account_purge_secret(p_secret text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  v_secret text;
begin
  if p_secret is null or length(p_secret) < 32 then return false; end if;
  if to_regclass('vault.decrypted_secrets') is null then return false; end if;
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1'
    into v_secret using 'zt_account_purge_secret';
  return v_secret is not null and length(v_secret) >= 32 and v_secret = p_secret;
end;
$$;

-- Hourly: when something is due, ask the account-deletion function to
-- delete it (only it can remove the storage files and the auth user).
create or replace function public.zt_request_account_purge()
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_url text;
  v_secret text;
begin
  if not exists (select 1 from public.zt_account_deletions where delete_after <= now()) then
    return;
  end if;
  if to_regclass('vault.decrypted_secrets') is null
     or not exists (select 1 from pg_extension where extname = 'pg_net') then
    raise warning 'zt_request_account_purge: pg_net or Vault missing';
    return;
  end if;
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1'
    into v_url using 'zt_functions_url';
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1'
    into v_secret using 'zt_account_purge_secret';
  if v_url is null or v_secret is null then
    raise warning 'zt_request_account_purge: Vault secrets not set';
    return;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3)'
    using rtrim(v_url, '/') || '/account-deletion',
          jsonb_build_object('action', 'purge'),
          jsonb_build_object('content-type', 'application/json',
                             'x-zt-purge-secret', v_secret);
end;
$$;

revoke execute on function public.zt_schedule_account_deletion(uuid, bytea, integer) from public, anon, authenticated;
revoke execute on function public.zt_cancel_account_deletion() from public, anon;
grant execute on function public.zt_cancel_account_deletion() to authenticated;
revoke execute on function public.zt_cancel_account_deletion_by_token(bytea) from public, anon, authenticated;
revoke execute on function public.zt_due_account_deletions(integer) from public, anon, authenticated;
revoke execute on function public.zt_check_account_purge_secret(text) from public, anon, authenticated;
revoke execute on function public.zt_request_account_purge() from public, anon, authenticated;
grant execute on function public.zt_schedule_account_deletion(uuid, bytea, integer),
  public.zt_cancel_account_deletion_by_token(bytea),
  public.zt_due_account_deletions(integer),
  public.zt_check_account_purge_secret(text) to service_role;

do $outer$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('zt-account-purge', '23 * * * *',
                          'select public.zt_request_account_purge()');
  end if;
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net;
  end if;
end;
$outer$;
