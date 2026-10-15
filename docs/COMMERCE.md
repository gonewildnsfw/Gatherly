# Gatherly social commerce — implementation and next connection

## What runs now

Open `social.html` through a static server. No installation or build is needed:

```sh
python3 -m http.server 8080
# http://localhost:8080/social.html
```

The existing sign-in and creator pages remain intact. The shared navigation links to the new Social page. The new experience deliberately does not load the old hard-coded Supabase connection.

Implemented: responsive feed, discovery, creator profiles, following, likes, comments, saved posts, search, post sharing, local post/listing creation, report/hide, creator studio and marketplace. State persists in this browser only. Seed creators, counts and listings are explicitly fictional. The “For you” feed uses a curated order, not personalized ranking. Previews use CSS artwork, not real protected media. Report actions are local only. No earnings or payments are simulated as real.

Listing types: free posts, paid photos, paid videos, digital downloads, physical products and services. Only one-time digital purchases are eligible in the server commerce boundary. Physical fulfillment and booking must be implemented before accepting money for those types. Memberships, tips, ads, direct messages, live streaming and recurring billing are not implemented.

## Payment foundation

`server/commerce.mjs` is a server-only integration module, **not a deployed API**. It has no database adapter or HTTP handlers yet and cannot process payments until those are provided. It creates NOWPayments hosted invoices using server-owned prices and verifies recursively sorted HMAC-SHA512 IPNs. The screenshot's keys are not included anywhere in these changes. Rotate both exposed keys before configuration.

Set these in server secrets, never public JavaScript or Git:

```
COMMERCE_ENABLED=false
NOWPAYMENTS_API_KEY=<new key>
NOWPAYMENTS_IPN_SECRET=<new secret>
NOWPAYMENTS_IPN_URL=https://your-backend.example/api/nowpayments/ipn
PUBLIC_SITE_URL=https://your-frontend.example/
```

The default platform commission is the existing project's 15%, represented by 1500 basis points, not a claim that this is an optimal rate. The revenue split is a gross ledger allocation; provider/network fees, taxes, refunds and payout fees need separate accounting. No automatic payouts occur. NOWPayments is a crypto payment flow, not Apple/Google native in-app billing.

Official references checked for this implementation:
- https://github.com/NowPaymentsIO/nowpayments-sdk-nodejs
- https://documenter.getpostman.com/view/7907941/S1a32n38
- https://supabase.com/docs/guides/storage/security/access-control

## Supabase connection contract (next phase)

No schema was applied to any project. Do not reuse the old project's public credentials by assumption. After the owner connects the intended project, inspect existing schemas and migrate without overwriting legacy tables. Use namespaced social tables and explicit grants with RLS:

| Data | Access rules |
| --- | --- |
| Public profiles and published post/listing metadata | Public read; author writes their own rows; immutable ownership |
| Likes, follows, comments and saved posts | Verified user creates/deletes their own; saved items private; comments publicly readable only for visible posts |
| Private media asset paths | Creator or verified purchaser only; never included in public feed payloads |
| Orders and entitlements | Buyer reads own; no client writes; server creates/settles |
| Creator ledger | Creator reads own; service-only writes |
| Reports | Reporter may submit; moderation-role reads/updates; no public read |
| Blocks | Blocker-only writes; enforced in feed and interaction queries |

Use a private media bucket. Never store paid originals in this repository, in a public storage bucket or in HTML under a CSS blur. Issue short-lived signed media URLs only after a server-side entitlement/ownership check. Separate deliberately public preview assets. Require upload size/type limits, quotas and moderation before public publication.

A durable repository must implement:

- `getListing(id)`: published listing with id, creatorId, integer priceMinor, uppercase currency, type and status.
- `hasEntitlement(buyerId, listingId)`: current unrevoked access.
- `reserveOrder(snapshot)`: atomic unique `(buyerId, idempotencyKey)` insert, returning `{order, created}`. Reject reuse with another listing. Snapshot price, currency, creator and fee; users cannot edit order fields. Add pending-order/rate limits.
- `attachInvoice(orderId, {invoiceId, invoiceUrl})`: server-only, uniqueness enforced. Preserve an audit trail; reconcile provider success/database failure.
- `getOrder(orderId)`: server-only trusted snapshot plus invoiceId.
- `settleOrder(...)`: one database transaction locks order, validates allowed state, prevents settlement after refunds, enforces globally unique provider payment ID, marks paid, inserts a unique entitlement and balanced pending-revenue ledger entries. Duplicate callbacks are no-ops. Never grant twice.
- `refundOrder(...)`: match payment ID, atomically revoke entitlement and reverse ledger exactly once. Record a refund tombstone even if the refund arrives before completion; a later `finished` webhook must not restore access. Unexpected refund amounts need reconciliation.

`authenticate(authorization)` must verify tokens against the actual auth provider, not decode JWT claims or trust browser user IDs. HTTP handlers must impose body limits, authenticate checkout, use an explicit CORS allowlist, rate-limit requests, redact errors and secrets, and return retriable non-2xx responses when durable writes fail. The webhook uses signature authentication, not a browser session. Out-of-order/missed callbacks need a reconciliation job and audit logs.

Success/cancel redirects are navigation only: never grant access from a query parameter. Show “awaiting verification” until the order is read back from the database. Partial payment is not fulfillment. Invoice creation timeouts must be reconciled rather than blindly retried. Completion requires matching order, invoice, amount and currency, a valid signature, final `finished` status, and sufficient payment.

Before opening commerce: configure the backend and rotated credentials, implement the adapter and handlers, exercise provider sandbox callbacks, verify RLS as two unrelated users, test inaccessible original media, replay and reorder callbacks, test refund/revocation, add creator onboarding and moderation, define fulfillment/support/refunds, and verify provider eligibility for the actual categories sold. A static GitHub Pages host can serve the UI but cannot hold payment secrets or run these server handlers.

## Validation

`npm run social:test` runs Node's built-in test runner against the payment boundary with an in-memory test double. Tests cover forged and partial payments, invoice and amount mismatches, authentication, idempotency, refund dispatch, unsupported fulfillment, disabled configuration and commission rounding. These are unit checks, not proof of database transactions or live provider integration. Browser visual QA was unavailable in the execution environment.

## Publishing changes

Work is on local branch `codex/social-commerce`. GitHub reported read permission but no push permission. No remote branch, PR, deployment or database change was made. Once write access is available, push this branch and review it before merging. The new page is `social.html`; `index.html` remains the legacy sign-in page.
