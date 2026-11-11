-- zero_trust_core v0.10 (Z24): sharing between Zero-Trust users.
--
-- A "space" is a set of encrypted items several accounts share: a child in
-- Meds, later a shared notebook, task list or calendar. Additive only: new
-- tables and functions; nothing existing is changed except that the daily
-- tombstone purge also covers shared items.
--
-- What the server sees, and nothing more:
--   - which accounts belong to which space, and who is an admin
--     (zt_space_members; needed for row-level security);
--   - each member's copy of each space key, wrapped with that member's
--     public key on an admin's device (zt_space_keys; the server can't open
--     them);
--   - sealed, signed items (zt_space_items), with the key epoch they were
--     sealed under and whether only admins may change them;
--   - open invites: the SHA-256 of a proof derived from the invite token
--     (the token itself only travels in the invite link or QR code) and,
--     once answered, the invitee's answer, sealed under a key derived from
--     the token.
-- Names, public keys and every item's content stay inside the encrypted
-- items. Members check each other's signatures against the space's own
-- (encrypted, signed) member list, so the server can neither read nor
-- forge shared data.
--
-- All membership and key changes go through the functions below; clients
-- can't write those tables directly. Items are written directly (upsert)
-- under row-level security, like vault_items.
--
-- Errors a client sees (PostgREST 400, code P0001):
--   zt_not_space_admin        the caller isn't an admin of that space
--   zt_space_key_stale        the item was sealed under an old key epoch;
--                             fetch the new key and seal again
--   zt_space_admin_only       only admins may write that item
--   zt_invite_invalid         wrong token, expired, used or revoked invite
--   zt_space_keys_mismatch    a key change didn't cover exactly the members
--   zt_space_limit            too many spaces, members or open invites
--   zt_last_admin             the change would leave the space without admin
--   zt_item_too_large / zt_storage_full   as for vault_items (per space)

-- 1. Tables ---------------------------------------------------------------

create table if not exists public.zt_spaces (
  id              uuid        primary key,             -- made on the creating device
  app             text        not null check (app ~ '^[a-z_]+$'),
  created_by      uuid,                                -- informational; may outlive the account
  key_epoch       int         not null default 1 check (key_epoch >= 1),
  -- A member left or deleted their account: an admin's device makes a new
  -- key next time it syncs, so the departed member can't read new data.
  rotation_needed boolean     not null default false,
  item_bytes      bigint      not null default 0,
  item_count      bigint      not null default 0,
  created_at      timestamptz not null default now()
);

create table if not exists public.zt_space_members (
  space_id uuid        not null references public.zt_spaces(id) on delete cascade,
  user_id  uuid        not null references auth.users(id) on delete cascade,
  role     text        not null check (role in ('admin', 'member')),
  added_by uuid,
  added_at timestamptz not null default clock_timestamp(),
  primary key (space_id, user_id)
);
create index if not exists zt_space_members_user on public.zt_space_members (user_id);

create table if not exists public.zt_space_keys (
  space_id    uuid        not null,
  epoch       int         not null check (epoch >= 1),
  user_id     uuid        not null,
  wrapped_key bytea       not null check (octet_length(wrapped_key) between 60 and 512),
  wrapped_by  uuid,
  signature   bytea       not null check (octet_length(signature) = 64),
  created_at  timestamptz not null default now(),
  primary key (space_id, epoch, user_id),
  foreign key (space_id, user_id)
    references public.zt_space_members (space_id, user_id) on delete cascade
);
create index if not exists zt_space_keys_user on public.zt_space_keys (user_id, space_id);

create table if not exists public.zt_space_invites (
  id          uuid        primary key,                 -- made on the inviting device
  space_id    uuid        not null references public.zt_spaces(id) on delete cascade,
  created_by  uuid        references auth.users(id) on delete cascade,
  role        text        not null check (role in ('admin', 'member')),
  token_hash  bytea       not null check (octet_length(token_hash) = 32),
  expires_at  timestamptz not null,
  status      text        not null default 'open'
                          check (status in ('open', 'answered', 'confirmed', 'revoked')),
  answered_by uuid        references auth.users(id) on delete cascade,
  answered_at timestamptz,
  answer      bytea       check (octet_length(answer) <= 4096),
  created_at  timestamptz not null default now()
);
create index if not exists zt_space_invites_space on public.zt_space_invites (space_id, status);

