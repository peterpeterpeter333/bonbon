-- 管理者が投稿報告を確認・処理するための追加設定。
-- supabase/setup.sql と supabase/social.sql の後に SQL Editor で実行します。
-- 管理者IDの登録は公開リポジトリに含めず、Dashboard で個別に行います。

alter table public.paper_reports
  add column if not exists status text not null default 'open';
alter table public.paper_reports
  add column if not exists handled_at timestamptz;
alter table public.paper_reports
  add column if not exists handled_by uuid references auth.users(id) on delete set null;
alter table public.paper_reports
  drop constraint if exists paper_reports_status_check;
alter table public.paper_reports
  add constraint paper_reports_status_check check (status in ('open', 'resolved', 'dismissed'));
create index if not exists paper_reports_status_created_idx
  on public.paper_reports (status, created_at desc);

revoke insert on public.paper_reports from authenticated;
grant insert (paper_id, reporter_id, reason) on public.paper_reports to authenticated;
grant select on public.paper_reports to authenticated;
grant update (status, handled_at, handled_by) on public.paper_reports to authenticated;
drop policy if exists "Moderators read reports" on public.paper_reports;
create policy "Moderators read reports" on public.paper_reports
  for select to authenticated using (
    exists (select 1 from public.moderators where user_id = (select auth.uid()))
  );
drop policy if exists "Moderators handle reports" on public.paper_reports;
create policy "Moderators handle reports" on public.paper_reports
  for update to authenticated using (
    exists (select 1 from public.moderators where user_id = (select auth.uid()))
  ) with check (
    exists (select 1 from public.moderators where user_id = (select auth.uid()))
    and (status = 'open' and handled_at is null and handled_by is null
      or status in ('resolved', 'dismissed')
        and handled_at is not null and handled_by = (select auth.uid()))
  );

-- 投稿削除後に公開画像が残らないよう、管理者に画像削除権限を付けます。
drop policy if exists "Moderators read paper image metadata" on storage.objects;
create policy "Moderators read paper image metadata" on storage.objects
  for select to authenticated using (
    bucket_id = 'paper-images'
    and exists (select 1 from public.moderators where user_id = (select auth.uid()))
  );
drop policy if exists "Moderators delete paper images" on storage.objects;
create policy "Moderators delete paper images" on storage.objects
  for delete to authenticated using (
    bucket_id = 'paper-images'
    and exists (select 1 from public.moderators where user_id = (select auth.uid()))
  );
