import {cp,mkdir,rm,writeFile} from 'node:fs/promises';
const root=new URL('../',import.meta.url),dist=new URL('../dist/',import.meta.url);
await rm(dist,{recursive:true,force:true});await mkdir(dist,{recursive:true});
for(const name of ['index.html','social.html','social-login.html','social-auth-callback.html','social-password-reset.html','privacy.html','terms.html','favicon.svg','admin.html','admin','earnings.html','social'])await cp(new URL(name,root),new URL(name,dist),{recursive:true});
await writeFile(new URL('.nojekyll',dist),'');
console.log('Static frontend built in dist/. No backend code or secrets included.');
