import {config} from './config.js';
const button=document.querySelector('#google-login'),message=document.querySelector('#auth-message');
try {
  const [{client},{googleSignIn}] = await Promise.all([import('./auth-client.js'),import('./auth-core.mjs')]);
  const response=await fetch(config.url+'/auth/v1/settings',{headers:{apikey:config.publishableKey},signal:AbortSignal.timeout(15000)});
  if(!response.ok) throw new Error('Sign-in is temporarily unavailable. Please try again shortly.');
  const settings=await response.json();
  if(!settings.external?.google) throw new Error('Google sign-in is awaiting activation by the site owner. You can explore the preview below.');
  message.textContent='Sign in or create your account securely with Google.';button.disabled=false;
  button.onclick=async()=>{button.disabled=true;message.textContent='Taking you to Google…';try{await googleSignIn(client,location.href);}catch{message.textContent='Could not start Google sign-in. Please try again.';button.disabled=false;}};
} catch(error){message.textContent=error instanceof TypeError?'Unable to load sign-in. Check your connection and try again.':error.message;}
