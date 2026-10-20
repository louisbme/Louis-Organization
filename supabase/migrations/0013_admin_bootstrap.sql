-- ============================================================
-- 0013_admin_bootstrap.sql
-- Rollenänderung: über die App nur durch Admins, direkt in der Datenbank
-- (SQL-Editor, Management API, ohne auth.uid()) erlaubt, damit der erste Admin
-- gesetzt werden kann.
-- ============================================================

create or replace function public.protect_profile_role()
returns trigger
language plpgsql
as $$
begin
  if new.role is distinct from old.role and auth.uid() is not null and not public.is_admin() then
    raise exception 'Rolle kann nicht geändert werden' using errcode = '42501';
  end if;
  return new;
end;
$$;
