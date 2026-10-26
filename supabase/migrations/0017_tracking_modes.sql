-- ============================================================
-- 0017_tracking_modes.sql
-- Drei Tracking-Arten je Übung (Gewicht × Wdh, Körpergewicht, Cardio),
-- Cardio-Sätze mit Dauer und Distanz, Körpergewichts-Sätze mit
-- Körpergewicht-Snapshot und Zusatzgewicht, Trainings nachträglich
-- bearbeitbar (Summen werden per Trigger neu berechnet).
-- ============================================================

-- ------------------------------------------------------------
-- exercises: Tracking-Art und Körpergewichts-Anteil
-- ------------------------------------------------------------
alter table public.exercises
  add column if not exists tracking_mode text not null default 'weight_reps'
    check (tracking_mode in ('weight_reps', 'bodyweight', 'cardio'));
alter table public.exercises
  add column if not exists bodyweight_factor numeric(4, 2) not null default 1.00
    check (bodyweight_factor >= 0 and bodyweight_factor <= 2);

comment on column public.exercises.tracking_mode is
  'weight_reps: Gewicht × Wiederholungen · bodyweight: Körpergewicht × Anteil + Zusatzgewicht · cardio: Dauer und Distanz';
comment on column public.exercises.bodyweight_factor is
  'Anteil des Körpergewichts, der bei Körpergewichtsübungen tatsächlich bewegt wird (1,00 = 100 %)';

-- Tracking-Art wird aus Kategorie und Equipment abgeleitet (auch für Seeds und eigene Übungen)
create or replace function public.derive_tracking_mode()
returns trigger
language plpgsql
as $$
begin
  if new.category = 'cardio' or new.equipment = 'cardio' then
    new.tracking_mode := 'cardio';
  elsif new.equipment = 'bodyweight' then
    new.tracking_mode := 'bodyweight';
  else
    new.tracking_mode := 'weight_reps';
  end if;
  return new;
end;
$$;
drop trigger if exists exercises_derive_tracking on public.exercises;
create trigger exercises_derive_tracking
  before insert or update of category, equipment on public.exercises
  for each row execute function public.derive_tracking_mode();

-- Bestehende Übungen einmal durch den Trigger schicken
update public.exercises set category = category;

-- Körpergewichts-Anteile der Standardübungen
update public.exercises set bodyweight_factor = 0.60 where owner_id is null and slug = 'hyperextensions';
update public.exercises set bodyweight_factor = 0.45 where owner_id is null and slug = 'hanging-knee-raise';
update public.exercises set bodyweight_factor = 0.65 where owner_id is null and slug = 'plank';

-- ------------------------------------------------------------
-- workout_sets: Cardio- und Körpergewichts-Felder
-- ------------------------------------------------------------
alter table public.workout_sets
  add column if not exists duration_seconds integer
    check (duration_seconds is null or (duration_seconds >= 0 and duration_seconds <= 86400));
alter table public.workout_sets
  add column if not exists distance_m integer
    check (distance_m is null or (distance_m >= 0 and distance_m <= 1000000));
alter table public.workout_sets
  add column if not exists body_weight numeric(5, 2)
    check (body_weight is null or (body_weight > 0 and body_weight < 500));
alter table public.workout_sets
  add column if not exists extra_weight numeric(7, 2)
    check (extra_weight is null or (extra_weight >= -500 and extra_weight <= 999));

comment on column public.workout_sets.weight is
  'Bewegte Last. Bei Körpergewichtsübungen: body_weight × bodyweight_factor + extra_weight. Bei Cardio 0.';
comment on column public.workout_sets.duration_seconds is 'Cardio: Dauer in Sekunden';
comment on column public.workout_sets.distance_m is 'Cardio: Distanz in Metern';
comment on column public.workout_sets.body_weight is 'Körpergewichtsübungen: Körpergewicht zum Zeitpunkt des Satzes';
comment on column public.workout_sets.extra_weight is 'Körpergewichtsübungen: Zusatzgewicht (negativ = unterstützt)';

-- ------------------------------------------------------------
-- Summen eines abgeschlossenen Trainings neu berechnen
-- ------------------------------------------------------------
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
    and s.status = 'completed';
