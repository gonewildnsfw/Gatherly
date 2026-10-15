# Gatherly hosting

Frontend URL: https://gatherly.syrupyox129.chatgpt.site

Hosted with Sites, separately from GitHub Pages. GitHub remains the source repository; Supabase remains the backend. GitHub pushes run checks but do not automatically redeploy the hosted copy. Future releases must build the current source and publish a new Sites version.

Site project ID: `appgprj_6ad07450b8848191bb12119ed4a70798`.

## Google OAuth settings

Google authorized JavaScript origin:
`https://gatherly.syrupyox129.chatgpt.site`

Google authorized redirect URI:
`https://lokkmduplshblarcknoh.supabase.co/auth/v1/callback`

Supabase Site URL:
`https://gatherly.syrupyox129.chatgpt.site`

Supabase allowed redirect URL:
`https://gatherly.syrupyox129.chatgpt.site/social-auth-callback.html`

Enter Google client ID and client secret directly in Supabase Authentication → Providers → Google, and enable the provider. Never put the secret in this repository. The Google provider was disabled at the latest verification; this document does not mean it has been enabled.

## Status

The frontend is early access. Public browsing is enabled. Uploads, purchases and payouts remain disabled. Google OAuth provider setup and end-to-end sign-in testing remain required. The remaining launch requirements are tracked in README.md.
