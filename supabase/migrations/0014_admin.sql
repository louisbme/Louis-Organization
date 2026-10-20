-- ============================================================
-- 0014_admin.sql
-- Verwaltung: Nutzerliste, Rolle setzen, Nutzer löschen (nur Admins)
-- ============================================================

create or replace function public.admin_list_users()
returns table (
  user_id uuid,
  nickname text,
  email text,
  role public.user_role,
  created_at timestamptz,
  last_sign_in_at timestamptz,
  total_workouts bigint,
  total_volume numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id as user_id,
    p.nickname,
    u.email::text as email,
    p.role,
    p.created_at,
    u.last_sign_in_at,
    (select count(*) from public.workout_sessions s where s.user_id = p.id and s.status = 'completed') as total_workouts,
    (select coalesce(sum(s.total_volume), 0) from public.workout_sessions s where s.user_id = p.id and s.status = 'completed') as total_volume
  from public.profiles p
  join auth.users u on u.id = p.id
  where public.is_admin()
  order by p.created_at;
$$;
revoke all on function public.admin_list_users() from public;
grant execute on function public.admin_list_users() to authenticated;

create or replace function public.admin_set_role(p_user_id uuid, p_role public.user_role)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Keine Berechtigung' using errcode = '42501';
  end if;
  if p_user_id = auth.uid() and p_role <> 'admin' then
    raise exception 'Die eigene Admin-Rolle kann nicht entfernt werden' using errcode = '42501';
  end if;
  update public.profiles set role = p_role where id = p_user_id;
  if not found then
    raise exception 'Benutzer nicht gefunden' using errcode = 'P0002';
  end if;
end;
$$;
revoke all on function public.admin_set_role(uuid, public.user_role) from public;
grant execute on function public.admin_set_role(uuid, public.user_role) to authenticated;

create or replace function public.admin_delete_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Keine Berechtigung' using errcode = '42501';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'Das eigene Konto kann hier nicht gelöscht werden' using errcode = '42501';
  end if;
  -- Löscht per Kaskade Profil, Einstellungen, Pläne, Trainings, Sätze, Kalender, Favoriten, eigene Übungen
  delete from auth.users where id = p_user_id;
  if not found then
    raise exception 'Benutzer nicht gefunden' using errcode = 'P0002';
  end if;
end;
$$;
revoke all on function public.admin_delete_user(uuid) from public;
grant execute on function public.admin_delete_user(uuid) to authenticated;
