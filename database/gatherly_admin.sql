-- Gatherly operations. Sensitive records stay outside the exposed public schema.
create schema if not exists gatherly_ops;
revoke all on schema gatherly_ops from public,anon,authenticated;
grant usage on schema gatherly_ops to authenticated;

create table gatherly_ops.roles(user_id uuid primary key references auth.users(id) on delete cascade,role text not null check(role='admin'),created_at timestamptz not null default now());
create table gatherly_ops.member_controls(user_id uuid primary key references auth.users(id) on delete cascade,suspended boolean not null default false,reason text not null default '',updated_at timestamptz not null default now());
create table gatherly_ops.audit(id bigint generated always as identity primary key,actor_id uuid references auth.users(id) on delete set null,action text not null,target_id text,details jsonb not null default '{}',created_at timestamptz not null default now());
create table gatherly_ops.report_cases(report_id uuid primary key references public.gatherly_reports(id) on delete cascade,status text not null check(status in ('resolved','dismissed')),note text not null,reviewer_id uuid not null references auth.users(id),reviewed_at timestamptz not null default now());
create table gatherly_ops.orders(
 id uuid primary key default gen_random_uuid(),buyer_id uuid not null references auth.users(id),creator_id uuid not null references auth.users(id),listing_id uuid references public.gatherly_posts(id) on delete set null,
 provider_payment_id text unique,provider_invoice_id text,status text not null check(status in ('pending','paid','partially_paid','failed','expired','refunded')),
 gross_minor bigint not null check(gross_minor>0),commission_minor bigint not null check(commission_minor>=0 and commission_minor<=gross_minor),provider_fee_minor bigint not null default 0 check(provider_fee_minor>=0),currency text not null default 'ZAR' check(currency='ZAR'),created_at timestamptz not null default now(),paid_at timestamptz
);
create table gatherly_ops.ledger(
 id uuid primary key default gen_random_uuid(),creator_id uuid not null references auth.users(id),order_id uuid references gatherly_ops.orders(id),kind text not null check(kind in ('sale','refund','fee')),amount_minor bigint not null check(amount_minor<>0),currency text not null default 'ZAR' check(currency='ZAR'),reference text not null unique,created_at timestamptz not null default now()
);
create table gatherly_ops.wallets(creator_id uuid primary key references auth.users(id),address text not null check(length(address) between 8 and 250),network text not null check(length(network) between 2 and 40),asset text not null check(length(asset) between 2 and 20),memo text not null default '' check(length(memo)<=100),updated_at timestamptz not null default now());
create table gatherly_ops.holds(id uuid primary key default gen_random_uuid(),creator_id uuid not null references auth.users(id),amount_minor bigint not null check(amount_minor>0),reason text not null,active boolean not null default true,created_at timestamptz not null default now());
create table gatherly_ops.payouts(
 id uuid primary key default gen_random_uuid(),creator_id uuid not null references auth.users(id),amount_minor bigint not null check(amount_minor>=100),currency text not null default 'ZAR' check(currency='ZAR'),
 status text not null default 'requested' check(status in ('requested','approved','processing','paid','rejected')),
 address text not null,network text not null,asset text not null,memo text not null default '',crypto_amount numeric(30,12) check(crypto_amount>0),exchange_rate numeric(30,12) check(exchange_rate>0),network_fee_crypto numeric(30,12) not null default 0 check(network_fee_crypto>=0),
 tx_hash text,note text not null default '',idempotency_key uuid not null unique,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),paid_at timestamptz,
 check(status not in ('approved','processing','paid') or (crypto_amount is not null and exchange_rate is not null)),check(status<>'paid' or (tx_hash is not null and paid_at is not null))
);
create unique index payout_unique_transfer on gatherly_ops.payouts(network,tx_hash) where tx_hash is not null;
create index ops_orders_creator on gatherly_ops.orders(creator_id,created_at desc);
create index ops_orders_buyer on gatherly_ops.orders(buyer_id);
create index ops_orders_listing on gatherly_ops.orders(listing_id);
create index ops_ledger_creator on gatherly_ops.ledger(creator_id);
create index ops_ledger_order on gatherly_ops.ledger(order_id);
create index ops_payout_creator on gatherly_ops.payouts(creator_id,status);
create index ops_holds_creator on gatherly_ops.holds(creator_id) where active;
create index ops_audit_actor on gatherly_ops.audit(actor_id,created_at desc);
create index ops_cases_reviewer on gatherly_ops.report_cases(reviewer_id);
-- No direct API permissions for sensitive operations tables, including admins.
alter table gatherly_ops.roles enable row level security;
alter table gatherly_ops.member_controls enable row level security;
alter table gatherly_ops.audit enable row level security;
alter table gatherly_ops.report_cases enable row level security;
alter table gatherly_ops.orders enable row level security;
alter table gatherly_ops.ledger enable row level security;
alter table gatherly_ops.wallets enable row level security;
alter table gatherly_ops.holds enable row level security;
alter table gatherly_ops.payouts enable row level security;
revoke all on all tables in schema gatherly_ops from public,anon,authenticated;
revoke all on all sequences in schema gatherly_ops from public,anon,authenticated;
create policy no_direct_api_access on gatherly_ops.roles for all to anon,authenticated using(false) with check(false);
create policy no_direct_api_access on gatherly_ops.member_controls for all to anon,authenticated using(false) with check(false);
create policy no_direct_api_access on gatherly_ops.audit for all to anon,authenticated using(false) with check(false);
create policy no_direct_api_access on gatherly_ops.report_cases for all to anon,authenticated using(false) with check(false);
create policy no_direct_api_access on gatherly_ops.orders for all to anon,authenticated using(false) with check(false);
create policy no_direct_api_access on gatherly_ops.ledger for all to anon,authenticated using(false) with check(false);
create policy no_direct_api_access on gatherly_ops.wallets for all to anon,authenticated using(false) with check(false);
create policy no_direct_api_access on gatherly_ops.holds for all to anon,authenticated using(false) with check(false);
create policy no_direct_api_access on gatherly_ops.payouts for all to anon,authenticated using(false) with check(false);


