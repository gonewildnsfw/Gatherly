# Member accounts and payouts

New members confirm their email and land on account.html. Existing members see a completion link on Home. Admins continue to land on the dashboard.

1. Private details: name, surname, birth date (18+ declaration), country, mobile; creators additionally provide an address. Only the member and authorized admins can read these through checked RPCs. The optional public legal-name setting defaults off.
2. Public profile: display name, bio, optional public JPEG/PNG/WebP avatar (2 MB). Shareable storefront URLs use social.html?profile=UUID. For sale, Posts and All tabs show only published content. Purchases and financial records never appear on storefronts.
3. Creator payouts: South African ZAR bank account or crypto wallet. Luno is optional. Changes require a newly created sign-in session less than ten minutes old, enforced in the database; the form confirms the Gatherly password. Existing payout requests retain their original method and destination.

Admin > Payout directory searches email, display name and legal name. Reveal private details fetches the restricted record and adds an audit event. Directory results mask account numbers. Payout requests expose their original destinations only to admins and the creator. Bank approvals need no crypto quote. Mark processing before a manual transfer, then record the bank reference or blockchain transaction and confirm sent. These actions record transfers; they do not execute them.

Bank accounts outside South Africa are not supported in this release. Checkout still uses NOWPayments crypto invoices, independently of creator payout method. Real payment/provider delivery and identity/age verification are not proven by these forms.

Validation: npm test; npm run build; rollback-only tests/members-payouts.sql and tests/commerce-rls.sql. database/gatherly_members.sql is the ordered schema update after existing commerce/payout SQL; it is not rerunnable. Applied through the connected Supabase migration tool. Browser QA was unavailable in this environment.
