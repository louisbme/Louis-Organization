-- ============================================================
-- 0019_body_data_cardio_targets.sql
-- 1) Körperdaten im Profil (Größe, Geburtsdatum); das Gewicht bleibt als
--    Verlauf in body_weight_entries und wird für Körpergewichtsübungen genutzt
-- 2) Cardio-Ziele im Plan: Dauer und Distanz je Einheit (auch im Training)
-- ============================================================

-- ------------------------------------------------------------
-- 1) Körperdaten
-- ------------------------------------------------------------
alter table public.profiles
  add column if not exists height_cm numeric(4, 1)
    check (height_cm is null or (height_cm >= 100 and height_cm <= 250));
alter table public.profiles
  add column if not exists birth_date date
    check (birth_date is null or birth_date > date '1900-01-01');

comment on column public.profiles.height_cm is 'Körpergröße in Zentimetern (optional, für BMI)';
comment on column public.profiles.birth_date is 'Geburtsdatum (optional, für Alter)';

-- ------------------------------------------------------------
-- 2) Cardio-Ziele
-- ------------------------------------------------------------
alter table public.workout_plan_exercises
  add column if not exists target_duration_seconds integer
    check (target_duration_seconds is null or (target_duration_seconds >= 0 and target_duration_seconds <= 86400));
alter table public.workout_plan_exercises
  add column if not exists target_distance_m integer
    check (target_distance_m is null or (target_distance_m >= 0 and target_distance_m <= 1000000));

alter table public.workout_session_exercises
  add column if not exists target_duration_seconds integer
    check (target_duration_seconds is null or (target_duration_seconds >= 0 and target_duration_seconds <= 86400));
alter table public.workout_session_exercises
  add column if not exists target_distance_m integer
    check (target_distance_m is null or (target_distance_m >= 0 and target_distance_m <= 1000000));

comment on column public.workout_plan_exercises.target_duration_seconds is 'Cardio: Zieldauer je Einheit in Sekunden';
comment on column public.workout_plan_exercises.target_distance_m is 'Cardio: Zieldistanz je Einheit in Metern';

-- Training starten: Cardio-Ziele aus dem Plan übernehmen
create or replace function public.start_workout_session(p_plan_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_plan record;
  v_session_id uuid;
begin
  if v_user is null then
    raise exception 'Nicht angemeldet' using errcode = '42501';
  end if;

  select id, name into v_plan
  from public.workout_plans
  where id = p_plan_id and user_id = v_user;

  if v_plan.id is null then
    raise exception 'Trainingsplan nicht gefunden' using errcode = 'P0002';
  end if;

  select id into v_session_id
  from public.workout_sessions
  where user_id = v_user and status = 'active'
  order by started_at desc
  limit 1;

  if v_session_id is not null then
    return v_session_id;
  end if;

  insert into public.workout_sessions (user_id, plan_id, name)
  values (v_user, v_plan.id, v_plan.name)
  returning id into v_session_id;

  insert into public.workout_session_exercises
    (session_id, user_id, exercise_id, sort_order, target_sets, rep_min, rep_max, target_duration_seconds, target_distance_m)
  select v_session_id, v_user, pe.exercise_id, pe.sort_order, pe.target_sets, pe.rep_min, pe.rep_max, pe.target_duration_seconds, pe.target_distance_m
  from public.workout_plan_exercises pe
  where pe.plan_id = v_plan.id
  order by pe.sort_order;

  return v_session_id;
end;
$$;

-- Pläne anderer Mitglieder: Cardio-Ziele mitliefern
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
        'tracking_mode', e.tracking_mode,
        'sort_order', pe.sort_order,
        'target_sets', pe.target_sets,
        'rep_min', pe.rep_min,
        'rep_max', pe.rep_max,
        'target_duration_seconds', pe.target_duration_seconds,
        'target_distance_m', pe.target_distance_m
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

-- Plan kopieren: Cardio-Ziele mitkopieren
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

  insert into public.workout_plan_exercises
    (plan_id, exercise_id, sort_order, target_sets, rep_min, rep_max, notes, target_duration_seconds, target_distance_m)
  select v_new, pe.exercise_id, pe.sort_order, pe.target_sets, pe.rep_min, pe.rep_max, pe.notes, pe.target_duration_seconds, pe.target_distance_m
  from public.workout_plan_exercises pe
  join public.exercises e on e.id = pe.exercise_id
  where pe.plan_id = v_src.id
    and (e.owner_id is null or e.owner_id = v_user)
  order by pe.sort_order;

  return v_new;
end;
$$;
