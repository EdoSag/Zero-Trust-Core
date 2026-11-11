-- Z25: the Plus plan (Edo, 2026-11-11). Hidden (offered = false) until the
-- apps are in the stores and payments exist; until then the owner gives it
-- to beta testers by hand:
--   select public.zt_grant_plan('<user id>', 'plus', now() + interval '1 year', 'beta tester');
-- One plan for every Zero Trust app. Higher limits, not unlimited:
-- 1 GiB and 1,000,000 items of synced data, 20 GiB of attachments.
insert into public.zt_plans
  (id, rank, names, max_item_bytes, max_items, max_attachment_bytes, features, offered)
values
  ('plus', 10, '{"en": "Plus", "he": "פלוס"}', 1073741824, 1000000, 21474836480, '{}', false)
on conflict (id) do nothing;
