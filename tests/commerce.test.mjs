import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {canonicalize,verifyIpn,splitRevenue,createCommerce} from '../server/commerce.mjs';
const secret='test-only-secret';
const sign=p=>createHmac('sha512',secret).update(JSON.stringify(canonicalize(p))).digest('hex');
const payload={order_id:'o1',invoice_id:12,payment_id:23,price_amount:10,price_currency:'zar',pay_amount:2,actually_paid:2,payment_status:'finished'};
function setup(overrides={}) {
 let settlements=0,fetches=0;
 const settled=new Set(),reservations=new Map();
 const order={id:'o1',invoiceId:'12',priceMinor:1000,currency:'ZAR',feeBps:1500};
 const repository={getListing:async()=>({id:'l1',creatorId:'seller',priceMinor:1000,currency:'ZAR',status:'published',type:'photo'}),hasEntitlement:async()=>false,getOrder:async()=>order,reserveOrder:async x=>{const key=x.buyerId+x.idempotencyKey;if(reservations.has(key))return {created:false,order:reservations.get(key)};reservations.set(key,x);return{created:true,order:x};},attachInvoice:async(id,data)=>{for(const o of reservations.values())if(o.id===id)Object.assign(o,data);},settleOrder:async x=>{if(!settled.has(x.paymentId)){settled.add(x.paymentId);settlements++;}return{accepted:true,granted:true};},refundOrder:async()=>({revoked:true}),...overrides};
 const api=createCommerce({repository,authenticate:async token=>token==='valid'?{id:'buyer'}:null,env:{COMMERCE_ENABLED:'true',NOWPAYMENTS_API_KEY:'test',NOWPAYMENTS_IPN_SECRET:secret,NOWPAYMENTS_IPN_URL:'https://example.com/ipn',PUBLIC_SITE_URL:'https://example.com/'},fetchImpl:async(url,opts)=>{fetches++;const body=JSON.parse(opts.body);assert.equal(body.price_amount,10);return{ok:true,json:async()=>({id:12,invoice_url:'https://nowpayments.io/payment/?iid=12'})};}});
 return{api,count:()=>settlements,fetches:()=>fetches};
}
test('valid signature verifies; tampered or malformed signatures fail',()=>{assert.ok(verifyIpn(payload,sign(payload),secret));assert.equal(verifyIpn({...payload,price_amount:1},sign(payload),secret),false);assert.equal(verifyIpn(payload,'oops',secret),false);assert.equal(verifyIpn(payload,sign(payload),''),false);});
test('canonicalization sorts nested objects without changing arrays',()=>assert.deepEqual(canonicalize({z:[{b:1,a:2}],a:3}),{a:3,z:[{a:2,b:1}]}));
test('commission is conserved in integer minor units',()=>{assert.deepEqual(splitRevenue(999),{platformMinor:150,creatorMinor:849});assert.throws(()=>splitRevenue(-1));});
test('checkout requires verified identity',async()=>{await assert.rejects(setup().api.checkout({authorization:'bad',listingId:'l1',idempotencyKey:'abcdefghijklmnop'}),/Authentication/);});
test('checkout uses server price and reuses an invoice',async()=>{const s=setup(),args={authorization:'valid',listingId:'l1',idempotencyKey:'abcdefghijklmnop',priceMinor:1};const a=await s.api.checkout(args),b=await s.api.checkout(args);assert.equal(a.checkoutUrl,b.checkoutUrl);assert.equal(s.fetches(),1);});
test('in-flight retries do not generate another invoice',async()=>{const s=setup({reserveOrder:async()=>({created:false,order:{id:'o1'}})});await assert.rejects(s.api.checkout({authorization:'valid',listingId:'l1',idempotencyKey:'abcdefghijklmnop'}),/reconciliation/);assert.equal(s.fetches(),0);});
test('non-final and partial payments never unlock',async()=>{for(const payment_status of ['waiting','confirming','confirmed','partially_paid','failed','expired']){const s=setup(),p={...payload,payment_status};assert.equal((await s.api.webhook({payload:p,signature:sign(p)})).granted,false);assert.equal(s.count(),0);}});
test('forged, wrong-amount, wrong-invoice and underpaid callbacks fail',async()=>{const s=setup();await assert.rejects(s.api.webhook({payload,signature:'bad'}));for(const patch of [{price_amount:1},{invoice_id:99},{actually_paid:1},{price_currency:'usd'}]){const p={...payload,...patch};await assert.rejects(s.api.webhook({payload:p,signature:sign(p)}));}assert.equal(s.count(),0);});
test('duplicate completion delegates to atomic idempotent settlement',async()=>{const s=setup();await s.api.webhook({payload,signature:sign(payload)});await s.api.webhook({payload,signature:sign(payload)});assert.equal(s.count(),1);});
test('refund invokes entitlement revocation boundary',async()=>{const s=setup(),p={...payload,payment_status:'refunded'};assert.deepEqual(await s.api.webhook({payload:p,signature:sign(p)}),{revoked:true});});
test('physical products cannot charge before fulfillment is implemented',async()=>{const s=setup({getListing:async()=>({id:'l1',creatorId:'seller',priceMinor:1000,currency:'ZAR',type:'product',status:'published'})});await assert.rejects(s.api.checkout({authorization:'valid',listingId:'l1',idempotencyKey:'abcdefghijklmnop'}),/not enabled/);});
test('missing backend configuration fails closed',async()=>{const api=createCommerce({repository:{},authenticate:async()=>({id:'x'}),env:{}});await assert.rejects(api.checkout({}),/not configured/);});
