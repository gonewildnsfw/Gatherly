import {completeAuthCallback,updatePassword,friendlyAuthError,authDestination} from './email-auth.mjs';
const message=document.querySelector('#auth-message');
const originalLocation=location.href;
history.replaceState(null,'',location.pathname);
try{
 const {client}=await import('./auth-client.js');
 const {user,recovery}=await completeAuthCallback(client,originalLocation);
 if(recovery){
  message.textContent='Choose a new password for your account.';
  const form=document.createElement('form');form.className='form';
  form.innerHTML='<label>New password<input name="password" type="password" autocomplete="new-password" minlength="12" required></label><label>Confirm new password<input name="confirm" type="password" autocomplete="new-password" minlength="12" required></label><p>Use at least 12 characters.</p><button class="primary">Save new password</button>';
  message.after(form);
  form.onsubmit=async e=>{e.preventDefault();const d=new FormData(form);if(d.get('password')!==d.get('confirm')){message.textContent='Your passwords do not match.';return;}form.querySelector('button').disabled=true;try{await updatePassword(client,d.get('password'));form.reset();message.textContent='Password updated. Sign in with your new password.';form.remove();location.replace(new URL('social-login.html?password=updated',originalLocation).href);}catch(error){message.textContent=friendlyAuthError(error);form.querySelector('button').disabled=false;}};
 }else{
  const {ensureProfile}=await import('./profile.js');await ensureProfile(client,user);message.textContent='Signed in. Opening your feed…';location.replace(authDestination(originalLocation));
 }
}catch(error){message.textContent=error instanceof TypeError?'Could not reach sign-in services. Please try again.':error.message;}
