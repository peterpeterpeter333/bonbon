-- bonbon の公開投稿 MVP。Supabase の SQL Editor で一度実行します。
-- SQL は何度実行しても既存投稿を消しません。

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
      if image_count > 3
         or jsonb_typeof(item->'path') is distinct from 'string'
         or jsonb_typeof(item->'caption') is distinct from 'string'
         or char_length(item->>'caption') > 100
         or (item->>'path') !~ ('^' || owner_id::text || '/[0-9a-f-]{36}\.jpg$')
         then return false; end if;
    else return false;
    end if;
  end loop;
  return true;
end;
$$;

create table if not exists public.papers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  author text not null default '匿名研究者' check (char_length(author) between 1 and 24),
  category text not null check (category in ('暮らし','食べもの','人間関係')),
  title text not null check (char_length(title) between 1 and 70),
  blocks jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  constraint valid_blocks check (public.valid_paper_blocks(blocks, user_id))
);
create index if not exists papers_created_at_idx on public.papers (created_at desc);
create index if not exists papers_user_id_idx on public.papers (user_id);
alter table public.papers add column if not exists sample_hidden boolean not null default false;
alter table public.papers enable row level security;
revoke all on public.papers from anon, authenticated;
grant select on public.papers to anon, authenticated;
grant insert, delete on public.papers to authenticated;
drop policy if exists "Read published papers" on public.papers;
create policy "Read published papers" on public.papers for select to anon, authenticated using (not sample_hidden);
drop policy if exists "Create own papers" on public.papers;
create policy "Create own papers" on public.papers for insert to authenticated
  with check ((select auth.uid()) = user_id);
drop policy if exists "Delete own papers" on public.papers;
create policy "Delete own papers" on public.papers for delete to authenticated
  using ((select auth.uid()) = user_id);

create table if not exists public.paper_reports (
  id bigint generated always as identity primary key,
  paper_id uuid not null references public.papers(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check (char_length(reason) between 1 and 500),
  created_at timestamptz not null default now(),
  unique (paper_id, reporter_id)
);
create index if not exists paper_reports_created_at_idx on public.paper_reports (created_at desc);
alter table public.paper_reports enable row level security;
revoke all on public.paper_reports from anon, authenticated;
grant insert on public.paper_reports to authenticated;
drop policy if exists "Report a paper once" on public.paper_reports;
create policy "Report a paper once" on public.paper_reports for insert to authenticated
  with check ((select auth.uid()) = reporter_id);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('paper-images', 'paper-images', true, 1000000, array['image/jpeg'])
on conflict (id) do nothing;
drop policy if exists "Upload own paper images" on storage.objects;
create policy "Upload own paper images" on storage.objects for insert to authenticated
  with check (bucket_id = 'paper-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and name ~ ('^' || (select auth.uid())::text || '/[0-9a-f-]{36}\.jpg$'));
drop policy if exists "Read own paper image metadata" on storage.objects;
create policy "Read own paper image metadata" on storage.objects for select to authenticated
  using (bucket_id = 'paper-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "Delete own paper images" on storage.objects;
create policy "Delete own paper images" on storage.objects for delete to authenticated
  using (bucket_id = 'paper-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text);

-- 投稿数の簡易制限。大量投稿対策の一層であり、運用上の監視も必要です。
create or replace function public.limit_daily_papers()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.created_at := now();
  if (select count(*) from public.papers
      where user_id = new.user_id and created_at > now() - interval '24 hours') >= 10 then
    raise exception 'Too many papers in 24 hours';
  end if;
  return new;
end;
$$;
drop trigger if exists limit_daily_papers_trigger on public.papers;
create trigger limit_daily_papers_trigger before insert on public.papers
for each row execute function public.limit_daily_papers();