create table if not exists public.zt_space_items (
  space_id   uuid        not null references public.zt_spaces(id) on delete cascade,
  item_id    text        not null check (length(item_id) between 1 and 200),
  key_epoch  int         not null check (key_epoch >= 1),
  data_blob  bytea,                                    -- sealed under the epoch's key; null when deleted
  signature  bytea       not null check (octet_length(signature) = 64),
  author_id  uuid,                                     -- set by the server to the writer
  device_id  text,
  admin_only boolean     not null default false,
  updated_at timestamptz not null default now(),
  synced_at  timestamptz not null default now(),
  deleted    boolean     not null default false,
  primary key (space_id, item_id),
  check (deleted or data_blob is not null)
);
create index if not exists zt_space_items_synced on public.zt_space_items (space_id, synced_at);

-- 2. Who may see what ---------------------------------------------------------

-- The caller's role in a space, or null. Security definer so the policies
-- below don't recurse into zt_space_members' own policy.
create or replace function public.zt_space_role(p_space uuid)
returns text language sql stable security definer set search_path = '' as $$
  select m.role from public.zt_space_members m
  where m.space_id = p_space and m.user_id = (select auth.uid());
$$;
revoke execute on function public.zt_space_role(uuid) from public, anon;
grant execute on function public.zt_space_role(uuid) to authenticated;

alter table public.zt_spaces        enable row level security;
alter table public.zt_space_members enable row level security;
alter table public.zt_space_keys    enable row level security;
alter table public.zt_space_invites enable row level security;
alter table public.zt_space_items   enable row level security;

create policy zt_spaces_member_read on public.zt_spaces
  for select to authenticated using (public.zt_space_role(id) is not null);

create policy zt_space_members_member_read on public.zt_space_members
  for select to authenticated using (public.zt_space_role(space_id) is not null);

-- Each member sees only their own wrapped keys.
create policy zt_space_keys_own_read on public.zt_space_keys
  for select to authenticated using ((select auth.uid()) = user_id);

-- Admins see the space's invites; an invitee sees the one they answered.
create policy zt_space_invites_read on public.zt_space_invites
  for select to authenticated
  using (public.zt_space_role(space_id) = 'admin' or (select auth.uid()) = answered_by);

create policy zt_space_items_member_read on public.zt_space_items
  for select to authenticated using (public.zt_space_role(space_id) is not null);
create policy zt_space_items_member_insert on public.zt_space_items
  for insert to authenticated with check (public.zt_space_role(space_id) is not null);
create policy zt_space_items_member_update on public.zt_space_items
  for update to authenticated
  using (public.zt_space_role(space_id) is not null)
  with check (public.zt_space_role(space_id) is not null);

-- Membership, keys and invites change only through the functions below.
-- Items are never deleted directly: a delete is a tombstone, so it reaches
-- every member's devices.
revoke insert, update, delete, truncate on public.zt_spaces        from anon, authenticated;
revoke insert, update, delete, truncate on public.zt_space_members from anon, authenticated;
revoke insert, update, delete, truncate on public.zt_space_keys    from anon, authenticated;
revoke insert, update, delete, truncate on public.zt_space_invites from anon, authenticated;
revoke delete, truncate on public.zt_space_items from anon, authenticated;
revoke all on public.zt_spaces, public.zt_space_members, public.zt_space_keys,
              public.zt_space_invites, public.zt_space_items from anon;

-- 3. Item writes --------------------------------------------------------------

-- Before a write: the same last-writer-wins and clock guards as vault_items,
-- the writer recorded as author, sealed under the current key, and
-- admin-only items kept admin-only.
create or replace function public.zt_space_items_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_epoch int;
  v_role  text;