create function gatherly_ops.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from gatherly_ops.roles r join auth.users u on u.id=r.user_id where r.user_id=auth.uid() and r.role='admin' and u.email_confirmed_at is not null and (u.banned_until is null or u.banned_until<now()))
$$;
create function gatherly_ops.can_participate() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not exists(select 1 from gatherly_ops.member_controls where user_id=auth.uid() and suspended)
$$;
revoke all on function gatherly_ops.is_admin(),gatherly_ops.can_participate() from public,anon;
grant execute on function gatherly_ops.is_admin(),gatherly_ops.can_participate() to authenticated;
create function public.gatherly_role() returns text language sql stable security invoker set search_path='' as $$ select case when gatherly_ops.is_admin() then 'admin' else 'member' end $$;
revoke all on function public.gatherly_role() from public,anon;
grant execute on function public.gatherly_role() to authenticated;

-- Existing member writes also respect suspension; admins cannot suspend themselves.
create policy ops_post_participation on public.gatherly_posts as restrictive for insert to authenticated with check((select gatherly_ops.can_participate()));
create policy ops_comment_participation on public.gatherly_comments as restrictive for insert to authenticated with check((select gatherly_ops.can_participate()));
create policy ops_like_participation on public.gatherly_likes as restrictive for insert to authenticated with check((select gatherly_ops.can_participate()));
create policy ops_follow_participation on public.gatherly_follows as restrictive for insert to authenticated with check((select gatherly_ops.can_participate()));
create policy ops_profile_participation on public.social_profiles as restrictive for update to authenticated using((select gatherly_ops.can_participate())) with check((select gatherly_ops.can_participate()));

create function gatherly_ops.balance(creator uuid) returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('earned_minor',e.total,'reserved_minor',p.reserved,'paid_minor',p.paid,'held_minor',h.total,'available_minor',e.total-p.reserved-p.paid-h.total,'currency','ZAR')
 from (select coalesce(sum(amount_minor),0) total from gatherly_ops.ledger where creator_id=creator) e,
 (select coalesce(sum(amount_minor) filter(where status in ('requested','approved','processing')),0) reserved,coalesce(sum(amount_minor) filter(where status='paid'),0) paid from gatherly_ops.payouts where creator_id=creator) p,
 (select coalesce(sum(amount_minor),0) total from gatherly_ops.holds where creator_id=creator and active) h
$$;
revoke all on function gatherly_ops.balance(uuid) from public,anon,authenticated;

