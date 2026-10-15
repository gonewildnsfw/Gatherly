-- Additive schema: does not touch the existing ViralDrop application's tables.
create table public.gatherly_posts (
 id uuid primary key default gen_random_uuid(),
 author_id uuid not null references public.social_profiles(id) on delete cascade,
 title text not null check(char_length(btrim(title)) between 1 and 80),
 body text not null check(char_length(btrim(body)) between 1 and 2000),
 kind text not null default 'post' check(kind in ('post','photo','video','download','product','service')),
 price_minor integer not null default 0 check(price_minor between 0 and 10000000),
 currency text not null default 'ZAR' check(currency='ZAR'),
 status text not null default 'draft' check(status in ('draft','published','hidden')),
 created_at timestamptz not null default now(),
 check ((kind='post' and price_minor=0) or (kind<>'post' and price_minor>=100))
);
create index gatherly_posts_feed on public.gatherly_posts(status,created_at desc);
create index gatherly_posts_author on public.gatherly_posts(author_id,created_at desc);
alter table public.gatherly_posts enable row level security;
revoke all on public.gatherly_posts from anon,authenticated;
grant select on public.gatherly_posts to anon,authenticated;
grant insert(author_id,title,body,kind,price_minor,status), delete on public.gatherly_posts to authenticated;
-- Paid listings remain private drafts until checkout and moderation are ready.
create policy posts_read on public.gatherly_posts for select to anon,authenticated using(status='published' or author_id=(select auth.uid()));
create policy posts_create on public.gatherly_posts for insert to authenticated with check(author_id=(select auth.uid()) and (status='draft' or (status='published' and kind='post' and price_minor=0)));
create policy posts_delete on public.gatherly_posts for delete to authenticated using(author_id=(select auth.uid()));
create table public.gatherly_likes (
 user_id uuid not null references auth.users(id) on delete cascade,
 post_id uuid not null references public.gatherly_posts(id) on delete cascade,
 primary key(user_id,post_id)
);
create table public.gatherly_saved (
 user_id uuid not null references auth.users(id) on delete cascade,
 post_id uuid not null references public.gatherly_posts(id) on delete cascade,
 primary key(user_id,post_id)
);
create table public.gatherly_follows (
 user_id uuid not null references auth.users(id) on delete cascade,
 creator_id uuid not null references public.social_profiles(id) on delete cascade,
 primary key(user_id,creator_id),check(user_id<>creator_id)
);
create table public.gatherly_comments (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.social_profiles(id) on delete cascade,
 post_id uuid not null references public.gatherly_posts(id) on delete cascade,
 body text not null check(char_length(btrim(body)) between 1 and 500),
 created_at timestamptz not null default now()
);
create table public.gatherly_reports (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 post_id uuid not null references public.gatherly_posts(id) on delete cascade,
 reason text not null check(char_length(btrim(reason)) between 1 and 500),
 created_at timestamptz not null default now(),unique(user_id,post_id)
);
create index gatherly_comments_post on public.gatherly_comments(post_id,created_at);
create index gatherly_comments_user on public.gatherly_comments(user_id);
create index gatherly_likes_post on public.gatherly_likes(post_id);
create index gatherly_saved_post on public.gatherly_saved(post_id);
create index gatherly_follows_creator on public.gatherly_follows(creator_id);
create index gatherly_reports_post on public.gatherly_reports(post_id);

alter table public.gatherly_likes enable row level security;
alter table public.gatherly_saved enable row level security;
alter table public.gatherly_follows enable row level security;
alter table public.gatherly_comments enable row level security;
alter table public.gatherly_reports enable row level security;
revoke all on public.gatherly_likes,public.gatherly_saved,public.gatherly_follows,public.gatherly_comments,public.gatherly_reports from anon,authenticated;
grant select on public.gatherly_likes,public.gatherly_follows,public.gatherly_comments to anon,authenticated;
grant select on public.gatherly_saved,public.gatherly_reports to authenticated;
grant insert(user_id,post_id),delete on public.gatherly_likes,public.gatherly_saved to authenticated;
grant insert(user_id,creator_id),delete on public.gatherly_follows to authenticated;
grant insert(user_id,post_id,body),delete on public.gatherly_comments to authenticated;
grant insert(user_id,post_id,reason) on public.gatherly_reports to authenticated;
create policy likes_read on public.gatherly_likes for select to anon,authenticated using(exists(select 1 from public.gatherly_posts p where p.id=post_id and p.status='published'));
create policy likes_insert on public.gatherly_likes for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.gatherly_posts p where p.id=post_id and p.status='published'));
create policy likes_delete on public.gatherly_likes for delete to authenticated using(user_id=(select auth.uid()));
create policy saved_read on public.gatherly_saved for select to authenticated using(user_id=(select auth.uid()));
create policy saved_insert on public.gatherly_saved for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.gatherly_posts p where p.id=post_id and p.status='published'));
create policy saved_delete on public.gatherly_saved for delete to authenticated using(user_id=(select auth.uid()));
create policy follows_read on public.gatherly_follows for select to anon,authenticated using(true);
create policy follows_insert on public.gatherly_follows for insert to authenticated with check(user_id=(select auth.uid()));
create policy follows_delete on public.gatherly_follows for delete to authenticated using(user_id=(select auth.uid()));
create policy comments_read on public.gatherly_comments for select to anon,authenticated using(exists(select 1 from public.gatherly_posts p where p.id=post_id and p.status='published'));
create policy comments_insert on public.gatherly_comments for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.gatherly_posts p where p.id=post_id and p.status='published'));
create policy comments_delete on public.gatherly_comments for delete to authenticated using(user_id=(select auth.uid()));
create policy reports_read on public.gatherly_reports for select to authenticated using(user_id=(select auth.uid()));
create policy reports_insert on public.gatherly_reports for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.gatherly_posts p where p.id=post_id and p.status='published'));

-- No storage write policies yet: uploads fail closed until quota enforcement,
-- moderation, and entitlement checks are deployed and verified.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('gatherly-private','gatherly-private',false,26214400,array['image/jpeg','image/png','image/webp','video/mp4','video/webm','application/pdf']);
