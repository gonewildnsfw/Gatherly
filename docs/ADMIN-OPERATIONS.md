# Gatherly operations

See MEMBER-SETUP.md for the current account and payout setup workflow. Luno-only restrictions have been removed.

## Access and navigation
The verified owner is an admin through gatherly_ops.roles. Every other account is a member. Roles are not taken from user-editable metadata. Admin sign-in lands on admin.html. Main navigation connects Home, Explore, Marketplace, Studio, Purchases, Account and Earnings. Operations section buttons remain inside the admin page.

## Member directory
Search all Gatherly profiles by email, display name, name or surname. Results show account setup status, available/reserved/held/paid balances and a masked payout destination. Reveal private details reads the member’s name, birth date, country, mobile, address and current payout destination; this access is audited. Names and age declarations are not verified identity. Public profiles show only display name, bio, photo, optionally shared real name and published posts/listings.

## Manual payouts
Creators save details at account.html and a destination at earnings.html. Destination changes require a fresh Gatherly password sign-in. Bank payouts support South African ZAR accounts; crypto supports the declared asset and network on a creator-owned receive address. Luno/referral code AQ7HMT is optional.

A request reserves the amount atomically from the creator balance. Each request snapshots the method and destination. Never substitute newer destination details when paying an existing request.

1. Review the creator and original request destination.
2. Approve bank requests for their exact ZAR amount. Crypto requests require an amount and ZAR exchange rate that reconcile with the requested balance, plus separately recorded network fees.
3. Mark processing before making the actual transfer in your bank or wallet.
4. Send manually, verify the destination and transfer result, then record the bank reference (minimum 6 characters) or blockchain reference (minimum 16 characters) and confirm sent.
5. Requested/approved requests can be rejected. Processing transfers require reconciliation and cannot simply be rejected.

App controls record transfers; they never move money. Available balance equals ledger credits minus reserved payouts, completed payouts and active holds. Negative balances block approval/processing until reconciled. Financial balances are ZAR accounting records, not bank or wallet liquidity.

## Other operations
Overview shows member/registration counts, content/reports, financial totals and media storage. Members provides participation suspension with reasons. Finance shows ledger, orders and holds. Content supports private media review and publication; Reports handles moderation; Audit records operational actions. CSV exports are restricted to admins and neutralize spreadsheet formulas.

## Validation and remaining limits
37 Node tests pass; rollback-only database tests check authorization, private information, bank transfers, payout snapshots, reauthentication, checkout idempotency and entitlement revocation. Static build excludes server code/secrets. Browser visual QA was unavailable. A real provider payment and buyer unlock still require verification. Automatic transfers, independent bank/wallet ownership verification, age/identity verification and automated reconciliation are not implemented.