create function gatherly_ops.admin_dispatch(request jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
   quote:=(request->>'crypto_amount')::numeric;rate:=(request->>'exchange_rate')::numeric;
   if quote is null or rate is null or quote<=0 or rate<=0 or abs(round(quote*rate*100)-item.amount_minor)>1 then raise exception 'Crypto quote and ZAR exchange rate do not match the requested amount'; end if;
   update gatherly_ops.payouts set status='approved',crypto_amount=quote,exchange_rate=rate,network_fee_crypto=coalesce((request->>'network_fee_crypto')::numeric,0),note=v_note where id=target;
  elsif request->>'status'='processing' and item.status='approved' then
   if (gatherly_ops.balance(item.creator_id)->>'available_minor')::bigint<0 then raise exception 'Creator balance requires reconciliation'; end if;
   update gatherly_ops.payouts set status='processing',note=v_note where id=target;
  elsif request->>'status'='paid' and item.status='processing' then
   if (request->>'confirm_sent') is distinct from 'YES' or length(btrim(coalesce(request->>'tx_hash','')))<16 or length(request->>'tx_hash')>250 then raise exception 'Confirm the transfer and provide a valid transaction reference'; end if;
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
revoke all on function gatherly_ops.admin_dispatch(jsonb) from public,anon;
grant execute on function gatherly_ops.admin_dispatch(jsonb) to authenticated;
create function public.gatherly_admin(request jsonb) returns jsonb language sql security invoker set search_path='' as $$select gatherly_ops.admin_dispatch(request)$$;
revoke all on function public.gatherly_admin(jsonb) from public,anon;
grant execute on function public.gatherly_admin(jsonb) to authenticated;

create function gatherly_ops.member_finance(request jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); op text:=request->>'action'; wallet gatherly_ops.wallets%rowtype; amount bigint; existing_id uuid; key uuid; result jsonb;
begin
 if actor is null then raise exception 'Sign in required' using errcode='42501'; end if;
 if op='balance' then
  return jsonb_build_object('balance',gatherly_ops.balance(actor),'wallet',(select to_jsonb(w) from gatherly_ops.wallets w where creator_id=actor),'payouts',(select coalesce(jsonb_agg(x),'[]') from (select * from gatherly_ops.payouts where creator_id=actor order by created_at desc limit 100) x),'collection_live',false);
 end if;
 if not gatherly_ops.can_participate() then raise exception 'This account is suspended' using errcode='42501'; end if;
 if op='save_wallet' then
  insert into gatherly_ops.wallets(creator_id,address,network,asset,memo) values(actor,btrim(request->>'address'),upper(btrim(request->>'network')),upper(btrim(request->>'asset')),btrim(coalesce(request->>'memo',''))) on conflict(creator_id) do update set address=excluded.address,network=excluded.network,asset=excluded.asset,memo=excluded.memo,updated_at=now();
  insert into gatherly_ops.audit(actor_id,action,target_id,details) values(actor,'wallet_updated',actor::text,jsonb_build_object('network',request->>'network','asset',request->>'asset'));
  return jsonb_build_object('saved',true);
 elsif op='request_payout' then
  perform pg_advisory_xact_lock(hashtextextended(actor::text,0));
  amount:=(request->>'amount_minor')::bigint;key:=(request->>'idempotency_key')::uuid;
  select id into existing_id from gatherly_ops.payouts where idempotency_key=key and creator_id=actor and amount_minor=amount;
  if existing_id is not null then return jsonb_build_object('id',existing_id); end if;
  if amount is null or amount<100 or key is null or amount>(gatherly_ops.balance(actor)->>'available_minor')::bigint then raise exception 'Amount exceeds your available balance or is below R1'; end if;
  select * into wallet from gatherly_ops.wallets where creator_id=actor;
  if not found then raise exception 'Add your payout wallet first'; end if;
  insert into gatherly_ops.payouts(creator_id,amount_minor,address,network,asset,memo,idempotency_key) values(actor,amount,wallet.address,wallet.network,wallet.asset,wallet.memo,key) returning id into existing_id;
  insert into gatherly_ops.audit(actor_id,action,target_id,details) values(actor,'payout_requested',existing_id::text,jsonb_build_object('amount_minor',amount));
  return jsonb_build_object('id',existing_id);
 else raise exception 'Unknown finance action'; end if;
end $$;
revoke all on function gatherly_ops.member_finance(jsonb) from public,anon;
grant execute on function gatherly_ops.member_finance(jsonb) to authenticated;
create function public.gatherly_finance(request jsonb) returns jsonb language sql security invoker set search_path='' as $$ select gatherly_ops.member_finance(request) $$;
revoke all on function public.gatherly_finance(jsonb) from public,anon;
grant execute on function public.gatherly_finance(jsonb) to authenticated;
