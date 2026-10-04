-- bonbon の交流機能。setup.sql の後に SQL Editor で実行します。
-- 既存の論文や利用者を消しません。

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  handle text not null unique check (handle ~ '^[a-z0-9_]{3,40}$'),
  display_name text not null default '研究者' check (char_length(display_name) between 1 and 30),
  bio text not null default '' check (char_length(bio) <= 200),
  created_at timestamptz not null default now()
);
create or replace function public.create_bonbon_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(user_id, handle, display_name)
  values (new.id, 'u' || replace(new.id::text, '-', ''),
    case when new.is_anonymous then 'ゲスト研究者' else '研究者' end)
  on conflict (user_id) do nothing;
  return new;
end;
$$;
drop trigger if exists create_bonbon_profile_trigger on auth.users;
create trigger create_bonbon_profile_trigger after insert on auth.users
for each row execute function public.create_bonbon_profile();
insert into public.profiles(user_id, handle, display_name)
select id, 'u' || replace(id::text, '-', ''), '研究者' from auth.users
on conflict (user_id) do nothing;
alter table public.profiles enable row level security;
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to anon, authenticated;
grant update (handle, display_name, bio) on public.profiles to authenticated;
drop policy if exists "Read profiles" on public.profiles;
create policy "Read profiles" on public.profiles for select to anon, authenticated using (true);
drop policy if exists "Edit own profile" on public.profiles;
create policy "Edit own profile" on public.profiles for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

alter table public.papers add column if not exists tags text[] not null default '{}';
alter table public.papers add column if not exists source_paper_id uuid references public.papers(id) on delete set null;
alter table public.papers add column if not exists source_kind text;
create or replace function public.valid_paper_tags(tag_list text[])
returns boolean language sql immutable set search_path = '' as $$
  select cardinality(tag_list) <= 5 and not exists
    (select 1 from unnest(tag_list) tag where tag is null or char_length(tag) not between 1 and 20);
$$;
alter table public.papers drop constraint if exists papers_tags_check;
alter table public.papers add constraint papers_tags_check check (public.valid_paper_tags(tags));
alter table public.papers drop constraint if exists papers_source_kind_check;
alter table public.papers add constraint papers_source_kind_check check
  (source_kind is null or source_kind in ('citation','replication'));
create index if not exists papers_tags_idx on public.papers using gin(tags);

create table if not exists public.user_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(blocker_id, blocked_id), check(blocker_id <> blocked_id)
);
create table if not exists public.user_mutes (
  muter_id uuid not null references auth.users(id) on delete cascade,
  muted_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(muter_id, muted_id), check(muter_id <> muted_id)
);
alter table public.user_blocks enable row level security;
alter table public.user_mutes enable row level security;
revoke all on public.user_blocks, public.user_mutes from anon, authenticated;
grant select, insert, delete on public.user_blocks, public.user_mutes to authenticated;
drop policy if exists "Manage own blocks" on public.user_blocks;
create policy "Manage own blocks" on public.user_blocks for all to authenticated
  using (blocker_id = (select auth.uid())) with check (blocker_id = (select auth.uid()));
drop policy if exists "Manage own mutes" on public.user_mutes;
create policy "Manage own mutes" on public.user_mutes for all to authenticated
  using (muter_id = (select auth.uid())) with check (muter_id = (select auth.uid()));

create or replace function public.can_interact_with(owner_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and owner_id <> auth.uid() and not exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = auth.uid() and b.blocked_id = owner_id)
       or (b.blocker_id = owner_id and b.blocked_id = auth.uid())
  );
$$;
revoke all on function public.can_interact_with(uuid) from public, anon;
grant execute on function public.can_interact_with(uuid) to authenticated;

create table if not exists public.follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  followed_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(follower_id, followed_id), check(follower_id <> followed_id)
);
create index if not exists follows_followed_id_idx on public.follows(followed_id);
alter table public.follows enable row level security;
revoke all on public.follows from anon, authenticated;
grant select on public.follows to anon, authenticated;
grant insert, delete on public.follows to authenticated;
drop policy if exists "Read follows" on public.follows;
create policy "Read follows" on public.follows for select to anon, authenticated using (true);
drop policy if exists "Follow users" on public.follows;
create policy "Follow users" on public.follows for insert to authenticated
  with check (follower_id = (select auth.uid()) and public.can_interact_with(followed_id));
drop policy if exists "Unfollow users" on public.follows;
create policy "Unfollow users" on public.follows for delete to authenticated
  using (follower_id = (select auth.uid()));

