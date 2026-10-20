-- ============================================================
-- 0003_rls.sql
-- Row Level Security: Jeder Benutzer sieht und ändert nur eigene Daten.
-- Stammdaten (Muskeln, Griffe, Standardübungen, Vorlagen, Zitate) sind für
-- angemeldete Benutzer lesbar, aber nicht veränderbar.
-- ============================================================

alter table public.profiles enable row level security;
alter table public.user_settings enable row level security;
alter table public.muscle_groups enable row level security;
alter table public.grips enable row level security;
alter table public.exercises enable row level security;
alter table public.exercise_muscles enable row level security;
alter table public.workout_plan_templates enable row level security;
alter table public.workout_plan_template_exercises enable row level security;
alter table public.workout_plans enable row level security;
alter table public.workout_plan_exercises enable row level security;
alter table public.workout_sessions enable row level security;
alter table public.workout_session_exercises enable row level security;
alter table public.workout_sets enable row level security;
alter table public.calendar_entries enable row level security;
alter table public.favorites enable row level security;
alter table public.quotes enable row level security;
alter table public.body_weight_entries enable row level security;

-- profiles --------------------------------------------------
create policy "profiles_select_own" on public.profiles
  for select to authenticated using (id = auth.uid());
create policy "profiles_update_own" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- user_settings ---------------------------------------------
create policy "settings_select_own" on public.user_settings
  for select to authenticated using (user_id = auth.uid());
create policy "settings_insert_own" on public.user_settings
  for insert to authenticated with check (user_id = auth.uid());
create policy "settings_update_own" on public.user_settings
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Stammdaten: nur lesen --------------------------------------
create policy "muscle_groups_read" on public.muscle_groups
  for select to authenticated using (true);
create policy "grips_read" on public.grips
  for select to authenticated using (true);
create policy "templates_read" on public.workout_plan_templates
  for select to authenticated using (is_active);
create policy "template_exercises_read" on public.workout_plan_template_exercises
  for select to authenticated using (true);
create policy "quotes_read" on public.quotes
  for select to authenticated using (active);

-- exercises --------------------------------------------------
-- Standardübungen (owner_id null) für alle lesbar, eigene Übungen nur für den Besitzer.
create policy "exercises_select" on public.exercises
  for select to authenticated using (owner_id is null or owner_id = auth.uid());
create policy "exercises_insert_own" on public.exercises
  for insert to authenticated with check (is_custom = true and owner_id = auth.uid());
create policy "exercises_update_own" on public.exercises
  for update to authenticated
  using (is_custom = true and owner_id = auth.uid())
  with check (is_custom = true and owner_id = auth.uid());
create policy "exercises_delete_own" on public.exercises
  for delete to authenticated using (is_custom = true and owner_id = auth.uid());
-- Admins dürfen Standardübungen pflegen
create policy "exercises_admin_all" on public.exercises
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- exercise_muscles -------------------------------------------
create policy "exercise_muscles_select" on public.exercise_muscles
  for select to authenticated using (
    exists (select 1 from public.exercises e where e.id = exercise_id and (e.owner_id is null or e.owner_id = auth.uid()))
  );
create policy "exercise_muscles_insert_own" on public.exercise_muscles
  for insert to authenticated with check (
    exists (select 1 from public.exercises e where e.id = exercise_id and e.owner_id = auth.uid())
  );
create policy "exercise_muscles_delete_own" on public.exercise_muscles
  for delete to authenticated using (
    exists (select 1 from public.exercises e where e.id = exercise_id and e.owner_id = auth.uid())
  );
create policy "exercise_muscles_admin_all" on public.exercise_muscles
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- workout_plans ----------------------------------------------
create policy "plans_all_own" on public.workout_plans
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "plan_exercises_all_own" on public.workout_plan_exercises
  for all to authenticated
  using (exists (select 1 from public.workout_plans p where p.id = plan_id and p.user_id = auth.uid()))
  with check (exists (select 1 from public.workout_plans p where p.id = plan_id and p.user_id = auth.uid()));

-- workout_sessions -------------------------------------------
create policy "sessions_all_own" on public.workout_sessions
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "session_exercises_all_own" on public.workout_session_exercises
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "sets_all_own" on public.workout_sets
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- calendar_entries -------------------------------------------
create policy "calendar_all_own" on public.calendar_entries
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- favorites --------------------------------------------------
create policy "favorites_all_own" on public.favorites
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- body_weight_entries ----------------------------------------
create policy "body_weight_all_own" on public.body_weight_entries
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Standardberechtigungen für Tabellen -------------------------
grant usage on schema public to anon, authenticated;
grant select on public.muscle_groups, public.grips, public.quotes,
  public.workout_plan_templates, public.workout_plan_template_exercises to authenticated;
grant select, insert, update, delete on public.profiles, public.user_settings, public.exercises,
  public.exercise_muscles, public.workout_plans, public.workout_plan_exercises, public.workout_sessions,
  public.workout_session_exercises, public.workout_sets, public.calendar_entries, public.favorites,
  public.body_weight_entries to authenticated;
