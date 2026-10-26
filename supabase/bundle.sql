-- ============================================================
-- bundle.sql – alle Migrationen in Reihenfolge (GENERIERT via `npm run db:generate`)
-- Für den Supabase SQL-Editor: komplette Datei einfügen und ausführen.
-- ============================================================


-- >>>>>>>>>> 0001_schema.sql <<<<<<<<<<

-- ============================================================
-- 0001_schema.sql
-- Fitness Tracker: Tabellen, Typen, Indexe, Foreign Keys
-- ============================================================

-- gen_random_uuid() ist seit PostgreSQL 13 Teil des Kerns, keine Extension nötig.

-- ------------------------------------------------------------
-- Enum-Typen
-- ------------------------------------------------------------
create type public.muscle_role as enum ('primary', 'secondary');
create type public.equipment_type as enum (
  'machine', 'cable', 'barbell', 'dumbbell', 'bodyweight', 'smith_machine', 'bench', 'other', 'cardio'
);
create type public.exercise_category as enum (
  'chest', 'back', 'shoulders', 'biceps', 'triceps', 'quads', 'hamstrings', 'glutes', 'calves', 'abs', 'forearms', 'adductors', 'cardio'
);
create type public.session_status as enum ('active', 'completed', 'cancelled');
create type public.calendar_entry_type as enum ('training', 'rest', 'leisure', 'party', 'other');
create type public.weight_unit as enum ('kg', 'lb');
create type public.theme_preference as enum ('dark', 'light', 'system');
create type public.user_role as enum ('user', 'admin');

