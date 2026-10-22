-- zero_trust_core v3 (part 5 of 5): protect the key row, and stop raw
-- passwords reaching Supabase. Applied 2026-10-22, in five parts.

-- Keep every replaced key row (newest 50 per user); see part 3.
create or replace function public.profiles_keep_key_history()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (old.key_version, old.kdf_salt, old.kdf_params, old.wrapped_dek,
      old.recovery_wrapped_dek, old.legacy_dek, old.pending_wrapped_dek,
      old.pending_kdf_params)
     is distinct from
     (new.key_version, new.kdf_salt, new.kdf_params, new.wrapped_dek,
      new.recovery_wrapped_dek, new.legacy_dek, new.pending_wrapped_dek,
      new.pending_kdf_params)
     and old.wrapped_dek is not null then
    insert into public.profile_key_history (
      user_id, key_version, kdf_salt, kdf_params, wrapped_dek,
      recovery_wrapped_dek, legacy_dek, pending_wrapped_dek, pending_kdf_params)
    values (
      old.id, old.key_version, old.kdf_salt, old.kdf_params, old.wrapped_dek,
      old.recovery_wrapped_dek, old.legacy_dek, old.pending_wrapped_dek,
      old.pending_kdf_params);
    -- Keep the newest 50 per user.
    delete from public.profile_key_history h
    where h.user_id = old.id
      and h.id not in (
        select id from public.profile_key_history
        where user_id = old.id
        order by id desc
        limit 50);
  end if;
  return null;
end;
$$;

create or replace trigger profiles_keep_key_history
  after update on public.profiles
  for each row execute function public.profiles_keep_key_history();

-- profiles has no delete policy, so clients can't remove the row either;
-- it goes only with the auth user (delete-account Edge Function).
