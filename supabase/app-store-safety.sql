-- Run after setup.sql, social.sql, demo-support.sql, and moderation.sql.
-- Adds comment reporting, a first-pass text filter, and self-service account deletion.

create table if not exists public.comment_reports (
  id bigint generated always as identity primary key,
  comment_id bigint not null references public.comments(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check (char_length(reason) between 1 and 500),
  status text not null default 'open' check (status in ('open', 'resolved', 'dismissed')),
  created_at timestamptz not null default now(),
  handled_at timestamptz,
  handled_by uuid references auth.users(id) on delete set null,
  unique (comment_id, reporter_id)
);
create index if not exists comment_reports_status_created_idx
  on public.comment_reports(status, created_at desc);
alter table public.comment_reports enable row level security;
revoke all on public.comment_reports from anon, authenticated;
grant insert (comment_id, reporter_id, reason) on public.comment_reports to authenticated;
grant select on public.comment_reports to authenticated;
grant update (status, handled_at, handled_by) on public.comment_reports to authenticated;
drop policy if exists "Report a comment once" on public.comment_reports;
create policy "Report a comment once" on public.comment_reports for insert to authenticated
  with check (reporter_id = (select auth.uid()) and exists (
    select 1 from public.comments c where c.id = comment_id and c.user_id <> (select auth.uid())
  ));
drop policy if exists "Moderators read comment reports" on public.comment_reports;
create policy "Moderators read comment reports" on public.comment_reports for select to authenticated
  using (exists (select 1 from public.moderators where user_id = (select auth.uid())));
drop policy if exists "Moderators handle comment reports" on public.comment_reports;
create policy "Moderators handle comment reports" on public.comment_reports for update to authenticated
  using (exists (select 1 from public.moderators where user_id = (select auth.uid())))
  with check (exists (select 1 from public.moderators where user_id = (select auth.uid()))
    and (status = 'open' and handled_at is null and handled_by is null
      or status in ('resolved', 'dismissed') and handled_at is not null
        and handled_by = (select auth.uid())));

-- A narrow server-side first pass. It is intentionally supplemented by reports and human review.
create or replace function public.bonbon_text_allowed(value text)
returns boolean language sql immutable set search_path = '' as $$
  select regexp_replace(lower(coalesce(value, '')), '[[:space:]　]+', '', 'g')
    !~ '(死ね|殺すぞ|自殺しろ|住所を晒す|個人情報を晒す|児童ポルノ)';
$$;
revoke all on function public.bonbon_text_allowed(text) from public, anon;
grant execute on function public.bonbon_text_allowed(text) to authenticated;

create or replace function public.check_bonbon_text()
returns trigger language plpgsql set search_path = '' as $$
declare content text;
begin
  if tg_table_name = 'papers' then
    content := new.title || ' ' || new.blocks::text || ' ' || array_to_string(new.tags, ' ');
  elsif tg_table_name = 'comments' then content := new.body;
  elsif tg_table_name = 'reposts' then content := new.quote;
  elsif tg_table_name = 'profiles' then
    content := new.display_name || ' ' || coalesce(new.bio, '');
  end if;
  if not public.bonbon_text_allowed(content) then
    raise exception 'Content needs revision before publishing' using errcode = '23514';
  end if;
  return new;
end;
$$;
drop trigger if exists check_bonbon_paper_text on public.papers;
create trigger check_bonbon_paper_text before insert or update of title, blocks, tags
  on public.papers for each row execute function public.check_bonbon_text();
drop trigger if exists check_bonbon_comment_text on public.comments;
create trigger check_bonbon_comment_text before insert or update of body
  on public.comments for each row execute function public.check_bonbon_text();
drop trigger if exists check_bonbon_repost_text on public.reposts;
create trigger check_bonbon_repost_text before insert or update of quote
  on public.reposts for each row execute function public.check_bonbon_text();
drop trigger if exists check_bonbon_profile_text on public.profiles;
create trigger check_bonbon_profile_text before insert or update of display_name, bio
  on public.profiles for each row execute function public.check_bonbon_text();

-- The browser removes files via Storage API first. Do not delete storage.objects in SQL:
-- that would leave physical files orphaned. This function refuses deletion if any remain.
create or replace function public.delete_own_bonbon_account()
returns void language plpgsql security definer set search_path = '' as $$
declare target_id uuid := (select auth.uid());
begin
  if target_id is null then raise exception 'Sign in is required'; end if;
  if exists (select 1 from storage.objects
    where bucket_id = 'paper-images' and
      ((storage.foldername(name))[1] = target_id::text or owner_id = target_id::text)) then
    raise exception 'Remove uploaded images before deleting the account';
  end if;
  delete from auth.users where id = target_id;
  if not found then raise exception 'Account not found'; end if;
end;
$$;
revoke all on function public.delete_own_bonbon_account() from public, anon;
grant execute on function public.delete_own_bonbon_account() to authenticated;
