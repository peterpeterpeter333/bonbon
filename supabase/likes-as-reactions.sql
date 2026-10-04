-- Existing projects: make likes one free reaction per user and disable paid likes.
-- Historical paid-like rows and credit balances are preserved for a future migration.
create or replace function public.give_free_like(target_paper uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare owner_id uuid;
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  select coalesce(user_id,sample_author_id) into owner_id from public.papers where id = target_paper;
  if owner_id is null or not public.can_interact_with(owner_id) then raise exception 'Like unavailable'; end if;
  if exists(select 1 from public.paper_likes where paper_id=target_paper and user_id=auth.uid() and paid=false)
    then raise exception 'Already liked'; end if;
  insert into public.paper_likes(paper_id,user_id,paid) values(target_paper,auth.uid(),false);
end;
$$;
revoke all on function public.give_free_like(uuid) from public, anon;
grant execute on function public.give_free_like(uuid) to authenticated;

create or replace function public.remove_free_like(target_paper uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  delete from public.paper_likes where paper_id=target_paper and user_id=auth.uid() and paid=false;
end;
$$;
revoke all on function public.remove_free_like(uuid) from public, anon;
grant execute on function public.remove_free_like(uuid) to authenticated;

revoke all on function public.give_paid_like(uuid) from public, anon, authenticated;
