export function callbackUrl(pageUrl) {
  const url = new URL('social-auth-callback.html', pageUrl);
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(url.hostname))) throw new Error('Sign-in requires HTTPS (or localhost for development).');
  return url.href;
}
export async function googleSignIn(client, pageUrl) {
  const {data, error} = await client.auth.signInWithOAuth({provider:'google', options:{redirectTo:callbackUrl(pageUrl),queryParams:{prompt:'select_account'}}});
  if (error) throw error;
  return data;
}
export async function finishGoogleSignIn(client, pageUrl) {
  const params = new URL(pageUrl).searchParams;
  if (params.has('error')) throw new Error('Google sign-in was cancelled or could not be completed. Please try again.');
  const code = params.get('code');
  if (!code) throw new Error('This sign-in link is missing its code. Start again from the sign-in page.');
  const {error} = await client.auth.exchangeCodeForSession(code);
  if (error) throw new Error('Your sign-in link expired or was opened in another browser. Please start again.');
  const {data, error: userError} = await client.auth.getUser();
  if (userError || !data?.user) throw new Error('We could not verify your account. Please try signing in again.');
  return data.user;
}
