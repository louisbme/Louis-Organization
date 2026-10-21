-- ============================================================
-- 0016_admin_nickname.sql
-- Verwaltung: Nickname eines Nutzers ändern (nur Admins)
-- ============================================================

create or replace function public.admin_set_nickname(p_user_id uuid, p_nickname text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nick text := trim(p_nickname);
begin
  if not public.is_admin() then
    raise exception 'Keine Berechtigung' using errcode = '42501';
  end if;
  if v_nick is null or char_length(v_nick) < 3 or char_length(v_nick) > 20 or v_nick !~ '^[A-Za-z0-9_.-]+$' then
    raise exception 'Nickname ungültig (3–20 Zeichen, nur Buchstaben, Zahlen, Punkt, Unterstrich, Bindestrich)' using errcode = '22023';
  end if;
  if exists (select 1 from public.profiles where lower(nickname) = lower(v_nick) and id <> p_user_id) then
    raise exception 'Nickname bereits vergeben' using errcode = '23505';
  end if;
  update public.profiles set nickname = v_nick where id = p_user_id;
  if not found then
    raise exception 'Benutzer nicht gefunden' using errcode = 'P0002';
  end if;
end;
$$;
revoke all on function public.admin_set_nickname(uuid, text) from public;
grant execute on function public.admin_set_nickname(uuid, text) to authenticated;
