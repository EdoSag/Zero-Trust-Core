-- K-5: ZT Calendar meeting polls ("Which time works? Vote on 3 times").
--
-- The owner proposes a few times in ZT Calendar and shares a link,
-- https://zerotrust.bz/poll/#<poll id>.<key>. Guests open it, enter a name and
-- mark the times that work. The key is only in the link's fragment (after
-- the #), which browsers never send to a server, so:
--   * the poll (title, times, place) is AES-256-GCM encrypted with that key
--     in the app, and guests' votes are encrypted with it in the browser;
--   * a guest's optional email is additionally sealed to the owner's key
--     (the booking pages' scheme), so other guests can't read it;
--   * the server keeps only ciphertext, how many votes there are and when
--     they came in.
--
-- Guests are not signed in. They reach polls only through the two security
-- definer functions at the end (granted to anon): read one poll with its
-- votes, and add or change their own vote with the token they got when
-- voting. The tables are closed to anon. A poll is gone (and its votes with
-- it) once its expires_at passes; the app sets that to 30 days after the
-- last proposed time.

create table if not exists public.zt_polls (
  id          text primary key check (id ~ '^p[A-Za-z0-9_-]{16,31}$'),
  owner       uuid not null references auth.users(id) on delete cascade,
  sealed      text not null check (char_length(sealed) between 40 and 16000),
  closed      boolean not null default false,
  expires_at  timestamptz not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists zt_polls_owner on public.zt_polls (owner);
create index if not exists zt_polls_expires on public.zt_polls (expires_at);

create or replace function public.zt_polls_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and (new.id is distinct from old.id or new.owner is distinct from old.owner
                           or new.created_at is distinct from old.created_at) then
    raise exception 'a poll keeps its id and owner' using errcode = '42501';
  end if;
  -- At most 30 live polls per account, counted whenever a poll becomes live:
  -- made live, or an expired one moved into the future.
  if new.expires_at > now() and (tg_op = 'INSERT' or old.expires_at <= now())
     and (select count(*) from public.zt_polls
          where owner = new.owner and expires_at > now() and id <> new.id) >= 30 then
    raise exception using errcode = 'P0001', message = 'zt_poll_limit';
  end if;
  if new.expires_at > now() + interval '400 days' then
    raise exception 'a poll lasts at most 400 days' using errcode = '22023';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists zt_polls_guard on public.zt_polls;
create trigger zt_polls_guard before insert or update on public.zt_polls
  for each row execute function public.zt_polls_guard();

create table if not exists public.zt_poll_votes (
  id          uuid primary key default gen_random_uuid(),
  poll_id     text not null references public.zt_polls(id) on delete cascade,
  owner       uuid not null references auth.users(id) on delete cascade,
  sealed      text not null check (char_length(sealed) between 40 and 6000),
  edit_hash   bytea not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists zt_poll_votes_poll on public.zt_poll_votes (poll_id, created_at);
create index if not exists zt_poll_votes_owner on public.zt_poll_votes (owner);

-- Row level security: owners read and remove their polls' votes; guests use
-- the functions below.
alter table public.zt_polls enable row level security;
alter table public.zt_poll_votes enable row level security;

drop policy if exists zt_polls_own on public.zt_polls;
create policy zt_polls_own on public.zt_polls for all to authenticated
  using (owner = (select auth.uid())) with check (owner = (select auth.uid()));
drop policy if exists zt_poll_votes_own_read on public.zt_poll_votes;
create policy zt_poll_votes_own_read on public.zt_poll_votes for select to authenticated
  using (owner = (select auth.uid()));
drop policy if exists zt_poll_votes_own_delete on public.zt_poll_votes;
create policy zt_poll_votes_own_delete on public.zt_poll_votes for delete to authenticated
  using (owner = (select auth.uid()));

revoke all on public.zt_polls, public.zt_poll_votes from anon;
grant select, insert, update, delete on public.zt_polls to authenticated;
revoke insert, update on public.zt_poll_votes from authenticated;
grant select, delete on public.zt_poll_votes to authenticated;

-- Public: one poll and its votes (all ciphertext), or null when there is no
-- such poll or it expired.
create or replace function public.zt_poll(p_poll text)
returns json language plpgsql stable security definer set search_path = '' as $$
declare
  v_poll public.zt_polls;
begin
  select * into v_poll from public.zt_polls where id = p_poll and expires_at > now();
  if not found then return null; end if;
  return json_build_object(
    'id', v_poll.id, 'sealed', v_poll.sealed, 'closed', v_poll.closed,
    'votes', coalesce((select json_agg(json_build_object('id', v.id, 'sealed', v.sealed,
                                                         'updatedAt', v.updated_at)
                                       order by v.created_at)
                         from public.zt_poll_votes v where v.poll_id = v_poll.id), '[]'::json));
end;
$$;

-- Public: add a vote ([p_vote] null) or change one (with its edit token).
-- Returns the vote id and its edit token (only the token's hash is kept).
create or replace function public.zt_poll_vote(p_poll text, p_sealed text,
                                               p_vote uuid default null, p_token text default null)
returns json language plpgsql volatile security definer set search_path = '' as $$
declare
  v_poll  public.zt_polls;
  v_vote  public.zt_poll_votes;
  v_token text := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  v_id    uuid;
begin
  select * into v_poll from public.zt_polls where id = p_poll and expires_at > now();
  if not found then
    raise exception using errcode = 'P0001', message = 'zt_poll_gone';
  end if;
  if v_poll.closed then
    raise exception using errcode = 'P0001', message = 'zt_poll_closed';
  end if;
  if p_sealed is null or char_length(p_sealed) not between 40 and 6000 then
    raise exception using errcode = 'P0001', message = 'zt_poll_invalid';
  end if;
  if p_vote is not null then
    select * into v_vote from public.zt_poll_votes where id = p_vote and poll_id = p_poll for update;
    if not found or p_token is null
       or v_vote.edit_hash is distinct from sha256(convert_to(p_token, 'UTF8')) then
      raise exception using errcode = 'P0001', message = 'zt_poll_invalid';
    end if;
    update public.zt_poll_votes set sealed = p_sealed, updated_at = now() where id = p_vote;
    return json_build_object('id', p_vote, 'editToken', p_token);
  end if;
  perform pg_advisory_xact_lock(hashtextextended('zt_poll:' || p_poll, 0));
  if (select count(*) from public.zt_poll_votes where poll_id = p_poll) >= 100
     or (select count(*) from public.zt_poll_votes
          where poll_id = p_poll and created_at > now() - interval '1 hour') >= 30 then
    raise exception using errcode = 'P0001', message = 'zt_poll_try_later';
  end if;
  insert into public.zt_poll_votes (poll_id, owner, sealed, edit_hash)
  values (p_poll, v_poll.owner, p_sealed, sha256(convert_to(v_token, 'UTF8')))
  returning id into v_id;
  return json_build_object('id', v_id, 'editToken', v_token);
end;
$$;

revoke all on function public.zt_poll(text) from public;
revoke all on function public.zt_poll_vote(text, text, uuid, text) from public;
grant execute on function public.zt_poll(text) to anon, authenticated;
grant execute on function public.zt_poll_vote(text, text, uuid, text) to anon, authenticated;

-- Expired polls are removed (with their votes) by the owner's app; this
-- catches the ones whose owner stopped using it. Runs only if pg_cron is on.
do $$ begin
  if exists (select 1 from pg_catalog.pg_extension where extname = 'pg_cron') then
    perform cron.schedule('zt-polls-expire', '17 3 * * *',
      $cron$delete from public.zt_polls where expires_at < now()$cron$);
  end if;
end $$;
