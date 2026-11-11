-- ZT Calendar booking pages: two fixes to the free-slot search.
-- 1. Busy times and bookings that just ended still block slots until their
--    buffer has passed (before, a slot inside the buffer opened as soon as
--    the earlier meeting ended).
-- 2. On the day clocks go forward, a start time that doesn't exist locally
--    is no longer offered, and every slot must end by the real end of its
--    working-hours window.
-- zt_book_slot only accepts starts this function offers, so it is fixed too.

create or replace function public.zt_booking_free_slots(p_page public.zt_booking_pages)
returns setof timestamptz language plpgsql stable security definer set search_path = '' as $$
declare
  v_busy  public.zt_booking_busy;
  v_now   timestamptz := now();
  v_until timestamptz;
  v_today date := (now() at time zone p_page.time_zone)::date;
  v_dur   interval := make_interval(mins => p_page.duration_min);
  v_buf   interval := make_interval(mins => p_page.buffer_min);
begin
  if not p_page.active then return; end if;
  select * into v_busy from public.zt_booking_busy where owner = p_page.owner;
  if not found then return; end if;
  v_until := least(v_now + make_interval(days => p_page.horizon_days),
                   v_busy.updated_at + interval '60 days');
  return query
  with taken as (
    select tstzrange(to_timestamp((b ->> 0)::numeric / 1000), to_timestamp((b ->> 1)::numeric / 1000)) as r
      from jsonb_array_elements(v_busy.blocks) b
     where to_timestamp((b ->> 1)::numeric / 1000) > v_now - v_buf
    union all
    select tstzrange(k.starts_at, k.ends_at)
      from public.zt_bookings k
     where k.owner = p_page.owner and k.ends_at > v_now - v_buf
       and (k.status = 'new' or (k.status = 'added' and k.updated_at >= v_busy.updated_at))
  ), candidates as (
    select (v_today + d) + make_interval(mins => t) as local_start,
           ((v_today + d) + make_interval(mins => t)) at time zone p_page.time_zone as s,
           ((v_today + d) + make_interval(mins => (h ->> 1)::int)) at time zone p_page.time_zone as window_end
      from generate_series(0, p_page.horizon_days) d,
           jsonb_array_elements(coalesce(p_page.hours -> extract(isodow from v_today + d)::int::text, '[]'::jsonb)) h,
           generate_series((h ->> 0)::int, (h ->> 1)::int - p_page.duration_min, p_page.step_min) t
  )
  select distinct c.s from candidates c
   -- A start that doesn't exist locally (skipped when clocks go forward)
   -- is not offered, and the meeting must end by the window's real end.
   where (c.s at time zone p_page.time_zone) = c.local_start
     and c.s + v_dur <= c.window_end
     and c.s >= v_now + make_interval(mins => p_page.notice_min)
     and c.s + v_dur <= v_until
     and not exists (select 1 from taken
                      where taken.r && tstzrange(c.s - v_buf, c.s + v_dur + v_buf))
   order by c.s;
end;
$$;
revoke all on function public.zt_booking_free_slots(public.zt_booking_pages) from public, anon, authenticated;
