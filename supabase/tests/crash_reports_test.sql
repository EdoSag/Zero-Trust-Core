-- Z15 crash reports: merged per bug and day, hidden from app users, capped.
\set ON_ERROR_STOP 1
delete from public.zt_crash_reports;

create function pg_temp.crash(p_count int default 1, p_version text default '1.0.0+1')
returns jsonb language sql as $$
  select jsonb_build_object(
    'app', 'notes', 'version', p_version, 'platform', 'android',
    'day', current_date::text, 'type', 'TypeError',
    'message', 'Null check operator used on a null value',
    'uncaught', true, 'fingerprint', '0123456789abcdef', 'count', p_count,
    'frames', jsonb_build_array('main (package:notes/main.dart:1:1)'));
$$;

do $$ begin
  assert public.zt_record_crash_report(pg_temp.crash(1)), 'first report stored';
  assert public.zt_record_crash_report(pg_temp.crash(4)), 'same bug merged';
  assert public.zt_record_crash_report(pg_temp.crash(1, '1.0.1+2')), 'new version, new row';
  assert (select count(*) from public.zt_crash_reports) = 2, 'two rows';
  assert (select occurrences from public.zt_crash_reports where version = '1.0.0+1') = 5,
    'counts added';
  assert (select reports from public.zt_crash_reports where version = '1.0.0+1') = 2,
    'reports counted';
  assert (select occurrences from public.zt_crash_groups) = 6, 'one group per bug';
end $$;

-- Bad values are refused by the table itself.
do $$ begin
  begin
    perform public.zt_record_crash_report(pg_temp.crash() || '{"app": "Bad App"}');
    assert false, 'bad app id accepted';
  exception when check_violation then null;
  end;
  begin
    perform public.zt_record_crash_report(pg_temp.crash() || '{"fingerprint": "zz"}');
    assert false, 'bad fingerprint accepted';
  exception when check_violation then null;
  end;
  -- A huge count is clamped.
  perform public.zt_record_crash_report(pg_temp.crash(99999, '2.0.0'));
  assert (select occurrences from public.zt_crash_reports where version = '2.0.0') = 1000,
    'count clamped to 1000';
end $$;

-- App users can neither read nor write it, nor call the function.
set role authenticated;
do $$ begin
  begin
    perform count(*) from public.zt_crash_reports;
    assert false, 'authenticated can read crash reports';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.zt_record_crash_report(pg_temp.crash());
    assert false, 'authenticated can call zt_record_crash_report';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
set role anon;
do $$ begin
  begin
    perform count(*) from public.zt_crash_groups;
    assert false, 'anon can read crash groups';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- Old rows are purged after 90 days.
insert into public.zt_crash_reports (app, version, platform, day, error_type, uncaught, fingerprint, frames)
values ('notes', '0.1.0', 'android', current_date - 91, 'StateError', true, 'fedcba9876543210', '{}');
do $$ begin
  assert public.zt_purge_crash_reports() = 1, 'one old row purged';
  assert (select count(*) from public.zt_crash_reports where day < current_date - 90) = 0, 'gone';
end $$;
delete from public.zt_crash_reports;

\echo crash_reports_test: all checks passed
