-- ============================================================
-- 0018_portfolio_admin_sharing.sql
-- 1) Eigene Übungen werden Standardübungen (gemeinsames Portfolio)
-- 2) Quelle der Ausführungs-Animation (Nachweis und Link)
-- 3) Admins dürfen Trainingsdaten anderer Nutzer lesen und bearbeiten
-- 4) Trainingspläne anderer Mitglieder ansehen und kopieren
-- ============================================================

-- ------------------------------------------------------------
-- 1) Eigene Übungen ins Portfolio übernehmen
--    Slug ohne Benutzer-Suffix (-uXXXX), falls frei; IDs bleiben erhalten,
--    damit Pläne, Trainings und Favoriten weiter darauf zeigen.
-- ------------------------------------------------------------
create or replace function public.promote_custom_exercises()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_base text;
  v_count integer := 0;
begin
  for r in select id, slug from public.exercises where is_custom = true order by created_at loop
    v_base := regexp_replace(r.slug, '-u[a-z0-9]{4}$', '');
    if exists (select 1 from public.exercises g where g.owner_id is null and g.slug = v_base) then
      v_base := r.slug;
    end if;
    update public.exercises
    set is_custom = false, owner_id = null, slug = v_base
    where id = r.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke all on function public.promote_custom_exercises() from public;

select public.promote_custom_exercises();

-- ------------------------------------------------------------
-- 2) Quelle der Animation
-- ------------------------------------------------------------
alter table public.exercises add column if not exists animation_source_url text;
comment on column public.exercises.animation_source_url is 'Seite, von der die Ausführungs-Animation stammt (Nachweis, Link)';

create or replace function public.upsert_seed_exercise(p jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  m text;
begin
  insert into public.exercises (
    slug, name, category, equipment, grip_id, grip_notes, description,
    setup, execution, range_of_motion, breathing, common_mistakes, tips, cable_setup, image_url, animation_url,
    muscle_focus, requirements, grip_alternatives, machine_name, alternative_exercises, bodyweight_factor, animation_source_url
  ) values (
    p ->> 'slug',
    p ->> 'name',
    (p ->> 'category')::public.exercise_category,
    (p ->> 'equipment')::public.equipment_type,
    nullif(p ->> 'grip_id', ''),
    nullif(p ->> 'grip_notes', ''),
    p ->> 'description',
    coalesce(array(select jsonb_array_elements_text(p -> 'setup')), '{}'),
    coalesce(array(select jsonb_array_elements_text(p -> 'execution')), '{}'),
    p ->> 'range_of_motion',
    p ->> 'breathing',
    coalesce(array(select jsonb_array_elements_text(p -> 'common_mistakes')), '{}'),
    coalesce(array(select jsonb_array_elements_text(p -> 'tips')), '{}'),
    case when jsonb_typeof(p -> 'cable_setup') = 'object' then p -> 'cable_setup' else null end,
    nullif(p ->> 'image_url', ''),
    nullif(p ->> 'animation_url', ''),
    coalesce(array(select jsonb_array_elements_text(p -> 'muscle_focus')), '{}'),
    coalesce(array(select jsonb_array_elements_text(p -> 'requirements')), '{}'),
    coalesce(array(select jsonb_array_elements_text(p -> 'grip_alternatives')), '{}'),
    nullif(p ->> 'machine_name', ''),
    coalesce(array(select jsonb_array_elements_text(p -> 'alternative_exercises')), '{}'),
    coalesce((p ->> 'bodyweight_factor')::numeric, 1.00),
    nullif(p ->> 'animation_source_url', '')
  )
  on conflict (slug) where owner_id is null do update set
    name = excluded.name,
    category = excluded.category,
    equipment = excluded.equipment,
    grip_id = excluded.grip_id,
    grip_notes = excluded.grip_notes,
    description = excluded.description,
    setup = excluded.setup,
    execution = excluded.execution,
    range_of_motion = excluded.range_of_motion,
    breathing = excluded.breathing,
    common_mistakes = excluded.common_mistakes,
    tips = excluded.tips,
    cable_setup = excluded.cable_setup,
    image_url = excluded.image_url,
    -- Seed-Animation hat Vorrang; ohne Seed-Wert bleibt eine manuell gesetzte erhalten
    animation_url = coalesce(excluded.animation_url, public.exercises.animation_url),
    animation_source_url = coalesce(excluded.animation_source_url, public.exercises.animation_source_url),
    muscle_focus = excluded.muscle_focus,
    requirements = excluded.requirements,
    grip_alternatives = excluded.grip_alternatives,
    machine_name = excluded.machine_name,
    alternative_exercises = excluded.alternative_exercises,
    bodyweight_factor = excluded.bodyweight_factor
  returning id into v_id;

  delete from public.exercise_muscles where exercise_id = v_id;

  for m in select jsonb_array_elements_text(p -> 'primary_muscles') loop
    insert into public.exercise_muscles (exercise_id, muscle_id, role)
    values (v_id, m, 'primary') on conflict do nothing;
  end loop;

  for m in select jsonb_array_elements_text(p -> 'secondary_muscles') loop
    insert into public.exercise_muscles (exercise_id, muscle_id, role)
    values (v_id, m, 'secondary') on conflict do nothing;
  end loop;

  return v_id;
end;
$$;
revoke all on function public.upsert_seed_exercise(jsonb) from public;

-- ------------------------------------------------------------
-- 3) Admins: Trainingsdaten (Trainings, Sätze, Pläne) und Profile anderer Nutzer
--    is_admin() in (select …) gekapselt, damit es je Abfrage nur einmal ausgewertet wird.
-- ------------------------------------------------------------
drop policy if exists "profiles_admin_select" on public.profiles;
create policy "profiles_admin_select" on public.profiles
  for select to authenticated using ((select public.is_admin()));

