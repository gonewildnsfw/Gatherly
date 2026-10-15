# Email and password authentication

Email/password sign-up, sign-in, resend confirmation and recovery are implemented. Google is optional and shown only when the provider is enabled. After login or confirmation, the fixed destination is `social.html`; password recovery opens a separate password form and then returns to sign-in.

## Dashboard settings still requiring verification

The app sends explicit redirects. The Supabase dashboard could not be reached through the browser, and the connected tools cannot edit the auth configuration. Do not confuse app-side URLs with a verified server allowlist.

Set Site URL to:
`https://gatherly.syrupyox129.chatgpt.site`

Add these allowed redirects, preserving entries used by other apps in this project:
- `https://gatherly.syrupyox129.chatgpt.site/social-auth-callback.html`
- `https://gatherly.syrupyox129.chatgpt.site/social-password-reset.html`

Dashboard: https://supabase.com/dashboard/project/lokkmduplshblarcknoh/auth/url-configuration

Email/password and sign-up were confirmed enabled via the Auth settings endpoint. Email confirmation stays enabled. Default confirmation/reset templates must use `{{ .ConfirmationURL }}`; update any custom template hardcoding another host.

Supabase's default mail service restricts recipients to project-team addresses and has low limits. Configure a custom SMTP provider for public registration and password resets. No SMTP credentials were available and live email delivery was not tested.

PKCE confirmation and recovery links must be opened in the same browser that requested the email. The callback also supports standard implicit confirmation links. Codes and tokens are removed from browser history before processing. Invalid links display an error and a sign-in link. No arbitrary `next` parameter is followed.

Passwords are sent directly to Supabase; Gatherly does not store them. New passwords must have at least 12 characters; existing-user login does not apply a new minimum retroactively.

Thirty unit tests pass, including redirect construction, verified login, confirmation, recovery and error handling. Full live sign-up/confirmation testing requires the redirect settings, working email delivery and a test mailbox.
