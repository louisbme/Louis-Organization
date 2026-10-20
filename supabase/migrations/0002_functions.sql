-- ============================================================
-- 0002_functions.sql
-- Trigger, Hilfsfunktionen und RPCs
-- ============================================================

-- ------------------------------------------------------------
-- Rolle prüfen
-- ------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role = 'admin' from public.profiles where id = auth.uid()),
    false
  );
$$;

-- Verhindert, dass normale Benutzer ihre Rolle selbst ändern
create or replace function public.protect_profile_role()
returns trigger
language plpgsql
as $$
begin
  if new.role is distinct from old.role and not public.is_admin() then
    raise exception 'Rolle kann nicht geändert werden' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger profiles_protect_role before update on public.profiles
  for each row execute function public.protect_profile_role();

-- ------------------------------------------------------------
-- Nickname-Verfügbarkeit (auch für nicht angemeldete Benutzer bei Registrierung)
-- ------------------------------------------------------------
create or replace function public.is_nickname_available(p_nickname text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
    select 1 from public.profiles
    where lower(nickname) = lower(trim(p_nickname))
      and id is distinct from auth.uid()
  );
$$;
revoke all on function public.is_nickname_available(text) from public;
grant execute on function public.is_nickname_available(text) to anon, authenticated;

-- ------------------------------------------------------------
-- Standardpläne für einen Benutzer aus den Vorlagen kopieren
-- ------------------------------------------------------------
create or replace function public.copy_template_plans_to_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  t record;
  new_plan_id uuid;
begin
  for t in
    select id, name, sort_order
    from public.workout_plan_templates
    where is_active
    order by sort_order
  loop
    insert into public.workout_plans (user_id, template_id, name, sort_order)
    values (p_user_id, t.id, t.name, t.sort_order)
    returning id into new_plan_id;

    insert into public.workout_plan_exercises (plan_id, exercise_id, sort_order, target_sets, rep_min, rep_max)
    select new_plan_id, te.exercise_id, te.sort_order, te.target_sets, te.rep_min, te.rep_max
    from public.workout_plan_template_exercises te
    where te.template_id = t.id
    order by te.sort_order;
  end loop;
end;
$$;
revoke all on function public.copy_template_plans_to_user(uuid) from public;

-- ------------------------------------------------------------
-- Neuer Benutzer: Profil, Einstellungen, Standardpläne
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nickname text;
begin
  v_nickname := nullif(trim(coalesce(new.raw_user_meta_data ->> 'nickname', '')), '');

  if v_nickname is null
     or char_length(v_nickname) < 3
     or char_length(v_nickname) > 20
     or v_nickname !~ '^[A-Za-z0-9_.-]+$'
     or exists (select 1 from public.profiles where lower(nickname) = lower(v_nickname)) then
    v_nickname := 'user_' || substr(replace(new.id::text, '-', ''), 1, 8);
  end if;

  insert into public.profiles (id, nickname) values (new.id, v_nickname);
  insert into public.user_settings (user_id) values (new.id);
  perform public.copy_template_plans_to_user(new.id);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------
-- Training starten: Session + Übungen aus Plan kopieren
-- ------------------------------------------------------------
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

  -- Bereits aktives Training? Dann dieses zurückgeben.
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

  insert into public.workout_session_exercises (session_id, user_id, exercise_id, sort_order, target_sets, rep_min, rep_max)
  select v_session_id, v_user, pe.exercise_id, pe.sort_order, pe.target_sets, pe.rep_min, pe.rep_max
  from public.workout_plan_exercises pe
  where pe.plan_id = v_plan.id
  order by pe.sort_order;

  return v_session_id;
end;
$$;

