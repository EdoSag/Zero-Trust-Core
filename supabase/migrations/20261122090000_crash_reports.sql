-- Z15: where opt-in crash reports go (Edo's pick, 2026-11-22: our own
-- table behind the `crash-report` edge function, nothing third-party).
--
-- A report carries no account, device, IP or time of day (see
-- ZtCrashReport in zero_trust_core). Reports of the same bug on the same
-- UTC day and app version are merged into one row that only counts them,
-- so the table can't grow faster than the number of distinct bugs.
--
-- Only the project owner reads it (dashboard or SQL editor). Phones never
-- write here directly: the edge function checks each report and calls
-- zt_record_crash_report with the service role.

create table if not exists public.zt_crash_reports (
  app text not null check (app ~ '^[a-z_]{1,24}$'),
  version text not null check (version ~ '^[0-9A-Za-z.+_-]{0,40}$'),
  platform text not null
    check (platform in ('android', 'ios', 'web', 'linux', 'macos', 'windows', 'fuchsia')),
  day date not null,
  error_type text not null check (length(error_type) between 1 and 83),
  message text check (length(message) <= 163),
  library text check (length(library) <= 63),
  uncaught boolean not null,
  fingerprint text not null check (fingerprint ~ '^[0-9a-f]{16}$'),
  frames text[] not null check (cardinality(frames) <= 25),
  -- Reports received for this row, and the crashes they counted (a phone
  -- that saved the same bug 5 times sends one report with count 5).
  reports integer not null default 1 check (reports >= 1),
  occurrences integer not null default 1 check (occurrences >= 1),
  first_received date not null default current_date,
  last_received date not null default current_date,
  primary key (app, version, platform, fingerprint, day)
);

alter table public.zt_crash_reports enable row level security;
-- No policies: nobody but the owner and the service role sees or writes it.
revoke all on table public.zt_crash_reports from public, anon, authenticated;

-- One row per bug for the owner: newest first.
create or replace view public.zt_crash_groups
with (security_invoker = true) as
select app,
       fingerprint,
       error_type,
       max(message) as message,
       bool_or(uncaught) as uncaught,
       array_agg(distinct version order by version) as versions,
       array_agg(distinct platform order by platform) as platforms,
       sum(occurrences) as occurrences,
       sum(reports) as reports,
       min(day) as first_day,
       max(day) as last_day,
       (array_agg(frames order by day desc))[1] as frames
  from public.zt_crash_reports
 group by app, fingerprint, error_type;
revoke all on table public.zt_crash_groups from public, anon, authenticated;

-- Called by the edge function only. Returns false when the daily cap is
-- reached (a flood of made-up reports can't fill the database).
create or replace function public.zt_record_crash_report(p jsonb)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_cap constant integer := 5000;
  v_frames text[];
begin
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

-- Kept 90 days, then removed (daily at 03:47 UTC where pg_cron exists).
create or replace function public.zt_purge_crash_reports()
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  v_count bigint;
begin
  delete from public.zt_crash_reports where day < current_date - 90;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function public.zt_purge_crash_reports() from public, anon, authenticated;

do $outer$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('zt-purge-crash-reports', '47 3 * * *',
                          'select public.zt_purge_crash_reports()');
  end if;
end;
$outer$;
