-- Fixes from the review of the 2026-11-22 Core changes.

-- Z22: "Keep my account" and the hourly purge can't both win. The purge
-- claims each account just before deleting it; keeping only works while
-- it isn't claimed, and a claimed account is no longer listed as due
-- until the claim is 30 minutes old (a purge that failed half way is
-- finished by the next hourly run).
alter table public.zt_account_deletions
  add column if not exists purging_since timestamptz;

create or replace function public.zt_claim_account_deletion(p_user uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  update public.zt_account_deletions
     set purging_since = now()
   where user_id = p_user
     and delete_after <= now()
     and (purging_since is null or purging_since < now() - interval '30 minutes');
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

create or replace function public.zt_due_account_deletions(p_limit integer default 50)
returns setof uuid language sql stable security definer set search_path = '' as $$
  select user_id from public.zt_account_deletions
   where delete_after <= now()
     and (purging_since is null or purging_since < now() - interval '30 minutes')
   order by delete_after
   limit greatest(1, least(p_limit, 500));
$$;

create or replace function public.zt_cancel_account_deletion()
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  delete from public.zt_account_deletions
   where user_id = (select auth.uid()) and purging_since is null;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

create or replace function public.zt_cancel_account_deletion_by_token(p_token_hash bytea)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  delete from public.zt_account_deletions
   where undo_token_hash = p_token_hash and purging_since is null;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

revoke execute on function public.zt_claim_account_deletion(uuid) from public, anon, authenticated;
grant execute on function public.zt_claim_account_deletion(uuid) to service_role;

-- Z15: the crash groups view took the latest stack with
-- array_agg(frames)[1], which fails on empty or different-length stacks
-- and returns null otherwise. Take the newest row's stack directly.
drop view if exists public.zt_crash_groups;
create view public.zt_crash_groups
with (security_invoker = true) as
select g.*,
       (select r.frames from public.zt_crash_reports r
         where r.app = g.app and r.fingerprint = g.fingerprint
           and r.error_type = g.error_type
         order by r.day desc, r.last_received desc, r.version desc
         limit 1) as frames
  from (select app,
               fingerprint,
               error_type,
               max(message) as message,
               bool_or(uncaught) as uncaught,
               array_agg(distinct version order by version) as versions,
               array_agg(distinct platform order by platform) as platforms,
               sum(occurrences) as occurrences,
               sum(reports) as reports,
               min(day) as first_day,
               max(day) as last_day
          from public.zt_crash_reports
         group by app, fingerprint, error_type) g;
revoke all on table public.zt_crash_groups from public, anon, authenticated;

-- Z15: concurrent reports near the daily cap could all pass the count and
-- go over it. One lock per call makes the check and the insert one step.
create or replace function public.zt_record_crash_report(p jsonb)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_cap constant integer := 5000;
  v_frames text[];
begin
  perform pg_advisory_xact_lock(hashtextextended('zt_record_crash_report', 0));
  if (select count(*) from public.zt_crash_reports
       where last_received = current_date) >= v_cap then
    return false;
  end if;
  v_frames := array(select jsonb_array_elements_text(coalesce(p->'frames', '[]'::jsonb)));
  insert into public.zt_crash_reports as r
    (app, version, platform, day, error_type, message, library, uncaught,
     fingerprint, frames, occurrences)
  values
    (p->>'app', coalesce(p->>'version', ''), p->>'platform', (p->>'day')::date,
     p->>'type', p->>'message', p->>'library', (p->>'uncaught')::boolean,
     p->>'fingerprint', v_frames,
     greatest(1, least(1000, coalesce((p->>'count')::integer, 1))))
  on conflict (app, version, platform, fingerprint, day) do update
    set reports = least(r.reports + 1, 1000000),
        occurrences = least(r.occurrences + excluded.occurrences, 1000000000),
        last_received = current_date;
  return true;
end;
$$;
revoke execute on function public.zt_record_crash_report(jsonb) from public, anon, authenticated;
grant execute on function public.zt_record_crash_report(jsonb) to service_role;
