-- Do not relabel existing destinations or change existing payout snapshots.
alter table gatherly_ops.wallets add column provider text check(provider='luno'), add column provider_confirmed_at timestamptz;
alter table gatherly_ops.payouts add column provider text check(provider='luno');
create or replace function gatherly_ops.member_finance(request jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); op text:=request->>'action'; wallet gatherly_ops.wallets%rowtype; amount bigint; existing_id uuid; key uuid; result jsonb;
begin
 if actor is null then raise exception 'Sign in required' using errcode='42501'; end if;
 if op='balance' then
  return jsonb_build_object('balance',gatherly_ops.balance(actor),'wallet',(select to_jsonb(w) from gatherly_ops.wallets w where creator_id=actor),'payouts',(select coalesce(jsonb_agg(x),'[]') from (select * from gatherly_ops.payouts where creator_id=actor order by created_at desc limit 100) x),'identity',(select to_jsonb(i) from gatherly_ops.payout_identity i where creator_id=actor),'collection_live',false);
 end if;
 if not gatherly_ops.can_participate() then raise exception 'This account is suspended' using errcode='42501'; end if;
 if op='save_identity' then
  if length(btrim(coalesce(request->>'first_name',''))) not between 1 and 80 or length(btrim(coalesce(request->>'last_name',''))) not between 1 and 80 then raise exception 'Enter your first and last name (maximum 80 characters each)'; end if;
  insert into gatherly_ops.payout_identity(creator_id,first_name,last_name) values(actor,btrim(request->>'first_name'),btrim(request->>'last_name')) on conflict(creator_id) do update set first_name=excluded.first_name,last_name=excluded.last_name,updated_at=now();
  insert into gatherly_ops.audit(actor_id,action,target_id) values(actor,'payout_identity_updated',actor::text);
  return jsonb_build_object('saved',true);
 elsif op='save_wallet' then
  if request->>'provider' is distinct from 'luno' or request->>'confirm_luno' is distinct from 'YES' then raise exception 'Confirm that this is your own verified Luno receive address'; end if;
  insert into gatherly_ops.wallets(creator_id,provider,provider_confirmed_at,address,network,asset,memo) values(actor,'luno',now(),btrim(request->>'address'),upper(btrim(request->>'network')),upper(btrim(request->>'asset')),btrim(coalesce(request->>'memo',''))) on conflict(creator_id) do update set provider=excluded.provider,provider_confirmed_at=excluded.provider_confirmed_at,address=excluded.address,network=excluded.network,asset=excluded.asset,memo=excluded.memo,updated_at=now();
  insert into gatherly_ops.audit(actor_id,action,target_id,details) values(actor,'wallet_updated',actor::text,jsonb_build_object('network',request->>'network','asset',request->>'asset'));
  return jsonb_build_object('saved',true);
 elsif op='request_payout' then
  perform pg_advisory_xact_lock(hashtextextended(actor::text,0));
  amount:=(request->>'amount_minor')::bigint;key:=(request->>'idempotency_key')::uuid;
  select id into existing_id from gatherly_ops.payouts where idempotency_key=key and creator_id=actor and amount_minor=amount;
  if existing_id is not null then return jsonb_build_object('id',existing_id); end if;
  if amount is null or amount<100 or key is null or amount>(gatherly_ops.balance(actor)->>'available_minor')::bigint then raise exception 'Amount exceeds your available balance or is below R1'; end if;
  if not exists(select 1 from gatherly_ops.payout_identity where creator_id=actor) then raise exception 'Save your first and last name before requesting a payout'; end if;
  select * into wallet from gatherly_ops.wallets where creator_id=actor;
  if not found or wallet.provider is distinct from 'luno' or wallet.provider_confirmed_at is null then raise exception 'Save and confirm your own verified Luno receive address before requesting a payout'; end if;
  insert into gatherly_ops.payouts(creator_id,amount_minor,provider,address,network,asset,memo,idempotency_key) values(actor,amount,'luno',wallet.address,wallet.network,wallet.asset,wallet.memo,key) returning id into existing_id;
  insert into gatherly_ops.audit(actor_id,action,target_id,details) values(actor,'payout_requested',existing_id::text,jsonb_build_object('amount_minor',amount));
  return jsonb_build_object('id',existing_id);
 else raise exception 'Unknown finance action'; end if;
end $$;

