const area=document.querySelector('#account-actions');
try {
  const {client}=await import('./auth-client.js');
  let generation=0;
  async function refresh(){
    const current=++generation;
    const {data,error}=await client.auth.getUser();
    if(current!==generation)return;
    area.replaceChildren();
    if(error||!data?.user){const link=document.createElement('a');link.href='social-login.html';link.className='primary';link.textContent='Sign in / Join';area.append(link);return;}
    const label=document.createElement('span');label.textContent='Signed in';label.title=data.user.email||'Your account';
    const button=document.createElement('button');button.className='text-button';button.textContent='Sign out';
    button.onclick=async()=>{button.disabled=true;const {error}=await client.auth.signOut({scope:'local'});if(error){button.disabled=false;button.textContent='Retry sign out';return;}location.replace('social.html');};
    area.append(label,button);
    const earnings=document.createElement('a');earnings.href='earnings.html';earnings.textContent='Earnings';area.append(earnings);
    const role=await client.rpc('gatherly_role');
    if(current!==generation)return;
    if(!role.error&&role.data==='admin'){const admin=document.createElement('a');admin.href='admin.html';admin.className='primary';admin.textContent='Admin';area.append(admin);}
  }
  // Do not await auth methods inside the auth event callback (SDK lock).
  client.auth.onAuthStateChange(()=>{setTimeout(()=>void refresh(),0);});
  await refresh();
}catch{area.textContent='Sign-in unavailable';}