begin
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return null;
  end if;
  if new.updated_at > now() + interval '10 minutes' then
    return null;
  end if;
  if tg_op = 'UPDATE' and (new.space_id <> old.space_id or new.item_id <> old.item_id) then
    raise exception using errcode = 'P0001', message = 'zt_space_item_moved';
  end if;
  select key_epoch into v_epoch from public.zt_spaces where id = new.space_id;
  if new.key_epoch <> v_epoch then
    raise exception using errcode = 'P0001', message = 'zt_space_key_stale',
      detail = format('sealed under epoch %s; the space is at %s', new.key_epoch, v_epoch);
  end if;
  v_role := public.zt_space_role(new.space_id);
  if v_role is distinct from 'admin'
     and (new.admin_only or (tg_op = 'UPDATE' and old.admin_only)) then
    raise exception using errcode = 'P0001', message = 'zt_space_admin_only',
      detail = format('item %s', new.item_id);
  end if;
  new.author_id := (select auth.uid());
  new.synced_at := clock_timestamp();
  return new;
end;
$$;
revoke execute on function public.zt_space_items_guard() from public, anon, authenticated;

drop trigger if exists zt_space_items_guard on public.zt_space_items;
create trigger zt_space_items_guard
  before insert or update on public.zt_space_items
  for each row execute function public.zt_space_items_guard();

-- Storage limits per space, like the per-account ones on vault_items:
-- 1 MiB per sealed item, 50 MiB and 100,000 items per space. Deletes and
-- shrinking writes are always allowed.
create or replace function public.zt_space_items_track_usage()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_space public.zt_spaces;
  v_bytes bigint;
  v_count bigint;
begin
  if tg_op = 'DELETE' then
    update public.zt_spaces
       set item_bytes = greatest(item_bytes - coalesce(octet_length(old.data_blob), 0), 0),
           item_count = greatest(item_count - 1, 0)
     where id = old.space_id;
    return null;
  end if;
  v_bytes := coalesce(octet_length(new.data_blob), 0)
           - case when tg_op = 'UPDATE' then coalesce(octet_length(old.data_blob), 0) else 0 end;
  v_count := case when tg_op = 'INSERT' then 1 else 0 end;
  update public.zt_spaces
     set item_bytes = greatest(item_bytes + v_bytes, 0),
         item_count = item_count + v_count
   where id = new.space_id
   returning * into v_space;
  if (v_bytes <= 0 and v_count = 0) or new.deleted then
    return null;
  end if;
  if octet_length(new.data_blob) > 1048576 then
    raise exception using errcode = 'P0001', message = 'zt_item_too_large',
      detail = format('item %s is %s bytes; the limit is 1048576',
                      new.item_id, octet_length(new.data_blob));
  end if;
  if v_space.item_bytes > 52428800 or v_space.item_count > 100000 then
    raise exception using errcode = 'P0001', message = 'zt_storage_full',
      detail = format('space has %s bytes in %s items', v_space.item_bytes, v_space.item_count);
  end if;
  return null;
end;
$$;
revoke execute on function public.zt_space_items_track_usage() from public, anon, authenticated;

drop trigger if exists zt_space_items_track_usage on public.zt_space_items;
create trigger zt_space_items_track_usage
  after insert or update or delete on public.zt_space_items
  for each row execute function public.zt_space_items_track_usage();

-- 4. Members leaving ----------------------------------------------------------

-- After a member is removed (by an admin, by leaving, or because their
-- account was deleted): an empty space is deleted with everything in it; a
-- space left without an admin gets its longest-standing member as admin;
-- otherwise the key must be rotated.
create or replace function public.zt_space_members_after_delete()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.zt_spaces where id = old.space_id) then
    return null;  -- the space itself is being deleted
  end if;
  if not exists (select 1 from public.zt_space_members where space_id = old.space_id) then
    delete from public.zt_spaces where id = old.space_id;
    return null;
  end if;
  if not exists (select 1 from public.zt_space_members
                 where space_id = old.space_id and role = 'admin') then
    update public.zt_space_members set role = 'admin'
     where (space_id, user_id) = (
       select space_id, user_id from public.zt_space_members
        where space_id = old.space_id
        order by added_at, user_id limit 1);
  end if;
  update public.zt_spaces set rotation_needed = true where id = old.space_id;
  return null;
end;
$$;
revoke execute on function public.zt_space_members_after_delete() from public, anon, authenticated;

