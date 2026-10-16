-- Server-only commerce operations; clients cannot settle, credit or grant access.
create table gatherly_ops.media(
 listing_id uuid primary key references public.gatherly_posts(id),creator_id uuid not null references auth.users(id),
 path text not null unique,mime text not null check(mime in ('image/jpeg','image/png','image/webp','video/mp4','video/webm')),
 size_bytes bigint not null check(size_bytes between 1 and 26214400),verified boolean not null default false,reviewed_by uuid references auth.users(id),created_at timestamptz not null default now()
);
create index media_creator on gatherly_ops.media(creator_id);
alter table gatherly_ops.media enable row level security;
revoke all on gatherly_ops.media from public,anon,authenticated;
create policy no_direct_api_access on gatherly_ops.media for all to anon,authenticated using(false) with check(false);
alter table gatherly_ops.orders add column idempotency_key uuid,add column invoice_url text,add column fee_bps integer not null default 1500 check(fee_bps between 0 and 10000);
create unique index commerce_order_idempotency on gatherly_ops.orders(buyer_id,idempotency_key) where idempotency_key is not null;
create unique index commerce_invoice_unique on gatherly_ops.orders(provider_invoice_id) where provider_invoice_id is not null;
create table gatherly_ops.entitlements(order_id uuid primary key references gatherly_ops.orders(id),buyer_id uuid not null references auth.users(id),listing_id uuid not null references public.gatherly_posts(id),revoked boolean not null default false,created_at timestamptz not null default now());
create index entitlement_access on gatherly_ops.entitlements(buyer_id,listing_id) where not revoked;
alter table gatherly_ops.entitlements enable row level security;
revoke all on gatherly_ops.entitlements from public,anon,authenticated;
create policy no_direct_api_access on gatherly_ops.entitlements for all to anon,authenticated using(false) with check(false);
-- Paid records cannot disappear while invoices or purchases reference them.
create function gatherly_ops.commerce_dispatch(request jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
  if not exists(select 1 from gatherly_ops.wallets where creator_id=item.author_id and provider='luno' and provider_confirmed_at is not null) or not exists(select 1 from gatherly_ops.payout_identity where creator_id=item.author_id) then raise exception 'Creator must complete Luno payout setup'; end if;
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
revoke all on function gatherly_ops.commerce_dispatch(jsonb) from public,anon,authenticated;
grant usage on schema gatherly_ops to service_role;
grant execute on function gatherly_ops.commerce_dispatch(jsonb) to service_role;
create function public.gatherly_commerce(request jsonb) returns jsonb language sql security invoker set search_path='' as $$ select gatherly_ops.commerce_dispatch(request) $$;
revoke all on function public.gatherly_commerce(jsonb) from public,anon,authenticated;
grant execute on function public.gatherly_commerce(jsonb) to service_role;
