-- Z25: the Unlimited plan (Edo, 2026-11-18). Above Plus, never sold and
-- never offered: the project owner gives it by hand, to their own account
-- and to anyone else they choose:
--   select public.zt_grant_plan('<user id>', 'unlimited', null, 'owner');
-- A grant with no end date stays until the owner removes it. Store events
-- never touch manual grants, and the highest-ranked plan wins, so buying
-- or cancelling Plus on the same account changes nothing.
--
-- What it means:
--   * No storage limit: every limit is 9007199254740991, the largest whole
--     number every client reads exactly (2^53 - 1, about 8 million GiB).
--     The apps show "no limit" from 2^50 bytes up.
--   * Every feature: the plan's features are '*', which zt_has_feature()
--     now treats as "all of them", including features added later. Nothing
--     needs to be re-granted when a new paid feature ships.
-- The 1 MiB cap per synced item stays, as on every plan: it protects sync,
-- not storage.
--
-- Clients still cannot write zt_plans or zt_subscriptions, or call
-- zt_grant_plan, so nobody can give this plan to themselves.
insert into public.zt_plans
  (id, rank, names, max_item_bytes, max_items, max_attachment_bytes, features, offered)
values
  ('unlimited', 1000, '{"en": "Unlimited", "he": "ללא הגבלה"}',
   9007199254740991, 9007199254740991, 9007199254740991, '{*}', false)
on conflict (id) do nothing;

-- Same as before, plus the '*' feature.
create or replace function public.zt_has_feature(p_feature text)
returns boolean language sql stable set search_path = '' as $$
  select coalesce(
    (select p_feature = any (p.features) or '*' = any (p.features)
       from public.zt_plans p
      where p.id = public.zt_plan_for((select auth.uid()))),
    false);
$$;
revoke execute on function public.zt_has_feature(text) from public, anon;
grant execute on function public.zt_has_feature(text) to authenticated;