drop trigger if exists zt_space_members_after_delete on public.zt_space_members;
create trigger zt_space_members_after_delete
  after delete on public.zt_space_members
  for each row execute function public.zt_space_members_after_delete();

-- 5. Functions apps call ------------------------------------------------------

create or replace function public.zt_require_space_admin(p_space uuid)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if public.zt_space_role(p_space) is distinct from 'admin' then
    raise exception using errcode = 'P0001', message = 'zt_not_space_admin';
  end if;
end;
$$;
revoke execute on function public.zt_require_space_admin(uuid) from public, anon, authenticated;

-- A new space with the caller as its only admin, and the caller's copy of
-- the first key. At most 100 spaces created per account.
create or replace function public.zt_create_space(
  p_space uuid, p_app text, p_wrapped_key bytea, p_key_signature bytea)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_me uuid := (select auth.uid());
begin
  if v_me is null then raise exception 'not signed in' using errcode = '42501'; end if;
  if (select count(*) from public.zt_spaces where created_by = v_me) >= 100 then
    raise exception using errcode = 'P0001', message = 'zt_space_limit';
  end if;
  insert into public.zt_spaces (id, app, created_by) values (p_space, p_app, v_me);
  insert into public.zt_space_members (space_id, user_id, role, added_by)
    values (p_space, v_me, 'admin', v_me);
  insert into public.zt_space_keys (space_id, epoch, user_id, wrapped_key, wrapped_by, signature)
    values (p_space, 1, v_me, p_wrapped_key, v_me, p_key_signature);
end;
$$;

-- An invite to [p_space]. The link carries the token; only its hash is
-- stored. Expires after [p_valid_for] (at most 30 days); at most 20 open
-- invites per space.
create or replace function public.zt_create_space_invite(
  p_invite uuid, p_space uuid, p_role text, p_token_hash bytea,
  p_valid_for interval default interval '7 days')
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.zt_require_space_admin(p_space);
  if p_valid_for > interval '30 days' or p_valid_for <= interval '0' then
    raise exception using errcode = 'P0001', message = 'zt_invite_invalid',
      detail = 'an invite is valid for up to 30 days';
  end if;
  if (select count(*) from public.zt_space_invites
      where space_id = p_space and status in ('open', 'answered')
        and expires_at > now()) >= 20 then
    raise exception using errcode = 'P0001', message = 'zt_space_limit';
  end if;
  insert into public.zt_space_invites (id, space_id, created_by, role, token_hash, expires_at)
    values (p_invite, p_space, (select auth.uid()), p_role, p_token_hash, now() + p_valid_for);
end;
$$;

-- The invitee answers with a proof derived from the link's token (never the
-- token itself) and their answer (public identity and name), sealed under a
-- key derived from the token, which the server never sees. Returns the space and
-- the inviter so the invitee's app can check the inviter's key once it can
-- read the space. One answer per invite.
create or replace function public.zt_answer_space_invite(
  p_invite uuid, p_proof bytea, p_answer bytea)
returns json language plpgsql security definer set search_path = '' as $$
declare
  v_me  uuid := (select auth.uid());
  v_inv public.zt_space_invites;
  v_app text;
begin
  if v_me is null then raise exception 'not signed in' using errcode = '42501'; end if;
  select * into v_inv from public.zt_space_invites where id = p_invite for update;
  if not found or v_inv.token_hash <> sha256(p_proof) or v_inv.expires_at <= now()
     or v_inv.status <> 'open' or octet_length(p_answer) > 4096 then
    raise exception using errcode = 'P0001', message = 'zt_invite_invalid';
  end if;
  if exists (select 1 from public.zt_space_members
             where space_id = v_inv.space_id and user_id = v_me) then
    raise exception using errcode = 'P0001', message = 'zt_invite_invalid',
      detail = 'already a member';
  end if;
  update public.zt_space_invites
     set status = 'answered', answered_by = v_me, answered_at = now(), answer = p_answer
   where id = p_invite;
  select app into v_app from public.zt_spaces where id = v_inv.space_id;
  return json_build_object('space_id', v_inv.space_id, 'app', v_app,
                           'role', v_inv.role, 'invited_by', v_inv.created_by);
end;
$$;

