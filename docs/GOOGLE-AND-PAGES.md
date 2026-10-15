# Google sign-in and GitHub Pages handoff

## Completed

- Resumed the explicitly selected Supabase project `lokkmduplshblarcknoh` on its existing Free plan. No paid upgrade.
- Created `public.social_profiles` with row-level security: public profile names/bios, owner-only inserts and updates. No emails stored in public profiles. The server owns creation timestamps; clients cannot change ownership.
- Security advisor returned no notices after this schema change.
- Added one Google button for sign-up/sign-in, PKCE code exchange, verified user lookup, profile creation, cancellation/error handling, and sign-out.
- Pinned the browser SDK to 2.117.3. No Google client secret is placed in the browser or repository.
- Added an explicit frontend-only Pages package and a deployment workflow. Backend code/SQL/legacy account pages are excluded from the Pages artifact.
- Updated the repository's shared Supabase configuration to the connected project. The legacy application's schemas have NOT been migrated; use the social frontend, not the legacy account pages.

## Current blockers

Google provider was checked through `/auth/v1/settings` and is disabled. Gmail access does not provide Google Cloud administrative access. No real OAuth completion has been tested. Social activity and commerce remain preview-only; the broader production backend is still unfinished.

GitHub connected account: `gonewildnsfw`. Accessible writable repositories found: `Deriv`, `viraldrop`. The original `etsymom/myonlineshop` repository is read-only. A destination for this social network must be selected without overwriting an unrelated project. A new dedicated public repository is recommended; current tools do not expose repository creation or forking.

## Google configuration (owner action)

1. Open https://console.cloud.google.com/auth/overview using the Google account that will own the app. Configure Gatherly branding, support email, audience, and the actual public terms/privacy links.
2. Create a Web application OAuth client. Request only `openid`, `email`, and `profile`.
3. Authorized redirect URI (exact):

   `https://lokkmduplshblarcknoh.supabase.co/auth/v1/callback`

4. Authorized JavaScript origin for GitHub Pages:

   `https://gonewildnsfw.github.io`

5. Copy the client ID and client secret directly into https://supabase.com/dashboard/project/lokkmduplshblarcknoh/auth/providers?provider=Google and enable Google. Do not paste the secret into source code, screenshots or chat.
6. In Supabase Authentication → URL Configuration set the Site URL to the chosen Pages URL. Allow exactly the deployed callback URL, for example `https://gonewildnsfw.github.io/REPOSITORY/social-auth-callback.html`. Replace REPOSITORY with the confirmed destination. Avoid wildcard production callbacks. Development may separately allow `http://localhost:8080/social-auth-callback.html`.
7. Google testing-mode apps allow only configured test users. Configure the production audience/publishing state before public launch and complete any verification Google requests. Do not disable nonce validation.

Google's redirect goes to Supabase; Supabase's allowed redirect goes back to the website. They are different URLs.

## GitHub Pages

After selecting a repository and pushing the code, Settings → Pages → Build and deployment → Source: GitHub Actions. The included workflow tests the auth/payment boundaries, builds `dist/`, and deploys the static frontend on pushes to `main` or manual dispatch. The artifact uses relative paths and works beneath a repository subdirectory. No server secrets belong in Actions for this static frontend.

Local checks:

```
node --test tests/*.test.mjs
node scripts/build-pages.mjs
python3 -m http.server 8080 --directory dist
```

The live Google round-trip must still be verified after the provider and callback allowlist are configured. Test first-time signup, returning login, denied consent, sign-out, and expired callback codes. Community data, protected upload entitlements, payment handlers, creator settlement, moderation and production operations remain separate launch gates documented in COMMERCE.md.

## Updated destination and hosting decision

Source repository: https://github.com/gonewildnsfw/Gatherly . Google remained disabled at the latest check. GitHub Pages commercial hosting restrictions mean the production origin and redirect URL must be set after a suitable host is selected. Earlier Pages instructions are reference only, not an active deployment. Google callback stays `https://lokkmduplshblarcknoh.supabase.co/auth/v1/callback`.
