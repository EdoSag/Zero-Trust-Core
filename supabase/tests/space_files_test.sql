-- Runs after 00_supabase_stub.sql and every migration. Files of a shared
-- space (ZT Gallery shared albums): members upload under their own id into
-- space_<id>, every member reads them, nobody else reads or writes them.
insert into auth.users values ('00000000-0000-0000-0000-0000000000f1', 'f1@x.com'),
                              ('00000000-0000-0000-0000-0000000000f2', 'f2@x.com'),
                              ('00000000-0000-0000-0000-0000000000f3', 'f3@x.com');
insert into public.zt_spaces (id, app)
  values ('11111111-2222-3333-4444-555555555555', 'gallery');
insert into public.zt_space_members (space_id, user_id, role)
  values ('11111111-2222-3333-4444-555555555555', '00000000-0000-0000-0000-0000000000f1', 'admin'),
         ('11111111-2222-3333-4444-555555555555', '00000000-0000-0000-0000-0000000000f2', 'member');

set role authenticated;
-- A member uploads into the space folder under their own id.
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f1';
insert into storage.objects (bucket_id, name)
  values ('zt-attachments', '00000000-0000-0000-0000-0000000000f1/space_11111111222233334444555555555555/aa');
do $$ begin
  -- Not under someone else's id, even in a shared space.
  begin
    insert into storage.objects (bucket_id, name)
      values ('zt-attachments', '00000000-0000-0000-0000-0000000000f2/space_11111111222233334444555555555555/ab');
    raise exception 'wrote under another member''s id';
  exception when insufficient_privilege then null;
  end;
  -- Not into a space they are not in.
  begin
    insert into storage.objects (bucket_id, name)
      values ('zt-attachments', '00000000-0000-0000-0000-0000000000f1/space_99999999222233334444555555555555/ac');
    raise exception 'wrote into a space without being a member';
  exception when insufficient_privilege then null;
  end;
  -- A malformed space folder is neither an app folder nor a space.
  begin
    insert into storage.objects (bucket_id, name)
      values ('zt-attachments', '00000000-0000-0000-0000-0000000000f1/space_xyz/ad');
    raise exception 'wrote into a malformed space folder';
  exception when insufficient_privilege then null;
  end;
end $$;

-- The other member reads it but cannot delete it.
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f2';
do $$ begin
  assert (select count(*) from storage.objects
          where name like '%/space_11111111222233334444555555555555/%') = 1,
         'member reads the shared file';
  delete from storage.objects;
end $$;

-- Someone outside the space sees nothing.
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f3';
do $$ begin
  assert (select count(*) from storage.objects) = 0, 'outsider sees nothing';
end $$;

-- After leaving the space, the old member reads nothing either.
reset role;
delete from public.zt_space_members
  where user_id = '00000000-0000-0000-0000-0000000000f2';
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f2';
do $$ begin
  assert (select count(*) from storage.objects) = 0, 'former member sees nothing';
end $$;

-- The uploader still has the file (the other member could not delete it).
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f1';
do $$ begin
  assert (select count(*) from storage.objects
          where name like '00000000-0000-0000-0000-0000000000f1/space_%') = 1,
         'uploader keeps the file';
end $$;
reset role;

-- Leave nothing behind for the tests after this one.
delete from storage.objects;
delete from public.zt_spaces where id = '11111111-2222-3333-4444-555555555555';
delete from auth.users where id in ('00000000-0000-0000-0000-0000000000f1',
                                    '00000000-0000-0000-0000-0000000000f2',
                                    '00000000-0000-0000-0000-0000000000f3');

\echo space_files_test: all checks passed