-- An admin, having compared the verification code, adds the invitee with
-- their copies of the space keys: p_keys = [{epoch, wrapped_key, signature}]
-- (bytes as standard base64), including the current epoch. Earlier epochs
-- are optional: an app that wants new members to see history wraps them too.
create or replace function public.zt_confirm_space_invite(p_invite uuid, p_keys jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_me    uuid := (select auth.uid());
  v_inv   public.zt_space_invites;
  v_space public.zt_spaces;
  v_key   jsonb;
begin
  select * into v_inv from public.zt_space_invites where id = p_invite for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'zt_invite_invalid';
  end if;
  perform public.zt_require_space_admin(v_inv.space_id);
  if v_inv.status <> 'answered' or v_inv.expires_at <= now() then
    raise exception using errcode = 'P0001', message = 'zt_invite_invalid';
  end if;
  select * into v_space from public.zt_spaces where id = v_inv.space_id for update;
  if (select count(*) from public.zt_space_members where space_id = v_space.id) >= 50 then
    raise exception using errcode = 'P0001', message = 'zt_space_limit';
  end if;
  if jsonb_typeof(p_keys) <> 'array'
     or not exists (select 1 from jsonb_array_elements(p_keys) k
                    where (k ->> 'epoch')::int = v_space.key_epoch)
     or exists (select 1 from jsonb_array_elements(p_keys) k
                where (k ->> 'epoch')::int not between 1 and v_space.key_epoch) then
    raise exception using errcode = 'P0001', message = 'zt_space_keys_mismatch';
  end if;
  insert into public.zt_space_members (space_id, user_id, role, added_by)
    values (v_space.id, v_inv.answered_by, v_inv.role, v_me);
  for v_key in select * from jsonb_array_elements(p_keys) loop
    insert into public.zt_space_keys (space_id, epoch, user_id, wrapped_key, wrapped_by, signature)
      values (v_space.id, (v_key ->> 'epoch')::int, v_inv.answered_by,
              decode(v_key ->> 'wrapped_key', 'base64'), v_me,
              decode(v_key ->> 'signature', 'base64'));
  end loop;
  update public.zt_space_invites set status = 'confirmed' where id = p_invite;
end;
$$;

-- An admin withdraws an invite, answered or not (for example when the
-- verification codes didn't match).
create or replace function public.zt_revoke_space_invite(p_invite uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_space uuid;
begin
  select space_id into v_space from public.zt_space_invites where id = p_invite;
  if v_space is null then
    raise exception using errcode = 'P0001', message = 'zt_invite_invalid';
  end if;
  perform public.zt_require_space_admin(v_space);
  update public.zt_space_invites set status = 'revoked'
   where id = p_invite and status in ('open', 'answered');
end;
$$;

-- A new key epoch: p_keys = [{user_id, wrapped_key, signature}] with exactly
-- one entry per current member. Shared by rotate and remove.
create or replace function public.zt_space_new_epoch(
  p_space uuid, p_new_epoch int, p_keys jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_space public.zt_spaces;
  v_key   jsonb;
begin
  select * into v_space from public.zt_spaces where id = p_space for update;
  if p_new_epoch <> v_space.key_epoch + 1 then
    raise exception using errcode = 'P0001', message = 'zt_space_keys_mismatch',
      detail = format('next epoch is %s', v_space.key_epoch + 1);
  end if;
  if jsonb_typeof(p_keys) <> 'array'
     or jsonb_array_length(p_keys) <> (select count(*) from public.zt_space_members where space_id = p_space)
     or exists (select 1 from public.zt_space_members m
                where m.space_id = p_space
                  and not exists (select 1 from jsonb_array_elements(p_keys) k
                                  where (k ->> 'user_id')::uuid = m.user_id)) then
    raise exception using errcode = 'P0001', message = 'zt_space_keys_mismatch';
  end if;
  for v_key in select * from jsonb_array_elements(p_keys) loop
    insert into public.zt_space_keys (space_id, epoch, user_id, wrapped_key, wrapped_by, signature)
      values (p_space, p_new_epoch, (v_key ->> 'user_id')::uuid,
              decode(v_key ->> 'wrapped_key', 'base64'), (select auth.uid()),
              decode(v_key ->> 'signature', 'base64'));
  end loop;
  update public.zt_spaces set key_epoch = p_new_epoch, rotation_needed = false
   where id = p_space;
end;
$$;
revoke execute on function public.zt_space_new_epoch(uuid, int, jsonb) from public, anon, authenticated;

-- An admin makes a new key for the remaining members (after someone left).
create or replace function public.zt_rotate_space_key(
  p_space uuid, p_new_epoch int, p_keys jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.zt_require_space_admin(p_space);
  perform public.zt_space_new_epoch(p_space, p_new_epoch, p_keys);
end;
$$;

-- An admin removes someone and, in the same step, gives everyone else a new
-- key the removed person never sees. p_keys covers the remaining members.
create or replace function public.zt_remove_space_member(
  p_space uuid, p_user uuid, p_new_epoch int, p_keys jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.zt_require_space_admin(p_space);
  if p_user = (select auth.uid()) then
    raise exception using errcode = 'P0001', message = 'zt_last_admin',
      detail = 'use zt_leave_space to leave';
  end if;
  delete from public.zt_space_members where space_id = p_space and user_id = p_user;
  if not found then
    raise exception using errcode = 'P0001', message = 'zt_space_keys_mismatch',
      detail = 'not a member';
  end if;
  perform public.zt_space_new_epoch(p_space, p_new_epoch, p_keys);
end;
$$;

-- The caller leaves. The space is deleted if nobody is left; otherwise an
-- admin's device rotates the key on its next sync.
create or replace function public.zt_leave_space(p_space uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from public.zt_space_members
   where space_id = p_space and user_id = (select auth.uid());
end;
$$;

create or replace function public.zt_set_space_role(p_space uuid, p_user uuid, p_role text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.zt_require_space_admin(p_space);
  perform 1 from public.zt_spaces where id = p_space for update;
  update public.zt_space_members set role = p_role
   where space_id = p_space and user_id = p_user;
  if not found then
    raise exception using errcode = 'P0001', message = 'zt_space_keys_mismatch',
      detail = 'not a member';
  end if;
  if not exists (select 1 from public.zt_space_members
                 where space_id = p_space and role = 'admin') then
    raise exception using errcode = 'P0001', message = 'zt_last_admin';
  end if;
end;
$$;

-- An admin deletes the space and everything in it, for every member.
create or replace function public.zt_delete_space(p_space uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.zt_require_space_admin(p_space);
  delete from public.zt_spaces where id = p_space;
end;
$$;

do $$
declare f text;
begin
  foreach f in array array[
    'zt_create_space(uuid, text, bytea, bytea)',
    'zt_create_space_invite(uuid, uuid, text, bytea, interval)',
    'zt_answer_space_invite(uuid, bytea, bytea)',
    'zt_confirm_space_invite(uuid, jsonb)',
    'zt_revoke_space_invite(uuid)',
    'zt_rotate_space_key(uuid, int, jsonb)',
    'zt_remove_space_member(uuid, uuid, int, jsonb)',
    'zt_leave_space(uuid)',
    'zt_set_space_role(uuid, uuid, text)',
    'zt_delete_space(uuid)'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end;
$$;

-- 6. Tombstones and live updates ---------------------------------------------

-- The daily purge now covers shared items too (same 180 days).
create or replace function public.zt_purge_tombstones(
  p_older_than interval default interval '180 days')
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  v_count  bigint;
  v_shared bigint;
begin
  if p_older_than < interval '30 days' then
    raise exception 'zt_purge_tombstones: keep tombstones at least 30 days';
  end if;
  delete from public.vault_items
   where deleted
     and synced_at < now() - p_older_than;
  get diagnostics v_count = row_count;
  delete from public.zt_space_items
   where deleted
     and synced_at < now() - p_older_than;
  get diagnostics v_shared = row_count;
  return v_count + v_shared;
end;
$$;
revoke execute on function public.zt_purge_tombstones(interval) from public, anon, authenticated;

-- Realtime respects the read policies above.
alter publication supabase_realtime add table
  public.zt_space_items, public.zt_space_members, public.zt_space_keys,
  public.zt_space_invites, public.zt_spaces;
