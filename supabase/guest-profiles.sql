-- Give newly created anonymous users a recognizable editable profile.
-- Existing profiles and posts are not changed.
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
