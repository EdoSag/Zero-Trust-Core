-- Fix: zt_answer_space_invite accepted a NULL proof. sha256(NULL) is NULL, so
-- the comparison was NULL and the "invalid" branch was skipped: a signed-in
-- user who knew an open invite's id could use it up without the link's token
-- and learn its space and inviter. They could not become a member (the admin
-- still compares the verification code and the answer cannot be opened), but
-- the real invitee's link stopped working. NULL proof or answer is now refused
-- and the comparison is null-safe. Same signature, so grants are unchanged.
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
  if not found or p_proof is null or p_answer is null
     or v_inv.token_hash is distinct from sha256(p_proof)
     or v_inv.expires_at <= now() or v_inv.status <> 'open'
     or octet_length(p_answer) > 4096 then
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
