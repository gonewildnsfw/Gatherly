import {createClient} from 'npm:@supabase/supabase-js@2.117.3';
import {verifyIpn} from './commerce.mjs';
const SITE='https://gatherly.syrupyox129.chatgpt.site';
const URL=Deno.env.get('SUPABASE_URL')!;
const db=createClient(URL,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
const headers={'Access-Control-Allow-Origin':SITE,'Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS','Cache-Control':'no-store'};
const reply=(body:unknown,status=200)=>Response.json(body,{status,headers});
async function rpc(action:string,values:Record<string,unknown>={}){const {data,error}=await db.rpc('gatherly_commerce',{request:{...values,action}});if(error)throw new Error(error.message);return data;}
async function user(req:Request){const auth=req.headers.get('authorization')||'';if(!auth.startsWith('Bearer '))throw new Error('Sign in required');const {data,error}=await db.auth.getUser(auth.slice(7));if(error||!data.user?.email_confirmed_at)throw new Error('Verified sign-in required');return data.user;}
const live=()=>Deno.env.get('COMMERCE_ENABLED')==='true'&&Boolean(Deno.env.get('NOWPAYMENTS_API_KEY'))&&Boolean(Deno.env.get('NOWPAYMENTS_IPN_SECRET'));
async function provider(path:string,body?:unknown){const r=await fetch('https://api.nowpayments.io/v1/'+path,{method:body?'POST':'GET',headers:{'x-api-key':Deno.env.get('NOWPAYMENTS_API_KEY')!,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(15000)});if(!r.ok)throw new Error('Payment provider unavailable; contact support before retrying');return r.json();}
function invoiceURL(value:string){const u=new globalThis.URL(value);if(u.protocol!=='https:'||u.hostname!=='nowpayments.io'||u.username||u.password)throw new Error('Invalid invoice address');return u.href;}
async function processPayment(p:any){
 const o=await rpc('get_order',{order_id:p.order_id});
 if(!o||String(p.invoice_id)!==o.provider_invoice_id||!p.payment_id||Number(p.price_amount)!==o.gross_minor/100||String(p.price_currency).toUpperCase()!==o.currency)throw new Error('Payment snapshot mismatch');
 if(!['finished','refunded'].includes(p.payment_status))return {pending:true};
 if(p.payment_status==='finished'&&(!Number.isFinite(Number(p.actually_paid))||!Number.isFinite(Number(p.pay_amount))||Number(p.pay_amount)<=0||Number(p.actually_paid)<Number(p.pay_amount)))throw new Error('Payment incomplete');
 return rpc(p.payment_status==='finished'?'settle':'refund',{order_id:o.id,invoice_id:String(p.invoice_id),payment_id:String(p.payment_id),gross_minor:o.gross_minor,currency:o.currency});
}
async function readBody(req:Request){const reader=req.body?.getReader();if(!reader)throw new Error('Request body required');let size=0;const chunks=[];for(;;){const {value,done}=await reader.read();if(done)break;size+=value.length;if(size>16384){await reader.cancel();throw new Error('Request too large');}chunks.push(value);}const all=new Uint8Array(size);let offset=0;for(const c of chunks){all.set(c,offset);offset+=c.length;}return JSON.parse(new TextDecoder().decode(all));}
function matches(b:Uint8Array,mime:string){const text=(a:number,z:number)=>new TextDecoder().decode(b.slice(a,z));return mime==='image/jpeg'?b[0]===255&&b[1]===216&&b[2]===255:mime==='image/png'?b[0]===137&&text(1,4)==='PNG'&&b[4]===13&&b[5]===10:mime==='image/webp'?text(0,4)==='RIFF'&&text(8,12)==='WEBP':mime==='video/mp4'?text(4,8)==='ftyp':mime==='video/webm'?b[0]===26&&b[1]===69&&b[2]===223&&b[3]===163:false;}
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response(null,{headers});
 if(req.method!=='POST')return reply({error:'POST required'},405);
 try{
  const v=await readBody(req);
  if(v.action==='webhook')throw new Error('Webhook payload must use provider format');
  // Provider callbacks authenticate with HMAC; all other actions verify a Supabase user.
  if(v.payment_status&&v.payment_id){
   if(!live())return reply({error:'Commerce inactive'},503);
   if(!verifyIpn(v,req.headers.get('x-nowpayments-sig'),Deno.env.get('NOWPAYMENTS_IPN_SECRET')))return reply({error:'Invalid signature'},401);
   if(!/^\d+$/.test(String(v.payment_id)))throw new Error('Invalid payment reference');
   const trusted=await provider('payment/'+encodeURIComponent(v.payment_id));
   if(String(trusted.payment_id)!==String(v.payment_id)||String(trusted.order_id)!==String(v.order_id))throw new Error('Provider reference mismatch');
   return reply(await processPayment(trusted));
  }
  if(req.headers.get('origin')&&req.headers.get('origin')!==SITE)return reply({error:'Origin not allowed'},403);
  const u=await user(req),actor=u.id;
  if(v.action==='status')return reply({checkout_enabled:live(),uploads_enabled:true});
  if(v.action==='purchases')return reply(await rpc('purchases',{actor}));
  if(v.action==='reserve_upload'){
   if(v.confirm_rights!=='YES')throw new Error('Confirm you own the media and have permission from everyone depicted');
   const m=await rpc('reserve_media',{actor,listing_id:v.listing_id,mime:v.mime,size_bytes:v.size_bytes});
   const {data,error}=await db.storage.from('gatherly-private').createSignedUploadUrl(m.path,{upsert:false});if(error)throw new Error('Upload could not be prepared');return reply({path:m.path,token:data.token});
  }
  if(v.action==='finish_upload'){
   const m=await rpc('pending_media',{actor,listing_id:v.listing_id});
   const {data:blob,error}=await db.storage.from('gatherly-private').download(m.path);
   if(error||!blob)throw new Error('Upload not found; upload your file before finishing');
   if(blob.size!==Number(m.size_bytes)||blob.size>26214400||!matches(new Uint8Array(await blob.slice(0,32).arrayBuffer()),m.mime))throw new Error('File size or format does not match the reserved upload');
   return reply(await rpc('verify_media',{actor,listing_id:v.listing_id}));
  }
  if(v.action==='access'){
   const m=await rpc('access',{actor,listing_id:v.listing_id});const {data,error}=await db.storage.from('gatherly-private').createSignedUrl(m.path,60);if(error)throw new Error('Media temporarily unavailable');return reply({url:data.signedUrl,mime:m.mime,expires_in:60});
  }
  if(v.action==='publish'){
   if(!live())return reply({error:'Checkout is not activated. Complete provider setup and testing before publishing.'},503);
   return reply(await rpc('publish',{actor,listing_id:v.listing_id,confirm_review:v.confirm_review}));
  }
  if(v.action==='checkout'){
   if(!live())return reply({error:'Purchases are not available yet. No payment was requested.'},503);
   const reserved=await rpc('reserve_order',{actor,listing_id:v.listing_id,idempotency_key:v.idempotency_key});const o=reserved.order;
   if(!reserved.created){if(o.invoice_url)return reply({checkout_url:invoiceURL(o.invoice_url),order_id:o.id});throw new Error('Order requires reconciliation; do not retry payment');}
   const inv=await provider('invoice',{price_amount:o.gross_minor/100,price_currency:o.currency.toLowerCase(),order_id:o.id,order_description:'Gatherly digital media '+o.id,ipn_callback_url:URL+'/functions/v1/gatherly-commerce',success_url:SITE+'/social.html?payment=pending',cancel_url:SITE+'/social.html?payment=cancelled'});
   const url=invoiceURL(inv.invoice_url);if(!inv.id)throw new Error('Invalid invoice response');await rpc('attach_invoice',{order_id:o.id,invoice_id:String(inv.id),invoice_url:url});return reply({checkout_url:url,order_id:o.id});
  }
  return reply({error:'Unknown action'},400);
 }catch(error){const message=error instanceof Error?error.message:'Request failed';return reply({error:message.startsWith('Sign in')||message.startsWith('Verified sign-in')?'Please sign in again.':message},400);}
});
