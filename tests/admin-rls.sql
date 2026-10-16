begin;
select set_config('gatherly.test_admin',gen_random_uuid()::text,true);
select set_config('gatherly.test_member',gen_random_uuid()::text,true);
select set_config('gatherly.test_other',gen_random_uuid()::text,true);
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
(current_setting('gatherly.test_admin')::uuid,gen_random_uuid()::text||'@example.invalid',now(),'{}'),
(current_setting('gatherly.test_member')::uuid,gen_random_uuid()::text||'@example.invalid',now(),'{"role":"admin"}'),
(current_setting('gatherly.test_other')::uuid,gen_random_uuid()::text||'@example.invalid',now(),'{}');
insert into public.social_profiles(id,display_name) values(current_setting('gatherly.test_admin')::uuid,'TEST OWNER'),(current_setting('gatherly.test_member')::uuid,'TEST MEMBER'),(current_setting('gatherly.test_other')::uuid,'TEST OTHER');
insert into gatherly_ops.roles(user_id,role) values(current_setting('gatherly.test_admin')::uuid,'admin');
insert into gatherly_ops.ledger(creator_id,kind,amount_minor,reference) values(current_setting('gatherly.test_member')::uuid,'sale',10000,'TEST-credit');
select set_config('request.jwt.claim.sub',current_setting('gatherly.test_member'),true);
set local role authenticated;
do $$begin
 if public.gatherly_role()<>'member' then raise exception 'FAIL metadata escalated member'; end if;
 begin perform public.gatherly_admin('{"action":"overview"}');raise exception 'FAIL member accessed admin';exception when insufficient_privilege then null;end;
 begin insert into gatherly_ops.roles(user_id,role) values(auth.uid(),'admin');raise exception 'FAIL direct role escalation';exception when insufficient_privilege then null;end;
 begin select 1 from gatherly_ops.payouts;raise exception 'FAIL direct financial read';exception when insufficient_privilege then null;end;
end$$;
select public.gatherly_finance('{"action":"save_wallet","address":"TEST-wallet-address-only","network":"TESTNET","asset":"TEST"}');
select set_config('gatherly.test_key',gen_random_uuid()::text,true);
select public.gatherly_finance(jsonb_build_object('action','request_payout','amount_minor',6000,'idempotency_key',current_setting('gatherly.test_key')));
select public.gatherly_finance(jsonb_build_object('action','request_payout','amount_minor',6000,'idempotency_key',current_setting('gatherly.test_key')));
do $$declare b jsonb;begin
 b:=public.gatherly_finance('{"action":"balance"}')->'balance';
 if (b->>'available_minor')::bigint<>4000 or (b->>'reserved_minor')::bigint<>6000 then raise exception 'FAIL duplicate payout or balance';end if;
 begin perform public.gatherly_finance(jsonb_build_object('action','request_payout','amount_minor',5000,'idempotency_key',gen_random_uuid()));raise exception 'FAIL overspend';exception when raise_exception then if sqlerrm='FAIL overspend' then raise;end if;end;
end$$;
select set_config('request.jwt.claim.sub',current_setting('gatherly.test_other'),true);
do $$begin
 if jsonb_array_length(public.gatherly_finance('{"action":"balance"}')->'payouts')<>0 then raise exception 'FAIL payout leaked to other user';end if;
 if (public.gatherly_finance('{"action":"balance"}')->'balance'->>'earned_minor')::bigint<>0 then raise exception 'FAIL earnings leaked';end if;
end$$;
select set_config('request.jwt.claim.sub',current_setting('gatherly.test_admin'),true);
select public.gatherly_admin('{"action":"overview"}');
select public.gatherly_admin('{"action":"users"}');
select public.gatherly_admin('{"action":"finance"}');
select public.gatherly_admin('{"action":"payouts"}');
select public.gatherly_admin('{"action":"reports"}');
select public.gatherly_admin('{"action":"content"}');
select public.gatherly_admin('{"action":"audit"}');
do $$declare p jsonb;begin
 p:=public.gatherly_admin('{"action":"payouts"}')->0;
 begin perform public.gatherly_admin(jsonb_build_object('action','payout_transition','payout_id',p->>'id','expected_status','requested','status','approved','crypto_amount',1,'exchange_rate',1,'note','Invalid quote'));raise exception 'FAIL bad quote';exception when raise_exception then if sqlerrm='FAIL bad quote' then raise;end if;end;
 perform public.gatherly_admin(jsonb_build_object('action','payout_transition','payout_id',p->>'id','expected_status','requested','status','approved','crypto_amount',3,'exchange_rate',20,'note','Test quote'));
 perform public.gatherly_admin(jsonb_build_object('action','payout_transition','payout_id',p->>'id','expected_status','approved','status','processing','note','Test processing'));
 begin perform public.gatherly_admin(jsonb_build_object('action','payout_transition','payout_id',p->>'id','expected_status','processing','status','paid','tx_hash','test-transfer-reference-0001','note','Missing confirmation'));raise exception 'FAIL paid without confirmation';exception when raise_exception then if sqlerrm='FAIL paid without confirmation' then raise;end if;end;
 perform public.gatherly_admin(jsonb_build_object('action','payout_transition','payout_id',p->>'id','expected_status','processing','status','paid','tx_hash','test-transfer-reference-0001','confirm_sent','YES','note','Test confirmed paid'));
 begin perform public.gatherly_admin(jsonb_build_object('action','payout_transition','payout_id',p->>'id','expected_status','processing','status','paid','tx_hash','test-transfer-reference-0001','confirm_sent','YES','note','Duplicate transfer'));raise exception 'FAIL double payout';exception when raise_exception then if sqlerrm='FAIL double payout' then raise;end if;end;
end$$;
select public.gatherly_admin(jsonb_build_object('action','hold','creator_id',current_setting('gatherly.test_member'),'amount_minor',1000,'note','Test hold'));
select public.gatherly_admin(jsonb_build_object('action','suspend','user_id',current_setting('gatherly.test_member'),'suspended',true,'note','Test suspension'));
select set_config('request.jwt.claim.sub',current_setting('gatherly.test_member'),true);
do $$declare b jsonb;begin
 b:=public.gatherly_finance('{"action":"balance"}')->'balance';
 if (b->>'available_minor')::bigint<>3000 or (b->>'paid_minor')::bigint<>6000 then raise exception 'FAIL paid/hold accounting';end if;
 begin insert into public.gatherly_posts(author_id,title,body,status) values(auth.uid(),'Suspended test','Must fail','published');raise exception 'FAIL suspended write';exception when insufficient_privilege then null;end;
end$$;
reset role;
-- Reserved owner cannot claim admin until Supabase verifies the email.
insert into gatherly_ops.owner_enrollment(email) values('gatherly-owner-test@example.invalid');
insert into auth.users(id,email) values(gen_random_uuid(),'gatherly-owner-test@example.invalid');
do $$declare account uuid;begin
 select id into account from auth.users where email='gatherly-owner-test@example.invalid';
 if exists(select 1 from gatherly_ops.roles where user_id=account) then raise exception 'FAIL unverified owner promoted';end if;
 update auth.users set email_confirmed_at=now() where id=account;
 if not exists(select 1 from gatherly_ops.roles where user_id=account and role='admin') then raise exception 'FAIL verified owner not promoted';end if;
end$$;
rollback;
select 'PASS: member isolation, forged-role rejection, private financial data, idempotent reservation, insufficient-funds checks, quote validation, paid confirmation, replay rejection, hold accounting, suspension and verified owner enrollment. All synthetic data rolled back.' as result;
