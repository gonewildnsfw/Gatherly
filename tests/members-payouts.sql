begin;
-- Run inside a rollback-only transaction; no real members or funds are changed.
select set_config('gatherly.member',gen_random_uuid()::text,true),set_config('gatherly.stranger',gen_random_uuid()::text,true),set_config('gatherly.operator',gen_random_uuid()::text,true),set_config('gatherly.session',gen_random_uuid()::text,true);
insert into auth.users(id,email,email_confirmed_at) select current_setting('gatherly.'||x)::uuid,gen_random_uuid()::text||'@example.invalid',now() from unnest(array['member','stranger','operator']) x;
insert into public.social_profiles(id,display_name) select current_setting('gatherly.'||x)::uuid,'Rollback '||x from unnest(array['member','stranger','operator']) x;
insert into gatherly_ops.roles(user_id,role) values(current_setting('gatherly.operator')::uuid,'admin');
insert into auth.sessions(id,user_id,created_at,updated_at) values(current_setting('gatherly.session')::uuid,current_setting('gatherly.member')::uuid,now(),now());
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('gatherly.member'),'role','authenticated','session_id',current_setting('gatherly.session'))::text,true);
set local role authenticated;
do $$declare r jsonb;begin
 begin perform public.gatherly_account('{"action":"admin_member"}');raise exception 'FAIL member read admin details';exception when insufficient_privilege then null;end;
 begin perform public.gatherly_account('{"action":"save","birth_date":"2020-01-01"}');raise exception 'FAIL underage accepted';exception when raise_exception then if sqlerrm='FAIL underage accepted' then raise;end if;end;
 perform public.gatherly_account('{"action":"save","first_name":"Private","last_name":"Member","birth_date":"1990-01-01","country":"South Africa","mobile":"+27000000000","address":"123 Rollback Street","is_creator":true,"share_name":false,"privacy_ack":"YES"}');
 if (select public_name from public.social_profiles where id=auth.uid())<>'' then raise exception 'FAIL legal name public by default';end if;
 begin perform * from gatherly_ops.member_details;raise exception 'FAIL direct private access';exception when insufficient_privilege then null;end;
 perform public.gatherly_finance('{"action":"save_wallet","method":"bank","bank_country":"ZA","account_holder":"Private Member","bank_name":"Test Bank","account_number":"123456789","branch_code":"123456","account_type":"savings","confirm_owner":"YES"}');
 r:=public.gatherly_finance('{"action":"balance"}');if r->'wallet'->>'method'<>'bank' then raise exception 'FAIL bank not saved';end if;
end $$;
reset role;
insert into gatherly_ops.ledger(creator_id,kind,amount_minor,reference) values(current_setting('gatherly.member')::uuid,'sale',10000,'rollback-member-'||gen_random_uuid());
set local role authenticated;
do $$declare r jsonb;k uuid:=gen_random_uuid();begin
 r:=public.gatherly_finance(jsonb_build_object('action','request_payout','amount_minor',5000,'idempotency_key',k));perform set_config('gatherly.payout',r->>'id',true);
 if public.gatherly_finance(jsonb_build_object('action','request_payout','amount_minor',5000,'idempotency_key',k))<>r then raise exception 'FAIL payout retry not idempotent';end if;
 perform public.gatherly_finance('{"action":"save_wallet","method":"crypto","asset":"BTC","network":"BITCOIN","address":"test-wallet-address","confirm_owner":"YES"}');
 r:=public.gatherly_finance('{"action":"balance"}');if r->'wallet'->>'method'<>'crypto' or r->'wallet'->'bank_details'<>'null'::jsonb then raise exception 'FAIL method switch';end if;
 if r->'payouts'->0->>'method'<>'bank' or r->'payouts'->0->'bank_details'->>'account_number'<>'123456789' then raise exception 'FAIL payout snapshot mutated';end if;
end$$;
reset role;
update auth.sessions set created_at=now()-interval '1 day' where id=current_setting('gatherly.session')::uuid;
set local role authenticated;
do $$begin
 begin perform public.gatherly_finance('{"action":"save_wallet","method":"crypto","asset":"BTC","network":"BITCOIN","address":"test-wallet-address","confirm_owner":"YES"}');raise exception 'FAIL stale session changed payout';exception when raise_exception then if sqlerrm<>'Sign in again before changing payout details' then raise;end if;end;
end$$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('gatherly.stranger'),'role','authenticated')::text,true);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.gatherly_account(jsonb_build_object('action','get','user_id',current_setting('gatherly.member')));if r->'details'<>'null'::jsonb then raise exception 'FAIL stranger read details';end if;
 begin perform public.gatherly_payout_directory('{}');raise exception 'FAIL stranger read directory';exception when insufficient_privilege then null;end;
end$$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('gatherly.operator'),'role','authenticated')::text,true);
set local role authenticated;
do $$declare r jsonb;p uuid:=current_setting('gatherly.payout')::uuid;begin
 r:=public.gatherly_account(jsonb_build_object('action','admin_member','user_id',current_setting('gatherly.member')));if r->'identity'->>'first_name'<>'Private' then raise exception 'FAIL admin lookup';end if;
 r:=public.gatherly_payout_directory('{"search":"Private Member"}');if jsonb_array_length(r)<>1 or r->0->'wallet' ? 'address' then raise exception 'FAIL directory search or masking';end if;
 perform public.gatherly_admin(jsonb_build_object('action','payout_transition','payout_id',p,'expected_status','requested','status','approved','note','Rollback approved'));
 perform public.gatherly_admin(jsonb_build_object('action','payout_transition','payout_id',p,'expected_status','approved','status','processing','note','Rollback processing'));
 perform public.gatherly_admin(jsonb_build_object('action','payout_transition','payout_id',p,'expected_status','processing','status','paid','note','Rollback recorded','tx_hash','TEST-REFERENCE','confirm_sent','YES'));
end$$;
reset role;
do $$begin
 if (select status from gatherly_ops.payouts where id=current_setting('gatherly.payout')::uuid)<>'paid' then raise exception 'FAIL bank payout not paid';end if;
 if (gatherly_ops.balance(current_setting('gatherly.member')::uuid)->>'available_minor')::bigint<>5000 then raise exception 'FAIL incorrect remaining balance';end if;
 if not exists(select 1 from gatherly_ops.audit where actor_id=current_setting('gatherly.operator')::uuid and action='private_member_details_viewed') then raise exception 'FAIL reveal not audited';end if;
end$$;

rollback;
