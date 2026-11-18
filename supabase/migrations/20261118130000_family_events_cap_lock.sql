-- ZT Family: the hourly cap on history events could be passed by two
-- requests sent together, because each counted before the other committed.
-- The guard now takes a lock per member and circle before it counts, so the
-- second request counts after the first has committed.
-- Safe to run again.

create or replace function public.family_events_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_recent bigint;
begin
  perform pg_advisory_xact_lock(
    hashtextextended('family_events:' || new.space_id::text || ':' || new.user_id::text, 0));
  select count(*) into v_recent from public.family_events e
   where e.space_id = new.space_id and e.user_id = new.user_id
     and e.sent_at > now() - interval '1 hour';
  if v_recent >= 1200 then
    raise exception 'family_too_many_events' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke execute on function public.family_events_guard() from public, anon, authenticated;
