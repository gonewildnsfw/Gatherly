-- Run against a test database, inside a rolled-back transaction.
begin;
select set_config('request.jwt.claim.sub','bad77cb3-ea1f-42d7-ab19-1aacf9b4f588',true);
do $$
declare actor uuid:=auth.uid(); result jsonb;
begin
 begin
  perform public.gatherly_finance('{"action":"save_wallet","provider":"other","confirm_luno":"YES","address":"test-address-only","asset":"BTC","network":"BITCOIN"}'::jsonb);
  raise exception 'Non-Luno destination accepted';
 exception when raise_exception then if sqlerrm<>'Confirm that this is your own verified Luno receive address' then raise; end if; end;
 begin
  perform public.gatherly_finance('{"action":"save_wallet","provider":"luno","address":"test-address-only","asset":"BTC","network":"BITCOIN"}'::jsonb);
  raise exception 'Missing ownership declaration accepted';
 exception when raise_exception then if sqlerrm<>'Confirm that this is your own verified Luno receive address' then raise; end if; end;
 perform public.gatherly_finance('{"action":"save_identity","first_name":"Rollback","last_name":"Test"}'::jsonb);
 perform public.gatherly_finance('{"action":"save_wallet","provider":"luno","confirm_luno":"YES","address":"test-address-only","asset":"BTC","network":"BITCOIN"}'::jsonb);
 insert into gatherly_ops.ledger(creator_id,kind,amount_minor,reference) values(actor,'sale',10000,'rollback-luno-test-'||gen_random_uuid());
 result:=public.gatherly_finance(jsonb_build_object('action','request_payout','amount_minor',100,'idempotency_key',gen_random_uuid()));
 if not exists(select 1 from gatherly_ops.payouts where id=(result->>'id')::uuid and provider='luno' and address='test-address-only') then raise exception 'Payout snapshot missing Luno provider'; end if;
 perform public.gatherly_finance('{"action":"save_wallet","provider":"luno","confirm_luno":"YES","address":"new-test-address-only","asset":"BTC","network":"BITCOIN"}'::jsonb);
 if not exists(select 1 from gatherly_ops.payouts where id=(result->>'id')::uuid and address='test-address-only') then raise exception 'Existing payout destination changed'; end if;
end $$;
rollback;