-- ------------------------------------------------------------
-- Hilfsfunktion: updated_at automatisch setzen
-- ------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ------------------------------------------------------------
-- profiles
-- ------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  nickname text not null,
  role public.user_role not null default 'user',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_nickname_length check (char_length(nickname) between 3 and 20),
  constraint profiles_nickname_format check (nickname ~ '^[A-Za-z0-9_.-]+$')
);
create unique index profiles_nickname_lower_idx on public.profiles (lower(nickname));
create trigger profiles_set_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- user_settings
-- ------------------------------------------------------------
create table public.user_settings (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  weight_unit public.weight_unit not null default 'kg',
  weight_step numeric(5, 2) not null default 2.5 check (weight_step > 0 and weight_step <= 50),
  rest_timer_default integer not null default 90 check (rest_timer_default between 10 and 600),
  show_rir boolean not null default false,
  theme public.theme_preference not null default 'dark',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger user_settings_set_updated_at before update on public.user_settings
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- muscle_groups (statische Stammdaten)
-- ------------------------------------------------------------
create table public.muscle_groups (
  id text primary key,
  name_de text not null,
  region text not null check (region in ('front', 'back', 'both')),
  sort_order integer not null default 0
);

-- ------------------------------------------------------------
-- grips (Kabelzug-Griffe, statische Stammdaten)
-- ------------------------------------------------------------
create table public.grips (
  id text primary key,
  name_de text not null,
  description text not null,
  sort_order integer not null default 0
);

-- ------------------------------------------------------------
-- exercises
-- ------------------------------------------------------------
create table public.exercises (
  id uuid primary key default gen_random_uuid(),
  slug text not null,
  name text not null,
  category public.exercise_category not null,
  equipment public.equipment_type not null,
  grip_id text references public.grips (id) on delete set null,
  grip_notes text,
  description text,
  setup text[] not null default '{}',
  execution text[] not null default '{}',
  range_of_motion text,
  breathing text,
  common_mistakes text[] not null default '{}',
  tips text[] not null default '{}',
  cable_setup jsonb,
  image_url text,
  animation_url text,
  muscle_focus text[] not null default '{}',
  requirements text[] not null default '{}',
  grip_alternatives text[] not null default '{}',
  machine_name text,
  alternative_exercises text[] not null default '{}',
  is_custom boolean not null default false,
  owner_id uuid references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint exercises_name_length check (char_length(name) between 2 and 80),
  constraint exercises_slug_format check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint exercises_custom_owner check (
    (is_custom = false and owner_id is null) or (is_custom = true and owner_id is not null)
  )
);
create unique index exercises_slug_global_idx on public.exercises (slug) where owner_id is null;
create unique index exercises_slug_owner_idx on public.exercises (owner_id, slug) where owner_id is not null;
create index exercises_owner_idx on public.exercises (owner_id);
create index exercises_category_idx on public.exercises (category);
create index exercises_equipment_idx on public.exercises (equipment);
create trigger exercises_set_updated_at before update on public.exercises
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- exercise_muscles
-- ------------------------------------------------------------
create table public.exercise_muscles (
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  muscle_id text not null references public.muscle_groups (id) on delete cascade,
  role public.muscle_role not null,
  primary key (exercise_id, muscle_id)
);
create index exercise_muscles_muscle_idx on public.exercise_muscles (muscle_id);

-- ------------------------------------------------------------
-- workout_plan_templates (globale Vorlagen)
-- ------------------------------------------------------------
create table public.workout_plan_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger workout_plan_templates_set_updated_at before update on public.workout_plan_templates
  for each row execute function public.set_updated_at();

create table public.workout_plan_template_exercises (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.workout_plan_templates (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  sort_order integer not null default 0,
  target_sets integer not null default 3 check (target_sets between 1 and 10),
  rep_min integer not null default 8 check (rep_min between 1 and 100),
  rep_max integer not null default 12 check (rep_max between 1 and 100),
  constraint template_exercises_rep_range check (rep_min <= rep_max)
);
create index template_exercises_template_idx on public.workout_plan_template_exercises (template_id);

-- ------------------------------------------------------------
-- workout_plans (pro Benutzer)
-- ------------------------------------------------------------
create table public.workout_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  template_id uuid references public.workout_plan_templates (id) on delete set null,
  name text not null check (char_length(name) between 1 and 60),
  sort_order integer not null default 0,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index workout_plans_user_idx on public.workout_plans (user_id, sort_order);
create trigger workout_plans_set_updated_at before update on public.workout_plans
  for each row execute function public.set_updated_at();

create table public.workout_plan_exercises (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.workout_plans (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  sort_order integer not null default 0,
  target_sets integer not null default 3 check (target_sets between 1 and 10),
  rep_min integer not null default 8 check (rep_min between 1 and 100),
  rep_max integer not null default 12 check (rep_max between 1 and 100),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint plan_exercises_rep_range check (rep_min <= rep_max)
);
create index plan_exercises_plan_idx on public.workout_plan_exercises (plan_id, sort_order);
create index plan_exercises_exercise_idx on public.workout_plan_exercises (exercise_id);
create trigger workout_plan_exercises_set_updated_at before update on public.workout_plan_exercises
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- workout_sessions
-- ------------------------------------------------------------
create table public.workout_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  plan_id uuid references public.workout_plans (id) on delete set null,
  name text not null,
  status public.session_status not null default 'active',
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  duration_seconds integer,
  total_volume numeric(12, 2) not null default 0,
  total_sets integer not null default 0,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index workout_sessions_user_started_idx on public.workout_sessions (user_id, started_at desc);
create index workout_sessions_user_active_idx on public.workout_sessions (user_id) where status = 'active';
create trigger workout_sessions_set_updated_at before update on public.workout_sessions
  for each row execute function public.set_updated_at();

create table public.workout_session_exercises (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.workout_sessions (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id) on delete restrict,
  sort_order integer not null default 0,
  target_sets integer not null default 3,
  rep_min integer not null default 8,
  rep_max integer not null default 12,
  created_at timestamptz not null default now()
);
create index session_exercises_session_idx on public.workout_session_exercises (session_id, sort_order);
create index session_exercises_user_exercise_idx on public.workout_session_exercises (user_id, exercise_id);

create table public.workout_sets (
  id uuid primary key default gen_random_uuid(),
  session_exercise_id uuid not null references public.workout_session_exercises (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  set_number integer not null check (set_number between 1 and 30),
  weight numeric(7, 2) not null default 0 check (weight >= 0),
  reps integer not null default 0 check (reps between 0 and 500),
  rir integer check (rir between 0 and 10),
  is_warmup boolean not null default false,
  completed boolean not null default true,
  completed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (session_exercise_id, set_number)
);
create index workout_sets_session_exercise_idx on public.workout_sets (session_exercise_id, set_number);
create index workout_sets_user_idx on public.workout_sets (user_id, completed_at desc);
create trigger workout_sets_set_updated_at before update on public.workout_sets
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- calendar_entries
-- ------------------------------------------------------------
create table public.calendar_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  entry_date date not null,
  entry_type public.calendar_entry_type not null,
  note text check (note is null or char_length(note) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, entry_date)
);
create index calendar_entries_user_date_idx on public.calendar_entries (user_id, entry_date);
create trigger calendar_entries_set_updated_at before update on public.calendar_entries
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- favorites
-- ------------------------------------------------------------
create table public.favorites (
  user_id uuid not null references public.profiles (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, exercise_id)
);

-- ------------------------------------------------------------
-- quotes
-- ------------------------------------------------------------
create table public.quotes (
  id uuid primary key default gen_random_uuid(),
  text text not null check (char_length(text) between 5 and 240),
  author text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- body_weight_entries (optional, für spätere Körpergewichts-Grafik)
-- ------------------------------------------------------------
create table public.body_weight_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  entry_date date not null,
  weight numeric(5, 2) not null check (weight > 0 and weight < 500),
  created_at timestamptz not null default now(),
  unique (user_id, entry_date)
);
create index body_weight_user_date_idx on public.body_weight_entries (user_id, entry_date desc);


-- >>>>>>>>>> 0002_functions.sql <<<<<<<<<<

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
  -- Über die App nur durch Admins; direkt in der Datenbank (ohne auth.uid()) erlaubt,
  -- damit der erste Admin per SQL gesetzt werden kann.
  if new.role is distinct from old.role and auth.uid() is not null and not public.is_admin() then
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
    muscle_focus, requirements, grip_alternatives, machine_name, alternative_exercises
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
    coalesce(array(select jsonb_array_elements_text(p -> 'alternative_exercises')), '{}')
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
    alternative_exercises = excluded.alternative_exercises
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


-- >>>>>>>>>> 0003_rls.sql <<<<<<<<<<

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


-- >>>>>>>>>> 0004_seed_static.sql <<<<<<<<<<

-- ============================================================
-- 0004_seed_static.sql
-- Stammdaten: Muskelgruppen, Griffe, Motivationssätze
-- ============================================================

insert into public.muscle_groups (id, name_de, region, sort_order) values
  ('chest', 'Brust', 'front', 10),
  ('upper_chest', 'Obere Brust', 'front', 11),
  ('front_delts', 'Vordere Schulter', 'front', 20),
  ('side_delts', 'Seitliche Schulter', 'both', 21),
  ('rear_delts', 'Hintere Schulter', 'back', 22),
  ('traps', 'Trapez', 'back', 30),
  ('lats', 'Latissimus', 'back', 31),
  ('upper_back', 'Oberer Rücken', 'back', 32),
  ('mid_back', 'Mittlerer Rücken', 'back', 33),
  ('lower_back', 'Unterer Rücken', 'back', 34),
  ('biceps', 'Bizeps', 'front', 40),
  ('triceps', 'Trizeps', 'back', 41),
  ('forearms', 'Unterarme', 'both', 42),
  ('abs', 'Bauch', 'front', 50),
  ('obliques', 'Seitliche Bauchmuskeln', 'front', 51),
  ('quads', 'Quadrizeps', 'front', 60),
  ('hamstrings', 'Hamstrings', 'back', 61),
  ('glutes', 'Gluteus', 'back', 62),
  ('calves', 'Waden', 'back', 63),
  ('adductors', 'Adduktoren', 'front', 64),
  ('abductors', 'Abduktoren', 'both', 65)
on conflict (id) do update set name_de = excluded.name_de, region = excluded.region, sort_order = excluded.sort_order;

insert into public.grips (id, name_de, description, sort_order) values
  ('neutral_parallel', 'Neutraler Parallelgriff', 'Zwei parallele Griffe, Handflächen zeigen zueinander. Schulterfreundlich, gut für Latzug und Rudern.', 10),
  ('wide_lat_bar', 'Breiter Latzuggriff', 'Lange, leicht gebogene Stange für breiten pronierten Griff. Betont Latissimus und oberen Rücken.', 20),
  ('close_v_grip', 'Enger V-Griff', 'Kompakter V-förmiger Doppelgriff, Handflächen zueinander. Für enges Rudern und engen Latzug.', 30),
  ('rope', 'Seil', 'Seil mit zwei Endknäufen. Erlaubt neutrale Handstellung und das Auseinanderziehen am Ende der Bewegung.', 40),
  ('single_handle', 'Einzelgriff', 'Einzelner D-Griff für einarmige Übungen. Erlaubt freie Handstellung und großen Bewegungsradius.', 50),
  ('strap_handle', 'Handschlaufe', 'Weiche Schlaufe mit Karabiner, die um die Hand gelegt wird. Entlastet den Griff und eignet sich für Seitheben, Kickbacks und einarmige Zugübungen.', 55),
  ('straight_bar', 'Gerade Stange', 'Kurze gerade Stange für pronierten oder supinierten Griff. Für Curls, Trizepsdrücken und Pulldowns.', 60),
  ('ez_bar', 'EZ-Stange', 'Gewellte Stange, die eine leicht gedrehte Handstellung erlaubt. Entlastet die Handgelenke bei Curls.', 70),
  ('v_bar_triceps', 'Trizeps-V-Stange', 'V-förmige Stange mit neutralem Griff. Für Trizepsdrücken am oberen Kabel.', 80),
  ('ankle_strap', 'Fußschlaufe', 'Manschette für das Sprunggelenk. Für Kickbacks und Hüftübungen am unteren Kabel.', 90)
on conflict (id) do update set name_de = excluded.name_de, description = excluded.description, sort_order = excluded.sort_order;

-- Kurze, eigene Formulierungen (keine urheberrechtlich geschützten Zitate)
insert into public.quotes (text, author) values
  ('Der schwerste Satz ist der, den du nicht gemacht hast.', null),
  ('Konstanz schlägt Intensität. Jede Woche, jeden Satz.', null),
  ('Heute eine Wiederholung mehr als beim letzten Mal.', null),
  ('Fortschritt zeigt sich nicht täglich, aber er summiert sich.', null),
  ('Technik zuerst. Das Gewicht kommt von allein.', null),
  ('Du musst nicht motiviert sein. Du musst nur anfangen.', null),
  ('Ein mittelmäßiges Training ist besser als kein Training.', null),
  ('Zähle die Sätze, die du machst, nicht die, die du planst.', null),
  ('Disziplin ist die Entscheidung, die du jeden Tag neu triffst.', null),
  ('Langsam aufwärmen, kontrolliert arbeiten, sauber beenden.', null),
  ('Der Plan funktioniert nur, wenn du ihn ausführst.', null),
  ('Stärke ist das Ergebnis von vielen gewöhnlichen Tagen.', null),
  ('Nicht perfekt. Nur regelmäßig.', null),
  ('Jeder Satz ist eine Abstimmung für die Person, die du werden willst.', null),
  ('Kontrolle in der Abwärtsbewegung macht den Unterschied.', null),
  ('Was du heute trackst, kannst du morgen steigern.', null),
  ('Geduld ist Teil des Trainingsplans.', null),
  ('Du bist nicht müde. Du bist am Anfang des Satzes.', null),
  ('Mach den ersten Satz. Der Rest folgt.', null),
  ('Ein Training zu verpassen ist okay. Zwei ist eine Gewohnheit.', null),
  ('Der Körper folgt dem, was du wiederholt tust.', null),
  ('Mehr Gewicht ist nicht das Ziel. Bessere Wiederholungen sind es.', null),
  ('Ruhetage sind Trainingstage für die Erholung.', null),
  ('Du vergleichst dich mit dir selbst vor drei Monaten. Mit niemandem sonst.', null),
  ('Zwischen Vorsatz und Ergebnis liegt nur Arbeit.', null),
  ('Volle Bewegung, volle Kontrolle, voller Fokus.', null),
  ('Die beste Zeit für Training ist die, die du einhältst.', null),
  ('Der Unterschied liegt in der letzten sauberen Wiederholung.', null),
  ('Nicht denken. Aufwärmen.', null),
  ('Kleine Schritte, lange Strecke.', null),
  ('Heute zählt, was du eintragst, nicht was du vorhast.', null),
  ('Stabiler Rumpf, ruhige Atmung, klarer Kopf.', null),
  ('Das Gewicht spürt deine Ausreden nicht.', null),
  ('Trainiere so, dass du nächste Woche wieder trainieren kannst.', null),
  ('Schwere Tage bauen die leichten auf.', null),
  ('Mach es langsam. Mach es richtig. Mach es wieder.', null),
  ('Konzentration auf den Muskel, nicht auf die Zahl.', null),
  ('Jede Wiederholung ist eine Information. Nutze sie.', null),
  ('Du hast heute Zeit für einen Satz. Dann hast du Zeit für das Training.', null),
  ('Struktur schlägt Motivation.', null),
  ('Erst die Form, dann das Tempo, dann das Gewicht.', null),
  ('Nicht alles muss schwer sein. Aber alles muss sauber sein.', null),
  ('Dein letztes Training war der Maßstab. Heute geht es um einen Schritt mehr.', null),
  ('Der Rest Timer läuft. Der nächste Satz wartet.', null),
  ('Progression ist ein Prozess, kein Zufall.', null),
  ('Du bist stärker als bei deinem ersten Eintrag.', null),
  ('Wer trackt, sieht Fortschritt, bevor er ihn spürt.', null),
  ('Mach heute den Satz, über den du dich morgen freust.', null),
  ('Einfach anfangen ist die halbe Arbeit.', null),
  ('Die Routine trägt dich, wenn die Lust fehlt.', null),
  ('Halte das Gewicht, wenn du musst. Erhöhe es, wenn du kannst.', null),
  ('Schulterblätter zurück, Brust raus, Satz beginnen.', null),
  ('Ein guter Trainingstag beginnt mit dem ersten Eintrag.', null),
  ('Der Körper merkt sich jede Wiederholung.', null),
  ('Heute Grundlagen, morgen Ergebnisse.', null),
  ('Sei stolz auf den Satz, den du sauber gemacht hast.', null),
  ('Nichts ersetzt das Training. Auch nicht das beste Programm.', null),
  ('Du trainierst für die Version von dir in einem Jahr.', null),
  ('Pausen gehören dazu. Aufgeben nicht.', null),
  ('Jeder Fortschritt beginnt mit einem gespeicherten Satz.', null)
on conflict do nothing;


-- >>>>>>>>>> 0005_seed_exercises.sql <<<<<<<<<<

-- ============================================================
-- 0005_seed_exercises.sql
-- GENERIERT aus supabase/seed/exercises/*.json via `npm run db:generate` – nicht manuell bearbeiten.
-- 62 Standardübungen
-- ============================================================

-- Schrägbankdrücken Maschine
select public.upsert_seed_exercise($seed${"slug":"schraegbankdruecken-maschine","name":"Schrägbankdrücken Maschine","category":"chest","equipment":"machine","grip_id":null,"grip_notes":"Pronierte Griffe (Handflächen nach vorne) oder neutrale Griffe, je nach Maschine. Handgelenke gerade halten.","primary_muscles":["upper_chest","chest"],"secondary_muscles":["triceps","front_delts"],"description":"Geführtes Drücken in Schrägposition für die obere Brust. Egal welche der Schrägbankmaschinen im Studio frei ist: die Bewegung ist identisch, entscheidend sind Sitzhöhe und Ellenbogenführung.","setup":["Sitz so einstellen, dass die Griffe ungefähr auf Höhe der mittleren bis oberen Brust liegen.","Rücken und Kopf vollständig an das Polster anlehnen.","Füße flach auf den Boden stellen.","Schulterblätter kontrolliert nach hinten und unten ziehen.","Griffe fassen, Handgelenke gerade, Ellenbogen leicht unterhalb der Griffe."],"execution":["Griffe kontrolliert nach vorne-oben drücken.","Ellenbogen am Ende nicht aggressiv durchstrecken.","Spannung in der Brust halten, Schulterblätter bleiben hinten.","Gewicht langsam und kontrolliert zurückführen.","In der Endposition leichte Dehnung der Brust spüren, ohne dass das Gewicht aufsetzt.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Voller Bewegungsradius, soweit die Schultern schmerzfrei bleiben. In der unteren Position die Griffe etwa auf Brusthöhe bringen, oben kurz vor dem Durchstrecken stoppen.","breathing":"Beim Drücken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Schultern rollen beim Drücken nach vorne.","Sitz zu niedrig, Griffe liegen auf Schulterhöhe.","Gewicht wird mit Schwung aus der unteren Position gedrückt.","Ellenbogen werden am Ende hart durchgestreckt.","Rücken löst sich vom Polster."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Erst dann Gewicht erhöhen, wenn alle Sätze im oberen Wiederholungsbereich sauber ausgeführt werden.","Wenn die Schultern unangenehm belastet sind, Sitz etwas höher stellen oder Griffweite ändern."],"cable_setup":null,"muscle_focus":["Der obere Brustanteil arbeitet am meisten, wenn die Ellenbogen leicht unterhalb der Griffe bleiben und die Druckrichtung nach vorne-oben zeigt.","Griffe tief genug zurückführen, bis die obere Brust gedehnt ist; dort liegt der größte Wachstumsreiz.","Brust raus, Schulterblätter zurück. Wenn die Schulter nach vorne kommt, sinkt die Brustbeteiligung sofort.","6 bis 12 Wiederholungen, kontrollierte Exzentrik, Progression über Gewicht erst bei sauberer Technik in allen Sätzen."],"requirements":["Schrägbankdrück-Maschine mit verstellbarem Sitz (Hebel- oder Stapelmaschine)"],"grip_alternatives":[],"image_url":"/exercises/incline-press-plate.jpg","machine_name":"DHZ Incline Chest Press, Plate Loaded","alternative_exercises":["schraegbankdruecken-langhantel","kurzhantel-schraegbankdruecken","brustpresse"],"animation_source_url":"https://modusx.de/fitness-uebungen/brustpresse/brustpresse-fuer-die-obere-brust-aufrecht-sitzend/","variants":[{"name":"Plate-Loaded Hebelmaschine (Standard)","description":"Griffe auf Höhe der oberen Brust, Druckrichtung nach vorne-oben. Scheiben beidseitig gleich auflegen."},{"name":"FLEX-Maschine (konvergierende Griffe)","description":"Die Griffe laufen beim Drücken zusammen. Mehr Kontraktion der oberen Brust am Ende der Bewegung."},{"name":"Liegende Variante (Hebel über Kopf)","description":"Liegend auf der Schrägbank, Hebel kommt von oben. Rücken flach lassen, nicht ins Hohlkreuz drücken."}]}$seed$::jsonb);

-- Brustpresse Maschine
select public.upsert_seed_exercise($seed${"slug":"brustpresse","name":"Brustpresse Maschine","category":"chest","equipment":"machine","grip_id":null,"grip_notes":"Pronierte Griffe (Handflächen nach vorne) oder neutrale Griffe, je nach Maschine. Handgelenke gerade halten, Griffe nicht zu fest umklammern.","primary_muscles":["chest"],"secondary_muscles":["triceps","front_delts"],"description":"Geführtes Drücken für die mittlere Brust. Ob Steckgewicht, Hebel oder vertikale Griffe: die Bewegung ist dieselbe, deshalb ist das hier eine Übung mit Maschinenvarianten. Sitzhöhe und Griffe bestimmen, welcher Teil der Brust den Schwerpunkt bekommt.","setup":["Sitz so einstellen, dass die Griffe etwa auf Höhe der mittleren Brust liegen.","Rücken und Kopf vollständig an das Polster anlehnen.","Füße flach auf den Boden oder auf die Fußstütze stellen.","Schulterblätter nach hinten und unten ziehen, Brust leicht anheben.","Griffe fassen, Handgelenke gerade, Ellenbogen etwa auf Höhe der Griffe oder leicht darunter."],"execution":["Griffe kontrolliert nach vorne drücken, bis die Arme fast gestreckt sind.","Ellenbogen am Ende nicht hart durchstrecken.","Schulterblätter während der gesamten Bewegung hinten am Polster lassen.","Gewicht langsam zurückführen, Ellenbogen wandern nach hinten.","In der Startposition leichte Dehnung der Brust spüren, Gewicht nicht aufsetzen lassen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer leichten Dehnung der Brust mit den Griffen etwa auf Brusthöhe bis kurz vor die vollständige Armstreckung. Bewegungsradius nur so groß wählen, wie die Schultern schmerzfrei bleiben.","breathing":"Beim Drücken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Schultern rollen beim Drücken nach vorne, Schulterblätter lösen sich vom Polster.","Sitz zu hoch oder zu tief, Griffe liegen nicht auf Brusthöhe.","Ellenbogen werden am Ende hart durchgestreckt.","Gewicht wird mit Schwung aus der hinteren Position gedrückt.","Handgelenke knicken nach hinten ab."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Ellenbogen etwa 45 bis 60 Grad vom Körper abspreizen, um die Schultern zu entlasten.","Falls vorhanden, das Fußpedal nutzen, um die Griffe in die Ausgangsposition zu bringen.","Erst Gewicht erhöhen, wenn alle Sätze sauber ausgeführt werden."],"cable_setup":null,"muscle_focus":["Schulterblätter zusammenziehen und während des Drückens hinten lassen, dann drückt die Brust und nicht die vordere Schulter.","Griffe so weit zurückführen, dass die Brust gedehnt wird (Hände etwa auf Brusthöhe), aber ohne dass die Schulter nach vorne rollt.","Oben nicht vollständig strecken, damit die Spannung auf der Brust bleibt.","6 bis 12 Wiederholungen mit 2 bis 3 Sekunden Absenken; Gewicht erst erhöhen, wenn alle Sätze das obere Ende des Bereichs erreichen."],"requirements":["Brustpresse (Sitzmaschine) mit verstellbarem Sitz"],"grip_alternatives":[],"image_url":"/exercises/chest-press.jpg","machine_name":"DHZ Chest Press, Steckgewicht","alternative_exercises":["schraegbankdruecken-maschine","bankdruecken-langhantel","kurzhantel-bankdruecken"],"animation_source_url":"https://modusx.de/fitness-uebungen/brustpresse/brustpresse-mit-fokus-auf-die-mittlere-brust/","variants":[{"name":"Steckgewicht sitzend (Standard)","description":"Griffe auf Höhe der Brustmitte, Rücken am Polster, voller Weg bis knapp vor die Streckung."},{"name":"Hebelmaschine / Iso-Lateral","description":"Jeder Arm bewegt sich einzeln. Gut für Seitenunterschiede und zum Ausgleichen; Gewicht pro Seite auflegen."},{"name":"Vertikale Griffe (neutral)","description":"Handflächen zueinander. Schulterfreundlich, etwas mehr Trizeps, bei Schulterbeschwerden die bessere Wahl."},{"name":"Multipresse","description":"Bankdrücken in der geführten Stange. Fühlt sich wie die Langhantel an, lässt sich aber ohne Spotter bis nahe ans Versagen trainieren."}]}$seed$::jsonb);

-- Butterfly
select public.upsert_seed_exercise($seed${"slug":"butterfly","name":"Butterfly","category":"chest","equipment":"machine","grip_id":null,"grip_notes":"Handgriffe neutral oder leicht proniert fassen, je nach Maschine. Arme fast gestreckt mit leichter Ellenbogenbeuge, Handgelenke gerade.","primary_muscles":["chest"],"secondary_muscles":["front_delts","biceps"],"description":"Isolationsübung für die Brust an der Butterfly-Maschine (auch Pec Deck genannt, es ist dieselbe Maschine). Die Bewegung unter konstanter Spannung belastet die Brust besonders in der gedehnten Position, ideal als zweite Brustübung nach dem Drücken.","setup":["Sitz so einstellen, dass die Griffe etwa auf Höhe der mittleren Brust bis Schulter liegen.","Rücken und Kopf an das Polster anlehnen, Füße flach auf den Boden stellen.","Griffe fassen, Arme fast gestreckt mit leichter Beuge im Ellenbogen.","Schulterblätter nach hinten und unten ziehen, Brust leicht anheben.","Startposition so wählen, dass eine leichte Dehnung der Brust spürbar ist."],"execution":["Griffe in einem weiten Bogen vor der Brust zusammenführen.","Ellenbogenwinkel während der gesamten Bewegung konstant halten.","In der Endposition kurz halten und die Brust anspannen.","Griffe langsam und kontrolliert zurückführen, bis die Hände etwa in der Schulterlinie sind.","Schulterblätter bleiben hinten am Polster.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer leichten Dehnung mit den Händen etwa in der Schulterlinie bis zum Zusammenführen der Griffe vor der Brust. Die Öffnung nicht erzwingen, Bewegungsradius an die Schulterbeweglichkeit anpassen.","breathing":"Beim Zusammenführen ausatmen, beim Öffnen einatmen.","common_mistakes":["Ellenbogen werden während der Bewegung stark gebeugt, die Übung wird zur Druckbewegung.","Griffe werden zu weit nach hinten geöffnet, Schulter wird überdehnt.","Schultern rollen beim Zusammenführen nach vorne.","Gewicht wird mit Schwung aus der Dehnposition geführt.","Rücken löst sich vom Polster, um mehr Gewicht zu bewegen."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Leichtes bis mittleres Gewicht wählen, der Fokus liegt auf Dehnung und Kontraktion.","Bei Beschwerden im Ellenbogen oder Bizeps auf die Pec-Deck-Variante mit Armpolstern wechseln."],"cable_setup":null,"muscle_focus":["Die Brust wächst am stärksten aus der gedehnten Position: Arme weit öffnen, bis eine deutliche Dehnung spürbar ist, ohne dass die Schulter nach vorne kippt.","Ellenbogen leicht gebeugt lassen und während der gesamten Bewegung nicht verändern, sonst übernimmt der Trizeps.","Vorne nur kurz zusammendrücken, das Anspannen bringt wenig; die Zeit unter Spannung in der Dehnung bringt viel.","2 bis 3 Sekunden kontrolliert öffnen, dann zügig schließen. 8 bis 15 Wiederholungen bis 1 bis 2 Wiederholungen vor dem Muskelversagen."],"requirements":["Butterfly-Maschine mit Handgriffen und verstellbarem Sitz"],"grip_alternatives":[],"image_url":"/exercises/pec-deck-rear-delt.jpg","machine_name":"DHZ Pectoral Fly / Rear Delt, Steckgewicht","alternative_exercises":["kabel-flys","kurzhantel-fliegende"],"animation_source_url":"https://modusx.de/fitness-uebungen/butterfly-an-maschine/","variants":[{"name":"Griffe mit gestreckten Armen","description":"Standard: Arme fast gestreckt, Ellenbogen leicht gebeugt und fixiert. Größter Hebel, stärkste Dehnung der Brust."},{"name":"Griffe auf Brusthöhe","description":"Sitz so einstellen, dass die Griffe genau auf Höhe der Brustmitte liegen. Zu hoch belastet die vordere Schulter, zu tief verschiebt die Last nach unten."},{"name":"Teilwiederholungen in der Dehnung","description":"Am Satzende die unteren zwei Drittel der Bewegung wiederholen, wenn die volle Bewegung nicht mehr geht. Die gedehnte Position ist für das Wachstum am wertvollsten."}]}$seed$::jsonb);

-- Kabel-Flys
select public.upsert_seed_exercise($seed${"slug":"kabel-flys","name":"Kabel-Flys","category":"chest","equipment":"cable","grip_id":"single_handle","grip_notes":"Einzelgriffe in beiden Händen, neutraler Griff (Handflächen zeigen zueinander oder leicht nach vorne). Alternativ Handschlaufen, um den Griff zu entlasten, oder ohne Griff direkt am Kabelende.","primary_muscles":["chest"],"secondary_muscles":["front_delts"],"description":"Fliegende am Kabelturm. Die Rollenhöhe bestimmt, welcher Anteil der Brust den Schwerpunkt bekommt: Rollen oben für die untere, auf Brusthöhe für die mittlere, unten für die obere Brust. Eine Übung, drei Einstellungen.","setup":["Beide Rollen des Doppelkabelzugs auf Schulter- bis Brusthöhe einstellen und Einzelgriffe einhängen.","Einen Griff nach dem anderen fassen und einen Schritt nach vorne in die Mitte gehen.","Schrittstellung einnehmen, Rumpf anspannen, Oberkörper leicht nach vorne geneigt.","Arme seitlich mit leichter Ellenbogenbeuge halten, Hände etwa in der Schulterlinie.","Schulterblätter nach hinten und unten ziehen, Brust leicht anheben."],"execution":["Griffe in einem weiten Bogen vor der Brust zusammenführen.","Ellenbogenwinkel während der gesamten Bewegung konstant halten.","In der Endposition die Hände vor der Brust zusammenbringen und die Brust anspannen.","Griffe langsam und kontrolliert zurückführen, bis die Hände wieder etwa in der Schulterlinie sind.","Oberkörper und Rumpf bleiben während der Bewegung stabil.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer leichten Dehnung mit den Händen etwa in der Schulterlinie bis zum Zusammenführen der Hände vor der Brust. Die Dehnposition nicht erzwingen.","breathing":"Beim Zusammenführen ausatmen, beim Öffnen einatmen.","common_mistakes":["Ellenbogen werden stark gebeugt, die Bewegung wird zum Drücken.","Oberkörper schwingt mit und erzeugt Schwung aus dem Rumpf.","Schultern rollen beim Zusammenführen nach vorne.","Hände werden zu weit nach hinten geführt, Schulter wird überdehnt.","Gewicht zieht die Arme in der exzentrischen Phase unkontrolliert zurück."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Leichtes bis mittleres Gewicht wählen, da die Hebelverhältnisse ungünstig sind.","Hände in der Endposition leicht überkreuzen, um die Kontraktion zu verlängern.","Schrittstellung von Satz zu Satz wechseln, um einseitige Belastung zu vermeiden."],"cable_setup":{"cable":"Kabelturm mit zwei Säulen (Doppelkabelzug / Cable Crossover)","height":"Schulterhöhe (bis Brusthöhe), damit das Kabel in Verlängerung der Arme läuft und die Zugrichtung waagerecht durch die mittlere Brust geht","grip_width":"Einzelgriffe, neutraler Griff, Hände starten etwa in der Schulterlinie","body_position":"Stehend in der Mitte zwischen den Säulen, Oberkörper leicht nach vorne geneigt, Rumpf angespannt, Schulterblätter hinten und unten","foot_position":"Schrittstellung, vorderer Fuß flach, hinterer Fuß auf dem Ballen, Knie leicht gebeugt","movement_direction":"Horizontal in einem Bogen von außen nach vorne-innen vor die Brust","elbow_position":"Leicht gebeugt, Winkel bleibt über die gesamte Bewegung konstant","end_position":"Hände vor der Brust zusammengeführt, Brust angespannt, Schultern bleiben hinten","return":"Langsam und kontrolliert, bis die Hände etwa in der Schulterlinie sind und eine leichte Dehnung spürbar ist"},"muscle_focus":["Das Kabel hält die Spannung über den gesamten Weg, besonders in der Dehnung. Arme weit öffnen, Ellenbogen leicht gebeugt und fixiert.","Schritt nach vorne, Oberkörper leicht geneigt, Schulterblätter hinten: so zieht die Brust und nicht die vordere Schulter.","Vorne die Hände nur kurz zusammenführen, die wertvolle Arbeit passiert beim langsamen Öffnen.","10 bis 15 Wiederholungen, 2 bis 3 Sekunden Exzentrik, bis 1 bis 2 Wiederholungen vor dem Versagen."],"requirements":["Kabelturm mit zwei Säulen (Doppelkabelzug) und verstellbaren Rollen","Zwei Einzelgriffe (D-Griffe)"],"grip_alternatives":["strap_handle"],"alternative_exercises":["butterfly","kurzhantel-fliegende"],"image_url":"/exercises/cable-tower.jpg","machine_name":"Kabelturm (Multistation)","animation_source_url":"https://modusx.de/fitness-uebungen/cable-fly/cable-fly-zur-mitte-fuer-die-mittlere-brust/","variants":[{"name":"Rollen auf Brusthöhe","description":"Zug horizontal zur Brustmitte. Standardvariante für die gesamte Brust.","source_url":"https://modusx.de/fitness-uebungen/cable-fly/cable-fly-zur-mitte-fuer-die-mittlere-brust/"},{"name":"Rollen ganz oben","description":"Zug schräg nach unten vor den Bauch. Schwerpunkt untere Brust.","source_url":"https://modusx.de/fitness-uebungen/cable-fly/cable-fly-nach-unten-fuer-die-untere-brust/"},{"name":"Rollen ganz unten","description":"Zug schräg nach oben vor das Gesicht. Schwerpunkt obere Brust.","source_url":"https://modusx.de/fitness-uebungen/cable-fly/cable-fly-nach-oben-fuer-die-obere-brust/"}]}$seed$::jsonb);

-- Schulterdrücken Maschine
select public.upsert_seed_exercise($seed${"slug":"schulterdruecken-maschine","name":"Schulterdrücken Maschine","category":"shoulders","equipment":"machine","grip_id":null,"grip_notes":"Pronierte Griffe (Handflächen nach vorne) oder neutrale Griffe, je nach Maschine. Neutrale Griffe sind meist schulterfreundlicher. Handgelenke gerade halten.","primary_muscles":["front_delts","side_delts"],"secondary_muscles":["triceps","traps"],"description":"Geführtes Überkopfdrücken für die vordere und seitliche Schulter. Hebelmaschine oder Steckgewicht: die Bewegung ist dieselbe. Die neutralen Griffe sind schulterfreundlicher, die pronierten belasten die seitliche Schulter etwas stärker.","setup":["Sitz so einstellen, dass die Griffe in der Startposition etwa auf Schulterhöhe oder leicht darunter liegen.","Rücken und Kopf an das Polster anlehnen, Füße flach auf den Boden stellen.","Griffe fassen, Handgelenke gerade, Unterarme möglichst senkrecht.","Rumpf anspannen, Rippen nicht nach vorne herausdrücken.","Schultern bewusst nach unten ziehen, nicht zu den Ohren hochziehen."],"execution":["Griffe kontrolliert nach oben drücken.","Ellenbogen am Ende nicht hart durchstrecken.","Schultern während des Drückens unten lassen, nicht hochziehen.","Gewicht langsam zurückführen, bis die Griffe etwa auf Schulterhöhe sind.","Rücken bleibt während der gesamten Bewegung am Polster.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von den Griffen etwa auf Schulterhöhe bis kurz vor die vollständige Armstreckung. Unten nur so tief, wie die Schultern schmerzfrei bleiben.","breathing":"Beim Drücken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Schultern werden beim Drücken zu den Ohren hochgezogen.","Rücken wölbt sich stark ins Hohlkreuz, Rippen werden herausgedrückt.","Sitz zu hoch, Griffe liegen deutlich unter der Schulter.","Ellenbogen werden am Ende hart durchgestreckt.","Gewicht wird mit Schwung aus der unteren Position gedrückt."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Bei Beschwerden in der Schulter neutrale Griffe wählen oder Sitz etwas höher stellen.","Erst Gewicht erhöhen, wenn alle Sätze sauber und ohne Hohlkreuz ausgeführt werden."],"cable_setup":null,"muscle_focus":["Griffe bis auf Kinn- bis Schulterhöhe absenken, dort ist die vordere Schulter gedehnt und der Reiz am größten.","Oben nicht komplett strecken und die Schultern nicht hochziehen, sonst übernimmt der Trapez.","Rücken am Polster, Rumpf fest, kein Hohlkreuz: die Kraft kommt aus der Schulter, nicht aus dem Rücken.","6 bis 12 Wiederholungen, kontrolliert absenken, Gewicht nach dem Doppelprogressions-Prinzip steigern."],"requirements":["Schulterdrück-Maschine mit verstellbarem Sitz und Rückenlehne"],"grip_alternatives":[],"image_url":"/exercises/shoulder-press-plate.jpg","machine_name":"DHZ Shoulder Press, Plate Loaded","alternative_exercises":["kurzhantel-schulterdruecken","arnold-press"],"animation_source_url":"https://modusx.de/fitness-uebungen/schulterdruecken-an-maschine/","variants":[{"name":"Plate Loaded mit neutralen Griffen (Standard)","description":"Handflächen zueinander, Ellenbogen leicht vor dem Körper. Schonend für das Schultergelenk."},{"name":"Steckgewicht mit pronierten Griffen","description":"Handflächen nach vorne, Ellenbogen weiter außen. Etwas mehr seitliche Schulter, mehr Belastung für das Gelenk."}]}$seed$::jsonb);

-- Seitheben Maschine
select public.upsert_seed_exercise($seed${"slug":"seitheben-maschine","name":"Seitheben Maschine","category":"shoulders","equipment":"machine","grip_id":null,"grip_notes":"Polster liegen an den Oberarmen knapp oberhalb der Ellenbogen an. Griffe locker fassen oder Hände nur anlegen, nicht mit den Händen heben.","primary_muscles":["side_delts"],"secondary_muscles":["traps"],"description":"Isolation der seitlichen Schulter mit konstanter Spannung. An der Maschine liegen die Oberarme am Polster, am Kabelzug zieht man einarmig von der tiefen Rolle. Beide Varianten belasten die Schulter im Gegensatz zur Kurzhantel auch unten, wo der Muskel gedehnt ist.","setup":["Sitz so einstellen, dass die Drehachse der Maschine etwa auf Höhe der Schultergelenke liegt.","Oberkörper aufrecht an das Polster anlehnen, Füße flach auf den Boden stellen.","Oberarme an die Polster legen, Ellenbogen etwa 90 Grad gebeugt.","Schultern bewusst nach unten ziehen, Brust leicht anheben.","Rumpf anspannen."],"execution":["Oberarme über die Polster seitlich nach oben führen.","Bewegung aus den Ellenbogen führen, nicht aus den Händen.","Bis etwa Schulterhöhe anheben, Schultern bleiben unten.","In der Endposition kurz halten.","Arme langsam und kontrolliert zurückführen.","Gewicht unten nicht aufsetzen lassen, Spannung halten."],"range_of_motion":"Von den Oberarmen neben dem Körper bis etwa Schulterhöhe. Nicht über die Schulterhöhe hinaus heben, da dann vermehrt der Trapezmuskel übernimmt.","breathing":"Beim Anheben ausatmen, beim Absenken einatmen.","common_mistakes":["Schultern werden beim Anheben zu den Ohren hochgezogen.","Oberarme werden über die Schulterhöhe hinaus gehoben.","Sitz zu niedrig oder zu hoch, Drehachse stimmt nicht mit der Schulter überein.","Gewicht fällt in der exzentrischen Phase unkontrolliert zurück.","Oberkörper lehnt sich nach hinten, um das Gewicht zu bewegen."],"tips":["Leichtes bis mittleres Gewicht wählen, der Fokus liegt auf der seitlichen Schulter.","Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","In der Endposition eine Sekunde halten."],"cable_setup":null,"muscle_focus":["Die seitliche Schulter arbeitet, wenn der Oberarm seitlich bis knapp über die Waagerechte geführt wird; höher bringt nichts und lässt den Trapez übernehmen.","Kleine Außendrehung vermeiden: Hand und Ellenbogen auf einer Höhe, Daumen nicht nach oben drehen.","Unten nicht ablegen oder entspannen, die Spannung bleibt über die ganze Serie erhalten.","12 bis 20 Wiederholungen, bis nahe ans Versagen; die seitliche Schulter verträgt und braucht hohes Volumen."],"requirements":["Seitheben-Maschine mit Armpolstern und verstellbarem Sitz"],"grip_alternatives":[],"alternative_exercises":["seitheben-kurzhantel"],"animation_source_url":"https://modusx.de/fitness-uebungen/seitheben-an-seitheben-maschine/","variants":[{"name":"Seitheben-Maschine (Standard)","description":"Polster am Oberarm knapp über dem Ellenbogen, Arme bis Schulterhöhe heben, langsam ab."},{"name":"Kabelzug einarmig, Rolle hüfthoch","description":"Kabel läuft hinter dem Körper, Arm leicht gebeugt, bis Schulterhöhe heben. Gleichmäßige Spannung über den gesamten Weg.","source_url":"https://modusx.de/fitness-uebungen/seitheben-am-kabelzug/seitheben-am-kabelzug-einarmig/"}]}$seed$::jsonb);

-- Reverse Butterfly
select public.upsert_seed_exercise($seed${"slug":"reverse-butterfly","name":"Reverse Butterfly","category":"shoulders","equipment":"machine","grip_id":null,"grip_notes":"Neutrale Griffe (Handflächen zeigen zueinander) oder pronierte Griffe, je nach Maschine. Griffe locker fassen, Handgelenke gerade, die Bewegung kommt aus den Ellenbogen und Schulterblättern.","primary_muscles":["rear_delts"],"secondary_muscles":["upper_back","traps","mid_back"],"description":"Isolation der hinteren Schulter und des oberen Rückens. An der Butterfly-Maschine in Rear-Delt-Stellung oder beidarmig am Kabelzug von vorne: dieselbe Bewegung, horizontale Abduktion mit fast gestreckten Armen.","setup":["Griffe der Maschine in die vordere Position stellen, sodass die Arme vor dem Körper starten.","Sitz so einstellen, dass die Griffe etwa auf Schulterhöhe liegen.","Mit der Brust zum Polster setzen, Brustbein am Polster anlehnen, Füße flach auf den Boden stellen.","Griffe fassen, Arme fast gestreckt mit leichter Ellenbogenbeuge.","Schultern nach unten ziehen, Rumpf anspannen."],"execution":["Griffe in einem weiten Bogen nach hinten-außen führen.","Ellenbogenwinkel während der gesamten Bewegung konstant halten.","Bewegung aus der hinteren Schulter und den Schulterblättern führen, nicht aus den Händen.","In der Endposition kurz halten, Hände etwa in der Schulterlinie oder leicht dahinter.","Griffe langsam und kontrolliert nach vorne zurückführen.","Brust bleibt am Polster, Gewicht vorne nicht aufsetzen lassen."],"range_of_motion":"Von den Armen vor dem Körper bis die Hände etwa in der Schulterlinie oder leicht dahinter sind. Nicht weiter nach hinten erzwingen.","breathing":"Beim Öffnen nach hinten ausatmen, beim Zurückführen einatmen.","common_mistakes":["Schultern werden zu den Ohren hochgezogen.","Ellenbogen werden stark gebeugt, die Übung wird zum Rudern.","Brust löst sich vom Polster, Oberkörper schwingt mit.","Gewicht wird mit Schwung nach hinten gerissen.","Gewicht fällt in der exzentrischen Phase unkontrolliert zurück."],"tips":["Leichtes bis mittleres Gewicht wählen, die hintere Schulter ist ein kleiner Muskel.","Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Vorstellen, die Ellenbogen nach hinten-außen zu ziehen.","Neutraler Griff legt den Fokus stärker auf die hintere Schulter, pronierter Griff mehr auf den oberen Rücken."],"cable_setup":null,"muscle_focus":["Die hintere Schulter arbeitet, wenn die Ellenbogen auf Schulterhöhe nach hinten-außen geführt werden; zu tief übernimmt der Latissimus.","Schulterblätter nicht aktiv zusammenziehen, dann bleibt die Last auf der hinteren Schulter statt auf dem Trapez.","Volle Dehnung vorne zulassen, der Reiz in der gedehnten Position ist für diesen kleinen Muskel entscheidend.","12 bis 20 Wiederholungen mit leichtem bis mittlerem Gewicht, kontrollierte Rückführung."],"requirements":["Reverse-Butterfly-Maschine (umgekehrtes Pec Deck) mit verstellbarem Sitz und Griffen"],"grip_alternatives":[],"image_url":"/exercises/pec-deck-rear-delt.jpg","machine_name":"DHZ Pectoral Fly / Rear Delt, Steckgewicht (Rear-Delt-Stellung)","alternative_exercises":["reverse-fly-kurzhantel","face-pull"],"animation_source_url":"https://modusx.de/fitness-uebungen/butterfly-reverse-am-geraet/","variants":[{"name":"Maschine in Rear-Delt-Stellung (Standard)","description":"Brust ans Polster, Griffe vorne greifen, Arme nach hinten-außen öffnen, bis sie in Verlängerung der Schultern stehen."},{"name":"Kabelzug beidarmig von vorne","description":"Rollen schulterhoch, über Kreuz greifen, Arme nach außen ziehen. Mehr Spannung in der Endposition.","source_url":"https://modusx.de/fitness-uebungen/butterfly-reverse-am-kabelzug/butterfly-reverse-am-kabelturm-von-vorne/"}]}$seed$::jsonb);

-- Face Pull
select public.upsert_seed_exercise($seed${"slug":"face-pull","name":"Face Pull","category":"shoulders","equipment":"cable","grip_id":"rope","grip_notes":"Seilgriff mit neutralem Griff, Daumen zeigen zum Körper. Alternativ Handflächen nach unten (proniert) fassen, dann liegt der Fokus stärker auf dem oberen Rücken. Ohne Seil: zwei Einzelgriffe am selben Karabiner, überkreuz gefasst (rechte Hand am linken Griff).","primary_muscles":["rear_delts"],"secondary_muscles":["upper_back","traps","side_delts"],"description":"Zugübung am Kabelzug mit Seilgriff, bei der das Seil auf Gesichtshöhe zum Kopf gezogen wird. Belastet die hintere Schulter und den oberen Rücken und eignet sich als Ausgleichsübung zu Druckbewegungen.","setup":["Rolle auf Gesichts- bis Stirnhöhe einstellen und Seilgriff einhängen.","Seil mit neutralem Griff fassen, Daumen zeigen zum Körper.","Ein bis zwei Schritte zurückgehen, bis das Kabel unter Spannung ist.","Hüftbreiter Stand oder Schrittstellung, Rumpf anspannen, Oberkörper aufrecht.","Arme gestreckt nach vorne, Schultern bewusst nach unten ziehen."],"execution":["Seil in Richtung Gesicht ziehen, Ellenbogen führen die Bewegung nach hinten-außen.","Seilenden auseinanderziehen, Hände kommen neben die Ohren.","Ellenbogen hoch auf Schulterhöhe und außen halten.","In der Endposition Schulterblätter zusammenziehen und kurz halten.","Seil langsam und kontrolliert zurückführen, Arme strecken.","Schultern am Ende leicht nach vorne kommen lassen, ohne den Oberkörper mitzuziehen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von vollständig gestreckten Armen bis die Hände neben den Ohren und die Ellenbogen etwa in der Schulterlinie sind. Nicht über die Schulterlinie hinaus ziehen.","breathing":"Beim Ziehen ausatmen, beim Zurückführen einatmen.","common_mistakes":["Ellenbogen sinken nach unten, die Übung wird zum Rudern.","Oberkörper lehnt sich nach hinten, Bewegung kommt aus dem Rumpf.","Schultern werden zu den Ohren hochgezogen.","Seil wird nur zum Gesicht gezogen, ohne die Enden auseinanderzuziehen.","Gewicht zieht die Arme unkontrolliert zurück."],"tips":["Leichtes bis mittleres Gewicht wählen und auf hohe Ellenbogen achten.","Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Vorstellen, in der Endposition eine Doppelbizeps-Pose einzunehmen.","Bei Platzmangel auch kniend oder im Halbkniestand ausführbar."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, eine Seite","height":"über Kopfhöhe (etwa Stirnhöhe oder knapp darüber), damit das Seil leicht von oben in Richtung Gesicht gezogen wird und die Ellenbogen auf Schulterhöhe bleiben","grip_width":"Seilgriff, neutraler Griff, Daumen zum Körper, Hände am Ende neben den Ohren","body_position":"Stehend mit ein bis zwei Schritten Abstand zur Säule, aufrecht, Rumpf angespannt, Schultern unten","foot_position":"Hüftbreit oder Schrittstellung, Knie leicht gebeugt","movement_direction":"Horizontal von vorne in Richtung Gesicht, Seilenden werden dabei nach außen gezogen","elbow_position":"Ellenbogen hoch etwa auf Schulterhöhe, zeigen nach außen und wandern nach hinten","end_position":"Hände neben den Ohren, Ellenbogen in der Schulterlinie, Schulterblätter zusammengezogen","return":"Langsam und kontrolliert bis zur vollen Armstreckung, Spannung am Kabel bleibt erhalten"},"muscle_focus":["Rolle über Kopfhöhe, Seil leicht von oben zum Gesicht ziehen und die Ellenbogen hoch auf Schulterhöhe nach außen-hinten führen; sinken die Ellenbogen, wird daraus ein Rudern für den Rücken.","Arme vorne vollständig strecken und die Schultern am Ende leicht nach vorne kommen lassen, damit die hintere Schulter aus der gedehnten Position arbeitet.","Seilenden am Ende auseinanderziehen und die Hände neben die Ohren bringen, Schulterblätter erst in der Endposition zusammenziehen.","Oberkörper aufrecht und ruhig halten, zwei bis drei Sekunden lang zurückführen und ein Gewicht wählen, bei dem die hintere Schulter und nicht der Rumpf limitiert."],"requirements":["Kabelturm mit verstellbarer Rolle","Seilgriff (alternativ zwei Einzelgriffe)"],"grip_alternatives":["single_handle"],"alternative_exercises":[],"image_url":"/exercises/cable-tower.jpg","machine_name":"Kabelturm (Multistation)","animation_source_url":"https://modusx.de/fitness-uebungen/face-pulls/face-pulls-am-kabelzug/","variants":[]}$seed$::jsonb);

-- Dips
select public.upsert_seed_exercise($seed${"slug":"dips","name":"Dips","category":"chest","equipment":"bodyweight","grip_id":null,"grip_notes":"Neutraler Griff an den Holmen, Handgelenke gerade über den Händen. Für mehr Brust den Oberkörper leicht nach vorne neigen, für mehr Trizeps aufrecht bleiben.","primary_muscles":["chest","triceps"],"secondary_muscles":["front_delts"],"description":"Druckübung mit dem eigenen Körpergewicht an den Dip-Holmen. Mit nach vorne geneigtem Oberkörper belastet sie vor allem die untere und mittlere Brust, aufrecht ausgeführt stärker den Trizeps.","setup":["Holme hüft- bis schulterbreit wählen; zu breite Holme belasten die Schulter.","In den Stütz springen oder steigen, Arme gestreckt, Schultern tief und hinten.","Beine leicht anwinkeln oder kreuzen, Blick nach vorne-unten.","Oberkörper etwa 20 bis 30 Grad nach vorne neigen, Brust raus."],"execution":["Ellenbogen beugen und den Körper kontrolliert absenken.","Ellenbogen zeigen leicht nach außen-hinten, nicht nach außen abspreizen.","Bis die Oberarme etwa waagerecht sind oder leichte Dehnung in der Brust spürbar wird.","Kraftvoll nach oben drücken, Brust bleibt raus, Schultern bleiben tief.","Oben nicht komplett durchstrecken, Spannung halten und direkt die nächste Wiederholung beginnen."],"range_of_motion":"Bis die Oberarme waagerecht sind, tiefer nur bei schmerzfreien Schultern. Oben kurz vor der vollen Streckung stoppen.","breathing":"Beim Absenken einatmen, beim Hochdrücken ausatmen.","common_mistakes":["Zu tief absenken, Schultern rollen nach vorne.","Schultern hochziehen statt tief und hinten halten.","Schwung aus den Beinen holen.","Ellenbogen weit nach außen abspreizen."],"tips":["Zusatzgewicht erst, wenn 3 × 10 saubere Wiederholungen gelingen.","Mit Gegengewicht an der Dip-Maschine starten, wenn das Körpergewicht noch zu schwer ist.","Tempo: zwei Sekunden absenken, kontrolliert hochdrücken."],"cable_setup":null,"muscle_focus":["Oberkörper nach vorne neigen und Ellenbogen leicht nach außen führen, dann arbeitet die Brust in der gedehnten Position.","Schultern während der ganzen Bewegung tief halten, sonst übernimmt die vordere Schulter.","Die untere Umkehr kontrolliert und ohne Federn ausführen."],"requirements":["Dip-Station oder Dip-Holme, hüft- bis schulterbreit","Optional Dip-Gürtel für Zusatzgewicht oder Dip-Maschine mit Gegengewicht"],"grip_alternatives":[],"bodyweight_factor":1,"animation_source_url":"https://modusx.de/fitness-uebungen/arnold-dips/klassische-arnold-dips/","variants":[],"alternative_exercises":[]}$seed$::jsonb);

-- Kurzhantel Bankdrücken
select public.upsert_seed_exercise($seed${"slug":"kurzhantel-bankdruecken","name":"Kurzhantel Bankdrücken","category":"chest","equipment":"dumbbell","grip_id":null,"grip_notes":null,"primary_muscles":["chest"],"secondary_muscles":["triceps","front_delts"],"description":"Drücken mit zwei Kurzhanteln auf der Flachbank. Gegenüber der Langhantel erlauben Kurzhanteln einen größeren Bewegungsweg und damit mehr Dehnung der Brust; jede Seite arbeitet für sich.","setup":["Kurzhanteln auf die Oberschenkel nehmen, hinlegen und mit den Knien in die Startposition schwingen.","Füße fest am Boden, Schulterblätter zusammen und nach unten, leichtes Hohlkreuz.","Hanteln über der Brust, Handflächen nach vorne oder leicht gedreht.","Ellenbogen etwa 45 Grad vom Körper abgespreizt."],"execution":["Hanteln kontrolliert absenken, bis sie neben der Brust unterhalb der Bankebene sind.","In der tiefen Position die Dehnung der Brust spüren, kurz halten.","Hanteln nach oben und leicht zueinander drücken, ohne sie aneinanderzuschlagen.","Oben nicht komplett strecken, Spannung halten.","Nächste Wiederholung ohne Federn starten."],"range_of_motion":"Tiefer als bei der Langhantel: die Hanteln dürfen unter die Bankebene, solange die Schulter stabil bleibt.","breathing":"Beim Absenken (Dehnung) einatmen, beim Drücken oder Ziehen ausatmen.","common_mistakes":["Hanteln oben zusammenschlagen und Spannung verlieren.","Ellenbogen auf Schulterhöhe abspreizen.","Zu schwere Hanteln und dadurch halber Weg.","Schulterblätter lösen und Schultern nach vorne rollen."],"tips":["Hanteln mit den Knien hochschwingen statt aus der Rückenlage heben.","Am Satzende die Hanteln kontrolliert auf die Oberschenkel legen und aufsetzen.","Gewicht erst erhöhen, wenn alle Sätze den oberen Wiederholungsbereich erreichen."],"cable_setup":null,"muscle_focus":["Die Brust wächst aus der gedehnten Position: tief absenken, unterhalb der Bankebene, ohne die Schulter nach vorne kippen zu lassen.","Schulterblätter die ganze Zeit hinten lassen, dann drückt die Brust und nicht die vordere Schulter.","2 bis 3 Sekunden absenken, zügig drücken, 6 bis 12 Wiederholungen bis 1 bis 2 Wiederholungen vor dem Versagen."],"requirements":["Flachbank","Zwei Kurzhanteln"],"grip_alternatives":[],"variants":[{"name":"Neutraler Griff","description":"Handflächen zueinander. Schulterschonend, etwas mehr Trizeps."},{"name":"Leicht negative Bank","description":"Bank 10 bis 15 Grad abfallend, Schwerpunkt untere Brust.","source_url":"https://modusx.de/fitness-uebungen/negativ-kurzhantel-bankdruecken/"}],"animation_source_url":"https://modusx.de/fitness-uebungen/kurzhantel-flachbankdruecken/","alternative_exercises":[]}$seed$::jsonb);

-- Kurzhantel Schrägbankdrücken
select public.upsert_seed_exercise($seed${"slug":"kurzhantel-schraegbankdruecken","name":"Kurzhantel Schrägbankdrücken","category":"chest","equipment":"dumbbell","grip_id":null,"grip_notes":null,"primary_muscles":["upper_chest","chest"],"secondary_muscles":["front_delts","triceps"],"description":"Drücken mit Kurzhanteln auf der Schrägbank für die obere Brust. Der freie Bewegungsweg erlaubt eine tiefere Dehnung als jede Maschine.","setup":["Bank auf 30 Grad stellen; steiler wird es zunehmend eine Schulterübung.","Hanteln auf den Knien aufnehmen, zurücklehnen, Hanteln in die Startposition bringen.","Schulterblätter zusammen und tief, Brust raus.","Hanteln über der oberen Brust, Ellenbogen etwa 45 Grad abgespreizt."],"execution":["Hanteln kontrolliert zur oberen Brust absenken, bis die Brust deutlich dehnt.","Kurz halten, dann nach oben-innen drücken.","Oben nicht aneinanderschlagen, Arme nicht komplett strecken.","Ellenbogen unter den Hanteln halten.","Ohne Schwung in die nächste Wiederholung."],"range_of_motion":"Hanteln bis auf Höhe der oberen Brust oder knapp darunter, oben kurz vor der Streckung.","breathing":"Beim Absenken (Dehnung) einatmen, beim Drücken oder Ziehen ausatmen.","common_mistakes":["Bank zu steil, dann übernimmt die Schulter.","Hohlkreuz übertreiben, um die Bank flacher zu machen.","Hanteln oben zusammenschlagen.","Zu wenig Tiefe aus Angst vor dem Gewicht."],"tips":["Mit 30 Grad starten; 15 bis 30 Grad sind für die obere Brust ideal.","Die obere Brust reagiert gut auf 8 bis 12 Wiederholungen mit voller Dehnung.","Spotter oder Hanteln auf die Knie ablegen, nie fallen lassen."],"cable_setup":null,"muscle_focus":["Obere Brust: Druckrichtung nach oben-innen, Ellenbogen leicht unter den Händen.","Tiefe Dehnung in der unteren Position ist der Hauptreiz, dort 1 Sekunde halten.","Schultern tief und hinten, sonst wandert die Last auf die vordere Schulter."],"requirements":["Schrägbank, verstellbar","Zwei Kurzhanteln"],"grip_alternatives":[],"variants":[{"name":"30 Grad (Standard)","description":"Bester Kompromiss aus oberer Brust und Schulterschonung."},{"name":"Neutraler Griff","description":"Handflächen zueinander, mehr Bewegungsfreiheit für die Schulter."}],"animation_source_url":"https://modusx.de/fitness-uebungen/kurzhantel-schraegbankdruecken/","alternative_exercises":[]}$seed$::jsonb);

-- Kurzhantel Fliegende
select public.upsert_seed_exercise($seed${"slug":"kurzhantel-fliegende","name":"Kurzhantel Fliegende","category":"chest","equipment":"dumbbell","grip_id":null,"grip_notes":null,"primary_muscles":["chest"],"secondary_muscles":["front_delts"],"description":"Fliegende mit Kurzhanteln auf der Flach- oder Schrägbank. Isoliert die Brust in der gedehnten Position; die Spannung oben ist gering, deshalb mit Kabel-Flys oder Butterfly kombinieren.","setup":["Auf der Bank liegen, Hanteln über der Brust, Handflächen zueinander.","Ellenbogen leicht gebeugt und in diesem Winkel fixieren.","Schulterblätter zusammen, Füße fest am Boden."],"execution":["Arme in einem weiten Bogen seitlich öffnen, Ellenbogen bleiben leicht gebeugt.","Absenken, bis die Hanteln auf Höhe der Brust oder leicht darunter sind und die Brust deutlich dehnt.","Kurz halten, dann im gleichen Bogen zurück über die Brust führen.","Oben nicht zusammenschlagen, Spannung halten.","Langsam und ohne Schwung."],"range_of_motion":"Bis die Brust deutlich gedehnt ist, nicht tiefer als die Schulter schmerzfrei zulässt.","breathing":"Beim Absenken (Dehnung) einatmen, beim Drücken oder Ziehen ausatmen.","common_mistakes":["Ellenbogen während der Bewegung beugen und daraus ein Drücken machen.","Zu schwere Hanteln, dadurch kein Bogen.","Hanteln oben zusammenschlagen.","Schultern nach vorne kippen lassen."],"tips":["Leichter wählen als beim Drücken; 10 bis 15 Wiederholungen.","Auf der Schrägbank trifft die Variante die obere Brust.","Als zweite oder dritte Brustübung einplanen."],"cable_setup":null,"muscle_focus":["Die gesamte Wirkung liegt in der Dehnung: dort langsam ankommen und eine Sekunde halten.","Fester Ellenbogenwinkel, sonst wird es ein Drücken mit Trizepsbeteiligung.","Oben bringt das Zusammenführen wenig, deshalb den Weg oben kurz halten und den Fokus nach unten legen."],"requirements":["Flach- oder Schrägbank","Zwei leichte bis mittlere Kurzhanteln"],"grip_alternatives":[],"variants":[{"name":"Flachbank (Standard)","description":"Gesamte Brust.","source_url":"https://modusx.de/fitness-uebungen/kurzhantel-fliegende/kurzhantel-fliegende-fuer-die-mittlere-brust/"},{"name":"Schrägbank","description":"Schwerpunkt obere Brust.","source_url":"https://modusx.de/fitness-uebungen/kurzhantel-fliegende/positive-kurzhantel-fliegende-fuer-die-obere-brust/"}],"animation_source_url":"https://modusx.de/fitness-uebungen/kurzhantel-fliegende/","alternative_exercises":[]}$seed$::jsonb);

-- Kurzhantel Pullover
select public.upsert_seed_exercise($seed${"slug":"kurzhantel-pullover","name":"Kurzhantel Pullover","category":"chest","equipment":"dumbbell","grip_id":null,"grip_notes":null,"primary_muscles":["chest","lats"],"secondary_muscles":["triceps"],"description":"Überzüge mit einer Kurzhantel quer auf der Bank. Belastet Brust und Latissimus in maximaler Dehnung über Kopf; eine der wenigen Übungen, die beide großen Oberkörpermuskeln in gestreckter Position trifft.","setup":["Mit dem oberen Rücken quer auf die Bank legen, Füße fest am Boden, Hüfte leicht tiefer als die Schultern.","Eine Kurzhantel mit beiden Händen unter der inneren Scheibe fassen, Arme fast gestreckt über der Brust.","Ellenbogen leicht gebeugt fixieren."],"execution":["Hantel in einem Bogen hinter den Kopf absenken, Arme bleiben leicht gebeugt.","So tief, bis Brust und Latissimus deutlich dehnen.","Kurz halten, dann im Bogen zurück über die Brust ziehen.","Hüfte ruhig halten, nicht absinken lassen, um Schwung zu holen.","Über der Brust nicht weiter als senkrecht, dort ist die Spannung weg."],"range_of_motion":"Hantel bis hinter den Kopf auf Höhe der Bank oder leicht darunter, zurück bis senkrecht über die Brust.","breathing":"Beim Absenken tief einatmen und den Brustkorb weiten, beim Hochziehen ausatmen.","common_mistakes":["Ellenbogen stark beugen und die Übung zur Trizeps-Extension machen.","Hüfte beim Absenken mit nach unten gehen lassen.","Zu schwere Hantel und dadurch kein kontrollierter Bogen.","Über der Brust weiterziehen, obwohl keine Spannung mehr da ist."],"tips":["Leicht bis mittel starten, 10 bis 15 Wiederholungen.","Längs auf der Bank liegend ist der Weg kürzer, aber stabiler.","Gut am Ende des Brust- oder Rückentrainings."],"cable_setup":null,"muscle_focus":["Die Dehnung hinter dem Kopf ist der Reiz; dort langsam ankommen und eine Sekunde halten.","Fester Ellenbogenwinkel hält die Last auf Brust und Latissimus statt auf dem Trizeps.","Wer die Brust betonen will, hält die Ellenbogen enger; für mehr Latissimus die Ellenbogen leicht weiter."],"requirements":["Flachbank","Eine Kurzhantel"],"grip_alternatives":[],"variants":[{"name":"Quer auf der Bank (Standard)","description":"Größter Bewegungsweg und Dehnung."},{"name":"Längs auf der Bank","description":"Stabiler, etwas weniger Weg, gut für Einsteiger."}],"animation_source_url":"https://modusx.de/fitness-uebungen/kurzhantel-ueberzuege/","alternative_exercises":[]}$seed$::jsonb);

-- Kurzhantel Schulterdrücken
select public.upsert_seed_exercise($seed${"slug":"kurzhantel-schulterdruecken","name":"Kurzhantel Schulterdrücken","category":"shoulders","equipment":"dumbbell","grip_id":null,"grip_notes":null,"primary_muscles":["front_delts","side_delts"],"secondary_muscles":["triceps","traps"],"description":"Überkopfdrücken mit Kurzhanteln, sitzend mit Rückenlehne. Freier Bewegungsweg, jede Seite arbeitet für sich; die wichtigste freie Übung für die vordere und seitliche Schulter.","setup":["Bank fast senkrecht (80 Grad) einstellen.","Hanteln auf die Knie nehmen und einzeln in die Startposition auf Schulterhöhe bringen.","Handflächen nach vorne oder leicht nach innen, Ellenbogen leicht vor dem Körper.","Rumpf fest, unterer Rücken leicht an der Lehne."],"execution":["Hanteln nach oben drücken, bis die Arme fast gestreckt sind.","Hanteln oben leicht zueinander führen, ohne sie zu berühren.","Kontrolliert bis auf Kinn- bis Schulterhöhe absenken.","Ellenbogen nicht hinter den Körper wandern lassen.","Ohne Schwung die nächste Wiederholung starten."],"range_of_motion":"Von Schulterhöhe bis kurz vor die Streckung; so tief, wie die Schulter ohne Ausweichen zulässt.","breathing":"Beim Absenken (Dehnung) einatmen, beim Drücken oder Ziehen ausatmen.","common_mistakes":["Hohlkreuz, um mehr zu drücken.","Oben die Schultern hochziehen.","Zu kurzer Weg nach unten.","Hanteln oben aneinanderschlagen."],"tips":["Mit 80 Grad Lehne starten; frei stehend braucht deutlich mehr Rumpfkontrolle.","6 bis 12 Wiederholungen, Gewicht per Doppelprogression steigern.","Hanteln nach dem Satz nach vorne auf die Knie ablegen."],"cable_setup":null,"muscle_focus":["Die vordere Schulter arbeitet in Dehnung, wenn die Hanteln bis auf Schulterhöhe oder leicht darunter kommen.","Ellenbogen leicht vor dem Körper (Scapula-Ebene) ist schulterfreundlicher als weit außen.","Nacken lang, Schultern tief, dann übernimmt nicht der Trapez."],"requirements":["Bank mit verstellbarer Lehne","Zwei Kurzhanteln"],"grip_alternatives":[],"variants":[{"name":"Sitzend mit Lehne (Standard)","description":"Stabil, höchste Last.","source_url":"https://modusx.de/fitness-uebungen/schulterdruecken-mit-kurzhanteln/schulterdruecken-mit-kurzhanteln-sitzend/"},{"name":"Stehend","description":"Mehr Rumpfarbeit, weniger Gewicht.","source_url":"https://modusx.de/fitness-uebungen/schulterdruecken-mit-kurzhanteln/schulterdruecken-mit-kurzhanteln-stehend/"}],"animation_source_url":"https://modusx.de/fitness-uebungen/schulterdruecken-mit-kurzhanteln/","alternative_exercises":[]}$seed$::jsonb);

-- Arnold Press
select public.upsert_seed_exercise($seed${"slug":"arnold-press","name":"Arnold Press","category":"shoulders","equipment":"dumbbell","grip_id":null,"grip_notes":null,"primary_muscles":["front_delts","side_delts"],"secondary_muscles":["triceps"],"description":"Schulterdrücken mit Drehung: Start mit den Handflächen zum Gesicht, beim Drücken nach außen drehen. Längerer Bewegungsweg und mehr Zeit unter Spannung für die vordere und seitliche Schulter.","setup":["Sitzend an der Lehne, Hanteln vor dem Gesicht auf Kinnhöhe, Handflächen zum Körper.","Ellenbogen vor dem Körper, Rumpf fest.","Schultern tief."],"execution":["Hanteln nach oben drücken und dabei die Handflächen nach vorne drehen.","Oben Arme fast gestreckt, Handflächen nach vorne.","Auf dem Rückweg wieder eindrehen, bis die Handflächen vor dem Gesicht zum Körper zeigen.","Kontrolliert und flüssig, keine Pause im Umkehrpunkt oben.","Ellenbogen nicht hinter den Körper."],"range_of_motion":"Von Kinnhöhe vor dem Gesicht bis kurz vor die Streckung.","breathing":"Beim Absenken (Dehnung) einatmen, beim Drücken oder Ziehen ausatmen.","common_mistakes":["Schwung aus dem Rücken.","Oben komplett strecken und Spannung verlieren.","Zu schwer und dadurch die Drehung weglassen.","Hohlkreuz."],"tips":["Deutlich leichter als beim normalen Schulterdrücken.","10 bis 15 Wiederholungen, Fokus auf Kontrolle.","Gute Alternative, wenn klassisches Drücken in der Schulter zwickt."],"cable_setup":null,"muscle_focus":["Die Eindrehung unten bringt die vordere Schulter in eine tiefe Dehnung, dort liegt der zusätzliche Reiz.","Die Drehung gleichmäßig über den ganzen Weg verteilen, nicht erst oben.","Tempo 2 Sekunden hoch, 2 bis 3 Sekunden runter."],"requirements":["Bank mit Lehne","Zwei Kurzhanteln"],"grip_alternatives":[],"variants":[{"name":"Sitzend (Standard)","description":"Stabile Ausführung.","source_url":"https://modusx.de/fitness-uebungen/arnold-press/arnold-press-sitzend-mit-kurzhanteln/"}],"animation_source_url":"https://modusx.de/fitness-uebungen/arnold-press/","alternative_exercises":[]}$seed$::jsonb);

-- Seitheben Kurzhantel
select public.upsert_seed_exercise($seed${"slug":"seitheben-kurzhantel","name":"Seitheben Kurzhantel","category":"shoulders","equipment":"dumbbell","grip_id":null,"grip_notes":null,"primary_muscles":["side_delts"],"secondary_muscles":["traps"],"description":"Klassisches Seitheben mit Kurzhanteln für die seitliche Schulter, die Übung für breite Schultern. Die Spannung ist oben am größten, deshalb gut mit Seitheben am Kabel oder an der Maschine kombinieren.","setup":["Stehend, Füße hüftbreit, Knie leicht gebeugt, Oberkörper minimal nach vorne geneigt.","Hanteln seitlich neben den Oberschenkeln, Ellenbogen leicht gebeugt.","Schultern tief, Nacken lang."],"execution":["Arme seitlich anheben, Ellenbogen führen die Bewegung.","Bis die Oberarme waagerecht sind, Hände auf Ellenbogenhöhe.","Oben kurz halten.","Langsam absenken, unten nicht ablegen.","Kein Schwung aus den Beinen."],"range_of_motion":"Bis zur Waagerechten des Oberarms, nicht höher.","breathing":"Beim Heben ausatmen, beim Senken einatmen.","common_mistakes":["Schultern hochziehen und den Trapez arbeiten lassen.","Schwung aus Knien und Rücken.","Zu schwer, dadurch kurzer Weg.","Daumen nach oben drehen und die vordere Schulter übernehmen lassen."],"tips":["Leicht bis mittel, 12 bis 20 Wiederholungen bis nahe ans Versagen.","Sitzend ausgeführt ist Schwung unmöglich.","Die seitliche Schulter verträgt hohes Volumen, 2 bis 3 Mal pro Woche."],"cable_setup":null,"muscle_focus":["Ellenbogen leicht gebeugt lassen und den Oberarm bewegen, nicht die Hand.","Leichte Vorneigung des Oberkörpers bringt die Bewegung in die Ebene des Schulterblatts, das ist gelenkschonender und trifft die seitliche Schulter besser.","Kontrolliert absenken, die Exzentrik zählt."],"requirements":["Zwei leichte Kurzhanteln"],"grip_alternatives":[],"variants":[{"name":"Stehend (Standard)","description":"Beidarmig, leichte Vorneigung.","source_url":"https://modusx.de/fitness-uebungen/kurzhantel-seitheben/kurzhantel-seitheben-im-stehen/"},{"name":"Sitzend","description":"Kein Schwung möglich, strenger.","source_url":"https://modusx.de/fitness-uebungen/kurzhantel-seitheben/kurzhantel-seitheben-im-sitzen/"}],"animation_source_url":"https://modusx.de/fitness-uebungen/kurzhantel-seitheben/","alternative_exercises":[]}$seed$::jsonb);

-- Latzug neutral
select public.upsert_seed_exercise($seed${"slug":"neutraler-latzug","name":"Latzug neutral","category":"back","equipment":"cable","grip_id":"neutral_parallel","grip_notes":"Neutraler Parallelgriff (Handflächen zeigen zueinander), etwa schulterbreit. Alternativ: breiter Latzuggriff für mehr Betonung der äußeren Lat-Anteile.","primary_muscles":["lats"],"secondary_muscles":["biceps","upper_back","forearms","rear_delts"],"description":"Vertikaler Zug mit neutralem, schulterbreitem Griff. Am Kabelturm oder an der Hebelmaschine ist die Bewegung dieselbe: Ellenbogen nach unten zum Körper ziehen, Latissimus über den vollen Weg dehnen und verkürzen.","setup":["Oberschenkelpolster so einstellen, dass die Beine fest fixiert sind.","Neutralen Parallelgriff am oberen Kabel einhängen.","Griff fassen, hinsetzen und Oberschenkel unter das Polster bringen.","Oberkörper aufrecht, leicht nach hinten geneigt, Brust leicht angehoben.","Arme gestreckt, Schultern bewusst nach unten ziehen, bevor die Bewegung beginnt."],"execution":["Griff in Richtung obere Brust ziehen, Ellenbogen führen die Bewegung nach unten.","Schulterblätter nach unten und zusammen ziehen.","In der Endposition kurz halten, Griff befindet sich etwa auf Höhe des Kinns bis der oberen Brust.","Gewicht langsam zurückführen, Arme kontrolliert strecken.","Schultern am oberen Ende leicht nach oben kommen lassen, um den Lat zu dehnen.","Ohne Schwung die nächste Wiederholung beginnen."],"range_of_motion":"Von vollständig gestreckten Armen bis der Griff etwa auf Höhe des Kinns bzw. der oberen Brust ist. Nicht bis zum Bauch ziehen.","breathing":"Beim Ziehen ausatmen, beim Strecken der Arme einatmen.","common_mistakes":["Oberkörper wird stark nach hinten gelehnt und die Bewegung mit Schwung ausgeführt.","Schultern bleiben während des Zugs oben am Ohr.","Griff wird mit den Armen statt mit den Ellenbogen geführt.","Gewicht fällt nach oben zurück, keine Kontrolle in der exzentrischen Phase.","Ellenbogen weichen weit nach hinten aus, sodass der Rücken rund wird."],"tips":["Daumen auf die Griffe legen statt zu umschließen, um weniger mit den Unterarmen zu arbeiten.","Vorstellen, die Ellenbogen in die Hosentaschen zu ziehen.","Die exzentrische Phase bewusst zwei bis drei Sekunden lang ausführen."],"cable_setup":{"cable":"Latzug-Station am Kabelturm (feste Rolle oben)","height":"","grip_width":"Schulterbreit, neutral (Handflächen zueinander)","body_position":"Aufrecht sitzend, leichte Rücklage von etwa 10 bis 20 Grad, Brust angehoben, Rumpf stabil","foot_position":"Füße flach auf dem Boden, Oberschenkel unter dem Polster fixiert","movement_direction":"Vertikal von oben nach unten in Richtung obere Brust","elbow_position":"Ellenbogen zeigen nach unten und leicht nach vorne, bleiben nah am Körper","end_position":"Griff auf Höhe des Kinns bis der oberen Brust, Schulterblätter nach unten und zusammengezogen","return":"Langsam und kontrolliert bis zur vollen Armstreckung, Schultern am Ende leicht nach oben kommen lassen","seat_position":"Oberschenkelpolster so einstellen, dass die Beine fest fixiert sind und die Füße flach auf dem Boden stehen. Sitz so wählen, dass die Arme oben vollständig gestreckt sind, ohne dass das Gewicht aufsetzt."},"muscle_focus":["Oben die Arme vollständig strecken und die Schultern mit nach oben gehen lassen: die Dehnung des Latissimus ist der stärkste Wachstumsreiz.","Ellenbogen nach unten zu den Hüften ziehen, nicht die Hände zur Brust; die Hände sind nur Haken.","Oberkörper nur leicht zurücklehnen und die Neigung konstant halten, kein Schwung aus dem Rumpf.","8 bis 12 Wiederholungen, 2 bis 3 Sekunden nach oben kontrollieren."],"requirements":["Latzug-Station am Kabelturm oder integrierter Latzug mit Oberschenkelpolster","Neutraler Parallelgriff (MAG-Griff)"],"grip_alternatives":["close_v_grip"],"alternative_exercises":["breiter-latzug","straight-arm-pulldown"],"image_url":"/exercises/cable-tower.jpg","machine_name":"Kabelturm (Multistation)","animation_source_url":"https://modusx.de/fitness-uebungen/latziehen-zur-brust/latziehen-enger-griff/","variants":[{"name":"Kabelturm mit Parallelgriff (Standard)","description":"Neutraler Griff schulterbreit, leicht zurückgelehnt, Stange zur oberen Brust ziehen.","source_url":"https://modusx.de/fitness-uebungen/latziehen-zur-brust/latziehen-enger-griff/"},{"name":"Hebelmaschine (Plate Loaded)","description":"Brust ans Polster, Griffe von oben nach unten ziehen. Gleiche Bewegung mit fester Führung, gut für schwere Sätze.","source_url":"https://modusx.de/fitness-uebungen/latziehen-zur-brust/klassische-latziehen-zur-brust/"}]}$seed$::jsonb);

-- Latzug breit
select public.upsert_seed_exercise($seed${"slug":"breiter-latzug","name":"Latzug breit","category":"back","equipment":"cable","grip_id":"wide_lat_bar","grip_notes":"Breite Latzugstange, pronierter Griff (Handflächen nach vorne), Hände deutlich weiter als schulterbreit an den gebogenen Enden der Stange. Alternativ: etwas enger greifen, wenn die Schultern in der gestreckten Position unangenehm belastet sind.","primary_muscles":["lats"],"secondary_muscles":["upper_back","biceps","forearms","rear_delts"],"description":"Vertikaler Zug mit breitem Obergriff. Der echte Unterschied zum neutralen Latzug ist die Armführung: die Ellenbogen gehen seitlich nach unten, wodurch der obere Latissimus und der Teres major stärker arbeiten und der Bizeps weniger hilft.","setup":["Breite Latzugstange am oberen Kabel einhängen.","Oberschenkelpolster so einstellen, dass die Beine fest fixiert sind.","Stange deutlich weiter als schulterbreit mit proniertem Griff fassen, hinsetzen und Oberschenkel unter das Polster bringen.","Oberkörper aufrecht mit leichter Rücklage, Brust angehoben, Blick nach vorne.","Arme gestreckt, Schultern bewusst nach unten ziehen, bevor die Bewegung beginnt."],"execution":["Stange in Richtung obere Brust ziehen, Ellenbogen führen die Bewegung nach unten und leicht nach außen.","Schulterblätter nach unten und zusammen ziehen, Brust bleibt angehoben.","In der Endposition kurz halten, Stange befindet sich etwa auf Höhe der oberen Brust.","Gewicht langsam zurückführen, Arme kontrolliert strecken.","Am oberen Ende die Schultern leicht nach oben kommen lassen, um den Lat zu dehnen.","Ohne Schwung die nächste Wiederholung beginnen."],"range_of_motion":"Von vollständig gestreckten Armen bis die Stange etwa auf Höhe der oberen Brust ist. Nicht bis zum Bauch ziehen und nicht hinter den Nacken.","breathing":"Beim Ziehen ausatmen, beim Strecken der Arme einatmen.","common_mistakes":["Oberkörper wird stark nach hinten gelehnt und die Stange mit Schwung gezogen.","Stange wird hinter den Nacken gezogen.","Schultern bleiben während des Zugs oben am Ohr.","Bewegung kommt vor allem aus den Armen statt aus den Ellenbogen und Schulterblättern.","Gewicht fällt nach oben zurück, keine Kontrolle in der exzentrischen Phase."],"tips":["Die Ellenbogen bewusst nach unten in Richtung Hüfte führen, nicht nach hinten.","Die exzentrische Phase zwei bis drei Sekunden lang kontrollieren.","Wenn die Schultern bei sehr breitem Griff unangenehm belastet sind, etwas enger greifen oder auf den neutralen Latzug wechseln."],"cable_setup":{"cable":"Latzug-Station am Kabelturm (feste Rolle oben)","height":"","grip_width":"Deutlich weiter als schulterbreit, proniert (Handflächen nach vorne)","body_position":"Aufrecht sitzend, leichte Rücklage von etwa 10 bis 20 Grad, Brust angehoben, Rumpf stabil","foot_position":"Füße flach auf dem Boden, Oberschenkel unter dem Polster fixiert","movement_direction":"Vertikal von oben nach unten in Richtung obere Brust","elbow_position":"Ellenbogen zeigen nach unten und leicht nach außen, bleiben etwa in der Ebene des Oberkörpers","end_position":"Stange auf Höhe der oberen Brust, Schulterblätter nach unten und zusammengezogen","return":"Langsam und kontrolliert bis zur vollen Armstreckung, Schultern am Ende leicht nach oben kommen lassen","seat_position":"Oberschenkelpolster so einstellen, dass die Beine fest fixiert sind und die Füße flach auf dem Boden stehen. Sitz so wählen, dass die Arme oben vollständig gestreckt sind, ohne dass das Gewicht aufsetzt."},"muscle_focus":["Oben vollständig hängen lassen und strecken, dort wird der Latissimus gedehnt.","Ellenbogen seitlich nach unten ziehen, als wollte man sie in die Hosentaschen stecken.","Nicht hinter den Nacken ziehen, das belastet die Schulter ohne Vorteil für den Rücken.","8 bis 12 Wiederholungen, keine Schwungbewegung aus dem Oberkörper."],"requirements":["Latzug-Station am Kabelturm oder integrierter Latzug mit Oberschenkelpolster","Breite Latzugstange"],"grip_alternatives":["neutral_parallel"],"alternative_exercises":["neutraler-latzug"],"image_url":"/exercises/cable-tower.jpg","machine_name":"Kabelturm (Multistation)","animation_source_url":"https://modusx.de/fitness-uebungen/latziehen-zur-brust/latzug-breit-zur-brust/","variants":[{"name":"Breiter Obergriff zur Brust (Standard)","description":"Griff etwa anderthalbfache Schulterbreite, Stange zur oberen Brust, Ellenbogen seitlich nach unten.","source_url":"https://modusx.de/fitness-uebungen/latziehen-zur-brust/latzug-breit-zur-brust/"},{"name":"Untergriff schulterbreit","description":"Handflächen zum Körper. Mehr Bizeps, Latissimus bleibt Hauptmuskel; gute Abwechslung.","source_url":"https://modusx.de/fitness-uebungen/latziehen-zur-brust/latzug-untergriff/"}]}$seed$::jsonb);

-- Rudern eng
select public.upsert_seed_exercise($seed${"slug":"enges-rudern","name":"Rudern eng","category":"back","equipment":"cable","grip_id":"close_v_grip","grip_notes":"Enger V-Griff, neutral (Handflächen zeigen zueinander). Alternativ: neutraler Parallelgriff in Schulterbreite, wenn der enge Griff die Handgelenke unangenehm belastet.","primary_muscles":["lats","mid_back"],"secondary_muscles":["biceps","forearms","rear_delts"],"description":"Horizontaler Zug mit engem, neutralem Griff. Ob am Kabelzug sitzend, an der Hebelmaschine oder einarmig: die Ellenbogen ziehen eng am Körper nach hinten, Schwerpunkt mittlerer Rücken und unterer Latissimus.","setup":["V-Griff am unteren Kabel der Ruderstation einhängen.","Hinsetzen, Füße auf die Fußplatten stellen, Knie leicht gebeugt.","Griff mit beiden Händen fassen und den Oberkörper aufrichten.","Brust angehoben, Rücken gerade, Schultern nach unten ziehen.","Arme gestreckt, Gewicht leicht abheben, sodass von Beginn an Spannung auf dem Kabel ist."],"execution":["Griff in Richtung unterer Bauch bzw. Nabel ziehen, Ellenbogen führen die Bewegung nah am Körper nach hinten.","Schulterblätter zusammen ziehen, Oberkörper bleibt aufrecht.","In der Endposition kurz halten, Griff berührt beinahe den Bauch.","Gewicht langsam zurückführen, Arme kontrolliert strecken.","Am Ende die Schulterblätter leicht nach vorne kommen lassen, um den Rücken zu dehnen.","Ohne Schwung aus dem Oberkörper die nächste Wiederholung beginnen."],"range_of_motion":"Von gestreckten Armen mit leicht nach vorne gezogenen Schulterblättern bis der Griff den unteren Bauch fast berührt. Der Oberkörper bewegt sich dabei nur wenige Grad.","breathing":"Beim Ziehen ausatmen, beim Strecken der Arme einatmen.","common_mistakes":["Oberkörper pendelt stark vor und zurück, Bewegung kommt aus dem unteren Rücken.","Schultern ziehen während des Zugs nach oben zu den Ohren.","Ellenbogen weichen nach außen aus, Griff wird zur Brust statt zum Bauch gezogen.","Rücken wird in der gestreckten Position stark gerundet.","Gewicht wird in der exzentrischen Phase einfach nach vorne gelassen."],"tips":["Vorstellen, die Ellenbogen nach hinten in die Hosentaschen zu ziehen.","In der Endposition eine Sekunde halten, um die Kontraktion im Rücken zu spüren.","Die exzentrische Phase zwei bis drei Sekunden lang ausführen.","Bei Beschwerden im unteren Rücken leichter beginnen und den Oberkörper bewusst stabil halten."],"cable_setup":{"cable":"Sitzende Ruderstation am Kabelturm oder Kabelturm mit unterer Rolle und Fußplatten","height":"ganz unten, so verläuft das Kabel im Sitzen etwa waagerecht auf Höhe des unteren Bauchs","grip_width":"Eng, neutral (Handflächen zueinander) am V-Griff","body_position":"Aufrecht sitzend, Brust angehoben, Rumpf stabil, Oberkörper nahezu senkrecht","foot_position":"Füße auf den Fußplatten, Knie leicht gebeugt","movement_direction":"Horizontal von vorne nach hinten in Richtung unterer Bauch","elbow_position":"Ellenbogen eng am Körper, zeigen nach hinten","end_position":"Griff am unteren Bauch, Schulterblätter zusammengezogen, Oberkörper aufrecht","return":"Langsam und kontrolliert bis zur Armstreckung, Schulterblätter am Ende leicht nach vorne kommen lassen"},"muscle_focus":["Vorne die Arme strecken und die Schulterblätter nach vorne gleiten lassen: so wird der Latissimus gedehnt und der Weg maximal.","Ellenbogen eng am Körper nach hinten ziehen, Schulterblätter am Ende zusammenführen.","Oberkörper bleibt still, der Zug kommt aus dem Rücken; wer sich zurücklehnt, verlagert die Arbeit auf den unteren Rücken.","8 bis 12 Wiederholungen, Rückführung 2 bis 3 Sekunden."],"requirements":["Sitzende Ruderstation oder Kabelturm mit unterer Rolle und Fußplatten","Enger V-Griff (Triangelgriff)"],"grip_alternatives":["neutral_parallel"],"alternative_exercises":["breites-rudern","kurzhantel-rudern-einarmig","kurzhantel-rudern-schraegbank"],"image_url":"/exercises/cable-tower.jpg","machine_name":"Kabelturm (Multistation)","animation_source_url":"https://modusx.de/fitness-uebungen/rudern-am-kabelzug-sitzend/enges-rudern-am-kabelzug/","variants":[{"name":"Kabelzug sitzend mit V-Griff (Standard)","description":"Füße gegen die Platte, Oberkörper aufrecht, Griff zum unteren Bauch ziehen.","source_url":"https://modusx.de/fitness-uebungen/rudern-am-kabelzug-sitzend/enges-rudern-am-kabelzug/"},{"name":"Hebelmaschine eng (Brustpolster)","description":"Brust ans Polster, neutrale Griffe eng. Das Polster verhindert Schwung, deshalb ideal für schwere Sätze.","source_url":"https://modusx.de/fitness-uebungen/t-bar-rudern/t-bar-rudern-an-der-maschine/"},{"name":"Einarmig am Kabel","description":"Ein Arm, Oberkörper leicht mitdrehen erlaubt. Größerer Bewegungsweg und Ausgleich von Seitenunterschieden."}]}$seed$::jsonb);

-- Rudern breit
select public.upsert_seed_exercise($seed${"slug":"breites-rudern","name":"Rudern breit","category":"back","equipment":"cable","grip_id":"wide_lat_bar","grip_notes":"Breite Latzugstange, pronierter Griff (Handrücken nach oben), Hände deutlich weiter als schulterbreit. Alternativ: gerade Stange in etwas engerer Griffweite.","primary_muscles":["upper_back","mid_back"],"secondary_muscles":["lats","rear_delts","biceps","forearms"],"description":"Horizontaler Zug mit breitem Obergriff. Die Ellenbogen gehen seitlich nach hinten, dadurch arbeiten oberer Rücken, hintere Schulter und Trapez stärker als beim engen Rudern. Kabelzug oder Hebelmaschine, die Bewegung ist dieselbe.","setup":["Breite Latzugstange am unteren Kabel der Ruderstation einhängen.","Hinsetzen, Füße auf die Fußplatten stellen, Knie leicht gebeugt.","Stange deutlich weiter als schulterbreit mit proniertem Griff fassen.","Oberkörper aufrichten, Brust angehoben, Schultern nach unten ziehen.","Arme gestreckt, Gewicht leicht abheben, sodass Spannung auf dem Kabel ist."],"execution":["Stange in Richtung untere Brust bzw. oberer Bauch ziehen.","Ellenbogen führen die Bewegung etwas weiter außen als beim engen Rudern, etwa 45 Grad vom Körper abgespreizt.","Schulterblätter zusammen ziehen, Oberkörper bleibt aufrecht.","In der Endposition kurz halten, Stange befindet sich nah an der unteren Brust.","Gewicht langsam zurückführen, Arme kontrolliert strecken.","Am Ende die Schulterblätter leicht nach vorne kommen lassen, ohne den Rücken rund zu machen.","Ohne Schwung die nächste Wiederholung beginnen."],"range_of_motion":"Von gestreckten Armen mit leicht nach vorne gezogenen Schulterblättern bis die Stange die untere Brust fast berührt. Der Oberkörper bleibt dabei nahezu senkrecht.","breathing":"Beim Ziehen ausatmen, beim Strecken der Arme einatmen.","common_mistakes":["Oberkörper pendelt stark nach hinten, um das Gewicht zu bewegen.","Ellenbogen fliegen weit nach außen auf Schulterhöhe, Schultern rollen nach vorne.","Stange wird zum Bauch gezogen, dadurch verlagert sich die Belastung vom oberen Rücken weg.","Schultern ziehen nach oben zu den Ohren.","Keine Kontrolle in der exzentrischen Phase."],"tips":["Fokus auf das Zusammenziehen der Schulterblätter, nicht auf die Arme.","Gewicht etwas leichter wählen als beim engen Rudern, da die Hebelverhältnisse ungünstiger sind.","Die exzentrische Phase zwei bis drei Sekunden lang kontrollieren."],"cable_setup":{"cable":"Sitzende Ruderstation am Kabelturm oder Kabelturm mit unterer Rolle und Fußplatten","height":"ganz unten, damit der Zug im Sitzen waagerecht bis leicht ansteigend zur unteren Brust verläuft","grip_width":"Deutlich weiter als schulterbreit, proniert (Handrücken nach oben)","body_position":"Aufrecht sitzend, Brust angehoben, Rumpf stabil, Oberkörper nahezu senkrecht","foot_position":"Füße auf den Fußplatten, Knie leicht gebeugt","movement_direction":"Horizontal von vorne nach hinten in Richtung untere Brust bzw. oberer Bauch","elbow_position":"Ellenbogen etwa 45 Grad vom Körper abgespreizt, zeigen nach hinten-außen","end_position":"Stange nah an der unteren Brust, Schulterblätter zusammengezogen, Oberkörper aufrecht","return":"Langsam und kontrolliert bis zur Armstreckung, Schulterblätter am Ende leicht nach vorne kommen lassen"},"muscle_focus":["Ellenbogen auf etwa Schulterhöhe seitlich nach hinten führen, dann arbeiten oberer Rücken und hintere Schulter.","Vorne vollständig strecken und den Rücken dehnen lassen, hinten Schulterblätter zusammenziehen.","Kein Schwung aus der Hüfte, der Oberkörperwinkel bleibt gleich.","8 bis 12 Wiederholungen, kontrolliert zurück."],"requirements":["Sitzende Ruderstation oder Kabelturm mit unterer Rolle und Fußplatten","Breite Latzugstange"],"grip_alternatives":["neutral_parallel"],"alternative_exercises":["enges-rudern","reverse-fly-kurzhantel"],"image_url":"/exercises/cable-tower.jpg","machine_name":"Kabelturm (Multistation)","animation_source_url":"https://modusx.de/fitness-uebungen/rudern-am-kabelzug-sitzend/kabelrudern-mit-breitem-griff/","variants":[{"name":"Kabelzug sitzend mit breiter Stange (Standard)","description":"Obergriff breiter als Schulter, Stange zur unteren Brust ziehen, Ellenbogen seitlich.","source_url":"https://modusx.de/fitness-uebungen/rudern-am-kabelzug-sitzend/kabelrudern-mit-breitem-griff/"},{"name":"Hebelmaschine breit","description":"Brust ans Polster, breite Griffe im Obergriff. Fester Rumpf, Ellenbogen auf Schulterhöhe nach hinten.","source_url":"https://modusx.de/fitness-uebungen/t-bar-rudern/t-bar-rudern-an-der-maschine/"}]}$seed$::jsonb);

-- Reverse Fly Kurzhantel
select public.upsert_seed_exercise($seed${"slug":"reverse-fly-kurzhantel","name":"Reverse Fly Kurzhantel","category":"back","equipment":"dumbbell","grip_id":null,"grip_notes":"Neutraler Griff (Handflächen zeigen zueinander) oder pronierter Griff (Handrücken nach oben). Hanteln locker in den Händen halten, Ellenbogen während der gesamten Bewegung leicht gebeugt.","primary_muscles":["rear_delts","upper_back"],"secondary_muscles":["traps","mid_back"],"description":"Seitliches Anheben der Arme in vorgebeugter Position, das die hintere Schulter und den oberen Rücken belastet. Geeignet als Ergänzung zu Zugübungen und als Ausgleich zu Druckübungen.","setup":["Leichte Kurzhanteln wählen.","Oberkörper etwa 45 Grad bis fast parallel zum Boden nach vorne neigen, Knie leicht gebeugt, Rücken gerade.","Alternativ bäuchlings auf eine Schrägbank legen, Brust auf dem Polster.","Hanteln unter der Brust hängen lassen, Arme fast gestreckt, Ellenbogen leicht gebeugt.","Rumpf anspannen, Nacken in Verlängerung der Wirbelsäule, Blick nach unten.","Schultern nach unten ziehen, bevor die Bewegung beginnt."],"execution":["Arme seitlich nach außen-oben anheben, Ellenbogen bleiben leicht gebeugt.","Bewegung aus den Schultern und Schulterblättern führen, nicht aus den Armen.","Anheben, bis die Oberarme etwa auf Höhe des Rückens sind.","In der Endposition kurz halten, Schulterblätter leicht zusammen ziehen.","Hanteln langsam und kontrolliert wieder absenken.","Unten die Spannung halten, Hanteln nicht zusammenschlagen lassen."],"range_of_motion":"Von hängenden Armen bis die Oberarme etwa auf Höhe des Rückens sind. Höher als die Rückenlinie ist nicht notwendig.","breathing":"Beim Anheben ausatmen, beim Absenken einatmen.","common_mistakes":["Oberkörper richtet sich beim Anheben auf, um Schwung zu holen.","Zu schweres Gewicht, Ellenbogen werden stark gebeugt und die Bewegung wird zum Rudern.","Schultern ziehen nach oben zu den Ohren.","Rücken wird in der vorgebeugten Position rund.","Hanteln werden einfach fallen gelassen, keine Kontrolle beim Absenken."],"tips":["Deutlich leichter beginnen als bei Ruderübungen, die hintere Schulter ist ein kleiner Muskel.","Daumen leicht nach unten drehen, um die hintere Schulter stärker zu betonen.","Die Variante auf der Schrägbank nimmt den unteren Rücken aus der Übung.","Höhere Wiederholungszahlen mit sauberer Technik sind hier sinnvoller als schweres Gewicht."],"cable_setup":null,"muscle_focus":["Arme unter der Brust hängen lassen und die Schulterblätter nach vorne gleiten lassen, so wird die hintere Schulter in der gedehnten Position belastet.","Bewegung aus dem Schultergelenk führen: Ellenbogenwinkel bleibt gleich, die Oberarme bewegen sich seitlich nach außen-oben in der Ebene des Oberkörpers.","Leichtes Gewicht wählen; sobald die Ellenbogen stark beugen oder der Oberkörper sich aufrichtet, übernehmen Rücken und Trapez die Arbeit.","Absenken über etwa zwei Sekunden kontrollieren und unten die Spannung halten."],"requirements":["Leichte Kurzhanteln","Optional: Schrägbank für die bäuchlings liegende Variante"],"grip_alternatives":[],"alternative_exercises":["reverse-butterfly","face-pull"],"animation_source_url":"https://modusx.de/fitness-uebungen/vorgebeugtes-seitheben-mit-kurzhanteln/vorgebeugtes-seitheben-sitzend/","variants":[]}$seed$::jsonb);

-- Straight Arm Pulldown
select public.upsert_seed_exercise($seed${"slug":"straight-arm-pulldown","name":"Straight Arm Pulldown","category":"back","equipment":"cable","grip_id":"straight_bar","grip_notes":"Gerade Stange, pronierter Griff etwa schulterbreit. Alternativ: Seil mit neutralem Griff (Handflächen zueinander), erlaubt am Ende etwas mehr Bewegung an der Hüfte vorbei.","primary_muscles":["lats"],"secondary_muscles":["triceps","rear_delts","abs"],"description":"Zugübung am oberen Kabel mit fast gestreckten Armen, bei der der Latissimus ohne nennenswerte Beteiligung des Bizeps arbeitet. Geeignet als Isolations- oder Vorermüdungsübung für den Rücken.","setup":["Gerade Stange am oberen Kabel einhängen.","Etwa einen Schritt vom Kabelturm entfernt aufstellen, Füße hüftbreit, Knie leicht gebeugt.","Stange schulterbreit mit proniertem Griff fassen, Arme nach vorne-oben gestreckt.","Oberkörper leicht nach vorne neigen, Rücken gerade, Rumpf anspannen.","Schultern nach unten ziehen, Ellenbogen leicht gebeugt und in dieser Position fixieren."],"execution":["Stange in einem Bogen nach unten zu den Oberschenkeln ziehen, Arme bleiben fast gestreckt.","Bewegung aus den Schultern führen, Ellenbogenwinkel bleibt unverändert.","Schulterblätter nach unten ziehen, Oberkörper bleibt stabil.","In der Endposition kurz halten, Stange berührt beinahe die Oberschenkel.","Stange langsam und kontrolliert wieder nach oben führen.","Oben die Dehnung im Latissimus spüren, ohne den Rücken zu überstrecken.","Ohne Schwung aus dem Oberkörper die nächste Wiederholung beginnen."],"range_of_motion":"Von Armen etwa auf Höhe des Kopfes oder leicht darüber bis die Stange die Oberschenkel fast berührt. Oben nur so weit, wie der Rücken gerade bleibt.","breathing":"Beim Ziehen nach unten ausatmen, beim Zurückführen nach oben einatmen.","common_mistakes":["Ellenbogen werden während des Zugs gebeugt, die Übung wird zum Trizepsdrücken.","Oberkörper pendelt mit, um das Gewicht zu bewegen.","Schultern rollen nach vorne und ziehen nach oben.","Zu schweres Gewicht, die Bewegung wird kurz und ruckartig.","Rücken wird in der oberen Position stark überstreckt."],"tips":["Leichtes Gewicht wählen und die Spannung im Latissimus über den gesamten Bewegungsradius halten.","Vorstellen, die Stange mit den Ellenbogen statt mit den Händen nach unten zu drücken.","Die exzentrische Phase zwei bis drei Sekunden lang ausführen.","Mit dem Seil lässt sich die Endposition etwas weiter an der Hüfte vorbei führen."],"cable_setup":{"cable":"Kabelturm mit oberer Rolle; alternativ Latzug-Station am Kabelturm im Stand","height":"ganz oben, damit der Zug von oben kommt und der Latissimus bei angehobenen Armen in der gedehnten Position belastet wird","grip_width":"Schulterbreit, proniert (Handrücken nach oben) an der geraden Stange","body_position":"Stehend, etwa einen Schritt vom Turm entfernt, Oberkörper leicht nach vorne geneigt, Rücken gerade, Rumpf angespannt","foot_position":"Hüftbreit, Knie leicht gebeugt, Gewicht gleichmäßig auf beiden Füßen","movement_direction":"Bogenförmig von vorne-oben nach unten zu den Oberschenkeln","elbow_position":"Leicht gebeugt und während der gesamten Bewegung unverändert","end_position":"Stange an den Oberschenkeln, Schulterblätter nach unten gezogen, Oberkörper stabil","return":"Langsam und kontrolliert nach oben bis etwa auf Kopfhöhe, Dehnung im Latissimus, Rücken bleibt gerade"},"muscle_focus":["Oben die Arme etwa auf Kopfhöhe lang werden lassen und die Dehnung im Latissimus kurz aufnehmen, ohne den unteren Rücken zu überstrecken.","Bewegung ausschließlich aus dem Schultergelenk führen: Ellenbogenwinkel bleibt leicht gebeugt und unverändert, die Oberarme drücken in einem Bogen nach unten zur Hüfte.","Leichtes Gewicht wählen; sobald die Ellenbogen beugen oder die Schultern nach vorne rollen, übernehmen Trizeps und Brust.","Rückführung zwei bis drei Sekunden kontrollieren, oben nicht ins Hohlkreuz ausweichen."],"requirements":["Kabelturm mit oberer Rolle","Gerade kurze Stange; alternativ breite Latzugstange oder Seil"],"grip_alternatives":["wide_lat_bar","rope"],"alternative_exercises":[],"image_url":"/exercises/cable-tower.jpg","machine_name":"Kabelturm (Multistation)","variants":[]}$seed$::jsonb);

-- Hyperextensions
select public.upsert_seed_exercise($seed${"slug":"hyperextensions","name":"Hyperextensions","category":"back","equipment":"bodyweight","grip_id":null,"grip_notes":"Arme vor der Brust verschränkt oder Hände an den Schläfen. Mit Zusatzgewicht: Hantelscheibe oder Kurzhantel vor der Brust halten.","primary_muscles":["lower_back","glutes"],"secondary_muscles":["hamstrings"],"description":"Rumpfstreckung an der 45-Grad-Rückenstrecker-Bank, die den unteren Rücken, das Gesäß und die hintere Oberschenkelmuskulatur belastet. Geeignet als Ergänzung im Rücken- oder Beintraining und zur Kräftigung der Rumpfrückseite.","setup":["Hüftpolster so einstellen, dass die Oberkante knapp unterhalb des Hüftknochens liegt und die Hüfte frei beugen kann.","Fersen fest gegen die Fußplatte stellen, Füße hüftbreit.","Oberkörper auf dem Polster ablegen, Arme vor der Brust verschränken.","Rumpf anspannen, Nacken in Verlängerung der Wirbelsäule.","Oberkörper aufrichten, bis der Körper eine gerade Linie von Kopf bis Ferse bildet."],"execution":["Oberkörper langsam aus der Hüfte nach unten absenken, Wirbelsäule bleibt neutral.","So weit absenken, wie der Rücken gerade bleibt, etwa bis der Oberkörper senkrecht ist.","Gesäß und hintere Oberschenkel anspannen und den Oberkörper kontrolliert wieder anheben.","Anheben, bis Oberkörper und Beine eine gerade Linie bilden.","In der Endposition kurz halten, ohne weiter nach oben zu überstrecken.","Nächste Wiederholung kontrolliert beginnen."],"range_of_motion":"Von der geraden Linie zwischen Oberkörper und Beinen bis der Oberkörper etwa senkrecht hängt. In der Endposition nicht über die gerade Linie hinaus überstrecken.","breathing":"Beim Absenken einatmen, beim Anheben ausatmen.","common_mistakes":["Oberkörper wird in der Endposition über die gerade Linie hinaus überstreckt.","Rücken wird beim Absenken rund, Bewegung kommt aus der Wirbelsäule statt aus der Hüfte.","Polster zu hoch eingestellt, Hüfte kann nicht frei beugen.","Bewegung wird mit Schwung ausgeführt.","Kopf wird in den Nacken gelegt."],"tips":["Zunächst mit Körpergewicht beginnen, Zusatzgewicht erst dann, wenn die Technik stabil ist.","Für mehr Betonung des Gesäßes die Füße leicht nach außen drehen und bewusst aus der Hüfte arbeiten.","Die exzentrische Phase zwei bis drei Sekunden lang kontrollieren."],"cable_setup":null,"muscle_focus":["Hüftpolster knapp unter dem Hüftknochen einstellen, damit die Beugung aus der Hüfte kommt und Gesäß und hintere Oberschenkel in der tiefen Position gedehnt werden.","Beim Absenken die Wirbelsäule neutral halten und so tief gehen, wie der Rücken gerade bleibt; die Dehnung unten kurz aufnehmen.","Beim Anheben Gesäß und hintere Oberschenkel aktiv anspannen und nur bis zur geraden Linie kommen; Überstrecken verlagert die Last auf die Lendenwirbelsäule.","Exzentrische Phase zwei bis drei Sekunden kontrollieren, kein Schwung aus dem Oberkörper."],"requirements":["45-Grad-Rückenstrecker-Bank (Hyperextension-Bank)","Optional: Hantelscheibe vor der Brust als Zusatzgewicht"],"grip_alternatives":[],"image_url":"/exercises/hyperextension-bench.jpg","machine_name":"Hyperextension-Bank 45°","alternative_exercises":["rumaenisches-kreuzheben","kurzhantel-rumaenisches-kreuzheben"],"bodyweight_factor":0.6,"animation_source_url":"https://modusx.de/fitness-uebungen/rueckenstrecken-am-geraet/hyperextensions-auf-der-hyperextension-bank/","variants":[]}$seed$::jsonb);

-- Wrist Curl
select public.upsert_seed_exercise($seed${"slug":"wrist-curl","name":"Wrist Curl","category":"forearms","equipment":"dumbbell","grip_id":null,"grip_notes":"Supinierter Griff (Handflächen nach oben), Kurzhantel locker in den Fingern. Alternativ: Langhantel mit beiden Händen, etwa schulterbreit.","primary_muscles":["forearms"],"secondary_muscles":[],"description":"Isolierte Beugung des Handgelenks mit der Kurzhantel, die die Beugemuskulatur des Unterarms belastet. Geeignet als Ergänzung am Ende des Arm- oder Rückentrainings.","setup":["Leichte Kurzhantel wählen, sitzend auf einer Bank Platz nehmen.","Unterarm auf dem Oberschenkel oder auf der Bank ablegen, Handfläche zeigt nach oben.","Handgelenk ragt über das Knie bzw. die Bankkante hinaus, sodass es sich frei bewegen kann.","Hantel locker greifen, Finger leicht geöffnet.","Unterarm bleibt während der gesamten Bewegung auf der Unterlage."],"execution":["Handgelenk langsam nach unten beugen, Hantel in die Finger rollen lassen.","In der unteren Position die Dehnung im Unterarm kurz halten.","Hantel mit den Fingern wieder greifen und das Handgelenk nach oben beugen.","In der oberen Position kurz halten, Unterarm bleibt auf der Unterlage.","Hantel langsam und kontrolliert wieder absenken.","Nach allen Wiederholungen die Seite wechseln."],"range_of_motion":"Von der vollständig gestreckten Position mit geöffneten Fingern bis zur vollen Beugung des Handgelenks nach oben. Der Unterarm bewegt sich dabei nicht.","breathing":"Beim Beugen nach oben ausatmen, beim Absenken einatmen.","common_mistakes":["Unterarm hebt sich von der Unterlage ab, die Bewegung kommt aus dem Ellenbogen.","Zu schweres Gewicht, der Bewegungsradius wird sehr klein.","Hantel wird mit Schwung nach oben geworfen.","Keine Kontrolle beim Absenken."],"tips":["Leichtes Gewicht und höhere Wiederholungszahlen wählen, die Unterarmmuskulatur reagiert gut darauf.","Die Hantel bewusst bis in die Finger rollen lassen, um den vollen Bewegungsradius zu nutzen.","Tempo langsam halten, etwa zwei Sekunden pro Phase."],"cable_setup":null,"muscle_focus":["Unten die Hantel bis in die Finger rollen lassen und die Dehnung der Unterarmbeuger kurz halten; dieser gedehnte Bereich ist der wichtigste Teil der Bewegung.","Unterarm fest auf der Unterlage lassen, die Bewegung kommt ausschließlich aus dem Handgelenk.","Leichtes Gewicht und langsames Tempo wählen, etwa zwei Sekunden pro Phase; zu schwere Hanteln verkürzen den Bewegungsradius."],"requirements":["Leichte Kurzhantel","Flachbank oder Hocker zum Sitzen und Ablegen des Unterarms"],"grip_alternatives":[],"alternative_exercises":[],"animation_source_url":"https://modusx.de/fitness-uebungen/unterarm-curls/unterarm-curls-mit-der-hantel/","variants":[]}$seed$::jsonb);

-- Reverse Wrist Curl
select public.upsert_seed_exercise($seed${"slug":"reverse-wrist-curl","name":"Reverse Wrist Curl","category":"forearms","equipment":"dumbbell","grip_id":null,"grip_notes":"Pronierter Griff (Handflächen nach unten), Hantel fest umschlossen. Alternativ: Langhantel oder EZ-Stange mit beiden Händen, etwa schulterbreit.","primary_muscles":["forearms"],"secondary_muscles":[],"description":"Isolierte Streckung des Handgelenks mit der Kurzhantel, die die Streckmuskulatur des Unterarms belastet. Geeignet als Ausgleich zum Wrist Curl und zur Kräftigung der Unterarmaußenseite.","setup":["Deutlich leichtere Kurzhantel als beim Wrist Curl wählen, sitzend auf einer Bank Platz nehmen.","Unterarm auf dem Oberschenkel oder auf der Bank ablegen, Handfläche zeigt nach unten.","Handgelenk ragt über das Knie bzw. die Bankkante hinaus, sodass es sich frei bewegen kann.","Hantel fest umschließen, Handgelenk in neutraler Ausgangsposition.","Unterarm bleibt während der gesamten Bewegung auf der Unterlage."],"execution":["Handgelenk langsam nach unten beugen, Handrücken bewegt sich in Richtung Boden.","In der unteren Position die Dehnung an der Unterarmaußenseite kurz halten.","Handgelenk kontrolliert nach oben strecken, Handrücken bewegt sich in Richtung Unterarm.","In der oberen Position kurz halten, Unterarm bleibt auf der Unterlage.","Hantel langsam und kontrolliert wieder absenken.","Nach allen Wiederholungen die Seite wechseln."],"range_of_motion":"Von der vollständig gebeugten Position nach unten bis zur vollen Streckung des Handgelenks nach oben. Der Unterarm bewegt sich dabei nicht.","breathing":"Beim Strecken nach oben ausatmen, beim Absenken einatmen.","common_mistakes":["Zu schweres Gewicht, die Streckmuskulatur ist deutlich schwächer als die Beugemuskulatur.","Unterarm hebt sich von der Unterlage ab, die Bewegung kommt aus dem Ellenbogen.","Bewegungsradius wird sehr klein, nur das obere Drittel wird genutzt.","Hantel wird mit Schwung nach oben geworfen."],"tips":["Mit etwa der Hälfte des Gewichts vom Wrist Curl beginnen und bei Bedarf anpassen.","Leichtes Gewicht und höhere Wiederholungszahlen wählen.","Tempo langsam halten, etwa zwei Sekunden pro Phase.","Bei Beschwerden im Ellenbogen das Gewicht reduzieren oder den Bewegungsradius verkleinern."],"cable_setup":null,"muscle_focus":["Unten das Handgelenk vollständig beugen und die Dehnung an der Unterarmaußenseite kurz halten, dann kontrolliert nach oben strecken.","Unterarm bleibt auf der Unterlage, die Bewegung kommt nur aus dem Handgelenk; Ellenbogen und Schulter bleiben ruhig.","Deutlich leichter als beim Wrist Curl beginnen und das Tempo bei etwa zwei Sekunden pro Phase halten, damit der volle Bewegungsradius erhalten bleibt."],"requirements":["Sehr leichte Kurzhantel","Flachbank oder Hocker zum Sitzen und Ablegen des Unterarms"],"grip_alternatives":[],"alternative_exercises":[],"animation_source_url":"https://modusx.de/fitness-uebungen/reverse-unterarm-curls/reverse-unterarm-curls-mit-der-hantel/","variants":[]}$seed$::jsonb);

-- Kurzhantel Rudern einarmig
select public.upsert_seed_exercise($seed${"slug":"kurzhantel-rudern-einarmig","name":"Kurzhantel Rudern einarmig","category":"back","equipment":"dumbbell","grip_id":null,"grip_notes":null,"primary_muscles":["lats","mid_back"],"secondary_muscles":["rear_delts","biceps","forearms"],"description":"Einarmiges Rudern mit Abstützen auf der Bank. Großer Bewegungsweg, tiefe Dehnung des Latissimus und voller Ausgleich von Seitenunterschieden.","setup":["Ein Knie und die gleichseitige Hand auf die Bank, anderer Fuß am Boden.","Rücken gerade, parallel zum Boden, Blick nach unten.","Hantel mit der freien Hand greifen, Arm lang hängen lassen, Schulter nach unten sinken lassen."],"execution":["Hantel zur Hüfte ziehen, Ellenbogen eng am Körper nach hinten-oben.","Oben Schulterblatt zurückziehen, kurz halten.","Langsam absenken und den Arm vollständig strecken.","Unten die Schulter leicht nach vorne sinken lassen, Latissimus dehnt.","Oberkörper bleibt still, keine Drehung."],"range_of_motion":"Vom voll gestreckten Arm mit gesenkter Schulter bis zur Hüfte.","breathing":"Beim Ziehen ausatmen, beim Absenken einatmen.","common_mistakes":["Oberkörper mitdrehen und Schwung holen.","Hantel zur Brust statt zur Hüfte ziehen.","Unten nicht strecken.","Rücken runden."],"tips":["Schwere Hanteln sind hier erlaubt, 8 bis 12 Wiederholungen.","Beide Seiten gleich viele Wiederholungen, schwache Seite zuerst.","Gute Hauptübung für den Rücken an Tagen ohne Maschinen."],"cable_setup":null,"muscle_focus":["Unten den Latissimus bewusst dehnen lassen: Arm lang, Schulter sinkt mit, dann kommt der Zug aus dem Rücken.","Ellenbogen zur Hüfte, nicht nach außen; so arbeitet der Latissimus und nicht die hintere Schulter.","Kontrolliertes Absenken über 2 bis 3 Sekunden."],"requirements":["Flachbank","Eine Kurzhantel"],"grip_alternatives":[],"variants":[{"name":"Knie auf der Bank (Standard)","description":"Stabil, klassische Ausführung."},{"name":"Beide Füße am Boden, Hand auf der Bank","description":"Mehr Freiheit für die Hüfte, größerer Weg."}],"animation_source_url":"https://modusx.de/fitness-uebungen/klassisches-einarmiges-kurzhantel-rudern/","alternative_exercises":[]}$seed$::jsonb);

-- Kurzhantel Rudern Schrägbank
select public.upsert_seed_exercise($seed${"slug":"kurzhantel-rudern-schraegbank","name":"Kurzhantel Rudern Schrägbank","category":"back","equipment":"dumbbell","grip_id":null,"grip_notes":null,"primary_muscles":["mid_back","lats"],"secondary_muscles":["rear_delts","biceps"],"description":"Brustgestütztes Rudern mit zwei Kurzhanteln auf der Schrägbank. Die Brust liegt auf, Schwung ist unmöglich; so bleibt die ganze Arbeit beim Rücken.","setup":["Bank auf 30 bis 45 Grad, bäuchlings drauflegen, Brust am oberen Ende.","Füße fest am Boden oder auf den Fußrasten.","Hanteln hängen lassen, Arme gestreckt, Schultern nach vorne-unten fallen lassen."],"execution":["Hanteln zum Körper ziehen, Ellenbogen etwa 45 Grad abgespreizt.","Oben Schulterblätter zusammenziehen, kurz halten.","Langsam absenken, bis die Arme gestreckt sind.","Unten den Rücken dehnen lassen.","Brust bleibt immer am Polster."],"range_of_motion":"Vom voll gestreckten Arm bis zum Körper, Schulterblätter oben zusammen.","breathing":"Beim Ziehen ausatmen, beim Absenken einatmen.","common_mistakes":["Brust vom Polster heben, um Schwung zu holen.","Arme unten nicht strecken.","Hanteln nur mit den Armen heben statt mit dem Rücken.","Zu schwer, dadurch kein voller Weg."],"tips":["Leichter als beim einarmigen Rudern, dafür strenger.","10 bis 15 Wiederholungen bis nahe ans Versagen.","Ellenbogen weiter außen für mehr oberen Rücken, enger für mehr Latissimus."],"cable_setup":null,"muscle_focus":["Volle Streckung unten, die Schulterblätter dürfen nach vorne gleiten: das ist die gedehnte Position des Rückens.","Oben die Schulterblätter aktiv zusammenziehen und eine Sekunde halten.","2 bis 3 Sekunden Exzentrik, kein Abwerfen."],"requirements":["Schrägbank","Zwei Kurzhanteln"],"grip_alternatives":[],"variants":[{"name":"Ellenbogen 45 Grad (Standard)","description":"Gesamter Rücken."},{"name":"Ellenbogen weit außen","description":"Oberer Rücken und hintere Schulter."}],"animation_source_url":"https://modusx.de/fitness-uebungen/kurzhantel-rudern-schraegbank/","alternative_exercises":[]}$seed$::jsonb);

-- Hackenschmidt Kniebeuge
select public.upsert_seed_exercise($seed${"slug":"hackenschmidt","name":"Hackenschmidt Kniebeuge","category":"quads","equipment":"machine","grip_id":null,"grip_notes":"Haltegriffe neben den Schulterpolstern fassen, Hände bleiben locker. Füße mittig auf der Plattform, etwa schulterbreit, Fußspitzen leicht nach außen.","primary_muscles":["quads"],"secondary_muscles":["glutes","hamstrings"],"description":"Geführte Kniebeuge mit Rückenpolster, der sicherste Weg, den Quadrizeps mit viel Gewicht in tiefer Beugung zu belasten. Die Multipresse-Kniebeuge ist die gleiche geführte Bewegung ohne Polster und deshalb hier eine Variante.","setup":["Rücken und Schultern vollständig an das Rückenpolster und die Schulterpolster anlegen.","Füße mittig und etwa schulterbreit auf der Plattform platzieren, Fußspitzen leicht nach außen.","Haltegriffe fassen und die Sicherungen der Maschine lösen.","Rumpf anspannen, unterer Rücken bleibt am Polster.","Knie in der Startposition leicht gebeugt lassen, nicht durchgestreckt."],"execution":["Schlitten kontrolliert absenken, Knie beugen sich in Richtung Fußspitzen.","Fersen bleiben während der gesamten Bewegung auf der Plattform.","So tief absenken, wie Beweglichkeit und Becken am Polster es zulassen.","Kurz in der unteren Position stoppen, ohne das Gewicht abzusetzen.","Über die ganze Fußsohle nach oben drücken, bis die Knie fast gestreckt sind.","Knie oben nicht durchdrücken, Spannung im Oberschenkel halten."],"range_of_motion":"Absenken, bis die Oberschenkel etwa parallel zur Plattform stehen oder so weit, wie das Becken am Polster bleibt. Oben kurz vor der vollen Kniestreckung stoppen.","breathing":"Beim Hochdrücken ausatmen, beim Absenken einatmen.","common_mistakes":["Fersen heben sich in der unteren Position von der Plattform ab.","Knie fallen nach innen, statt in Richtung Fußspitzen zu zeigen.","Becken kippt unten vom Polster weg, unterer Rücken rundet sich.","Knie werden oben vollständig durchgestreckt und die Spannung geht verloren.","Füße stehen zu weit unten auf der Plattform, Fersen finden keinen Halt."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Füße etwas höher auf der Plattform platzieren, wenn Gesäß und hintere Oberschenkel stärker beteiligt sein sollen.","Sicherungen vor dem Satz prüfen und erst nach dem letzten Satz wieder einrasten lassen.","Erst dann Gewicht erhöhen, wenn die Tiefe über alle Wiederholungen gleich bleibt."],"cable_setup":null,"muscle_focus":["Tief beugen: unterhalb der Waagerechten arbeitet der Quadrizeps in gedehnter Position, dort entsteht der größte Reiz.","Füße weiter vorne verlagern die Last Richtung Gesäß, weiter hinten Richtung Quadrizeps.","Knie über die Fußspitzen hinaus sind bei beschwerdefreien Knien erwünscht, nicht verboten.","6 bis 12 Wiederholungen, kontrolliertes Absenken, oben nicht einrasten."],"requirements":["Hackenschmidt-Maschine (Hack Squat) mit Schulterpolstern und Sicherungen"],"grip_alternatives":[],"image_url":"/exercises/hack-squat.jpg","machine_name":"Hack Squat, Plate Loaded","alternative_exercises":["beinpresse-45-grad","kniebeuge","kurzhantel-kniebeuge"],"animation_source_url":"https://modusx.de/fitness-uebungen/hackenschmidt-kniebeuge/","variants":[{"name":"Hackenschmidt (Standard)","description":"Schultern unter die Polster, Füße mittig, tief beugen, Rücken bleibt am Polster.","source_url":"https://modusx.de/fitness-uebungen/hackenschmidt-kniebeuge/"},{"name":"Enger Stand","description":"Füße hüftbreit oder enger, Schwerpunkt äußerer Quadrizeps.","source_url":"https://modusx.de/fitness-uebungen/hackenschmidt-kniebeuge/enge-squats-an-der-squat-maschine/"},{"name":"Multipresse-Kniebeuge","description":"Stange in der Führung, Füße eine Fußlänge vor der Stange. Erlaubt aufrechten Oberkörper und tiefe Beugung ohne Gleichgewichtsarbeit.","source_url":"https://modusx.de/fitness-uebungen/multipresse-kniebeuge/"}]}$seed$::jsonb);

-- Beinstrecker
select public.upsert_seed_exercise($seed${"slug":"beinstrecker","name":"Beinstrecker","category":"quads","equipment":"machine","grip_id":null,"grip_notes":"Haltegriffe seitlich am Sitz fassen, um das Becken im Sitz zu halten. Keine Griffarbeit nötig, Hände bleiben locker.","primary_muscles":["quads"],"secondary_muscles":[],"description":"Isolationsübung an der Maschine, bei der die Knie gegen Widerstand gestreckt werden. Gut geeignet, um den Quadrizeps gezielt und ohne Belastung von Hüfte und Rücken zu trainieren.","setup":["Rückenlehne so einstellen, dass die Drehachse der Maschine auf Höhe des Kniegelenks liegt.","Beinpolster so einstellen, dass es knapp oberhalb des Sprunggelenks am Schienbein anliegt.","Rücken vollständig an das Polster anlehnen, Haltegriffe fassen.","Oberschenkel liegen flach auf dem Sitz, Fußspitzen leicht angezogen.","Gewicht so wählen, dass die Streckung kontrolliert möglich ist."],"execution":["Beine kontrolliert strecken, bis die Knie fast gestreckt sind.","In der Endposition ein bis zwei Sekunden halten und den Quadrizeps anspannen.","Oberschenkel bleiben auf dem Sitz, Becken bleibt am Polster.","Gewicht langsam zurückführen, bis der Kniewinkel etwa 90 Grad erreicht.","Gewicht nicht aufsetzen lassen, Spannung halten.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von etwa 90 Grad Kniebeugung bis zur fast vollständigen Streckung. Bei Beschwerden im Knie den Bewegungsradius in der unteren Position verkleinern.","breathing":"Beim Strecken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Gewicht wird mit Schwung nach oben geschleudert.","Becken hebt sich vom Sitz ab, um mehr Gewicht zu bewegen.","Drehachse der Maschine liegt nicht auf Kniehöhe, Knie wird ungünstig belastet.","Gewicht fällt in der exzentrischen Phase unkontrolliert zurück.","Polster liegt zu hoch am Schienbein, Hebel wird ungünstig."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Fußspitzen leicht nach oben ziehen, um die Spannung im Quadrizeps zu erhöhen.","Einbeinige Ausführung, um Seitenunterschiede auszugleichen.","Mit moderatem Gewicht und höheren Wiederholungszahlen beginnen, dann schrittweise steigern."],"cable_setup":null,"muscle_focus":["Drehachse der Maschine auf Kniehöhe und das Polster knapp über dem Sprunggelenk einstellen, damit der Widerstand über den ganzen Hebel auf den Quadrizeps wirkt.","Rückenlehne eher nach hinten geneigt einstellen, so wird der gerade Oberschenkelmuskel über die Hüfte vorgedehnt und arbeitet stärker mit.","Unten bis etwa 90 Grad oder tiefer zurückführen, soweit die Knie beschwerdefrei bleiben, oben ein bis zwei Sekunden halten; das Becken bleibt am Polster.","Exzentrische Phase zwei bis drei Sekunden kontrollieren, kein Schwung aus der unteren Position."],"requirements":["Beinstrecker-Maschine mit verstellbarer Rückenlehne und Beinpolster"],"grip_alternatives":[],"image_url":"/exercises/leg-extension-curl.jpg","machine_name":"DHZ Leg Extension / Leg Curl, Steckgewicht","alternative_exercises":["beinbeuger"],"animation_source_url":"https://modusx.de/fitness-uebungen/beinstrecken-maschine/","variants":[]}$seed$::jsonb);

-- Bulgarian Split Squat
select public.upsert_seed_exercise($seed${"slug":"bulgarian-split-squat","name":"Bulgarian Split Squat","category":"quads","equipment":"dumbbell","grip_id":null,"grip_notes":"Kurzhanteln neutral an den Seiten halten, Arme hängen locker, Handgelenke gerade. Alternativ eine Kurzhantel vor der Brust halten (Goblet-Position) für mehr Rumpfstabilität.","primary_muscles":["quads","glutes"],"secondary_muscles":["hamstrings","abs"],"description":"Einbeinige Kniebeuge mit dem hinteren Fuß auf einer Bank, bei der das vordere Bein die Hauptlast trägt. Gut geeignet, um Quadrizeps und Gesäß einseitig zu belasten und Seitenunterschiede auszugleichen.","setup":["Bank hinter sich aufstellen, Kurzhanteln an den Seiten halten.","Mit dem Rücken zur Bank einen großen Schritt nach vorne machen.","Hinteren Fuß mit dem Fußrücken oder den Zehen auf der Bank ablegen.","Vorderer Fuß steht flach und so weit vorne, dass das Knie unten etwa über dem Mittelfuß bleibt.","Oberkörper aufrecht, Blick nach vorne, Rumpf anspannen."],"execution":["Vorderes Knie kontrolliert beugen und das Becken gerade nach unten absenken.","Vorderes Knie zeigt in Richtung Fußspitze, Ferse bleibt am Boden.","Hinteres Knie nähert sich dem Boden, ohne aufzusetzen.","Oberkörper bleibt aufrecht oder leicht nach vorne geneigt.","Über die ganze Fußsohle des vorderen Fußes nach oben drücken.","Oben Knie nicht durchstrecken, Spannung halten.","Nach allen Wiederholungen die Seite wechseln."],"range_of_motion":"Absenken, bis der vordere Oberschenkel etwa parallel zum Boden steht oder das hintere Knie knapp über dem Boden ist, je nach Beweglichkeit. Oben kurz vor der vollen Streckung stoppen.","breathing":"Beim Hochdrücken ausatmen, beim Absenken einatmen.","common_mistakes":["Vorderer Fuß steht zu nah an der Bank, Knie wandert weit über die Fußspitze.","Vorderes Knie fällt nach innen.","Oberkörper kippt stark nach vorne oder dreht sich ein.","Hinteres Bein drückt aktiv mit und übernimmt einen Teil der Arbeit.","Ferse des vorderen Fußes hebt sich vom Boden ab."],"tips":["Zuerst ohne Zusatzgewicht die Fußposition finden, dann Kurzhanteln hinzunehmen.","Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Leichte Vorlage des Oberkörpers betont das Gesäß, aufrechte Haltung mehr den Quadrizeps.","Bei Gleichgewichtsproblemen mit einer Hand leicht an einem Rack abstützen."],"cable_setup":null,"muscle_focus":["Tief absenken, bis das hintere Knie knapp über dem Boden ist; das vordere Bein trägt die Last, die tiefe Position belastet Quadrizeps und Gesäß in der Dehnung.","Vorderes Knie in Richtung Fußspitze führen und die Ferse am Boden lassen; aufrechter Oberkörper betont den Quadrizeps, leichte Vorlage das Gesäß.","Hinteres Bein nur zum Ausbalancieren nutzen, nicht aktiv mitdrücken.","Exzentrische Phase etwa zwei Sekunden kontrollieren, oben kurz vor der Kniestreckung stoppen."],"requirements":["Kurzhanteln","Flachbank für den hinteren Fuß","Optional: Rack oder Wand zum Abstützen bei Gleichgewichtsproblemen"],"grip_alternatives":[],"alternative_exercises":[],"animation_source_url":"https://modusx.de/fitness-uebungen/bulgarian-split-squat/bulgarian-split-kniebeugen-mit-kurzhanteln/","variants":[]}$seed$::jsonb);

-- Kniebeuge
select public.upsert_seed_exercise($seed${"slug":"kniebeuge","name":"Kniebeuge","category":"quads","equipment":"barbell","grip_id":null,"grip_notes":"Pronierter Griff etwas weiter als schulterbreit, Stange liegt auf dem oberen Trapez (High Bar) oder etwas tiefer auf den hinteren Schultern (Low Bar). Handgelenke möglichst gerade, Ellenbogen zeigen nach unten.","primary_muscles":["quads","glutes"],"secondary_muscles":["hamstrings","lower_back","abs"],"description":"Freie Kniebeuge mit der Langhantel im Nacken, bei der Knie und Hüfte gemeinsam gebeugt und gestreckt werden. Grundübung für Quadrizeps und Gesäß, die zusätzlich Rumpf und unteren Rücken fordert.","setup":["Stange im Rack etwa auf Höhe des oberen Brustbeins ablegen, Sicherheitsstangen knapp unterhalb der tiefsten Position einstellen.","Unter die Stange treten, Stange auf dem oberen Trapez ablegen und Griff etwas weiter als schulterbreit fassen.","Schulterblätter zusammenziehen, Rumpf anspannen und Stange aus dem Rack heben.","Ein bis zwei kleine Schritte zurück, Füße etwa schulterbreit, Fußspitzen leicht nach außen.","Blick nach vorne, Stange steht über dem Mittelfuß."],"execution":["Vor dem Absenken einatmen und den Rumpf anspannen.","Hüfte und Knie gleichzeitig beugen, Becken nach hinten und unten absenken.","Knie zeigen in Richtung Fußspitzen, Fersen bleiben am Boden.","So tief absenken, wie der Rücken neutral bleibt.","Über die ganze Fußsohle nach oben drücken, Hüfte und Schultern steigen gemeinsam.","Oben aufrecht stehen, Knie nicht hart durchstrecken.","Nach dem letzten Satz Stange kontrolliert zurück ins Rack führen."],"range_of_motion":"Tiefe nach Beweglichkeit wählen, in der Regel bis die Oberschenkel etwa parallel zum Boden stehen oder tiefer. Sobald das Becken unten einrollt oder die Fersen abheben, ist der sinnvolle Bewegungsradius erreicht.","breathing":"Oben einatmen und die Spannung während des Absenkens halten, beim Hochdrücken nach dem schwersten Punkt ausatmen.","common_mistakes":["Knie fallen nach innen.","Fersen heben sich vom Boden ab, Gewicht verlagert sich auf die Zehen.","Hüfte steigt beim Hochdrücken schneller als die Schultern, Oberkörper kippt nach vorne.","Unterer Rücken rundet sich in der tiefen Position.","Sicherheitsstangen werden nicht eingestellt oder liegen zu hoch."],"tips":["Technik zuerst mit der leeren Stange oder leichtem Gewicht festigen.","Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Bei eingeschränkter Sprunggelenkbeweglichkeit Fersen leicht erhöhen oder Schuhe mit erhöhter Ferse nutzen.","Gewicht in kleinen Schritten steigern, wenn Tiefe und Rückenposition stabil bleiben."],"cable_setup":null,"muscle_focus":["So tief gehen, wie der Rücken neutral bleibt, in der Regel bis die Oberschenkel mindestens parallel stehen; die tiefe Position belastet Quadrizeps und Gesäß in der gedehnten Stellung.","Knie in Richtung Fußspitzen führen und das Gewicht über dem Mittelfuß halten; die Fersen bleiben am Boden.","Hüfte und Schultern gemeinsam anheben; steigt die Hüfte zuerst, wandert die Last vom Quadrizeps in Rücken und Hüfte.","Absenken etwa zwei Sekunden kontrollieren und unten nicht abfedern."],"requirements":["Langhantel und Rack mit Sicherheitsstangen","Hantelscheiben mit Verschlüssen","Optional: Schuhe mit erhöhter Ferse"],"grip_alternatives":[],"image_url":"/exercises/half-rack.jpg","machine_name":"Half Rack mit Plattform","alternative_exercises":["hackenschmidt","beinpresse-45-grad","kurzhantel-kniebeuge"],"animation_source_url":"https://modusx.de/fitness-uebungen/langhantel-kniebeuge/","variants":[]}$seed$::jsonb);

-- Ausfallschritte
select public.upsert_seed_exercise($seed${"slug":"ausfallschritte","name":"Ausfallschritte","category":"glutes","equipment":"dumbbell","grip_id":null,"grip_notes":"Kurzhanteln neutral an den Seiten halten, Arme hängen locker, Schultern hinten. Handgelenke gerade.","primary_muscles":["glutes","quads"],"secondary_muscles":["hamstrings","abs"],"description":"Schrittbewegung mit Kurzhanteln, bei der ein Bein nach vorne gesetzt und das Becken abgesenkt wird, entweder gehend (Walking Lunges) oder auf der Stelle. Gut geeignet für Gesäß und Oberschenkel sowie für Gleichgewicht und einseitige Stabilität.","setup":["Kurzhanteln an den Seiten halten, Füße hüftbreit, Oberkörper aufrecht.","Ausreichend Platz nach vorne sicherstellen, besonders bei gehender Ausführung.","Rumpf anspannen, Blick nach vorne.","Schrittlänge so wählen, dass das vordere Knie unten etwa über dem Mittelfuß bleibt."],"execution":["Mit einem Bein einen großen Schritt nach vorne machen und den Fuß flach aufsetzen.","Becken gerade nach unten absenken, beide Knie beugen sich.","Vorderes Knie zeigt in Richtung Fußspitze, Ferse bleibt am Boden.","Hinteres Knie nähert sich dem Boden, ohne hart aufzusetzen.","Über die ganze Fußsohle des vorderen Fußes nach oben drücken.","Bei Walking Lunges das hintere Bein direkt in den nächsten Schritt führen, auf der Stelle zurück in die Ausgangsposition.","Seiten gleichmäßig abwechseln."],"range_of_motion":"Absenken, bis der vordere Oberschenkel etwa parallel zum Boden steht und das hintere Knie knapp über dem Boden ist, je nach Beweglichkeit. Oben kurz vor der vollen Kniestreckung stoppen.","breathing":"Beim Hochdrücken ausatmen, beim Absenken einatmen.","common_mistakes":["Schritt zu kurz, vorderes Knie wandert weit über die Fußspitze.","Vorderes Knie fällt nach innen.","Oberkörper kippt nach vorne oder dreht sich zur Seite.","Hinteres Knie schlägt auf den Boden auf.","Abdruck erfolgt über die Zehen statt über die ganze Fußsohle."],"tips":["Zuerst ohne Zusatzgewicht die Schrittlänge finden, dann Kurzhanteln hinzunehmen.","Leichte Vorlage des Oberkörpers betont das Gesäß stärker.","Exzentrische Phase kontrolliert ausführen, nicht in die untere Position fallen.","Bei Gleichgewichtsproblemen Ausfallschritte auf der Stelle statt gehend ausführen."],"cable_setup":null,"muscle_focus":["Großen Schritt wählen und das Becken gerade absenken, bis das hintere Knie knapp über dem Boden ist; so werden Gesäß und Quadrizeps des vorderen Beins in der gedehnten Position belastet.","Über die ganze Fußsohle des vorderen Fußes hochdrücken, Knie in Richtung Fußspitze; leichte Vorlage des Oberkörpers betont das Gesäß.","Rumpf stabil und Oberkörper ruhig halten, kein Eindrehen oder Pendeln.","Absenken kontrolliert ausführen und nicht in die untere Position fallen."],"requirements":["Kurzhanteln","Bank oder Ablage zum Aufnehmen und Abstellen der Kurzhanteln","Ausreichend Platz nach vorne, besonders bei gehender Ausführung"],"grip_alternatives":[],"alternative_exercises":[],"animation_source_url":"https://modusx.de/fitness-uebungen/klassische-lunges-mit-gewicht/ausfallschritte-mit-kurzhanteln/","variants":[]}$seed$::jsonb);

-- Beinbeuger
select public.upsert_seed_exercise($seed${"slug":"beinbeuger","name":"Beinbeuger","category":"hamstrings","equipment":"machine","grip_id":null,"grip_notes":"Haltegriffe fassen, um Becken und Oberkörper stabil zu halten. Liegend: Griffe vorne unter dem Polster, Hüfte bleibt auf dem Polster. Sitzend: Griffe seitlich, Rücken am Polster, Oberschenkelpolster fest fixiert.","primary_muscles":["hamstrings"],"secondary_muscles":["calves","glutes"],"description":"Isolationsübung an der Maschine, bei der die Knie gegen Widerstand gebeugt werden, liegend oder sitzend. Gut geeignet, um die hintere Oberschenkelmuskulatur gezielt zu trainieren.","setup":["Maschine so einstellen, dass die Drehachse auf Höhe des Kniegelenks liegt.","Beinpolster knapp oberhalb der Ferse an der Achillessehne anlegen.","Liegend: Hüfte flach auf dem Polster, Oberkörper abgelegt, Griffe fassen.","Sitzend: Rücken am Polster, Oberschenkelpolster fest auf den Oberschenkeln fixieren, Griffe fassen.","Beine in der Startposition fast gestreckt, Fußspitzen leicht angezogen."],"execution":["Fersen kontrolliert in Richtung Gesäß ziehen.","Becken bleibt dabei stabil auf oder am Polster.","In der Endposition kurz halten und die hinteren Oberschenkel anspannen.","Gewicht langsam zurückführen, bis die Beine fast gestreckt sind.","Gewicht nicht aufsetzen lassen, Spannung halten.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von fast gestreckten Beinen bis zu einem Kniewinkel von etwa 90 Grad oder enger, soweit das Becken stabil bleibt. Die Dehnung in der gestreckten Position bewusst kontrollieren.","breathing":"Beim Beugen ausatmen, beim Strecken einatmen.","common_mistakes":["Hüfte hebt sich liegend vom Polster ab, unterer Rücken überstreckt.","Gewicht wird mit Schwung nach oben gezogen.","Beine werden am Ende nicht wieder kontrolliert gestreckt.","Polster liegt zu hoch an der Wade, Hebel wird ungünstig.","Sitzend: Oberschenkelpolster zu locker, Oberschenkel heben sich ab."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Sitzende Variante erlaubt eine stärkere Dehnung, liegende Variante eine stärkere Endkontraktion; beide lassen sich abwechseln.","Einbeinige Ausführung, um Seitenunterschiede auszugleichen.","Fußspitzen gestreckt halten, um den Anteil der Waden zu verringern und die hinteren Oberschenkel stärker zu betonen."],"cable_setup":null,"muscle_focus":["Startposition mit fast gestreckten Beinen einnehmen und die gedehnte Position bewusst mitnehmen; sitzend lässt sich die Dehnung durch einen leicht nach vorne geneigten Oberkörper verstärken.","Drehachse auf Kniehöhe und Polster knapp über der Ferse einstellen, dann wirkt der Widerstand sauber auf die hintere Oberschenkelmuskulatur.","Becken stabil auf bzw. am Polster lassen; Anheben der Hüfte oder Schwung verlagert die Arbeit in den unteren Rücken.","Fußspitzen eher gestreckt halten, um den Wadenanteil zu verringern, und die Rückführung zwei bis drei Sekunden kontrollieren."],"requirements":["Beinbeuger-Maschine, liegend oder sitzend, mit verstellbarer Drehachse und Beinpolster"],"grip_alternatives":[],"image_url":"/exercises/seated-leg-curl.jpg","machine_name":"DHZ Seated Leg Curl, Steckgewicht","alternative_exercises":["beinstrecker","kurzhantel-rumaenisches-kreuzheben"],"animation_source_url":"https://modusx.de/fitness-uebungen/beincurls-maschine/beinbeuger-sitzend-am-beinbeuger-geraet/","variants":[]}$seed$::jsonb);

-- Rumänisches Kreuzheben
select public.upsert_seed_exercise($seed${"slug":"rumaenisches-kreuzheben","name":"Rumänisches Kreuzheben","category":"hamstrings","equipment":"barbell","grip_id":null,"grip_notes":"Pronierter Griff etwa schulterbreit, Stange nah an den Oberschenkeln. Bei nachlassender Griffkraft Zughilfen nutzen.","primary_muscles":["hamstrings","glutes"],"secondary_muscles":["lower_back","forearms","upper_back"],"description":"Hüftdominante Beugebewegung mit der Langhantel, bei der die Knie leicht gebeugt bleiben und die Stange nah am Körper abgesenkt wird. Gut geeignet, um hintere Oberschenkel und Gesäß über eine Dehnung zu belasten.","setup":["Stange aus dem Rack oder vom Boden in den aufrechten Stand bringen, Füße hüftbreit.","Pronierter Griff etwa schulterbreit, Arme gestreckt, Stange liegt an den Oberschenkeln.","Knie leicht beugen und diesen Winkel während der Bewegung beibehalten.","Schulterblätter leicht nach hinten ziehen, Brust angehoben, Rücken neutral.","Rumpf anspannen, Gewicht auf der ganzen Fußsohle."],"execution":["Hüfte nach hinten schieben, Oberkörper neigt sich nach vorne.","Stange gleitet nah an den Oberschenkeln nach unten.","Rücken bleibt neutral, Blick folgt dem Oberkörper.","So tief absenken, wie der Rücken neutral bleibt und die Dehnung in den hinteren Oberschenkeln spürbar ist.","Hüfte nach vorne schieben und aufrichten, Gesäß anspannen.","Oben aufrecht stehen, unteren Rücken nicht überstrecken."],"range_of_motion":"Von der aufrechten Position bis die Stange etwa auf Höhe der Knie oder des oberen Schienbeins ist. Die Tiefe wird durch die neutrale Rückenposition begrenzt, nicht durch den Boden.","breathing":"Oben einatmen, während des Absenkens die Spannung halten, beim Aufrichten ausatmen.","common_mistakes":["Unterer Rücken rundet sich in der tiefen Position.","Stange entfernt sich vom Körper, Hebel auf den unteren Rücken steigt.","Knie werden stark gebeugt, Bewegung wird zur Kniebeuge.","Oben wird der untere Rücken überstreckt.","Schultern hängen nach vorne, Oberkörper verliert die Spannung."],"tips":["Technik zuerst mit leichtem Gewicht festigen und auf die Dehnung in den hinteren Oberschenkeln achten.","Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Zughilfen nutzen, wenn die Griffkraft vor den hinteren Oberschenkeln nachlässt.","Alternativ mit Kurzhanteln ausführen, wenn keine Langhantel verfügbar ist."],"cable_setup":null,"muscle_focus":["Hüfte aktiv nach hinten schieben und die Stange nah an den Oberschenkeln absenken, bis eine deutliche Dehnung in den hinteren Oberschenkeln spürbar ist; dieser gedehnte Bereich ist der wichtigste Teil der Bewegung.","Kniewinkel leicht gebeugt und über die ganze Bewegung konstant halten; stärkere Kniebeugung verlagert die Arbeit auf den Quadrizeps.","Rücken neutral und Schulterblätter leicht zurückgezogen; die Tiefe wird durch die neutrale Wirbelsäule begrenzt, nicht durch den Boden.","Absenken zwei bis drei Sekunden kontrollieren, oben über das Gesäß aufrichten und den unteren Rücken nicht überstrecken."],"requirements":["Langhantel mit Hantelscheiben und Verschlüssen; alternativ Kurzhanteln","Optional: Zughilfen bei nachlassender Griffkraft"],"grip_alternatives":[],"image_url":"/exercises/half-rack.jpg","machine_name":"Half Rack mit Plattform","alternative_exercises":["hyperextensions","kurzhantel-rumaenisches-kreuzheben"],"animation_source_url":"https://modusx.de/fitness-uebungen/rumaenisches-kreuzheben/","variants":[]}$seed$::jsonb);

-- Hip Thrust
select public.upsert_seed_exercise($seed${"slug":"hip-thrust","name":"Hip Thrust","category":"glutes","equipment":"barbell","grip_id":null,"grip_notes":"Stange mit proniertem Griff etwa schulterbreit außen am Polster halten, nur zum Stabilisieren, nicht ziehen. Alternativ: Hip-Thrust-Maschine mit Gurt oder Polster über der Hüfte, Haltegriffe seitlich.","primary_muscles":["glutes"],"secondary_muscles":["hamstrings","quads"],"description":"Hüftstreckung gegen Widerstand mit dem oberen Rücken auf einer Bank und der Langhantel auf der Hüfte. Gut geeignet, um das Gesäß in der gestreckten Endposition stark zu belasten.","setup":["Stabile Bank quer hinter sich stellen, Höhe etwa Kniehöhe.","Polster auf die Stange legen und Stange über die Hüfte rollen.","Oberen Rücken unterhalb der Schulterblätter auf der Bankkante ablegen.","Füße hüftbreit so aufstellen, dass die Unterschenkel in der Endposition etwa senkrecht stehen.","Rippen nach unten, Kinn leicht eingezogen, Rumpf anspannen."],"execution":["Über die Fersen die Hüfte nach oben drücken.","Gesäß in der Endposition bewusst anspannen, Hüfte vollständig gestreckt.","Oben bilden Schultern, Hüfte und Knie eine Linie, unterer Rücken bleibt neutral.","Ein bis zwei Sekunden oben halten.","Hüfte kontrolliert absenken, bis die Stange knapp über dem Boden ist.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von knapp über dem Boden bis zur vollständigen Hüftstreckung. Die Endposition wird durch das Gesäß erreicht, nicht durch Überstrecken des unteren Rückens.","breathing":"Beim Hochdrücken ausatmen, beim Absenken einatmen.","common_mistakes":["Unterer Rücken wird oben überstreckt, statt die Hüfte zu strecken.","Kopf kippt nach hinten, Blick geht an die Decke.","Füße stehen zu weit vorne, Belastung geht in die hinteren Oberschenkel.","Füße stehen zu nah am Gesäß, Quadrizeps übernimmt.","Bewegung wird mit Schwung ausgeführt, keine Pause oben."],"tips":["Blick während der gesamten Bewegung in Richtung Knie halten.","Oben ein bis zwei Sekunden halten und das Gesäß bewusst anspannen.","Gewichtsscheiben mit Stoppern gegen Verrutschen sichern und Bank gegen Wegrutschen fixieren.","Zu Beginn Technik ohne Zusatzgewicht oder nur mit der Stange üben."],"cable_setup":null,"muscle_focus":["Oberen Rücken unterhalb der Schulterblätter auf die Bankkante legen und die Füße so platzieren, dass die Unterschenkel oben senkrecht stehen; so trägt das Gesäß die Hauptlast.","Hüfte vollständig strecken und oben ein bis zwei Sekunden bewusst anspannen; das Gesäß arbeitet in der gestreckten Endposition am stärksten.","Rippen unten und Kinn leicht eingezogen halten, damit die Streckung aus der Hüfte und nicht aus der Lendenwirbelsäule kommt.","Absenken kontrolliert, bis die Hüfte knapp über dem Boden ist, ohne das Gewicht abzusetzen."],"requirements":["Stabile Bank, Höhe etwa Kniehöhe, gegen Wegrutschen gesichert","Langhantel mit Polster (Hip-Thrust-Pad) und Hantelscheiben mit Verschlüssen; alternativ Hip-Thrust-Maschine"],"grip_alternatives":[],"alternative_exercises":[],"animation_source_url":"https://modusx.de/fitness-uebungen/hip-thrust-langhantel/","variants":[]}$seed$::jsonb);

-- Kabel Kickback
select public.upsert_seed_exercise($seed${"slug":"kabel-kickback","name":"Kabel Kickback","category":"glutes","equipment":"cable","grip_id":"ankle_strap","grip_notes":"Fußschlaufe am Sprunggelenk des Arbeitsbeins befestigen, fest, aber nicht einschnürend. Hände stützen sich am Kabelturm ab. Alternativ eine gepolsterte Manschette nutzen, wenn vorhanden.","primary_muscles":["glutes"],"secondary_muscles":["hamstrings"],"description":"Einbeinige Hüftstreckung am unteren Kabelzug mit Fußschlaufe, bei der das Bein nach hinten-oben geführt wird. Gut geeignet als Isolationsübung für das Gesäß mit leichtem bis moderatem Gewicht.","setup":["Fußschlaufe am unteren Kabel einhängen und am Sprunggelenk des Arbeitsbeins befestigen.","Mit dem Gesicht zum Kabelturm stellen, Hände am Turm abstützen.","Oberkörper leicht nach vorne neigen, Rücken neutral, Rumpf anspannen.","Standbein leicht gebeugt, Gewicht auf der ganzen Fußsohle.","Arbeitsbein leicht vor dem Körper, Spannung im Kabel aufnehmen."],"execution":["Arbeitsbein kontrolliert nach hinten-oben führen, Knie bleibt fast gestreckt.","Bewegung kommt aus der Hüfte, Gesäß anspannen.","Becken bleibt stabil, unterer Rücken überstreckt nicht.","In der Endposition ein bis zwei Sekunden halten.","Bein langsam zurückführen, bis es leicht vor dem Körper ist.","Nach allen Wiederholungen die Seite wechseln."],"range_of_motion":"Vom leichten Vorschwung bis zur vollständigen Hüftstreckung. Die Höhe des Beins wird durch die stabile Beckenposition begrenzt, nicht durch Überstrecken des Rückens.","breathing":"Beim Führen des Beins nach hinten ausatmen, beim Zurückführen einatmen.","common_mistakes":["Unterer Rücken überstreckt, um das Bein höher zu bringen.","Bewegung wird mit Schwung aus dem Vorschwung ausgeführt.","Oberkörper dreht sich ein oder weicht zur Seite aus.","Knie des Arbeitsbeins beugt sich stark, Bewegung wird zum Beinbeugen.","Zu viel Gewicht, Bewegungsradius wird klein."],"tips":["Leichtes bis moderates Gewicht wählen und auf die Kontraktion im Gesäß konzentrieren.","Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Fußspitze des Arbeitsbeins leicht nach außen drehen, um das Gesäß stärker zu spüren.","Höhere Wiederholungszahlen (12 bis 20) sind bei dieser Übung sinnvoll."],"cable_setup":{"cable":"Kabelturm mit unterer Rolle, ein Kabel (eine Seite des Doppelkabelzugs)","height":"ganz unten, damit der Zug von vorne-unten kommt und das Gesäß über die gesamte Hüftstreckung belastet wird","grip_width":"Keine Griffarbeit, Fußschlaufe am Sprunggelenk; Hände stützen sich am Turm ab","body_position":"Stehend mit dem Gesicht zum Turm, Oberkörper leicht nach vorne geneigt, Rücken neutral, Rumpf angespannt, Hände am Turm","foot_position":"Standbein leicht gebeugt, Fuß flach auf dem Boden; Arbeitsbein mit Schlaufe leicht vor dem Körper","movement_direction":"Bein nach hinten-oben, in Verlängerung des Rumpfes","elbow_position":"Arme leicht gebeugt am Turm, dienen nur der Stabilisierung","end_position":"Bein hinter dem Körper, Hüfte vollständig gestreckt, Gesäß angespannt, Becken stabil","return":"Langsam und kontrolliert über etwa zwei Sekunden, bis das Bein leicht vor dem Körper ist, ohne dass das Gewicht aufsetzt"},"muscle_focus":["Arbeitsbein in der Startposition leicht vor dem Körper führen, damit das Gesäß in leichter Hüftbeugung, also in der gedehnten Position, unter Last steht.","Bewegung ausschließlich aus der Hüfte: Knie fast gestreckt und Becken stabil; die Endposition ist die volle Hüftstreckung, nicht ein möglichst hohes Bein.","Oberkörper leicht nach vorne geneigt und Rumpf angespannt; Überstrecken des unteren Rückens verlagert die Arbeit weg vom Gesäß.","Oben ein bis zwei Sekunden halten, Rückführung etwa zwei Sekunden kontrollieren."],"requirements":["Kabelturm mit unterer Rolle","Fußschlaufe (Ankle Strap) oder gepolsterte Manschette"],"grip_alternatives":[],"alternative_exercises":[],"image_url":"/exercises/cable-tower.jpg","machine_name":"Kabelturm (Multistation)","animation_source_url":"https://modusx.de/fitness-uebungen/po-kickbacks-kabel/","variants":[]}$seed$::jsonb);

-- Wadenheben
select public.upsert_seed_exercise($seed${"slug":"wadenheben-stehend","name":"Wadenheben","category":"calves","equipment":"machine","grip_id":null,"grip_notes":"Haltegriffe oder Schulterpolster der stehenden Wadenmaschine nutzen, Hände bleiben locker. Alternativ: Smith-Maschine mit Stange im Nacken oder Stufe mit Kurzhantel in einer Hand und Abstützen mit der anderen.","primary_muscles":["calves"],"secondary_muscles":[],"description":"Wadenheben als eine Übung mit zwei anatomisch begründeten Varianten: Stehend mit gestrecktem Knie trainiert den Gastrocnemius (die sichtbare Wade), sitzend mit gebeugtem Knie den darunter liegenden Soleus. Für vollständige Waden gehören beide ins Programm.","setup":["Schulterpolster so einstellen, dass die Beine im Stand fast gestreckt sind und das Gewicht leicht abhebt.","Fußballen auf die Kante der Plattform stellen, Fersen frei, Füße hüftbreit.","Knie fast gestreckt, aber nicht durchgedrückt.","Rumpf anspannen, Oberkörper aufrecht.","Fersen kontrolliert absenken, um die Startposition in der Dehnung einzunehmen."],"execution":["Fersen so hoch wie möglich anheben, auf die Fußballen drücken.","In der oberen Position ein bis zwei Sekunden halten.","Fersen langsam absenken, bis eine deutliche Dehnung in der Wade spürbar ist.","In der unteren Position kurz halten, ohne zu federn.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Volle Dehnung unten mit Fersen deutlich unter der Plattformkante bis zum höchsten Punkt auf den Fußballen. Der Kniewinkel bleibt während der gesamten Bewegung gleich.","breathing":"Beim Anheben der Fersen ausatmen, beim Absenken einatmen.","common_mistakes":["Bewegung wird federnd und mit Schwung aus der Dehnung ausgeführt.","Knie werden während der Bewegung gebeugt und gestreckt.","Bewegungsradius ist zu klein, keine Dehnung unten.","Füße rutschen auf der Plattform nach vorne.","Oberkörper kippt nach vorne oder hinten."],"tips":["Oben kurze Pause einlegen, unten die Dehnung ein bis zwei Sekunden halten.","Höhere Wiederholungszahlen (12 bis 20) mit vollem Bewegungsradius sind bei Waden in der Regel sinnvoll.","Einbeinige Ausführung, um Seitenunterschiede auszugleichen.","Ohne Maschine: Stufe mit Kurzhantel in einer Hand, andere Hand stützt sich ab."],"cable_setup":null,"muscle_focus":["Die gedehnte Position unten ist der wichtigste Teil: Fersen tief absenken und dort eine Sekunde halten, bevor es hochgeht.","Oben kurz auf die Zehenspitzen, nicht federn; das Springen aus der Achillessehne bringt dem Muskel nichts.","Stehend und sitzend trainieren unterschiedliche Muskeln, beide Varianten einplanen.","10 bis 20 Wiederholungen, 2 bis 3 Sekunden absenken, Waden vertragen hohe Frequenz."],"requirements":["Stehende Wadenmaschine mit Schulterpolstern; alternativ Multipresse mit Stufe oder Kurzhanteln in den Händen auf einer Stufe","Stufe oder Plattformkante, damit die Fersen frei absinken können"],"grip_alternatives":[],"image_url":"/exercises/standing-calf-raise.jpg","machine_name":"DHZ Standing Calf Raise, Plate Loaded","alternative_exercises":[],"animation_source_url":"https://modusx.de/fitness-uebungen/wadenheben-stehend/wadenheben-maschine-stehend/","variants":[{"name":"Stehend (Gastrocnemius)","description":"Knie gestreckt, Fersen tief absenken, bis die Wade deutlich dehnt, dann hoch auf die Zehenspitzen. An der Standmaschine oder mit Kurzhanteln auf einer Stufe.","source_url":"https://modusx.de/fitness-uebungen/wadenheben-stehend/wadenheben-maschine-stehend/"},{"name":"Sitzend (Soleus)","description":"Knie 90° gebeugt, Polster auf den Oberschenkeln. Der Gastrocnemius ist entspannt, der Soleus übernimmt.","source_url":"https://modusx.de/fitness-uebungen/wadenheben-sitzend/wadenheben-maschine-sitzend/"},{"name":"An der Hackenschmidt oder Beinpresse","description":"Fußballen auf der Plattenkante, Beine fast gestreckt. Ersetzt die Standmaschine bei gestrecktem Knie.","source_url":"https://modusx.de/fitness-uebungen/wadenheben-hackenschmidt-maschine/"}]}$seed$::jsonb);

-- Kurzhantel Kniebeuge (Goblet Squat)
select public.upsert_seed_exercise($seed${"slug":"kurzhantel-kniebeuge","name":"Kurzhantel Kniebeuge (Goblet Squat)","category":"quads","equipment":"dumbbell","grip_id":null,"grip_notes":null,"primary_muscles":["quads","glutes"],"secondary_muscles":["adductors","abs"],"description":"Kniebeuge mit einer Kurzhantel vor der Brust. Die Last vorne hält den Oberkörper aufrecht und erlaubt eine tiefe, saubere Beuge; die beste freie Kniebeuge zum Lernen und für das Aufwärmen.","setup":["Kurzhantel senkrecht mit beiden Händen unter der oberen Scheibe vor der Brust halten.","Füße etwas weiter als schulterbreit, Zehen leicht nach außen.","Ellenbogen zeigen nach unten, Brust raus, Rumpf fest."],"execution":["Hüfte und Knie gleichzeitig beugen, tief absitzen.","Knie in Richtung der Fußspitzen, Ellenbogen zwischen den Knien.","So tief, wie der Rücken gerade bleibt, ideal unter die Waagerechte.","Unten kurz halten, dann über den ganzen Fuß hochdrücken.","Oben nicht komplett strecken."],"range_of_motion":"So tief wie möglich mit geradem Rücken, Fersen bleiben am Boden.","breathing":"Beim Absenken (Dehnung) einatmen, beim Drücken oder Ziehen ausatmen.","common_mistakes":["Fersen heben sich ab.","Knie fallen nach innen.","Oberkörper kippt nach vorne.","Zu flach beugen."],"tips":["Hantel ist zu schwer, wenn die Ellenbogen nicht mehr unten bleiben.","10 bis 15 Wiederholungen.","Ideal vor schweren Beinübungen oder an Tagen ohne Rack."],"cable_setup":null,"muscle_focus":["Tiefe ist der Reiz: der Quadrizeps arbeitet unterhalb der Waagerechten in Dehnung.","Die Last vorne zwingt zur aufrechten Haltung, so bleibt der untere Rücken entlastet.","Kontrolliert absenken, unten eine Sekunde halten, kein Federn."],"requirements":["Eine Kurzhantel oder Kettlebell"],"grip_alternatives":[],"variants":[{"name":"Goblet (Standard)","description":"Hantel vor der Brust."},{"name":"Zwei Kurzhanteln seitlich","description":"Mehr Gewicht möglich, weniger Hilfe für die Haltung."}],"animation_source_url":"https://modusx.de/fitness-uebungen/kurzhantel-kniebeuge/","alternative_exercises":[]}$seed$::jsonb);

-- Kurzhantel Rumänisches Kreuzheben
select public.upsert_seed_exercise($seed${"slug":"kurzhantel-rumaenisches-kreuzheben","name":"Kurzhantel Rumänisches Kreuzheben","category":"hamstrings","equipment":"dumbbell","grip_id":null,"grip_notes":null,"primary_muscles":["hamstrings","glutes"],"secondary_muscles":["lower_back","forearms"],"description":"Hüftbeugen mit fast gestreckten Beinen und zwei Kurzhanteln. Die wichtigste Übung für die Beinbeuger in gedehnter Position; mit Kurzhanteln bleibt die Last nah am Körper und der Griff ist einfacher als mit der Langhantel.","setup":["Stehend, Füße hüftbreit, Hanteln vor den Oberschenkeln.","Knie leicht gebeugt und in diesem Winkel fixiert.","Schultern hinten, Rücken gerade, Blick nach vorne-unten."],"execution":["Hüfte nach hinten schieben, Oberkörper neigt sich, Hanteln gleiten eng an den Beinen nach unten.","Bis die Beinbeuger deutlich dehnen, meist etwa Mitte Schienbein.","Rücken bleibt gerade, Knie bleiben leicht gebeugt.","Mit der Hüfte nach vorne wieder aufrichten.","Oben Gesäß anspannen, nicht ins Hohlkreuz."],"range_of_motion":"So tief, wie der Rücken gerade bleibt und die Dehnung in den Beinbeugern spürbar ist.","breathing":"Beim Absenken (Dehnung) einatmen, beim Drücken oder Ziehen ausatmen.","common_mistakes":["Rücken rund werden lassen.","Knie stark beugen und daraus eine Kniebeuge machen.","Hanteln vom Körper weg führen.","Oben überstrecken."],"tips":["Griff hält? Sonst Zughilfen, der Griff darf nicht der limitierende Faktor sein.","8 bis 12 Wiederholungen, 3 Sekunden absenken.","Perfekte Ergänzung zum Beinbeuger an der Maschine."],"cable_setup":null,"muscle_focus":["Beinbeuger wachsen aus der gedehnten Position; die Tiefe kommt aus der Hüfte, nicht aus dem Rücken.","Hanteln eng am Bein halten, dann bleibt der Hebel klein und der Rücken sicher.","Langsame Exzentrik, unten eine Sekunde halten."],"requirements":["Zwei Kurzhanteln","Optional Zughilfen"],"grip_alternatives":[],"variants":[{"name":"Beidbeinig (Standard)","description":"Klassische Ausführung.","source_url":"https://modusx.de/fitness-uebungen/kurzhantel-kreuzheben/rumaenisches-kreuzheben-mit-kurzhanteln/"},{"name":"Einbeinig","description":"Mehr Gleichgewicht, stärkere Gesäßbeteiligung.","source_url":"https://modusx.de/fitness-uebungen/einbeiniges-kreuzheben/einbeiniges-kreuzheben-mit-kurzhanteln/"}],"animation_source_url":"https://modusx.de/fitness-uebungen/kurzhantel-kreuzheben/rumaenisches-kreuzheben-mit-kurzhanteln/","alternative_exercises":[]}$seed$::jsonb);

-- Incline Curl
select public.upsert_seed_exercise($seed${"slug":"incline-curl","name":"Incline Curl","category":"biceps","equipment":"dumbbell","grip_id":null,"grip_notes":"Supinierter Griff (Handflächen zeigen nach vorne bzw. oben), Kurzhanteln locker aber sicher umschließen. Handgelenke gerade halten, nicht einknicken.","primary_muscles":["biceps"],"secondary_muscles":["forearms"],"description":"Bizepscurl auf der Schrägbank, die Übung mit der stärksten Dehnung des langen Bizepskopfs. Je weiter die Arme hinter dem Körper hängen, desto größer die Dehnung: deshalb hier eine Übung mit zwei Positionen statt zwei Übungen.","setup":["Rückenlehne der Bank auf etwa 45 bis 60 Grad einstellen.","Kurzhanteln aufnehmen und sich mit dem Rücken vollständig an die Lehne setzen.","Kopf und oberer Rücken liegen an, Füße flach auf dem Boden.","Arme seitlich und leicht hinter der Körperlinie hängen lassen, Handflächen zeigen nach vorne.","Schultern nach hinten und unten ziehen, Oberarme ruhig halten."],"execution":["Kurzhanteln kontrolliert nach oben curlen, nur der Unterarm bewegt sich.","Oberarme bleiben während der gesamten Bewegung an ihrer Position.","In der oberen Position den Bizeps kurz bewusst anspannen.","Gewicht langsam absenken, bis die Arme fast gestreckt sind.","Am unteren Ende die Dehnung im Bizeps spüren, ohne die Ellenbogen hart durchzustrecken.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von fast gestreckten Armen in der gedehnten Position bis zur vollen Beugung, soweit die Oberarme an ihrer Position bleiben. Unten nicht in die Ellenbogen fallen lassen.","breathing":"Beim Curlen ausatmen, beim Absenken einatmen.","common_mistakes":["Oberarme wandern beim Curlen nach vorne, dadurch geht die Vordehnung verloren.","Schultern rollen nach vorne und lösen sich von der Lehne.","Gewicht wird unten fallen gelassen statt kontrolliert abgesenkt.","Handgelenke knicken beim Curlen nach innen ein.","Zu viel Gewicht, sodass der Oberkörper mitschwingt."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Eher leichteres Gewicht wählen als bei stehenden Curls, da die gedehnte Position mehr fordert.","Wenn die Schulter in der gedehnten Position unangenehm ist, Bank etwas steiler stellen."],"cable_setup":null,"muscle_focus":["Bizepsmuskel wächst nachweislich stärker, wenn er in gedehnter Position belastet wird; genau das macht die Schrägbank.","Oberarme während des Curls still halten, sonst geht die Dehnung verloren und die vordere Schulter übernimmt.","Unten vollständig strecken und kurz halten, oben supinieren (kleiner Finger nach außen drehen).","8 bis 15 Wiederholungen, langsam absenken, lieber leichter und sauber als schwer mit Schwung."],"requirements":["Verstellbare Schrägbank (45–60 Grad)","Kurzhanteln"],"grip_alternatives":[],"alternative_exercises":["kurzhantelcurl","scott-curl","konzentrationscurl"],"animation_source_url":"https://modusx.de/fitness-uebungen/kurzhantel-bizeps-curls-schraegbank/klassische-bizeps-curls-auf-der-schraegbank/","variants":[{"name":"Arme neben dem Körper, Bank 45 bis 60°","description":"Standard. Oberarme hängen senkrecht nach unten, nur der Unterarm bewegt sich.","source_url":"https://modusx.de/fitness-uebungen/kurzhantel-bizeps-curls-schraegbank/klassische-bizeps-curls-auf-der-schraegbank/"},{"name":"Arme hinter dem Körper, Bank 60 bis 75°","description":"Flachere Lehne, Oberarme leicht nach hinten. Maximale Dehnung des Bizeps, weniger Gewicht nötig.","source_url":"https://modusx.de/fitness-uebungen/kurzhantel-bizeps-curls-schraegbank/"}]}$seed$::jsonb);

-- Kabelcurl
select public.upsert_seed_exercise($seed${"slug":"kabelcurl","name":"Kabelcurl","category":"biceps","equipment":"cable","grip_id":"straight_bar","grip_notes":"Supinierter Griff an der geraden Stange, etwa schulterbreit. Alternativ: EZ-Stange, wenn die Handgelenke bei gerader Stange unangenehm belastet werden.","primary_muscles":["biceps"],"secondary_muscles":["forearms"],"description":"Bizepscurl am tiefen Block mit konstanter Spannung. Der Griff entscheidet über den Schwerpunkt: gerade Stange supiniert für den Bizeps, Seil im Hammergriff für Brachialis und Brachioradialis. Eine Übung, zwei Griffe.","setup":["Gerade Stange am unteren Kabel einhängen und Gewicht einstellen.","Stange mit supiniertem Griff etwa schulterbreit fassen.","Einen Schritt vom Turm zurücktreten, bis das Gewicht leicht angehoben ist.","Aufrecht stehen, Füße hüftbreit, Knie leicht gebeugt, Rumpf angespannt.","Ellenbogen seitlich am Körper, Schultern nach hinten und unten."],"execution":["Stange kontrolliert nach oben curlen, nur die Unterarme bewegen sich.","Ellenbogen bleiben am Körper und wandern nicht nach vorne oder hinten.","In der oberen Position kurz halten und den Bizeps anspannen.","Stange langsam absenken, bis die Arme fast gestreckt sind.","Unten Spannung halten, Gewicht nicht auf dem Stapel aufsetzen lassen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von fast gestreckten Armen bis zur vollen Beugung, soweit die Ellenbogen an ihrer Position bleiben. Oben nicht die Ellenbogen anheben, um die Stange höher zu bringen.","breathing":"Beim Curlen ausatmen, beim Absenken einatmen.","common_mistakes":["Oberkörper lehnt sich zurück und erzeugt Schwung aus der Hüfte.","Ellenbogen wandern nach vorne, um die Stange höher zu bringen.","Handgelenke knicken oben nach innen ein.","Gewicht fällt unten unkontrolliert zurück.","Schultern ziehen während des Curls nach oben."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Bei Beschwerden in den Handgelenken auf die EZ-Stange wechseln.","Wenn der Oberkörper mitschwingt, Gewicht reduzieren oder mit dem Rücken an eine Stütze stellen.","Erst Gewicht erhöhen, wenn alle Sätze ohne Schwung ausgeführt werden."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einzelnes Kabel","height":"ganz unten, damit das Kabel senkrecht nach unten zieht und der Bizeps auch bei fast gestreckten Armen unter Spannung steht","grip_width":"Schulterbreit, supiniert (Handflächen nach oben), an gerader Stange oder EZ-Stange","body_position":"Aufrecht stehend, etwa einen Schritt vom Turm entfernt, Rumpf angespannt, Oberkörper ruhig","foot_position":"Füße hüftbreit, parallel, Knie leicht gebeugt","movement_direction":"Von unten nach oben in Richtung Schultern, Unterarm rotiert um den Ellenbogen","elbow_position":"Ellenbogen seitlich am Körper, bleiben während der Bewegung an ihrer Position","end_position":"Stange etwa auf Höhe der oberen Brust, Unterarme vollständig gebeugt, Bizeps angespannt","return":"Langsam und kontrolliert bis fast zur vollen Streckung, Gewicht bleibt in der Luft"},"muscle_focus":["Das Kabel hält auch unten Spannung, deshalb die Arme ganz strecken und einen Schritt vom Turm weg stehen, dann ist der Bizeps unten gedehnt und unter Last.","Ellenbogen bleiben vor dem Körper fixiert, kein Mitziehen der Schulter.","Oben kurz anspannen, dann 2 bis 3 Sekunden absenken.","10 bis 15 Wiederholungen bis nahe ans Versagen."],"requirements":["Kabelturm mit verstellbarer Rolle","Gerade kurze Stange (alternativ SZ-Stange)"],"grip_alternatives":["ez_bar"],"alternative_exercises":["kurzhantelcurl","hammer-curl-kurzhantel","curls"],"image_url":"/exercises/cable-tower.jpg","machine_name":"Kabelturm (Multistation)","animation_source_url":"https://modusx.de/fitness-uebungen/cable-curls/","variants":[{"name":"Gerade Stange, supiniert (Standard)","description":"Untergriff schulterbreit, Ellenbogen am Körper. Voller Bizeps.","source_url":"https://modusx.de/fitness-uebungen/cable-curls/"},{"name":"Seil im Hammergriff","description":"Daumen nach oben, am Ende die Hände leicht auseinanderziehen. Schwerpunkt Brachialis und Unterarm.","source_url":"https://modusx.de/fitness-uebungen/cable-curls/kabelcurls-mit-stange-und-seil-am-tiefen-block/"},{"name":"Einarmig mit Einzelgriff","description":"Ein Arm, leicht nach vorne gelehnt. Ausgleich von Seitenunterschieden und mehr Dehnung unten."}]}$seed$::jsonb);

-- Kurzhantelcurl
select public.upsert_seed_exercise($seed${"slug":"kurzhantelcurl","name":"Kurzhantelcurl","category":"biceps","equipment":"dumbbell","grip_id":null,"grip_notes":"Supinierter Griff, Handflächen zeigen nach oben. Alternativ: Start mit neutraler Handstellung und Drehen der Hand während des Curls (Supination). Handgelenke gerade halten.","primary_muscles":["biceps"],"secondary_muscles":["forearms"],"description":"Klassischer Bizepscurl mit Kurzhanteln, stehend oder sitzend, beidarmig oder im Wechsel. Grundübung für den Bizeps mit freier Bewegung und ohne Gerätebindung.","setup":["Kurzhanteln aufnehmen und aufrecht stehen oder auf einer Bank mit aufrechter Lehne sitzen.","Füße hüftbreit, Knie leicht gebeugt, Rumpf angespannt.","Arme hängen gestreckt seitlich am Körper, Handflächen zeigen nach vorne.","Schultern nach hinten und unten ziehen, Brust leicht anheben.","Ellenbogen leicht vor der Körpermitte, nah am Rumpf."],"execution":["Kurzhanteln kontrolliert nach oben curlen, beidarmig oder im Wechsel.","Oberarme bleiben an ihrer Position, nur die Unterarme bewegen sich.","In der oberen Position den Bizeps kurz anspannen.","Gewicht langsam absenken, bis die Arme fast gestreckt sind.","Unten nicht in die Ellenbogen fallen lassen, Spannung halten.","Nächste Wiederholung ohne Schwung aus Hüfte oder Rücken beginnen."],"range_of_motion":"Von fast gestreckten Armen bis zur vollen Beugung, soweit die Oberarme an ihrer Position bleiben. Die Hantel muss oben nicht die Schulter berühren.","breathing":"Beim Curlen ausatmen, beim Absenken einatmen.","common_mistakes":["Oberkörper schwingt zurück, um das Gewicht in Bewegung zu bringen.","Ellenbogen wandern nach vorne, dadurch arbeitet die vordere Schulter mit.","Handgelenke knicken oben nach innen ein.","Gewicht wird unten fallen gelassen statt kontrolliert abgesenkt.","Im Wechsel wird der ruhende Arm vollständig entspannt."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Sitzende Ausführung reduziert Schwung aus dem Oberkörper.","Beim Curl im Wechsel den ruhenden Arm leicht gebeugt und unter Spannung halten.","Erst Gewicht erhöhen, wenn alle Sätze ohne Schwung ausgeführt werden."],"cable_setup":null,"muscle_focus":["Arme unten bis fast zur vollen Streckung bringen und die Dehnung im Bizeps zulassen; der untere Bereich der Bewegung trägt nach aktuellem Stand stark zum Muskelaufbau bei.","Oberarme nah am Rumpf und leicht vor der Körpermitte halten, nur der Unterarm bewegt sich; Ellenbogen, die nach vorne wandern, lassen die vordere Schulter übernehmen.","Handflächen beim Curlen vollständig nach oben drehen (Supination), oben kurz anspannen, ohne das Handgelenk einzuknicken.","Zwei Sekunden lang absenken, Oberkörper ruhig halten; wenn der Rumpf mitschwingt, ist das Gewicht zu schwer."],"requirements":["Kurzhanteln","Optional: Bank mit aufrechter Lehne für die sitzende Ausführung"],"grip_alternatives":[],"alternative_exercises":["incline-curl","hammer-curl-kurzhantel","konzentrationscurl"],"animation_source_url":"https://modusx.de/fitness-uebungen/kurzhantel-bizeps-curls-klassisch/kurzhantel-curls-stehend/","variants":[]}$seed$::jsonb);

-- Trizepsdrücken Kabel
select public.upsert_seed_exercise($seed${"slug":"trizepsdruecken-kabel","name":"Trizepsdrücken Kabel","category":"triceps","equipment":"cable","grip_id":"v_bar_triceps","grip_notes":"Neutraler Griff an der V-förmigen Trizepsstange, Handgelenke gerade. Alternativ: Seil oder gerade Stange, je nach Verfügbarkeit und Handgelenkskomfort.","primary_muscles":["triceps"],"secondary_muscles":[],"description":"Trizepsdrücken am hohen Block. Stange, Seil oder Einzelgriff ändern nur den Griff, nicht die Bewegung: Ellenbogen fixiert, Unterarme nach unten strecken. Deshalb eine Übung mit Griffvarianten.","setup":["V-förmige Trizepsstange am oberen Kabel einhängen und Gewicht einstellen.","Stange mit neutralem Griff fassen, Handgelenke gerade.","Einen kleinen Schritt vom Turm zurücktreten, Oberkörper leicht nach vorne neigen.","Füße hüftbreit oder in leichter Schrittstellung, Knie leicht gebeugt.","Ellenbogen seitlich am Körper fixieren, Schultern nach hinten und unten."],"execution":["Stange kontrolliert nach unten drücken, bis die Arme gestreckt sind.","Ellenbogen bleiben am Körper, nur die Unterarme bewegen sich.","In der unteren Position den Trizeps kurz anspannen.","Gewicht langsam zurückführen, bis die Unterarme etwa waagerecht oder etwas höher sind.","Oben Spannung halten, das Gewicht nicht auf dem Stapel aufsetzen lassen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer Beugung von etwa 90 Grad oder etwas mehr bis zur vollen Streckung. Die Ellenbogen bleiben dabei die gesamte Zeit an ihrer Position.","breathing":"Beim Drücken nach unten ausatmen, beim Zurückführen einatmen.","common_mistakes":["Ellenbogen wandern nach vorne oder außen, dadurch arbeitet die Schulter mit.","Oberkörper drückt mit und erzeugt Schwung von oben.","Gewicht fällt oben unkontrolliert zurück.","Handgelenke knicken unten ein.","Schultern ziehen nach oben."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Vorstellen, die Ellenbogen an die Rippen zu klemmen.","Wenn der Oberkörper mitdrückt, Gewicht reduzieren."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einzelnes Kabel","height":"ganz oben, damit das Kabel von oben in Verlängerung des Unterarms zieht und der Trizeps über den gesamten Bewegungsradius Widerstand hat","grip_width":"Neutral an der V-förmigen Trizepsstange, Hände eng beieinander","body_position":"Stehend, leichte Vorlage von etwa 10 bis 20 Grad, Rumpf angespannt, Oberkörper ruhig","foot_position":"Füße hüftbreit oder leichte Schrittstellung, Knie leicht gebeugt","movement_direction":"Von oben nach unten, Unterarm rotiert um den Ellenbogen","elbow_position":"Ellenbogen seitlich am Körper fixiert, bleiben während der Bewegung an ihrer Position","end_position":"Arme vollständig gestreckt, Stange etwa auf Höhe der Oberschenkel, Trizeps angespannt","return":"Langsam und kontrolliert, bis die Unterarme etwa waagerecht sind, Gewicht bleibt in der Luft"},"muscle_focus":["Ellenbogen am Körper fixieren und nur den Unterarm bewegen; wandert der Ellenbogen, übernimmt der Latissimus.","Unten vollständig strecken und eine Sekunde halten, oben die Unterarme über die Waagerechte zurückkommen lassen, damit der Trizeps gedehnt wird.","Für den langen Kopf (Masse des Trizeps) zusätzlich die Überkopf-Extension einplanen, hier arbeitet er in Dehnung.","10 bis 15 Wiederholungen, kontrollierte Rückführung, Griffe im Wechsel über die Wochen."],"requirements":["Kabelturm mit verstellbarer Rolle","Trizeps-V-Stange (alternativ gerade kurze Stange)"],"grip_alternatives":["straight_bar"],"alternative_exercises":["ueberkopf-trizeps-extension","kurzhantel-trizepsdruecken-ueber-kopf","trizeps-kickbacks","dips"],"image_url":"/exercises/cable-tower.jpg","machine_name":"Kabelturm (Multistation)","animation_source_url":"https://modusx.de/fitness-uebungen/trizepsdruecken-kabelzug/trizeps-pushdowns-am-kabel/","variants":[{"name":"Gerade Stange oder V-Stange (Standard)","description":"Obergriff schulterbreit, Stange bis zur vollen Streckung drücken. Höchste Lasten möglich.","source_url":"https://modusx.de/fitness-uebungen/trizepsdruecken-kabelzug/trizeps-pushdowns-am-kabel/"},{"name":"Seil","description":"Hände am Ende der Bewegung auseinanderziehen und Handrücken nach außen drehen. Betont den seitlichen Kopf, mehr Bewegungsfreiheit für die Handgelenke.","source_url":"https://modusx.de/fitness-uebungen/trizepsdruecken-kabelzug/"},{"name":"Einarmig im Untergriff","description":"Einzelgriff, Handfläche nach oben. Isoliert den inneren Kopf, gut für Seitenunterschiede."},{"name":"Einarmig im Obergriff","description":"Einzelgriff, Handfläche nach unten, Ellenbogen fest am Körper."}]}$seed$::jsonb);

-- Überkopf Trizeps Extension
select public.upsert_seed_exercise($seed${"slug":"ueberkopf-trizeps-extension","name":"Überkopf Trizeps Extension","category":"triceps","equipment":"cable","grip_id":"straight_bar","grip_notes":"Gerade kurze Stange etwa schulterbreit mit proniertem Griff fassen, Handgelenke gerade. Alternativ SZ-Stange, wenn die Handgelenke bei gerader Stange unangenehm belastet werden, oder Seil.","primary_muscles":["triceps"],"secondary_muscles":[],"description":"Trizepsstreckung über dem Kopf am Kabelzug mit gerader Stange, bei der die Oberarme neben dem Kopf gehalten werden. Durch die gestreckte Schulterposition wird vor allem der lange Trizepskopf belastet.","setup":["Gerade Stange am Kabel einhängen und Rolle ganz unten einstellen.","Stange fassen, sich mit dem Rücken zum Turm drehen und in Schrittstellung gehen.","Stange hinter den Kopf absenken, Hände schulterbreit, Ellenbogen zeigen nach vorne-oben.","Oberkörper leicht nach vorne neigen, Rumpf anspannen, Rücken gerade.","Oberarme neben dem Kopf ruhig halten, Schultern nach unten ziehen."],"execution":["Arme kontrolliert nach vorne-oben strecken, Oberarme bleiben an ihrer Position.","Nur die Unterarme bewegen sich, Ellenbogen zeigen weiter nach vorne-oben.","In der gestreckten Position den Trizeps kurz anspannen.","Stange langsam hinter den Kopf absenken und die Dehnung im Trizeps zulassen.","Hinten stoppen, wenn die Unterarme etwa parallel zum Oberarm sind.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer vollständigen Beugung mit gedehntem Trizeps hinter dem Kopf bis zur vollen Streckung nach vorne-oben. Die Oberarme bleiben dabei neben dem Kopf.","breathing":"Beim Strecken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Ellenbogen weichen seitlich nach außen aus.","Oberarme wandern beim Strecken nach unten, dadurch wird die Bewegung zum Drücken.","Unterer Rücken fällt ins Hohlkreuz, Rumpfspannung fehlt.","Gewicht fällt hinten unkontrolliert zurück.","Zu viel Gewicht, der Bewegungsradius hinten wird verkürzt."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren und die Dehnung bewusst zulassen.","Eher leichteres Gewicht wählen, die gedehnte Position des langen Kopfes ist anspruchsvoll.","Bauch anspannen, um ein Hohlkreuz zu vermeiden.","Bei Beschwerden in der Schulter die Rolle etwas höher einstellen."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einzelnes Kabel","height":"ganz unten, damit das Kabel von unten-hinten zieht und der lange Trizepskopf hinter dem Kopf in der gedehnten Position unter Spannung steht; bei Schulterbeschwerden Hüfthöhe","grip_width":"Gerade Stange, schulterbreit, pronierter Griff, Handgelenke gerade","body_position":"Mit dem Rücken zum Turm stehend, Oberkörper leicht nach vorne geneigt, Rumpf angespannt, Rücken gerade","foot_position":"Schrittstellung, vorderes Bein leicht gebeugt, hinteres Bein gestreckt für Stabilität","movement_direction":"Von hinter dem Kopf nach vorne-oben, Unterarm rotiert um den Ellenbogen","elbow_position":"Ellenbogen neben dem Kopf, zeigen nach vorne-oben, bleiben an ihrer Position","end_position":"Arme vollständig gestreckt nach vorne-oben, Trizeps angespannt, Oberarme weiter neben dem Kopf","return":"Langsam und kontrolliert, bis die Unterarme hinter dem Kopf etwa parallel zu den Oberarmen sind"},"muscle_focus":["Oberarme neben dem Kopf nach oben gestreckt halten, so wird der lange Trizepskopf über die Schulter vorgedehnt; genau diese gedehnte Position macht die Übung wirksam.","Stange hinter dem Kopf absenken, bis die Unterarme etwa parallel zu den Oberarmen sind, und die Dehnung zwei bis drei Sekunden lang kontrolliert zulassen.","Ellenbogen nach vorne-oben gerichtet lassen und nicht nach außen ausweichen; sinken die Oberarme beim Strecken ab, wird aus der Übung ein Drücken.","Rumpf anspannen, kein Hohlkreuz, und ein eher leichtes Gewicht wählen, damit der Trizeps und nicht der untere Rücken limitiert."],"requirements":["Kabelturm mit verstellbarer Rolle","Gerade kurze Stange (alternativ SZ-Stange oder Seil)"],"grip_alternatives":["ez_bar","rope"],"alternative_exercises":["trizepsdruecken-kabel","kurzhantel-trizepsdruecken-ueber-kopf"],"image_url":"/exercises/cable-tower.jpg","machine_name":"Kabelturm (Multistation)","animation_source_url":"https://modusx.de/fitness-uebungen/trizepsdruecken-kabelzug/trizepsdruecken-ueber-kopf-am-kabelzug/","variants":[]}$seed$::jsonb);

-- Crunch
select public.upsert_seed_exercise($seed${"slug":"crunch-maschine","name":"Crunch","category":"abs","equipment":"machine","grip_id":null,"grip_notes":"Griffe oder Polster je nach Maschine locker halten, nicht mit den Armen ziehen. Bei Brustpolster die Arme nur zur Fixierung auflegen.","primary_muscles":["abs"],"secondary_muscles":["obliques"],"description":"Belasteter Crunch für den geraden Bauchmuskel. An der Crunch-Maschine sitzend oder kniend am Seil des Kabelturms: beide Varianten rollen die Wirbelsäule gegen Widerstand ein, nur die Haltung unterscheidet sich.","setup":["Sitz so einstellen, dass die Drehachse der Maschine etwa auf Höhe des unteren Brustkorbs liegt.","Füße unter die Fußpolster bringen oder flach auf den Boden stellen.","Griffe oder Brustpolster locker fassen bzw. anlegen.","Rücken an das Polster lehnen, Schultern locker.","Leichtes Gewicht wählen, bis der Bewegungsablauf sicher sitzt."],"execution":["Oberkörper kontrolliert nach vorne einrollen, Bewegung aus der Brustwirbelsäule.","Brustbein in Richtung Becken ziehen, der Rücken wird dabei rund.","In der Endposition den Bauch kurz bewusst anspannen.","Gewicht langsam zurückführen, ohne den Rücken ins Hohlkreuz zu bringen.","Oben stoppen, bevor das Gewicht auf dem Stapel aufsetzt.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer leicht gestreckten Ausgangsposition bis zum vollständig eingerollten Oberkörper. Die Bewegung kommt aus der Brustwirbelsäule, nicht aus der Hüfte.","breathing":"Beim Einrollen ausatmen, beim Zurückführen einatmen.","common_mistakes":["Bewegung kommt aus der Hüfte statt aus der Wirbelsäule, die Hüftbeuger arbeiten statt des Bauchs.","Mit den Armen an den Griffen gezogen statt mit dem Bauch eingerollt.","Gewicht fällt oben unkontrolliert zurück.","Zu viel Gewicht, der Bewegungsradius wird klein.","Luft wird während der Bewegung angehalten."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Beim Einrollen bewusst ausatmen, das unterstützt die Anspannung des Bauchs.","Lieber leichtes Gewicht mit vollem Bewegungsradius als schweres Gewicht mit kurzer Bewegung.","Vorstellen, die Rippen in Richtung Becken zu ziehen."],"cable_setup":null,"muscle_focus":["Bauchmuskeln wachsen wie jeder Muskel durch progressiv steigende Last, deshalb mit Gewicht und 8 bis 15 Wiederholungen statt hunderter Wiederholungen ohne Widerstand.","Einrollen statt Beugen aus der Hüfte: der Abstand zwischen Brustbein und Becken verkürzt sich.","Oben vollständig aufrichten und die Bauchmuskeln in Dehnung bringen, bevor die nächste Wiederholung beginnt.","Ausatmen beim Einrollen, langsam zurück."],"requirements":["Bauchmaschine (Crunch-Maschine) mit Gewichtsstapel und verstellbarem Sitz"],"grip_alternatives":[],"image_url":"/exercises/abdominal-machine.jpg","machine_name":"DHZ Abdominal Isolator, Steckgewicht","alternative_exercises":["hanging-knee-raise","sit-ups"],"animation_source_url":"https://modusx.de/fitness-uebungen/crunches-an-crunch-maschine/","variants":[{"name":"Crunch-Maschine sitzend (Standard)","description":"Polster an der Brust oder Griffe hinter dem Kopf, Oberkörper einrollen, Becken bleibt fest im Sitz.","source_url":"https://modusx.de/fitness-uebungen/crunches-an-crunch-maschine/"},{"name":"Cable Crunch kniend am Seil","description":"Seil hinter dem Kopf halten, Hüfte ruhig, Ellenbogen Richtung Oberschenkel einrollen.","source_url":"https://modusx.de/fitness-uebungen/cable-crunches/crunch-kniend-am-seil/"}]}$seed$::jsonb);

-- Hanging Knee Raise
select public.upsert_seed_exercise($seed${"slug":"hanging-knee-raise","name":"Hanging Knee Raise","category":"abs","equipment":"bodyweight","grip_id":null,"grip_notes":"Pronierter oder neutraler Griff an der Klimmzugstange, etwa schulterbreit. Alternativ: Armschlaufen, wenn die Griffkraft vor dem Bauch ermüdet.","primary_muscles":["abs"],"secondary_muscles":["obliques","forearms"],"description":"Hängendes Anziehen der Knie an der Klimmzugstange oder in Armschlaufen, bei dem das Becken leicht eingerollt wird. Bauchübung mit dem eigenen Körpergewicht, die zusätzlich die Griffkraft fordert.","setup":["Klimmzugstange etwa schulterbreit fassen oder Oberarme in Armschlaufen einhängen.","Frei hängen, Beine gestreckt oder leicht gebeugt, Füße ohne Bodenkontakt.","Schultern aktiv nach unten ziehen, nicht passiv in den Gelenken hängen.","Rumpf anspannen und den Körper zur Ruhe bringen, bevor die Bewegung beginnt."],"execution":["Knie kontrolliert in Richtung Brust anziehen.","Am Ende der Bewegung das Becken leicht einrollen, der untere Rücken rundet sich dabei etwas.","In der oberen Position den Bauch kurz bewusst anspannen.","Beine langsam absenken, bis die Ausgangsposition erreicht ist.","Unten kurz zur Ruhe kommen, damit kein Schwung entsteht.","Nächste Wiederholung aus dem Stand heraus beginnen."],"range_of_motion":"Von gestreckt hängenden Beinen bis zu angezogenen Knien mit leicht eingerolltem Becken. Die Knie müssen nicht die Brust berühren, das Einrollen des Beckens ist entscheidend.","breathing":"Beim Anziehen der Knie ausatmen, beim Absenken einatmen.","common_mistakes":["Körper schwingt vor und zurück, die Bewegung kommt aus dem Schwung.","Becken wird nicht eingerollt, nur die Hüftbeuger heben die Beine.","Beine fallen unkontrolliert nach unten.","Schultern hängen passiv in den Gelenken.","Zu schnelles Tempo, das Einrollen des Beckens wird übersprungen."],"tips":["Jede Wiederholung erst beginnen, wenn der Körper ruhig hängt.","Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Als Progression die Beine zunehmend gestreckt halten oder die Bewegung langsamer ausführen.","Wenn die Griffkraft vor dem Bauch ermüdet, Armschlaufen verwenden."],"cable_setup":null,"muscle_focus":["Entscheidend ist das Einrollen des Beckens am Ende der Bewegung; reines Anheben der Beine kommt überwiegend aus den Hüftbeugern.","Beine unten fast gestreckt hängen lassen, sodass die Bauchmuskulatur in der gedehnten Position arbeitet, und jede Wiederholung aus dem ruhigen Hang starten.","Schultern aktiv nach unten ziehen und den Rumpf anspannen, damit kein Schwung entsteht.","Zwei Sekunden lang absenken; wenn die Griffkraft vor dem Bauch ermüdet, Armschlaufen verwenden."],"requirements":["Klimmzugstange oder Armschlaufen (Ab Straps) an einem stabilen Gestell"],"grip_alternatives":[],"image_url":"/exercises/knee-raise-station.jpg","machine_name":"DHZ Vertical Knee Raise Station","alternative_exercises":["crunch-maschine","sit-ups"],"bodyweight_factor":0.45,"animation_source_url":"https://modusx.de/fitness-uebungen/beinheben-haengend/beinheben-haengend-fuer-die-geraden-bauchmuskeln/","variants":[]}$seed$::jsonb);

-- Plank
select public.upsert_seed_exercise($seed${"slug":"plank","name":"Plank","category":"abs","equipment":"bodyweight","grip_id":null,"grip_notes":"Unterarme flach auf dem Boden, Hände locker geöffnet oder zu Fäusten geschlossen. Ellenbogen etwa unter den Schultern.","primary_muscles":["abs"],"secondary_muscles":["obliques","glutes"],"description":"Isometrischer Unterarmstütz, bei dem der Körper in einer geraden Linie gehalten wird. Grundübung für die Rumpfstabilität, die über die Haltedauer statt über Wiederholungen gesteuert wird.","setup":["Unterarme flach auf den Boden legen, Ellenbogen etwa unter den Schultern.","Beine nach hinten strecken, Füße etwa hüftbreit auf den Zehenspitzen.","Körper in eine gerade Linie von Kopf bis Fersen bringen.","Blick auf den Boden richten, Nacken in Verlängerung der Wirbelsäule.","Bauch und Gesäß anspannen, Becken leicht nach hinten kippen."],"execution":["Position halten, Rumpfspannung über die gesamte Dauer aufrechterhalten.","Becken bleibt in neutraler Position, weder abgesenkt noch angehoben.","Gleichmäßig weiteratmen, ohne die Spannung zu verlieren.","Schultern aktiv vom Boden wegdrücken, oberer Rücken bleibt stabil.","Halten, solange die gerade Linie sauber gehalten werden kann.","Kontrolliert ablegen, wenn die Position nicht mehr gehalten werden kann."],"range_of_motion":"Keine Bewegung, die Position wird statisch gehalten. Entscheidend ist die gerade Körperlinie ohne Absinken der Hüfte.","breathing":"Gleichmäßig und ruhig weiteratmen, die Luft nicht anhalten. Bei jeder Ausatmung die Bauchspannung bewusst beibehalten.","common_mistakes":["Hüfte sinkt ab, der untere Rücken fällt ins Hohlkreuz.","Gesäß wird zu hoch gehoben, der Körper bildet ein Dreieck.","Kopf hängt nach unten oder wird in den Nacken gelegt.","Luft wird angehalten.","Schultern sacken zwischen den Schulterblättern ein."],"tips":["Haltedauer in Sekunden kann als Wiederholungszahl eingetragen werden, zum Beispiel 45 für 45 Sekunden.","Lieber kürzere Haltezeiten mit sauberer Linie als lange Haltezeiten mit abgesenkter Hüfte.","Als Progression die Haltedauer schrittweise verlängern oder die Füße enger stellen.","Gesäß bewusst anspannen, das stabilisiert das Becken."],"cable_setup":null,"muscle_focus":["Becken leicht nach hinten kippen und Gesäß anspannen; so arbeitet die Bauchmuskulatur gegen das Hohlkreuz und hält die Spannung.","Ellenbogen unter den Schultern und aktiv in den Boden drücken, damit der obere Rücken nicht einsackt.","Gerade Linie von Kopf bis Fersen halten, ohne das Gesäß anzuheben; ruhig weiteratmen und die Spannung bei jeder Ausatmung beibehalten.","Lieber kürzer und sauber halten als lange mit abgesenkter Hüfte."],"requirements":["Matte oder weicher Untergrund für die Unterarme"],"grip_alternatives":[],"alternative_exercises":[],"bodyweight_factor":0.65,"variants":[]}$seed$::jsonb);

-- Bizepscurl Maschine
select public.upsert_seed_exercise($seed${"slug":"curls","name":"Bizepscurl Maschine","category":"biceps","equipment":"machine","grip_id":null,"grip_notes":"Supinierter Griff (Handflächen nach oben) an den Griffen der Maschine, Handgelenke gerade.","primary_muscles":["biceps"],"secondary_muscles":["forearms"],"description":"Geführte Curl-Bewegung an der Bizepsmaschine mit Armpolster. Die feste Führung isoliert den Bizeps und verhindert Schwung aus dem Oberkörper.","setup":["Sitz so einstellen, dass die Achseln oben auf dem Armpolster aufliegen.","Oberarme vollständig auf dem Polster ablegen, Ellenbogen auf Höhe der Drehachse.","Griffe im Untergriff fassen, Handgelenke gerade.","Rücken aufrecht, Brust leicht raus, Füße flach auf dem Boden."],"execution":["Griffe kontrolliert nach oben curlen, Oberarme bleiben auf dem Polster.","Oben kurz anspannen, ohne die Ellenbogen vom Polster zu heben.","Gewicht langsam zurückführen, bis die Arme fast gestreckt sind.","Unten die Spannung halten, Gewicht nicht aufsetzen.","Nächste Wiederholung ohne Ruck beginnen."],"range_of_motion":"Fast gestreckte Arme unten bis zur vollen Beugung oben; die Ellenbogen bleiben dabei immer auf dem Polster.","breathing":"Beim Curlen ausatmen, beim Zurückführen einatmen.","common_mistakes":["Ellenbogen vom Polster heben.","Mit dem Oberkörper nachhelfen.","Handgelenke abknicken.","Unten das Gewicht aufsetzen und Spannung verlieren."],"tips":["Langsame Negative, etwa drei Sekunden.","Eher 10 bis 15 Wiederholungen, die Maschine verzeiht wenig Schwung.","Sitzhöhe bei jedem Training gleich einstellen."],"cable_setup":null,"muscle_focus":["Oberarme fest auf dem Polster lassen, dann arbeitet nur der Ellenbogen und der Bizeps trägt die ganze Last.","Oben eine Sekunde halten und bewusst anspannen.","Unten fast strecken, damit der Bizeps unter Dehnung arbeitet."],"requirements":["Bizepscurl-Maschine mit Armpolster","Optional Trainingshandschuhe bei glatten Griffen"],"grip_alternatives":[],"animation_source_url":"https://modusx.de/fitness-uebungen/bizepsmaschine-bizeps-curls/klassische-curls-an-der-bizepsmaschine/","variants":[],"alternative_exercises":[]}$seed$::jsonb);

-- Hammercurl Kurzhantel
select public.upsert_seed_exercise($seed${"slug":"hammer-curl-kurzhantel","name":"Hammercurl Kurzhantel","category":"biceps","equipment":"dumbbell","grip_id":null,"grip_notes":"Neutraler Griff (Daumen nach oben) über die gesamte Bewegung, Handgelenke gerade.","primary_muscles":["biceps"],"secondary_muscles":["forearms"],"description":"Curl mit neutralem Griff im Stehen oder Sitzen. Der Hammergriff belastet neben dem Bizeps stark den Brachialis und die Unterarme und sorgt für dickere Oberarme.","setup":["Zwei Kurzhanteln im neutralen Griff an den Seiten halten.","Stand hüftbreit, Knie leicht gebeugt, Rumpf angespannt.","Schultern hinten und tief, Ellenbogen nah am Körper.","Blick geradeaus, Brust leicht raus."],"execution":["Eine oder beide Hanteln kontrolliert nach oben curlen, Daumen zeigen nach oben.","Ellenbogen bleiben am Körper, Oberarme bewegen sich nicht.","Oben kurz anspannen, Hantel nicht an die Schulter legen.","Langsam zurückführen, bis der Arm fast gestreckt ist.","Wechselnd oder beidarmig, ohne Schwung aus dem Rücken."],"range_of_motion":"Von fast gestrecktem Arm bis zur vollen Beugung; die Oberarme bleiben senkrecht und still.","breathing":"Beim Curlen ausatmen, beim Senken einatmen.","common_mistakes":["Ellenbogen nach vorne wandern lassen.","Schwung aus Hüfte und Rücken holen.","Handgelenke eindrehen oder abknicken.","Zu schwere Hanteln, dadurch halbe Bewegungen."],"tips":["Alternierend ausführen, dann bleibt die Technik sauberer.","Zwei bis drei Sekunden absenken.","Als letzte Bizepsübung im Training einplanen."],"cable_setup":null,"muscle_focus":["Neutraler Griff verlagert Last auf Brachialis und Brachioradialis, deshalb Handgelenke nicht eindrehen.","Ellenbogen am Körper fixieren, sonst übernimmt die vordere Schulter.","Volle Streckung unten für die Dehnung, kontrolliert ohne Federn."],"requirements":["Zwei Kurzhanteln","Optional eine Bank mit Rückenlehne für die sitzende Variante"],"grip_alternatives":[],"animation_source_url":"https://modusx.de/fitness-uebungen/hammer-curls/hammer-curls-mit-kurzhanteln-stehend/","variants":[],"alternative_exercises":[]}$seed$::jsonb);

-- Sit-ups
select public.upsert_seed_exercise($seed${"slug":"sit-ups","name":"Sit-ups","category":"abs","equipment":"bodyweight","grip_id":null,"grip_notes":"Hände locker an den Schläfen oder vor der Brust gekreuzt, nicht hinter dem Kopf ziehen.","primary_muscles":["abs"],"secondary_muscles":["obliques"],"description":"Klassische Rumpfbeuge aus der Rückenlage bis zum Sitzen. Beansprucht die geraden Bauchmuskeln über den vollen Bewegungsweg, mit Beteiligung der Hüftbeuger.","setup":["Auf den Rücken legen, Knie etwa 90 Grad gebeugt, Füße flach auf dem Boden.","Füße bei Bedarf unter einer Hantel oder Bank fixieren.","Hände an die Schläfen oder vor die Brust.","Unteren Rücken in den Boden drücken, Bauch anspannen."],"execution":["Kinn leicht zur Brust, Schultern vom Boden lösen.","Wirbel für Wirbel aufrollen, bis der Oberkörper fast senkrecht ist.","Oben kurz anspannen, nicht nach vorne fallen lassen.","Kontrolliert und langsam wieder abrollen.","Schultern kurz über dem Boden stoppen und die nächste Wiederholung beginnen."],"range_of_motion":"Vom Boden bis zum fast aufrechten Sitz; unten die Schultern nicht ganz ablegen, damit die Spannung bleibt.","breathing":"Beim Aufrollen ausatmen, beim Abrollen einatmen.","common_mistakes":["Mit den Armen am Kopf ziehen.","Schwung aus den Armen oder Beinen holen.","Rücken durchdrücken statt einrollen.","Zu schnell und ohne Kontrolle abrollen."],"tips":["Für mehr Widerstand eine Hantelscheibe vor der Brust halten.","Langsame Negative von drei Sekunden.","Bei Nackenbeschwerden lieber Crunches oder Cable Crunches wählen."],"cable_setup":null,"muscle_focus":["Einrollen statt Hochklappen, dann arbeitet der gerade Bauchmuskel und nicht nur die Hüftbeuger.","Ausatmen und den Bauchnabel zur Wirbelsäule ziehen.","Unten nicht ablegen, die Spannung bleibt über die ganze Serie erhalten."],"requirements":["Matte oder Bauchbank","Optional Fixierung für die Füße oder eine Hantelscheibe als Zusatzgewicht"],"grip_alternatives":[],"bodyweight_factor":0.5,"animation_source_url":"https://modusx.de/fitness-uebungen/sit-ups/","variants":[],"alternative_exercises":[]}$seed$::jsonb);

-- Kurzhantel Trizepsdrücken über Kopf
select public.upsert_seed_exercise($seed${"slug":"kurzhantel-trizepsdruecken-ueber-kopf","name":"Kurzhantel Trizepsdrücken über Kopf","category":"triceps","equipment":"dumbbell","grip_id":null,"grip_notes":null,"primary_muscles":["triceps"],"secondary_muscles":[],"description":"Trizepsextension über Kopf mit einer Kurzhantel. Belastet den langen Trizepskopf in maximaler Dehnung, den Teil, der die meiste Masse ausmacht und bei Pushdowns zu kurz kommt.","setup":["Sitzend oder stehend, Kurzhantel mit beiden Händen unter der oberen Scheibe greifen.","Hantel über den Kopf strecken, Oberarme eng neben den Ohren.","Rumpf fest, kein Hohlkreuz."],"execution":["Hantel hinter dem Kopf absenken, Ellenbogen bleiben oben und eng.","So tief, bis der Trizeps deutlich dehnt.","Kurz halten, dann nach oben strecken.","Oben fast strecken, Spannung halten.","Ellenbogen nicht nach außen fallen lassen."],"range_of_motion":"Von der vollen Dehnung hinter dem Kopf bis kurz vor die Streckung.","breathing":"Beim Absenken einatmen, beim Strecken ausatmen.","common_mistakes":["Ellenbogen nach außen fallen lassen.","Oberarme nach vorne kippen.","Hohlkreuz, um das Gewicht zu bewegen.","Zu kurzer Weg hinter dem Kopf."],"tips":["Mittleres Gewicht, 10 bis 15 Wiederholungen.","Sitzend mit Lehne ist der Rücken geschützt.","Mit Pushdowns kombinieren, dann sind alle drei Köpfe abgedeckt."],"cable_setup":null,"muscle_focus":["Der lange Kopf wird nur über Kopf richtig gedehnt; genau deshalb ist diese Übung für den Trizeps so wirksam.","Ellenbogen eng und oben halten, dann bleibt die Last auf dem Trizeps.","2 bis 3 Sekunden absenken, unten kurz halten."],"requirements":["Eine Kurzhantel","Optional Bank mit Lehne"],"grip_alternatives":[],"variants":[{"name":"Beidarmig mit einer Hantel (Standard)","description":"Stabil, höchste Last.","source_url":"https://modusx.de/fitness-uebungen/trizepsdruecken-kurzhanteln/kurzhantel-trizepsdruecken-mit-beiden-armen/"},{"name":"Einarmig","description":"Freie Hand stützt den Ellenbogen, gleicht Seitenunterschiede aus.","source_url":"https://modusx.de/fitness-uebungen/trizepsdruecken-kurzhanteln/einarmiges-trizepsdruecken-mit-der-kurzhantel/"}],"animation_source_url":"https://modusx.de/fitness-uebungen/trizepsdruecken-kurzhanteln/","alternative_exercises":[]}$seed$::jsonb);

-- Trizeps Kickbacks
select public.upsert_seed_exercise($seed${"slug":"trizeps-kickbacks","name":"Trizeps Kickbacks","category":"triceps","equipment":"dumbbell","grip_id":null,"grip_notes":null,"primary_muscles":["triceps"],"secondary_muscles":["rear_delts"],"description":"Trizepsstrecken im vorgebeugten Stand oder mit Stütze auf der Bank. Belastet den Trizeps in der verkürzten Position am stärksten, die Ergänzung zur Überkopf-Extension.","setup":["Vorgebeugt mit Stütze auf der Bank oder beidarmig im Stand, Rücken gerade.","Oberarm parallel zum Boden, Ellenbogen 90 Grad gebeugt.","Hantel hängt unter dem Ellenbogen."],"execution":["Unterarm nach hinten strecken, bis der Arm gerade ist.","Oben eine Sekunde anspannen.","Kontrolliert zurück auf 90 Grad.","Oberarm bleibt die ganze Zeit still und parallel zum Boden.","Kein Schwung aus der Schulter."],"range_of_motion":"Von 90 Grad Beugung bis zur vollen Streckung.","breathing":"Beim Strecken ausatmen, beim Beugen einatmen.","common_mistakes":["Oberarm absinken lassen.","Zu schwer, dadurch Schwung.","Oben nicht voll strecken.","Rücken rund."],"tips":["Leichte Hanteln, 12 bis 20 Wiederholungen.","Am Ende des Trizepstrainings.","Mit Kabel ausgeführt bleibt die Spannung über den ganzen Weg."],"cable_setup":null,"muscle_focus":["Die Spannung ist oben in der Streckung am größten, dort eine Sekunde halten.","Oberarm leicht über die Waagerechte heben, dann ist der Weg oben länger.","Langsam zurück, die Hantel nicht fallen lassen."],"requirements":["Leichte Kurzhanteln","Optional Flachbank"],"grip_alternatives":[],"variants":[{"name":"Einarmig mit Stütze (Standard)","description":"Stabiler Oberkörper.","source_url":"https://modusx.de/fitness-uebungen/trizeps-kickbacks-kurzhanteln/kickbacks-mit-einer-kurzhantel/"},{"name":"Beidarmig im Stand","description":"Zeitsparend, braucht Rumpfspannung.","source_url":"https://modusx.de/fitness-uebungen/trizeps-kickbacks-kurzhanteln/kickbacks-mit-zwei-kurzhanteln/"}],"animation_source_url":"https://modusx.de/fitness-uebungen/trizeps-kickbacks-kurzhanteln/","alternative_exercises":[]}$seed$::jsonb);

-- Konzentrationscurl
select public.upsert_seed_exercise($seed${"slug":"konzentrationscurl","name":"Konzentrationscurl","category":"biceps","equipment":"dumbbell","grip_id":null,"grip_notes":null,"primary_muscles":["biceps"],"secondary_muscles":["forearms"],"description":"Einarmiger Curl sitzend mit dem Ellenbogen an der Oberschenkelinnenseite. Vollständige Isolation ohne Schwung, mit Spitzenkontraktion oben; ideal als letzte Bizepsübung.","setup":["Auf der Bankkante sitzen, Beine weit auseinander.","Ellenbogen an die Innenseite des Oberschenkels stützen, Arm hängt gestreckt.","Freie Hand auf dem anderen Knie, Oberkörper leicht nach vorne."],"execution":["Hantel zur Schulter curlen, Ellenbogen bleibt am Oberschenkel.","Oben supinieren und eine Sekunde anspannen.","Langsam bis zur vollen Streckung absenken.","Oberkörper bleibt still.","Seite wechseln."],"range_of_motion":"Vom voll gestreckten Arm bis zur Schulter.","breathing":"Beim Curlen ausatmen, beim Senken einatmen.","common_mistakes":["Ellenbogen vom Oberschenkel lösen.","Oberkörper mitbewegen.","Unten nicht strecken.","Zu schwer."],"tips":["Leicht bis mittel, 10 bis 15 Wiederholungen.","Als Abschluss nach schwereren Curls.","Beide Seiten gleich viele Wiederholungen."],"cable_setup":null,"muscle_focus":["Volle Streckung unten und kräftige Supination oben: der Bizeps arbeitet so über seinen gesamten Weg.","Der Ellenbogen am Oberschenkel schließt jede Hilfe aus Schulter und Rücken aus.","2 bis 3 Sekunden absenken."],"requirements":["Flachbank","Eine Kurzhantel"],"grip_alternatives":[],"variants":[{"name":"Sitzend (Standard)","description":"Klassische Ausführung.","source_url":"https://modusx.de/fitness-uebungen/konzentrationscurls/kurzhantel-konzentrationscurls/"}],"animation_source_url":"https://modusx.de/fitness-uebungen/konzentrationscurls/","alternative_exercises":[]}$seed$::jsonb);

-- Bankdrücken Langhantel
select public.upsert_seed_exercise($seed${"slug":"bankdruecken-langhantel","name":"Bankdrücken Langhantel","category":"chest","equipment":"barbell","grip_id":null,"grip_notes":"Pronierter Griff (Handflächen nach vorne), etwas weiter als schulterbreit, Daumen umschließen die Stange. Stange in der Handwurzel ablegen, Handgelenke gerade.","primary_muscles":["chest"],"secondary_muscles":["triceps","front_delts"],"description":"Freie Druckübung auf der Flachbank mit Langhantel und Ablage, die Brust, vordere Schulter und Trizeps belastet. Grundübung für den Oberkörper, bei der Stabilität und Technik gleichermaßen gefordert sind.","setup":["Sicherheitsablagen so einstellen, dass die Stange knapp über der Brust abgefangen wird, wenn sie abgelegt werden muss.","Ablage so einstellen, dass die Stange mit fast gestreckten Armen erreichbar ist.","Gewichtsscheiben beidseitig gleich laden und mit Verschlüssen sichern.","Auf die Bank legen, Augen etwa unter der Stange, Füße flach auf den Boden stellen.","Schulterblätter nach hinten und unten ziehen, Stange etwas weiter als schulterbreit fassen.","Stange aus der Ablage heben und über der Schulter stabilisieren."],"execution":["Stange kontrolliert zur mittleren Brust absenken.","Ellenbogen etwa 45 bis 60 Grad vom Körper abgewinkelt halten.","Stange leicht die Brust berühren lassen, ohne sie abzulegen.","Stange nach oben drücken, bis die Arme fast gestreckt sind.","Schulterblätter und Gesäß bleiben während der gesamten Bewegung auf der Bank.","Nach dem letzten Satz die Stange kontrolliert in die Ablage zurückführen."],"range_of_motion":"Von der Stange an der mittleren Brust bis kurz vor die Armstreckung. Wenn die Schultern in der tiefen Position unangenehm belastet sind, Griffweite verringern.","breathing":"Beim Drücken ausatmen, beim Absenken einatmen. Bei höheren Lasten kurz vor dem Absenken einatmen und die Luft bis zum Drücken halten.","common_mistakes":["Sicherheitsablagen nicht eingestellt oder zu niedrig.","Gesäß hebt sich beim Drücken von der Bank ab.","Ellenbogen stehen 90 Grad vom Körper ab.","Stange prallt von der Brust ab.","Handgelenke knicken unter der Stange nach hinten ab."],"tips":["Bei schweren Sätzen einen Trainingspartner zum Absichern bitten, der die Stange im Zweifel mit anheben kann.","Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Erst dann Gewicht erhöhen, wenn alle Sätze im oberen Wiederholungsbereich sauber ausgeführt werden.","Füße fest in den Boden drücken, um den Rumpf zu stabilisieren."],"cable_setup":null,"muscle_focus":["Schulterblätter nach hinten und unten in die Bank drücken und dort halten; Ellenbogen etwa 45 bis 60 Grad vom Rumpf abgewinkelt, damit die Brust die Last trägt und das Schultergelenk nicht überlastet wird.","Stange bis zur mittleren Brust absenken und die gedehnte Position bewusst mitnehmen, ohne die Stange abprallen zu lassen; dort ist der Reiz auf die Brust am größten.","Exzentrik etwa zwei Sekunden lang kontrollieren, oben kurz vor der Armstreckung stoppen; Gesäß bleibt auf der Bank, Füße fest am Boden.","Griff etwas weiter als schulterbreit; ein engerer Griff verschiebt die Arbeit zum Trizeps. Gewicht so wählen, dass die Brust den Satz begrenzt."],"requirements":["Flachbank mit Hantelablage (Bankdrückstation)","Langhantel mit Gewichtsscheiben und Verschlüssen","Sicherheitsablagen oder Trainingspartner zum Absichern"],"grip_alternatives":[],"image_url":"/exercises/flat-bench-rack.jpg","machine_name":"Olympic Flat Bench mit Hantelablage","alternative_exercises":["brustpresse","kurzhantel-bankdruecken"],"animation_source_url":"https://modusx.de/fitness-uebungen/langhantel-flachbankdruecken/","variants":[]}$seed$::jsonb);

-- Schrägbankdrücken Langhantel
select public.upsert_seed_exercise($seed${"slug":"schraegbankdruecken-langhantel","name":"Schrägbankdrücken Langhantel","category":"chest","equipment":"barbell","grip_id":null,"grip_notes":"Pronierter Griff (Handflächen nach vorne), etwas weiter als schulterbreit, Daumen umschließen die Stange. Stange in der Handwurzel ablegen, Handgelenke gerade.","primary_muscles":["upper_chest","chest"],"secondary_muscles":["triceps","front_delts"],"description":"Freie Druckübung auf der etwa 30 Grad geneigten Schrägbank mit Langhantel und Ablage, die vor allem den oberen Anteil der Brust belastet. Ergänzung zum flachen Bankdrücken.","setup":["Sicherheitsablagen so einstellen, dass die Stange knapp über der oberen Brust abgefangen wird, wenn sie abgelegt werden muss.","Ablage so einstellen, dass die Stange mit fast gestreckten Armen erreichbar ist.","Gewichtsscheiben beidseitig gleich laden und mit Verschlüssen sichern.","Auf die Schrägbank setzen, Rücken und Kopf anlehnen, Füße flach auf den Boden stellen.","Schulterblätter nach hinten und unten ziehen, Stange etwas weiter als schulterbreit fassen.","Stange aus der Ablage heben und über der Schulter stabilisieren."],"execution":["Stange kontrolliert zur oberen Brust absenken.","Ellenbogen etwa 45 bis 60 Grad vom Körper abgewinkelt halten.","Stange leicht die obere Brust berühren lassen, ohne sie abzulegen.","Stange nach oben drücken, bis die Arme fast gestreckt sind.","Rücken und Gesäß bleiben während der gesamten Bewegung am Polster.","Nach dem letzten Satz die Stange kontrolliert in die Ablage zurückführen."],"range_of_motion":"Von der Stange an der oberen Brust bis kurz vor die Armstreckung. Nicht tiefer gehen, als die Schultern schmerzfrei zulassen.","breathing":"Beim Drücken ausatmen, beim Absenken einatmen.","common_mistakes":["Sicherheitsablagen nicht eingestellt oder zu niedrig.","Stange wird zu weit Richtung Hals abgesenkt.","Ellenbogen stehen 90 Grad vom Körper ab.","Rücken löst sich vom Polster, Lendenwirbelsäule wird überstreckt.","Stange prallt von der Brust ab."],"tips":["Bei schweren Sätzen einen Trainingspartner zum Absichern bitten.","Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Mit einer geringeren Last als beim flachen Bankdrücken starten, da die Schrägposition weniger Kraft zulässt."],"cable_setup":null,"muscle_focus":["Schulterblätter nach hinten und unten am Polster halten, Ellenbogen etwa 45 bis 60 Grad vom Rumpf abgewinkelt; die Stange zur oberen Brust führen, nicht zum Hals.","Ein Bankwinkel um 30 Grad betont die obere Brust; steilere Winkel verlagern die Arbeit zunehmend auf die vordere Schulter.","Gedehnte Position mit der Stange an der oberen Brust bewusst mitnehmen, Exzentrik etwa zwei Sekunden lang kontrollieren und oben kurz vor der Armstreckung stoppen.","Gewicht so wählen, dass die obere Brust den Satz begrenzt; mit weniger Last als beim flachen Bankdrücken starten."],"requirements":["Schrägbank (etwa 30 Grad) mit Hantelablage","Langhantel mit Gewichtsscheiben und Verschlüssen","Sicherheitsablagen oder Trainingspartner zum Absichern"],"grip_alternatives":[],"image_url":"/exercises/incline-bench-rack.jpg","machine_name":"Olympic Incline Bench mit Hantelablage","alternative_exercises":["schraegbankdruecken-maschine","kurzhantel-schraegbankdruecken"],"animation_source_url":"https://modusx.de/fitness-uebungen/langhantel-schraegbankdruecken/","variants":[]}$seed$::jsonb);

-- Scott Curl
select public.upsert_seed_exercise($seed${"slug":"scott-curl","name":"Scott Curl","category":"biceps","equipment":"barbell","grip_id":null,"grip_notes":"Supinierter Griff (Handflächen nach oben) an der SZ-Hantel oder Langhantel, etwa schulterbreit. Die SZ-Hantel entlastet die Handgelenke, die gerade Langhantel betont die Supination.","primary_muscles":["biceps"],"secondary_muscles":["forearms"],"description":"Bizepscurl am Scott-Pult, bei dem die Oberarme flächig auf dem geneigten Polster aufliegen und dadurch kein Schwung aus Schulter oder Rumpf möglich ist. Betont die Bizepsarbeit über einen klar begrenzten Bewegungsweg.","setup":["Sitz so einstellen, dass die Achseln oben an der Polsterkante anliegen und die Oberarme flächig auf dem Polster liegen.","SZ-Hantel oder Langhantel beidseitig gleich laden und mit Verschlüssen sichern.","Hantel aus der Ablage nehmen oder reichen lassen, Griff etwa schulterbreit, Handflächen nach oben.","Oberkörper aufrecht, Brust an das Polster, Füße flach auf den Boden stellen.","Arme kontrolliert strecken, ohne die Ellenbogen am Ende zu überstrecken."],"execution":["Hantel kontrolliert nach oben curlen, Oberarme bleiben auf dem Polster.","In der oberen Position den Bizeps kurz anspannen, Unterarme etwa senkrecht.","Handgelenke während der gesamten Bewegung gerade halten.","Hantel langsam absenken, bis die Arme fast gestreckt sind.","In der unteren Position Spannung halten, nicht in die Ellenbogen fallen lassen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von fast gestreckten Armen bis zur Position mit etwa senkrechten Unterarmen. Die Ellenbogen unten nicht vollständig durchdrücken, da der Bizeps in dieser Position unter Dehnung hohe Last trägt.","breathing":"Beim Curlen ausatmen, beim Absenken einatmen.","common_mistakes":["Ellenbogen heben sich beim Curlen vom Polster ab.","Hantel wird in der exzentrischen Phase fallen gelassen.","Ellenbogen werden in der unteren Position hart durchgestreckt.","Handgelenke knicken beim Curlen nach innen ab.","Oberkörper richtet sich auf und löst sich vom Polster."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Mit einer geringeren Last als beim stehenden Curl starten, da kein Schwung möglich ist.","Bei Beschwerden in den Handgelenken auf die SZ-Hantel wechseln.","Nach dem letzten Satz die Hantel kontrolliert in die Ablage legen oder reichen lassen."],"cable_setup":null,"muscle_focus":["Oberarme flächig auf dem Polster, Achseln an der Polsterkante; so kann die Schulter nicht mithelfen und der Bizeps trägt die gesamte Last.","Untere, gedehnte Position bis fast zur Armstreckung nutzen; am Scott-Pult trägt der Bizeps dort hohe Last, deshalb die Ellenbogen nicht hart durchdrücken.","Exzentrik etwa zwei bis drei Sekunden lang kontrollieren, oben kurz anspannen; Handgelenke gerade halten und nicht einrollen.","Gewicht so wählen, dass der Bizeps den Satz begrenzt und nicht Unterarme oder Handgelenke."],"requirements":["Scott-Pult (Preacher-Bank) mit Hantelablage","SZ-Stange oder kurze Langhantel","Gewichtsscheiben und Verschlüsse"],"grip_alternatives":[],"image_url":"/exercises/preacher-curl-bench.jpg","machine_name":"Preacher Curl Bench (Scott-Pult)","alternative_exercises":["kurzhantelcurl","kabelcurl","incline-curl"],"animation_source_url":"https://modusx.de/fitness-uebungen/scott-curls/preacher-curls-mit-der-langhantel/","variants":[]}$seed$::jsonb);

-- Beinpresse
select public.upsert_seed_exercise($seed${"slug":"beinpresse-45-grad","name":"Beinpresse","category":"quads","equipment":"machine","grip_id":null,"grip_notes":"Hände an den seitlichen Haltegriffen, um Rücken und Becken am Polster zu halten. Griffe nicht zum Mitdrücken nutzen.","primary_muscles":["quads","glutes"],"secondary_muscles":["hamstrings"],"description":"Schwere Grundübung für Quadrizeps und Gesäß an der 45°-Beinpresse. Die Fußposition steuert den Schwerpunkt: tief und eng für den Quadrizeps, hoch und breit für Gesäß und Beinbeuger. Die horizontale, sitzende Beinpresse ist dieselbe Bewegung mit kleinerem Weg.","setup":["Gewichtsscheiben beidseitig gleich beladen und sichern.","Rückenlehne so einstellen, dass das Becken in der unteren Position am Polster bleibt.","Hinsetzen, Rücken und Gesäß vollständig an das Polster legen.","Füße etwa schulterbreit mittig auf der Fußplatte, Zehen leicht nach außen.","Schlitten mit gestreckten Beinen leicht anheben und Sicherheitsriegel nach außen klappen.","Hände an die seitlichen Haltegriffe legen."],"execution":["Schlitten langsam absenken, Knie in Richtung der Zehen beugen.","So tief absenken, wie das Becken am Polster bleibt.","Über die ganze Fußsohle nach oben drücken, Fersen bleiben auf der Platte.","Knie oben nicht vollständig durchstrecken.","Knie während der Bewegung in Linie mit den Füßen halten.","Nächste Wiederholung ohne Abfedern in der unteren Position beginnen."],"range_of_motion":"Beine bis etwa 90 Grad oder etwas tiefer beugen, solange das Becken nicht vom Polster abhebt. Oben kurz vor der vollen Kniestreckung stoppen.","breathing":"Beim Drücken ausatmen, beim Absenken einatmen.","common_mistakes":["Becken rollt in der unteren Position vom Polster ab und der untere Rücken rundet sich.","Knie werden oben hart durchgestreckt.","Knie fallen beim Drücken nach innen.","Fersen heben von der Fußplatte ab.","Sicherheitsriegel werden vor dem Satz nicht geöffnet oder danach nicht wieder eingeklappt."],"tips":["Sicherheitsriegel nach jedem Satz wieder einklappen, bevor die Beine entlastet werden.","Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Höhere Fußposition belastet Gesäß und hintere Oberschenkel stärker, tiefere Fußposition die Oberschenkelvorderseite.","Gewicht in kleinen Schritten erhöhen, erst wenn die Tiefe in allen Sätzen gleich bleibt."],"cable_setup":null,"muscle_focus":["Der Quadrizeps wächst am stärksten aus tiefer Kniebeugung: so weit absenken, wie der untere Rücken auf dem Polster bleibt.","Knie in Richtung der Fußspitzen führen, nicht nach innen; Fersen nicht abheben.","Oben nicht durchstrecken, die Knie bleiben leicht gebeugt, damit die Spannung bleibt.","8 bis 15 Wiederholungen, 2 bis 3 Sekunden absenken, Gewicht steigern, sobald alle Sätze das obere Ende erreichen."],"requirements":["Scheibenbeladene 45-Grad-Beinpresse mit Sicherheitsriegeln","Gewichtsscheiben und Scheibenverschlüsse","Einstellbare Rückenlehne"],"grip_alternatives":[],"image_url":"/exercises/leg-press-45.jpg","machine_name":"Leg Press 45°, Plate Loaded","alternative_exercises":["hackenschmidt","kniebeuge"],"animation_source_url":"https://modusx.de/fitness-uebungen/beinpresse-45-grad/","variants":[{"name":"45° mit mittlerer Fußposition (Standard)","description":"Füße schulterbreit in der Plattenmitte, Knie tief beugen, Fersen bleiben auf der Platte.","source_url":"https://modusx.de/fitness-uebungen/beinpresse-45-grad/45-grad-beinpresse-mit-neutraler-fussstellung/"},{"name":"Füße tief und eng","description":"Mehr Kniebeugung, Schwerpunkt Quadrizeps. Knie nicht nach innen fallen lassen.","source_url":"https://modusx.de/fitness-uebungen/beinpresse-45-grad/45-grad-beinpresse-mit-enger-fussstellung/"},{"name":"Füße hoch und breit","description":"Mehr Hüftbeugung, Schwerpunkt Gesäß und Beinbeuger.","source_url":"https://modusx.de/fitness-uebungen/beinpresse-45-grad/45-grad-beinpresse-mit-breiter-fussstellung/"},{"name":"Horizontale Beinpresse sitzend","description":"Gleiche Bewegung an der sitzenden Maschine mit Steckgewicht. Sitz so einstellen, dass die Knie in der Startposition tief gebeugt sind.","source_url":"https://modusx.de/fitness-uebungen/beinpresse-klassisch/beinpresse-mit-beiden-beinen/"}]}$seed$::jsonb);

-- Ad-/Abduktoren Maschine
select public.upsert_seed_exercise($seed${"slug":"adduktoren-maschine","name":"Ad-/Abduktoren Maschine","category":"adductors","equipment":"machine","grip_id":null,"grip_notes":"Hände an den seitlichen Haltegriffen, um das Becken ruhig am Polster zu halten.","primary_muscles":["adductors","abductors"],"secondary_muscles":["glutes"],"description":"Eine Maschine, zwei Bewegungen: Beine gegen Widerstand schließen (Adduktion, Innenseite der Oberschenkel) oder öffnen (Abduktion, Gesäß seitlich). Beide Varianten gehören in ein vollständiges Beintraining und werden hier als eine Übung geführt.","setup":["Gewicht am Steckgewicht wählen.","Hinsetzen, Rücken an die Lehne, Oberschenkel innen an die Polster legen.","Startweite über den Einstellhebel so wählen, dass die Dehnung spürbar, aber angenehm ist.","Füße auf die Fußstützen stellen, Hände an die Haltegriffe.","Becken und Rücken fest am Polster, Rumpf anspannen."],"execution":["Beine kontrolliert zusammenführen, bis sich die Polster fast berühren.","In der Endposition kurz anspannen.","Beine langsam wieder nach außen führen.","Bewegung an der eingestellten Startweite stoppen, ohne dass das Gewicht aufsetzt.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer angenehm gedehnten Startposition bis die Polster fast zusammen sind. Die Startweite in kleinen Schritten vergrößern, nicht in die maximale Dehnung gehen.","breathing":"Beim Zusammenführen ausatmen, beim Öffnen einatmen.","common_mistakes":["Startweite zu groß gewählt, dadurch Zug in der Leiste.","Beine schnellen zusammen und das Gewicht wird nach außen fallen gelassen.","Becken kippt oder der Rücken löst sich vom Polster.","Gewicht setzt in der offenen Position auf und die Spannung geht verloren."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Startweite erst vergrößern, wenn sich der aktuelle Bewegungsradius sauber ausführen lässt.","Moderate Gewichte und höhere Wiederholungszahlen sind hier sinnvoll.","Als Ergänzung zu Kniebeuge und Beinpresse einsetzen."],"cable_setup":null,"muscle_focus":["Bei der Adduktion die Startposition weit öffnen: die Adduktoren wachsen am besten aus der gedehnten Position.","Bei der Abduktion die Endposition eine Sekunde halten und langsam zurück, das Gesäß seitlich arbeitet gegen den Widerstand auch beim Nachgeben.","Becken ruhig am Polster, kein Wippen mit dem Oberkörper.","12 bis 20 Wiederholungen je Variante, beide Varianten im selben Training sind sinnvoll."],"requirements":["Adduktoren-Maschine mit Steckgewichtsblock und Innenpolstern","Einstellhebel für die Startweite"],"grip_alternatives":[],"image_url":"/exercises/adductor-machine.jpg","machine_name":"DHZ Adductor, Steckgewicht","alternative_exercises":[],"animation_source_url":"https://modusx.de/fitness-uebungen/adduktion-geraet/adduktion-am-geraet-im-sitzen/","variants":[{"name":"Adduktion: Beine schließen","description":"Polster innen an den Knien, Beine weit öffnen (Dehnung), kontrolliert zusammenführen. Zielmuskel Adduktoren.","source_url":"https://modusx.de/fitness-uebungen/adduktion-geraet/adduktion-am-geraet-im-sitzen/"},{"name":"Abduktion: Beine öffnen","description":"Polster außen, Beine gegen Widerstand öffnen. Zielmuskel Gluteus medius und minimus. Leicht nach vorne gelehnt trifft es das Gesäß stärker.","source_url":"https://modusx.de/fitness-uebungen/abduktion-maschine/abduktion-an-der-abduktionsmaschine-klassisch/"}]}$seed$::jsonb);

-- Air Bike
select public.upsert_seed_exercise($seed${"slug":"air-bike","name":"Air Bike","category":"cardio","equipment":"cardio","grip_id":null,"grip_notes":"Hände an den beweglichen Armhebeln, Griffe locker umschließen. Alternativ die festen Griffe in der Mitte nutzen, wenn nur die Beine arbeiten sollen.","primary_muscles":["quads"],"secondary_muscles":["hamstrings","calves","triceps","front_delts"],"description":"Fahrrad mit Luftwiderstand und beweglichen Armhebeln, bei dem Beine und Arme gleichzeitig arbeiten. Der Widerstand steigt mit dem Tempo; geeignet für Aufwärmen, Intervalle und Ausdauertraining.","setup":["Sattelhöhe so einstellen, dass das Knie in der unteren Pedalstellung leicht gebeugt bleibt.","Sattel in der Länge so stellen, dass die Armhebel mit leicht gebeugten Ellenbogen erreichbar sind.","Füße mittig auf die Pedale stellen, Riemen falls vorhanden schließen.","Aufrecht sitzen, Rumpf anspannen, Griffe fassen.","Mit niedrigem Tempo starten und die Konsole bei Bedarf auf Zeit oder Intervall stellen."],"execution":["Gleichmäßig in die Pedale treten, Beine arbeiten über die ganze Umdrehung.","Armhebel abwechselnd drücken und ziehen, Bewegung aus Schulter und Rumpf.","Oberkörper bleibt stabil, kein Wippen im Sattel.","Tempo steigern, um den Widerstand zu erhöhen; Tempo senken, um ihn zu verringern.","Bei Intervallen Belastungs- und Erholungsphasen klar voneinander trennen.","Zum Schluss ein bis zwei Minuten locker austreten."],"range_of_motion":"Volle Pedalumdrehung mit leichter Kniebeugung im unteren Punkt. Armhebel über den vollen Hebelweg drücken und ziehen, ohne die Ellenbogen am Ende hart durchzustrecken.","breathing":"Gleichmäßig und tief atmen, Atemrhythmus an das Tempo anpassen. Nicht die Luft anhalten.","common_mistakes":["Sattel zu niedrig, dadurch sind die Knie stark gebeugt.","Oberkörper rundet sich und zieht nur noch mit den Armen.","Tempo zu Beginn zu hoch, die Belastung lässt sich nicht über die geplante Dauer halten.","Füße rutschen von den Pedalen, weil die Riemen nicht geschlossen sind."],"tips":["Dauer in Minuten im Feld Wiederholungen eintragen; Gewicht bleibt 0 oder kann als Widerstandsstufe genutzt werden, falls das Gerät eine hat.","Für Intervalle etwa 20 bis 40 Sekunden hohes Tempo mit ein bis zwei Minuten lockerem Treten abwechseln.","Für reines Beintraining die festen Griffe nutzen und die Armhebel ruhen lassen.","Progression über längere Dauer oder mehr Distanz beziehungsweise Kalorien bei gleicher Zeit."],"cable_setup":null,"muscle_focus":["Der Widerstand steigt mit dem Tempo; Belastung über die Trittfrequenz steuern, nicht über Wippen im Sattel.","Beine arbeiten über die ganze Pedalumdrehung, Armhebel aus Schulter und Rumpf drücken und ziehen; so verteilt sich die Belastung auf Ober- und Unterkörper.","Sattelhöhe mit leicht gebeugtem Knie im unteren Punkt hält die Oberschenkelvorderseite im arbeitsfähigen Bereich.","Für reines Beintraining die festen Griffe nutzen; bei Intervallen Belastung und Erholung klar trennen und das Tempo so wählen, dass es über die geplante Dauer haltbar ist."],"requirements":["Air Bike mit Luftwiderstand und beweglichen Armhebeln","Verstellbarer Sattel (Höhe und Länge)"],"grip_alternatives":[],"image_url":"/exercises/air-bike.jpg","machine_name":"USAEON Air Bike","alternative_exercises":[],"variants":[]}$seed$::jsonb);

-- Rudergerät
select public.upsert_seed_exercise($seed${"slug":"rudergeraet","name":"Rudergerät","category":"cardio","equipment":"cardio","grip_id":null,"grip_notes":"Griff mit beiden Händen etwa schulterbreit von oben fassen, Handgelenke gerade. Griff locker halten, die Finger haken, nicht verkrampfen.","primary_muscles":["quads","lats"],"secondary_muscles":["hamstrings","glutes","biceps","mid_back"],"description":"Rudergerät mit Magnet- oder Luftwiderstand, bei dem Beine, Rumpf und Arme nacheinander arbeiten. Ganzkörper-Ausdauerübung, die sich für Aufwärmen, Intervalle und Dauerbelastung eignet.","setup":["Widerstandsstufe am Gerät einstellen, für den Einstieg eine mittlere Stufe wählen.","Auf den Rollsitz setzen, Füße in die Fußschalen stellen und Riemen über dem Fußballen schließen.","Griff fassen, Knie beugen und mit aufrechtem Oberkörper nach vorne rollen.","Schienbeine etwa senkrecht, Arme gestreckt, Rumpf angespannt.","Konsole bei Bedarf auf Zeit, Distanz oder Intervall stellen."],"execution":["Zuerst die Beine strecken und den Sitz nach hinten schieben, Arme bleiben gestreckt.","Dann den Oberkörper leicht nach hinten lehnen, etwa auf elf Uhr.","Zuletzt den Griff zum unteren Brustbereich ziehen, Ellenbogen nah am Körper.","Rückweg in umgekehrter Reihenfolge: Arme strecken, Oberkörper nach vorne, dann Knie beugen.","Kontrolliert nach vorne rollen, nicht mit Schwung in die Startposition fallen.","Schlagfrequenz gleichmäßig halten, etwa 20 bis 28 Schläge pro Minute für Dauerbelastung."],"range_of_motion":"Vom eingerollten Start mit senkrechten Schienbeinen bis zu gestreckten Beinen, leichter Rücklage und Griff am unteren Brustbereich. Der Zug ist etwa doppelt so schnell wie die Rückführung.","breathing":"Beim Zug ausatmen, beim Vorrollen einatmen. Atmung gleichmäßig an den Schlagrhythmus koppeln.","common_mistakes":["Arme ziehen zu früh, bevor die Beine gestreckt sind.","Oberkörper lehnt sich zu weit nach hinten oder rundet sich beim Vorrollen.","Knie werden auf dem Rückweg zu früh gebeugt und kommen dem Griff in die Quere.","Griff wird zum Hals statt zur unteren Brust gezogen.","Schlagfrequenz zu hoch, dadurch wird der Zug unkontrolliert."],"tips":["Dauer in Minuten im Feld Wiederholungen eintragen; im Feld Gewicht kann die Widerstandsstufe notiert werden, sonst bleibt es 0.","Reihenfolge Beine, Rumpf, Arme bei langsamem Tempo einüben, bevor die Intensität steigt.","Progression über längere Dauer oder eine bessere Zeit pro 500 Meter bei gleicher Schlagfrequenz.","Für Intervalle Zugphasen von ein bis zwei Minuten mit lockeren Erholungsphasen abwechseln."],"cable_setup":null,"muscle_focus":["Reihenfolge Beine, Rumpf, Arme einhalten: erst die Beine strecken, dann den Oberkörper leicht zurücklehnen, zuletzt den Griff zur unteren Brust ziehen. So kommt der größte Teil der Kraft aus den Beinen.","Schlagzahl moderat halten, etwa 20 bis 28 Schläge pro Minute; Intensität über die Kraft pro Zug steuern, nicht über die Frequenz.","Rückweg in umgekehrter Reihenfolge und etwa doppelt so lang wie der Zug; der untere Rücken bleibt dabei gerade.","Widerstandsstufe mittel wählen; eine hohe Stufe macht den Zug schwerfällig und verschiebt die Belastung auf den Rücken."],"requirements":["Rudergerät mit Magnet- oder Luftwiderstand (Rollsitz, Fußschalen mit Riemen)","Konsole für Zeit, Distanz oder Intervall"],"grip_alternatives":[],"image_url":"/exercises/rowing-machine.jpg","machine_name":"Rudergerät (Neolymp)","alternative_exercises":[],"variants":[]}$seed$::jsonb);

-- Ski Erg
select public.upsert_seed_exercise($seed${"slug":"ski-erg","name":"Ski Erg","category":"cardio","equipment":"cardio","grip_id":null,"grip_notes":"Beide Griffe von oben fassen, Handflächen zeigen nach unten beziehungsweise zueinander. Griffe locker halten, der Zug kommt aus Rumpf und Latissimus, nicht aus den Fingern.","primary_muscles":["lats","abs"],"secondary_muscles":["triceps","hamstrings","glutes"],"description":"Ski-Ergometer, bei dem die Griffe von oben nach unten gezogen werden, ähnlich dem Doppelstockschub beim Skilanglauf. Belastet Latissimus und Bauch über die Rumpfbeuge; geeignet für Aufwärmen, Intervalle und Ausdauertraining.","setup":["Widerstandsstufe am Gerät einstellen, für den Einstieg eine mittlere Stufe wählen.","Etwa eine Armlänge vor dem Gerät stehen, Füße hüftbreit.","Griffe fassen und mit gestreckten Armen über Kopf in die Startposition bringen.","Knie leicht gebeugt, Rumpf angespannt, Blick nach vorne.","Konsole bei Bedarf auf Zeit, Distanz oder Intervall stellen."],"execution":["Griffe zügig nach unten ziehen, der Oberkörper beugt sich dabei aus der Hüfte nach vorne.","Hüfte und Knie leicht mitbeugen, Rücken bleibt gerade.","Griffe an den Oberschenkeln vorbei nach hinten führen, Arme am Ende fast gestreckt.","Oberkörper wieder aufrichten und die Arme kontrolliert nach oben in die Startposition bringen.","Der Zug ist zügig und kräftig, die Rückführung ruhiger.","Rhythmus gleichmäßig halten."],"range_of_motion":"Von gestreckten Armen über Kopf bis die Griffe hinter den Oberschenkeln sind, mit Rumpfbeuge aus der Hüfte. Rückführung bis zur Streckung über Kopf, ohne ins Hohlkreuz zu fallen.","breathing":"Beim Zug nach unten ausatmen, beim Aufrichten einatmen. Atmung gleichmäßig an den Rhythmus koppeln.","common_mistakes":["Rücken rundet sich beim Zug nach unten.","Zug kommt nur aus den Armen, Rumpf und Hüfte bleiben steif.","Zu nah am Gerät gestanden, dadurch fehlt Platz für die Rumpfbeuge.","Griffe werden oben zu weit nach hinten geführt und der untere Rücken überstreckt."],"tips":["Dauer in Minuten im Feld Wiederholungen eintragen; im Feld Gewicht kann die Widerstandsstufe notiert werden, sonst bleibt es 0.","Bewegung bei niedrigem Tempo einüben, bevor die Intensität steigt.","Progression über längere Dauer oder mehr Distanz bei gleicher Zeit.","Für Intervalle 30 bis 60 Sekunden zügiger Zug mit lockeren Erholungsphasen abwechseln."],"cable_setup":null,"muscle_focus":["Der Zug kommt aus der Hüftbeuge mit dem Rumpf: Oberkörper aus der Hüfte nach vorne beugen, Latissimus und Bauch ziehen die Griffe nach unten, die Arme übertragen die Kraft.","Hüfte und Knie leicht mitbeugen, Rücken gerade; ein runder Rücken nimmt Latissimus und Bauch die Arbeit ab.","Oben die Arme gestreckt über Kopf bringen, ohne ins Hohlkreuz zu fallen; so arbeitet der Latissimus aus der gedehnten Position.","Zug zügig, Rückführung ruhiger; Intensität über die Kraft pro Zug steuern, Widerstandsstufe mittel."],"requirements":["Ski-Ergometer mit Griffen über Kopf (Luft- oder Magnetwiderstand)","Etwa eine Armlänge Platz vor dem Gerät"],"grip_alternatives":[],"image_url":"/exercises/ski-erg.jpg","machine_name":"Ski-Ergometer (Rogue)","alternative_exercises":[],"variants":[]}$seed$::jsonb);

-- Laufband
select public.upsert_seed_exercise($seed${"slug":"laufband","name":"Laufband","category":"cardio","equipment":"cardio","grip_id":null,"grip_notes":"Hände frei und locker mitschwingen lassen. Haltegriffe nur zum Aufsteigen, Absteigen oder kurzen Abstützen nutzen.","primary_muscles":["quads","calves"],"secondary_muscles":["hamstrings","glutes"],"description":"Laufband mit einstellbarer Geschwindigkeit und Steigung für Gehen, zügiges Gehen und Laufen. Geeignet für Aufwärmen, Dauerbelastung und Intervalle.","setup":["Beidbeinig auf die seitlichen Trittflächen stellen, nicht auf das stehende Band.","Not-Stopp-Clip an der Kleidung befestigen.","Band mit niedriger Geschwindigkeit starten und auf das Band treten.","Geschwindigkeit und Steigung schrittweise auf das geplante Niveau erhöhen.","Aufrecht laufen oder gehen, Blick nach vorne, nicht auf die Füße."],"execution":["Tempo und Steigung über die geplante Dauer gleichmäßig halten.","Mit dem Fuß unter dem Körper aufsetzen, Schritte kurz und locker halten.","Arme locker mitschwingen lassen, Schultern entspannt.","Bei Steigung den Oberkörper leicht nach vorne neigen, nicht an den Griffen festhalten.","Bei Intervallen die Geschwindigkeit stufenweise erhöhen und senken, nicht abrupt.","Zum Schluss zwei bis drei Minuten im Gehen auslaufen, dann Band stoppen und absteigen."],"range_of_motion":"Natürliche Schrittlänge bei aufrechtem Oberkörper. Schrittfrequenz lieber erhöhen, als die Schritte zu verlängern.","breathing":"Gleichmäßig und tief atmen, Atemrhythmus an die Schritte koppeln. Nicht die Luft anhalten.","common_mistakes":["Dauerhaftes Festhalten an den Griffen, besonders bei Steigung.","Schritte zu lang, der Fuß setzt weit vor dem Körper auf.","Blick nach unten auf die Füße oder zur Seite.","Not-Stopp-Clip nicht befestigt.","Abstieg vom laufenden Band ohne vorheriges Abbremsen."],"tips":["Dauer in Minuten im Feld Wiederholungen eintragen; Gewicht bleibt 0 oder kann als Widerstandsstufe genutzt werden, zum Beispiel für die Steigung in Prozent.","Progression über längere Dauer, höhere Geschwindigkeit oder mehr Steigung, jeweils nur eine Größe gleichzeitig erhöhen.","Steigung von ein bis zwei Prozent beim Laufen gleicht den fehlenden Luftwiderstand aus.","Für Intervalle etwa eine Minute schnelleres Tempo mit ein bis zwei Minuten lockerem Gehen oder Laufen abwechseln."],"cable_setup":null,"muscle_focus":["Für Gesäß und Waden Steigung statt Tempo erhöhen; schon 5 bis 10 Prozent Steigung im zügigen Gehen belasten Gesäß und Waden deutlich stärker als flaches Laufen.","Fuß unter dem Körper aufsetzen, Schritte kurz und schnell; lange Schritte vor dem Körper bremsen und belasten die Knie.","Hände frei lassen und nicht an den Griffen festhalten; Festhalten nimmt die Belastung aus Beinen und Gesäß.","Ein bis zwei Prozent Steigung beim Laufen gleichen den fehlenden Luftwiderstand aus; nur eine Größe gleichzeitig steigern: Dauer, Tempo oder Steigung."],"requirements":["Laufband mit einstellbarer Geschwindigkeit und Steigung","Not-Stopp-Clip"],"grip_alternatives":[],"image_url":"/exercises/treadmill.jpg","machine_name":"USAEON Laufband","alternative_exercises":[],"variants":[]}$seed$::jsonb);


-- >>>>>>>>>> 0006_seed_templates.sql <<<<<<<<<<

-- ============================================================
-- 0006_seed_templates.sql
-- GENERIERT aus supabase/seed/templates.json via `npm run db:generate` – nicht manuell bearbeiten.
-- Standard-Trainingspläne (Vorlagen), werden bei Registrierung je Benutzer kopiert.
-- ============================================================

-- Oberkörper A
select public.upsert_seed_template($seed${"name":"Oberkörper A","sort_order":1,"exercises":[{"slug":"schraegbankdruecken-maschine","sets":3,"rep_min":6,"rep_max":10},{"slug":"butterfly","sets":3,"rep_min":6,"rep_max":10},{"slug":"neutraler-latzug","sets":3,"rep_min":8,"rep_max":12},{"slug":"breites-rudern","sets":3,"rep_min":8,"rep_max":12},{"slug":"schulterdruecken-maschine","sets":2,"rep_min":8,"rep_max":12},{"slug":"seitheben-maschine","sets":2,"rep_min":12,"rep_max":15},{"slug":"trizepsdruecken-kabel","sets":2,"rep_min":10,"rep_max":15},{"slug":"incline-curl","sets":2,"rep_min":10,"rep_max":15}]}$seed$::jsonb);

-- Unterkörper
select public.upsert_seed_template($seed${"name":"Unterkörper","sort_order":2,"exercises":[{"slug":"hackenschmidt","sets":3,"rep_min":6,"rep_max":10},{"slug":"beinpresse-45-grad","sets":2,"rep_min":10,"rep_max":12},{"slug":"beinbeuger","sets":3,"rep_min":8,"rep_max":12},{"slug":"beinstrecker","sets":2,"rep_min":10,"rep_max":15},{"slug":"hyperextensions","sets":2,"rep_min":10,"rep_max":15},{"slug":"wadenheben-stehend","sets":3,"rep_min":10,"rep_max":15},{"slug":"crunch-maschine","sets":3,"rep_min":10,"rep_max":15}]}$seed$::jsonb);

-- Oberkörper B
select public.upsert_seed_template($seed${"name":"Oberkörper B","sort_order":3,"exercises":[{"slug":"schraegbankdruecken-maschine","sets":2,"rep_min":8,"rep_max":12},{"slug":"enges-rudern","sets":3,"rep_min":8,"rep_max":12},{"slug":"neutraler-latzug","sets":2,"rep_min":8,"rep_max":12},{"slug":"butterfly","sets":2,"rep_min":10,"rep_max":15},{"slug":"reverse-butterfly","sets":2,"rep_min":12,"rep_max":15},{"slug":"seitheben-maschine","sets":2,"rep_min":12,"rep_max":15},{"slug":"kabelcurl","sets":2,"rep_min":10,"rep_max":15},{"slug":"ueberkopf-trizeps-extension","sets":2,"rep_min":10,"rep_max":12}]}$seed$::jsonb);


-- >>>>>>>>>> 0007_media_and_storage.sql <<<<<<<<<<

-- ============================================================
-- 0007_media_and_storage.sql
-- Griff-Bilder, Ausführungs-Animationen, Storage-Bucket
-- ============================================================

-- Griffe können ein Foto bekommen (z. B. aus dem eigenen Studio)
alter table public.grips add column if not exists image_url text;

-- Übungen: zusätzlich zur Maschinen-/Übungsabbildung eine Ausführungs-Animation (GIF, WebP, MP4)
alter table public.exercises add column if not exists animation_url text;

-- Seed-Funktion: animation_url mitnehmen, vorhandene Werte nicht überschreiben
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
    setup, execution, range_of_motion, breathing, common_mistakes, tips, cable_setup, image_url, animation_url
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
    nullif(p ->> 'animation_url', '')
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
    animation_url = coalesce(public.exercises.animation_url, excluded.animation_url)
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
-- Storage-Bucket für Übungs-, Griff- und Animationsdateien
-- (öffentlich lesbar; Schreiben nur für angemeldete Benutzer in eigenem Ordner)
-- ------------------------------------------------------------
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'storage' and table_name = 'buckets') then
    insert into storage.buckets (id, name, public)
    values ('exercise-assets', 'exercise-assets', true)
    on conflict (id) do update set public = true;

    if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'exercise_assets_public_read') then
      create policy "exercise_assets_public_read" on storage.objects
        for select using (bucket_id = 'exercise-assets');
    end if;
    if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'exercise_assets_user_write') then
      create policy "exercise_assets_user_write" on storage.objects
        for insert to authenticated
        with check (bucket_id = 'exercise-assets' and (storage.foldername(name))[1] = auth.uid()::text);
    end if;
    if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'exercise_assets_user_update') then
      create policy "exercise_assets_user_update" on storage.objects
        for update to authenticated
        using (bucket_id = 'exercise-assets' and (storage.foldername(name))[1] = auth.uid()::text);
    end if;
    if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'exercise_assets_user_delete') then
      create policy "exercise_assets_user_delete" on storage.objects
        for delete to authenticated
        using (bucket_id = 'exercise-assets' and (storage.foldername(name))[1] = auth.uid()::text);
    end if;
  end if;
end $$;


-- >>>>>>>>>> 0008_member_sessions.sql <<<<<<<<<<

-- ============================================================
-- 0008_member_sessions.sql
-- Mitglieder-Detailansicht in den Stats: abgeschlossene Trainings
-- eines Mitglieds samt Übungen und Sätzen (nur lesend, nur für
-- angemeldete Benutzer).
-- ============================================================

-- ------------------------------------------------------------
-- Trainingsliste eines Mitglieds
-- ------------------------------------------------------------
create or replace function public.get_member_sessions(p_user_id uuid, p_limit integer default 100)
returns table (
  session_id uuid,
  name text,
  started_at timestamptz,
  ended_at timestamptz,
  duration_seconds integer,
  total_volume numeric,
  total_sets integer,
  exercise_names text[]
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Nicht angemeldet' using errcode = '42501';
  end if;

  return query
  select
    s.id as session_id,
    s.name,
    s.started_at,
    s.ended_at,
    s.duration_seconds,
    s.total_volume,
    s.total_sets,
    coalesce(
      (select array_agg(e.name order by se.sort_order)
         from public.workout_session_exercises se
         join public.exercises e on e.id = se.exercise_id
        where se.session_id = s.id),
      '{}'::text[]
    ) as exercise_names
  from public.workout_sessions s
  where s.user_id = p_user_id
    and s.status = 'completed'
  order by s.started_at desc
  limit coalesce(p_limit, 100);
end;
$$;
revoke all on function public.get_member_sessions(uuid, integer) from public;
grant execute on function public.get_member_sessions(uuid, integer) to authenticated;

-- ------------------------------------------------------------
-- Detail eines abgeschlossenen Trainings (Übungen + Sätze) als JSON
-- Gibt null zurück, wenn die Session nicht existiert oder nicht abgeschlossen ist.
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
             'equipment', e.equipment
           ),
           'sets', coalesce(
             (select jsonb_agg(
                jsonb_build_object(
                  'set_number', ws.set_number,
                  'weight', ws.weight,
                  'reps', ws.reps,
                  'rir', ws.rir,
                  'is_warmup', ws.is_warmup
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
revoke all on function public.get_member_session_detail(uuid) from public;
grant execute on function public.get_member_session_detail(uuid) to authenticated;


-- >>>>>>>>>> 0009_categories_cardio_hips.sql <<<<<<<<<<

-- ============================================================
-- 0009_categories_cardio_hips.sql
-- Neue Kategorien (Cardio, Ad-/Abduktoren), neues Equipment (Cardio), neue Muskelgruppen.
-- Für bestehende Datenbanken; frische Installationen enthalten die Werte bereits in 0001/0004.
-- Hinweis: Die neuen Enum-Werte dürfen erst in einer späteren Anfrage verwendet werden
-- (deshalb hier keine Übungen anlegen; das macht 0005 beim erneuten Ausführen).
-- ============================================================

alter type public.exercise_category add value if not exists 'adductors';
alter type public.exercise_category add value if not exists 'cardio';
alter type public.equipment_type add value if not exists 'cardio';

insert into public.muscle_groups (id, name_de, region, sort_order) values
  ('adductors', 'Adduktoren', 'front', 64),
  ('abductors', 'Abduktoren', 'both', 65)
on conflict (id) do update set name_de = excluded.name_de, region = excluded.region, sort_order = excluded.sort_order;


-- >>>>>>>>>> 0010_remove_machine_images.sql <<<<<<<<<<

-- ============================================================
-- 0010_remove_machine_images.sql
-- Maschinenfotos entfernt: Standardübungen zeigen nur noch die Muskelkarte.
-- ============================================================

update public.exercises
set image_url = null
where owner_id is null and image_url like '/exercises/%';


-- >>>>>>>>>> 0011_focus_requirements_grips.sql <<<<<<<<<<

-- ============================================================
-- 0011_focus_requirements_grips.sql
-- Muskelfokus, benötigte Ausstattung, Griff-Alternativen, Handschlaufe
-- ============================================================

alter table public.exercises add column if not exists muscle_focus text[] not null default '{}';
alter table public.exercises add column if not exists requirements text[] not null default '{}';
alter table public.exercises add column if not exists grip_alternatives text[] not null default '{}';

insert into public.grips (id, name_de, description, sort_order) values
  ('strap_handle', 'Handschlaufe', 'Weiche Schlaufe mit Karabiner, die um die Hand gelegt wird. Entlastet den Griff und eignet sich für Seitheben, Kickbacks und einarmige Zugübungen.', 55)
on conflict (id) do update set name_de = excluded.name_de, description = excluded.description, sort_order = excluded.sort_order;

-- Seed-Funktion: neue Felder übernehmen
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


-- >>>>>>>>>> 0012_machine_info.sql <<<<<<<<<<

-- ============================================================
-- 0012_machine_info.sql
-- Gerätename und alternative Geräte je Übung
-- ============================================================

alter table public.exercises add column if not exists machine_name text;
alter table public.exercises add column if not exists alternative_exercises text[] not null default '{}';

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
    muscle_focus, requirements, grip_alternatives, machine_name, alternative_exercises
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
    coalesce(array(select jsonb_array_elements_text(p -> 'alternative_exercises')), '{}')
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
    alternative_exercises = excluded.alternative_exercises
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


-- >>>>>>>>>> 0013_admin_bootstrap.sql <<<<<<<<<<

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


-- >>>>>>>>>> 0014_admin.sql <<<<<<<<<<

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


-- >>>>>>>>>> 0015_row_variants.sql <<<<<<<<<<

-- ============================================================
-- 0015_row_variants.sql
-- Rudern Hebel sitzend wird zu "Rudern Hebel eng" (Slug-Umbenennung, Inhalte kommen aus dem Seed),
-- "Rudern Hebel breit" kommt neu aus dem Seed, Brustgestütztes Rudern entfällt.
-- Trainingsdaten bleiben erhalten (Übungen mit Trainingshistorie werden nicht gelöscht).
-- ============================================================

update public.exercises
set slug = 'rudern-hebel-eng', name = 'Rudern Hebel eng'
where slug = 'rudern-hebel-sitzend' and owner_id is null;

delete from public.exercises e
where e.slug = 'brustgestuetztes-rudern'
  and e.owner_id is null
  and not exists (select 1 from public.workout_session_exercises se where se.exercise_id = e.id);


-- >>>>>>>>>> 0016_admin_nickname.sql <<<<<<<<<<

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


-- >>>>>>>>>> 0017_tracking_modes.sql <<<<<<<<<<

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
    and s.status = 'completed'
    -- Nur eigene Trainings; ohne Benutzerkontext (SQL-Editor, Service-Rolle) alle
    and (auth.uid() is null or s.user_id = auth.uid());
end;
$$;
-- Nur für angemeldete Benutzer (wird auch aus complete_workout_session im Benutzerkontext aufgerufen);
-- berechnet ausschließlich eigene, bereits abgeschlossene Trainings neu und ist damit idempotent.
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


-- >>>>>>>>>> 0018_portfolio_admin_sharing.sql <<<<<<<<<<

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


-- >>>>>>>>>> 0019_body_data_cardio_targets.sql <<<<<<<<<<

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


-- >>>>>>>>>> 0020_admin_body_data.sql <<<<<<<<<<

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


-- >>>>>>>>>> 0021_exercise_consolidation.sql <<<<<<<<<<

-- ============================================================
-- 0021_exercise_consolidation.sql
-- Übungskatalog konsolidiert: Dubletten werden zusammengeführt, Varianten
-- (z. B. stehend/sitzend, Stange/Seil) werden innerhalb einer Übung erklärt.
-- Pläne, Vorlagen, Trainings und Favoriten werden auf die behaltene Übung
-- umgehängt, bevor die Dublette gelöscht wird (Historie bleibt vollständig).
-- ============================================================

-- ------------------------------------------------------------
-- Varianten je Übung: [{ "name": "Stehend", "description": "…", "source_url": "…" }]
-- ------------------------------------------------------------
alter table public.exercises add column if not exists variants jsonb not null default '[]'::jsonb;
comment on column public.exercises.variants is 'Ausführungsvarianten einer Übung (Name, Beschreibung, optional Link)';

-- ------------------------------------------------------------
-- Zwei Standardübungen zusammenführen: alle Verweise von p_from auf p_to,
-- dann p_from löschen. Liefert die Anzahl umgehängter Trainingsübungen.
-- ------------------------------------------------------------
create or replace function public.merge_exercise(p_from text, p_to text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_from uuid;
  v_to uuid;
  v_moved integer := 0;
begin
  select id into v_from from public.exercises where slug = p_from and owner_id is null;
  select id into v_to from public.exercises where slug = p_to and owner_id is null;
  if v_from is null or v_to is null or v_from = v_to then
    return 0;
  end if;

  -- Pläne: steht die Zielübung schon im selben Plan, entfällt die Dublette
  delete from public.workout_plan_exercises pe
  where pe.exercise_id = v_from
    and exists (select 1 from public.workout_plan_exercises q where q.plan_id = pe.plan_id and q.exercise_id = v_to);
  update public.workout_plan_exercises set exercise_id = v_to where exercise_id = v_from;

  -- Vorlagen analog
  delete from public.workout_plan_template_exercises te
  where te.exercise_id = v_from
    and exists (select 1 from public.workout_plan_template_exercises q where q.template_id = te.template_id and q.exercise_id = v_to);
  update public.workout_plan_template_exercises set exercise_id = v_to where exercise_id = v_from;

  -- Trainings: vollständig umhängen, Sätze bleiben erhalten
  update public.workout_session_exercises set exercise_id = v_to where exercise_id = v_from;
  get diagnostics v_moved = row_count;

  -- Favoriten
  delete from public.favorites f
  where f.exercise_id = v_from
    and exists (select 1 from public.favorites g where g.user_id = f.user_id and g.exercise_id = v_to);
  update public.favorites set exercise_id = v_to where exercise_id = v_from;

  -- Verweise in Alternativlisten bereinigen
  update public.exercises
  set alternative_exercises = array_remove(alternative_exercises, p_from)
  where p_from = any (alternative_exercises);

  delete from public.exercises where id = v_from;
  return v_moved;
end;
$$;
revoke all on function public.merge_exercise(text, text) from public;

-- ------------------------------------------------------------
-- Zusammenführungen (in einer frischen Datenbank ohne Wirkung, weil der
-- Seed die Dubletten nicht mehr enthält)
-- ------------------------------------------------------------
select public.merge_exercise('pec-deck', 'butterfly');
select public.merge_exercise('brustpresse-hebel-sitzend', 'brustpresse');
select public.merge_exercise('brustpresse-hebel', 'brustpresse');
select public.merge_exercise('brustpresse-vertikal', 'brustpresse');
select public.merge_exercise('multi-press-maschine', 'brustpresse');
select public.merge_exercise('schraegbankdruecken-hebelmaschine', 'schraegbankdruecken-maschine');
select public.merge_exercise('schraegbankdruecken-hebel-liegend', 'schraegbankdruecken-maschine');
select public.merge_exercise('schraegbankdruecken-hebel-flex', 'schraegbankdruecken-maschine');
select public.merge_exercise('kabel-flys-von-unten', 'kabel-flys');
select public.merge_exercise('kabel-flys-von-oben', 'kabel-flys');
select public.merge_exercise('schulterpresse-maschine', 'schulterdruecken-maschine');
select public.merge_exercise('seitheben-kabel', 'seitheben-maschine');
select public.merge_exercise('kabel-reverse-fly', 'reverse-butterfly');
select public.merge_exercise('latzug-hebel', 'neutraler-latzug');
select public.merge_exercise('rudern-hebel-eng', 'enges-rudern');
select public.merge_exercise('kabelrudern-einarmig', 'enges-rudern');
select public.merge_exercise('rudern-hebel-breit', 'breites-rudern');
select public.merge_exercise('abduktoren-maschine', 'adduktoren-maschine');
select public.merge_exercise('beinpresse', 'beinpresse-45-grad');
select public.merge_exercise('multipresse-kniebeuge', 'hackenschmidt');
select public.merge_exercise('wadenheben-sitzend', 'wadenheben-stehend');
select public.merge_exercise('wadenheben-hackenschmidt', 'wadenheben-stehend');
select public.merge_exercise('incline-curl-hinterm-koerper', 'incline-curl');
select public.merge_exercise('hammercurl-kabel', 'kabelcurl');
select public.merge_exercise('trizepsdruecken-stange', 'trizepsdruecken-kabel');
select public.merge_exercise('trizepsdruecken-seil', 'trizepsdruecken-kabel');
select public.merge_exercise('kabel-extension-einarmig', 'trizepsdruecken-kabel');
select public.merge_exercise('kabel-crunch', 'crunch-maschine');

-- ------------------------------------------------------------
-- Seed-Hilfsfunktion: Varianten aus JSON übernehmen
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
    muscle_focus, requirements, grip_alternatives, machine_name, alternative_exercises, bodyweight_factor, animation_source_url, variants
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
    nullif(p ->> 'animation_source_url', ''),
    case when jsonb_typeof(p -> 'variants') = 'array' then p -> 'variants' else '[]'::jsonb end
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
    animation_url = coalesce(excluded.animation_url, public.exercises.animation_url),
    animation_source_url = coalesce(excluded.animation_source_url, public.exercises.animation_source_url),
    muscle_focus = excluded.muscle_focus,
    requirements = excluded.requirements,
    grip_alternatives = excluded.grip_alternatives,
    machine_name = excluded.machine_name,
    alternative_exercises = excluded.alternative_exercises,
    bodyweight_factor = excluded.bodyweight_factor,
    variants = excluded.variants
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
