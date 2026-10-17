export async function signedInDestination(client,pageUrl){
 const {data,error}=await client.rpc('gatherly_role');
 if(error)throw new Error('Your account permissions could not be checked. Please try again.');
 if(data==='admin')return new URL('admin.html',pageUrl).href;
 const account=await client.rpc('gatherly_account',{request:{action:'get'}});
 if(account.error)throw new Error('Your account setup could not be checked. Please try again.');
 return new URL(account.data?.details?'social.html':'account.html',pageUrl).href;
}
