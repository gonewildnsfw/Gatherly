create table public.social_profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null check (char_length(btrim(display_name)) between 1 and 80),
 bio text not null default '' check (char_length(bio) <= 500),
 created_at timestamptz not null default now()
);
alter table public.social_profiles enable row level security;
revoke all on public.social_profiles from anon, authenticated;
grant select on public.social_profiles to anon, authenticated;
grant insert(id,display_name,bio), update(display_name,bio) on public.social_profiles to authenticated;
create policy social_profiles_read on public.social_profiles for select to anon, authenticated using (true);
create policy social_profiles_create on public.social_profiles for insert to authenticated with check ((select auth.uid()) = id);
create policy social_profiles_edit on public.social_profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
