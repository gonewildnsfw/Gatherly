import {config} from './config.js';
import {emailSignUp,emailSignIn,resendConfirmation,sendRecovery,friendlyAuthError,authDestination} from './email-auth.mjs';
const $=s=>document.querySelector(s),message=$('#auth-message'),form=$('#email-auth-form'),submit=$('#email-submit');
let mode='signin',client,busy=false;
function setMode(next){mode=next;const signup=mode==='signup';$('#name-field').hidden=!signup;$('#full-name').disabled=!signup;$('#full-name').required=signup;$('#password').autocomplete=signup?'new-password':'current-password';$('#password').minLength=signup?12:1;$('#password-help').hidden=!signup;submit.textContent=signup?'Create account':'Sign in';$('#sign-in-tab').classList.toggle('active',!signup);$('#sign-up-tab').classList.toggle('active',signup);$('#sign-in-tab').setAttribute('aria-selected',String(!signup));$('#sign-up-tab').setAttribute('aria-selected',String(signup));$('#password').value='';message.textContent='';}
function lock(value){busy=value;for(const control of document.querySelectorAll('button'))control.disabled=value;}
async function perform(action){if(busy||!client)return;lock(true);try{await action();}catch(error){message.textContent=friendlyAuthError(error);}finally{lock(false);}}
$('#sign-in-tab').onclick=()=>setMode('signin');$('#sign-up-tab').onclick=()=>setMode('signup');
form.onsubmit=e=>{e.preventDefault();void perform(async()=>{const values={email:$('#email').value,password:$('#password').value,name:$('#full-name').value};message.textContent=mode==='signup'?'Creating your account…':'Signing in…';const data=mode==='signup'?await emailSignUp(client,values,location.href):await emailSignIn(client,values);$('#password').value='';if(data?.session){const {ensureProfile}=await import('./profile.js');await ensureProfile(client,data.user);location.replace(authDestination(location.href));}else{message.textContent='Check your inbox for a confirmation email. Open its link in this browser to finish creating your account. If you already have an account, sign in instead.';}});};
$('#resend-confirmation').onclick=()=>{if(!$('#email').reportValidity())return;void perform(async()=>{await resendConfirmation(client,$('#email').value,location.href);message.textContent='If this account needs confirmation, a new email has been requested. Check your inbox and spam folder.';});};
$('#forgot-password').onclick=()=>{$('#recovery-panel').hidden=false;form.hidden=true;$('#recovery-form').elements.email.value=$('#email').value;message.textContent='Enter your email to request a password reset. Open the link in this browser.';};
$('#cancel-recovery').onclick=()=>{$('#recovery-panel').hidden=true;form.hidden=false;message.textContent='';};
$('#recovery-form').onsubmit=e=>{e.preventDefault();void perform(async()=>{await sendRecovery(client,new FormData(e.target).get('email'),location.href);message.textContent='If an account exists for that email, a reset link has been requested. Check your inbox and spam folder.';});};
try{
 ({client}=await import('./auth-client.js'));submit.disabled=false;message.textContent='';
 const {data}=await client.auth.getUser();if(data?.user){location.replace(authDestination(location.href));}
 // Google availability must never prevent email authentication.
 fetch(config.url+'/auth/v1/settings',{headers:{apikey:config.publishableKey},signal:AbortSignal.timeout(10000)}).then(r=>r.ok?r.json():null).then(settings=>{if(settings?.external?.google){$('#google-option').hidden=false;$('#google-login').disabled=false;$('#google-login').onclick=()=>void perform(async()=>{const {googleSignIn}=await import('./auth-core.mjs');await googleSignIn(client,location.href);});}}).catch(()=>{});
}catch{message.textContent='Sign-in could not load. Check your connection and refresh this page.';submit.disabled=true;}
