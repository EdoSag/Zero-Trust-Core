-- zero_trust_core v3 (part 2 of 5): protect the key row, and stop raw
-- passwords reaching Supabase. Applied 2026-10-22, in five parts.

-- 2. Asked before sign-in: may the client try the raw password? Only for a
--    pre-core account that hasn't switched yet. Unknown emails and v2
--    accounts get false, so this reveals nothing about them; it does reveal
--    that an email has a not-yet-upgraded pre-core account, a set that only
--    shrinks.
create or replace function public.zt_needs_legacy_sign_in(p_email text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from auth.users u
    join public.profiles p on p.id = u.id
    where lower(u.email) = lower(trim(p_email))
      and p.salt is not null
      and p.auth_upgraded_at is null
      and (p.wrapped_dek is null or p.legacy_dek)
  );
$$;

revoke all on function public.zt_needs_legacy_sign_in(text) from public;
grant execute on function public.zt_needs_legacy_sign_in(text)
  to anon, authenticated;
