-- Member onboarding and payout methods. Existing payout snapshots are unchanged.
alter table gatherly_ops.wallets drop constraint wallets_provider_check;
alter table gatherly_ops.payouts drop constraint payouts_provider_check;
alter table gatherly_ops.wallets add column method text not null default 'crypto' check(method in ('crypto','bank')), add column bank_details jsonb;
alter table gatherly_ops.payouts add column method text not null default 'crypto' check(method in ('crypto','bank')), add column bank_details jsonb;
alter table gatherly_ops.wallets drop constraint wallets_address_check;
alter table gatherly_ops.wallets add constraint wallets_address_check check(length(address) between 4 and 250 and (method='bank' or length(address)>=8));
alter table gatherly_ops.payouts drop constraint payouts_check;
alter table gatherly_ops.payouts add constraint payouts_quote_check check(method='bank' or status not in ('approved','processing','paid') or (crypto_amount is not null and exchange_rate is not null));
create table gatherly_ops.member_details(
 user_id uuid primary key references auth.users(id) on delete cascade,
 birth_date date not null, country text not null check(length(country) between 2 and 80),
 mobile text not null check(length(mobile) between 7 and 30),address text not null default '' check(length(address)<=500),
 is_creator boolean not null default false,share_name boolean not null default false,
 completed_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
alter table gatherly_ops.member_details enable row level security;
revoke all on gatherly_ops.member_details from public,anon,authenticated;
create policy no_direct_api_access on gatherly_ops.member_details for all to anon,authenticated using(false) with check(false);
alter table public.social_profiles add column public_name text not null default '', add column avatar_path text not null default '' check(length(avatar_path)<=250);
-- These fields are changed only by the private account operation, not arbitrary profile writes.
create function gatherly_ops.guard_profile_fields() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in ('authenticated','anon') and (new.public_name is distinct from old.public_name or new.avatar_path is distinct from old.avatar_path) then raise exception 'Use account settings to change public identity'; end if;
 return new;
end $$;
create trigger guard_profile_fields before update on public.social_profiles for each row execute function gatherly_ops.guard_profile_fields();
create function gatherly_ops.account_dispatch(request jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); op text:=request->>'action'; dob date; creator boolean; sharing boolean; first_n text:=btrim(request->>'first_name'); last_n text:=btrim(request->>'last_name'); target uuid;
begin
 if actor is null or not exists(select 1 from auth.users where id=actor and email_confirmed_at is not null and (banned_until is null or banned_until<now())) then raise exception 'Verified sign-in required' using errcode='42501'; end if;
 if op='get' then return jsonb_build_object('details',(select to_jsonb(d) from gatherly_ops.member_details d where user_id=actor),'identity',(select to_jsonb(i) from gatherly_ops.payout_identity i where creator_id=actor),'profile',(select to_jsonb(p) from public.social_profiles p where id=actor),'payout_ready',exists(select 1 from gatherly_ops.wallets where creator_id=actor and provider_confirmed_at is not null)); end if;
 if op='admin_member' then
  if not gatherly_ops.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
  target:=(request->>'user_id')::uuid;
  insert into gatherly_ops.audit(actor_id,action,target_id) values(actor,'private_member_details_viewed',target::text);
  return jsonb_build_object('details',(select to_jsonb(d) from gatherly_ops.member_details d where user_id=target),'identity',(select to_jsonb(i) from gatherly_ops.payout_identity i where creator_id=target),'wallet',(select to_jsonb(w) from gatherly_ops.wallets w where creator_id=target));
 end if;
 if not gatherly_ops.can_participate() then raise exception 'Account suspended'; end if;
 if op='save' then
  dob:=(request->>'birth_date')::date;creator:=coalesce((request->>'is_creator')::boolean,false);sharing:=coalesce((request->>'share_name')::boolean,false);
  if dob is null or dob>current_date-interval '18 years' or dob<current_date-interval '120 years' then raise exception 'You must be at least 18. Enter your correct date of birth.'; end if;
  if coalesce(length(first_n),0) not between 1 and 80 or coalesce(length(last_n),0) not between 1 and 80 then raise exception 'Enter your name and surname'; end if;
  if coalesce(length(btrim(request->>'country')),0) not between 2 and 80 or coalesce(length(btrim(request->>'mobile')),0) not between 7 and 30 or coalesce(request->>'mobile','') !~ '^\+?[0-9 ()-]+$' then raise exception 'Enter your country and mobile number with country code'; end if;
  if creator and coalesce(length(btrim(request->>'address')),0)<8 then raise exception 'Creators must provide their full address'; end if;
  if request->>'privacy_ack' is distinct from 'YES' then raise exception 'Acknowledge administrator access to private details'; end if;
  insert into gatherly_ops.payout_identity(creator_id,first_name,last_name) values(actor,first_n,last_n) on conflict(creator_id) do update set first_name=excluded.first_name,last_name=excluded.last_name,updated_at=now();
  insert into gatherly_ops.member_details(user_id,birth_date,country,mobile,address,is_creator,share_name) values(actor,dob,btrim(request->>'country'),btrim(request->>'mobile'),btrim(coalesce(request->>'address','')),creator,sharing) on conflict(user_id) do update set birth_date=excluded.birth_date,country=excluded.country,mobile=excluded.mobile,address=excluded.address,is_creator=excluded.is_creator,share_name=excluded.share_name,updated_at=now();
  update public.social_profiles set public_name=case when sharing then first_n||' '||last_n else '' end where id=actor;
 elsif op='save_profile' then
  if coalesce(length(btrim(request->>'display_name')),0) not between 1 and 80 or length(coalesce(request->>'bio',''))>500 then raise exception 'Enter a display name and bio of up to 500 characters'; end if;
  update public.social_profiles set display_name=btrim(request->>'display_name'),bio=coalesce(request->>'bio','') where id=actor;
 elsif op='avatar' then
  if request->>'path' not like actor::text||'/%' or not exists(select 1 from storage.objects where bucket_id='gatherly-avatars' and name=request->>'path' and owner_id=actor::text) then raise exception 'Upload your own profile photo first'; end if;
  update public.social_profiles set avatar_path=request->>'path' where id=actor;
 else raise exception 'Unknown account action'; end if;
 insert into gatherly_ops.audit(actor_id,action,target_id) values(actor,'account_'||op,actor::text);
 return jsonb_build_object('saved',true);
end $$;
revoke all on function gatherly_ops.account_dispatch(jsonb) from public,anon;
grant execute on function gatherly_ops.account_dispatch(jsonb) to authenticated;
create function public.gatherly_account(request jsonb) returns jsonb language sql security invoker set search_path='' as $$ select gatherly_ops.account_dispatch(request) $$;
revoke all on function public.gatherly_account(jsonb) from public,anon;
grant execute on function public.gatherly_account(jsonb) to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('gatherly-avatars','gatherly-avatars',true,2097152,array['image/jpeg','image/png','image/webp']);
create policy avatar_insert on storage.objects for insert to authenticated with check(bucket_id='gatherly-avatars' and (storage.foldername(name))[1]=(select auth.uid())::text and (select gatherly_ops.can_participate()));
create policy avatar_owner_select on storage.objects for select to authenticated using(bucket_id='gatherly-avatars' and owner_id=(select auth.uid())::text);
create policy avatar_owner_delete on storage.objects for delete to authenticated using(bucket_id='gatherly-avatars' and owner_id=(select auth.uid())::text);
create or replace function gatherly_ops.member_finance(request jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); op text:=request->>'action'; wallet gatherly_ops.wallets%rowtype; amount bigint; existing_id uuid; key uuid; result jsonb;
begin
 if actor is null or not exists(select 1 from auth.users where id=actor and email_confirmed_at is not null and (banned_until is null or banned_until<now())) then raise exception 'Verified sign-in required' using errcode='42501'; end if;
 if op='balance' then
  return jsonb_build_object('balance',gatherly_ops.balance(actor),'wallet',(select to_jsonb(w) from gatherly_ops.wallets w where creator_id=actor),'payouts',(select coalesce(jsonb_agg(x),'[]') from (select * from gatherly_ops.payouts where creator_id=actor order by created_at desc limit 100) x),'identity',(select to_jsonb(i) from gatherly_ops.payout_identity i where creator_id=actor),'collection_live',false);
 end if;
 if not gatherly_ops.can_participate() then raise exception 'This account is suspended' using errcode='42501'; end if;
 if op='save_identity' then raise exception 'Update your name in Account settings';
 elsif op='save_wallet' then
  if request->>'confirm_owner' is distinct from 'YES' then raise exception 'Confirm this payout destination belongs to you'; end if;
  if not exists(select 1 from auth.sessions where user_id=actor and id=nullif(auth.jwt()->>'session_id','')::uuid and created_at>now()-interval '10 minutes') then raise exception 'Sign in again before changing payout details'; end if;
  if not exists(select 1 from gatherly_ops.member_details where user_id=actor and is_creator and length(address)>=8) then raise exception 'Complete your creator account details first'; end if;
  if request->>'method'='bank' then
   if request->>'bank_country' is distinct from 'ZA' then raise exception 'Bank payouts currently support South African ZAR accounts'; end if;
   if coalesce(length(btrim(request->>'account_holder')),0) not between 2 and 160 or coalesce(length(btrim(request->>'bank_name')),0) not between 2 and 100 or coalesce(request->>'account_number','') !~ '^[0-9]{4,30}$' or coalesce(request->>'branch_code','') !~ '^[0-9]{6}$' or coalesce(request->>'account_type','') not in ('cheque','savings','transmission') then raise exception 'Enter valid account holder, bank, account number, 6-digit branch code and account type'; end if;
   insert into gatherly_ops.wallets(creator_id,method,provider,provider_confirmed_at,address,network,asset,memo,bank_details) values(actor,'bank','bank',now(),request->>'account_number','ZA-BANK','ZAR','',jsonb_build_object('account_holder',btrim(request->>'account_holder'),'bank_name',btrim(request->>'bank_name'),'account_number',request->>'account_number','branch_code',request->>'branch_code','account_type',request->>'account_type','country','ZA','currency','ZAR')) on conflict(creator_id) do update set method=excluded.method,provider=excluded.provider,provider_confirmed_at=now(),address=excluded.address,network=excluded.network,asset=excluded.asset,memo='',bank_details=excluded.bank_details,updated_at=now();
   insert into gatherly_ops.audit(actor_id,action,target_id) values(actor,'bank_destination_updated',actor::text);
   return jsonb_build_object('saved',true);
  end if;
  if request->>'method' is distinct from 'crypto' then raise exception 'Choose bank or crypto'; end if;
  insert into gatherly_ops.wallets(creator_id,provider,provider_confirmed_at,address,network,asset,memo) values(actor,'crypto',now(),btrim(request->>'address'),upper(btrim(request->>'network')),upper(btrim(request->>'asset')),btrim(coalesce(request->>'memo',''))) on conflict(creator_id) do update set method='crypto',bank_details=null,provider=excluded.provider,provider_confirmed_at=excluded.provider_confirmed_at,address=excluded.address,network=excluded.network,asset=excluded.asset,memo=excluded.memo,updated_at=now();
  insert into gatherly_ops.audit(actor_id,action,target_id,details) values(actor,'wallet_updated',actor::text,jsonb_build_object('network',request->>'network','asset',request->>'asset'));
  return jsonb_build_object('saved',true);
 elsif op='request_payout' then
  perform pg_advisory_xact_lock(hashtextextended(actor::text,0));
  amount:=(request->>'amount_minor')::bigint;key:=(request->>'idempotency_key')::uuid;
  select id into existing_id from gatherly_ops.payouts where idempotency_key=key and creator_id=actor and amount_minor=amount;
  if existing_id is not null then return jsonb_build_object('id',existing_id); end if;
  if amount is null or amount<100 or key is null or amount>(gatherly_ops.balance(actor)->>'available_minor')::bigint then raise exception 'Amount exceeds your available balance or is below R1'; end if;
  if not exists(select 1 from gatherly_ops.member_details where user_id=actor and is_creator and length(address)>=8) then raise exception 'Complete your creator account details before requesting a payout'; end if;
  select * into wallet from gatherly_ops.wallets where creator_id=actor;
  if not found or wallet.provider_confirmed_at is null then raise exception 'Save and confirm your payout destination before requesting a payout'; end if;
  insert into gatherly_ops.payouts(creator_id,amount_minor,provider,address,network,asset,memo,idempotency_key,method,bank_details) values(actor,amount,wallet.provider,wallet.address,wallet.network,wallet.asset,wallet.memo,key,wallet.method,wallet.bank_details) returning id into existing_id;
  insert into gatherly_ops.audit(actor_id,action,target_id,details) values(actor,'payout_requested',existing_id::text,jsonb_build_object('amount_minor',amount));
  return jsonb_build_object('id',existing_id);
 else raise exception 'Unknown finance action'; end if;
end $$;

create or replace function gatherly_ops.admin_dispatch(request jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare op text:=request->>'action'; target uuid; actor uuid:=auth.uid(); result jsonb; item gatherly_ops.payouts%rowtype; amount bigint; prev text; v_note text:=btrim(coalesce(request->>'note','')); quote numeric; rate numeric;
begin
 if not gatherly_ops.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
 if op='overview' then
  select jsonb_build_object(
   'users',(select count(*) from public.social_profiles),
   'new_users_7d',(select count(*) from public.social_profiles where created_at>now()-interval '7 days'),
   'signed_in_7d',(select count(*) from auth.users u join public.social_profiles p on p.id=u.id where u.last_sign_in_at>now()-interval '7 days'),
   'unconfirmed_accounts',(select count(*) from auth.users where email_confirmed_at is null),
   'posts',(select count(*) from public.gatherly_posts where status='published'),
   'drafts',(select count(*) from public.gatherly_posts where status='draft'),
   'hidden_posts',(select count(*) from public.gatherly_posts where status='hidden'),
   'comments',(select count(*) from public.gatherly_comments),
   'open_reports',(select count(*) from public.gatherly_reports r where not exists(select 1 from gatherly_ops.report_cases c where c.report_id=r.id)),
   'payout_requests',(select count(*) from gatherly_ops.payouts where status in ('requested','approved','processing')),
   'gross_sales_minor',(select coalesce(sum(gross_minor),0) from gatherly_ops.orders where status='paid'),
   'commission_minor',(select coalesce(sum(commission_minor),0) from gatherly_ops.orders where status='paid'),
   'provider_fees_minor',(select coalesce(sum(provider_fee_minor),0) from gatherly_ops.orders where status='paid'),
   'refunds_minor',(select coalesce(sum(gross_minor),0) from gatherly_ops.orders where status='refunded'),
   'creator_earnings_minor',(select coalesce(sum(amount_minor),0) from gatherly_ops.ledger),
   'payouts_paid_minor',(select coalesce(sum(amount_minor),0) from gatherly_ops.payouts where status='paid'),
   'pending_payout_minor',(select coalesce(sum(amount_minor),0) from gatherly_ops.payouts where status in ('requested','approved','processing')),
   'storage_bytes',(select coalesce(sum((metadata->>'size')::bigint),0) from storage.objects where bucket_id='gatherly-private'),
   'payments_live',false,'uploads_live',false,'currency','ZAR',
   'signups_30d',(select coalesce(jsonb_agg(x),'[]') from (select date_trunc('day',created_at)::date as signup_date,count(*) as users from public.social_profiles where created_at>now()-interval '30 days' group by 1 order by 1) x)
  ) into result;
 elsif op='users' then
  select coalesce(jsonb_agg(x),'[]') into result from (
   select u.id,u.email,u.email_confirmed_at,u.created_at,u.last_sign_in_at,p.display_name,
    case when r.user_id is not null then 'admin' else 'member' end role,coalesce(m.suspended,false) suspended,m.reason
   from auth.users u left join public.social_profiles p on p.id=u.id left join gatherly_ops.roles r on r.user_id=u.id left join gatherly_ops.member_controls m on m.user_id=u.id
   order by u.created_at desc limit 200 offset least(greatest(coalesce((request->>'offset')::int,0),0),100000)
  ) x;
 elsif op='finance' then
  select jsonb_build_object(
   'creators',(select coalesce(jsonb_agg(x),'[]') from (select p.id,p.display_name,u.email,gatherly_ops.balance(p.id) balance from public.social_profiles p join auth.users u on u.id=p.id where exists(select 1 from gatherly_ops.ledger l where l.creator_id=p.id) or exists(select 1 from public.gatherly_posts g where g.author_id=p.id and g.kind<>'post') order by p.created_at desc limit 200) x),
   'orders',(select coalesce(jsonb_agg(x),'[]') from (select * from gatherly_ops.orders order by created_at desc limit 200) x),
   'ledger',(select coalesce(jsonb_agg(x),'[]') from (select * from gatherly_ops.ledger order by created_at desc limit 200) x),
   'holds',(select coalesce(jsonb_agg(x),'[]') from (select * from gatherly_ops.holds order by created_at desc limit 200) x)
  ) into result;
 elsif op='payouts' then
  select coalesce(jsonb_agg(x),'[]') into result from (select p.*,s.display_name,u.email from gatherly_ops.payouts p join auth.users u on u.id=p.creator_id left join public.social_profiles s on s.id=p.creator_id order by p.created_at desc limit 200) x;
 elsif op='reports' then
  select coalesce(jsonb_agg(x),'[]') into result from (select r.*,p.title,p.body,p.author_id,p.status post_status,coalesce(c.status,'open') review_status,c.note review_note from public.gatherly_reports r left join public.gatherly_posts p on p.id=r.post_id left join gatherly_ops.report_cases c on c.report_id=r.id order by r.created_at desc limit 200) x;
 elsif op='content' then
  select coalesce(jsonb_agg(x),'[]') into result from (select p.*,s.display_name from public.gatherly_posts p left join public.social_profiles s on s.id=p.author_id order by p.created_at desc limit 200) x;
 elsif op='audit' then
  select coalesce(jsonb_agg(x),'[]') into result from (select * from gatherly_ops.audit order by created_at desc,id desc limit 200) x;
 elsif op='suspend' then
  target:=(request->>'user_id')::uuid;
  if exists(select 1 from gatherly_ops.roles where user_id=target) then raise exception 'Administrator accounts cannot be suspended here'; end if;
  if char_length(v_note)<3 or char_length(v_note)>500 then raise exception 'A reason of 3–500 characters is required'; end if;
  insert into gatherly_ops.member_controls(user_id,suspended,reason) values(target,(request->>'suspended')::boolean,v_note) on conflict(user_id) do update set suspended=excluded.suspended,reason=excluded.reason,updated_at=now();
  result:=jsonb_build_object('saved',true);
 elsif op='moderate_post' then
  target:=(request->>'post_id')::uuid;
  if char_length(v_note)<3 or char_length(v_note)>500 then raise exception 'A moderation reason is required'; end if;
  select status into prev from public.gatherly_posts where id=target for update;
  if prev is null then raise exception 'Post not found'; end if;
  if request->>'status'='published' then
   update public.gatherly_posts set status='published' where id=target and kind='post' and price_minor=0;
   if not found then raise exception 'Paid listings cannot be published while commerce is inactive'; end if;
  elsif request->>'status'='hidden' then update public.gatherly_posts set status='hidden' where id=target;
  else raise exception 'Invalid moderation status'; end if;
  result:=jsonb_build_object('saved',true,'previous_status',prev);
 elsif op='review_report' then
  target:=(request->>'report_id')::uuid;
  if request->>'status' not in ('resolved','dismissed') or char_length(v_note)<3 or char_length(v_note)>500 then raise exception 'Choose a status and add a reason'; end if;
  insert into gatherly_ops.report_cases(report_id,status,note,reviewer_id) values(target,request->>'status',v_note,actor) on conflict(report_id) do update set status=excluded.status,note=excluded.note,reviewer_id=actor,reviewed_at=now();
  result:=jsonb_build_object('saved',true);
 elsif op='hold' then
  target:=(request->>'creator_id')::uuid;amount:=(request->>'amount_minor')::bigint;
  perform pg_advisory_xact_lock(hashtextextended(target::text,0));
  if amount<=0 or amount>(gatherly_ops.balance(target)->>'available_minor')::bigint or char_length(v_note)<3 or char_length(v_note)>500 then raise exception 'Invalid hold amount or reason'; end if;
  insert into gatherly_ops.holds(creator_id,amount_minor,reason) values(target,amount,v_note);
  result:=jsonb_build_object('saved',true);
 elsif op='release_hold' then
  target:=(request->>'hold_id')::uuid;
  if char_length(v_note)<3 or char_length(v_note)>500 then raise exception 'A release reason is required'; end if;
  update gatherly_ops.holds set active=false where id=target and active;
  if not found then raise exception 'Hold not active'; end if;
  result:=jsonb_build_object('saved',true);
 elsif op='payout_transition' then
  target:=(request->>'payout_id')::uuid;
  select * into item from gatherly_ops.payouts where id=target;
  if not found then raise exception 'Payout not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended(item.creator_id::text,0));
  select * into item from gatherly_ops.payouts where id=target for update;
  if item.status is distinct from (request->>'expected_status') then raise exception 'Payout changed; refresh before continuing'; end if;
  if char_length(v_note)<3 or char_length(v_note)>500 then raise exception 'An operator note is required'; end if;
  if request->>'status'='approved' and item.status='requested' then
   if (gatherly_ops.balance(item.creator_id)->>'available_minor')::bigint<0 then raise exception 'Creator balance requires reconciliation'; end if;
   if item.method='bank' then
    update gatherly_ops.payouts set status='approved',note=v_note where id=target;
   else
   quote:=(request->>'crypto_amount')::numeric;rate:=(request->>'exchange_rate')::numeric;
   if quote is null or rate is null or quote<=0 or rate<=0 or abs(round(quote*rate*100)-item.amount_minor)>1 then raise exception 'Crypto quote and ZAR exchange rate do not match the requested amount'; end if;
   update gatherly_ops.payouts set status='approved',crypto_amount=quote,exchange_rate=rate,network_fee_crypto=coalesce((request->>'network_fee_crypto')::numeric,0),note=v_note where id=target;
   end if;
  elsif request->>'status'='processing' and item.status='approved' then
   if (gatherly_ops.balance(item.creator_id)->>'available_minor')::bigint<0 then raise exception 'Creator balance requires reconciliation'; end if;
   update gatherly_ops.payouts set status='processing',note=v_note where id=target;
  elsif request->>'status'='paid' and item.status='processing' then
   if (request->>'confirm_sent') is distinct from 'YES' or length(btrim(coalesce(request->>'tx_hash','')))<(case when item.method='bank' then 6 else 16 end) or length(request->>'tx_hash')>250 then raise exception 'Confirm the transfer and provide a valid transaction reference'; end if;
   update gatherly_ops.payouts set status='paid',tx_hash=btrim(request->>'tx_hash'),paid_at=now(),note=v_note where id=target;
  elsif request->>'status'='rejected' and item.status in ('requested','approved') then
   update gatherly_ops.payouts set status='rejected',note=v_note where id=target;
  else raise exception 'Invalid payout transition; processing transfers require reconciliation'; end if;
  update gatherly_ops.payouts set updated_at=now() where id=target;
  result:=jsonb_build_object('saved',true);
 else raise exception 'Unknown administrator action'; end if;
 insert into gatherly_ops.audit(actor_id,action,target_id,details) values(actor,op,coalesce(target::text,''),case when op in ('overview','users','finance','payouts','reports','content','audit') then '{}'::jsonb else request-'action' end);
 return result;
end $$;
create or replace function gatherly_ops.commerce_dispatch(request jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare op text:=request->>'action'; actor uuid:=(request->>'actor')::uuid; listing uuid:=(request->>'listing_id')::uuid; item public.gatherly_posts%rowtype; media gatherly_ops.media%rowtype; ord gatherly_ops.orders%rowtype; result jsonb; platform bigint;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'Server access required' using errcode='42501'; end if;
 if actor is not null and not exists(select 1 from auth.users where id=actor and email_confirmed_at is not null and (banned_until is null or banned_until<now())) then raise exception 'Verified account required'; end if;
 if actor is not null and exists(select 1 from gatherly_ops.member_controls where user_id=actor and suspended) then raise exception 'Account suspended'; end if;
 if op in ('reserve_media','pending_media','verify_media','publish','access','reserve_order') then
  select * into item from public.gatherly_posts where id=listing for update;
  if not found then raise exception 'Listing not found'; end if;
 end if;
 if op='reserve_media' then
  if actor is null or item.author_id<>actor or item.status<>'draft' or item.kind not in ('photo','video') then raise exception 'Own photo/video draft required'; end if;
  if (item.kind='photo' and request->>'mime' not like 'image/%') or (item.kind='video' and request->>'mime' not like 'video/%') then raise exception 'File type does not match listing'; end if;
  perform pg_advisory_xact_lock(hashtextextended(actor::text,1));
  if exists(select 1 from gatherly_ops.media where listing_id=listing) then raise exception 'This draft already has a reserved file; create a new draft to replace it'; end if;
  if (select coalesce(sum(size_bytes),0) from gatherly_ops.media where creator_id=actor)+(request->>'size_bytes')::bigint>104857600 then raise exception 'Creator media limit is 100 MB'; end if;
  insert into gatherly_ops.media(listing_id,creator_id,path,mime,size_bytes) values(listing,actor,actor::text||'/'||listing::text||'/'||gen_random_uuid()::text,request->>'mime',(request->>'size_bytes')::bigint) returning to_jsonb(gatherly_ops.media.*) into result;
 elsif op='pending_media' then
  if actor is null or item.author_id<>actor or item.status<>'draft' then raise exception 'Own draft required'; end if;
  select to_jsonb(m) into result from gatherly_ops.media m where listing_id=listing and creator_id=actor;
  if result is null then raise exception 'No reserved upload'; end if;
 elsif op='verify_media' then
  if actor is null or item.author_id<>actor or item.status<>'draft' then raise exception 'Own draft required'; end if;
  update gatherly_ops.media set verified=true where listing_id=listing returning to_jsonb(gatherly_ops.media.*) into result;
 elsif op='publish' then
  if actor is null or not exists(select 1 from gatherly_ops.roles where user_id=actor and role='admin') then raise exception 'Admin review required'; end if;
  if request->>'confirm_review' is distinct from 'YES' or item.kind not in ('photo','video') or item.price_minor<100 then raise exception 'Review photo/video rights and content before publishing'; end if;
  if not exists(select 1 from gatherly_ops.media where listing_id=listing and verified) then raise exception 'Verified media upload required'; end if;
  update public.gatherly_posts set status='published' where id=listing;
  update gatherly_ops.media set reviewed_by=actor where listing_id=listing;
  result:=jsonb_build_object('published',true);
 elsif op='access' then
  if actor is null or not (item.author_id=actor or exists(select 1 from gatherly_ops.roles where user_id=actor) or exists(select 1 from gatherly_ops.entitlements where buyer_id=actor and listing_id=listing and not revoked)) then raise exception 'Purchase required' using errcode='42501'; end if;
  if item.status='hidden' and not exists(select 1 from gatherly_ops.roles where user_id=actor) then raise exception 'Content unavailable'; end if;
  select to_jsonb(m) into result from gatherly_ops.media m where listing_id=listing and verified;
  if result is null then raise exception 'Media not ready'; end if;
 elsif op='reserve_order' then
  if actor is null or item.author_id=actor or item.status<>'published' or item.kind not in ('photo','video') then raise exception 'Listing unavailable'; end if;
  if not exists(select 1 from gatherly_ops.media where listing_id=listing and verified and reviewed_by is not null) then raise exception 'Media not ready'; end if;
  if not exists(select 1 from gatherly_ops.wallets where creator_id=item.author_id and provider_confirmed_at is not null) or not exists(select 1 from gatherly_ops.member_details where user_id=item.author_id and is_creator and length(address)>=8) then raise exception 'Creator must complete payout setup'; end if;
  perform pg_advisory_xact_lock(hashtextextended(actor::text,2));
  select * into ord from gatherly_ops.orders where buyer_id=actor and idempotency_key=(request->>'idempotency_key')::uuid;
  if found then
   if ord.listing_id<>listing then raise exception 'Idempotency key belongs to another listing'; end if;
   return jsonb_build_object('order',to_jsonb(ord),'created',false);
  end if;
  if exists(select 1 from gatherly_ops.entitlements where buyer_id=actor and listing_id=listing and not revoked) then raise exception 'Already purchased'; end if;
  if exists(select 1 from gatherly_ops.orders where buyer_id=actor and listing_id=listing and status='pending') then raise exception 'An invoice already exists; open Purchases or contact support for reconciliation'; end if;
  if (select count(*) from gatherly_ops.orders where buyer_id=actor and created_at>now()-interval '1 hour')>=10 then raise exception 'Checkout request limit reached'; end if;
  platform:=round(item.price_minor::numeric*1500/10000);
  insert into gatherly_ops.orders(buyer_id,creator_id,listing_id,status,gross_minor,commission_minor,idempotency_key) values(actor,item.author_id,listing,'pending',item.price_minor,platform,(request->>'idempotency_key')::uuid) returning * into ord;
  result:=jsonb_build_object('order',to_jsonb(ord),'created',true);
 elsif op='attach_invoice' then
  update gatherly_ops.orders set provider_invoice_id=request->>'invoice_id',invoice_url=request->>'invoice_url' where id=(request->>'order_id')::uuid and status='pending' and provider_invoice_id is null returning to_jsonb(gatherly_ops.orders.*) into result;
  if result is null then raise exception 'Order requires reconciliation'; end if;
 elsif op='get_order' then
  select to_jsonb(o) into result from gatherly_ops.orders o where id=(request->>'order_id')::uuid;
 elsif op in ('settle','refund') then
  select * into ord from gatherly_ops.orders where id=(request->>'order_id')::uuid for update;
  if not found or ord.provider_invoice_id is distinct from request->>'invoice_id' or ord.gross_minor is distinct from (request->>'gross_minor')::bigint or ord.currency is distinct from request->>'currency' or nullif(request->>'payment_id','') is null then raise exception 'Payment snapshot mismatch'; end if;
  if ord.provider_payment_id is not null and ord.provider_payment_id<>request->>'payment_id' then raise exception 'Payment reference mismatch'; end if;
  if op='settle' then
   if ord.status in ('paid','refunded') then return jsonb_build_object('granted',ord.status='paid','duplicate',true); end if;
   if ord.status<>'pending' then raise exception 'Order requires reconciliation'; end if;
   update gatherly_ops.orders set status='paid',provider_payment_id=request->>'payment_id',paid_at=now() where id=ord.id;
   insert into gatherly_ops.entitlements(order_id,buyer_id,listing_id) values(ord.id,ord.buyer_id,ord.listing_id);
   insert into gatherly_ops.ledger(creator_id,order_id,kind,amount_minor,reference) values(ord.creator_id,ord.id,'sale',ord.gross_minor-ord.commission_minor,'sale:'||ord.id::text);
   result:=jsonb_build_object('granted',true);
  else
   if ord.status='refunded' then return jsonb_build_object('refunded',true,'duplicate',true); end if;
   update gatherly_ops.entitlements set revoked=true where order_id=ord.id;
   if ord.status='paid' then insert into gatherly_ops.ledger(creator_id,order_id,kind,amount_minor,reference) values(ord.creator_id,ord.id,'refund',-(ord.gross_minor-ord.commission_minor),'refund:'||ord.id::text); end if;
   update gatherly_ops.orders set status='refunded',provider_payment_id=request->>'payment_id' where id=ord.id;
   result:=jsonb_build_object('refunded',true);
  end if;
 elsif op='purchases' then
  if actor is null then raise exception 'Sign in required'; end if;
  select coalesce(jsonb_agg(x),'[]') into result from (select o.id,o.listing_id,o.status,o.gross_minor,o.invoice_url,o.created_at,p.title,exists(select 1 from gatherly_ops.entitlements e where e.order_id=o.id and not e.revoked) has_access from gatherly_ops.orders o left join public.gatherly_posts p on p.id=o.listing_id where o.buyer_id=actor order by o.created_at desc limit 100) x;
 else raise exception 'Unknown commerce action'; end if;
 insert into gatherly_ops.audit(actor_id,action,target_id,details) values(actor,'commerce_'||op,coalesce(listing::text,request->>'order_id'),jsonb_build_object('success',true));
 return result;
end $$;
create or replace function gatherly_ops.payout_directory(request jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; term text:=lower(left(btrim(coalesce(request->>'search','')),160)); page_offset int:=least(greatest(coalesce((request->>'offset')::int,0),0),100000);
begin
 if not gatherly_ops.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
 select coalesce(jsonb_agg(x),'[]'::jsonb) into result from (
  select u.id,u.email,p.display_name,i.first_name,i.last_name,
   gatherly_ops.balance(u.id) balance,
   (select jsonb_build_object('method',w.method,'provider',w.provider,'asset',w.asset,'network',w.network,'last_four',right(w.address,4),'updated_at',w.updated_at) from gatherly_ops.wallets w where w.creator_id=u.id) wallet,
   exists(select 1 from gatherly_ops.member_details where user_id=u.id) setup_complete,
   (select coalesce(jsonb_agg(t),'[]'::jsonb) from (select id,status,amount_minor,method,created_at from gatherly_ops.payouts where creator_id=u.id order by created_at desc limit 100) t) payouts
  from auth.users u join public.social_profiles p on p.id=u.id
  left join gatherly_ops.payout_identity i on i.creator_id=u.id
  where term='' or position(term in lower(concat_ws(' ',u.email,p.display_name,i.first_name,i.last_name)))>0
  order by p.created_at desc,u.id limit 100 offset page_offset
 ) x;
 insert into gatherly_ops.audit(actor_id,action,details) values(auth.uid(),'payout_directory_viewed',jsonb_build_object('result_count',jsonb_array_length(result)));
 return result;
end $$;
