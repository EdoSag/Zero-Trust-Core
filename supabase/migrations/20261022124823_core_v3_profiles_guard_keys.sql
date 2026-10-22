-- zero_trust_core v3 (part 4 of 5): protect the key row, and stop raw
-- passwords reaching Supabase. Applied 2026-10-22, in five parts.

-- 4. Refuse writes that would destroy key material. Changing keys stays
--    allowed (password change, recovery-key rotation); erasing them,
--    downgrading the version or dropping the legacy flag does not.
create or replace function public.profiles_guard_keys()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.wrapped_dek is not null and new.wrapped_dek is null
     or old.recovery_wrapped_dek is not null and new.recovery_wrapped_dek is null
     or old.kdf_salt is not null and new.kdf_salt is null
     or old.kdf_params is not null and new.kdf_params is null then
    raise exception 'profiles: key material cannot be removed'
      using errcode = 'check_violation';
  end if;
  if new.key_version < old.key_version then
    raise exception 'profiles: key_version cannot go down'
      using errcode = 'check_violation';
  end if;
  if old.legacy_dek and not new.legacy_dek then
    raise exception 'profiles: legacy_dek cannot be cleared'
      using errcode = 'check_violation';
  end if;
  -- Once switched, an account never goes back to raw-password sign-in.
  new.auth_upgraded_at := coalesce(old.auth_upgraded_at, new.auth_upgraded_at);
  return new;
end;
$$;

create or replace trigger profiles_guard_keys
  before update on public.profiles
  for each row execute function public.profiles_guard_keys();
