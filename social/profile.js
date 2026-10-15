export async function ensureProfile(client,user){
  // Display metadata is never used for roles or authorization.
  const name=String(user.user_metadata?.full_name||user.user_metadata?.name||'New creator').trim().slice(0,80)||'New creator';
  const {error}=await client.from('social_profiles').upsert({id:user.id,display_name:name},{onConflict:'id',ignoreDuplicates:true});
  if(error)throw new Error('You are signed in, but your profile could not be saved. Please try again shortly.');
}
