-- Calendar Planner, phase R6 (Edo, 2026-11-18): the automatic Planner in
-- ZT Calendar is part of Plus. "Find a time for a task" stays free and
-- needs no feature. The apps check `planner` on the phone (the Planner
-- never talks to a server); Unlimited's '*' already covers it.
-- Safe to run twice.
update public.zt_plans
   set features = array(
         select distinct f from unnest(features || array['planner']) as f order by f
       )
 where id = 'plus'
   and not ('planner' = any(features));
