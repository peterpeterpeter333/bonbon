-- 公式サンプル著者。ログイン可能な auth.users は作成しません。
-- setup.sql と social.sql の後に実行します。

create table if not exists public.sample_authors (
  id uuid primary key,
  handle text not null unique check (handle ~ '^[a-z0-9_]{3,40}$'),
  display_name text not null check (char_length(display_name) between 1 and 30),
  bio text not null check (char_length(bio) <= 200),
  created_at timestamptz not null default now()
);
alter table public.sample_authors enable row level security;
revoke all on public.sample_authors from anon, authenticated;
grant select on public.sample_authors to anon, authenticated;
drop policy if exists "Read sample authors" on public.sample_authors;
create policy "Read sample authors" on public.sample_authors for select to anon, authenticated using (true);

alter table public.papers add column if not exists sample_author_id uuid references public.sample_authors(id);
alter table public.papers alter column user_id drop not null;
alter table public.papers drop constraint if exists papers_one_author_check;
alter table public.papers add constraint papers_one_author_check check
  ((user_id is not null) <> (sample_author_id is not null));
create index if not exists papers_sample_author_idx on public.papers(sample_author_id);

-- 画像は従来の本人所有 Storage パスか、4つの生成済みサイト画像だけ受け入れます。
create or replace function public.valid_paper_blocks(payload jsonb, owner_id uuid)
returns boolean language plpgsql immutable set search_path = '' as $$
declare item jsonb; image_count integer := 0;
begin
  if jsonb_typeof(payload) <> 'array' or jsonb_array_length(payload) > 30
     or octet_length(payload::text) > 20000 then return false; end if;
  for item in select value from jsonb_array_elements(payload) loop
    if jsonb_typeof(item) <> 'object' then return false; end if;
    if item->>'type' = 'text' then
      if jsonb_typeof(item->'heading') is distinct from 'string'
         or jsonb_typeof(item->'body') is distinct from 'string'
         or char_length(item->>'heading') > 40
         or char_length(item->>'body') > 500 then return false; end if;
    elsif item->>'type' = 'image' then
      image_count := image_count + 1;
      if image_count > 3 or jsonb_typeof(item->'caption') is distinct from 'string'
         or char_length(item->>'caption') > 100 then return false; end if;
      if jsonb_typeof(item->'path') = 'string' then
        if (item->>'path') !~ ('^' || owner_id::text || '/[0-9a-f-]{36}\.jpg$') then return false; end if;
      elsif jsonb_typeof(item->'asset') = 'string' then
        if (item->>'asset') not in (
          'images/sock-detective.jpg', 'images/checkout-lines.jpg',
          'images/reply-at-night.jpg', 'images/umbrella-choices.jpg'
        ) then return false; end if;
      else return false;
      end if;
    else return false;
    end if;
  end loop;
  return true;
end;
$$;
alter table public.papers drop constraint if exists valid_blocks;
alter table public.papers add constraint valid_blocks check
  (public.valid_paper_blocks(blocks, coalesce(user_id,sample_author_id)));

create table if not exists public.sample_follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  sample_author_id uuid not null references public.sample_authors(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(follower_id,sample_author_id)
);
create index if not exists sample_follows_author_idx on public.sample_follows(sample_author_id);
alter table public.sample_follows enable row level security;
revoke all on public.sample_follows from anon, authenticated;
grant select on public.sample_follows to anon, authenticated;
grant insert, delete on public.sample_follows to authenticated;
drop policy if exists "Read sample follows" on public.sample_follows;
create policy "Read sample follows" on public.sample_follows for select to anon, authenticated using (true);
drop policy if exists "Follow sample authors" on public.sample_follows;
create policy "Follow sample authors" on public.sample_follows for insert to authenticated with check
  (follower_id = (select auth.uid()) and public.can_interact_with(sample_author_id));
drop policy if exists "Unfollow sample authors" on public.sample_follows;
create policy "Unfollow sample authors" on public.sample_follows for delete to authenticated using
  (follower_id = (select auth.uid()));

create table if not exists public.sample_mutes (
  muter_id uuid not null references auth.users(id) on delete cascade,
  sample_author_id uuid not null references public.sample_authors(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(muter_id,sample_author_id)
);
create table if not exists public.sample_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  sample_author_id uuid not null references public.sample_authors(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(blocker_id,sample_author_id)
);
alter table public.sample_mutes enable row level security;
alter table public.sample_blocks enable row level security;
revoke all on public.sample_mutes, public.sample_blocks from anon, authenticated;
grant select, insert, delete on public.sample_mutes, public.sample_blocks to authenticated;
drop policy if exists "Manage own sample mutes" on public.sample_mutes;
create policy "Manage own sample mutes" on public.sample_mutes for all to authenticated
  using (muter_id = (select auth.uid())) with check (muter_id = (select auth.uid()));
drop policy if exists "Manage own sample blocks" on public.sample_blocks;
create policy "Manage own sample blocks" on public.sample_blocks for all to authenticated
  using (blocker_id = (select auth.uid())) with check (blocker_id = (select auth.uid()));

create or replace function public.can_interact_with(owner_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and owner_id <> auth.uid() and not exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = auth.uid() and b.blocked_id = owner_id)
       or (b.blocker_id = owner_id and b.blocked_id = auth.uid())
  ) and not exists (
    select 1 from public.sample_blocks b
    where b.blocker_id = auth.uid() and b.sample_author_id = owner_id
  );
$$;

create or replace function public.give_free_like(target_paper uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare owner_id uuid;
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  select coalesce(user_id,sample_author_id) into owner_id from public.papers where id = target_paper;
  if owner_id is null or not public.can_interact_with(owner_id) then raise exception 'Like unavailable'; end if;
  if exists(select 1 from public.paper_likes where paper_id=target_paper and user_id=auth.uid())
    then raise exception 'A paid credit is required for another like'; end if;
  insert into public.paper_likes(paper_id,user_id,paid) values(target_paper,auth.uid(),false);
end;
$$;
create or replace function public.give_paid_like(target_paper uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare owner_id uuid;
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  select coalesce(user_id,sample_author_id) into owner_id from public.papers where id = target_paper;
  if owner_id is null or not public.can_interact_with(owner_id) then raise exception 'Like unavailable'; end if;
  update public.paid_like_credits set balance=balance-1,updated_at=now()
    where user_id=auth.uid() and balance>0;
  if not found then raise exception 'Paid like credit required'; end if;
  insert into public.paper_likes(paper_id,user_id,paid) values(target_paper,auth.uid(),true);
end;
$$;

drop policy if exists "Write comments" on public.comments;
create policy "Write comments" on public.comments for insert to authenticated with check
  (user_id = (select auth.uid()) and (
    (select user_id from public.papers where id=paper_id) = (select auth.uid())
    or public.can_interact_with((select coalesce(user_id,sample_author_id) from public.papers where id=paper_id))));
drop policy if exists "Create reposts" on public.reposts;
create policy "Create reposts" on public.reposts for insert to authenticated with check
  (user_id = (select auth.uid()) and public.can_interact_with(
    (select coalesce(user_id,sample_author_id) from public.papers where id=paper_id)));

create or replace function public.limit_daily_papers()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.sample_author_id is not null then return new; end if;
  new.created_at := now();
  if (select count(*) from public.papers
      where user_id = new.user_id and created_at > now() - interval '24 hours') >= 10 then
    raise exception 'Too many papers in 24 hours';
  end if;
  return new;
end;
$$;
