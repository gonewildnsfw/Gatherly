/** Server-only commerce boundary. Never import this module into browser code.
 * A durable repository implementing docs/COMMERCE.md is required before deployment.
 */
import { createHmac, timingSafeEqual, randomUUID } from 'node:crypto';
export function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(k => [k, canonicalize(value[k])]));
  return value;
}
export function verifyIpn(payload, signature, secret) {
  if (!secret || typeof signature !== 'string' || !/^[a-f\d]{128}$/i.test(signature)) return false;
  const expected = createHmac('sha512', secret).update(JSON.stringify(canonicalize(payload))).digest();
  return timingSafeEqual(expected, Buffer.from(signature, 'hex'));
}
export function splitRevenue(amountMinor, feeBps = 1500) {
  if (!Number.isSafeInteger(amountMinor) || amountMinor < 1 || !Number.isInteger(feeBps) || feeBps < 0 || feeBps > 10000) throw new Error('Invalid amount or fee');
  const platformMinor = Math.round(amountMinor * feeBps / 10000);
  return {platformMinor, creatorMinor: amountMinor - platformMinor};
}
function httpsUrl(value) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.username || url.password) throw new Error('HTTPS URL required');
  return url.href;
}
export function createCommerce({repository, authenticate, env, fetchImpl = fetch}) {
  if (!repository || typeof authenticate !== 'function') throw new Error('Durable repository and verified authentication are required');
  // Fail closed; merely setting payment credentials must never enable charging.
  function configured() {
    if (env.COMMERCE_ENABLED !== 'true' || !env.NOWPAYMENTS_API_KEY || !env.NOWPAYMENTS_IPN_SECRET) throw new Error('Commerce is not configured');
  }
  return {
    async checkout({authorization, listingId, idempotencyKey}) {
      configured();
      const user = await authenticate(authorization); // Must verify token with auth provider.
      if (!user?.id) throw new Error('Authentication required');
      if (typeof idempotencyKey !== 'string' || !/^[a-zA-Z0-9_-]{16,100}$/.test(idempotencyKey)) throw new Error('Valid idempotency key required');
      const listing = await repository.getListing(listingId);
      if (!listing || listing.status !== 'published' || listing.creatorId === user.id) throw new Error('Listing unavailable');
      if (!Number.isSafeInteger(listing.priceMinor) || listing.priceMinor < 1 || !['ZAR','USD','EUR','GBP'].includes(listing.currency)) throw new Error('Invalid listing price');
      // Physical goods/services require fulfillment, stock, address/tax/booking support first.
      if (!['photo','video','download'].includes(listing.type)) throw new Error('This listing type is not enabled for checkout');
      if (await repository.hasEntitlement(user.id, listing.id)) throw new Error('Already purchased');
      const callback = httpsUrl(env.NOWPAYMENTS_IPN_URL);
      const origin = httpsUrl(env.PUBLIC_SITE_URL);
      const {order, created} = await repository.reserveOrder({id:randomUUID(),buyerId:user.id,listingId:listing.id,creatorId:listing.creatorId,priceMinor:listing.priceMinor,currency:listing.currency,feeBps:1500,idempotencyKey});
      if (!created) {
        if (order.invoiceUrl) return {orderId:order.id,checkoutUrl:order.invoiceUrl};
        // Do not blindly retry invoice creation after a network timeout; reconcile first.
        throw new Error('Order pending reconciliation');
      }
      const response = await fetchImpl('https://api.nowpayments.io/v1/invoice', {
        method:'POST', headers:{'Content-Type':'application/json','x-api-key':env.NOWPAYMENTS_API_KEY},
        body:JSON.stringify({price_amount:order.priceMinor/100,price_currency:order.currency.toLowerCase(),order_id:order.id,order_description:`Inkwell order ${order.id}`,ipn_callback_url:callback,success_url:new URL('social.html?payment=pending',origin).href,cancel_url:new URL('social.html?payment=cancelled',origin).href}),
        signal:AbortSignal.timeout(15000)
      });
      if (!response.ok) throw new Error('Payment provider unavailable; order requires reconciliation');
      const invoice = await response.json();
      const invoiceUrl = new URL(invoice.invoice_url);
      if (invoiceUrl.protocol !== 'https:' || invoiceUrl.hostname !== 'nowpayments.io' || invoiceUrl.username || invoiceUrl.password || !invoice.id) throw new Error('Invalid provider response');
      await repository.attachInvoice(order.id,{invoiceId:String(invoice.id),invoiceUrl:invoiceUrl.href});
      return {orderId:order.id,checkoutUrl:invoiceUrl.href};
    },
    async webhook({payload,signature}) {
      configured();
      if (!verifyIpn(payload,signature,env.NOWPAYMENTS_IPN_SECRET)) throw new Error('Invalid webhook signature');
      const order = await repository.getOrder(payload.order_id);
      if (!order || !order.invoiceId || String(payload.invoice_id)!==order.invoiceId || !payload.payment_id) throw new Error('Unknown payment');
      const minor = Math.round(Number(payload.price_amount)*100);
      if (!Number.isFinite(Number(payload.price_amount)) || minor!==order.priceMinor || String(payload.price_currency).toUpperCase()!==order.currency) throw new Error('Payment amount mismatch');
      // No access for pending, confirming, partially_paid, expired or failed payments.
      if (payload.payment_status === 'finished') {
        const paid=Number(payload.actually_paid),due=Number(payload.pay_amount);
        if (!Number.isFinite(paid)||!Number.isFinite(due)||due<=0||paid<due) throw new Error('Payment incomplete');
        // Repository transaction: unique provider payment, mark order paid, entitlement,
        // pending creator ledger + platform ledger. Duplicate callbacks return no-op.
        return repository.settleOrder({orderId:order.id,paymentId:String(payload.payment_id),...splitRevenue(order.priceMinor,order.feeBps)});
      }
      if (payload.payment_status === 'refunded') return repository.refundOrder({orderId:order.id,paymentId:String(payload.payment_id)});
      return {accepted:true,granted:false};
    }
  };
}