end;
$$;
-- Nur für angemeldete Benutzer (wird auch aus complete_workout_session im Benutzerkontext aufgerufen);
-- berechnet ausschließlich bereits abgeschlossene Trainings neu und ist damit idempotent.
revoke all on function public.recalc_session_totals(uuid) from public;
grant execute on function public.recalc_session_totals(uuid) to authenticated;

-- Nach jeder Satzänderung: Summen des (abgeschlossenen) Trainings aktualisieren
create or replace function public.workout_sets_touch_session()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session uuid;
begin
  select se.session_id into v_session
  from public.workout_session_exercises se
  where se.id = coalesce(new.session_exercise_id, old.session_exercise_id);
  if v_session is not null then
    perform public.recalc_session_totals(v_session);
  end if;
  return coalesce(new, old);
end;
$$;
drop trigger if exists workout_sets_recalc on public.workout_sets;
create trigger workout_sets_recalc
  after insert or update or delete on public.workout_sets
  for each row execute function public.workout_sets_touch_session();

-- Übung aus einem Training entfernt: Sätze sind per Cascade weg, Summen neu berechnen
create or replace function public.session_exercises_touch_session()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.recalc_session_totals(old.session_id);
  return old;
end;
$$;
drop trigger if exists session_exercises_recalc on public.workout_session_exercises;
create trigger session_exercises_recalc
  after delete on public.workout_session_exercises
  for each row execute function public.session_exercises_touch_session();

-- Abschließen nutzt dieselbe Berechnung
create or replace function public.complete_workout_session(p_session_id uuid, p_notes text default null, p_local_date date default null)
returns public.workout_sessions
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_session public.workout_sessions;
  v_ended timestamptz := now();
begin
  select * into v_session
  from public.workout_sessions
  where id = p_session_id and user_id = v_user;

  if v_session.id is null then
    raise exception 'Training nicht gefunden' using errcode = 'P0002';
  end if;

  if v_session.status <> 'active' then
    return v_session;
  end if;

  delete from public.workout_sets s
  using public.workout_session_exercises se
  where s.session_exercise_id = se.id
    and se.session_id = p_session_id
    and s.completed = false;

  delete from public.workout_session_exercises se
  where se.session_id = p_session_id
    and not exists (select 1 from public.workout_sets s where s.session_exercise_id = se.id);

  update public.workout_sessions
  set status = 'completed',
      ended_at = v_ended,
      duration_seconds = greatest(0, extract(epoch from (v_ended - started_at))::integer),
      notes = coalesce(p_notes, notes)
  where id = p_session_id;

  perform public.recalc_session_totals(p_session_id);

  select * into v_session from public.workout_sessions where id = p_session_id;

  insert into public.calendar_entries (user_id, entry_date, entry_type)
  values (v_user, coalesce(p_local_date, (v_session.started_at at time zone 'Europe/Berlin')::date), 'training')
  on conflict (user_id, entry_date) do update set entry_type = 'training';

  return v_session;
end;
$$;

-- ------------------------------------------------------------
-- Letzte Leistung je Übung: Cardio- und Körpergewichtsfelder mitliefern
-- ------------------------------------------------------------
drop function if exists public.get_last_exercise_performance(uuid[]);
create function public.get_last_exercise_performance(p_exercise_ids uuid[])
returns table (
  exercise_id uuid,
  session_id uuid,
  started_at timestamptz,
  target_sets integer,
  rep_min integer,
  rep_max integer,
  set_number integer,
  weight numeric,
  reps integer,
  rir integer,
  is_warmup boolean,
  duration_seconds integer,
  distance_m integer,
  body_weight numeric,
  extra_weight numeric
)
language sql
stable
security invoker
set search_path = public
as $$
  with last_sessions as (
    select distinct on (se.exercise_id)
      se.exercise_id, se.id as session_exercise_id, ws.id as session_id, ws.started_at,
      se.target_sets, se.rep_min, se.rep_max
    from public.workout_session_exercises se
    join public.workout_sessions ws on ws.id = se.session_id
    where se.user_id = auth.uid()
      and ws.status = 'completed'
      and se.exercise_id = any (p_exercise_ids)
      and exists (select 1 from public.workout_sets s where s.session_exercise_id = se.id and s.completed)
    order by se.exercise_id, ws.started_at desc
  )
  select ls.exercise_id, ls.session_id, ls.started_at, ls.target_sets, ls.rep_min, ls.rep_max,
         s.set_number, s.weight, s.reps, s.rir, s.is_warmup,
         s.duration_seconds, s.distance_m, s.body_weight, s.extra_weight
  from last_sessions ls
  join public.workout_sets s on s.session_exercise_id = ls.session_exercise_id
  where s.completed
  order by ls.exercise_id, s.set_number;