-- ------------------------------------------------------------
-- Training abschließen: Dauer, Volumen, Kalender
-- ------------------------------------------------------------
create or replace function public.complete_workout_session(p_session_id uuid, p_notes text default null, p_local_date date default null)
returns public.workout_sessions
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_session public.workout_sessions;
  v_volume numeric(12, 2);
  v_sets integer;
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

  -- Nicht abgeschlossene Sätze entfernen
  delete from public.workout_sets s
  using public.workout_session_exercises se
  where s.session_exercise_id = se.id
    and se.session_id = p_session_id
    and s.completed = false;

  -- Übungen ohne Sätze entfernen
  delete from public.workout_session_exercises se
  where se.session_id = p_session_id
    and not exists (select 1 from public.workout_sets s where s.session_exercise_id = se.id);

  select coalesce(sum(s.weight * s.reps), 0), coalesce(count(*), 0)
  into v_volume, v_sets
  from public.workout_sets s
  join public.workout_session_exercises se on se.id = s.session_exercise_id
  where se.session_id = p_session_id
    and s.completed
    and s.is_warmup = false;

  update public.workout_sessions
  set status = 'completed',
      ended_at = v_ended,
      duration_seconds = greatest(0, extract(epoch from (v_ended - started_at))::integer),
      total_volume = v_volume,
      total_sets = v_sets,
      notes = coalesce(p_notes, notes)
  where id = p_session_id
  returning * into v_session;

  insert into public.calendar_entries (user_id, entry_date, entry_type)
  values (v_user, coalesce(p_local_date, (v_session.started_at at time zone 'Europe/Berlin')::date), 'training')
  on conflict (user_id, entry_date) do update set entry_type = 'training';

  return v_session;
end;
$$;

