const message=document.querySelector('#auth-message');
// Remove the authorization code from browser history before any async work.
const callbackLocation=location.href;
history.replaceState(null,'',location.pathname);
try {
  const [{client},{finishGoogleSignIn}]=await Promise.all([import('./auth-client.js'),import('./auth-core.mjs')]);
  const user=await finishGoogleSignIn(client,callbackLocation);
  const {ensureProfile}=await import('./profile.js');
  await ensureProfile(client,user);
  message.textContent='Signed in. Opening your feed…';
  location.replace(new URL('social.html',location.href).href);
} catch(error){message.textContent=error instanceof TypeError?'Could not reach sign-in services. Please try again.':error.message;}
