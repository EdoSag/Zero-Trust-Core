-- Runs after 00_supabase_stub.sql and every migration. zt-attachments: a
-- user reaches only objects under their own id, in an app folder.
insert into auth.users values ('00000000-0000-0000-0000-0000000000a1', 'a@x.com'),
                              ('00000000-0000-0000-0000-0000000000a2', 'b@x.com');
do $$ begin
  assert (select not public from storage.buckets where id = 'zt-attachments'), 'bucket is private';
end $$;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
insert into storage.objects (bucket_id, name)
  values ('zt-attachments', '00000000-0000-0000-0000-0000000000a1/notes/0123');
do $$ begin
  begin
    insert into storage.objects (bucket_id, name)
      values ('zt-attachments', '00000000-0000-0000-0000-0000000000a2/notes/0123');
    raise exception 'wrote into another user''s folder';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into storage.objects (bucket_id, name)
      values ('zt-attachments', '00000000-0000-0000-0000-0000000000a1/other/0123');
    raise exception 'wrote outside an app folder';
  exception when insufficient_privilege then null;
  end;
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a2';
do $$ begin
  assert (select count(*) from storage.objects) = 0, 'other user sees nothing';
  delete from storage.objects;
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
do $$ begin
  assert (select count(*) from storage.objects) = 1, 'owner sees own file, other user could not delete it';
end $$;
reset role;

\echo attachments_test: all checks passed
