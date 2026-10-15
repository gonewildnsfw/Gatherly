begin;
select set_config('gatherly.test_a',gen_random_uuid()::text,true);
select set_config('gatherly.test_b',gen_random_uuid()::text,true);
insert into auth.users(id) values(current_setting('gatherly.test_a')::uuid),(current_setting('gatherly.test_b')::uuid);
insert into public.social_profiles(id,display_name) values(current_setting('gatherly.test_a')::uuid,'TEST A'),(current_setting('gatherly.test_b')::uuid,'TEST B');
select set_config('request.jwt.claim.sub',current_setting('gatherly.test_a'),true);
set local role authenticated;
insert into public.gatherly_posts(author_id,title,body,kind,price_minor,status) values(auth.uid(),'RLS test private','Private test','photo',100,'draft');
insert into public.gatherly_posts(author_id,title,body,status) values(auth.uid(),'RLS test public','Public test','published');
insert into public.gatherly_saved(user_id,post_id) select auth.uid(),id from public.gatherly_posts where title='RLS test public';
do $$ begin
 begin
  insert into public.gatherly_posts(author_id,title,body,kind,price_minor,status) values(auth.uid(),'Invalid','Must fail','photo',100,'published');
  raise exception 'TEST FAILED paid listing published';
 exception when insufficient_privilege then null; end;
 begin
  insert into public.gatherly_posts(author_id,title,body) values(current_setting('gatherly.test_b')::uuid,'Invalid','Must fail');
  raise exception 'TEST FAILED impersonation allowed';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('gatherly.test_b'),true);
do $$ begin
 if exists(select 1 from public.gatherly_posts where title='RLS test private') then raise exception 'TEST FAILED draft leaked'; end if;
 if exists(select 1 from public.gatherly_saved where user_id=current_setting('gatherly.test_a')::uuid) then raise exception 'TEST FAILED saved leaked'; end if;
 if not exists(select 1 from public.gatherly_posts where title='RLS test public') then raise exception 'TEST FAILED public missing'; end if;
 delete from public.gatherly_posts where author_id=current_setting('gatherly.test_a')::uuid;
 if found then raise exception 'TEST FAILED cross-user delete'; end if;
 update public.social_profiles set display_name='Tampered' where id=current_setting('gatherly.test_a')::uuid;
 if found then raise exception 'TEST FAILED cross-user profile edit'; end if;
end $$;
reset role;
rollback;
select 'PASS: paid publication blocked; ownership enforced; drafts and saved posts private; cross-user modification denied; all test data rolled back' as result;
