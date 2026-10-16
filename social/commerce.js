import {client} from './auth-client.js';
export async function commerce(action,values={}){
 const {data,error}=await client.functions.invoke('gatherly-commerce',{body:{...values,action}});
 if(error){let detail;try{detail=await error.context?.json();}catch{}throw new Error(detail?.error||'Commerce service is unavailable. No access or payment was confirmed.');}
 if(data?.error)throw new Error(data.error);return data;
}
export async function uploadMedia(listingId,file){
 if(!file||!['image/jpeg','image/png','image/webp','video/mp4','video/webm'].includes(file.type)||file.size<1||file.size>26214400)throw new Error('Choose a JPEG, PNG, WebP, MP4 or WebM file up to 25 MB.');
 const r=await commerce('reserve_upload',{listing_id:listingId,mime:file.type,size_bytes:file.size,confirm_rights:'YES'});
 const {error}=await client.storage.from('gatherly-private').uploadToSignedUrl(r.path,r.token,file,{contentType:file.type});if(error)throw new Error('Upload failed. This draft keeps its reserved space; contact the operator before retrying.');
 await commerce('finish_upload',{listing_id:listingId});
}
