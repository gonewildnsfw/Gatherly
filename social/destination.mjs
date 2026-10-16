export async function signedInDestination(client,pageUrl){
 const {data,error}=await client.rpc('gatherly_role');
 if(error)throw new Error('Your account permissions could not be checked. Please try again.');
 return new URL(data==='admin'?'admin.html':'social.html',pageUrl).href;
}
