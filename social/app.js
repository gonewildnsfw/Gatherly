import {commerce,uploadMedia} from './commerce.js';
import {client} from './auth-client.js';
import {ensureProfile} from './profile.js';
const $=s=>document.querySelector(s);
const escape=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=n=>new Intl.NumberFormat('en-ZA',{style:'currency',currency:'ZAR'}).format(n/100);
let user=null,page='feed',filter='all',query='',profileId=null,rows=[],profiles=[],likes=[],saved=[],follows=[],comments=[],reports=[],limit=30,loading=0;
const title={purchases:'Your purchases',feed:'Your daily inspiration',explore:'Find your kind of people',shop:'Your creator marketplace',saved:'Keep a little inspiration',studio:'Your creator studio',profile:'A little closer'};
const nav=[['feed','⌂','Home'],['explore','◎','Discover'],['shop','▧','Marketplace'],['saved','♧','Saved'],['studio','◈','Studio'],['purchases','▣','Purchases']];
const name=id=>profiles.find(p=>p.id===id)?.display_name||'Creator';
const avatar=id=>`<span class="avatar">${escape(name(id).slice(0,2).toUpperCase())}</span>`;
let timer;
function toast(t){$('#toast').textContent=t;$('#toast').classList.add('show');clearTimeout(timer);timer=setTimeout(()=>$('#toast').classList.remove('show'),4500);}
function modal(t,h){$('#modal-title').textContent=t;$('#modal-body').innerHTML=h;$('#modal').showModal();}
function signedIn(){if(user)return true;modal('Join the conversation','<p>Sign in to publish, follow creators and save your favourites.</p><a class="primary" href="social-login.html">Sign in or join</a>');return false;}
async function checked(request){const {data,error}=await request;if(error)throw error;return data||[];}
async function load(){
 if(page==='purchases'){await purchases();return;}
 const ticket=++loading;
 $('#content').setAttribute('aria-busy','true');
 try{
  let request=client.from('gatherly_posts').select('*').order('created_at',{ascending:false}).limit(limit);
  if(page==='studio'){if(!user){rows=[];render();return;}request=request.eq('author_id',user.id);}
  else if(page==='profile')request=request.eq('author_id',profileId).eq('status','published');
  else request=request.eq('status','published');
  const [newRows,newProfiles,newFollows,newSaved,newReports]=await Promise.all([
   checked(request),checked(client.from('social_profiles').select('id,display_name,bio').order('created_at',{ascending:false}).limit(100)),
   user?checked(client.from('gatherly_follows').select('creator_id').eq('user_id',user.id)):[],
   user?checked(client.from('gatherly_saved').select('post_id').eq('user_id',user.id)):[],
   user?checked(client.from('gatherly_reports').select('post_id').eq('user_id',user.id)):[]
  ]);
  const ids=newRows.map(p=>p.id);
  const [newLikes,newComments]=ids.length?await Promise.all([checked(client.from('gatherly_likes').select('post_id,user_id').in('post_id',ids)),checked(client.from('gatherly_comments').select('id,post_id,user_id,body').in('post_id',ids).order('created_at').limit(300))]):[[],[]];
  if(ticket!==loading)return;
  rows=newRows;profiles=newProfiles;follows=newFollows;saved=newSaved;reports=newReports;likes=newLikes;comments=newComments;render();
 }catch{if(ticket===loading)$('#content').innerHTML='<div class="empty"><h2>Could not load the community</h2><p>Your connection may be unavailable. Please try again.</p><button class="primary" data-reload="1">Try again</button></div>';}
 finally{if(ticket===loading)$('#content').removeAttribute('aria-busy');}
}
function card(p){
 const liked=likes.some(l=>l.post_id===p.id&&l.user_id===user?.id),kept=saved.some(s=>s.post_id===p.id),thread=comments.filter(c=>c.post_id===p.id);
 return `<article class="post" id="post-${p.id}"><div class="post-head">${avatar(p.author_id)}<button class="profile-link" data-profile="${p.author_id}"><strong>${escape(name(p.author_id))}</strong><small>${escape(new Date(p.created_at).toLocaleDateString())} · ${p.status==='draft'?'Private draft':'Public post'}</small></button>${p.author_id===user?.id?`<button class="more" data-delete="${p.id}" aria-label="Delete post">×</button>`:`<button class="more" data-report="${p.id}" aria-label="Report post">⋯</button>`}</div><p class="post-copy"><strong>${escape(p.title)}</strong></p><p class="post-copy">${escape(p.body)}</p>${p.price_minor?`<div class="paywall"><div><strong>${escape(p.kind)} · ${money(p.price_minor)}</strong><p>${p.status==='draft'?'Private draft: upload a file, then ask the operator to review it.':'Payment is verified on the server before access is granted.'}</p>${p.author_id===user?.id?`<button data-upload="${p.id}">Upload media</button><button data-access="${p.id}">Preview private media</button>`:`<button class="primary" data-buy="${p.id}">Buy · ${money(p.price_minor)}</button><button data-access="${p.id}">Open purchased media</button>`}</div></div>`:''}${p.status==='published'?`<div class="actions"><button data-like="${p.id}" aria-pressed="${liked}">${liked?'♥':'♡'} ${likes.filter(l=>l.post_id===p.id).length}</button><button data-comment="${p.id}">◌ ${thread.length}</button><button data-share="${p.id}">↗ Share</button><button data-save="${p.id}" aria-pressed="${kept}">${kept?'▣ Saved':'▢ Save'}</button></div><div class="comments">${thread.map(c=>`<p><strong>${escape(name(c.user_id))}</strong> ${escape(c.body)}${c.user_id===user?.id?` <button data-delete-comment="${c.id}" aria-label="Delete your comment">×</button>`:''}</p>`).join('')}</div><form class="comment-form" data-post="${p.id}"><input name="comment" aria-label="Your comment" placeholder="Add to the conversation…" required maxlength="500"><button>Post</button></form>`:''}</article>`;
}
function render(){
 $('#page-title').textContent=title[page];
 $('#navigation').innerHTML=nav.map(([id,icon,text])=>`<button class="nav-button ${page===id?'active':''}" data-page="${id}" ${page===id?'aria-current="page"':''}><span class="nav-icon">${icon}</span>${text}</button>`).join('');
 const others=profiles.filter(p=>p.id!==user?.id).slice(0,5);
 $('#suggestions').innerHTML=others.length?others.map(p=>`<div class="suggestion">${avatar(p.id)}<button class="profile-link" data-profile="${p.id}"><strong>${escape(p.display_name)}</strong></button><button class="follow" data-follow="${p.id}">${follows.some(f=>f.creator_id===p.id)?'Following':'Follow'}</button></div>`).join(''):'<small>The community is just getting started.</small>';
 let list=rows.filter(p=>!reports.some(r=>r.post_id===p.id));
 if(query)list=list.filter(p=>(p.title+' '+p.body+' '+name(p.author_id)).toLowerCase().includes(query.toLowerCase()));
 if(page==='saved')list=list.filter(p=>saved.some(s=>s.post_id===p.id));
 if(page==='shop')list=list.filter(p=>p.kind!=='post');
 if(filter==='following'&&page==='feed')list=list.filter(p=>follows.some(f=>f.creator_id===p.author_id));
 let html='';
 if(page==='feed')html=`<div class="composer">${avatar(user?.id)}<button class="compose-trigger">What have you been creating?</button><button class="compose-trigger plus" aria-label="Create post">＋</button></div><div class="tabs"><button class="tab ${filter==='all'?'active':''}" data-filter="all">Latest</button><button class="tab ${filter==='following'?'active':''}" data-filter="following">Following</button></div>`;
 if(page==='studio')html='<section class="profile-hero"><span class="eyebrow">YOUR IDEAS HAVE A HOME</span><h2>Create. Connect. Make it yours.</h2><p>Publish a text post or prepare a private listing draft.</p><button class="primary compose-trigger">＋ Create</button><button class="text-button" id="edit-profile">Edit profile</button></section><div class="notice">Photo/video drafts can have one private file up to 25 MB. Complete your Luno payout setup, upload your file, then ask the operator to review it. Purchases require checkout activation. Products, services and other downloads remain unavailable.</div>';
 if(page==='profile'){const p=profiles.find(p=>p.id===profileId);html=`<section class="profile-hero">${avatar(profileId)}<h2>${escape(p?.display_name||'Creator')}</h2><p>${escape(p?.bio||'')}</p>${profileId!==user?.id?`<button class="primary" data-follow="${profileId}">${follows.some(f=>f.creator_id===profileId)?'Following':'Follow creator'}</button>`:''}</section>`;}
 if(page==='shop')html='<div class="notice">Only reviewed listings appear here. Use Buy to request a hosted crypto invoice. Purchases unlock only after server verification, never from a payment redirect.</div>';
 html+=list.length?list.map(card).join(''):'<div class="empty"><h3>Nothing here yet</h3><p>Start a conversation, discover a creator or save a post.</p></div>';
 if(rows.length===limit)html+='<button class="primary" data-more="1">Load more posts</button>';
 $('#content').innerHTML=html;
}
async function purchases(){
 if(!signedIn())return;$('#page-title').textContent='Your purchases';
 try{const list=await commerce('purchases');$('#content').innerHTML='<div class="notice">Returning from checkout does not confirm payment. Refresh this page to check server-verified status. Pending invoices must be reconciled before creating another payment.</div><button data-reload="1">Refresh purchases</button>'+list.map(o=>`<section class="post"><h3>${escape(o.title||'Digital media')}</h3><p>${money(o.gross_minor)} · ${escape(o.status)}</p>${o.has_access?`<button data-access="${o.listing_id}">Open purchased media</button>`:o.status==='pending'&&o.invoice_url?`<a href="${escape(o.invoice_url)}" rel="noopener noreferrer">Continue hosted checkout</a>`:'<p>No media access granted.</p>'}</section>`).join('');}catch(error){toast(error.message);}
}
async function openMedia(id){if(!signedIn())return;try{const r=await commerce('access',{listing_id:id});modal('Private media',r.mime.startsWith('video/')?`<video controls controlslist="nodownload" style="max-width:100%" src="${escape(r.url)}"></video>`:`<img alt="Purchased creator media" style="max-width:100%" src="${escape(r.url)}">`);}catch(error){toast(error.message);}}
async function buy(id,button){if(!signedIn())return;button.disabled=true;try{const key='gatherly-order-'+user.id+'-'+id;let token=localStorage.getItem(key);if(!token){token=crypto.randomUUID();localStorage.setItem(key,token);}const r=await commerce('checkout',{listing_id:id,idempotency_key:token});const u=new URL(r.checkout_url);if(u.protocol!=='https:'||u.hostname!=='nowpayments.io')throw new Error('Invalid checkout URL');location.assign(u.href);}catch(error){toast(error.message);}finally{button.disabled=false;}}
async function mediaUpload(id){if(!signedIn())return;modal('Upload private photo or video','<form class="form" id="media-form"><label>File (25 MB maximum)<input type="file" name="file" accept="image/jpeg,image/png,image/webp,video/mp4,video/webm" required></label><label><input type="checkbox" required>I own this content and have permission from everyone depicted to sell it.</label><p>Files stay private. The operator must review content and rights before publication. Never upload illegal content.</p><p id="upload-status" role="status"></p><button class="primary">Upload private file</button></form>');$('#media-form').onsubmit=async ev=>{ev.preventDefault();const b=ev.target.querySelector('button');b.disabled=true;$('#upload-status').textContent='Uploading privately…';try{await uploadMedia(id,ev.target.elements.file.files[0]);$('#upload-status').textContent='Upload verified. Ask the operator to review this draft before publication.';}catch(error){$('#upload-status').textContent=error.message;}finally{b.disabled=false;}};}
async function action(fn){try{await fn();await load();}catch(error){toast(error.code==='23505'?'Already saved.':error.message?.includes('rate')?'Please slow down and try again.':'Could not save your change. Please try again.');}}
function compose(){if(!signedIn())return;modal('Make something worth sharing',`<form id="create-form" class="form"><label>Title<input name="title" required maxlength="80"></label><label>Your story<textarea name="body" required maxlength="2000"></textarea></label><div class="row"><label>Type<select name="kind"><option value="post">Public text post</option><option value="photo">Paid photos (draft)</option><option value="video">Paid video (draft)</option><option value="download">Download (draft)</option><option value="product">Product (draft)</option><option value="service">Service (draft)</option></select></label><label>Price (ZAR)<input type="number" name="price" min="1" max="100000" step="0.01" disabled></label></div><p class="notice">Text posts are public. Paid listings stay private until commerce is enabled. Media uploads are not available yet.</p><button class="primary" type="submit">Save</button></form>`);const form=$('#create-form');form.elements.kind.onchange=()=>{form.elements.price.disabled=form.elements.kind.value==='post';form.elements.price.required=form.elements.kind.value!=='post';};form.onsubmit=e=>{e.preventDefault();const d=new FormData(form),kind=d.get('kind'),price=kind==='post'?0:Math.round(Number(d.get('price'))*100);if(!d.get('title').trim()||!d.get('body').trim())return toast('Enter a title and story.');form.querySelector('button').disabled=true;action(async()=>{try{await ensureProfile(client,user);await checked(client.from('gatherly_posts').insert({author_id:user.id,title:d.get('title').trim(),body:d.get('body').trim(),kind,price_minor:price,status:kind==='post'?'published':'draft'}));$('#modal').close();page='studio';toast(kind==='post'?'Post published.':'Private draft saved.');}finally{form.querySelector('button').disabled=false;}});};}
document.addEventListener('click',e=>{
 const button=e.target.closest('button');if(!button)return;const d=button.dataset;
 if(d.page){page=d.page;limit=30;filter='all';void load();}
 else if(d.filter){filter=d.filter;render();}
 else if(d.profile){page='profile';profileId=d.profile;void load();}
 else if(d.more){limit+=30;void load();}
 else if(d.reload)void load();
 else if(d.query){query=d.query;$('#search').value=query;page='explore';render();}
 else if(button.classList.contains('compose-trigger'))compose();
 else if(d.upload)void mediaUpload(d.upload);
 else if(d.access)void openMedia(d.access);
 else if(d.buy)void buy(d.buy,button);
 else if(d.comment)document.getElementById('post-'+d.comment)?.querySelector('input')?.focus();
 else if(d.share){const url=new URL('social.html',location.href);url.hash='post-'+d.share;navigator.clipboard.writeText(url.href).then(()=>toast('Link copied.')).catch(()=>toast('Copy the page address to share.'));}
 else if(d.like||d.save||d.follow){if(!signedIn())return;const table=d.like?'gatherly_likes':d.save?'gatherly_saved':'gatherly_follows',col=d.follow?'creator_id':'post_id',id=d.like||d.save||d.follow;const active=d.like?likes.some(x=>x.post_id===id&&x.user_id===user.id):d.save?saved.some(x=>x.post_id===id):follows.some(x=>x.creator_id===id);button.disabled=true;void action(()=>checked(active?client.from(table).delete().eq('user_id',user.id).eq(col,id):client.from(table).insert({user_id:user.id,[col]:id})));}
 else if(d.delete){if(!signedIn())return;modal('Delete this post?','<p>This removes the post and its comments permanently.</p><button class="primary" id="confirm-delete">Delete my post</button>');$('#confirm-delete').onclick=()=>void action(async()=>{await checked(client.from('gatherly_posts').delete().eq('id',d.delete).eq('author_id',user.id));$('#modal').close();});}
 else if(d.deleteComment){if(signedIn())void action(()=>checked(client.from('gatherly_comments').delete().eq('id',d.deleteComment).eq('user_id',user.id)));}
 else if(d.report){if(!signedIn())return;modal('Report this post','<form id="report-form" class="form"><label>Reason<textarea name="reason" maxlength="500" required></textarea></label><p>Reports are saved privately for the site operator. This post will also be hidden from your feed.</p><button class="primary">Send report</button></form>');$('#report-form').onsubmit=ev=>{ev.preventDefault();const reason=new FormData(ev.target).get('reason').trim();if(reason)void action(async()=>{await checked(client.from('gatherly_reports').insert({user_id:user.id,post_id:d.report,reason}));$('#modal').close();toast('Report saved.');});};}
 else if(button.id==='edit-profile'){if(!signedIn())return;const p=profiles.find(p=>p.id===user.id);modal('Your profile',`<form class="form" id="profile-form"><label>Display name<input name="display_name" required maxlength="80" value="${escape(p?.display_name||'New creator')}"></label><label>Bio<textarea name="bio" maxlength="500">${escape(p?.bio||'')}</textarea></label><button class="primary">Save profile</button></form>`);$('#profile-form').onsubmit=ev=>{ev.preventDefault();const d=new FormData(ev.target);void action(async()=>{await checked(client.from('social_profiles').update({display_name:d.get('display_name').trim(),bio:d.get('bio').trim()}).eq('id',user.id));$('#modal').close();});};}
});
document.addEventListener('submit',e=>{if(!e.target.matches('.comment-form'))return;e.preventDefault();if(!signedIn())return;const body=new FormData(e.target).get('comment').trim();if(body)void action(()=>checked(client.from('gatherly_comments').insert({post_id:e.target.dataset.post,user_id:user.id,body})));});
$('#close-modal').onclick=()=>$('#modal').close();$('#search').oninput=e=>{query=e.target.value;render();};$('#start-selling').onclick=compose;$('#my-profile').onclick=()=>{if(signedIn()){page='profile';profileId=user.id;void load();}};
const reset=$('#reset');if(reset)reset.remove();
try{const {data}=await client.auth.getUser();user=data?.user||null;if(user)await ensureProfile(client,user);}catch{toast('Profile setup is temporarily unavailable.');}
await load();
client.auth.onAuthStateChange((event,session)=>{if(session?.user?.id!==user?.id)setTimeout(()=>location.reload(),0);});