$$;

-- ------------------------------------------------------------
-- Bestleistungen: zusätzlich Distanz, Dauer und Pace (Cardio)
-- ------------------------------------------------------------
drop function if exists public.get_exercise_records(uuid);
create function public.get_exercise_records(p_exercise_id uuid)
returns table (
  max_weight numeric,
  max_weight_reps integer,
  max_weight_at timestamptz,
  max_reps integer,
  max_reps_weight numeric,
  max_reps_at timestamptz,
  best_est_1rm numeric,
  best_est_1rm_at timestamptz,
  max_session_volume numeric,
  max_session_volume_at timestamptz,
  total_sessions bigint,
  max_distance_m integer,
  max_distance_at timestamptz,
  max_duration_seconds integer,
  max_duration_at timestamptz,
  best_pace_sec_per_km numeric,
  best_pace_at timestamptz
)
language sql
stable
security invoker
set search_path = public
as $$
  with sets as (
    select s.weight, s.reps, s.duration_seconds, s.distance_m, s.completed_at, ws.id as session_id, ws.started_at,
           s.weight * (1 + s.reps / 30.0) as est_1rm
    from public.workout_sets s
    join public.workout_session_exercises se on se.id = s.session_exercise_id
    join public.workout_sessions ws on ws.id = se.session_id
    where se.user_id = auth.uid()
      and se.exercise_id = p_exercise_id
      and ws.status = 'completed'
      and s.completed
      and s.is_warmup = false
  ),
  lifted as (select * from sets where reps > 0),
  by_session as (
    select session_id, started_at, sum(weight * reps) as volume
    from sets group by session_id, started_at
  ),
  mw as (select weight, reps, started_at from lifted order by weight desc, reps desc limit 1),
  mr as (select reps, weight, started_at from lifted order by reps desc, weight desc limit 1),
  m1 as (select est_1rm, started_at from lifted order by est_1rm desc limit 1),
  mv as (select volume, started_at from by_session where volume > 0 order by volume desc limit 1),
  md as (select distance_m, started_at from sets where distance_m > 0 order by distance_m desc limit 1),
  mt as (select duration_seconds, started_at from sets where duration_seconds > 0 order by duration_seconds desc limit 1),
  mp as (
    select duration_seconds::numeric / (distance_m / 1000.0) as pace, started_at
    from sets where distance_m >= 500 and duration_seconds > 0
    order by pace asc limit 1
  )
  select
    (select weight from mw), (select reps from mw), (select started_at from mw),
    (select reps from mr), (select weight from mr), (select started_at from mr),
    (select round(est_1rm, 1) from m1), (select started_at from m1),
    (select volume from mv), (select started_at from mv),
    (select count(*) from by_session),
    (select distance_m from md), (select started_at from md),
    (select duration_seconds from mt), (select started_at from mt),
    (select round(pace, 0) from mp), (select started_at from mp);
$$;

