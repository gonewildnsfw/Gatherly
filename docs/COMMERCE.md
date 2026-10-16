# Gatherly digital commerce

## Current rollout state
The additive schema in `database/gatherly_commerce.sql` is installed. The source includes a Supabase Edge Function, private photo/video upload flow, operator review, hosted NOWPayments invoices, buyer purchase history and short-lived media access. **The Edge Function deployment was rejected by automatic approval review, so none of this is active on the hosted app.** No live checkout or provider end-to-end test has passed. Keep `COMMERCE_ENABLED` unset/false.

## Server secrets
In the intended project's Edge Functions → Secrets, configure:

- `NOWPAYMENTS_API_KEY`: a new server-only NOWPayments API key.
- `NOWPAYMENTS_IPN_SECRET`: the matching NOWPayments IPN signature secret.
- `COMMERCE_ENABLED`: leave `false` until provider tests and operator review are complete.

Never commit real secrets or put them in browser code. The server uses Supabase's injected URL/service-role key only inside the Edge Function. Set the provider's callback to `https://lokkmduplshblarcknoh.supabase.co/functions/v1/gatherly-commerce`. Invoice creation also supplies this callback. The public frontend origin is fixed to the existing Gatherly Site.

## Authentication boundary and deployment approval
The proposed `gatherly-commerce` function uses `verify_jwt=false` because NOWPayments cannot send Supabase user JWTs. Every browser action verifies a user token through `auth.getUser`; provider callbacks require a valid recursively canonicalized HMAC-SHA512 signature and a separate authenticated provider payment lookup. No arbitrary database query, account provisioning or role assignment endpoint is exposed. Database settlement RPCs are executable only by service_role and check that role internally. Automatic approval review rejected deployment because it changes the gateway JWT boundary and introduces a production payment service. Explicit approval is required before retrying that deployment. Do not bypass the rejection using a different deployment path.

## Data and payment rules
- One private JPEG/PNG/WebP/MP4/WebM per photo/video draft; 25 MB per file, 100 MB reserved media per creator. Reserved space is retained on failed uploads; operator cleanup tooling is still needed before unrestricted scaling.
- Signed uploads use an opaque reserved path and no upsert. Finalization checks stored size and file signature. These checks are not malware scanning or content moderation. The operator previews the file and checks rights/consent before publication.
- Media originals are never put in the public feed or repository. Authorized users get a 60-second signed URL; links already issued remain usable until expiration. Purchases cannot prevent screenshots, recordings or redistribution.
- Publication and checkout fail closed unless commerce secrets and COMMERCE_ENABLED=true are set. Only photo/video listings are enabled; products, services and downloads remain drafts.
- A creator must complete private payout name and declared Luno destination before checkout can create an order.
- Server-owned order snapshots store the ZAR price and 15% platform share. Financial figures are gross accounting allocations; provider/network fees and actual wallet liquidity require reconciliation.
- Unique buyer/idempotency keys, one pending order per listing/buyer, hourly order limits and durable invoice IDs avoid duplicate invoice creation. Timeouts require reconciliation rather than blind retries.
- Only authenticated provider state with a matching invoice/order/amount/currency and fully paid `finished` status can settle. Settlement is transactional and idempotent. Refunds revoke entitlements and reverse the creator ledger once; a later finished callback cannot undo the refund tombstone.
- Existing pending invoices whose callbacks are missed require operator reconciliation; no scheduled provider reconciliation worker is deployed yet. Do not open unrestricted commerce until this operational gap and provider sandbox tests are complete.
- Luno payout sending remains manual. Never treat a payment redirect, webhook submission or browser field as proof that a payment completed.

## Verification
`npm test` exercises the payment boundary including HMAC tampering, partial payments, amount and invoice mismatches and idempotency. `tests/commerce-rls.sql` runs in a rolled-back database transaction and verifies non-server RPC rejection, owner/buyer/unrelated-user access, immutable order snapshots, duplicate settlement, 15% commission allocation and refund reversal/revocation. These tests passed on the connected project. They do not substitute for provider sandbox and browser end-to-end tests.

## Remaining activation requirements
1. Approval for the described Edge Function authentication boundary and deployment.
2. Configure new NOWPayments server secrets and verify merchant/category eligibility.
3. Deploy and test private upload and media access as separate users.
4. Complete provider sandbox/full payment/refund tests and implement reconciliation/cleanup operations.
5. Finalize commerce support, refund and content policies. Then enable commerce and publish reviewed listings.
