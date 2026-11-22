-- Z21: retire the raw-password sign-in fallback.
--
-- Pre-core accounts were upgraded at their first core sign-in (their old
-- key became the DEK, profiles.legacy_dek). Checked live on 2026-11-22:
-- no account still has a raw Supabase password, so apps on Core after 0.13
-- never send the raw password.
--
-- Older app versions still ask this function before trying the raw
-- password. It now always answers false, so they stop sending it too and
-- it no longer tells anyone which emails have a pre-core account.
-- Upgraded accounts are untouched: legacy_dek and their data stay as they
-- are, and they sign in with the derived auth secret like every account.
create or replace function public.zt_needs_legacy_sign_in(p_email text)
returns boolean
language sql immutable security definer set search_path = ''
as $$
  select false;
$$;

comment on function public.zt_needs_legacy_sign_in(text) is
  'Retired 2026-11-22 (Z21): always false. Kept for apps on Core 0.13 and older.';

revoke all on function public.zt_needs_legacy_sign_in(text) from public;
grant execute on function public.zt_needs_legacy_sign_in(text)
  to anon, authenticated;