drop policy if exists "sessions_admin_all" on public.workout_sessions;
create policy "sessions_admin_all" on public.workout_sessions
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists "session_exercises_admin_all" on public.workout_session_exercises;
create policy "session_exercises_admin_all" on public.workout_session_exercises
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists "sets_admin_all" on public.workout_sets;
create policy "sets_admin_all" on public.workout_sets
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists "plans_admin_all" on public.workout_plans;
create policy "plans_admin_all" on public.workout_plans
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists "plan_exercises_admin_all" on public.workout_plan_exercises;
create policy "plan_exercises_admin_all" on public.workout_plan_exercises
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists "body_weight_admin_select" on public.body_weight_entries;
create policy "body_weight_admin_select" on public.body_weight_entries
  for select to authenticated using ((select public.is_admin()));

-- Summen auch dann neu berechnen, wenn ein Admin fremde Sätze bearbeitet
create or replace function public.recalc_session_totals(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.workout_sessions s
  set total_volume = coalesce((
        select sum(w.weight * w.reps)
        from public.workout_sets w
        join public.workout_session_exercises se on se.id = w.session_exercise_id
        where se.session_id = s.id and w.completed and w.is_warmup = false
      ), 0),
      total_sets = coalesce((
        select count(*)
        from public.workout_sets w
        join public.workout_session_exercises se on se.id = w.session_exercise_id
        where se.session_id = s.id and w.completed and w.is_warmup = false
      ), 0)
  where s.id = p_session_id
    and s.status = 'completed'
    and (auth.uid() is null or s.user_id = auth.uid() or public.is_admin());
end;
$$;

-- ------------------------------------------------------------
-- 4) Trainingspläne anderer Mitglieder ansehen und kopieren
-- ------------------------------------------------------------
create or replace function public.get_member_plans(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Nicht angemeldet' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'name', p.name,
    'sort_order', p.sort_order,
    'exercises', coalesce((
      select jsonb_agg(jsonb_build_object(
        'exercise_id', pe.exercise_id,
        'name', e.name,
        'slug', e.slug,
        'sort_order', pe.sort_order,
        'target_sets', pe.target_sets,
        'rep_min', pe.rep_min,
        'rep_max', pe.rep_max
      ) order by pe.sort_order)
      from public.workout_plan_exercises pe
      join public.exercises e on e.id = pe.exercise_id
      where pe.plan_id = p.id
    ), '[]'::jsonb)
  ) order by p.sort_order), '[]'::jsonb)
  into v_result
  from public.workout_plans p
  where p.user_id = p_user_id
    and p.is_archived = false;

  return v_result;
end;
$$;
revoke all on function public.get_member_plans(uuid) from public;
grant execute on function public.get_member_plans(uuid) to authenticated;

create or replace function public.copy_member_plan(p_plan_id uuid, p_name text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_src record;
  v_owner text;
  v_name text;
  v_order integer;
  v_new uuid;
begin
  if v_user is null then
    raise exception 'Nicht angemeldet' using errcode = '42501';
  end if;

  select id, user_id, name into v_src
  from public.workout_plans
  where id = p_plan_id and is_archived = false;
  if v_src.id is null then
    raise exception 'Trainingsplan nicht gefunden' using errcode = 'P0002';
  end if;

  select nickname into v_owner from public.profiles where id = v_src.user_id;
  v_name := left(coalesce(nullif(trim(p_name), ''), v_src.name || ' (von ' || coalesce(v_owner, 'Mitglied') || ')'), 60);

  select coalesce(max(sort_order), 0) + 1 into v_order from public.workout_plans where user_id = v_user;

  insert into public.workout_plans (user_id, name, sort_order)
  values (v_user, v_name, v_order)
  returning id into v_new;

  insert into public.workout_plan_exercises (plan_id, exercise_id, sort_order, target_sets, rep_min, rep_max, notes)
  select v_new, pe.exercise_id, pe.sort_order, pe.target_sets, pe.rep_min, pe.rep_max, pe.notes
  from public.workout_plan_exercises pe
  join public.exercises e on e.id = pe.exercise_id
  where pe.plan_id = v_src.id
    -- nur Übungen, die der Kopierende sehen darf (Standard oder eigene)
    and (e.owner_id is null or e.owner_id = v_user)
  order by pe.sort_order;

  return v_new;
end;
$$;
revoke all on function public.copy_member_plan(uuid, text) from public;
grant execute on function public.copy_member_plan(uuid, text) to authenticated;
