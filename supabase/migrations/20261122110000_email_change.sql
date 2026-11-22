-- Z14: change the account's email address.
--
-- The sign-in secret is derived from the password and the email, so the
-- email and the Supabase password must change in one step, or the person
-- couldn't sign in with either address. The change-email function does
-- that with one admin call, after the person proved the new address with
-- a 6-digit code it emailed. This table holds the code (hashed) meanwhile.
-- The encryption keys don't change: they stay wrapped as before.

create table if not exists public.zt_email_changes (
  user_id uuid primary key references auth.users(id) on delete cascade,
  new_email text not null check (length(new_email) between 3 and 254),
  -- SHA-256 of "<user id>:<code>"; the code itself is never stored.
  code_hash bytea not null,
  expires_at timestamptz not null,
  attempts integer not null default 0 check (attempts >= 0),
  created_at timestamptz not null default now()
);

alter table public.zt_email_changes enable row level security;
-- No policies: only the change-email function (service role) uses it.
revoke all on table public.zt_email_changes from public, anon, authenticated;

-- Is the address taken by another account? Service role only, so it can't
-- be used to find out who has an account.
create or replace function public.zt_email_in_use(p_email text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from auth.users where lower(email) = lower(trim(p_email)));
$$;
revoke execute on function public.zt_email_in_use(text) from public, anon, authenticated;
grant execute on function public.zt_email_in_use(text) to service_role;

-- Leftover codes are removed daily.
create or replace function public.zt_purge_email_changes()
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  v_count bigint;
begin
  delete from public.zt_email_changes where expires_at < now() - interval '1 day';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function public.zt_purge_email_changes() from public, anon, authenticated;

do $outer$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('zt-purge-email-changes', '53 3 * * *',
                          'select public.zt_purge_email_changes()');
  end if;
end;
$outer$;
