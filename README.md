# Gatherly

A creator community using a static frontend and Supabase. **Early access implementation; not a production-ready paid-content service.**

## Implemented

- Email/password sign-up, sign-in, confirmation and recovery. Required dashboard settings are documented in docs/EMAIL-AUTH.md.
- Optional Google sign-in appears when the provider is activated.
- Supabase-backed profiles, text posts, follows, likes, comments, saved posts and private reports.
- Creator studio with paid photo, video, download, product and service listing drafts.
- Database-enforced ownership and private drafts; paid publication is disabled.
- NOWPayments server boundary with signature verification and unit tests; not deployed or connected to a durable order store.
- Static frontend build and GitHub Actions checks.

## Run

Requires Node 22+. No npm install needed for checks/build; the browser imports a version-pinned Supabase SDK.

```sh
npm test
npm run build
python3 -m http.server 8080 --directory dist
```

Open http://localhost:8080/. Public Supabase configuration is in `social/config.js`. Never add service-role, Google OAuth or NOWPayments secrets to the frontend or this repository.

## Owner operations

Administrator dashboard: `admin.html`. Creator balances and manual payout requests: `earnings.html`. See [operations guide](docs/ADMIN-OPERATIONS.md). The owner role activates only after the reserved email is verified; other accounts are members. No default administrator password is stored.

## Backend

The selected project is `lokkmduplshblarcknoh`. Applied schemas are recorded in `database/`. Existing tables for other applications were preserved. Test ownership isolation with `tests/rls.sql` through a privileged SQL session; it rolls back all synthetic data.

## Launch blockers

1. Enable Google OAuth and configure the final host's callback URL. See `docs/GOOGLE-AND-PAGES.md`.
2. Choose a suitable production host. GitHub Pages is not permitted for operating an e-commerce business or commercial SaaS: https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits . Keep source on GitHub; deploy `dist/` to a compatible host. This repository does not automatically publish a commercial Pages site.
3. Configure rotated NOWPayments credentials in server secrets, implement/deploy the durable order adapter and HTTP handlers, and verify payment/refund/replay flows before enabling paid publication.
4. Finish private media uploads, upload quotas, entitlement-controlled delivery, moderation operations, abuse/rate limiting, user account deletion, legal/operator information, observability, backups and real-browser/end-to-end testing.

Uploads, checkout, earnings and payouts are not active. The `gatherly-private` bucket is private and intentionally has no client upload/read policies yet. Reports persist for operator review through Supabase; there is no moderator dashboard or automated response yet. Feed loads in batches of 30; search filters loaded results. No recommendation algorithm or live chat is claimed.

## Branding

Gatherly is a working product name; domain and trademark availability have not been checked.
