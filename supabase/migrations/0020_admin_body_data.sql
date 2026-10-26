-- ============================================================
-- 0020_admin_body_data.sql
-- Admins dürfen Profil-Körperdaten (Größe, Geburtsdatum) und
-- Körpergewichtseinträge anderer Nutzer pflegen.
-- ============================================================

drop policy if exists "profiles_admin_update" on public.profiles;
create policy "profiles_admin_update" on public.profiles
  for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- Gewichtseinträge: bisher nur lesend für Admins, jetzt vollständig
drop policy if exists "body_weight_admin_select" on public.body_weight_entries;
drop policy if exists "body_weight_admin_all" on public.body_weight_entries;
create policy "body_weight_admin_all" on public.body_weight_entries
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));
