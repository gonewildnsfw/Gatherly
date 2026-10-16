# Gatherly administration and manual payouts

## Owner onboarding

The project owner’s email is reserved privately in the database using identity confirmed by the connected GitHub account. The email itself is not stored in public source code. No auth account existed when this work began. Automatic privileged account provisioning was rejected by approval review; no provisioning Edge Function was deployed.

The owner account was subsequently created through the standard public Supabase signup API, with a cryptographically random initial password that was never printed or persisted. A confirmation email was requested with the password-setup page as its destination. The owner must verify the email and choose a new password on that page. A private trigger consumes the one-time owner reservation and assigns that verified account the admin role. Unverified accounts and all other accounts remain members. Roles live in a private database table; user-editable metadata cannot assign privileges. There is no shared/default/easy administrator password. Choose a memorable passphrase of at least 12 characters during password setup. Existing auth redirects and SMTP configuration still need end-to-end verification as documented in EMAIL-AUTH.md.

Once verified, signing in routes the administrator to `/admin.html`. Members land on `/social.html`. The account menu also shows Admin only after the server confirms the role.

## Dashboard

- Overview: Gatherly profile count, seven-day registrations, recent sign-ins (not concurrent visitors), unconfirmed auth accounts, posts, drafts, reports, payout queue, recorded sales, commissions, fees, refunds, creator ledger, completed payouts and bucket usage.
- Members: account email, confirmation state, dates, role and suspend/restore participation, with required operator notes. The directory includes all users in the shared Supabase auth project; Gatherly profile counts are shown separately. Suspension restricts community writes and payout requests; it does not revoke sessions or delete an account.
- Finance: creator net earnings, reserved/pending payouts, completed payouts, active holds and available balance; latest 200 orders and ledger entries. Holds and releases are audited.
- Payouts: creator, wallet/network/asset/memo snapshot, fiat amount, quote and exchange rate, separately recorded network fee, status, transaction reference and operator notes.
- Reports/content: review reports, hide posts and restore free posts. Paid publication remains blocked.
- Audit: latest 200 admin reads/mutations and financial record changes. CSV export neutralizes spreadsheet-formula input.
- Setup: current launch gaps and links to Supabase and GitHub.

## How manual payouts work

Creators use `/earnings.html` to save a wallet destination and request a payout from a positive recorded balance. There is no way for members to invent earnings: sensitive tables have no direct API access, and admin tools also cannot create arbitrary sale credits.

1. Verified settlement must first credit the creator ledger. The existing payment boundary is NOT yet connected to this ledger. Until that integration is built and verified, balances remain zero.
2. A payout request atomically reserves the requested ZAR amount under a per-creator transaction lock. Repeated request keys do not create another payout. Insufficient funds are rejected. Destination details are snapshotted so a later wallet edit cannot reroute a pending payout.
3. Admin reviews the destination, asset, network, memo and available balance, enters the crypto amount and ZAR-per-unit exchange rate, and approves. The quote must match the fiat amount to within one cent. Recorded network fees are additional operator costs; they are not silently deducted from the creator’s quote.
4. Mark processing BEFORE sending a manual transfer in your own wallet. These app controls do not send funds. Processing transfers cannot simply be rejected, because an external transfer may already exist.
5. After checking the transfer externally, record its blockchain reference and explicitly confirm that it was sent. The database requires the prior processing state and a unique network/reference combination. A second paid transition is rejected.
6. Requested/approved requests may be rejected with a reason, releasing their reservation. Paid requests cannot be edited back to pending. Failed external transfers in processing need controlled reconciliation; this release path is not automated.

Available balance = net creator ledger credits − requested/approved/processing reservations − completed payouts − active holds. If refunds make a balance negative, the dashboard highlights it and further approval/processing is blocked until reconciliation. The ledger and order snapshots are service-only data. The financial totals are not proof of actual crypto-wallet liquidity, blockchain settlement or tax profit.

## Security and verification

Sensitive tables are in `gatherly_ops`, not exposed through the Data API, with table permissions revoked, RLS enabled and explicit deny policies. Public RPC wrappers are security invoker; guarded private functions implement the narrowly scoped privileged operations. Search paths are fixed. Every admin operation checks a live role record and verified email instead of trusting browser state or user metadata. The reserved owner cannot be suspended through the UI.

`tests/admin-rls.sql` runs synthetic transactions and rolls everything back. It verifies member denial, forged metadata rejection, private financial data, reservation idempotency, overspending, quoting, transfer confirmation, replay rejection, holds, suspensions and owner enrollment only after email verification. Unit tests also cover XSS escaping, CSV formula protection, fiat parsing and admin/member redirect destinations.

Browser visual QA and a real owner sign-in were not available during implementation. Public commerce, actual payment collection, media uploads, automatic payouts, on-chain verification, tax reporting, creator identity verification and automated reconciliation are not claimed as live features.
