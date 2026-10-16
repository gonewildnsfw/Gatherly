-- A project owner inserts one private reservation through a trusted admin session.
-- No browser/API user can reserve or change the owner email.
create table gatherly_ops.owner_enrollment(email text primary key,claimed_user_id uuid,created_at timestamptz not null default now(),claimed_at timestamptz);
alter table gatherly_ops.owner_enrollment enable row level security;
revoke all on gatherly_ops.owner_enrollment from public,anon,authenticated;
create policy no_direct_api_access on gatherly_ops.owner_enrollment for all to anon,authenticated using(false) with check(false);
create function gatherly_ops.claim_owner_after_verification() returns trigger language plpgsql security definer set search_path='' as $$
declare reserved_email text;
begin
 if new.email_confirmed_at is null or new.email is null then return new; end if;
 select email into reserved_email from gatherly_ops.owner_enrollment where email=lower(new.email) and claimed_user_id is null for update;
 if not found then return new; end if;
 insert into gatherly_ops.roles(user_id,role) values(new.id,'admin') on conflict(user_id) do nothing;
 insert into public.social_profiles(id,display_name) values(new.id,left(coalesce(nullif(btrim(new.raw_user_meta_data->>'full_name'),''),'Owner'),80)) on conflict(id) do nothing;
 update gatherly_ops.owner_enrollment set claimed_user_id=new.id,claimed_at=now() where email=reserved_email;
 insert into gatherly_ops.audit(actor_id,action,target_id,details) values(new.id,'owner_email_verified',new.id::text,'{}');
 return new;
end $$;
revoke all on function gatherly_ops.claim_owner_after_verification() from public,anon,authenticated;
create trigger gatherly_claim_owner after insert or update of email_confirmed_at on auth.users for each row execute function gatherly_ops.claim_owner_after_verification();