-- ------------------------------------------------------------
-- Verlauf einer Übung: zusätzlich Dauer und Distanz je Training
-- ------------------------------------------------------------
drop function if exists public.get_exercise_history(uuid, timestamptz);
create function public.get_exercise_history(p_exercise_id uuid, p_from timestamptz default null)
returns table (
  session_id uuid,
  started_at timestamptz,
  max_weight numeric,
  max_reps integer,
  top_set_weight numeric,
  top_set_reps integer,
  est_1rm numeric,
  volume numeric,
  sets integer,
  total_duration_seconds integer,
  total_distance_m integer
)
language sql
stable
security invoker
set search_path = public
as $$
  with sets as (
    select ws.id as session_id, ws.started_at, s.weight, s.reps, s.duration_seconds, s.distance_m,
           s.weight * (1 + s.reps / 30.0) as est_1rm
    from public.workout_sets s
    join public.workout_session_exercises se on se.id = s.session_exercise_id
    join public.workout_sessions ws on ws.id = se.session_id
    where se.user_id = auth.uid()
      and se.exercise_id = p_exercise_id
      and ws.status = 'completed'
      and s.completed
      and s.is_warmup = false
      and (p_from is null or ws.started_at >= p_from)
  ),
  top as (
    select distinct on (session_id) session_id, weight as top_set_weight, reps as top_set_reps
    from sets order by session_id, est_1rm desc
  )
  select s.session_id, s.started_at,
         max(s.weight) as max_weight,
         max(s.reps) as max_reps,
         t.top_set_weight, t.top_set_reps,
         round(max(s.est_1rm), 1) as est_1rm,
         sum(s.weight * s.reps) as volume,
         count(*)::integer as sets,
         coalesce(sum(s.duration_seconds), 0)::integer as total_duration_seconds,
         coalesce(sum(s.distance_m), 0)::integer as total_distance_m
  from sets s
  join top t on t.session_id = s.session_id
  group by s.session_id, s.started_at, t.top_set_weight, t.top_set_reps
  order by s.started_at;
$$;

-- ------------------------------------------------------------
-- Mitglieder-Detail: Tracking-Art und Cardio-/Körpergewichtsfelder im JSON
-- ------------------------------------------------------------
create or replace function public.get_member_session_detail(p_session_id uuid)
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

  select jsonb_build_object(
    'session', jsonb_build_object(
      'id', s.id,
      'user_id', s.user_id,
      'nickname', coalesce(p.nickname, 'Benutzer'),
      'name', s.name,
      'started_at', s.started_at,
      'ended_at', s.ended_at,
      'duration_seconds', s.duration_seconds,
      'total_volume', s.total_volume,
      'total_sets', s.total_sets,
      'notes', s.notes
    ),
    'exercises', coalesce(
      (select jsonb_agg(
         jsonb_build_object(
           'id', se.id,
           'sort_order', se.sort_order,
           'target_sets', se.target_sets,
           'rep_min', se.rep_min,
           'rep_max', se.rep_max,
           'exercise', jsonb_build_object(
             'id', e.id,
             'slug', e.slug,
             'name', e.name,
             'category', e.category,
             'equipment', e.equipment,
             'tracking_mode', e.tracking_mode
           ),
           'sets', coalesce(
             (select jsonb_agg(
                jsonb_build_object(
                  'set_number', ws.set_number,
                  'weight', ws.weight,
                  'reps', ws.reps,
                  'rir', ws.rir,
                  'is_warmup', ws.is_warmup,
                  'duration_seconds', ws.duration_seconds,
                  'distance_m', ws.distance_m,
                  'body_weight', ws.body_weight,
                  'extra_weight', ws.extra_weight
                ) order by ws.set_number)
                from public.workout_sets ws
               where ws.session_exercise_id = se.id
                 and ws.completed),
             '[]'::jsonb
           )
         ) order by se.sort_order)
         from public.workout_session_exercises se
         join public.exercises e on e.id = se.exercise_id
        where se.session_id = s.id),
      '[]'::jsonb
    )
  )
  into v_result
  from public.workout_sessions s
  left join public.profiles p on p.id = s.user_id
  where s.id = p_session_id
    and s.status = 'completed';

  return v_result;
end;
$$;

-- ------------------------------------------------------------
-- Seed-Hilfsfunktion: bodyweight_factor aus JSON übernehmen
-- ------------------------------------------------------------
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
    muscle_focus, requirements, grip_alternatives, machine_name, alternative_exercises, bodyweight_factor
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
    coalesce((p ->> 'bodyweight_factor')::numeric, 1.00)
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
    animation_url = coalesce(public.exercises.animation_url, excluded.animation_url),
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
