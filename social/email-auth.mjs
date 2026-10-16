import {callbackUrl} from './auth-core.mjs';
export const MIN_PASSWORD_LENGTH=12;
export function authDestination(pageUrl){return new URL('social.html',callbackUrl(pageUrl)).href;}
export function emailCallbackUrl(pageUrl,flow='signup'){
 if(!['signup','recovery'].includes(flow))throw new Error('Unsupported authentication flow');
 return flow==='recovery'?new URL('social-password-reset.html',callbackUrl(pageUrl)).href:callbackUrl(pageUrl);
}
export function validatePassword(password){if(typeof password!=='string'||password.length<MIN_PASSWORD_LENGTH)throw new Error('Use a password with at least 12 characters.');}
export function friendlyAuthError(error){
 const code=error?.code;
 if(code==='email_not_confirmed')return 'Please confirm your email first. You can resend the confirmation below.';
 if(code==='invalid_credentials')return 'That email and password do not match. Please try again.';
 if(code==='email_address_not_authorized')return 'Email delivery is not configured for this address yet. The site owner needs to connect a mail provider.';
 if(code==='over_email_send_rate_limit')return 'Email sending limit reached. No new email was sent. Please wait before trying again. The site owner needs to connect a mail provider for reliable delivery.';
 if(code==='over_request_rate_limit'||error?.status===429)return 'Too many requests. Please wait a few minutes before trying again.';
 if(code==='weak_password')return 'Choose a stronger password with at least 12 characters.';
 if(code==='signup_disabled')return 'New account registration is currently unavailable.';
 if(code==='user_already_exists')return 'Unable to create that account. Try signing in or resetting your password.';
 if(code==='otp_expired')return 'This link has expired or has already been used. Request a new email.';
 return 'Unable to complete your request. Please check your connection and try again.';
}
export async function emailSignUp(client,{email,password,name},pageUrl){
 validatePassword(password);
 const {data,error}=await client.auth.signUp({email:email.trim(),password,options:{data:{full_name:name.trim().slice(0,80)},emailRedirectTo:emailCallbackUrl(pageUrl)}});
 if(error)throw error;return data;
}
export async function emailSignIn(client,{email,password}){
 const {data,error}=await client.auth.signInWithPassword({email:email.trim(),password});
 if(error)throw error;
 const verified=await client.auth.getUser();if(verified.error||!verified.data?.user)throw new Error('Account verification failed');
 return {...data,user:verified.data.user};
}
export async function resendConfirmation(client,email,pageUrl){
 const {error}=await client.auth.resend({type:'signup',email:email.trim(),options:{emailRedirectTo:emailCallbackUrl(pageUrl)}});if(error)throw error;
}
export async function sendRecovery(client,email,pageUrl){
 const {error}=await client.auth.resetPasswordForEmail(email.trim(),{redirectTo:emailCallbackUrl(pageUrl,'recovery')});if(error)throw error;
}
export async function completeAuthCallback(client,pageUrl){
 const url=new URL(pageUrl),params=url.searchParams,hash=new URLSearchParams(url.hash.slice(1));
 if(params.has('error')||hash.has('error'))throw new Error('This sign-in link expired or was cancelled. Request a new link.');
 let recovery=url.pathname.endsWith('/social-password-reset.html')||params.get('flow')==='recovery';
 if(params.has('code')){
  const {data,error}=await client.auth.exchangeCodeForSession(params.get('code'));
  if(error)throw new Error('This link expired or was opened in another browser. Open it in the browser where you requested it, or sign in again.');
  recovery ||= data?.redirectType==='recovery';
 }else if(hash.has('access_token')&&hash.has('refresh_token')){
  // Supports Supabase confirmation links from other clients using implicit flow.
  const {error}=await client.auth.setSession({access_token:hash.get('access_token'),refresh_token:hash.get('refresh_token')});if(error)throw new Error('This link could not be verified. Request a new email.');
  recovery ||= hash.get('type')==='recovery';
 }else{throw new Error('This authentication link is incomplete. Start again from sign-in.');}
 const {data,error}=await client.auth.getUser();if(error||!data?.user)throw new Error('Your account could not be verified. Please sign in again.');
 return {user:data.user,recovery};
}
export async function updatePassword(client,password){
 validatePassword(password);
 const {error}=await client.auth.updateUser({password});if(error)throw error;
 // End this session after a reset; normal password sign-in proves the new secret.
 const {error:signOutError}=await client.auth.signOut({scope:'local'});if(signOutError)throw signOutError;
}
