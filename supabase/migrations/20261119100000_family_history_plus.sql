-- ZT Family, phase L4: more than 7 days of history is part of Plus.
--
-- Safety (map, check-ins, the safety timer, SOS, 7 days of history) stays
-- free. Plus gets the `family` feature: up to 30 days of history (and, in
-- the app, more than 5 places). The circle's owner needs Plus to choose
-- more than 7 days; a circle keeps its window if the owner's Plus ends
-- (it can still be shortened). Unlimited's '*' already covers it.
-- Safe to run again.

update public.zt_plans
   set features = array(
         select distinct f from unnest(features || array['family']) as f order by f
       )
 where id = 'plus'
   and not ('family' = any(features));

create or replace function public.family_set_history_days(p_space uuid, p_days int)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then
    raise exception 'zt_not_signed_in' using errcode = 'P0001';
  end if;
  if public.zt_space_role(p_space) is distinct from 'admin' then
    raise exception 'zt_not_space_admin' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.zt_spaces where id = p_space and app = 'family') then
    raise exception 'family_not_a_circle' using errcode = 'P0001';
  end if;
  if p_days is null or p_days < 1 or p_days > 30 then
    raise exception 'family_bad_history_days' using errcode = 'P0001';
  end if;
  -- Over 7 days needs Plus, except keeping or shortening a window the
  -- circle already has (an owner whose Plus ended can still shorten it).
  if p_days > 7 and not public.zt_has_feature('family')
     and p_days > coalesce(
       (select s.history_days from public.family_settings s where s.space_id = p_space), 7) then
    raise exception 'family_needs_plus' using errcode = 'P0001';
  end if;
  insert into public.family_settings (space_id, history_days)
    values (p_space, p_days)
  on conflict (space_id) do update
    set history_days = excluded.history_days, updated_at = now();
end;
$$;
revoke execute on function public.family_set_history_days(uuid, int) from public, anon;
grant execute on function public.family_set_history_days(uuid, int) to authenticated;