create table if not exists public.paper_likes (
  id bigint generated always as identity primary key,
  paper_id uuid not null references public.papers(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  paid boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index if not exists one_free_like_per_user on public.paper_likes(paper_id,user_id) where paid = false;
create index if not exists paper_likes_paper_idx on public.paper_likes(paper_id);
alter table public.paper_likes enable row level security;
revoke all on public.paper_likes from anon, authenticated;
grant select on public.paper_likes to anon, authenticated;
drop policy if exists "Read likes" on public.paper_likes;
create policy "Read likes" on public.paper_likes for select to anon, authenticated using (true);

create or replace function public.give_free_like(target_paper uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare owner_id uuid;
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  select user_id into owner_id from public.papers where id = target_paper;
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

create table if not exists public.comments (
  id bigint generated always as identity primary key,
  paper_id uuid not null references public.papers(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
create index if not exists comments_paper_idx on public.comments(paper_id,created_at);
alter table public.comments enable row level security;
revoke all on public.comments from anon, authenticated;
grant select on public.comments to anon, authenticated;
grant insert, delete on public.comments to authenticated;
drop policy if exists "Read comments" on public.comments;
create policy "Read comments" on public.comments for select to anon, authenticated using (true);
drop policy if exists "Write comments" on public.comments;
create policy "Write comments" on public.comments for insert to authenticated with check
  (user_id = (select auth.uid()) and (
    (select user_id from public.papers where id=paper_id) = (select auth.uid())
    or public.can_interact_with((select user_id from public.papers where id=paper_id))));
drop policy if exists "Delete own comments" on public.comments;
create policy "Delete own comments" on public.comments for delete to authenticated
  using (user_id = (select auth.uid()));

create table if not exists public.reposts (
  paper_id uuid not null references public.papers(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  quote text not null default '' check (char_length(quote) <= 280),
  created_at timestamptz not null default now(),
  primary key(paper_id,user_id)
);
create index if not exists reposts_created_idx on public.reposts(created_at desc);
alter table public.reposts enable row level security;
revoke all on public.reposts from anon, authenticated;
grant select on public.reposts to anon, authenticated;
grant insert, delete on public.reposts to authenticated;
drop policy if exists "Read reposts" on public.reposts;
create policy "Read reposts" on public.reposts for select to anon, authenticated using (true);
drop policy if exists "Create reposts" on public.reposts;
create policy "Create reposts" on public.reposts for insert to authenticated with check
  (user_id = (select auth.uid()) and public.can_interact_with((select user_id from public.papers where id=paper_id)));
drop policy if exists "Delete own reposts" on public.reposts;
create policy "Delete own reposts" on public.reposts for delete to authenticated
  using (user_id = (select auth.uid()));

create table if not exists public.bookmarks (
  paper_id uuid not null references public.papers(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(paper_id,user_id)
);
alter table public.bookmarks enable row level security;
revoke all on public.bookmarks from anon, authenticated;
grant select, insert, delete on public.bookmarks to authenticated;
drop policy if exists "Manage own bookmarks" on public.bookmarks;
create policy "Manage own bookmarks" on public.bookmarks for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public.notifications (
  id bigint generated always as identity primary key,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid not null references auth.users(id) on delete cascade,
  paper_id uuid references public.papers(id) on delete cascade,
  kind text not null check (kind in ('like','comment','follow','repost')),
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists notifications_recipient_idx on public.notifications(recipient_id,created_at desc);
alter table public.notifications enable row level security;
revoke all on public.notifications from anon, authenticated;
grant select, update(read_at) on public.notifications to authenticated;
drop policy if exists "Read own notifications" on public.notifications;
create policy "Read own notifications" on public.notifications for select to authenticated
  using (recipient_id = (select auth.uid()));
drop policy if exists "Read own notifications once" on public.notifications;
create policy "Read own notifications once" on public.notifications for update to authenticated
  using (recipient_id = (select auth.uid())) with check (recipient_id = (select auth.uid()));

create or replace function public.notify_bonbon_interaction()
returns trigger language plpgsql security definer set search_path = '' as $$
declare owner_id uuid; notice_kind text; related_paper uuid;
begin
  select user_id into owner_id from public.papers where id = new.paper_id;
  related_paper := new.paper_id;
  notice_kind := case tg_table_name when 'paper_likes' then 'like'
    when 'comments' then 'comment' else 'repost' end;
  if owner_id is not null and owner_id <> new.user_id then
    insert into public.notifications(recipient_id,actor_id,paper_id,kind)
      values(owner_id,new.user_id,related_paper,notice_kind);
  end if;
  return new;
end;
$$;
-- follows の列名だけ異なるため専用の通知トリガーを使います。
create or replace function public.notify_bonbon_follow()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.notifications(recipient_id,actor_id,kind)
  values(new.followed_id,new.follower_id,'follow');
  return new;
end;
$$;
drop trigger if exists notify_like_trigger on public.paper_likes;
create trigger notify_like_trigger after insert on public.paper_likes
for each row execute function public.notify_bonbon_interaction();
drop trigger if exists notify_comment_trigger on public.comments;
create trigger notify_comment_trigger after insert on public.comments
for each row execute function public.notify_bonbon_interaction();
drop trigger if exists notify_repost_trigger on public.reposts;
create trigger notify_repost_trigger after insert on public.reposts
for each row execute function public.notify_bonbon_interaction();
drop trigger if exists notify_follow_trigger on public.follows;
create trigger notify_follow_trigger after insert on public.follows
for each row execute function public.notify_bonbon_follow();

create table if not exists public.moderators (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.moderators enable row level security;
revoke all on public.moderators from anon, authenticated;
grant select on public.moderators to authenticated;
drop policy if exists "Read own moderator role" on public.moderators;
create policy "Read own moderator role" on public.moderators for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "Moderators delete papers" on public.papers;
create policy "Moderators delete papers" on public.papers for delete to authenticated using
  (exists(select 1 from public.moderators where user_id = (select auth.uid())));
drop policy if exists "Moderators delete comments" on public.comments;
create policy "Moderators delete comments" on public.comments for delete to authenticated using
  (exists(select 1 from public.moderators where user_id = (select auth.uid())));