-- ------------------------------------------------------------
-- Training abbrechen
-- ------------------------------------------------------------
create or replace function public.cancel_workout_session(p_session_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  delete from public.workout_sessions
  where id = p_session_id and user_id = auth.uid() and status = 'active';
end;
$$;

-- ------------------------------------------------------------
-- Letzte Leistung je Übung (für Vorschlag + "Vorher"-Anzeige)
-- ------------------------------------------------------------
create or replace function public.get_last_exercise_performance(p_exercise_ids uuid[])
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
  is_warmup boolean
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
         s.set_number, s.weight, s.reps, s.rir, s.is_warmup
  from last_sessions ls
  join public.workout_sets s on s.session_exercise_id = ls.session_exercise_id
  where s.completed
  order by ls.exercise_id, s.set_number;
$$;

-- ------------------------------------------------------------
-- Persönliche Statistiken des aktuellen Benutzers
-- ------------------------------------------------------------
create or replace function public.get_user_stats()
returns table (
  total_workouts bigint,
  total_duration_seconds bigint,
  total_volume numeric,
  total_sets bigint,
  distinct_exercises bigint,
  last_workout_at timestamptz
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    count(*) as total_workouts,
    coalesce(sum(duration_seconds), 0)::bigint as total_duration_seconds,
    coalesce(sum(total_volume), 0) as total_volume,
    coalesce(sum(total_sets), 0)::bigint as total_sets,
    (select count(distinct se.exercise_id)
       from public.workout_session_exercises se
       join public.workout_sessions s2 on s2.id = se.session_id
      where se.user_id = auth.uid() and s2.status = 'completed') as distinct_exercises,
    max(started_at) as last_workout_at
  from public.workout_sessions
  where user_id = auth.uid() and status = 'completed';
$$;

-- ------------------------------------------------------------
-- Gruppen-Statistik (nur aggregierte Werte, nur für angemeldete Benutzer)
-- ------------------------------------------------------------
create or replace function public.get_group_stats()
returns table (
  user_id uuid,
  nickname text,
  total_workouts bigint,
  total_duration_seconds bigint,
  total_volume numeric,
  last_workout_at timestamptz,
  member_since timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id as user_id,
    p.nickname,
    count(s.id) as total_workouts,
    coalesce(sum(s.duration_seconds), 0)::bigint as total_duration_seconds,
    coalesce(sum(s.total_volume), 0) as total_volume,
    max(s.started_at) as last_workout_at,
    p.created_at as member_since
  from public.profiles p
  left join public.workout_sessions s on s.user_id = p.id and s.status = 'completed'
  where auth.uid() is not null
  group by p.id, p.nickname, p.created_at
  order by total_workouts desc, p.nickname asc;
$$;
revoke all on function public.get_group_stats() from public;
grant execute on function public.get_group_stats() to authenticated;

-- ------------------------------------------------------------
-- Bestleistungen je Übung
-- ------------------------------------------------------------
create or replace function public.get_exercise_records(p_exercise_id uuid)
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
  total_sessions bigint
)
language sql
stable
security invoker
set search_path = public
as $$
  with sets as (
    select s.weight, s.reps, s.completed_at, ws.id as session_id, ws.started_at,
           s.weight * (1 + s.reps / 30.0) as est_1rm
    from public.workout_sets s
    join public.workout_session_exercises se on se.id = s.session_exercise_id
    join public.workout_sessions ws on ws.id = se.session_id
    where se.user_id = auth.uid()
      and se.exercise_id = p_exercise_id
      and ws.status = 'completed'
      and s.completed
      and s.is_warmup = false
      and s.reps > 0
  ),
  by_session as (
    select session_id, started_at, sum(weight * reps) as volume
    from sets group by session_id, started_at
  ),
  mw as (select weight, reps, started_at from sets order by weight desc, reps desc limit 1),
  mr as (select reps, weight, started_at from sets order by reps desc, weight desc limit 1),
  m1 as (select est_1rm, started_at from sets order by est_1rm desc limit 1),
  mv as (select volume, started_at from by_session order by volume desc limit 1)
  select
    (select weight from mw), (select reps from mw), (select started_at from mw),
    (select reps from mr), (select weight from mr), (select started_at from mr),
    (select round(est_1rm, 1) from m1), (select started_at from m1),
    (select volume from mv), (select started_at from mv),
    (select count(*) from by_session);
$$;

-- ------------------------------------------------------------
-- Verlauf einer Übung (für Fortschrittsgrafiken)
-- ------------------------------------------------------------
create or replace function public.get_exercise_history(p_exercise_id uuid, p_from timestamptz default null)
returns table (
  session_id uuid,
  started_at timestamptz,
  max_weight numeric,
  max_reps integer,
  top_set_weight numeric,
  top_set_reps integer,
  est_1rm numeric,
  volume numeric,
  sets integer
)
language sql
stable
security invoker
set search_path = public
as $$
  with sets as (
    select ws.id as session_id, ws.started_at, s.weight, s.reps,
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
         count(*)::integer as sets
  from sets s
  join top t on t.session_id = s.session_id
  group by s.session_id, s.started_at, t.top_set_weight, t.top_set_reps
  order by s.started_at;
$$;

-- ------------------------------------------------------------
-- Seed-Hilfsfunktion: Übung aus JSON anlegen/aktualisieren (nur für Migrationen)
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
    muscle_focus, requirements, grip_alternatives
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
    coalesce(array(select jsonb_array_elements_text(p -> 'grip_alternatives')), '{}')
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
    image_url = coalesce(public.exercises.image_url, excluded.image_url),
    animation_url = coalesce(public.exercises.animation_url, excluded.animation_url),
    muscle_focus = excluded.muscle_focus,
    requirements = excluded.requirements,
    grip_alternatives = excluded.grip_alternatives
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
-- Seed-Hilfsfunktion: Vorlagenplan aus JSON anlegen
-- p = {"name": "...", "sort_order": 1, "exercises": [{"slug": "...", "sets": 3, "rep_min": 6, "rep_max": 10}, ...]}
-- ------------------------------------------------------------
create or replace function public.upsert_seed_template(p jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_template_id uuid;
  e jsonb;
  v_exercise_id uuid;
  i integer := 0;
begin
  select id into v_template_id from public.workout_plan_templates where name = p ->> 'name';

  if v_template_id is null then
    insert into public.workout_plan_templates (name, sort_order)
    values (p ->> 'name', coalesce((p ->> 'sort_order')::integer, 0))
    returning id into v_template_id;
  else
    update public.workout_plan_templates
    set sort_order = coalesce((p ->> 'sort_order')::integer, sort_order)
    where id = v_template_id;
    delete from public.workout_plan_template_exercises where template_id = v_template_id;
  end if;

  for e in select jsonb_array_elements(p -> 'exercises') loop
    i := i + 1;
    select id into v_exercise_id from public.exercises where slug = e ->> 'slug' and owner_id is null;
    if v_exercise_id is null then
      raise exception 'Übung mit Slug % nicht gefunden', e ->> 'slug';
    end if;
    insert into public.workout_plan_template_exercises (template_id, exercise_id, sort_order, target_sets, rep_min, rep_max)
    values (v_template_id, v_exercise_id, i, (e ->> 'sets')::integer, (e ->> 'rep_min')::integer, (e ->> 'rep_max')::integer);
  end loop;

  return v_template_id;
end;
$$;
revoke all on function public.upsert_seed_template(jsonb) from public;
