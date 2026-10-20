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
-- 71 Standardübungen
-- ============================================================

-- Schrägbankdrücken Maschine
select public.upsert_seed_exercise($seed${"slug":"schraegbankdruecken-maschine","name":"Schrägbankdrücken Maschine","category":"chest","equipment":"machine","grip_id":null,"grip_notes":"Pronierte Griffe (Handflächen nach vorne) oder neutrale Griffe, je nach Maschine. Handgelenke gerade halten.","primary_muscles":["upper_chest","chest"],"secondary_muscles":["triceps","front_delts"],"description":"Geführte Druckbewegung in Schrägposition, die vor allem den oberen Anteil der Brust belastet. Gut geeignet als erste Druckübung im Oberkörpertraining.","setup":["Sitz so einstellen, dass die Griffe ungefähr auf Höhe der mittleren bis oberen Brust liegen.","Rücken und Kopf vollständig an das Polster anlehnen.","Füße flach auf den Boden stellen.","Schulterblätter kontrolliert nach hinten und unten ziehen.","Griffe fassen, Handgelenke gerade, Ellenbogen leicht unterhalb der Griffe."],"execution":["Griffe kontrolliert nach vorne-oben drücken.","Ellenbogen am Ende nicht aggressiv durchstrecken.","Spannung in der Brust halten, Schulterblätter bleiben hinten.","Gewicht langsam und kontrolliert zurückführen.","In der Endposition leichte Dehnung der Brust spüren, ohne dass das Gewicht aufsetzt.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Voller Bewegungsradius, soweit die Schultern schmerzfrei bleiben. In der unteren Position die Griffe etwa auf Brusthöhe bringen, oben kurz vor dem Durchstrecken stoppen.","breathing":"Beim Drücken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Schultern rollen beim Drücken nach vorne.","Sitz zu niedrig, Griffe liegen auf Schulterhöhe.","Gewicht wird mit Schwung aus der unteren Position gedrückt.","Ellenbogen werden am Ende hart durchgestreckt.","Rücken löst sich vom Polster."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Erst dann Gewicht erhöhen, wenn alle Sätze im oberen Wiederholungsbereich sauber ausgeführt werden.","Wenn die Schultern unangenehm belastet sind, Sitz etwas höher stellen oder Griffweite ändern."],"cable_setup":null,"muscle_focus":["Griffe in der unteren Position bis auf Höhe der mittleren bis oberen Brust bringen, damit die obere Brust in der gedehnten Position arbeitet; dieser Bereich liefert nach aktuellem Stand einen hohen Trainingsreiz.","Schulterblätter während des gesamten Satzes nach hinten und unten am Polster halten, sonst übernimmt die vordere Schulter einen Großteil der Arbeit.","Ellenbogen etwa 45 bis 60 Grad vom Rumpf abgespreizt führen, nicht ganz seitlich und nicht am Körper anliegend.","Exzentrische Phase zwei bis drei Sekunden lang kontrollieren und oben kurz vor dem Durchstrecken stoppen, damit die Spannung in der Brust bleibt."],"requirements":["Schrägbankdrück-Maschine mit verstellbarem Sitz (Hebel- oder Stapelmaschine)"],"grip_alternatives":[],"image_url":"/exercises/incline-press-plate.jpg","machine_name":"DHZ Incline Chest Press, Plate Loaded","alternative_exercises":["schraegbankdruecken-hebelmaschine","schraegbankdruecken-hebel-flex","schraegbankdruecken-hebel-liegend","schraegbankdruecken-langhantel"]}$seed$::jsonb);

-- Brustpresse
select public.upsert_seed_exercise($seed${"slug":"brustpresse","name":"Brustpresse","category":"chest","equipment":"machine","grip_id":null,"grip_notes":"Pronierte Griffe (Handflächen nach vorne) oder neutrale Griffe, je nach Maschine. Handgelenke gerade halten, Griffe nicht zu fest umklammern.","primary_muscles":["chest"],"secondary_muscles":["triceps","front_delts"],"description":"Geführte horizontale Druckbewegung im Sitzen, die die gesamte Brustmuskulatur belastet. Geeignet als Grundübung für die Brust, wenn eine stabile Führung gewünscht ist.","setup":["Sitz so einstellen, dass die Griffe etwa auf Höhe der mittleren Brust liegen.","Rücken und Kopf vollständig an das Polster anlehnen.","Füße flach auf den Boden oder auf die Fußstütze stellen.","Schulterblätter nach hinten und unten ziehen, Brust leicht anheben.","Griffe fassen, Handgelenke gerade, Ellenbogen etwa auf Höhe der Griffe oder leicht darunter."],"execution":["Griffe kontrolliert nach vorne drücken, bis die Arme fast gestreckt sind.","Ellenbogen am Ende nicht hart durchstrecken.","Schulterblätter während der gesamten Bewegung hinten am Polster lassen.","Gewicht langsam zurückführen, Ellenbogen wandern nach hinten.","In der Startposition leichte Dehnung der Brust spüren, Gewicht nicht aufsetzen lassen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer leichten Dehnung der Brust mit den Griffen etwa auf Brusthöhe bis kurz vor die vollständige Armstreckung. Bewegungsradius nur so groß wählen, wie die Schultern schmerzfrei bleiben.","breathing":"Beim Drücken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Schultern rollen beim Drücken nach vorne, Schulterblätter lösen sich vom Polster.","Sitz zu hoch oder zu tief, Griffe liegen nicht auf Brusthöhe.","Ellenbogen werden am Ende hart durchgestreckt.","Gewicht wird mit Schwung aus der hinteren Position gedrückt.","Handgelenke knicken nach hinten ab."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Ellenbogen etwa 45 bis 60 Grad vom Körper abspreizen, um die Schultern zu entlasten.","Falls vorhanden, das Fußpedal nutzen, um die Griffe in die Ausgangsposition zu bringen.","Erst Gewicht erhöhen, wenn alle Sätze sauber ausgeführt werden."],"cable_setup":null,"muscle_focus":["Griffe so weit zurückführen, dass eine deutliche Dehnung in der Brust spürbar ist; der gedehnte Bereich liefert einen hohen Reiz, das Gewicht darf dabei nicht aufsetzen.","Schulterblätter nach hinten und unten am Polster fixieren und die Brust leicht anheben, damit die Bewegung aus der Brust und nicht aus der vorderen Schulter kommt.","Ellenbogen etwa 45 bis 60 Grad vom Rumpf abgespreizt halten; weit abgespreizte Ellenbogen belasten die Schulter, eng anliegende verlagern die Arbeit auf den Trizeps.","Beim Drücken kurz vor der Streckung stoppen und zwei bis drei Sekunden lang zurückführen, ohne mit Schwung aus der hinteren Position zu starten."],"requirements":["Brustpresse (Sitzmaschine) mit verstellbarem Sitz"],"grip_alternatives":[],"image_url":"/exercises/chest-press.jpg","machine_name":"DHZ Chest Press, Steckgewicht","alternative_exercises":["brustpresse-vertikal","brustpresse-hebel","brustpresse-hebel-sitzend","multi-press-maschine"]}$seed$::jsonb);

-- Pec Deck
select public.upsert_seed_exercise($seed${"slug":"pec-deck","name":"Pec Deck","category":"chest","equipment":"machine","grip_id":null,"grip_notes":"Unterarme liegen an den Polstern an, Hände halten die Griffe locker oder liegen flach auf. Nicht mit den Händen drücken, die Kraft kommt aus den Unterarmen und Ellenbogen.","primary_muscles":["chest"],"secondary_muscles":["front_delts"],"description":"Geführte Adduktionsbewegung an der Maschine mit Armpolstern, bei der die Brust ohne Belastung der Handgelenke isoliert wird. Geeignet als Isolationsübung nach den Druckübungen.","setup":["Sitz so einstellen, dass die Polster etwa auf Höhe der mittleren Brust liegen und die Oberarme waagerecht sind.","Rücken und Kopf an das Polster anlehnen, Füße flach auf den Boden stellen.","Unterarme an die Polster legen, Ellenbogen etwa 90 Grad gebeugt.","Schulterblätter nach hinten und unten ziehen, Brust leicht anheben.","Startposition so wählen, dass eine leichte Dehnung in der Brust spürbar ist."],"execution":["Polster über die Ellenbogen kontrolliert vor dem Körper zusammenführen.","Vorstellen, die Ellenbogen zueinander zu bringen statt die Hände.","In der Endposition kurz halten und die Brust bewusst anspannen.","Polster langsam zurückführen, bis die Oberarme etwa in der Schulterlinie sind.","Schulterblätter bleiben während der gesamten Bewegung hinten.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer leichten Dehnung mit den Oberarmen etwa in der Schulterlinie bis zum Zusammenführen der Polster vor der Brust. Nicht weiter nach hinten öffnen, als die Schultern schmerzfrei zulassen.","breathing":"Beim Zusammenführen ausatmen, beim Öffnen einatmen.","common_mistakes":["Schultern rollen nach vorne, Schulterblätter lösen sich vom Polster.","Bewegung wird aus den Händen statt aus den Ellenbogen geführt.","Polster werden zu weit nach hinten geöffnet, Schulter wird überdehnt.","Gewicht fällt in der exzentrischen Phase unkontrolliert zurück.","Sitz zu niedrig, Ellenbogen liegen deutlich über der Schulterlinie."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang ausführen.","In der Endposition eine Sekunde halten, um die Kontraktion zu betonen.","Leichtes bis mittleres Gewicht wählen, der Fokus liegt auf der Muskelspannung."],"cable_setup":null,"muscle_focus":["Startposition so wählen, dass die Oberarme etwa in der Schulterlinie sind und die Brust leicht gedehnt ist; dieser gedehnte Bereich trägt nach aktuellem Stand stark zum Muskelaufbau bei.","Druck über die Ellenbogen und Unterarme an die Polster geben, nicht über die Hände, und die Ellenbogen zueinander führen.","Schulterblätter nach hinten und unten halten und nicht nach vorne rollen, sonst übernimmt die vordere Schulter.","Zwei bis drei Sekunden lang öffnen, in der Endposition kurz halten und das Gewicht so wählen, dass die Brust und nicht die Schulter limitiert."],"requirements":["Pec-Deck-Maschine mit Armpolstern und verstellbarem Sitz"],"grip_alternatives":[],"image_url":"/exercises/pec-deck-rear-delt.jpg","machine_name":"DHZ Pectoral Fly / Rear Delt, Steckgewicht","alternative_exercises":["butterfly","kabel-flys"]}$seed$::jsonb);

-- Butterfly
select public.upsert_seed_exercise($seed${"slug":"butterfly","name":"Butterfly","category":"chest","equipment":"machine","grip_id":null,"grip_notes":"Handgriffe neutral oder leicht proniert fassen, je nach Maschine. Arme fast gestreckt mit leichter Ellenbogenbeuge, Handgelenke gerade.","primary_muscles":["chest"],"secondary_muscles":["front_delts","biceps"],"description":"Geführte Fly-Bewegung an der Maschine mit Handgriffen und fast gestreckten Armen, die die Brust über einen großen Bewegungsradius dehnt und kontrahiert. Geeignet als Isolationsübung für die Brust.","setup":["Sitz so einstellen, dass die Griffe etwa auf Höhe der mittleren Brust bis Schulter liegen.","Rücken und Kopf an das Polster anlehnen, Füße flach auf den Boden stellen.","Griffe fassen, Arme fast gestreckt mit leichter Beuge im Ellenbogen.","Schulterblätter nach hinten und unten ziehen, Brust leicht anheben.","Startposition so wählen, dass eine leichte Dehnung der Brust spürbar ist."],"execution":["Griffe in einem weiten Bogen vor der Brust zusammenführen.","Ellenbogenwinkel während der gesamten Bewegung konstant halten.","In der Endposition kurz halten und die Brust anspannen.","Griffe langsam und kontrolliert zurückführen, bis die Hände etwa in der Schulterlinie sind.","Schulterblätter bleiben hinten am Polster.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer leichten Dehnung mit den Händen etwa in der Schulterlinie bis zum Zusammenführen der Griffe vor der Brust. Die Öffnung nicht erzwingen, Bewegungsradius an die Schulterbeweglichkeit anpassen.","breathing":"Beim Zusammenführen ausatmen, beim Öffnen einatmen.","common_mistakes":["Ellenbogen werden während der Bewegung stark gebeugt, die Übung wird zur Druckbewegung.","Griffe werden zu weit nach hinten geöffnet, Schulter wird überdehnt.","Schultern rollen beim Zusammenführen nach vorne.","Gewicht wird mit Schwung aus der Dehnposition geführt.","Rücken löst sich vom Polster, um mehr Gewicht zu bewegen."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Leichtes bis mittleres Gewicht wählen, der Fokus liegt auf Dehnung und Kontraktion.","Bei Beschwerden im Ellenbogen oder Bizeps auf die Pec-Deck-Variante mit Armpolstern wechseln."],"cable_setup":null,"muscle_focus":["Griffe so weit öffnen, dass die Hände etwa in der Schulterlinie sind und die Brust spürbar gedehnt wird; nicht weiter, als die Schulter zulässt.","Ellenbogenwinkel über die gesamte Bewegung konstant halten, damit die Arbeit aus der Schulteradduktion und nicht aus Drücken oder Armbeugen kommt.","Schulterblätter am Polster halten und die Brust angehoben lassen, sodass die Brust und nicht die vordere Schulter die Bewegung führt.","Exzentrische Phase zwei bis drei Sekunden lang kontrollieren und ein Gewicht wählen, bei dem die Brust limitiert."],"requirements":["Butterfly-Maschine mit Handgriffen und verstellbarem Sitz"],"grip_alternatives":[],"image_url":"/exercises/pec-deck-rear-delt.jpg","machine_name":"DHZ Pectoral Fly / Rear Delt, Steckgewicht","alternative_exercises":["pec-deck","kabel-flys"]}$seed$::jsonb);

-- Kabel-Flys
select public.upsert_seed_exercise($seed${"slug":"kabel-flys","name":"Kabel-Flys","category":"chest","equipment":"cable","grip_id":"single_handle","grip_notes":"Einzelgriffe in beiden Händen, neutraler Griff (Handflächen zeigen zueinander oder leicht nach vorne). Alternativ Handschlaufen, um den Griff zu entlasten, oder ohne Griff direkt am Kabelende.","primary_muscles":["chest"],"secondary_muscles":["front_delts"],"description":"Fly-Bewegung am Doppelkabelzug mit Rollen auf Schulter- bis Brusthöhe, die die Brust horizontal mit konstanter Spannung belastet. Geeignet als Isolationsübung mit gleichmäßigem Widerstand über den gesamten Bewegungsradius.","setup":["Beide Rollen des Doppelkabelzugs auf Schulter- bis Brusthöhe einstellen und Einzelgriffe einhängen.","Einen Griff nach dem anderen fassen und einen Schritt nach vorne in die Mitte gehen.","Schrittstellung einnehmen, Rumpf anspannen, Oberkörper leicht nach vorne geneigt.","Arme seitlich mit leichter Ellenbogenbeuge halten, Hände etwa in der Schulterlinie.","Schulterblätter nach hinten und unten ziehen, Brust leicht anheben."],"execution":["Griffe in einem weiten Bogen vor der Brust zusammenführen.","Ellenbogenwinkel während der gesamten Bewegung konstant halten.","In der Endposition die Hände vor der Brust zusammenbringen und die Brust anspannen.","Griffe langsam und kontrolliert zurückführen, bis die Hände wieder etwa in der Schulterlinie sind.","Oberkörper und Rumpf bleiben während der Bewegung stabil.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer leichten Dehnung mit den Händen etwa in der Schulterlinie bis zum Zusammenführen der Hände vor der Brust. Die Dehnposition nicht erzwingen.","breathing":"Beim Zusammenführen ausatmen, beim Öffnen einatmen.","common_mistakes":["Ellenbogen werden stark gebeugt, die Bewegung wird zum Drücken.","Oberkörper schwingt mit und erzeugt Schwung aus dem Rumpf.","Schultern rollen beim Zusammenführen nach vorne.","Hände werden zu weit nach hinten geführt, Schulter wird überdehnt.","Gewicht zieht die Arme in der exzentrischen Phase unkontrolliert zurück."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Leichtes bis mittleres Gewicht wählen, da die Hebelverhältnisse ungünstig sind.","Hände in der Endposition leicht überkreuzen, um die Kontraktion zu verlängern.","Schrittstellung von Satz zu Satz wechseln, um einseitige Belastung zu vermeiden."],"cable_setup":{"cable":"Kabelturm mit zwei Säulen (Doppelkabelzug / Cable Crossover)","height":"Schulterhöhe (bis Brusthöhe), damit das Kabel in Verlängerung der Arme läuft und die Zugrichtung waagerecht durch die mittlere Brust geht","grip_width":"Einzelgriffe, neutraler Griff, Hände starten etwa in der Schulterlinie","body_position":"Stehend in der Mitte zwischen den Säulen, Oberkörper leicht nach vorne geneigt, Rumpf angespannt, Schulterblätter hinten und unten","foot_position":"Schrittstellung, vorderer Fuß flach, hinterer Fuß auf dem Ballen, Knie leicht gebeugt","movement_direction":"Horizontal in einem Bogen von außen nach vorne-innen vor die Brust","elbow_position":"Leicht gebeugt, Winkel bleibt über die gesamte Bewegung konstant","end_position":"Hände vor der Brust zusammengeführt, Brust angespannt, Schultern bleiben hinten","return":"Langsam und kontrolliert, bis die Hände etwa in der Schulterlinie sind und eine leichte Dehnung spürbar ist"},"muscle_focus":["Rollen auf Schulterhöhe stellen, sodass die Zugrichtung waagerecht durch die mittlere Brust läuft; so bleibt die Spannung auch in der gedehnten Position hoch.","Hände beim Öffnen bis in die Schulterlinie zurückführen und dort kurz halten; der gedehnte Bereich liefert einen hohen Reiz, die Position aber nicht erzwingen.","Ellenbogenwinkel konstant lassen und Schulterblätter nach hinten und unten halten, sonst wird die Übung zum Drücken und die vordere Schulter übernimmt.","Zwei bis drei Sekunden lang zurückführen, Oberkörper ruhig lassen und das Gewicht so wählen, dass die Brust und nicht der Rumpf limitiert."],"requirements":["Kabelturm mit zwei Säulen (Doppelkabelzug) und verstellbaren Rollen","Zwei Einzelgriffe (D-Griffe)"],"grip_alternatives":["strap_handle"],"alternative_exercises":[]}$seed$::jsonb);

-- Kabel-Flys von unten
select public.upsert_seed_exercise($seed${"slug":"kabel-flys-von-unten","name":"Kabel-Flys von unten","category":"chest","equipment":"cable","grip_id":"single_handle","grip_notes":"Einzelgriffe in beiden Händen, neutraler Griff (Handflächen zeigen zueinander bzw. nach oben). Alternativ Handschlaufen oder ohne Griff direkt am Kabelende.","primary_muscles":["upper_chest","chest"],"secondary_muscles":["front_delts"],"description":"Fly-Bewegung am Doppelkabelzug mit Rollen in der unteren Position, bei der die Arme von unten nach oben-vorne zusammengeführt werden. Belastet vor allem den oberen Anteil der Brust.","setup":["Beide Rollen des Doppelkabelzugs in die unterste Position bringen und Einzelgriffe einhängen.","Griffe fassen und einen Schritt nach vorne in die Mitte gehen.","Schrittstellung einnehmen, Rumpf anspannen, Oberkörper aufrecht oder leicht nach vorne geneigt.","Arme seitlich-unten mit leichter Ellenbogenbeuge halten, Handflächen zeigen nach vorne-oben.","Schulterblätter nach hinten und unten ziehen, Brust leicht anheben."],"execution":["Griffe in einem Bogen von unten nach oben-vorne zusammenführen.","Ellenbogenwinkel während der gesamten Bewegung konstant halten.","In der Endposition die Hände etwa auf Höhe der oberen Brust bis Kinn zusammenbringen.","Obere Brust kurz bewusst anspannen.","Griffe langsam und kontrolliert nach unten-außen zurückführen.","Oberkörper bleibt stabil, kein Mitschwingen aus dem Rumpf.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von den seitlich-unten gehaltenen Armen bis die Hände vor der oberen Brust zusammenkommen. Nicht über die Schulterhöhe hinaus führen, um die Schultern nicht unnötig zu belasten.","breathing":"Beim Zusammenführen nach oben ausatmen, beim Zurückführen einatmen.","common_mistakes":["Schultern ziehen beim Anheben nach oben zum Ohr.","Bewegung wird zum Frontheben, Ellenbogen stark gebeugt und Arme vor dem Körper angehoben.","Oberkörper lehnt sich nach hinten, um das Gewicht zu bewegen.","Hände werden in der Endposition deutlich über die Schulter geführt.","Gewicht zieht die Arme unkontrolliert nach unten zurück."],"tips":["Leichtes Gewicht wählen und in der Endposition eine Sekunde halten.","Vorstellen, die Oberarme zueinander zu führen, nicht die Hände nach oben zu heben.","Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren."],"cable_setup":{"cable":"Kabelturm mit zwei Säulen (Doppelkabelzug / Cable Crossover)","height":"ganz unten, damit die Zugrichtung von unten-außen nach oben-innen entlang der Fasern der oberen Brust verläuft","grip_width":"Einzelgriffe, neutraler Griff, Hände starten seitlich-unten neben den Hüften","body_position":"Stehend in der Mitte zwischen den Säulen, Oberkörper aufrecht bis leicht nach vorne geneigt, Rumpf angespannt, Schulterblätter hinten und unten","foot_position":"Schrittstellung, Knie leicht gebeugt, Gewicht gleichmäßig verteilt","movement_direction":"Von unten-außen in einem Bogen nach oben-vorne vor die obere Brust","elbow_position":"Leicht gebeugt, Winkel bleibt konstant, Ellenbogen zeigen leicht nach außen-unten","end_position":"Hände vor der oberen Brust bis Kinnhöhe zusammengeführt, obere Brust angespannt, Schultern unten","return":"Langsam und kontrolliert nach unten-außen bis zur Startposition neben den Hüften"},"muscle_focus":["Rollen ganz unten, sodass die Zugrichtung von unten-außen nach oben-innen entlang der Fasern der oberen Brust verläuft.","Startposition mit Händen seitlich neben den Hüften und leichter Dehnung einnehmen; aus dieser gedehnten Position kommt ein hoher Reiz für die obere Brust.","Oberarme in einem Bogen zueinander führen und die Ellenbogenbeuge konstant halten, sonst wird die Übung zum Frontheben für die vordere Schulter.","Schultern unten halten, Endposition auf Höhe der oberen Brust kurz halten und zwei bis drei Sekunden lang nach unten-außen zurückführen."],"requirements":["Kabelturm mit zwei Säulen (Doppelkabelzug) und verstellbaren Rollen","Zwei Einzelgriffe (D-Griffe)"],"grip_alternatives":["strap_handle"],"alternative_exercises":[]}$seed$::jsonb);

-- Kabel-Flys von oben
select public.upsert_seed_exercise($seed${"slug":"kabel-flys-von-oben","name":"Kabel-Flys von oben","category":"chest","equipment":"cable","grip_id":"single_handle","grip_notes":"Einzelgriffe in beiden Händen, neutraler Griff (Handflächen zeigen zueinander bzw. nach unten-innen). Alternativ Handschlaufen oder ohne Griff direkt am Kabelende.","primary_muscles":["chest"],"secondary_muscles":["front_delts","triceps"],"description":"Fly-Bewegung am Doppelkabelzug mit Rollen in der oberen Position, bei der die Arme von oben nach unten-vorne zusammengeführt werden. Belastet vor allem den unteren Anteil der Brust.","setup":["Beide Rollen des Doppelkabelzugs in die oberste Position bringen und Einzelgriffe einhängen.","Griffe fassen und einen Schritt nach vorne in die Mitte gehen.","Schrittstellung einnehmen, Rumpf anspannen, Oberkörper leicht nach vorne geneigt.","Arme seitlich-oben mit leichter Ellenbogenbeuge halten, Hände etwas über Schulterhöhe.","Schulterblätter nach hinten und unten ziehen, Brust leicht anheben."],"execution":["Griffe in einem Bogen von oben nach unten-vorne zusammenführen.","Ellenbogenwinkel während der gesamten Bewegung konstant halten.","In der Endposition die Hände etwa auf Höhe der unteren Brust bis Bauchnabel zusammenbringen.","Untere Brust kurz bewusst anspannen.","Griffe langsam und kontrolliert nach oben-außen zurückführen.","Oberkörper bleibt in seiner Neigung, kein Mitschwingen aus dem Rumpf.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von den seitlich-oben gehaltenen Armen mit leichter Dehnung bis die Hände vor der unteren Brust zusammenkommen. Die Dehnposition oben nicht erzwingen.","breathing":"Beim Zusammenführen nach unten ausatmen, beim Zurückführen einatmen.","common_mistakes":["Oberkörper wird stark nach vorne geklappt, die Bewegung kommt aus dem Rumpf.","Ellenbogen werden stark gebeugt, die Übung wird zum Drücken nach unten.","Schultern rollen beim Zusammenführen nach vorne.","Arme werden in der Startposition zu weit nach hinten geführt.","Gewicht zieht die Arme unkontrolliert nach oben zurück."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Hände in der Endposition leicht überkreuzen, um die Kontraktion zu verlängern.","Leichtes bis mittleres Gewicht wählen, der Fokus liegt auf der Muskelspannung.","Schrittstellung von Satz zu Satz wechseln."],"cable_setup":{"cable":"Kabelturm mit zwei Säulen (Doppelkabelzug / Cable Crossover)","height":"ganz oben, damit die Zugrichtung von oben-außen nach unten-innen entlang der Fasern der unteren Brust verläuft","grip_width":"Einzelgriffe, neutraler Griff, Hände starten seitlich etwas über Schulterhöhe","body_position":"Stehend in der Mitte zwischen den Säulen, Oberkörper etwa 15 bis 30 Grad nach vorne geneigt, Rumpf angespannt, Schulterblätter hinten und unten","foot_position":"Schrittstellung, vorderer Fuß flach, hinterer Fuß auf dem Ballen, Knie leicht gebeugt","movement_direction":"Von oben-außen in einem Bogen nach unten-vorne vor die untere Brust","elbow_position":"Leicht gebeugt, Winkel bleibt konstant, Ellenbogen zeigen nach außen-oben","end_position":"Hände vor der unteren Brust bis Bauchnabelhöhe zusammengeführt, untere Brust angespannt, Schultern bleiben hinten","return":"Langsam und kontrolliert nach oben-außen, bis eine leichte Dehnung in der Brust spürbar ist"},"muscle_focus":["Rollen ganz oben, sodass die Zugrichtung von oben-außen nach unten-innen entlang der Fasern der unteren Brust verläuft.","Arme in der Startposition seitlich-oben bis zu einer leichten Dehnung zurückführen; dieser Bereich liefert einen hohen Reiz, die Position nicht erzwingen.","Oberkörper etwa 15 bis 30 Grad nach vorne geneigt halten und die Neigung während des Satzes nicht verändern, sonst kommt die Bewegung aus dem Rumpf.","Ellenbogenwinkel konstant halten, Schulterblätter hinten lassen und zwei bis drei Sekunden lang nach oben-außen zurückführen."],"requirements":["Kabelturm mit zwei Säulen (Doppelkabelzug) und verstellbaren Rollen","Zwei Einzelgriffe (D-Griffe)"],"grip_alternatives":["strap_handle"],"alternative_exercises":[]}$seed$::jsonb);

-- Schulterdrücken Maschine
select public.upsert_seed_exercise($seed${"slug":"schulterdruecken-maschine","name":"Schulterdrücken Maschine","category":"shoulders","equipment":"machine","grip_id":null,"grip_notes":"Pronierte Griffe (Handflächen nach vorne) oder neutrale Griffe, je nach Maschine. Neutrale Griffe sind meist schulterfreundlicher. Handgelenke gerade halten.","primary_muscles":["front_delts","side_delts"],"secondary_muscles":["triceps","traps"],"description":"Geführte vertikale Druckbewegung im Sitzen, die vor allem die vordere und seitliche Schulter belastet. Geeignet als Grundübung für die Schulter mit stabiler Führung.","setup":["Sitz so einstellen, dass die Griffe in der Startposition etwa auf Schulterhöhe oder leicht darunter liegen.","Rücken und Kopf an das Polster anlehnen, Füße flach auf den Boden stellen.","Griffe fassen, Handgelenke gerade, Unterarme möglichst senkrecht.","Rumpf anspannen, Rippen nicht nach vorne herausdrücken.","Schultern bewusst nach unten ziehen, nicht zu den Ohren hochziehen."],"execution":["Griffe kontrolliert nach oben drücken.","Ellenbogen am Ende nicht hart durchstrecken.","Schultern während des Drückens unten lassen, nicht hochziehen.","Gewicht langsam zurückführen, bis die Griffe etwa auf Schulterhöhe sind.","Rücken bleibt während der gesamten Bewegung am Polster.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von den Griffen etwa auf Schulterhöhe bis kurz vor die vollständige Armstreckung. Unten nur so tief, wie die Schultern schmerzfrei bleiben.","breathing":"Beim Drücken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Schultern werden beim Drücken zu den Ohren hochgezogen.","Rücken wölbt sich stark ins Hohlkreuz, Rippen werden herausgedrückt.","Sitz zu hoch, Griffe liegen deutlich unter der Schulter.","Ellenbogen werden am Ende hart durchgestreckt.","Gewicht wird mit Schwung aus der unteren Position gedrückt."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Bei Beschwerden in der Schulter neutrale Griffe wählen oder Sitz etwas höher stellen.","Erst Gewicht erhöhen, wenn alle Sätze sauber und ohne Hohlkreuz ausgeführt werden."],"cable_setup":null,"muscle_focus":["Griffe in der unteren Position bis etwa auf Schulterhöhe absenken, damit die vordere und seitliche Schulter über den vollen Bewegungsradius arbeitet; nur so tief, wie die Schulter schmerzfrei zulässt.","Unterarme möglichst senkrecht unter den Griffen führen und die Ellenbogen leicht vor der Schulterlinie halten, das entlastet das Schultergelenk.","Schultern während des Drückens unten lassen und nicht zu den Ohren ziehen, sonst übernimmt der Trapezmuskel einen Teil der Arbeit.","Rumpf anspannen und Rippen nicht herausdrücken, oben kurz vor dem Durchstrecken stoppen und zwei Sekunden lang zurückführen."],"requirements":["Schulterdrück-Maschine mit verstellbarem Sitz und Rückenlehne"],"grip_alternatives":[],"image_url":"/exercises/shoulder-press-plate.jpg","machine_name":"DHZ Shoulder Press, Plate Loaded","alternative_exercises":["schulterpresse-maschine","multi-press-maschine"]}$seed$::jsonb);

-- Seitheben Maschine
select public.upsert_seed_exercise($seed${"slug":"seitheben-maschine","name":"Seitheben Maschine","category":"shoulders","equipment":"machine","grip_id":null,"grip_notes":"Polster liegen an den Oberarmen knapp oberhalb der Ellenbogen an. Griffe locker fassen oder Hände nur anlegen, nicht mit den Händen heben.","primary_muscles":["side_delts"],"secondary_muscles":["traps"],"description":"Geführtes Seitheben an der Maschine mit Polstern an den Oberarmen, das die seitliche Schulter isoliert. Geeignet für kontrollierte Isolationsarbeit ohne Ausweichbewegungen des Rumpfes.","setup":["Sitz so einstellen, dass die Drehachse der Maschine etwa auf Höhe der Schultergelenke liegt.","Oberkörper aufrecht an das Polster anlehnen, Füße flach auf den Boden stellen.","Oberarme an die Polster legen, Ellenbogen etwa 90 Grad gebeugt.","Schultern bewusst nach unten ziehen, Brust leicht anheben.","Rumpf anspannen."],"execution":["Oberarme über die Polster seitlich nach oben führen.","Bewegung aus den Ellenbogen führen, nicht aus den Händen.","Bis etwa Schulterhöhe anheben, Schultern bleiben unten.","In der Endposition kurz halten.","Arme langsam und kontrolliert zurückführen.","Gewicht unten nicht aufsetzen lassen, Spannung halten."],"range_of_motion":"Von den Oberarmen neben dem Körper bis etwa Schulterhöhe. Nicht über die Schulterhöhe hinaus heben, da dann vermehrt der Trapezmuskel übernimmt.","breathing":"Beim Anheben ausatmen, beim Absenken einatmen.","common_mistakes":["Schultern werden beim Anheben zu den Ohren hochgezogen.","Oberarme werden über die Schulterhöhe hinaus gehoben.","Sitz zu niedrig oder zu hoch, Drehachse stimmt nicht mit der Schulter überein.","Gewicht fällt in der exzentrischen Phase unkontrolliert zurück.","Oberkörper lehnt sich nach hinten, um das Gewicht zu bewegen."],"tips":["Leichtes bis mittleres Gewicht wählen, der Fokus liegt auf der seitlichen Schulter.","Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","In der Endposition eine Sekunde halten."],"cable_setup":null,"muscle_focus":["Drehachse der Maschine auf Höhe der Schultergelenke einstellen, sonst passt der Bewegungsbogen nicht zur Schulter und der Widerstand verschiebt sich.","Bewegung über die Ellenbogen gegen die Polster führen und die Oberarme nur bis etwa Schulterhöhe heben; darüber übernimmt zunehmend der Trapezmuskel.","Schultern während des gesamten Satzes nach unten ziehen und den Oberkörper aufrecht am Polster lassen, kein Mitschwingen aus dem Rumpf.","Zwei bis drei Sekunden lang absenken, unten die Spannung halten und das Gewicht so wählen, dass die seitliche Schulter limitiert."],"requirements":["Seitheben-Maschine mit Armpolstern und verstellbarem Sitz"],"grip_alternatives":[],"alternative_exercises":["seitheben-kabel"]}$seed$::jsonb);

-- Seitheben Kabel
select public.upsert_seed_exercise($seed${"slug":"seitheben-kabel","name":"Seitheben Kabel","category":"shoulders","equipment":"cable","grip_id":"strap_handle","grip_notes":"Handschlaufe um die Hand legen, Hand bleibt locker, der Arm hängt entspannt. Alternativ Einzelgriff mit lockerem Daumen oder ohne Griff direkt am Kabelende.","primary_muscles":["side_delts"],"secondary_muscles":["traps","front_delts"],"description":"Einarmiges Seitheben am Kabelzug mit der Rolle unten und Handschlaufe, das die seitliche Schulter mit konstanter Spannung belastet. Geeignet als Isolationsübung mit gleichmäßigem Widerstand auch in der unteren Position.","setup":["Rolle auf Hüfthöhe einstellen und Handschlaufe einhängen.","Seitlich zur Säule stellen, die arbeitende Hand ist von der Säule abgewandt.","Schlaufe um die Hand legen, Hand locker lassen, das Kabel läuft vor oder hinter dem Körper zur Säule.","Freie Hand an der Säule abstützen, Rumpf anspannen, Oberkörper aufrecht.","Arm mit leichter Ellenbogenbeuge entspannt neben dem Körper hängen lassen, Schulter bewusst nach unten ziehen."],"execution":["Arm seitlich nach oben führen, der Ellenbogen führt die Bewegung.","Bis etwa Schulterhöhe anheben, Hand und Ellenbogen etwa auf gleicher Höhe.","Schulter bleibt während der gesamten Bewegung unten.","In der Endposition kurz halten.","Arm langsam und kontrolliert zurückführen, bis er wieder neben dem Körper ist.","Spannung unten halten, Gewicht nicht aufsetzen lassen.","Nach dem Satz die Seite wechseln."],"range_of_motion":"Vom Arm neben bzw. leicht vor dem Körper bis etwa Schulterhöhe. Nicht über die Schulterhöhe hinaus heben.","breathing":"Beim Anheben ausatmen, beim Absenken einatmen.","common_mistakes":["Schulter wird beim Anheben zum Ohr hochgezogen.","Oberkörper neigt sich zur Seite oder schwingt mit.","Arm wird über die Schulterhöhe hinaus gehoben.","Hand liegt in der Endposition deutlich über dem Ellenbogen.","Gewicht zieht den Arm unkontrolliert zurück."],"tips":["Leichtes Gewicht wählen, die Übung reagiert empfindlich auf Schwung.","Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Vorstellen, den Ellenbogen zur Seite wegzuschieben, nicht die Hand anzuheben.","Kabel hinter dem Körper führen, wenn die seitliche Schulter stärker isoliert werden soll."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einarmig","height":"Hüfthöhe, damit das Kabel über den gesamten Weg seitlich am Körper vorbei zieht und die Spannung auch unten erhalten bleibt","grip_width":"Handschlaufe um eine Hand, Hand locker, kein aktives Greifen","body_position":"Seitlich zur Säule stehend, aufrecht, freie Hand an der Säule abgestützt, Rumpf angespannt, Schulter unten","foot_position":"Hüftbreit oder leichte Schrittstellung, Knie leicht gebeugt","movement_direction":"Seitlich nach oben in einem Bogen bis etwa Schulterhöhe","elbow_position":"Leicht gebeugt, Winkel bleibt konstant, Ellenbogen führt die Bewegung und bleibt auf Höhe der Hand oder leicht darüber","end_position":"Oberarm etwa waagerecht auf Schulterhöhe, Schulter unten, kurz halten","return":"Langsam und kontrolliert zurück neben den Körper, Spannung am Kabel bleibt erhalten"},"muscle_focus":["Rolle ganz unten und Kabel hinter dem Körper führen, sodass der Arm in der Startposition leicht vor dem Körper hängt; so steht die seitliche Schulter schon in der gedehnten Position unter Spannung.","Bewegung über den Ellenbogen seitlich nach außen führen, Hand und Ellenbogen auf gleicher Höhe, nur bis etwa Schulterhöhe heben; darüber übernimmt der Trapezmuskel.","Schulter während des gesamten Satzes unten halten und den Oberkörper nicht zur Seite neigen; die Handschlaufe hält die Hand passiv, sodass der Unterarm nicht mitarbeitet.","Zwei bis drei Sekunden lang absenken, unten die Spannung halten und ein Gewicht wählen, bei dem die seitliche Schulter limitiert."],"requirements":["Kabelturm mit verstellbarer Rolle","Handschlaufe (alternativ Einzelgriff)"],"grip_alternatives":["single_handle"],"alternative_exercises":["seitheben-maschine"]}$seed$::jsonb);

-- Reverse Butterfly
select public.upsert_seed_exercise($seed${"slug":"reverse-butterfly","name":"Reverse Butterfly","category":"shoulders","equipment":"machine","grip_id":null,"grip_notes":"Neutrale Griffe (Handflächen zeigen zueinander) oder pronierte Griffe, je nach Maschine. Griffe locker fassen, Handgelenke gerade, die Bewegung kommt aus den Ellenbogen und Schulterblättern.","primary_muscles":["rear_delts"],"secondary_muscles":["upper_back","traps","mid_back"],"description":"Geführte Reverse-Fly-Bewegung an der umgekehrten Pec-Deck-Maschine, die die hintere Schulter und den oberen Rücken belastet. Geeignet als Isolationsübung für die hintere Schulter und als Ausgleich zu Druckübungen.","setup":["Griffe der Maschine in die vordere Position stellen, sodass die Arme vor dem Körper starten.","Sitz so einstellen, dass die Griffe etwa auf Schulterhöhe liegen.","Mit der Brust zum Polster setzen, Brustbein am Polster anlehnen, Füße flach auf den Boden stellen.","Griffe fassen, Arme fast gestreckt mit leichter Ellenbogenbeuge.","Schultern nach unten ziehen, Rumpf anspannen."],"execution":["Griffe in einem weiten Bogen nach hinten-außen führen.","Ellenbogenwinkel während der gesamten Bewegung konstant halten.","Bewegung aus der hinteren Schulter und den Schulterblättern führen, nicht aus den Händen.","In der Endposition kurz halten, Hände etwa in der Schulterlinie oder leicht dahinter.","Griffe langsam und kontrolliert nach vorne zurückführen.","Brust bleibt am Polster, Gewicht vorne nicht aufsetzen lassen."],"range_of_motion":"Von den Armen vor dem Körper bis die Hände etwa in der Schulterlinie oder leicht dahinter sind. Nicht weiter nach hinten erzwingen.","breathing":"Beim Öffnen nach hinten ausatmen, beim Zurückführen einatmen.","common_mistakes":["Schultern werden zu den Ohren hochgezogen.","Ellenbogen werden stark gebeugt, die Übung wird zum Rudern.","Brust löst sich vom Polster, Oberkörper schwingt mit.","Gewicht wird mit Schwung nach hinten gerissen.","Gewicht fällt in der exzentrischen Phase unkontrolliert zurück."],"tips":["Leichtes bis mittleres Gewicht wählen, die hintere Schulter ist ein kleiner Muskel.","Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Vorstellen, die Ellenbogen nach hinten-außen zu ziehen.","Neutraler Griff legt den Fokus stärker auf die hintere Schulter, pronierter Griff mehr auf den oberen Rücken."],"cable_setup":null,"muscle_focus":["Griffe vorne so einstellen, dass die Arme vor dem Körper starten und die hintere Schulter in der Startposition gedehnt ist; aus dieser Position kommt ein hoher Reiz.","Bewegung aus der hinteren Schulter nach hinten-außen führen, Ellenbogenwinkel konstant halten, Hände nur bis in die Schulterlinie bringen; darüber hinaus übernimmt der obere Rücken.","Schultern unten lassen, Brust am Polster halten und nicht mit den Armen ziehen, sonst wird die Übung zum Rudern.","Zwei bis drei Sekunden lang zurückführen und ein leichtes Gewicht wählen, bei dem die hintere Schulter limitiert."],"requirements":["Reverse-Butterfly-Maschine (umgekehrtes Pec Deck) mit verstellbarem Sitz und Griffen"],"grip_alternatives":[],"image_url":"/exercises/pec-deck-rear-delt.jpg","machine_name":"DHZ Pectoral Fly / Rear Delt, Steckgewicht (Rear-Delt-Stellung)","alternative_exercises":["kabel-reverse-fly","reverse-fly-kurzhantel"]}$seed$::jsonb);

-- Kabel Reverse Fly
select public.upsert_seed_exercise($seed${"slug":"kabel-reverse-fly","name":"Kabel Reverse Fly","category":"shoulders","equipment":"cable","grip_id":"single_handle","grip_notes":"Einzelgriffe (alternativ Handschlaufen) oder ohne Griff direkt am Kabelende bzw. an der Kugel fassen. Kabel überkreuz greifen: die rechte Hand hält das linke Kabel, die linke Hand das rechte Kabel.","primary_muscles":["rear_delts"],"secondary_muscles":["upper_back","traps"],"description":"Reverse-Fly-Bewegung am Doppelkabelzug mit Rollen auf Schulterhöhe und überkreuz gegriffenen Kabeln. Belastet die hintere Schulter mit konstanter Spannung und eignet sich als Isolationsübung für den hinteren Schulteranteil.","setup":["Beide Rollen des Doppelkabelzugs auf Schulterhöhe einstellen, Einzelgriffe einhängen oder Kabelenden direkt nutzen.","In die Mitte zwischen die Säulen stellen und die Kabel überkreuz fassen.","Einen Schritt zurückgehen, bis die Kabel unter Spannung sind.","Hüftbreiter Stand oder leichte Schrittstellung, Rumpf anspannen, Oberkörper aufrecht.","Arme vor der Brust fast gestreckt mit leichter Ellenbogenbeuge halten, Schultern nach unten ziehen."],"execution":["Arme in einem weiten Bogen nach außen-hinten führen.","Ellenbogenwinkel während der gesamten Bewegung konstant halten.","Bewegung aus der hinteren Schulter führen, Schulterblätter am Ende leicht zusammenziehen.","In der Endposition kurz halten, Hände etwa in der Schulterlinie.","Arme langsam und kontrolliert nach vorne zurückführen, bis sich die Hände wieder vor der Brust überkreuzen.","Oberkörper bleibt stabil, kein Mitschwingen."],"range_of_motion":"Von den vor der Brust überkreuzten Armen bis die Hände etwa in der Schulterlinie sind. Nicht weiter nach hinten erzwingen.","breathing":"Beim Öffnen nach außen ausatmen, beim Zurückführen einatmen.","common_mistakes":["Schultern werden zu den Ohren hochgezogen.","Ellenbogen werden stark gebeugt, die Übung wird zum Rudern.","Oberkörper lehnt sich nach hinten, um das Gewicht zu bewegen.","Gewicht zieht die Arme in der exzentrischen Phase unkontrolliert zurück.","Zu viel Gewicht, der Bewegungsradius wird deutlich kleiner."],"tips":["Leichtes Gewicht wählen und auf saubere Ausführung achten.","Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Vorstellen, die Hände an eine Wand hinter dem Körper zu führen."],"cable_setup":{"cable":"Kabelturm mit zwei Säulen (Doppelkabelzug / Cable Crossover)","height":"Schulterhöhe, damit die Zugrichtung waagerecht in Verlängerung der Arme durch die hintere Schulter verläuft","grip_width":"Kabel überkreuz gegriffen, Einzelgriffe oder direkt am Kabelende, neutraler Griff","body_position":"Stehend in der Mitte zwischen den Säulen, aufrecht, Rumpf angespannt, Schultern unten, Arme vor der Brust","foot_position":"Hüftbreit oder leichte Schrittstellung, Knie leicht gebeugt","movement_direction":"Horizontal in einem Bogen von vorne nach außen-hinten","elbow_position":"Leicht gebeugt, Winkel bleibt konstant, Ellenbogen etwa auf Schulterhöhe","end_position":"Arme seitlich etwa in der Schulterlinie, Schulterblätter leicht zusammengezogen, kurz halten","return":"Langsam und kontrolliert nach vorne, bis sich die Hände vor der Brust wieder überkreuzen, Spannung bleibt erhalten"},"muscle_focus":["Rollen auf Schulterhöhe und Kabel überkreuz greifen, sodass die Arme vor der Brust starten und die hintere Schulter in der gedehnten Position unter Spannung steht.","Arme in einem weiten Bogen nach außen führen, Ellenbogen etwa auf Schulterhöhe und Ellenbogenwinkel konstant; stark gebeugte Ellenbogen machen daraus ein Rudern für den Rücken.","Schultern unten halten und die Schulterblätter erst am Ende leicht zusammenziehen, nicht die gesamte Bewegung aus dem Schulterblatt führen.","Zwei bis drei Sekunden lang zurückführen, bis sich die Hände wieder überkreuzen, und ein leichtes Gewicht wählen, bei dem die hintere Schulter limitiert."],"requirements":["Kabelturm mit zwei Säulen (Doppelkabelzug) und verstellbaren Rollen","Zwei Einzelgriffe (D-Griffe) oder direkt an den Kabelenden"],"grip_alternatives":["strap_handle"],"alternative_exercises":[]}$seed$::jsonb);

-- Face Pull
select public.upsert_seed_exercise($seed${"slug":"face-pull","name":"Face Pull","category":"shoulders","equipment":"cable","grip_id":"rope","grip_notes":"Seilgriff mit neutralem Griff, Daumen zeigen zum Körper. Alternativ Handflächen nach unten (proniert) fassen, dann liegt der Fokus stärker auf dem oberen Rücken. Ohne Seil: zwei Einzelgriffe am selben Karabiner, überkreuz gefasst (rechte Hand am linken Griff).","primary_muscles":["rear_delts"],"secondary_muscles":["upper_back","traps","side_delts"],"description":"Zugübung am Kabelzug mit Seilgriff, bei der das Seil auf Gesichtshöhe zum Kopf gezogen wird. Belastet die hintere Schulter und den oberen Rücken und eignet sich als Ausgleichsübung zu Druckbewegungen.","setup":["Rolle auf Gesichts- bis Stirnhöhe einstellen und Seilgriff einhängen.","Seil mit neutralem Griff fassen, Daumen zeigen zum Körper.","Ein bis zwei Schritte zurückgehen, bis das Kabel unter Spannung ist.","Hüftbreiter Stand oder Schrittstellung, Rumpf anspannen, Oberkörper aufrecht.","Arme gestreckt nach vorne, Schultern bewusst nach unten ziehen."],"execution":["Seil in Richtung Gesicht ziehen, Ellenbogen führen die Bewegung nach hinten-außen.","Seilenden auseinanderziehen, Hände kommen neben die Ohren.","Ellenbogen hoch auf Schulterhöhe und außen halten.","In der Endposition Schulterblätter zusammenziehen und kurz halten.","Seil langsam und kontrolliert zurückführen, Arme strecken.","Schultern am Ende leicht nach vorne kommen lassen, ohne den Oberkörper mitzuziehen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von vollständig gestreckten Armen bis die Hände neben den Ohren und die Ellenbogen etwa in der Schulterlinie sind. Nicht über die Schulterlinie hinaus ziehen.","breathing":"Beim Ziehen ausatmen, beim Zurückführen einatmen.","common_mistakes":["Ellenbogen sinken nach unten, die Übung wird zum Rudern.","Oberkörper lehnt sich nach hinten, Bewegung kommt aus dem Rumpf.","Schultern werden zu den Ohren hochgezogen.","Seil wird nur zum Gesicht gezogen, ohne die Enden auseinanderzuziehen.","Gewicht zieht die Arme unkontrolliert zurück."],"tips":["Leichtes bis mittleres Gewicht wählen und auf hohe Ellenbogen achten.","Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Vorstellen, in der Endposition eine Doppelbizeps-Pose einzunehmen.","Bei Platzmangel auch kniend oder im Halbkniestand ausführbar."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, eine Seite","height":"über Kopfhöhe (etwa Stirnhöhe oder knapp darüber), damit das Seil leicht von oben in Richtung Gesicht gezogen wird und die Ellenbogen auf Schulterhöhe bleiben","grip_width":"Seilgriff, neutraler Griff, Daumen zum Körper, Hände am Ende neben den Ohren","body_position":"Stehend mit ein bis zwei Schritten Abstand zur Säule, aufrecht, Rumpf angespannt, Schultern unten","foot_position":"Hüftbreit oder Schrittstellung, Knie leicht gebeugt","movement_direction":"Horizontal von vorne in Richtung Gesicht, Seilenden werden dabei nach außen gezogen","elbow_position":"Ellenbogen hoch etwa auf Schulterhöhe, zeigen nach außen und wandern nach hinten","end_position":"Hände neben den Ohren, Ellenbogen in der Schulterlinie, Schulterblätter zusammengezogen","return":"Langsam und kontrolliert bis zur vollen Armstreckung, Spannung am Kabel bleibt erhalten"},"muscle_focus":["Rolle über Kopfhöhe, Seil leicht von oben zum Gesicht ziehen und die Ellenbogen hoch auf Schulterhöhe nach außen-hinten führen; sinken die Ellenbogen, wird daraus ein Rudern für den Rücken.","Arme vorne vollständig strecken und die Schultern am Ende leicht nach vorne kommen lassen, damit die hintere Schulter aus der gedehnten Position arbeitet.","Seilenden am Ende auseinanderziehen und die Hände neben die Ohren bringen, Schulterblätter erst in der Endposition zusammenziehen.","Oberkörper aufrecht und ruhig halten, zwei bis drei Sekunden lang zurückführen und ein Gewicht wählen, bei dem die hintere Schulter und nicht der Rumpf limitiert."],"requirements":["Kabelturm mit verstellbarer Rolle","Seilgriff (alternativ zwei Einzelgriffe)"],"grip_alternatives":["single_handle"],"alternative_exercises":[]}$seed$::jsonb);

-- Neutraler Latzug
select public.upsert_seed_exercise($seed${"slug":"neutraler-latzug","name":"Neutraler Latzug","category":"back","equipment":"cable","grip_id":"neutral_parallel","grip_notes":"Neutraler Parallelgriff (Handflächen zeigen zueinander), etwa schulterbreit. Alternativ: breiter Latzuggriff für mehr Betonung der äußeren Lat-Anteile.","primary_muscles":["lats"],"secondary_muscles":["biceps","upper_back","forearms","rear_delts"],"description":"Vertikale Zugübung am Latzug mit neutralem Griff, die den Latissimus über einen großen Bewegungsradius belastet. Schulterfreundliche Variante des Latzugs.","setup":["Oberschenkelpolster so einstellen, dass die Beine fest fixiert sind.","Neutralen Parallelgriff am oberen Kabel einhängen.","Griff fassen, hinsetzen und Oberschenkel unter das Polster bringen.","Oberkörper aufrecht, leicht nach hinten geneigt, Brust leicht angehoben.","Arme gestreckt, Schultern bewusst nach unten ziehen, bevor die Bewegung beginnt."],"execution":["Griff in Richtung obere Brust ziehen, Ellenbogen führen die Bewegung nach unten.","Schulterblätter nach unten und zusammen ziehen.","In der Endposition kurz halten, Griff befindet sich etwa auf Höhe des Kinns bis der oberen Brust.","Gewicht langsam zurückführen, Arme kontrolliert strecken.","Schultern am oberen Ende leicht nach oben kommen lassen, um den Lat zu dehnen.","Ohne Schwung die nächste Wiederholung beginnen."],"range_of_motion":"Von vollständig gestreckten Armen bis der Griff etwa auf Höhe des Kinns bzw. der oberen Brust ist. Nicht bis zum Bauch ziehen.","breathing":"Beim Ziehen ausatmen, beim Strecken der Arme einatmen.","common_mistakes":["Oberkörper wird stark nach hinten gelehnt und die Bewegung mit Schwung ausgeführt.","Schultern bleiben während des Zugs oben am Ohr.","Griff wird mit den Armen statt mit den Ellenbogen geführt.","Gewicht fällt nach oben zurück, keine Kontrolle in der exzentrischen Phase.","Ellenbogen weichen weit nach hinten aus, sodass der Rücken rund wird."],"tips":["Daumen auf die Griffe legen statt zu umschließen, um weniger mit den Unterarmen zu arbeiten.","Vorstellen, die Ellenbogen in die Hosentaschen zu ziehen.","Die exzentrische Phase bewusst zwei bis drei Sekunden lang ausführen."],"cable_setup":{"cable":"Latzug-Station am Kabelturm (feste Rolle oben)","height":"","grip_width":"Schulterbreit, neutral (Handflächen zueinander)","body_position":"Aufrecht sitzend, leichte Rücklage von etwa 10 bis 20 Grad, Brust angehoben, Rumpf stabil","foot_position":"Füße flach auf dem Boden, Oberschenkel unter dem Polster fixiert","movement_direction":"Vertikal von oben nach unten in Richtung obere Brust","elbow_position":"Ellenbogen zeigen nach unten und leicht nach vorne, bleiben nah am Körper","end_position":"Griff auf Höhe des Kinns bis der oberen Brust, Schulterblätter nach unten und zusammengezogen","return":"Langsam und kontrolliert bis zur vollen Armstreckung, Schultern am Ende leicht nach oben kommen lassen","seat_position":"Oberschenkelpolster so einstellen, dass die Beine fest fixiert sind und die Füße flach auf dem Boden stehen. Sitz so wählen, dass die Arme oben vollständig gestreckt sind, ohne dass das Gewicht aufsetzt."},"muscle_focus":["Oben die Arme lang werden lassen und die Schultern kurz in Richtung Ohren gleiten lassen, so steht der Latissimus in der gedehnten Position unter Last.","Die Bewegung über die Ellenbogen einleiten und sie nach unten in Richtung Hüfte führen; die Hände nur als Haken verstehen, nicht aktiv zum Körper ziehen.","Den Oberkörper nur leicht zurücklehnen und ohne Schwung ziehen; starke Rücklage verlagert die Arbeit auf den oberen Rücken und den Bizeps.","Die Rückführung zwei bis drei Sekunden kontrollieren, der gedehnte Bereich oben gehört zur Wiederholung dazu."],"requirements":["Latzug-Station am Kabelturm oder integrierter Latzug mit Oberschenkelpolster","Neutraler Parallelgriff (MAG-Griff)"],"grip_alternatives":["close_v_grip"],"alternative_exercises":["latzug-hebel","breiter-latzug"]}$seed$::jsonb);

-- Breiter Latzug
select public.upsert_seed_exercise($seed${"slug":"breiter-latzug","name":"Breiter Latzug","category":"back","equipment":"cable","grip_id":"wide_lat_bar","grip_notes":"Breite Latzugstange, pronierter Griff (Handflächen nach vorne), Hände deutlich weiter als schulterbreit an den gebogenen Enden der Stange. Alternativ: etwas enger greifen, wenn die Schultern in der gestreckten Position unangenehm belastet sind.","primary_muscles":["lats"],"secondary_muscles":["upper_back","biceps","forearms","rear_delts"],"description":"Vertikale Zugübung am Latzug mit breitem, proniertem Griff, die den Latissimus und den oberen Rücken belastet. Klassische Übung für die Rückenbreite.","setup":["Breite Latzugstange am oberen Kabel einhängen.","Oberschenkelpolster so einstellen, dass die Beine fest fixiert sind.","Stange deutlich weiter als schulterbreit mit proniertem Griff fassen, hinsetzen und Oberschenkel unter das Polster bringen.","Oberkörper aufrecht mit leichter Rücklage, Brust angehoben, Blick nach vorne.","Arme gestreckt, Schultern bewusst nach unten ziehen, bevor die Bewegung beginnt."],"execution":["Stange in Richtung obere Brust ziehen, Ellenbogen führen die Bewegung nach unten und leicht nach außen.","Schulterblätter nach unten und zusammen ziehen, Brust bleibt angehoben.","In der Endposition kurz halten, Stange befindet sich etwa auf Höhe der oberen Brust.","Gewicht langsam zurückführen, Arme kontrolliert strecken.","Am oberen Ende die Schultern leicht nach oben kommen lassen, um den Lat zu dehnen.","Ohne Schwung die nächste Wiederholung beginnen."],"range_of_motion":"Von vollständig gestreckten Armen bis die Stange etwa auf Höhe der oberen Brust ist. Nicht bis zum Bauch ziehen und nicht hinter den Nacken.","breathing":"Beim Ziehen ausatmen, beim Strecken der Arme einatmen.","common_mistakes":["Oberkörper wird stark nach hinten gelehnt und die Stange mit Schwung gezogen.","Stange wird hinter den Nacken gezogen.","Schultern bleiben während des Zugs oben am Ohr.","Bewegung kommt vor allem aus den Armen statt aus den Ellenbogen und Schulterblättern.","Gewicht fällt nach oben zurück, keine Kontrolle in der exzentrischen Phase."],"tips":["Die Ellenbogen bewusst nach unten in Richtung Hüfte führen, nicht nach hinten.","Die exzentrische Phase zwei bis drei Sekunden lang kontrollieren.","Wenn die Schultern bei sehr breitem Griff unangenehm belastet sind, etwas enger greifen oder auf den neutralen Latzug wechseln."],"cable_setup":{"cable":"Latzug-Station am Kabelturm (feste Rolle oben)","height":"","grip_width":"Deutlich weiter als schulterbreit, proniert (Handflächen nach vorne)","body_position":"Aufrecht sitzend, leichte Rücklage von etwa 10 bis 20 Grad, Brust angehoben, Rumpf stabil","foot_position":"Füße flach auf dem Boden, Oberschenkel unter dem Polster fixiert","movement_direction":"Vertikal von oben nach unten in Richtung obere Brust","elbow_position":"Ellenbogen zeigen nach unten und leicht nach außen, bleiben etwa in der Ebene des Oberkörpers","end_position":"Stange auf Höhe der oberen Brust, Schulterblätter nach unten und zusammengezogen","return":"Langsam und kontrolliert bis zur vollen Armstreckung, Schultern am Ende leicht nach oben kommen lassen","seat_position":"Oberschenkelpolster so einstellen, dass die Beine fest fixiert sind und die Füße flach auf dem Boden stehen. Sitz so wählen, dass die Arme oben vollständig gestreckt sind, ohne dass das Gewicht aufsetzt."},"muscle_focus":["Oben die Arme vollständig strecken und die Schulterblätter kurz nach oben gleiten lassen, so wird der Latissimus in der gedehnten Position belastet.","Ellenbogen nach unten und leicht nach außen in Richtung Hüfte führen, die Hände folgen nur; die Oberarme bleiben dabei etwa in der Ebene des Oberkörpers.","Stange vor dem Körper zur oberen Brust bringen, nicht in den Nacken, und die Rücklage klein halten, damit die Bewegung vertikal bleibt.","Exzentrische Phase zwei bis drei Sekunden kontrollieren und die Dehnung oben nicht mit Schwung durchlaufen."],"requirements":["Latzug-Station am Kabelturm oder integrierter Latzug mit Oberschenkelpolster","Breite Latzugstange"],"grip_alternatives":["neutral_parallel"],"alternative_exercises":["neutraler-latzug","latzug-hebel"]}$seed$::jsonb);

-- Enges Rudern
select public.upsert_seed_exercise($seed${"slug":"enges-rudern","name":"Enges Rudern","category":"back","equipment":"cable","grip_id":"close_v_grip","grip_notes":"Enger V-Griff, neutral (Handflächen zeigen zueinander). Alternativ: neutraler Parallelgriff in Schulterbreite, wenn der enge Griff die Handgelenke unangenehm belastet.","primary_muscles":["lats","mid_back"],"secondary_muscles":["biceps","forearms","rear_delts"],"description":"Horizontale Zugübung am sitzenden Kabelzug mit engem V-Griff, die den Latissimus und den mittleren Rücken belastet. Geeignet als Grundübung für die Rückendicke.","setup":["V-Griff am unteren Kabel der Ruderstation einhängen.","Hinsetzen, Füße auf die Fußplatten stellen, Knie leicht gebeugt.","Griff mit beiden Händen fassen und den Oberkörper aufrichten.","Brust angehoben, Rücken gerade, Schultern nach unten ziehen.","Arme gestreckt, Gewicht leicht abheben, sodass von Beginn an Spannung auf dem Kabel ist."],"execution":["Griff in Richtung unterer Bauch bzw. Nabel ziehen, Ellenbogen führen die Bewegung nah am Körper nach hinten.","Schulterblätter zusammen ziehen, Oberkörper bleibt aufrecht.","In der Endposition kurz halten, Griff berührt beinahe den Bauch.","Gewicht langsam zurückführen, Arme kontrolliert strecken.","Am Ende die Schulterblätter leicht nach vorne kommen lassen, um den Rücken zu dehnen.","Ohne Schwung aus dem Oberkörper die nächste Wiederholung beginnen."],"range_of_motion":"Von gestreckten Armen mit leicht nach vorne gezogenen Schulterblättern bis der Griff den unteren Bauch fast berührt. Der Oberkörper bewegt sich dabei nur wenige Grad.","breathing":"Beim Ziehen ausatmen, beim Strecken der Arme einatmen.","common_mistakes":["Oberkörper pendelt stark vor und zurück, Bewegung kommt aus dem unteren Rücken.","Schultern ziehen während des Zugs nach oben zu den Ohren.","Ellenbogen weichen nach außen aus, Griff wird zur Brust statt zum Bauch gezogen.","Rücken wird in der gestreckten Position stark gerundet.","Gewicht wird in der exzentrischen Phase einfach nach vorne gelassen."],"tips":["Vorstellen, die Ellenbogen nach hinten in die Hosentaschen zu ziehen.","In der Endposition eine Sekunde halten, um die Kontraktion im Rücken zu spüren.","Die exzentrische Phase zwei bis drei Sekunden lang ausführen.","Bei Beschwerden im unteren Rücken leichter beginnen und den Oberkörper bewusst stabil halten."],"cable_setup":{"cable":"Sitzende Ruderstation am Kabelturm oder Kabelturm mit unterer Rolle und Fußplatten","height":"ganz unten, so verläuft das Kabel im Sitzen etwa waagerecht auf Höhe des unteren Bauchs","grip_width":"Eng, neutral (Handflächen zueinander) am V-Griff","body_position":"Aufrecht sitzend, Brust angehoben, Rumpf stabil, Oberkörper nahezu senkrecht","foot_position":"Füße auf den Fußplatten, Knie leicht gebeugt","movement_direction":"Horizontal von vorne nach hinten in Richtung unterer Bauch","elbow_position":"Ellenbogen eng am Körper, zeigen nach hinten","end_position":"Griff am unteren Bauch, Schulterblätter zusammengezogen, Oberkörper aufrecht","return":"Langsam und kontrolliert bis zur Armstreckung, Schulterblätter am Ende leicht nach vorne kommen lassen"},"muscle_focus":["Vorne die Arme lang werden lassen und die Schulterblätter nach vorne gleiten lassen, damit Latissimus und mittlerer Rücken in der gedehnten Position unter Last stehen; der untere Rücken bleibt dabei neutral.","Ellenbogen eng am Körper nach hinten in Richtung Hüfte führen und den Griff zum unteren Bauch bringen, nicht zur Brust.","Oberkörper nahezu senkrecht halten; die Bewegung kommt aus Schulterblättern und Ellenbogen, nicht aus dem Pendeln des Rumpfes.","Rückführung zwei bis drei Sekunden kontrollieren und erst dann die nächste Wiederholung beginnen."],"requirements":["Sitzende Ruderstation oder Kabelturm mit unterer Rolle und Fußplatten","Enger V-Griff (Triangelgriff)"],"grip_alternatives":["neutral_parallel"],"alternative_exercises":[]}$seed$::jsonb);

-- Breites Rudern
select public.upsert_seed_exercise($seed${"slug":"breites-rudern","name":"Breites Rudern","category":"back","equipment":"cable","grip_id":"wide_lat_bar","grip_notes":"Breite Latzugstange, pronierter Griff (Handrücken nach oben), Hände deutlich weiter als schulterbreit. Alternativ: gerade Stange in etwas engerer Griffweite.","primary_muscles":["upper_back","mid_back"],"secondary_muscles":["lats","rear_delts","biceps","forearms"],"description":"Horizontale Zugübung am sitzenden Kabelzug mit breiter Stange und proniertem Griff, die vor allem den oberen und mittleren Rücken belastet. Gute Ergänzung zum engen Rudern.","setup":["Breite Latzugstange am unteren Kabel der Ruderstation einhängen.","Hinsetzen, Füße auf die Fußplatten stellen, Knie leicht gebeugt.","Stange deutlich weiter als schulterbreit mit proniertem Griff fassen.","Oberkörper aufrichten, Brust angehoben, Schultern nach unten ziehen.","Arme gestreckt, Gewicht leicht abheben, sodass Spannung auf dem Kabel ist."],"execution":["Stange in Richtung untere Brust bzw. oberer Bauch ziehen.","Ellenbogen führen die Bewegung etwas weiter außen als beim engen Rudern, etwa 45 Grad vom Körper abgespreizt.","Schulterblätter zusammen ziehen, Oberkörper bleibt aufrecht.","In der Endposition kurz halten, Stange befindet sich nah an der unteren Brust.","Gewicht langsam zurückführen, Arme kontrolliert strecken.","Am Ende die Schulterblätter leicht nach vorne kommen lassen, ohne den Rücken rund zu machen.","Ohne Schwung die nächste Wiederholung beginnen."],"range_of_motion":"Von gestreckten Armen mit leicht nach vorne gezogenen Schulterblättern bis die Stange die untere Brust fast berührt. Der Oberkörper bleibt dabei nahezu senkrecht.","breathing":"Beim Ziehen ausatmen, beim Strecken der Arme einatmen.","common_mistakes":["Oberkörper pendelt stark nach hinten, um das Gewicht zu bewegen.","Ellenbogen fliegen weit nach außen auf Schulterhöhe, Schultern rollen nach vorne.","Stange wird zum Bauch gezogen, dadurch verlagert sich die Belastung vom oberen Rücken weg.","Schultern ziehen nach oben zu den Ohren.","Keine Kontrolle in der exzentrischen Phase."],"tips":["Fokus auf das Zusammenziehen der Schulterblätter, nicht auf die Arme.","Gewicht etwas leichter wählen als beim engen Rudern, da die Hebelverhältnisse ungünstiger sind.","Die exzentrische Phase zwei bis drei Sekunden lang kontrollieren."],"cable_setup":{"cable":"Sitzende Ruderstation am Kabelturm oder Kabelturm mit unterer Rolle und Fußplatten","height":"ganz unten, damit der Zug im Sitzen waagerecht bis leicht ansteigend zur unteren Brust verläuft","grip_width":"Deutlich weiter als schulterbreit, proniert (Handrücken nach oben)","body_position":"Aufrecht sitzend, Brust angehoben, Rumpf stabil, Oberkörper nahezu senkrecht","foot_position":"Füße auf den Fußplatten, Knie leicht gebeugt","movement_direction":"Horizontal von vorne nach hinten in Richtung untere Brust bzw. oberer Bauch","elbow_position":"Ellenbogen etwa 45 Grad vom Körper abgespreizt, zeigen nach hinten-außen","end_position":"Stange nah an der unteren Brust, Schulterblätter zusammengezogen, Oberkörper aufrecht","return":"Langsam und kontrolliert bis zur Armstreckung, Schulterblätter am Ende leicht nach vorne kommen lassen"},"muscle_focus":["Vorne die Arme strecken und die Schulterblätter kontrolliert nach vorne gleiten lassen, so wird der obere Rücken in der gedehnten Position belastet, ohne dass der untere Rücken rund wird.","Ellenbogen etwa 45 Grad vom Körper abgespreizt nach hinten führen und die Schulterblätter aktiv zusammenziehen; die Stange kommt zur unteren Brust, nicht zum Bauch.","Ellenbogenhöhe bestimmt den Fokus: höhere Ellenbogen betonen oberen Rücken und hintere Schulter, tiefere den Latissimus.","Oberkörper nahezu senkrecht halten und die Rückführung zwei bis drei Sekunden kontrollieren."],"requirements":["Sitzende Ruderstation oder Kabelturm mit unterer Rolle und Fußplatten","Breite Latzugstange"],"grip_alternatives":["neutral_parallel"],"alternative_exercises":[]}$seed$::jsonb);

-- Brustgestütztes Rudern
select public.upsert_seed_exercise($seed${"slug":"brustgestuetztes-rudern","name":"Brustgestütztes Rudern","category":"back","equipment":"machine","grip_id":null,"grip_notes":"Neutrale oder pronierte Griffe, je nach Maschine. Neutraler Griff mit Ellenbogen nah am Körper betont eher den Latissimus, pronierter Griff mit Ellenbogen weiter außen eher den oberen Rücken. Handgelenke gerade halten.","primary_muscles":["mid_back","lats"],"secondary_muscles":["upper_back","rear_delts","biceps","forearms"],"description":"Horizontale Zugübung an einer Rudermaschine mit Brustpolster, das den Oberkörper stabilisiert und den unteren Rücken entlastet. Geeignet, um den Rücken ohne Ausweichbewegungen des Rumpfes zu trainieren.","setup":["Sitz so einstellen, dass die Griffe etwa auf Höhe der unteren Brust liegen.","Brust fest an das Polster legen, Füße flach auf den Boden oder die Fußplatten stellen.","Griffe fassen, Handgelenke gerade, Arme gestreckt.","Schultern bewusst nach unten ziehen, Brust bleibt am Polster.","Rumpf anspannen, bevor die Bewegung beginnt."],"execution":["Griffe kontrolliert nach hinten ziehen, Ellenbogen führen die Bewegung.","Schulterblätter zusammen ziehen, Brust bleibt die ganze Zeit am Polster.","In der Endposition kurz halten, Ellenbogen befinden sich etwa auf Höhe des Rumpfes oder leicht dahinter.","Gewicht langsam zurückführen, Arme kontrolliert strecken.","Am Ende die Schulterblätter leicht nach vorne kommen lassen, um den Rücken zu dehnen.","Ohne Schwung die nächste Wiederholung beginnen."],"range_of_motion":"Von gestreckten Armen mit leicht nach vorne gezogenen Schulterblättern bis die Ellenbogen etwa auf Höhe des Rumpfes oder leicht dahinter sind. Die Brust löst sich dabei nicht vom Polster.","breathing":"Beim Ziehen ausatmen, beim Strecken der Arme einatmen.","common_mistakes":["Brust löst sich vom Polster, um das Gewicht mit dem Oberkörper zu bewegen.","Schultern ziehen nach oben zu den Ohren.","Bewegung kommt vor allem aus den Armen, Schulterblätter bleiben vorne.","Sitz zu niedrig oder zu hoch, Griffe liegen auf Schulterhöhe oder Bauchhöhe.","Gewicht wird in der exzentrischen Phase einfach nach vorne gelassen."],"tips":["In der Endposition eine Sekunde halten, um die Kontraktion im Rücken zu spüren.","Die exzentrische Phase zwei bis drei Sekunden lang kontrollieren.","Gut geeignet als Alternative zum Kabelrudern, wenn der untere Rücken entlastet werden soll."],"cable_setup":null,"muscle_focus":["Vorne die Arme vollständig strecken und die Schulterblätter nach vorne gleiten lassen, damit der mittlere Rücken in der gedehnten Position belastet wird; die Brust bleibt dabei am Polster.","Bewegung über die Ellenbogen einleiten und die Schulterblätter nach hinten-unten ziehen; die Hände nur als Haken verstehen.","Ellenbogen nah am Körper betonen den Latissimus, Ellenbogen weiter außen den oberen Rücken; Griffwahl entsprechend anpassen.","Rückführung zwei bis drei Sekunden kontrollieren, das Gewicht nicht in die Dehnung fallen lassen."],"requirements":["Rudermaschine mit Brustpolster (Hebel- oder Seilzugmaschine)"],"grip_alternatives":[],"image_url":"/exercises/chest-supported-row.jpg","machine_name":"DHZ Flex Mid Row (A704L)","alternative_exercises":["rudern-hebel-sitzend","enges-rudern"]}$seed$::jsonb);

-- Kabelrudern einarmig
select public.upsert_seed_exercise($seed${"slug":"kabelrudern-einarmig","name":"Kabelrudern einarmig","category":"back","equipment":"cable","grip_id":"single_handle","grip_notes":"Einzelgriff, neutral (Handfläche zeigt zum Körper). Alternativ: Griff während des Zugs leicht eindrehen, sodass die Handfläche am Ende nach innen-oben zeigt.","primary_muscles":["lats","mid_back"],"secondary_muscles":["biceps","forearms","rear_delts"],"description":"Einarmige horizontale Zugübung am Kabelzug, die den Latissimus und den mittleren Rücken belastet. Geeignet, um Seitenunterschiede auszugleichen und den Bewegungsradius pro Seite zu vergrößern.","setup":["Einzelgriff am Kabelzug einhängen, Rolle etwa auf Hüfthöhe einstellen.","Sitzend an der Ruderstation oder stehend in Schrittstellung vor dem Kabelturm positionieren.","Griff mit einer Hand fassen, die freie Hand stützt sich am Gerät oder auf dem vorderen Oberschenkel ab.","Oberkörper aufrecht, Brust angehoben, Rumpf anspannen.","Arm gestreckt, Schulter nach unten ziehen, Gewicht leicht abheben, sodass Spannung auf dem Kabel ist."],"execution":["Griff in Richtung Hüfte bzw. unterer Bauch ziehen, Ellenbogen führt die Bewegung nah am Körper nach hinten.","Schulterblatt der arbeitenden Seite nach hinten und unten ziehen.","In der Endposition kurz halten, Ellenbogen befindet sich leicht hinter dem Rumpf.","Gewicht langsam zurückführen, Arm kontrolliert strecken.","Am Ende das Schulterblatt leicht nach vorne kommen lassen, ohne den Oberkörper zu verdrehen.","Alle Wiederholungen auf einer Seite ausführen, dann die Seite wechseln."],"range_of_motion":"Von gestrecktem Arm mit leicht nach vorne gezogenem Schulterblatt bis der Ellenbogen leicht hinter dem Rumpf ist. Der Oberkörper bleibt dabei stabil und dreht sich nur minimal mit.","breathing":"Beim Ziehen ausatmen, beim Strecken des Arms einatmen.","common_mistakes":["Oberkörper dreht sich stark mit, um das Gewicht zu bewegen.","Schulter zieht während des Zugs nach oben zum Ohr.","Ellenbogen weicht nach außen aus, Griff wird zur Brust statt zur Hüfte gezogen.","Zu schweres Gewicht, Bewegung wird aus dem Bizeps statt aus dem Rücken ausgeführt.","Keine Kontrolle in der exzentrischen Phase."],"tips":["Mit der schwächeren Seite beginnen und die Wiederholungszahl auf der stärkeren Seite daran anpassen.","Vorstellen, den Ellenbogen nach hinten in die Hosentasche zu ziehen.","Die exzentrische Phase zwei bis drei Sekunden lang kontrollieren."],"cable_setup":{"cable":"Kabelturm, eine Seite des Doppelkabelzugs; alternativ sitzende Ruderstation am Kabelturm","height":"Hüfthöhe, damit das Kabel in Schrittstellung etwa waagerecht zur Hüfte verläuft; an der sitzenden Ruderstation die feste untere Rolle nutzen","grip_width":"Einzelgriff, eine Hand, neutral (Handfläche zum Körper)","body_position":"Sitzend aufrecht oder stehend in Schrittstellung mit leicht nach vorne geneigtem Oberkörper, Rumpf stabil, freie Hand stützt","foot_position":"Sitzend: Füße auf den Fußplatten; stehend: Schrittstellung, gegenüberliegendes Bein vorne","movement_direction":"Horizontal von vorne nach hinten in Richtung Hüfte bzw. unterer Bauch","elbow_position":"Ellenbogen eng am Körper, zeigt nach hinten","end_position":"Griff an der Hüfte, Ellenbogen leicht hinter dem Rumpf, Schulterblatt nach hinten und unten gezogen","return":"Langsam und kontrolliert bis zur Armstreckung, Schulterblatt am Ende leicht nach vorne kommen lassen"},"muscle_focus":["Vorne den Arm lang werden lassen und das Schulterblatt nach vorne gleiten lassen, so steht der Latissimus in der gedehnten Position unter Last; der Oberkörper dreht dabei nur minimal mit.","Ellenbogen eng am Körper nach hinten zur Hüfte führen und das Schulterblatt nach hinten-unten ziehen; der Griff bleibt tief, nicht auf Brusthöhe.","Rumpf stabil halten und die freie Hand abstützen, damit die Arbeit im Rücken bleibt und nicht aus der Rumpfdrehung kommt.","Rückführung zwei bis drei Sekunden kontrollieren, die Dehnung vorne nicht überspringen."],"requirements":["Kabelturm mit verstellbarer Rolle oder sitzende Ruderstation","Einzelgriff (D-Griff)"],"grip_alternatives":["strap_handle"],"alternative_exercises":[]}$seed$::jsonb);

-- Reverse Fly Kurzhantel
select public.upsert_seed_exercise($seed${"slug":"reverse-fly-kurzhantel","name":"Reverse Fly Kurzhantel","category":"back","equipment":"dumbbell","grip_id":null,"grip_notes":"Neutraler Griff (Handflächen zeigen zueinander) oder pronierter Griff (Handrücken nach oben). Hanteln locker in den Händen halten, Ellenbogen während der gesamten Bewegung leicht gebeugt.","primary_muscles":["rear_delts","upper_back"],"secondary_muscles":["traps","mid_back"],"description":"Seitliches Anheben der Arme in vorgebeugter Position, das die hintere Schulter und den oberen Rücken belastet. Geeignet als Ergänzung zu Zugübungen und als Ausgleich zu Druckübungen.","setup":["Leichte Kurzhanteln wählen.","Oberkörper etwa 45 Grad bis fast parallel zum Boden nach vorne neigen, Knie leicht gebeugt, Rücken gerade.","Alternativ bäuchlings auf eine Schrägbank legen, Brust auf dem Polster.","Hanteln unter der Brust hängen lassen, Arme fast gestreckt, Ellenbogen leicht gebeugt.","Rumpf anspannen, Nacken in Verlängerung der Wirbelsäule, Blick nach unten.","Schultern nach unten ziehen, bevor die Bewegung beginnt."],"execution":["Arme seitlich nach außen-oben anheben, Ellenbogen bleiben leicht gebeugt.","Bewegung aus den Schultern und Schulterblättern führen, nicht aus den Armen.","Anheben, bis die Oberarme etwa auf Höhe des Rückens sind.","In der Endposition kurz halten, Schulterblätter leicht zusammen ziehen.","Hanteln langsam und kontrolliert wieder absenken.","Unten die Spannung halten, Hanteln nicht zusammenschlagen lassen."],"range_of_motion":"Von hängenden Armen bis die Oberarme etwa auf Höhe des Rückens sind. Höher als die Rückenlinie ist nicht notwendig.","breathing":"Beim Anheben ausatmen, beim Absenken einatmen.","common_mistakes":["Oberkörper richtet sich beim Anheben auf, um Schwung zu holen.","Zu schweres Gewicht, Ellenbogen werden stark gebeugt und die Bewegung wird zum Rudern.","Schultern ziehen nach oben zu den Ohren.","Rücken wird in der vorgebeugten Position rund.","Hanteln werden einfach fallen gelassen, keine Kontrolle beim Absenken."],"tips":["Deutlich leichter beginnen als bei Ruderübungen, die hintere Schulter ist ein kleiner Muskel.","Daumen leicht nach unten drehen, um die hintere Schulter stärker zu betonen.","Die Variante auf der Schrägbank nimmt den unteren Rücken aus der Übung.","Höhere Wiederholungszahlen mit sauberer Technik sind hier sinnvoller als schweres Gewicht."],"cable_setup":null,"muscle_focus":["Arme unter der Brust hängen lassen und die Schulterblätter nach vorne gleiten lassen, so wird die hintere Schulter in der gedehnten Position belastet.","Bewegung aus dem Schultergelenk führen: Ellenbogenwinkel bleibt gleich, die Oberarme bewegen sich seitlich nach außen-oben in der Ebene des Oberkörpers.","Leichtes Gewicht wählen; sobald die Ellenbogen stark beugen oder der Oberkörper sich aufrichtet, übernehmen Rücken und Trapez die Arbeit.","Absenken über etwa zwei Sekunden kontrollieren und unten die Spannung halten."],"requirements":["Leichte Kurzhanteln","Optional: Schrägbank für die bäuchlings liegende Variante"],"grip_alternatives":[],"alternative_exercises":[]}$seed$::jsonb);

-- Straight Arm Pulldown
select public.upsert_seed_exercise($seed${"slug":"straight-arm-pulldown","name":"Straight Arm Pulldown","category":"back","equipment":"cable","grip_id":"straight_bar","grip_notes":"Gerade Stange, pronierter Griff etwa schulterbreit. Alternativ: Seil mit neutralem Griff (Handflächen zueinander), erlaubt am Ende etwas mehr Bewegung an der Hüfte vorbei.","primary_muscles":["lats"],"secondary_muscles":["triceps","rear_delts","abs"],"description":"Zugübung am oberen Kabel mit fast gestreckten Armen, bei der der Latissimus ohne nennenswerte Beteiligung des Bizeps arbeitet. Geeignet als Isolations- oder Vorermüdungsübung für den Rücken.","setup":["Gerade Stange am oberen Kabel einhängen.","Etwa einen Schritt vom Kabelturm entfernt aufstellen, Füße hüftbreit, Knie leicht gebeugt.","Stange schulterbreit mit proniertem Griff fassen, Arme nach vorne-oben gestreckt.","Oberkörper leicht nach vorne neigen, Rücken gerade, Rumpf anspannen.","Schultern nach unten ziehen, Ellenbogen leicht gebeugt und in dieser Position fixieren."],"execution":["Stange in einem Bogen nach unten zu den Oberschenkeln ziehen, Arme bleiben fast gestreckt.","Bewegung aus den Schultern führen, Ellenbogenwinkel bleibt unverändert.","Schulterblätter nach unten ziehen, Oberkörper bleibt stabil.","In der Endposition kurz halten, Stange berührt beinahe die Oberschenkel.","Stange langsam und kontrolliert wieder nach oben führen.","Oben die Dehnung im Latissimus spüren, ohne den Rücken zu überstrecken.","Ohne Schwung aus dem Oberkörper die nächste Wiederholung beginnen."],"range_of_motion":"Von Armen etwa auf Höhe des Kopfes oder leicht darüber bis die Stange die Oberschenkel fast berührt. Oben nur so weit, wie der Rücken gerade bleibt.","breathing":"Beim Ziehen nach unten ausatmen, beim Zurückführen nach oben einatmen.","common_mistakes":["Ellenbogen werden während des Zugs gebeugt, die Übung wird zum Trizepsdrücken.","Oberkörper pendelt mit, um das Gewicht zu bewegen.","Schultern rollen nach vorne und ziehen nach oben.","Zu schweres Gewicht, die Bewegung wird kurz und ruckartig.","Rücken wird in der oberen Position stark überstreckt."],"tips":["Leichtes Gewicht wählen und die Spannung im Latissimus über den gesamten Bewegungsradius halten.","Vorstellen, die Stange mit den Ellenbogen statt mit den Händen nach unten zu drücken.","Die exzentrische Phase zwei bis drei Sekunden lang ausführen.","Mit dem Seil lässt sich die Endposition etwas weiter an der Hüfte vorbei führen."],"cable_setup":{"cable":"Kabelturm mit oberer Rolle; alternativ Latzug-Station am Kabelturm im Stand","height":"ganz oben, damit der Zug von oben kommt und der Latissimus bei angehobenen Armen in der gedehnten Position belastet wird","grip_width":"Schulterbreit, proniert (Handrücken nach oben) an der geraden Stange","body_position":"Stehend, etwa einen Schritt vom Turm entfernt, Oberkörper leicht nach vorne geneigt, Rücken gerade, Rumpf angespannt","foot_position":"Hüftbreit, Knie leicht gebeugt, Gewicht gleichmäßig auf beiden Füßen","movement_direction":"Bogenförmig von vorne-oben nach unten zu den Oberschenkeln","elbow_position":"Leicht gebeugt und während der gesamten Bewegung unverändert","end_position":"Stange an den Oberschenkeln, Schulterblätter nach unten gezogen, Oberkörper stabil","return":"Langsam und kontrolliert nach oben bis etwa auf Kopfhöhe, Dehnung im Latissimus, Rücken bleibt gerade"},"muscle_focus":["Oben die Arme etwa auf Kopfhöhe lang werden lassen und die Dehnung im Latissimus kurz aufnehmen, ohne den unteren Rücken zu überstrecken.","Bewegung ausschließlich aus dem Schultergelenk führen: Ellenbogenwinkel bleibt leicht gebeugt und unverändert, die Oberarme drücken in einem Bogen nach unten zur Hüfte.","Leichtes Gewicht wählen; sobald die Ellenbogen beugen oder die Schultern nach vorne rollen, übernehmen Trizeps und Brust.","Rückführung zwei bis drei Sekunden kontrollieren, oben nicht ins Hohlkreuz ausweichen."],"requirements":["Kabelturm mit oberer Rolle","Gerade kurze Stange; alternativ breite Latzugstange oder Seil"],"grip_alternatives":["wide_lat_bar","rope"],"alternative_exercises":[]}$seed$::jsonb);

-- Hyperextensions
select public.upsert_seed_exercise($seed${"slug":"hyperextensions","name":"Hyperextensions","category":"back","equipment":"bodyweight","grip_id":null,"grip_notes":"Arme vor der Brust verschränkt oder Hände an den Schläfen. Mit Zusatzgewicht: Hantelscheibe oder Kurzhantel vor der Brust halten.","primary_muscles":["lower_back","glutes"],"secondary_muscles":["hamstrings"],"description":"Rumpfstreckung an der 45-Grad-Rückenstrecker-Bank, die den unteren Rücken, das Gesäß und die hintere Oberschenkelmuskulatur belastet. Geeignet als Ergänzung im Rücken- oder Beintraining und zur Kräftigung der Rumpfrückseite.","setup":["Hüftpolster so einstellen, dass die Oberkante knapp unterhalb des Hüftknochens liegt und die Hüfte frei beugen kann.","Fersen fest gegen die Fußplatte stellen, Füße hüftbreit.","Oberkörper auf dem Polster ablegen, Arme vor der Brust verschränken.","Rumpf anspannen, Nacken in Verlängerung der Wirbelsäule.","Oberkörper aufrichten, bis der Körper eine gerade Linie von Kopf bis Ferse bildet."],"execution":["Oberkörper langsam aus der Hüfte nach unten absenken, Wirbelsäule bleibt neutral.","So weit absenken, wie der Rücken gerade bleibt, etwa bis der Oberkörper senkrecht ist.","Gesäß und hintere Oberschenkel anspannen und den Oberkörper kontrolliert wieder anheben.","Anheben, bis Oberkörper und Beine eine gerade Linie bilden.","In der Endposition kurz halten, ohne weiter nach oben zu überstrecken.","Nächste Wiederholung kontrolliert beginnen."],"range_of_motion":"Von der geraden Linie zwischen Oberkörper und Beinen bis der Oberkörper etwa senkrecht hängt. In der Endposition nicht über die gerade Linie hinaus überstrecken.","breathing":"Beim Absenken einatmen, beim Anheben ausatmen.","common_mistakes":["Oberkörper wird in der Endposition über die gerade Linie hinaus überstreckt.","Rücken wird beim Absenken rund, Bewegung kommt aus der Wirbelsäule statt aus der Hüfte.","Polster zu hoch eingestellt, Hüfte kann nicht frei beugen.","Bewegung wird mit Schwung ausgeführt.","Kopf wird in den Nacken gelegt."],"tips":["Zunächst mit Körpergewicht beginnen, Zusatzgewicht erst dann, wenn die Technik stabil ist.","Für mehr Betonung des Gesäßes die Füße leicht nach außen drehen und bewusst aus der Hüfte arbeiten.","Die exzentrische Phase zwei bis drei Sekunden lang kontrollieren."],"cable_setup":null,"muscle_focus":["Hüftpolster knapp unter dem Hüftknochen einstellen, damit die Beugung aus der Hüfte kommt und Gesäß und hintere Oberschenkel in der tiefen Position gedehnt werden.","Beim Absenken die Wirbelsäule neutral halten und so tief gehen, wie der Rücken gerade bleibt; die Dehnung unten kurz aufnehmen.","Beim Anheben Gesäß und hintere Oberschenkel aktiv anspannen und nur bis zur geraden Linie kommen; Überstrecken verlagert die Last auf die Lendenwirbelsäule.","Exzentrische Phase zwei bis drei Sekunden kontrollieren, kein Schwung aus dem Oberkörper."],"requirements":["45-Grad-Rückenstrecker-Bank (Hyperextension-Bank)","Optional: Hantelscheibe vor der Brust als Zusatzgewicht"],"grip_alternatives":[],"image_url":"/exercises/hyperextension-bench.jpg","machine_name":"Hyperextension-Bank 45°","alternative_exercises":["rumaenisches-kreuzheben"]}$seed$::jsonb);

-- Wrist Curl
select public.upsert_seed_exercise($seed${"slug":"wrist-curl","name":"Wrist Curl","category":"forearms","equipment":"dumbbell","grip_id":null,"grip_notes":"Supinierter Griff (Handflächen nach oben), Kurzhantel locker in den Fingern. Alternativ: Langhantel mit beiden Händen, etwa schulterbreit.","primary_muscles":["forearms"],"secondary_muscles":[],"description":"Isolierte Beugung des Handgelenks mit der Kurzhantel, die die Beugemuskulatur des Unterarms belastet. Geeignet als Ergänzung am Ende des Arm- oder Rückentrainings.","setup":["Leichte Kurzhantel wählen, sitzend auf einer Bank Platz nehmen.","Unterarm auf dem Oberschenkel oder auf der Bank ablegen, Handfläche zeigt nach oben.","Handgelenk ragt über das Knie bzw. die Bankkante hinaus, sodass es sich frei bewegen kann.","Hantel locker greifen, Finger leicht geöffnet.","Unterarm bleibt während der gesamten Bewegung auf der Unterlage."],"execution":["Handgelenk langsam nach unten beugen, Hantel in die Finger rollen lassen.","In der unteren Position die Dehnung im Unterarm kurz halten.","Hantel mit den Fingern wieder greifen und das Handgelenk nach oben beugen.","In der oberen Position kurz halten, Unterarm bleibt auf der Unterlage.","Hantel langsam und kontrolliert wieder absenken.","Nach allen Wiederholungen die Seite wechseln."],"range_of_motion":"Von der vollständig gestreckten Position mit geöffneten Fingern bis zur vollen Beugung des Handgelenks nach oben. Der Unterarm bewegt sich dabei nicht.","breathing":"Beim Beugen nach oben ausatmen, beim Absenken einatmen.","common_mistakes":["Unterarm hebt sich von der Unterlage ab, die Bewegung kommt aus dem Ellenbogen.","Zu schweres Gewicht, der Bewegungsradius wird sehr klein.","Hantel wird mit Schwung nach oben geworfen.","Keine Kontrolle beim Absenken."],"tips":["Leichtes Gewicht und höhere Wiederholungszahlen wählen, die Unterarmmuskulatur reagiert gut darauf.","Die Hantel bewusst bis in die Finger rollen lassen, um den vollen Bewegungsradius zu nutzen.","Tempo langsam halten, etwa zwei Sekunden pro Phase."],"cable_setup":null,"muscle_focus":["Unten die Hantel bis in die Finger rollen lassen und die Dehnung der Unterarmbeuger kurz halten; dieser gedehnte Bereich ist der wichtigste Teil der Bewegung.","Unterarm fest auf der Unterlage lassen, die Bewegung kommt ausschließlich aus dem Handgelenk.","Leichtes Gewicht und langsames Tempo wählen, etwa zwei Sekunden pro Phase; zu schwere Hanteln verkürzen den Bewegungsradius."],"requirements":["Leichte Kurzhantel","Flachbank oder Hocker zum Sitzen und Ablegen des Unterarms"],"grip_alternatives":[],"alternative_exercises":[]}$seed$::jsonb);

-- Reverse Wrist Curl
select public.upsert_seed_exercise($seed${"slug":"reverse-wrist-curl","name":"Reverse Wrist Curl","category":"forearms","equipment":"dumbbell","grip_id":null,"grip_notes":"Pronierter Griff (Handflächen nach unten), Hantel fest umschlossen. Alternativ: Langhantel oder EZ-Stange mit beiden Händen, etwa schulterbreit.","primary_muscles":["forearms"],"secondary_muscles":[],"description":"Isolierte Streckung des Handgelenks mit der Kurzhantel, die die Streckmuskulatur des Unterarms belastet. Geeignet als Ausgleich zum Wrist Curl und zur Kräftigung der Unterarmaußenseite.","setup":["Deutlich leichtere Kurzhantel als beim Wrist Curl wählen, sitzend auf einer Bank Platz nehmen.","Unterarm auf dem Oberschenkel oder auf der Bank ablegen, Handfläche zeigt nach unten.","Handgelenk ragt über das Knie bzw. die Bankkante hinaus, sodass es sich frei bewegen kann.","Hantel fest umschließen, Handgelenk in neutraler Ausgangsposition.","Unterarm bleibt während der gesamten Bewegung auf der Unterlage."],"execution":["Handgelenk langsam nach unten beugen, Handrücken bewegt sich in Richtung Boden.","In der unteren Position die Dehnung an der Unterarmaußenseite kurz halten.","Handgelenk kontrolliert nach oben strecken, Handrücken bewegt sich in Richtung Unterarm.","In der oberen Position kurz halten, Unterarm bleibt auf der Unterlage.","Hantel langsam und kontrolliert wieder absenken.","Nach allen Wiederholungen die Seite wechseln."],"range_of_motion":"Von der vollständig gebeugten Position nach unten bis zur vollen Streckung des Handgelenks nach oben. Der Unterarm bewegt sich dabei nicht.","breathing":"Beim Strecken nach oben ausatmen, beim Absenken einatmen.","common_mistakes":["Zu schweres Gewicht, die Streckmuskulatur ist deutlich schwächer als die Beugemuskulatur.","Unterarm hebt sich von der Unterlage ab, die Bewegung kommt aus dem Ellenbogen.","Bewegungsradius wird sehr klein, nur das obere Drittel wird genutzt.","Hantel wird mit Schwung nach oben geworfen."],"tips":["Mit etwa der Hälfte des Gewichts vom Wrist Curl beginnen und bei Bedarf anpassen.","Leichtes Gewicht und höhere Wiederholungszahlen wählen.","Tempo langsam halten, etwa zwei Sekunden pro Phase.","Bei Beschwerden im Ellenbogen das Gewicht reduzieren oder den Bewegungsradius verkleinern."],"cable_setup":null,"muscle_focus":["Unten das Handgelenk vollständig beugen und die Dehnung an der Unterarmaußenseite kurz halten, dann kontrolliert nach oben strecken.","Unterarm bleibt auf der Unterlage, die Bewegung kommt nur aus dem Handgelenk; Ellenbogen und Schulter bleiben ruhig.","Deutlich leichter als beim Wrist Curl beginnen und das Tempo bei etwa zwei Sekunden pro Phase halten, damit der volle Bewegungsradius erhalten bleibt."],"requirements":["Sehr leichte Kurzhantel","Flachbank oder Hocker zum Sitzen und Ablegen des Unterarms"],"grip_alternatives":[],"alternative_exercises":[]}$seed$::jsonb);

-- Hackenschmidt
select public.upsert_seed_exercise($seed${"slug":"hackenschmidt","name":"Hackenschmidt","category":"quads","equipment":"machine","grip_id":null,"grip_notes":"Haltegriffe neben den Schulterpolstern fassen, Hände bleiben locker. Füße mittig auf der Plattform, etwa schulterbreit, Fußspitzen leicht nach außen.","primary_muscles":["quads"],"secondary_muscles":["glutes","hamstrings"],"description":"Geführte Kniebeuge an der Hackenschmidt-Maschine, bei der der Rücken am Schlitten anliegt und die Bewegung in einer festen Bahn verläuft. Gut geeignet, um den Quadrizeps mit hoher Kontrolle und ohne freie Stabilisation zu belasten.","setup":["Rücken und Schultern vollständig an das Rückenpolster und die Schulterpolster anlegen.","Füße mittig und etwa schulterbreit auf der Plattform platzieren, Fußspitzen leicht nach außen.","Haltegriffe fassen und die Sicherungen der Maschine lösen.","Rumpf anspannen, unterer Rücken bleibt am Polster.","Knie in der Startposition leicht gebeugt lassen, nicht durchgestreckt."],"execution":["Schlitten kontrolliert absenken, Knie beugen sich in Richtung Fußspitzen.","Fersen bleiben während der gesamten Bewegung auf der Plattform.","So tief absenken, wie Beweglichkeit und Becken am Polster es zulassen.","Kurz in der unteren Position stoppen, ohne das Gewicht abzusetzen.","Über die ganze Fußsohle nach oben drücken, bis die Knie fast gestreckt sind.","Knie oben nicht durchdrücken, Spannung im Oberschenkel halten."],"range_of_motion":"Absenken, bis die Oberschenkel etwa parallel zur Plattform stehen oder so weit, wie das Becken am Polster bleibt. Oben kurz vor der vollen Kniestreckung stoppen.","breathing":"Beim Hochdrücken ausatmen, beim Absenken einatmen.","common_mistakes":["Fersen heben sich in der unteren Position von der Plattform ab.","Knie fallen nach innen, statt in Richtung Fußspitzen zu zeigen.","Becken kippt unten vom Polster weg, unterer Rücken rundet sich.","Knie werden oben vollständig durchgestreckt und die Spannung geht verloren.","Füße stehen zu weit unten auf der Plattform, Fersen finden keinen Halt."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Füße etwas höher auf der Plattform platzieren, wenn Gesäß und hintere Oberschenkel stärker beteiligt sein sollen.","Sicherungen vor dem Satz prüfen und erst nach dem letzten Satz wieder einrasten lassen.","Erst dann Gewicht erhöhen, wenn die Tiefe über alle Wiederholungen gleich bleibt."],"cable_setup":null,"muscle_focus":["Tief absenken, soweit das Becken am Polster bleibt; der Quadrizeps arbeitet in der tiefen, gedehnten Kniebeugung am stärksten.","Fersen auf der Plattform lassen und die Knie in Richtung Fußspitzen führen, dann bleibt die Last auf dem Oberschenkel statt auf dem Kniegelenk.","Füße eher mittig bis tief auf der Plattform betonen den Quadrizeps; höher platziert verlagert sich die Arbeit zu Gesäß und hinteren Oberschenkeln.","Exzentrische Phase zwei bis drei Sekunden kontrollieren und oben kurz vor der Kniestreckung stoppen, damit die Spannung erhalten bleibt."],"requirements":["Hackenschmidt-Maschine (Hack Squat) mit Schulterpolstern und Sicherungen"],"grip_alternatives":[],"image_url":"/exercises/hack-squat.jpg","machine_name":"Hack Squat, Plate Loaded","alternative_exercises":["beinpresse-45-grad","multipresse-kniebeuge"]}$seed$::jsonb);

-- Beinpresse
select public.upsert_seed_exercise($seed${"slug":"beinpresse","name":"Beinpresse","category":"quads","equipment":"machine","grip_id":null,"grip_notes":"Haltegriffe seitlich am Sitz fassen, um das Becken stabil zu halten. Füße mittig auf der Platte, etwa schulterbreit, Fußspitzen leicht nach außen.","primary_muscles":["quads"],"secondary_muscles":["glutes","hamstrings"],"description":"Geführte Druckübung an der 45-Grad- oder horizontalen Beinpresse, bei der der Oberkörper fixiert ist und die Beine das Gewicht wegdrücken. Gut geeignet, um Quadrizeps und Gesäß mit hoher Last und geringer Stabilisationsanforderung zu trainieren.","setup":["Rückenlehne so einstellen, dass unterer Rücken und Becken vollständig am Polster anliegen.","Füße mittig und etwa schulterbreit auf die Platte stellen, Fußspitzen leicht nach außen.","Haltegriffe fassen, Rumpf anspannen.","Platte leicht wegdrücken und die Sicherungen lösen.","Startposition mit leicht gebeugten Knien einnehmen, Fersen fest auf der Platte."],"execution":["Platte kontrolliert absenken, Knie beugen sich in Richtung Fußspitzen.","So weit absenken, wie das Becken am Polster bleibt.","Unten kurz stoppen, ohne dass das Gewicht aufsetzt.","Über die ganze Fußsohle wegdrücken, Fersen bleiben auf der Platte.","Knie am Ende nicht vollständig durchstrecken.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von leicht gebeugten Knien bis zu einem Kniewinkel von etwa 90 Grad oder tiefer, solange das Becken am Polster bleibt. Oben kurz vor der vollen Streckung stoppen.","breathing":"Beim Wegdrücken ausatmen, beim Absenken einatmen.","common_mistakes":["Becken hebt sich unten vom Polster ab, unterer Rücken rundet sich.","Knie werden oben vollständig durchgestreckt.","Knie fallen beim Drücken nach innen.","Fersen heben sich von der Platte ab, Druck kommt nur aus den Zehen.","Gewicht wird unten mit Schwung abgefangen."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Hände an den Griffen lassen und nicht gegen die Knie drücken.","Höhere Fußposition auf der Platte verlagert die Belastung mehr auf Gesäß und hintere Oberschenkel, tiefere Position mehr auf den Quadrizeps.","Sicherungen vor dem Satz prüfen und erst nach dem letzten Satz einrasten lassen."],"cable_setup":null,"muscle_focus":["So tief absenken, wie das Becken am Polster bleibt; die tiefe Kniebeugung belastet den Quadrizeps in der gedehnten Position.","Über die ganze Fußsohle drücken und die Knie in Richtung Fußspitzen führen, nicht nach innen fallen lassen.","Fußposition bestimmt den Fokus: tiefer auf der Platte betont den Quadrizeps, höher Gesäß und hintere Oberschenkel.","Exzentrische Phase etwa zwei Sekunden kontrollieren, oben nicht durchstrecken."],"requirements":["45-Grad- oder horizontale Beinpresse mit verstellbarer Rückenlehne und Sicherungen"],"grip_alternatives":[],"image_url":"/exercises/leg-press-seated.jpg","machine_name":"DHZ Seated Leg Press, Steckgewicht","alternative_exercises":["beinpresse-45-grad","hackenschmidt"]}$seed$::jsonb);

-- Beinstrecker
select public.upsert_seed_exercise($seed${"slug":"beinstrecker","name":"Beinstrecker","category":"quads","equipment":"machine","grip_id":null,"grip_notes":"Haltegriffe seitlich am Sitz fassen, um das Becken im Sitz zu halten. Keine Griffarbeit nötig, Hände bleiben locker.","primary_muscles":["quads"],"secondary_muscles":[],"description":"Isolationsübung an der Maschine, bei der die Knie gegen Widerstand gestreckt werden. Gut geeignet, um den Quadrizeps gezielt und ohne Belastung von Hüfte und Rücken zu trainieren.","setup":["Rückenlehne so einstellen, dass die Drehachse der Maschine auf Höhe des Kniegelenks liegt.","Beinpolster so einstellen, dass es knapp oberhalb des Sprunggelenks am Schienbein anliegt.","Rücken vollständig an das Polster anlehnen, Haltegriffe fassen.","Oberschenkel liegen flach auf dem Sitz, Fußspitzen leicht angezogen.","Gewicht so wählen, dass die Streckung kontrolliert möglich ist."],"execution":["Beine kontrolliert strecken, bis die Knie fast gestreckt sind.","In der Endposition ein bis zwei Sekunden halten und den Quadrizeps anspannen.","Oberschenkel bleiben auf dem Sitz, Becken bleibt am Polster.","Gewicht langsam zurückführen, bis der Kniewinkel etwa 90 Grad erreicht.","Gewicht nicht aufsetzen lassen, Spannung halten.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von etwa 90 Grad Kniebeugung bis zur fast vollständigen Streckung. Bei Beschwerden im Knie den Bewegungsradius in der unteren Position verkleinern.","breathing":"Beim Strecken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Gewicht wird mit Schwung nach oben geschleudert.","Becken hebt sich vom Sitz ab, um mehr Gewicht zu bewegen.","Drehachse der Maschine liegt nicht auf Kniehöhe, Knie wird ungünstig belastet.","Gewicht fällt in der exzentrischen Phase unkontrolliert zurück.","Polster liegt zu hoch am Schienbein, Hebel wird ungünstig."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Fußspitzen leicht nach oben ziehen, um die Spannung im Quadrizeps zu erhöhen.","Einbeinige Ausführung, um Seitenunterschiede auszugleichen.","Mit moderatem Gewicht und höheren Wiederholungszahlen beginnen, dann schrittweise steigern."],"cable_setup":null,"muscle_focus":["Drehachse der Maschine auf Kniehöhe und das Polster knapp über dem Sprunggelenk einstellen, damit der Widerstand über den ganzen Hebel auf den Quadrizeps wirkt.","Rückenlehne eher nach hinten geneigt einstellen, so wird der gerade Oberschenkelmuskel über die Hüfte vorgedehnt und arbeitet stärker mit.","Unten bis etwa 90 Grad oder tiefer zurückführen, soweit die Knie beschwerdefrei bleiben, oben ein bis zwei Sekunden halten; das Becken bleibt am Polster.","Exzentrische Phase zwei bis drei Sekunden kontrollieren, kein Schwung aus der unteren Position."],"requirements":["Beinstrecker-Maschine mit verstellbarer Rückenlehne und Beinpolster"],"grip_alternatives":[],"image_url":"/exercises/leg-extension-curl.jpg","machine_name":"DHZ Leg Extension / Leg Curl, Steckgewicht","alternative_exercises":["beinbeuger"]}$seed$::jsonb);

-- Bulgarian Split Squat
select public.upsert_seed_exercise($seed${"slug":"bulgarian-split-squat","name":"Bulgarian Split Squat","category":"quads","equipment":"dumbbell","grip_id":null,"grip_notes":"Kurzhanteln neutral an den Seiten halten, Arme hängen locker, Handgelenke gerade. Alternativ eine Kurzhantel vor der Brust halten (Goblet-Position) für mehr Rumpfstabilität.","primary_muscles":["quads","glutes"],"secondary_muscles":["hamstrings","abs"],"description":"Einbeinige Kniebeuge mit dem hinteren Fuß auf einer Bank, bei der das vordere Bein die Hauptlast trägt. Gut geeignet, um Quadrizeps und Gesäß einseitig zu belasten und Seitenunterschiede auszugleichen.","setup":["Bank hinter sich aufstellen, Kurzhanteln an den Seiten halten.","Mit dem Rücken zur Bank einen großen Schritt nach vorne machen.","Hinteren Fuß mit dem Fußrücken oder den Zehen auf der Bank ablegen.","Vorderer Fuß steht flach und so weit vorne, dass das Knie unten etwa über dem Mittelfuß bleibt.","Oberkörper aufrecht, Blick nach vorne, Rumpf anspannen."],"execution":["Vorderes Knie kontrolliert beugen und das Becken gerade nach unten absenken.","Vorderes Knie zeigt in Richtung Fußspitze, Ferse bleibt am Boden.","Hinteres Knie nähert sich dem Boden, ohne aufzusetzen.","Oberkörper bleibt aufrecht oder leicht nach vorne geneigt.","Über die ganze Fußsohle des vorderen Fußes nach oben drücken.","Oben Knie nicht durchstrecken, Spannung halten.","Nach allen Wiederholungen die Seite wechseln."],"range_of_motion":"Absenken, bis der vordere Oberschenkel etwa parallel zum Boden steht oder das hintere Knie knapp über dem Boden ist, je nach Beweglichkeit. Oben kurz vor der vollen Streckung stoppen.","breathing":"Beim Hochdrücken ausatmen, beim Absenken einatmen.","common_mistakes":["Vorderer Fuß steht zu nah an der Bank, Knie wandert weit über die Fußspitze.","Vorderes Knie fällt nach innen.","Oberkörper kippt stark nach vorne oder dreht sich ein.","Hinteres Bein drückt aktiv mit und übernimmt einen Teil der Arbeit.","Ferse des vorderen Fußes hebt sich vom Boden ab."],"tips":["Zuerst ohne Zusatzgewicht die Fußposition finden, dann Kurzhanteln hinzunehmen.","Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Leichte Vorlage des Oberkörpers betont das Gesäß, aufrechte Haltung mehr den Quadrizeps.","Bei Gleichgewichtsproblemen mit einer Hand leicht an einem Rack abstützen."],"cable_setup":null,"muscle_focus":["Tief absenken, bis das hintere Knie knapp über dem Boden ist; das vordere Bein trägt die Last, die tiefe Position belastet Quadrizeps und Gesäß in der Dehnung.","Vorderes Knie in Richtung Fußspitze führen und die Ferse am Boden lassen; aufrechter Oberkörper betont den Quadrizeps, leichte Vorlage das Gesäß.","Hinteres Bein nur zum Ausbalancieren nutzen, nicht aktiv mitdrücken.","Exzentrische Phase etwa zwei Sekunden kontrollieren, oben kurz vor der Kniestreckung stoppen."],"requirements":["Kurzhanteln","Flachbank für den hinteren Fuß","Optional: Rack oder Wand zum Abstützen bei Gleichgewichtsproblemen"],"grip_alternatives":[],"alternative_exercises":[]}$seed$::jsonb);

-- Kniebeuge
select public.upsert_seed_exercise($seed${"slug":"kniebeuge","name":"Kniebeuge","category":"quads","equipment":"barbell","grip_id":null,"grip_notes":"Pronierter Griff etwas weiter als schulterbreit, Stange liegt auf dem oberen Trapez (High Bar) oder etwas tiefer auf den hinteren Schultern (Low Bar). Handgelenke möglichst gerade, Ellenbogen zeigen nach unten.","primary_muscles":["quads","glutes"],"secondary_muscles":["hamstrings","lower_back","abs"],"description":"Freie Kniebeuge mit der Langhantel im Nacken, bei der Knie und Hüfte gemeinsam gebeugt und gestreckt werden. Grundübung für Quadrizeps und Gesäß, die zusätzlich Rumpf und unteren Rücken fordert.","setup":["Stange im Rack etwa auf Höhe des oberen Brustbeins ablegen, Sicherheitsstangen knapp unterhalb der tiefsten Position einstellen.","Unter die Stange treten, Stange auf dem oberen Trapez ablegen und Griff etwas weiter als schulterbreit fassen.","Schulterblätter zusammenziehen, Rumpf anspannen und Stange aus dem Rack heben.","Ein bis zwei kleine Schritte zurück, Füße etwa schulterbreit, Fußspitzen leicht nach außen.","Blick nach vorne, Stange steht über dem Mittelfuß."],"execution":["Vor dem Absenken einatmen und den Rumpf anspannen.","Hüfte und Knie gleichzeitig beugen, Becken nach hinten und unten absenken.","Knie zeigen in Richtung Fußspitzen, Fersen bleiben am Boden.","So tief absenken, wie der Rücken neutral bleibt.","Über die ganze Fußsohle nach oben drücken, Hüfte und Schultern steigen gemeinsam.","Oben aufrecht stehen, Knie nicht hart durchstrecken.","Nach dem letzten Satz Stange kontrolliert zurück ins Rack führen."],"range_of_motion":"Tiefe nach Beweglichkeit wählen, in der Regel bis die Oberschenkel etwa parallel zum Boden stehen oder tiefer. Sobald das Becken unten einrollt oder die Fersen abheben, ist der sinnvolle Bewegungsradius erreicht.","breathing":"Oben einatmen und die Spannung während des Absenkens halten, beim Hochdrücken nach dem schwersten Punkt ausatmen.","common_mistakes":["Knie fallen nach innen.","Fersen heben sich vom Boden ab, Gewicht verlagert sich auf die Zehen.","Hüfte steigt beim Hochdrücken schneller als die Schultern, Oberkörper kippt nach vorne.","Unterer Rücken rundet sich in der tiefen Position.","Sicherheitsstangen werden nicht eingestellt oder liegen zu hoch."],"tips":["Technik zuerst mit der leeren Stange oder leichtem Gewicht festigen.","Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Bei eingeschränkter Sprunggelenkbeweglichkeit Fersen leicht erhöhen oder Schuhe mit erhöhter Ferse nutzen.","Gewicht in kleinen Schritten steigern, wenn Tiefe und Rückenposition stabil bleiben."],"cable_setup":null,"muscle_focus":["So tief gehen, wie der Rücken neutral bleibt, in der Regel bis die Oberschenkel mindestens parallel stehen; die tiefe Position belastet Quadrizeps und Gesäß in der gedehnten Stellung.","Knie in Richtung Fußspitzen führen und das Gewicht über dem Mittelfuß halten; die Fersen bleiben am Boden.","Hüfte und Schultern gemeinsam anheben; steigt die Hüfte zuerst, wandert die Last vom Quadrizeps in Rücken und Hüfte.","Absenken etwa zwei Sekunden kontrollieren und unten nicht abfedern."],"requirements":["Langhantel und Rack mit Sicherheitsstangen","Hantelscheiben mit Verschlüssen","Optional: Schuhe mit erhöhter Ferse"],"grip_alternatives":[],"image_url":"/exercises/half-rack.jpg","machine_name":"Half Rack mit Plattform","alternative_exercises":["multipresse-kniebeuge","hackenschmidt"]}$seed$::jsonb);

-- Ausfallschritte
select public.upsert_seed_exercise($seed${"slug":"ausfallschritte","name":"Ausfallschritte","category":"glutes","equipment":"dumbbell","grip_id":null,"grip_notes":"Kurzhanteln neutral an den Seiten halten, Arme hängen locker, Schultern hinten. Handgelenke gerade.","primary_muscles":["glutes","quads"],"secondary_muscles":["hamstrings","abs"],"description":"Schrittbewegung mit Kurzhanteln, bei der ein Bein nach vorne gesetzt und das Becken abgesenkt wird, entweder gehend (Walking Lunges) oder auf der Stelle. Gut geeignet für Gesäß und Oberschenkel sowie für Gleichgewicht und einseitige Stabilität.","setup":["Kurzhanteln an den Seiten halten, Füße hüftbreit, Oberkörper aufrecht.","Ausreichend Platz nach vorne sicherstellen, besonders bei gehender Ausführung.","Rumpf anspannen, Blick nach vorne.","Schrittlänge so wählen, dass das vordere Knie unten etwa über dem Mittelfuß bleibt."],"execution":["Mit einem Bein einen großen Schritt nach vorne machen und den Fuß flach aufsetzen.","Becken gerade nach unten absenken, beide Knie beugen sich.","Vorderes Knie zeigt in Richtung Fußspitze, Ferse bleibt am Boden.","Hinteres Knie nähert sich dem Boden, ohne hart aufzusetzen.","Über die ganze Fußsohle des vorderen Fußes nach oben drücken.","Bei Walking Lunges das hintere Bein direkt in den nächsten Schritt führen, auf der Stelle zurück in die Ausgangsposition.","Seiten gleichmäßig abwechseln."],"range_of_motion":"Absenken, bis der vordere Oberschenkel etwa parallel zum Boden steht und das hintere Knie knapp über dem Boden ist, je nach Beweglichkeit. Oben kurz vor der vollen Kniestreckung stoppen.","breathing":"Beim Hochdrücken ausatmen, beim Absenken einatmen.","common_mistakes":["Schritt zu kurz, vorderes Knie wandert weit über die Fußspitze.","Vorderes Knie fällt nach innen.","Oberkörper kippt nach vorne oder dreht sich zur Seite.","Hinteres Knie schlägt auf den Boden auf.","Abdruck erfolgt über die Zehen statt über die ganze Fußsohle."],"tips":["Zuerst ohne Zusatzgewicht die Schrittlänge finden, dann Kurzhanteln hinzunehmen.","Leichte Vorlage des Oberkörpers betont das Gesäß stärker.","Exzentrische Phase kontrolliert ausführen, nicht in die untere Position fallen.","Bei Gleichgewichtsproblemen Ausfallschritte auf der Stelle statt gehend ausführen."],"cable_setup":null,"muscle_focus":["Großen Schritt wählen und das Becken gerade absenken, bis das hintere Knie knapp über dem Boden ist; so werden Gesäß und Quadrizeps des vorderen Beins in der gedehnten Position belastet.","Über die ganze Fußsohle des vorderen Fußes hochdrücken, Knie in Richtung Fußspitze; leichte Vorlage des Oberkörpers betont das Gesäß.","Rumpf stabil und Oberkörper ruhig halten, kein Eindrehen oder Pendeln.","Absenken kontrolliert ausführen und nicht in die untere Position fallen."],"requirements":["Kurzhanteln","Bank oder Ablage zum Aufnehmen und Abstellen der Kurzhanteln","Ausreichend Platz nach vorne, besonders bei gehender Ausführung"],"grip_alternatives":[],"alternative_exercises":[]}$seed$::jsonb);

-- Beinbeuger
select public.upsert_seed_exercise($seed${"slug":"beinbeuger","name":"Beinbeuger","category":"hamstrings","equipment":"machine","grip_id":null,"grip_notes":"Haltegriffe fassen, um Becken und Oberkörper stabil zu halten. Liegend: Griffe vorne unter dem Polster, Hüfte bleibt auf dem Polster. Sitzend: Griffe seitlich, Rücken am Polster, Oberschenkelpolster fest fixiert.","primary_muscles":["hamstrings"],"secondary_muscles":["calves","glutes"],"description":"Isolationsübung an der Maschine, bei der die Knie gegen Widerstand gebeugt werden, liegend oder sitzend. Gut geeignet, um die hintere Oberschenkelmuskulatur gezielt zu trainieren.","setup":["Maschine so einstellen, dass die Drehachse auf Höhe des Kniegelenks liegt.","Beinpolster knapp oberhalb der Ferse an der Achillessehne anlegen.","Liegend: Hüfte flach auf dem Polster, Oberkörper abgelegt, Griffe fassen.","Sitzend: Rücken am Polster, Oberschenkelpolster fest auf den Oberschenkeln fixieren, Griffe fassen.","Beine in der Startposition fast gestreckt, Fußspitzen leicht angezogen."],"execution":["Fersen kontrolliert in Richtung Gesäß ziehen.","Becken bleibt dabei stabil auf oder am Polster.","In der Endposition kurz halten und die hinteren Oberschenkel anspannen.","Gewicht langsam zurückführen, bis die Beine fast gestreckt sind.","Gewicht nicht aufsetzen lassen, Spannung halten.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von fast gestreckten Beinen bis zu einem Kniewinkel von etwa 90 Grad oder enger, soweit das Becken stabil bleibt. Die Dehnung in der gestreckten Position bewusst kontrollieren.","breathing":"Beim Beugen ausatmen, beim Strecken einatmen.","common_mistakes":["Hüfte hebt sich liegend vom Polster ab, unterer Rücken überstreckt.","Gewicht wird mit Schwung nach oben gezogen.","Beine werden am Ende nicht wieder kontrolliert gestreckt.","Polster liegt zu hoch an der Wade, Hebel wird ungünstig.","Sitzend: Oberschenkelpolster zu locker, Oberschenkel heben sich ab."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Sitzende Variante erlaubt eine stärkere Dehnung, liegende Variante eine stärkere Endkontraktion; beide lassen sich abwechseln.","Einbeinige Ausführung, um Seitenunterschiede auszugleichen.","Fußspitzen gestreckt halten, um den Anteil der Waden zu verringern und die hinteren Oberschenkel stärker zu betonen."],"cable_setup":null,"muscle_focus":["Startposition mit fast gestreckten Beinen einnehmen und die gedehnte Position bewusst mitnehmen; sitzend lässt sich die Dehnung durch einen leicht nach vorne geneigten Oberkörper verstärken.","Drehachse auf Kniehöhe und Polster knapp über der Ferse einstellen, dann wirkt der Widerstand sauber auf die hintere Oberschenkelmuskulatur.","Becken stabil auf bzw. am Polster lassen; Anheben der Hüfte oder Schwung verlagert die Arbeit in den unteren Rücken.","Fußspitzen eher gestreckt halten, um den Wadenanteil zu verringern, und die Rückführung zwei bis drei Sekunden kontrollieren."],"requirements":["Beinbeuger-Maschine, liegend oder sitzend, mit verstellbarer Drehachse und Beinpolster"],"grip_alternatives":[],"image_url":"/exercises/seated-leg-curl.jpg","machine_name":"DHZ Seated Leg Curl, Steckgewicht","alternative_exercises":["beinstrecker"]}$seed$::jsonb);

-- Rumänisches Kreuzheben
select public.upsert_seed_exercise($seed${"slug":"rumaenisches-kreuzheben","name":"Rumänisches Kreuzheben","category":"hamstrings","equipment":"barbell","grip_id":null,"grip_notes":"Pronierter Griff etwa schulterbreit, Stange nah an den Oberschenkeln. Bei nachlassender Griffkraft Zughilfen nutzen.","primary_muscles":["hamstrings","glutes"],"secondary_muscles":["lower_back","forearms","upper_back"],"description":"Hüftdominante Beugebewegung mit der Langhantel, bei der die Knie leicht gebeugt bleiben und die Stange nah am Körper abgesenkt wird. Gut geeignet, um hintere Oberschenkel und Gesäß über eine Dehnung zu belasten.","setup":["Stange aus dem Rack oder vom Boden in den aufrechten Stand bringen, Füße hüftbreit.","Pronierter Griff etwa schulterbreit, Arme gestreckt, Stange liegt an den Oberschenkeln.","Knie leicht beugen und diesen Winkel während der Bewegung beibehalten.","Schulterblätter leicht nach hinten ziehen, Brust angehoben, Rücken neutral.","Rumpf anspannen, Gewicht auf der ganzen Fußsohle."],"execution":["Hüfte nach hinten schieben, Oberkörper neigt sich nach vorne.","Stange gleitet nah an den Oberschenkeln nach unten.","Rücken bleibt neutral, Blick folgt dem Oberkörper.","So tief absenken, wie der Rücken neutral bleibt und die Dehnung in den hinteren Oberschenkeln spürbar ist.","Hüfte nach vorne schieben und aufrichten, Gesäß anspannen.","Oben aufrecht stehen, unteren Rücken nicht überstrecken."],"range_of_motion":"Von der aufrechten Position bis die Stange etwa auf Höhe der Knie oder des oberen Schienbeins ist. Die Tiefe wird durch die neutrale Rückenposition begrenzt, nicht durch den Boden.","breathing":"Oben einatmen, während des Absenkens die Spannung halten, beim Aufrichten ausatmen.","common_mistakes":["Unterer Rücken rundet sich in der tiefen Position.","Stange entfernt sich vom Körper, Hebel auf den unteren Rücken steigt.","Knie werden stark gebeugt, Bewegung wird zur Kniebeuge.","Oben wird der untere Rücken überstreckt.","Schultern hängen nach vorne, Oberkörper verliert die Spannung."],"tips":["Technik zuerst mit leichtem Gewicht festigen und auf die Dehnung in den hinteren Oberschenkeln achten.","Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Zughilfen nutzen, wenn die Griffkraft vor den hinteren Oberschenkeln nachlässt.","Alternativ mit Kurzhanteln ausführen, wenn keine Langhantel verfügbar ist."],"cable_setup":null,"muscle_focus":["Hüfte aktiv nach hinten schieben und die Stange nah an den Oberschenkeln absenken, bis eine deutliche Dehnung in den hinteren Oberschenkeln spürbar ist; dieser gedehnte Bereich ist der wichtigste Teil der Bewegung.","Kniewinkel leicht gebeugt und über die ganze Bewegung konstant halten; stärkere Kniebeugung verlagert die Arbeit auf den Quadrizeps.","Rücken neutral und Schulterblätter leicht zurückgezogen; die Tiefe wird durch die neutrale Wirbelsäule begrenzt, nicht durch den Boden.","Absenken zwei bis drei Sekunden kontrollieren, oben über das Gesäß aufrichten und den unteren Rücken nicht überstrecken."],"requirements":["Langhantel mit Hantelscheiben und Verschlüssen; alternativ Kurzhanteln","Optional: Zughilfen bei nachlassender Griffkraft"],"grip_alternatives":[],"image_url":"/exercises/half-rack.jpg","machine_name":"Half Rack mit Plattform","alternative_exercises":["hyperextensions"]}$seed$::jsonb);

-- Hip Thrust
select public.upsert_seed_exercise($seed${"slug":"hip-thrust","name":"Hip Thrust","category":"glutes","equipment":"barbell","grip_id":null,"grip_notes":"Stange mit proniertem Griff etwa schulterbreit außen am Polster halten, nur zum Stabilisieren, nicht ziehen. Alternativ: Hip-Thrust-Maschine mit Gurt oder Polster über der Hüfte, Haltegriffe seitlich.","primary_muscles":["glutes"],"secondary_muscles":["hamstrings","quads"],"description":"Hüftstreckung gegen Widerstand mit dem oberen Rücken auf einer Bank und der Langhantel auf der Hüfte. Gut geeignet, um das Gesäß in der gestreckten Endposition stark zu belasten.","setup":["Stabile Bank quer hinter sich stellen, Höhe etwa Kniehöhe.","Polster auf die Stange legen und Stange über die Hüfte rollen.","Oberen Rücken unterhalb der Schulterblätter auf der Bankkante ablegen.","Füße hüftbreit so aufstellen, dass die Unterschenkel in der Endposition etwa senkrecht stehen.","Rippen nach unten, Kinn leicht eingezogen, Rumpf anspannen."],"execution":["Über die Fersen die Hüfte nach oben drücken.","Gesäß in der Endposition bewusst anspannen, Hüfte vollständig gestreckt.","Oben bilden Schultern, Hüfte und Knie eine Linie, unterer Rücken bleibt neutral.","Ein bis zwei Sekunden oben halten.","Hüfte kontrolliert absenken, bis die Stange knapp über dem Boden ist.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von knapp über dem Boden bis zur vollständigen Hüftstreckung. Die Endposition wird durch das Gesäß erreicht, nicht durch Überstrecken des unteren Rückens.","breathing":"Beim Hochdrücken ausatmen, beim Absenken einatmen.","common_mistakes":["Unterer Rücken wird oben überstreckt, statt die Hüfte zu strecken.","Kopf kippt nach hinten, Blick geht an die Decke.","Füße stehen zu weit vorne, Belastung geht in die hinteren Oberschenkel.","Füße stehen zu nah am Gesäß, Quadrizeps übernimmt.","Bewegung wird mit Schwung ausgeführt, keine Pause oben."],"tips":["Blick während der gesamten Bewegung in Richtung Knie halten.","Oben ein bis zwei Sekunden halten und das Gesäß bewusst anspannen.","Gewichtsscheiben mit Stoppern gegen Verrutschen sichern und Bank gegen Wegrutschen fixieren.","Zu Beginn Technik ohne Zusatzgewicht oder nur mit der Stange üben."],"cable_setup":null,"muscle_focus":["Oberen Rücken unterhalb der Schulterblätter auf die Bankkante legen und die Füße so platzieren, dass die Unterschenkel oben senkrecht stehen; so trägt das Gesäß die Hauptlast.","Hüfte vollständig strecken und oben ein bis zwei Sekunden bewusst anspannen; das Gesäß arbeitet in der gestreckten Endposition am stärksten.","Rippen unten und Kinn leicht eingezogen halten, damit die Streckung aus der Hüfte und nicht aus der Lendenwirbelsäule kommt.","Absenken kontrolliert, bis die Hüfte knapp über dem Boden ist, ohne das Gewicht abzusetzen."],"requirements":["Stabile Bank, Höhe etwa Kniehöhe, gegen Wegrutschen gesichert","Langhantel mit Polster (Hip-Thrust-Pad) und Hantelscheiben mit Verschlüssen; alternativ Hip-Thrust-Maschine"],"grip_alternatives":[],"alternative_exercises":[]}$seed$::jsonb);

-- Kabel Kickback
select public.upsert_seed_exercise($seed${"slug":"kabel-kickback","name":"Kabel Kickback","category":"glutes","equipment":"cable","grip_id":"ankle_strap","grip_notes":"Fußschlaufe am Sprunggelenk des Arbeitsbeins befestigen, fest, aber nicht einschnürend. Hände stützen sich am Kabelturm ab. Alternativ eine gepolsterte Manschette nutzen, wenn vorhanden.","primary_muscles":["glutes"],"secondary_muscles":["hamstrings"],"description":"Einbeinige Hüftstreckung am unteren Kabelzug mit Fußschlaufe, bei der das Bein nach hinten-oben geführt wird. Gut geeignet als Isolationsübung für das Gesäß mit leichtem bis moderatem Gewicht.","setup":["Fußschlaufe am unteren Kabel einhängen und am Sprunggelenk des Arbeitsbeins befestigen.","Mit dem Gesicht zum Kabelturm stellen, Hände am Turm abstützen.","Oberkörper leicht nach vorne neigen, Rücken neutral, Rumpf anspannen.","Standbein leicht gebeugt, Gewicht auf der ganzen Fußsohle.","Arbeitsbein leicht vor dem Körper, Spannung im Kabel aufnehmen."],"execution":["Arbeitsbein kontrolliert nach hinten-oben führen, Knie bleibt fast gestreckt.","Bewegung kommt aus der Hüfte, Gesäß anspannen.","Becken bleibt stabil, unterer Rücken überstreckt nicht.","In der Endposition ein bis zwei Sekunden halten.","Bein langsam zurückführen, bis es leicht vor dem Körper ist.","Nach allen Wiederholungen die Seite wechseln."],"range_of_motion":"Vom leichten Vorschwung bis zur vollständigen Hüftstreckung. Die Höhe des Beins wird durch die stabile Beckenposition begrenzt, nicht durch Überstrecken des Rückens.","breathing":"Beim Führen des Beins nach hinten ausatmen, beim Zurückführen einatmen.","common_mistakes":["Unterer Rücken überstreckt, um das Bein höher zu bringen.","Bewegung wird mit Schwung aus dem Vorschwung ausgeführt.","Oberkörper dreht sich ein oder weicht zur Seite aus.","Knie des Arbeitsbeins beugt sich stark, Bewegung wird zum Beinbeugen.","Zu viel Gewicht, Bewegungsradius wird klein."],"tips":["Leichtes bis moderates Gewicht wählen und auf die Kontraktion im Gesäß konzentrieren.","Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Fußspitze des Arbeitsbeins leicht nach außen drehen, um das Gesäß stärker zu spüren.","Höhere Wiederholungszahlen (12 bis 20) sind bei dieser Übung sinnvoll."],"cable_setup":{"cable":"Kabelturm mit unterer Rolle, ein Kabel (eine Seite des Doppelkabelzugs)","height":"ganz unten, damit der Zug von vorne-unten kommt und das Gesäß über die gesamte Hüftstreckung belastet wird","grip_width":"Keine Griffarbeit, Fußschlaufe am Sprunggelenk; Hände stützen sich am Turm ab","body_position":"Stehend mit dem Gesicht zum Turm, Oberkörper leicht nach vorne geneigt, Rücken neutral, Rumpf angespannt, Hände am Turm","foot_position":"Standbein leicht gebeugt, Fuß flach auf dem Boden; Arbeitsbein mit Schlaufe leicht vor dem Körper","movement_direction":"Bein nach hinten-oben, in Verlängerung des Rumpfes","elbow_position":"Arme leicht gebeugt am Turm, dienen nur der Stabilisierung","end_position":"Bein hinter dem Körper, Hüfte vollständig gestreckt, Gesäß angespannt, Becken stabil","return":"Langsam und kontrolliert über etwa zwei Sekunden, bis das Bein leicht vor dem Körper ist, ohne dass das Gewicht aufsetzt"},"muscle_focus":["Arbeitsbein in der Startposition leicht vor dem Körper führen, damit das Gesäß in leichter Hüftbeugung, also in der gedehnten Position, unter Last steht.","Bewegung ausschließlich aus der Hüfte: Knie fast gestreckt und Becken stabil; die Endposition ist die volle Hüftstreckung, nicht ein möglichst hohes Bein.","Oberkörper leicht nach vorne geneigt und Rumpf angespannt; Überstrecken des unteren Rückens verlagert die Arbeit weg vom Gesäß.","Oben ein bis zwei Sekunden halten, Rückführung etwa zwei Sekunden kontrollieren."],"requirements":["Kabelturm mit unterer Rolle","Fußschlaufe (Ankle Strap) oder gepolsterte Manschette"],"grip_alternatives":[],"alternative_exercises":[]}$seed$::jsonb);

-- Wadenheben stehend
select public.upsert_seed_exercise($seed${"slug":"wadenheben-stehend","name":"Wadenheben stehend","category":"calves","equipment":"machine","grip_id":null,"grip_notes":"Haltegriffe oder Schulterpolster der stehenden Wadenmaschine nutzen, Hände bleiben locker. Alternativ: Smith-Maschine mit Stange im Nacken oder Stufe mit Kurzhantel in einer Hand und Abstützen mit der anderen.","primary_muscles":["calves"],"secondary_muscles":[],"description":"Plantarflexion im Stand gegen Widerstand, bei der die gesamte Wadenmuskulatur einschließlich des zweigelenkigen Gastrocnemius belastet wird. Gut geeignet als Grundübung für die Waden.","setup":["Schulterpolster so einstellen, dass die Beine im Stand fast gestreckt sind und das Gewicht leicht abhebt.","Fußballen auf die Kante der Plattform stellen, Fersen frei, Füße hüftbreit.","Knie fast gestreckt, aber nicht durchgedrückt.","Rumpf anspannen, Oberkörper aufrecht.","Fersen kontrolliert absenken, um die Startposition in der Dehnung einzunehmen."],"execution":["Fersen so hoch wie möglich anheben, auf die Fußballen drücken.","In der oberen Position ein bis zwei Sekunden halten.","Fersen langsam absenken, bis eine deutliche Dehnung in der Wade spürbar ist.","In der unteren Position kurz halten, ohne zu federn.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Volle Dehnung unten mit Fersen deutlich unter der Plattformkante bis zum höchsten Punkt auf den Fußballen. Der Kniewinkel bleibt während der gesamten Bewegung gleich.","breathing":"Beim Anheben der Fersen ausatmen, beim Absenken einatmen.","common_mistakes":["Bewegung wird federnd und mit Schwung aus der Dehnung ausgeführt.","Knie werden während der Bewegung gebeugt und gestreckt.","Bewegungsradius ist zu klein, keine Dehnung unten.","Füße rutschen auf der Plattform nach vorne.","Oberkörper kippt nach vorne oder hinten."],"tips":["Oben kurze Pause einlegen, unten die Dehnung ein bis zwei Sekunden halten.","Höhere Wiederholungszahlen (12 bis 20) mit vollem Bewegungsradius sind bei Waden in der Regel sinnvoll.","Einbeinige Ausführung, um Seitenunterschiede auszugleichen.","Ohne Maschine: Stufe mit Kurzhantel in einer Hand, andere Hand stützt sich ab."],"cable_setup":null,"muscle_focus":["Fersen tief unter die Plattformkante absenken und die Dehnung unten ein bis zwei Sekunden halten; in dieser gedehnten Position reagiert die Wade am stärksten auf das Training.","Knie fast gestreckt und den Kniewinkel konstant halten, so arbeitet vor allem der zweigelenkige Gastrocnemius; das sitzende Wadenheben betont dagegen den Soleus.","Oben auf den Fußballen hochdrücken und kurz halten, dann langsam über zwei bis drei Sekunden absenken, nicht federn.","Oberkörper aufrecht und ruhig halten, kein Mitschwingen aus Hüfte oder Knie."],"requirements":["Stehende Wadenmaschine mit Schulterpolstern; alternativ Multipresse mit Stufe oder Kurzhanteln in den Händen auf einer Stufe","Stufe oder Plattformkante, damit die Fersen frei absinken können"],"grip_alternatives":[],"image_url":"/exercises/standing-calf-raise.jpg","machine_name":"DHZ Standing Calf Raise, Plate Loaded","alternative_exercises":["wadenheben-sitzend"]}$seed$::jsonb);

-- Wadenheben sitzend
select public.upsert_seed_exercise($seed${"slug":"wadenheben-sitzend","name":"Wadenheben sitzend","category":"calves","equipment":"machine","grip_id":null,"grip_notes":"Haltegriffe am Oberschenkelpolster fassen, um das Polster zu sichern und den Oberkörper stabil zu halten. Hände bleiben locker, keine Zugarbeit.","primary_muscles":["calves"],"secondary_muscles":[],"description":"Plantarflexion im Sitzen gegen Widerstand mit gebeugten Knien, bei der vor allem der Soleus belastet wird, weil der Gastrocnemius durch die Kniebeugung entlastet ist. Sinnvolle Ergänzung zum stehenden Wadenheben.","setup":["Polster so einstellen, dass es fest auf dem unteren Oberschenkel knapp oberhalb der Knie aufliegt.","Fußballen auf die Kante der Plattform stellen, Fersen frei, Füße hüftbreit.","Knie etwa im rechten Winkel, Oberkörper aufrecht.","Haltegriffe fassen und die Sicherung der Maschine lösen.","Fersen kontrolliert absenken, um die Startposition in der Dehnung einzunehmen.","Ohne Maschine: Auf Flachbank oder Hocker setzen, Fußballen auf die Kante einer Stufe oder Hantelscheibe stellen, Fersen tief, Kurzhanteln oder Langhantel mit Polster auf den Oberschenkeln nahe den Knien ablegen."],"execution":["Fersen so hoch wie möglich anheben, auf die Fußballen drücken.","In der oberen Position ein bis zwei Sekunden halten.","Fersen langsam absenken, bis eine deutliche Dehnung in der Wade spürbar ist.","Unten kurz halten, ohne zu federn.","Nächste Wiederholung ohne Schwung beginnen.","Bei der Hantelvariante die Last mit den Händen auf den Oberschenkeln nahe den Knien sichern und die Fersen unten bewusst tief unter die Kante absenken."],"range_of_motion":"Volle Dehnung unten bis zum höchsten Punkt auf den Fußballen. Der Kniewinkel bleibt während der gesamten Bewegung gleich, damit der Soleus gezielt arbeitet.","breathing":"Beim Anheben der Fersen ausatmen, beim Absenken einatmen.","common_mistakes":["Bewegung wird federnd und mit Schwung aus der Dehnung ausgeführt.","Bewegungsradius ist zu klein, keine Dehnung unten.","Polster liegt zu weit oben auf dem Oberschenkel, Hebel wird ungünstig.","Oberkörper wird nach vorne gebeugt, um mit dem Rücken mitzuhelfen."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Höhere Wiederholungszahlen (12 bis 20) mit vollem Bewegungsradius sind hier sinnvoll.","Mit stehendem Wadenheben kombinieren, um Gastrocnemius und Soleus gemeinsam zu trainieren."],"cable_setup":null,"muscle_focus":["Fersen tief absenken und die Dehnung unten ein bis zwei Sekunden halten; die gedehnte Position ist der wirksamste Teil der Bewegung.","Knie etwa im rechten Winkel halten; durch die Kniebeugung ist der Gastrocnemius entlastet und der Soleus übernimmt die Arbeit.","Last nahe an den Knien auf den Oberschenkeln, oben auf den Fußballen hochdrücken und kurz halten, Absenken über zwei bis drei Sekunden kontrollieren.","Oberkörper ruhig lassen, nicht mit dem Rücken oder durch Federn mithelfen."],"requirements":["Sitzende Wadenmaschine; alternativ Flachbank oder Hocker, Kurzhanteln auf den Knien oder Langhantel mit Polster auf den Oberschenkeln, Stufe oder Hantelscheibe unter den Fußballen"],"grip_alternatives":[],"alternative_exercises":["wadenheben-stehend"]}$seed$::jsonb);

-- Incline Curl
select public.upsert_seed_exercise($seed${"slug":"incline-curl","name":"Incline Curl","category":"biceps","equipment":"dumbbell","grip_id":null,"grip_notes":"Supinierter Griff (Handflächen zeigen nach vorne bzw. oben), Kurzhanteln locker aber sicher umschließen. Handgelenke gerade halten, nicht einknicken.","primary_muscles":["biceps"],"secondary_muscles":["forearms"],"description":"Kurzhantelcurl auf der Schrägbank, bei dem die Arme seitlich und leicht hinter dem Körper hängen. Durch die vorgedehnte Position wird der Bizeps über einen großen Bewegungsradius belastet.","setup":["Rückenlehne der Bank auf etwa 45 bis 60 Grad einstellen.","Kurzhanteln aufnehmen und sich mit dem Rücken vollständig an die Lehne setzen.","Kopf und oberer Rücken liegen an, Füße flach auf dem Boden.","Arme seitlich und leicht hinter der Körperlinie hängen lassen, Handflächen zeigen nach vorne.","Schultern nach hinten und unten ziehen, Oberarme ruhig halten."],"execution":["Kurzhanteln kontrolliert nach oben curlen, nur der Unterarm bewegt sich.","Oberarme bleiben während der gesamten Bewegung an ihrer Position.","In der oberen Position den Bizeps kurz bewusst anspannen.","Gewicht langsam absenken, bis die Arme fast gestreckt sind.","Am unteren Ende die Dehnung im Bizeps spüren, ohne die Ellenbogen hart durchzustrecken.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von fast gestreckten Armen in der gedehnten Position bis zur vollen Beugung, soweit die Oberarme an ihrer Position bleiben. Unten nicht in die Ellenbogen fallen lassen.","breathing":"Beim Curlen ausatmen, beim Absenken einatmen.","common_mistakes":["Oberarme wandern beim Curlen nach vorne, dadurch geht die Vordehnung verloren.","Schultern rollen nach vorne und lösen sich von der Lehne.","Gewicht wird unten fallen gelassen statt kontrolliert abgesenkt.","Handgelenke knicken beim Curlen nach innen ein.","Zu viel Gewicht, sodass der Oberkörper mitschwingt."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Eher leichteres Gewicht wählen als bei stehenden Curls, da die gedehnte Position mehr fordert.","Wenn die Schulter in der gedehnten Position unangenehm ist, Bank etwas steiler stellen."],"cable_setup":null,"muscle_focus":["Oberarme seitlich und leicht hinter der Körperlinie hängen lassen, damit der lange Bizepskopf in der gedehnten Position arbeitet; diese Position liefert nach aktuellem Stand einen hohen Reiz.","Nur den Unterarm bewegen, Oberarme bleiben über den gesamten Satz an ihrer Position; wandern die Ellenbogen nach vorne, geht die Vordehnung verloren.","Unten bis fast zur vollen Streckung absenken und zwei bis drei Sekunden lang kontrollieren, ohne in die Ellenbogen zu fallen.","Schultern hinten an der Lehne lassen und ein Gewicht wählen, bei dem der Bizeps und nicht der Oberkörper limitiert."],"requirements":["Verstellbare Schrägbank (45–60 Grad)","Kurzhanteln"],"grip_alternatives":[],"alternative_exercises":[]}$seed$::jsonb);

-- Incline Curl hinterm Körper
select public.upsert_seed_exercise($seed${"slug":"incline-curl-hinterm-koerper","name":"Incline Curl hinterm Körper","category":"biceps","equipment":"dumbbell","grip_id":null,"grip_notes":"Supinierter Griff, Handflächen zeigen während der gesamten Bewegung nach vorne bzw. oben. Handgelenke gerade, kein Umklappen in der oberen Position.","primary_muscles":["biceps"],"secondary_muscles":["forearms","front_delts"],"description":"Variante des Incline Curls mit steilerer Bank, bei der die Oberarme bewusst hinter der Körperlinie bleiben. Dadurch wird der lange Bizepskopf in einer stark gedehnten Position belastet.","setup":["Rückenlehne der Bank auf etwa 60 bis 75 Grad einstellen.","Kurzhanteln aufnehmen und sich mit Rücken und Kopf vollständig anlehnen.","Füße flach auf den Boden stellen, Rumpf anspannen.","Arme hängen lassen und die Oberarme bewusst leicht hinter die Körperlinie bringen.","Schultern nach hinten und unten ziehen, Brust leicht anheben."],"execution":["Kurzhanteln kontrolliert nach oben curlen, Ellenbogen bleiben hinter der Körperlinie.","Nur der Unterarm bewegt sich, der Oberarm bleibt an seiner Position.","Oben den Bizeps kurz anspannen, ohne die Ellenbogen nach vorne zu ziehen.","Gewicht langsam absenken und die Dehnung im Bizeps zulassen.","Unten kurz vor der vollen Streckung stoppen und Spannung halten.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von fast gestreckten Armen in starker Vordehnung bis zu einer Beugung von etwa 90 bis 110 Grad. Die obere Position ist bewusst kürzer, da die Oberarme hinten bleiben.","breathing":"Beim Curlen ausatmen, beim Absenken einatmen.","common_mistakes":["Ellenbogen wandern beim Curlen nach vorne, dadurch entspricht die Übung einem normalen Incline Curl.","Schultern rollen nach vorne, um das Gewicht leichter zu bewegen.","Bank zu flach eingestellt, sodass die Arme nicht hinter die Körperlinie kommen.","Zu viel Gewicht, der Bewegungsradius wird unten verkürzt.","Handgelenke klappen oben nach innen."],"tips":["Deutlich leichteres Gewicht als beim Kurzhantelcurl wählen, die gedehnte Position ist anspruchsvoll.","Exzentrische Phase etwa drei Sekunden lang ausführen.","Vorstellen, die Ellenbogen während der ganzen Wiederholung nach hinten zu drücken.","Bei Beschwerden in der vorderen Schulter die Bank etwas flacher stellen."],"cable_setup":null,"muscle_focus":["Bank auf 60 bis 75 Grad stellen und die Oberarme bewusst hinter die Körperlinie bringen; so wird der lange Bizepskopf über Schulter und Ellenbogen gleichzeitig gedehnt.","Ellenbogen über den gesamten Satz hinten lassen, auch wenn der Bewegungsradius oben dadurch kürzer bleibt; nach vorne wandernde Ellenbogen heben den Effekt auf.","Unten fast vollständig strecken und die Dehnung zwei bis drei Sekunden lang kontrolliert zulassen, nicht fallen lassen.","Deutlich leichteres Gewicht als beim stehenden Curl wählen, damit der Bizeps in der gedehnten Position limitiert und die Schulter nicht ausweicht."],"requirements":["Verstellbare Schrägbank (60–75 Grad)","Leichte Kurzhanteln"],"grip_alternatives":[],"alternative_exercises":[]}$seed$::jsonb);

-- Hammercurl Kabel
select public.upsert_seed_exercise($seed${"slug":"hammercurl-kabel","name":"Hammercurl Kabel","category":"biceps","equipment":"cable","grip_id":"neutral_parallel","grip_notes":"Neutraler Parallelgriff (Handflächen zeigen zueinander, Daumen nach oben), Griffe etwa schulterbreit. Alternativ Seil oder einarmig mit Handschlaufe bzw. Einzelgriff in neutraler Handstellung.","primary_muscles":["biceps","forearms"],"secondary_muscles":[],"description":"Curl am Kabelzug mit neutralem Parallelgriff (Handflächen zueinander), der neben dem Bizeps vor allem den Brachialis und den Brachioradialis belastet. Durch das Kabel bleibt die Spannung über den gesamten Bewegungsradius erhalten.","setup":["Parallelgriff am unteren Kabel einhängen und Gewicht einstellen.","Griffe mit neutraler Handstellung fassen, Handflächen zeigen zueinander, Daumen nach oben.","Einen Schritt vom Turm zurücktreten, bis das Gewicht leicht angehoben ist.","Aufrecht stehen, Füße etwa hüftbreit, Knie leicht gebeugt.","Ellenbogen seitlich am Körper, Schultern nach hinten und unten."],"execution":["Griff kontrolliert nach oben curlen, Handstellung bleibt neutral.","Ellenbogen bleiben am Körper und wandern nicht nach vorne.","In der oberen Position kurz halten und Oberarm anspannen.","Gewicht langsam absenken, bis die Arme fast gestreckt sind.","Spannung am unteren Ende halten, das Gewicht nicht aufsetzen lassen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von fast gestreckten Armen bis zur vollen Beugung, soweit die Ellenbogen am Körper bleiben. Das Gewicht sollte unten nicht auf dem Stapel aufliegen.","breathing":"Beim Curlen ausatmen, beim Absenken einatmen.","common_mistakes":["Ellenbogen wandern nach vorne, dadurch arbeitet die vordere Schulter mit.","Oberkörper lehnt sich zurück und erzeugt Schwung.","Handgelenke drehen oben in eine supinierte Position.","Gewicht fällt unten auf den Stapel zurück.","Schultern ziehen beim Curlen nach oben."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Mit dem Seil als Alternative lassen sich die Seilenden am Ende leicht auseinanderziehen, das betont den Brachioradialis zusätzlich.","Wenn der Oberkörper mitschwingt, Gewicht reduzieren oder mit dem Rücken an eine Stütze stellen."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einzelnes Kabel","height":"ganz unten, damit das Kabel in der Startposition senkrecht nach unten zieht und die Armbeuger bereits bei fast gestrecktem Arm unter Spannung stehen","grip_width":"Neutraler Parallelgriff, etwa schulterbreit, Handflächen zeigen zueinander, Daumen nach oben","body_position":"Aufrecht stehend, etwa einen Schritt vom Turm entfernt, leichte Vorlage, Rumpf stabil","foot_position":"Füße hüftbreit, parallel oder leichte Schrittstellung, Knie leicht gebeugt","movement_direction":"Von unten nach oben in Richtung Schultern, Unterarm rotiert um den Ellenbogen","elbow_position":"Ellenbogen seitlich am Körper, bleiben während der Bewegung an ihrer Position","end_position":"Hände etwa auf Höhe der Schultern, Unterarme vollständig gebeugt, Oberarm angespannt","return":"Langsam und kontrolliert bis fast zur vollen Streckung, Gewicht bleibt in der Luft"},"muscle_focus":["Neutrale Handstellung über den gesamten Satz beibehalten; so übernehmen Brachialis und Brachioradialis einen großen Teil der Arbeit, beim Drehen in die Supination verschiebt sich der Fokus zum Bizeps.","Unten bis fast zur vollen Streckung absenken, damit die Armbeuger in der gedehnten Position unter Spannung stehen; das Gewicht dabei nicht aufsetzen lassen.","Ellenbogen seitlich am Körper lassen und nicht nach vorne wandern, sonst arbeitet die vordere Schulter mit.","Zwei Sekunden lang absenken, Oberkörper ruhig halten und das Gewicht so wählen, dass die Arme und nicht der Rumpf limitieren."],"requirements":["Kabelturm mit verstellbarer Rolle","Neutraler Parallelgriff (alternativ Seil oder Handschlaufe)"],"grip_alternatives":["rope","strap_handle"],"alternative_exercises":[]}$seed$::jsonb);

-- Kabelcurl
select public.upsert_seed_exercise($seed${"slug":"kabelcurl","name":"Kabelcurl","category":"biceps","equipment":"cable","grip_id":"straight_bar","grip_notes":"Supinierter Griff an der geraden Stange, etwa schulterbreit. Alternativ: EZ-Stange, wenn die Handgelenke bei gerader Stange unangenehm belastet werden.","primary_muscles":["biceps"],"secondary_muscles":["forearms"],"description":"Stehender Bizepscurl am unteren Kabelzug mit gerader Stange. Das Kabel hält die Spannung über den gesamten Bewegungsradius, auch in der oberen Position.","setup":["Gerade Stange am unteren Kabel einhängen und Gewicht einstellen.","Stange mit supiniertem Griff etwa schulterbreit fassen.","Einen Schritt vom Turm zurücktreten, bis das Gewicht leicht angehoben ist.","Aufrecht stehen, Füße hüftbreit, Knie leicht gebeugt, Rumpf angespannt.","Ellenbogen seitlich am Körper, Schultern nach hinten und unten."],"execution":["Stange kontrolliert nach oben curlen, nur die Unterarme bewegen sich.","Ellenbogen bleiben am Körper und wandern nicht nach vorne oder hinten.","In der oberen Position kurz halten und den Bizeps anspannen.","Stange langsam absenken, bis die Arme fast gestreckt sind.","Unten Spannung halten, Gewicht nicht auf dem Stapel aufsetzen lassen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von fast gestreckten Armen bis zur vollen Beugung, soweit die Ellenbogen an ihrer Position bleiben. Oben nicht die Ellenbogen anheben, um die Stange höher zu bringen.","breathing":"Beim Curlen ausatmen, beim Absenken einatmen.","common_mistakes":["Oberkörper lehnt sich zurück und erzeugt Schwung aus der Hüfte.","Ellenbogen wandern nach vorne, um die Stange höher zu bringen.","Handgelenke knicken oben nach innen ein.","Gewicht fällt unten unkontrolliert zurück.","Schultern ziehen während des Curls nach oben."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Bei Beschwerden in den Handgelenken auf die EZ-Stange wechseln.","Wenn der Oberkörper mitschwingt, Gewicht reduzieren oder mit dem Rücken an eine Stütze stellen.","Erst Gewicht erhöhen, wenn alle Sätze ohne Schwung ausgeführt werden."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einzelnes Kabel","height":"ganz unten, damit das Kabel senkrecht nach unten zieht und der Bizeps auch bei fast gestreckten Armen unter Spannung steht","grip_width":"Schulterbreit, supiniert (Handflächen nach oben), an gerader Stange oder EZ-Stange","body_position":"Aufrecht stehend, etwa einen Schritt vom Turm entfernt, Rumpf angespannt, Oberkörper ruhig","foot_position":"Füße hüftbreit, parallel, Knie leicht gebeugt","movement_direction":"Von unten nach oben in Richtung Schultern, Unterarm rotiert um den Ellenbogen","elbow_position":"Ellenbogen seitlich am Körper, bleiben während der Bewegung an ihrer Position","end_position":"Stange etwa auf Höhe der oberen Brust, Unterarme vollständig gebeugt, Bizeps angespannt","return":"Langsam und kontrolliert bis fast zur vollen Streckung, Gewicht bleibt in der Luft"},"muscle_focus":["Unten bis fast zur vollen Streckung absenken, damit der Bizeps in der gedehnten Position unter Spannung steht; das Kabel hält die Spannung dort, wo die Hantel sie verliert.","Oberarme seitlich am Körper fixieren und nur den Unterarm bewegen; wandern die Ellenbogen nach vorne, übernimmt die vordere Schulter.","Handgelenke gerade und supiniert halten, oben kurz anspannen und nicht die Ellenbogen anheben, um die Stange höher zu bringen.","Zwei bis drei Sekunden lang absenken, Oberkörper ruhig und das Gewicht so wählen, dass der Bizeps und nicht die Hüfte limitiert."],"requirements":["Kabelturm mit verstellbarer Rolle","Gerade kurze Stange (alternativ SZ-Stange)"],"grip_alternatives":["ez_bar"],"alternative_exercises":[]}$seed$::jsonb);

-- Kurzhantelcurl
select public.upsert_seed_exercise($seed${"slug":"kurzhantelcurl","name":"Kurzhantelcurl","category":"biceps","equipment":"dumbbell","grip_id":null,"grip_notes":"Supinierter Griff, Handflächen zeigen nach oben. Alternativ: Start mit neutraler Handstellung und Drehen der Hand während des Curls (Supination). Handgelenke gerade halten.","primary_muscles":["biceps"],"secondary_muscles":["forearms"],"description":"Klassischer Bizepscurl mit Kurzhanteln, stehend oder sitzend, beidarmig oder im Wechsel. Grundübung für den Bizeps mit freier Bewegung und ohne Gerätebindung.","setup":["Kurzhanteln aufnehmen und aufrecht stehen oder auf einer Bank mit aufrechter Lehne sitzen.","Füße hüftbreit, Knie leicht gebeugt, Rumpf angespannt.","Arme hängen gestreckt seitlich am Körper, Handflächen zeigen nach vorne.","Schultern nach hinten und unten ziehen, Brust leicht anheben.","Ellenbogen leicht vor der Körpermitte, nah am Rumpf."],"execution":["Kurzhanteln kontrolliert nach oben curlen, beidarmig oder im Wechsel.","Oberarme bleiben an ihrer Position, nur die Unterarme bewegen sich.","In der oberen Position den Bizeps kurz anspannen.","Gewicht langsam absenken, bis die Arme fast gestreckt sind.","Unten nicht in die Ellenbogen fallen lassen, Spannung halten.","Nächste Wiederholung ohne Schwung aus Hüfte oder Rücken beginnen."],"range_of_motion":"Von fast gestreckten Armen bis zur vollen Beugung, soweit die Oberarme an ihrer Position bleiben. Die Hantel muss oben nicht die Schulter berühren.","breathing":"Beim Curlen ausatmen, beim Absenken einatmen.","common_mistakes":["Oberkörper schwingt zurück, um das Gewicht in Bewegung zu bringen.","Ellenbogen wandern nach vorne, dadurch arbeitet die vordere Schulter mit.","Handgelenke knicken oben nach innen ein.","Gewicht wird unten fallen gelassen statt kontrolliert abgesenkt.","Im Wechsel wird der ruhende Arm vollständig entspannt."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Sitzende Ausführung reduziert Schwung aus dem Oberkörper.","Beim Curl im Wechsel den ruhenden Arm leicht gebeugt und unter Spannung halten.","Erst Gewicht erhöhen, wenn alle Sätze ohne Schwung ausgeführt werden."],"cable_setup":null,"muscle_focus":["Arme unten bis fast zur vollen Streckung bringen und die Dehnung im Bizeps zulassen; der untere Bereich der Bewegung trägt nach aktuellem Stand stark zum Muskelaufbau bei.","Oberarme nah am Rumpf und leicht vor der Körpermitte halten, nur der Unterarm bewegt sich; Ellenbogen, die nach vorne wandern, lassen die vordere Schulter übernehmen.","Handflächen beim Curlen vollständig nach oben drehen (Supination), oben kurz anspannen, ohne das Handgelenk einzuknicken.","Zwei Sekunden lang absenken, Oberkörper ruhig halten; wenn der Rumpf mitschwingt, ist das Gewicht zu schwer."],"requirements":["Kurzhanteln","Optional: Bank mit aufrechter Lehne für die sitzende Ausführung"],"grip_alternatives":[],"alternative_exercises":[]}$seed$::jsonb);

-- Trizepsdrücken Kabel
select public.upsert_seed_exercise($seed${"slug":"trizepsdruecken-kabel","name":"Trizepsdrücken Kabel","category":"triceps","equipment":"cable","grip_id":"v_bar_triceps","grip_notes":"Neutraler Griff an der V-förmigen Trizepsstange, Handgelenke gerade. Alternativ: Seil oder gerade Stange, je nach Verfügbarkeit und Handgelenkskomfort.","primary_muscles":["triceps"],"secondary_muscles":[],"description":"Trizepsdrücken am oberen Kabelzug mit der V-förmigen Trizepsstange. Der neutrale Griff ist handgelenkschonend und erlaubt eine stabile Führung der Bewegung.","setup":["V-förmige Trizepsstange am oberen Kabel einhängen und Gewicht einstellen.","Stange mit neutralem Griff fassen, Handgelenke gerade.","Einen kleinen Schritt vom Turm zurücktreten, Oberkörper leicht nach vorne neigen.","Füße hüftbreit oder in leichter Schrittstellung, Knie leicht gebeugt.","Ellenbogen seitlich am Körper fixieren, Schultern nach hinten und unten."],"execution":["Stange kontrolliert nach unten drücken, bis die Arme gestreckt sind.","Ellenbogen bleiben am Körper, nur die Unterarme bewegen sich.","In der unteren Position den Trizeps kurz anspannen.","Gewicht langsam zurückführen, bis die Unterarme etwa waagerecht oder etwas höher sind.","Oben Spannung halten, das Gewicht nicht auf dem Stapel aufsetzen lassen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer Beugung von etwa 90 Grad oder etwas mehr bis zur vollen Streckung. Die Ellenbogen bleiben dabei die gesamte Zeit an ihrer Position.","breathing":"Beim Drücken nach unten ausatmen, beim Zurückführen einatmen.","common_mistakes":["Ellenbogen wandern nach vorne oder außen, dadurch arbeitet die Schulter mit.","Oberkörper drückt mit und erzeugt Schwung von oben.","Gewicht fällt oben unkontrolliert zurück.","Handgelenke knicken unten ein.","Schultern ziehen nach oben."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Vorstellen, die Ellenbogen an die Rippen zu klemmen.","Wenn der Oberkörper mitdrückt, Gewicht reduzieren."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einzelnes Kabel","height":"ganz oben, damit das Kabel von oben in Verlängerung des Unterarms zieht und der Trizeps über den gesamten Bewegungsradius Widerstand hat","grip_width":"Neutral an der V-förmigen Trizepsstange, Hände eng beieinander","body_position":"Stehend, leichte Vorlage von etwa 10 bis 20 Grad, Rumpf angespannt, Oberkörper ruhig","foot_position":"Füße hüftbreit oder leichte Schrittstellung, Knie leicht gebeugt","movement_direction":"Von oben nach unten, Unterarm rotiert um den Ellenbogen","elbow_position":"Ellenbogen seitlich am Körper fixiert, bleiben während der Bewegung an ihrer Position","end_position":"Arme vollständig gestreckt, Stange etwa auf Höhe der Oberschenkel, Trizeps angespannt","return":"Langsam und kontrolliert, bis die Unterarme etwa waagerecht sind, Gewicht bleibt in der Luft"},"muscle_focus":["Oben so weit zurückführen, dass die Unterarme mindestens waagerecht sind, damit der Trizeps in der gedehnten Position arbeitet; das Gewicht nicht aufsetzen lassen.","Ellenbogen seitlich an den Rippen fixieren und nur den Unterarm bewegen; wandern die Ellenbogen nach vorne, drückt die Schulter mit.","Unten vollständig strecken und den Trizeps kurz anspannen, Handgelenke gerade halten.","Zwei Sekunden lang zurückführen, Oberkörper ruhig halten und das Gewicht so wählen, dass der Trizeps und nicht der Rumpf limitiert."],"requirements":["Kabelturm mit verstellbarer Rolle","Trizeps-V-Stange (alternativ gerade kurze Stange)"],"grip_alternatives":["straight_bar"],"alternative_exercises":[]}$seed$::jsonb);

-- Trizepsdrücken Stange
select public.upsert_seed_exercise($seed${"slug":"trizepsdruecken-stange","name":"Trizepsdrücken Stange","category":"triceps","equipment":"cable","grip_id":"straight_bar","grip_notes":"Pronierter Griff (Handflächen nach unten), etwa schulterbreit. Alternativ: EZ-Stange, wenn die Handgelenke bei gerader Stange unangenehm belastet werden.","primary_muscles":["triceps"],"secondary_muscles":["forearms"],"description":"Trizepsdrücken am oberen Kabelzug mit gerader Stange und proniertem Griff. Erlaubt eine stabile beidarmige Ausführung und eine gute Kontrolle des Gewichts.","setup":["Gerade Stange am oberen Kabel einhängen und Gewicht einstellen.","Stange mit proniertem Griff etwa schulterbreit fassen.","Einen kleinen Schritt vom Turm zurücktreten, Oberkörper leicht nach vorne neigen.","Füße hüftbreit oder in leichter Schrittstellung, Knie leicht gebeugt.","Ellenbogen seitlich am Körper fixieren, Schultern nach hinten und unten."],"execution":["Stange kontrolliert nach unten drücken, bis die Arme gestreckt sind.","Ellenbogen bleiben am Körper, nur die Unterarme bewegen sich.","Unten den Trizeps kurz anspannen, Handgelenke gerade halten.","Gewicht langsam zurückführen, bis die Unterarme etwa waagerecht oder etwas höher sind.","Oben Spannung halten, das Gewicht nicht auf dem Stapel aufsetzen lassen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer Beugung von etwa 90 Grad oder etwas mehr bis zur vollen Streckung. Die Ellenbogen bleiben dabei an ihrer Position.","breathing":"Beim Drücken nach unten ausatmen, beim Zurückführen einatmen.","common_mistakes":["Ellenbogen wandern nach vorne oder außen.","Oberkörper drückt mit und erzeugt Schwung von oben.","Handgelenke knicken unten nach unten ab.","Gewicht fällt oben unkontrolliert zurück.","Griff zu breit, dadurch weichen die Ellenbogen nach außen."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Bei Beschwerden in den Handgelenken auf die EZ-Stange oder das Seil wechseln.","Vorstellen, die Ellenbogen an die Rippen zu klemmen.","Wenn der Oberkörper mitdrückt, Gewicht reduzieren."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einzelnes Kabel","height":"ganz oben, damit das Kabel von oben in Verlängerung des Unterarms zieht und der Trizeps auch in der gebeugten Position unter Spannung steht","grip_width":"Schulterbreit, proniert (Handflächen nach unten), an gerader Stange oder EZ-Stange","body_position":"Stehend, leichte Vorlage von etwa 10 bis 20 Grad, Rumpf angespannt, Oberkörper ruhig","foot_position":"Füße hüftbreit oder leichte Schrittstellung, Knie leicht gebeugt","movement_direction":"Von oben nach unten, Unterarm rotiert um den Ellenbogen","elbow_position":"Ellenbogen seitlich am Körper fixiert, bleiben während der Bewegung an ihrer Position","end_position":"Arme vollständig gestreckt, Stange etwa auf Höhe der Oberschenkel, Trizeps angespannt","return":"Langsam und kontrolliert, bis die Unterarme etwa waagerecht sind, Gewicht bleibt in der Luft"},"muscle_focus":["Oben bis mindestens waagerechte Unterarme zurückführen, sodass der Trizeps in der gedehnten Position arbeitet und das Gewicht in der Luft bleibt.","Ellenbogen seitlich am Körper fixieren, Griff etwa schulterbreit; bei zu breitem Griff weichen die Ellenbogen nach außen aus und die Schulter arbeitet mit.","Unten vollständig strecken, Trizeps kurz anspannen und die Handgelenke gerade halten, nicht nach unten abknicken.","Zwei Sekunden lang zurückführen und ein Gewicht wählen, bei dem der Trizeps und nicht der Oberkörper limitiert."],"requirements":["Kabelturm mit verstellbarer Rolle","Gerade kurze Stange (alternativ Trizeps-V-Stange oder SZ-Stange)"],"grip_alternatives":["v_bar_triceps"],"alternative_exercises":[]}$seed$::jsonb);

-- Trizepsdrücken Seil
select public.upsert_seed_exercise($seed${"slug":"trizepsdruecken-seil","name":"Trizepsdrücken Seil","category":"triceps","equipment":"cable","grip_id":"rope","grip_notes":"Neutraler Griff am Seil, Seilenden fest umschließen. Alternativ: V-förmige Trizepsstange, wenn kein Seil verfügbar ist.","primary_muscles":["triceps"],"secondary_muscles":[],"description":"Trizepsdrücken am oberen Kabelzug mit Seil, bei dem die Seilenden am Ende der Bewegung auseinandergezogen werden. Erlaubt eine vollständige Streckung und eine deutliche Endkontraktion des Trizeps.","setup":["Seil am oberen Kabel einhängen und Gewicht einstellen.","Seilenden mit neutralem Griff fassen, Daumen zeigen nach oben.","Einen kleinen Schritt vom Turm zurücktreten, Oberkörper leicht nach vorne neigen.","Füße hüftbreit oder in leichter Schrittstellung, Knie leicht gebeugt.","Ellenbogen seitlich am Körper fixieren, Schultern nach hinten und unten."],"execution":["Seil kontrolliert nach unten drücken, Ellenbogen bleiben am Körper.","Kurz vor der vollen Streckung die Seilenden nach außen auseinanderziehen.","In der unteren Position den Trizeps kurz anspannen, Handrücken zeigen nach außen.","Hände wieder zusammenführen und das Gewicht langsam zurückführen.","Oben stoppen, wenn die Unterarme etwa waagerecht oder etwas höher sind.","Spannung halten und die nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer Beugung von etwa 90 Grad oder etwas mehr bis zur vollen Streckung mit auseinandergezogenen Seilenden. Die Ellenbogen bleiben dabei an ihrer Position.","breathing":"Beim Drücken nach unten ausatmen, beim Zurückführen einatmen.","common_mistakes":["Seilenden werden nicht auseinandergezogen, die Endkontraktion fehlt.","Ellenbogen wandern nach vorne oder außen.","Oberkörper drückt mit und erzeugt Schwung von oben.","Gewicht fällt oben unkontrolliert zurück.","Schultern ziehen während der Bewegung nach oben."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Das Auseinanderziehen der Seilenden erst kurz vor der vollen Streckung beginnen.","Wenn der Oberkörper mitdrückt, Gewicht reduzieren."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einzelnes Kabel","height":"ganz oben, damit das Kabel von oben zieht und die Seilenden am Ende der Bewegung nach außen geführt werden können","grip_width":"Neutral am Seil, Hände oben eng beieinander, unten auseinandergezogen","body_position":"Stehend, leichte Vorlage von etwa 10 bis 20 Grad, Rumpf angespannt, Oberkörper ruhig","foot_position":"Füße hüftbreit oder leichte Schrittstellung, Knie leicht gebeugt","movement_direction":"Von oben nach unten, am Ende leicht nach außen zu den Seiten der Oberschenkel","elbow_position":"Ellenbogen seitlich am Körper fixiert, bleiben während der Bewegung an ihrer Position","end_position":"Arme vollständig gestreckt, Seilenden seitlich neben den Oberschenkeln, Trizeps angespannt","return":"Hände zusammenführen, langsam und kontrolliert zurück bis die Unterarme etwa waagerecht sind"},"muscle_focus":["Oben bis mindestens waagerechte Unterarme zurückführen, damit der Trizeps in der gedehnten Position arbeitet; das Gewicht dabei nicht aufsetzen lassen.","Ellenbogen an den Rippen fixieren und nur den Unterarm bewegen; die Seilenden erst kurz vor der vollen Streckung auseinanderziehen.","Unten vollständig strecken und kurz anspannen, Handrücken zeigen nach außen; so wird die Endkontraktion betont.","Zwei Sekunden lang zurückführen, Oberkörper ruhig halten und das Gewicht so wählen, dass der Trizeps und nicht der Rumpf limitiert."],"requirements":["Kabelturm mit verstellbarer Rolle","Seilgriff"],"grip_alternatives":["v_bar_triceps","straight_bar"],"alternative_exercises":[]}$seed$::jsonb);

-- Überkopf Trizeps Extension
select public.upsert_seed_exercise($seed${"slug":"ueberkopf-trizeps-extension","name":"Überkopf Trizeps Extension","category":"triceps","equipment":"cable","grip_id":"straight_bar","grip_notes":"Gerade kurze Stange etwa schulterbreit mit proniertem Griff fassen, Handgelenke gerade. Alternativ SZ-Stange, wenn die Handgelenke bei gerader Stange unangenehm belastet werden, oder Seil.","primary_muscles":["triceps"],"secondary_muscles":[],"description":"Trizepsstreckung über dem Kopf am Kabelzug mit gerader Stange, bei der die Oberarme neben dem Kopf gehalten werden. Durch die gestreckte Schulterposition wird vor allem der lange Trizepskopf belastet.","setup":["Gerade Stange am Kabel einhängen und Rolle ganz unten einstellen.","Stange fassen, sich mit dem Rücken zum Turm drehen und in Schrittstellung gehen.","Stange hinter den Kopf absenken, Hände schulterbreit, Ellenbogen zeigen nach vorne-oben.","Oberkörper leicht nach vorne neigen, Rumpf anspannen, Rücken gerade.","Oberarme neben dem Kopf ruhig halten, Schultern nach unten ziehen."],"execution":["Arme kontrolliert nach vorne-oben strecken, Oberarme bleiben an ihrer Position.","Nur die Unterarme bewegen sich, Ellenbogen zeigen weiter nach vorne-oben.","In der gestreckten Position den Trizeps kurz anspannen.","Stange langsam hinter den Kopf absenken und die Dehnung im Trizeps zulassen.","Hinten stoppen, wenn die Unterarme etwa parallel zum Oberarm sind.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer vollständigen Beugung mit gedehntem Trizeps hinter dem Kopf bis zur vollen Streckung nach vorne-oben. Die Oberarme bleiben dabei neben dem Kopf.","breathing":"Beim Strecken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Ellenbogen weichen seitlich nach außen aus.","Oberarme wandern beim Strecken nach unten, dadurch wird die Bewegung zum Drücken.","Unterer Rücken fällt ins Hohlkreuz, Rumpfspannung fehlt.","Gewicht fällt hinten unkontrolliert zurück.","Zu viel Gewicht, der Bewegungsradius hinten wird verkürzt."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren und die Dehnung bewusst zulassen.","Eher leichteres Gewicht wählen, die gedehnte Position des langen Kopfes ist anspruchsvoll.","Bauch anspannen, um ein Hohlkreuz zu vermeiden.","Bei Beschwerden in der Schulter die Rolle etwas höher einstellen."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einzelnes Kabel","height":"ganz unten, damit das Kabel von unten-hinten zieht und der lange Trizepskopf hinter dem Kopf in der gedehnten Position unter Spannung steht; bei Schulterbeschwerden Hüfthöhe","grip_width":"Gerade Stange, schulterbreit, pronierter Griff, Handgelenke gerade","body_position":"Mit dem Rücken zum Turm stehend, Oberkörper leicht nach vorne geneigt, Rumpf angespannt, Rücken gerade","foot_position":"Schrittstellung, vorderes Bein leicht gebeugt, hinteres Bein gestreckt für Stabilität","movement_direction":"Von hinter dem Kopf nach vorne-oben, Unterarm rotiert um den Ellenbogen","elbow_position":"Ellenbogen neben dem Kopf, zeigen nach vorne-oben, bleiben an ihrer Position","end_position":"Arme vollständig gestreckt nach vorne-oben, Trizeps angespannt, Oberarme weiter neben dem Kopf","return":"Langsam und kontrolliert, bis die Unterarme hinter dem Kopf etwa parallel zu den Oberarmen sind"},"muscle_focus":["Oberarme neben dem Kopf nach oben gestreckt halten, so wird der lange Trizepskopf über die Schulter vorgedehnt; genau diese gedehnte Position macht die Übung wirksam.","Stange hinter dem Kopf absenken, bis die Unterarme etwa parallel zu den Oberarmen sind, und die Dehnung zwei bis drei Sekunden lang kontrolliert zulassen.","Ellenbogen nach vorne-oben gerichtet lassen und nicht nach außen ausweichen; sinken die Oberarme beim Strecken ab, wird aus der Übung ein Drücken.","Rumpf anspannen, kein Hohlkreuz, und ein eher leichtes Gewicht wählen, damit der Trizeps und nicht der untere Rücken limitiert."],"requirements":["Kabelturm mit verstellbarer Rolle","Gerade kurze Stange (alternativ SZ-Stange oder Seil)"],"grip_alternatives":["ez_bar","rope"],"alternative_exercises":[]}$seed$::jsonb);

-- Kabel Extension einarmig
select public.upsert_seed_exercise($seed${"slug":"kabel-extension-einarmig","name":"Kabel Extension einarmig","category":"triceps","equipment":"cable","grip_id":"single_handle","grip_notes":"Einzelner Griff mit neutraler oder pronierter Handstellung, je nach Komfort. Alternativ Handschlaufe, um den Griff zu entlasten, oder ohne Griff direkt am Kabelende greifen.","primary_muscles":["triceps"],"secondary_muscles":[],"description":"Einarmiges Trizepsdrücken am oberen Kabelzug, bei dem die freie Hand am Turm stützt. Erlaubt eine gezielte Arbeit pro Seite und den Ausgleich von Kraftunterschieden.","setup":["Einzelnen Griff am oberen Kabel einhängen und Gewicht einstellen.","Griff mit einer Hand fassen, neutrale oder pronierte Handstellung.","Einen kleinen Schritt vom Turm zurücktreten, Oberkörper leicht nach vorne neigen.","Freie Hand zur Stabilisierung am Turm abstützen.","Ellenbogen des arbeitenden Arms seitlich am Körper fixieren, Schulter nach unten."],"execution":["Griff kontrolliert nach unten drücken, bis der Arm gestreckt ist.","Ellenbogen bleibt am Körper, nur der Unterarm bewegt sich.","Unten den Trizeps kurz anspannen.","Gewicht langsam zurückführen, bis der Unterarm etwa waagerecht oder etwas höher ist.","Oben Spannung halten, das Gewicht nicht auf dem Stapel aufsetzen lassen.","Nach dem Satz die Seite wechseln."],"range_of_motion":"Von einer Beugung von etwa 90 Grad oder etwas mehr bis zur vollen Streckung. Der Ellenbogen bleibt dabei an seiner Position.","breathing":"Beim Drücken nach unten ausatmen, beim Zurückführen einatmen.","common_mistakes":["Ellenbogen wandert nach vorne oder außen.","Oberkörper dreht sich zur arbeitenden Seite und erzeugt Schwung.","Schulter zieht nach oben.","Gewicht fällt oben unkontrolliert zurück.","Zu viel Gewicht, sodass der Rumpf mitarbeitet."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Mit der schwächeren Seite beginnen und die Wiederholungszahl auf der stärkeren Seite daran anpassen.","Vorstellen, den Ellenbogen an die Rippen zu klemmen."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einzelnes Kabel","height":"ganz oben, damit das Kabel von oben in Verlängerung des Unterarms zieht und der Trizeps über den gesamten Bewegungsradius Widerstand hat","grip_width":"Einzelner Griff, neutral oder proniert, Handgelenk gerade","body_position":"Stehend, leichte Vorlage von etwa 10 bis 20 Grad, freie Hand am Turm abgestützt, Rumpf angespannt","foot_position":"Füße hüftbreit oder leichte Schrittstellung, Knie leicht gebeugt","movement_direction":"Von oben nach unten, Unterarm rotiert um den Ellenbogen","elbow_position":"Ellenbogen seitlich am Körper fixiert, bleibt während der Bewegung an seiner Position","end_position":"Arm vollständig gestreckt, Griff etwa auf Höhe des Oberschenkels, Trizeps angespannt","return":"Langsam und kontrolliert, bis der Unterarm etwa waagerecht ist, Gewicht bleibt in der Luft"},"muscle_focus":["Oben bis mindestens waagerechten Unterarm zurückführen, damit der Trizeps in der gedehnten Position arbeitet; das Gewicht nicht aufsetzen lassen.","Ellenbogen seitlich an den Rippen fixieren und nur den Unterarm bewegen, der Oberkörper dreht sich nicht zur arbeitenden Seite.","Unten vollständig strecken und kurz anspannen; mit der freien Hand am Turm stützen, damit der Rumpf nicht mitarbeitet.","Zwei Sekunden lang zurückführen und ein Gewicht wählen, bei dem der Trizeps limitiert; mit der schwächeren Seite beginnen."],"requirements":["Kabelturm mit verstellbarer Rolle","Einzelgriff (D-Griff) oder Handschlaufe"],"grip_alternatives":["strap_handle"],"alternative_exercises":[]}$seed$::jsonb);

-- Crunch Maschine
select public.upsert_seed_exercise($seed${"slug":"crunch-maschine","name":"Crunch Maschine","category":"abs","equipment":"machine","grip_id":null,"grip_notes":"Griffe oder Polster je nach Maschine locker halten, nicht mit den Armen ziehen. Bei Brustpolster die Arme nur zur Fixierung auflegen.","primary_muscles":["abs"],"secondary_muscles":["obliques"],"description":"Geführte Crunch-Bewegung an der Maschine, bei der der Widerstand über einen Gewichtsstapel eingestellt wird. Gut geeignet, um die Bauchmuskulatur mit Zusatzgewicht gezielt zu trainieren.","setup":["Sitz so einstellen, dass die Drehachse der Maschine etwa auf Höhe des unteren Brustkorbs liegt.","Füße unter die Fußpolster bringen oder flach auf den Boden stellen.","Griffe oder Brustpolster locker fassen bzw. anlegen.","Rücken an das Polster lehnen, Schultern locker.","Leichtes Gewicht wählen, bis der Bewegungsablauf sicher sitzt."],"execution":["Oberkörper kontrolliert nach vorne einrollen, Bewegung aus der Brustwirbelsäule.","Brustbein in Richtung Becken ziehen, der Rücken wird dabei rund.","In der Endposition den Bauch kurz bewusst anspannen.","Gewicht langsam zurückführen, ohne den Rücken ins Hohlkreuz zu bringen.","Oben stoppen, bevor das Gewicht auf dem Stapel aufsetzt.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer leicht gestreckten Ausgangsposition bis zum vollständig eingerollten Oberkörper. Die Bewegung kommt aus der Brustwirbelsäule, nicht aus der Hüfte.","breathing":"Beim Einrollen ausatmen, beim Zurückführen einatmen.","common_mistakes":["Bewegung kommt aus der Hüfte statt aus der Wirbelsäule, die Hüftbeuger arbeiten statt des Bauchs.","Mit den Armen an den Griffen gezogen statt mit dem Bauch eingerollt.","Gewicht fällt oben unkontrolliert zurück.","Zu viel Gewicht, der Bewegungsradius wird klein.","Luft wird während der Bewegung angehalten."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Beim Einrollen bewusst ausatmen, das unterstützt die Anspannung des Bauchs.","Lieber leichtes Gewicht mit vollem Bewegungsradius als schweres Gewicht mit kurzer Bewegung.","Vorstellen, die Rippen in Richtung Becken zu ziehen."],"cable_setup":null,"muscle_focus":["Drehachse der Maschine auf Höhe des unteren Brustkorbs einstellen, damit das Einrollen aus der Brustwirbelsäule kommt und nicht aus der Hüfte.","Oben leicht gestreckt starten, sodass die Bauchmuskulatur in der gedehnten Position arbeitet; dann Brustbein in Richtung Becken ziehen und den Rücken rund werden lassen.","Griffe oder Polster nur locker halten, nicht mit den Armen ziehen; kommt die Bewegung aus der Hüfte, übernehmen die Hüftbeuger.","Beim Einrollen ausatmen, zwei Sekunden lang zurückführen und lieber leichtes Gewicht mit vollem Bewegungsradius wählen."],"requirements":["Bauchmaschine (Crunch-Maschine) mit Gewichtsstapel und verstellbarem Sitz"],"grip_alternatives":[],"image_url":"/exercises/abdominal-machine.jpg","machine_name":"DHZ Abdominal Isolator, Steckgewicht","alternative_exercises":["kabel-crunch"]}$seed$::jsonb);

-- Seated Cable Crunch
select public.upsert_seed_exercise($seed${"slug":"kabel-crunch","name":"Seated Cable Crunch","category":"abs","equipment":"cable","grip_id":"rope","grip_notes":"Seil mit neutralem Griff fassen und die Seilenden beidhändig vor der Brust bzw. an den Schultern halten, Position während des Satzes nicht verändern. Alternativ Handschlaufen (eine pro Hand), wenn das Seil stört.","primary_muscles":["abs"],"secondary_muscles":["obliques"],"description":"Sitzender Crunch auf der Matte mit dem Rücken zum Kabelturm, bei dem das Seil vor der Brust gehalten und der Oberkörper gegen den Zug von hinten-oben eingerollt wird. Erlaubt eine gut steuerbare Belastung der Bauchmuskulatur mit Zusatzgewicht, ohne Druck auf die Knie.","setup":["Rolle am Kabelturm auf Hüft- bis Brusthöhe einstellen und Seil einhängen.","Matte vor den Turm legen und sich mit dem Rücken zum Turm hinsetzen, etwa eine halbe bis eine Armlänge entfernt.","Beine angewinkelt nach vorne aufstellen, Füße flach auf dem Boden.","Seil über die Schultern nach vorne führen und die Seilenden beidhändig vor der Brust bzw. an den Schultern halten.","Oberkörper aufrecht, leichte Vorspannung im Bauch, Becken stabil auf der Matte."],"execution":["Oberkörper kontrolliert nach vorne-unten einrollen, Bewegung aus der Brustwirbelsäule.","Brustbein in Richtung Becken ziehen, der Rücken wird dabei rund.","Becken bleibt stabil auf der Matte, die Hüfte beugt sich nicht aktiv mit.","In der Endposition den Bauch kurz bewusst anspannen.","Oberkörper langsam wieder aufrichten, Spannung im Bauch halten.","Oben stoppen, bevor der Rücken ins Hohlkreuz fällt und das Gewicht aufsetzt."],"range_of_motion":"Von einem aufrechten, leicht vorgespannten Oberkörper bis zum vollständig eingerollten Rumpf. Das Becken bleibt stabil, nur die Wirbelsäule rollt ein; oben nicht über die aufrechte Position hinaus ins Hohlkreuz.","breathing":"Beim Einrollen ausatmen, beim Aufrichten einatmen.","common_mistakes":["Oberkörper kippt mit geradem Rücken nach vorne, statt sich einzurollen; die Hüftbeuger übernehmen.","Mit den Armen am Seil gezogen statt mit dem Bauch eingerollt.","Hände verändern während des Satzes ihre Position vor der Brust.","Beim Aufrichten ins Hohlkreuz gefallen, der Zug zieht den Oberkörper nach hinten.","Gewicht fällt unkontrolliert zurück, keine Kontrolle in der exzentrischen Phase."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Vorstellen, die Rippen in Richtung Becken zu ziehen.","Lieber leichtes Gewicht mit vollem Bewegungsradius als schweres Gewicht mit kurzer Bewegung.","Abstand zum Turm so wählen, dass das Kabel bereits in der aufrechten Position unter Spannung steht."],"cable_setup":{"cable":"Kabelturm, einzelnes Kabel","height":"Hüfthöhe bis Brusthöhe, damit der Zug im Sitzen etwa auf Kopf- bis Schulterhöhe schräg von hinten-oben kommt","grip_width":"Neutral am Seil, Seilenden beidhändig vor der Brust bzw. an den Schultern, eng beieinander","body_position":"Sitzend auf der Matte mit dem Rücken zum Turm, etwa eine halbe bis eine Armlänge entfernt, Oberkörper aufrecht, Becken stabil","foot_position":"Beine angewinkelt nach vorne aufgestellt, Füße flach auf dem Boden, etwa hüftbreit","movement_direction":"Einrollen nach vorne-unten, Brustbein in Richtung Becken, gegen den Zug von hinten-oben","elbow_position":"Ellenbogen zeigen nach unten und bleiben nah am Körper, keine aktive Armbewegung","end_position":"Rumpf vollständig eingerollt, Brustbein in Richtung Becken, Bauch angespannt","return":"Langsam und kontrolliert aufrichten, bis der Oberkörper aufrecht ist, nicht ins Hohlkreuz, Gewicht bleibt in der Luft"},"muscle_focus":["Rolle so einstellen, dass der Zug schräg von hinten-oben kommt; dann steht die Bauchmuskulatur schon in der aufrechten, leicht gestreckten Position unter Spannung.","Einrollen aus der Brustwirbelsäule, Brustbein in Richtung Becken; das Becken bleibt auf der Matte stabil, sonst übernehmen die Hüftbeuger.","Seil nur fixieren, nicht mit den Armen ziehen; die Ellenbogen bleiben während des Satzes an derselben Stelle.","Beim Einrollen ausatmen, zwei Sekunden lang aufrichten und oben nicht ins Hohlkreuz fallen; leichtes Gewicht mit vollem Bewegungsradius bevorzugen."],"requirements":["Kabelturm mit verstellbarer Rolle","Seilgriff (alternativ Handschlaufen)","Matte"],"grip_alternatives":["strap_handle"],"alternative_exercises":["crunch-maschine"]}$seed$::jsonb);

-- Hanging Knee Raise
select public.upsert_seed_exercise($seed${"slug":"hanging-knee-raise","name":"Hanging Knee Raise","category":"abs","equipment":"bodyweight","grip_id":null,"grip_notes":"Pronierter oder neutraler Griff an der Klimmzugstange, etwa schulterbreit. Alternativ: Armschlaufen, wenn die Griffkraft vor dem Bauch ermüdet.","primary_muscles":["abs"],"secondary_muscles":["obliques","forearms"],"description":"Hängendes Anziehen der Knie an der Klimmzugstange oder in Armschlaufen, bei dem das Becken leicht eingerollt wird. Bauchübung mit dem eigenen Körpergewicht, die zusätzlich die Griffkraft fordert.","setup":["Klimmzugstange etwa schulterbreit fassen oder Oberarme in Armschlaufen einhängen.","Frei hängen, Beine gestreckt oder leicht gebeugt, Füße ohne Bodenkontakt.","Schultern aktiv nach unten ziehen, nicht passiv in den Gelenken hängen.","Rumpf anspannen und den Körper zur Ruhe bringen, bevor die Bewegung beginnt."],"execution":["Knie kontrolliert in Richtung Brust anziehen.","Am Ende der Bewegung das Becken leicht einrollen, der untere Rücken rundet sich dabei etwas.","In der oberen Position den Bauch kurz bewusst anspannen.","Beine langsam absenken, bis die Ausgangsposition erreicht ist.","Unten kurz zur Ruhe kommen, damit kein Schwung entsteht.","Nächste Wiederholung aus dem Stand heraus beginnen."],"range_of_motion":"Von gestreckt hängenden Beinen bis zu angezogenen Knien mit leicht eingerolltem Becken. Die Knie müssen nicht die Brust berühren, das Einrollen des Beckens ist entscheidend.","breathing":"Beim Anziehen der Knie ausatmen, beim Absenken einatmen.","common_mistakes":["Körper schwingt vor und zurück, die Bewegung kommt aus dem Schwung.","Becken wird nicht eingerollt, nur die Hüftbeuger heben die Beine.","Beine fallen unkontrolliert nach unten.","Schultern hängen passiv in den Gelenken.","Zu schnelles Tempo, das Einrollen des Beckens wird übersprungen."],"tips":["Jede Wiederholung erst beginnen, wenn der Körper ruhig hängt.","Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Als Progression die Beine zunehmend gestreckt halten oder die Bewegung langsamer ausführen.","Wenn die Griffkraft vor dem Bauch ermüdet, Armschlaufen verwenden."],"cable_setup":null,"muscle_focus":["Entscheidend ist das Einrollen des Beckens am Ende der Bewegung; reines Anheben der Beine kommt überwiegend aus den Hüftbeugern.","Beine unten fast gestreckt hängen lassen, sodass die Bauchmuskulatur in der gedehnten Position arbeitet, und jede Wiederholung aus dem ruhigen Hang starten.","Schultern aktiv nach unten ziehen und den Rumpf anspannen, damit kein Schwung entsteht.","Zwei Sekunden lang absenken; wenn die Griffkraft vor dem Bauch ermüdet, Armschlaufen verwenden."],"requirements":["Klimmzugstange oder Armschlaufen (Ab Straps) an einem stabilen Gestell"],"grip_alternatives":[],"image_url":"/exercises/knee-raise-station.jpg","machine_name":"DHZ Vertical Knee Raise Station","alternative_exercises":[]}$seed$::jsonb);

-- Plank
select public.upsert_seed_exercise($seed${"slug":"plank","name":"Plank","category":"abs","equipment":"bodyweight","grip_id":null,"grip_notes":"Unterarme flach auf dem Boden, Hände locker geöffnet oder zu Fäusten geschlossen. Ellenbogen etwa unter den Schultern.","primary_muscles":["abs"],"secondary_muscles":["obliques","glutes"],"description":"Isometrischer Unterarmstütz, bei dem der Körper in einer geraden Linie gehalten wird. Grundübung für die Rumpfstabilität, die über die Haltedauer statt über Wiederholungen gesteuert wird.","setup":["Unterarme flach auf den Boden legen, Ellenbogen etwa unter den Schultern.","Beine nach hinten strecken, Füße etwa hüftbreit auf den Zehenspitzen.","Körper in eine gerade Linie von Kopf bis Fersen bringen.","Blick auf den Boden richten, Nacken in Verlängerung der Wirbelsäule.","Bauch und Gesäß anspannen, Becken leicht nach hinten kippen."],"execution":["Position halten, Rumpfspannung über die gesamte Dauer aufrechterhalten.","Becken bleibt in neutraler Position, weder abgesenkt noch angehoben.","Gleichmäßig weiteratmen, ohne die Spannung zu verlieren.","Schultern aktiv vom Boden wegdrücken, oberer Rücken bleibt stabil.","Halten, solange die gerade Linie sauber gehalten werden kann.","Kontrolliert ablegen, wenn die Position nicht mehr gehalten werden kann."],"range_of_motion":"Keine Bewegung, die Position wird statisch gehalten. Entscheidend ist die gerade Körperlinie ohne Absinken der Hüfte.","breathing":"Gleichmäßig und ruhig weiteratmen, die Luft nicht anhalten. Bei jeder Ausatmung die Bauchspannung bewusst beibehalten.","common_mistakes":["Hüfte sinkt ab, der untere Rücken fällt ins Hohlkreuz.","Gesäß wird zu hoch gehoben, der Körper bildet ein Dreieck.","Kopf hängt nach unten oder wird in den Nacken gelegt.","Luft wird angehalten.","Schultern sacken zwischen den Schulterblättern ein."],"tips":["Haltedauer in Sekunden kann als Wiederholungszahl eingetragen werden, zum Beispiel 45 für 45 Sekunden.","Lieber kürzere Haltezeiten mit sauberer Linie als lange Haltezeiten mit abgesenkter Hüfte.","Als Progression die Haltedauer schrittweise verlängern oder die Füße enger stellen.","Gesäß bewusst anspannen, das stabilisiert das Becken."],"cable_setup":null,"muscle_focus":["Becken leicht nach hinten kippen und Gesäß anspannen; so arbeitet die Bauchmuskulatur gegen das Hohlkreuz und hält die Spannung.","Ellenbogen unter den Schultern und aktiv in den Boden drücken, damit der obere Rücken nicht einsackt.","Gerade Linie von Kopf bis Fersen halten, ohne das Gesäß anzuheben; ruhig weiteratmen und die Spannung bei jeder Ausatmung beibehalten.","Lieber kürzer und sauber halten als lange mit abgesenkter Hüfte."],"requirements":["Matte oder weicher Untergrund für die Unterarme"],"grip_alternatives":[],"alternative_exercises":[]}$seed$::jsonb);

-- Multi Press Maschine
select public.upsert_seed_exercise($seed${"slug":"multi-press-maschine","name":"Multi Press Maschine","category":"chest","equipment":"machine","grip_id":null,"grip_notes":"Pronierte Griffe (Handflächen nach vorne) an den beiden Hebelarmen. Handgelenke gerade halten, Griffe mittig in der Handfläche.","primary_muscles":["chest","front_delts"],"secondary_muscles":["triceps"],"description":"Steckgewicht-Multipresse mit verstellbarem Sitz, bei der die Griffe in der Ausgangsposition über Schulterhöhe liegen. Je nach Sitzhöhe lässt sich die Übung als Brustdrücken oder als Schulterdrücken ausführen.","setup":["Gewicht am Steckgewichtsblock wählen und den Stift vollständig einstecken.","Für Brustdrücken den Sitz so hoch stellen, dass die Griffe auf Höhe der oberen Brust liegen; für Schulterdrücken den Sitz tiefer stellen, sodass die Griffe etwa auf Schulterhöhe sind.","Rücken und Kopf an das Rückenpolster anlehnen, Füße flach auf den Boden stellen.","Griffe fassen, Handgelenke gerade, Ellenbogen unterhalb der Griffe.","Schulterblätter nach hinten und unten ziehen und Rumpf anspannen."],"execution":["Griffe kontrolliert nach oben beziehungsweise nach vorne-oben drücken, je nach Sitzhöhe.","Ellenbogen am Ende nicht hart durchstrecken.","Spannung in Brust und vorderer Schulter halten, Schulterblätter bleiben am Polster.","Gewicht langsam zurückführen, bis die Oberarme etwa waagerecht sind.","Gewichtsblock in der unteren Position nicht aufsetzen lassen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Vom unteren Umkehrpunkt mit etwa waagerechten Oberarmen bis kurz vor die Armstreckung. Nicht tiefer gehen, als die Schultern schmerzfrei zulassen.","breathing":"Beim Drücken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Sitzhöhe passt nicht zum gewünschten Ziel, Griffe liegen zu hoch oder zu tief.","Rücken hebt sich beim Drücken vom Polster ab.","Schultern wandern beim Drücken Richtung Ohren.","Gewicht wird mit Schwung aus der unteren Position gedrückt.","Ellenbogen werden am Ende hart durchgestreckt."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Sitzhöhe einmal festlegen und für Vergleichbarkeit notieren, da sie die Belastung deutlich verschiebt.","Erst dann Gewicht erhöhen, wenn alle Sätze im oberen Wiederholungsbereich sauber ausgeführt werden."],"cable_setup":null,"muscle_focus":["Die Sitzhöhe bestimmt den Zielmuskel: Griffe auf Höhe der oberen Brust belasten die Brust, Griffe auf Schulterhöhe die vordere Schulter. Einmal festlegen und für alle Sätze beibehalten.","Schulterblätter nach hinten und unten am Polster halten, Ellenbogen etwa 45 Grad vom Rumpf abgewinkelt; so bleibt die Last auf Brust und vorderer Schulter statt auf dem Schultergelenk.","Vollen Bewegungsradius nutzen und die untere, gedehnte Position bewusst mitnehmen, ohne den Gewichtsblock aufzusetzen; dort entsteht ein großer Teil des Trainingsreizes.","Exzentrik etwa zwei Sekunden lang kontrollieren und das Gewicht so wählen, dass Brust oder Schulter den Satz begrenzen, nicht der Trizeps."],"requirements":["Multipresse mit Steckgewichtsblock (Hebel-Druckmaschine mit über Schulterhöhe gelagerten Griffen)","Höhenverstellbarer Sitz mit Rückenpolster"],"grip_alternatives":[],"image_url":"/exercises/multi-press.jpg","machine_name":"DHZ Multi Press, Steckgewicht","alternative_exercises":["brustpresse","schulterpresse-maschine"]}$seed$::jsonb);

-- Brustpresse Hebel sitzend
select public.upsert_seed_exercise($seed${"slug":"brustpresse-hebel-sitzend","name":"Brustpresse Hebel sitzend","category":"chest","equipment":"machine","grip_id":null,"grip_notes":"Pronierte Griffe (Handflächen nach vorne) auf Brusthöhe. Handgelenke gerade halten, Griffe fest in der Handfläche.","primary_muscles":["chest"],"secondary_muscles":["triceps","front_delts"],"description":"Scheibenbeladene Hebelmaschine für die horizontale Druckbewegung im Sitzen mit Griffen auf Brusthöhe. Die Fußplatte vorne hilft, die Hebelarme in die Startposition zu bringen.","setup":["Gewichtsscheiben gleichmäßig auf beide Seiten laden und mit Verschlüssen sichern.","Sitz so einstellen, dass die Griffe auf Höhe der mittleren Brust liegen.","Rücken und Kopf an das Rückenpolster anlehnen.","Mit dem Fuß auf die Fußplatte drücken, um die Hebelarme nach vorne zu bringen, und die Griffe fassen.","Fuß von der Platte nehmen, Füße flach auf den Boden stellen, Schulterblätter nach hinten und unten ziehen."],"execution":["Griffe kontrolliert nach vorne drücken.","Ellenbogen am Ende nicht hart durchstrecken.","Brust gespannt halten, Schulterblätter bleiben am Polster.","Hebelarme langsam zurückführen, bis die Hände etwa auf Brusthöhe neben dem Körper sind.","Gewicht nicht in der Endstellung ablegen, sondern Spannung halten.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer leichten Dehnung der Brust in der hinteren Position bis kurz vor die Armstreckung. Die Griffe nicht weiter hinter die Brustlinie führen, als die Schultern schmerzfrei zulassen.","breathing":"Beim Drücken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Sitz zu hoch oder zu tief, Griffe liegen nicht auf Brusthöhe.","Schultern rollen beim Drücken nach vorne.","Rücken löst sich vom Polster.","Hebelarme fallen in der exzentrischen Phase unkontrolliert zurück.","Ellenbogen werden am Ende hart durchgestreckt."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Nach dem letzten Satz die Hebelarme über die Fußplatte kontrolliert ablegen.","Beim Beladen beide Seiten gleich bestücken, um eine einseitige Belastung zu vermeiden."],"cable_setup":null,"muscle_focus":["Griffe auf Höhe der mittleren Brust, Schulterblätter nach hinten und unten am Polster fixiert, Ellenbogen etwa 45 Grad vom Rumpf abgewinkelt; so arbeitet die Brust statt der vorderen Schulter.","Hebelarme so weit zurückführen, dass die Brust in der hinteren Position spürbar gedehnt ist; die gedehnte Position liefert einen großen Teil des Wachstumsreizes.","Exzentrik etwa zwei Sekunden lang kontrollieren und vorne kurz vor der Armstreckung stoppen, damit die Spannung in der Brust bleibt.","Gewicht so wählen, dass die Brust den Satz begrenzt und die Schultern nicht nach vorne rollen."],"requirements":["Scheibenbeladene Brustpresse (Hebelmaschine) mit Fußplatte zum Vorlegen der Hebelarme","Gewichtsscheiben und Scheibenverschlüsse","Höhenverstellbarer Sitz mit Rückenpolster"],"grip_alternatives":[],"image_url":"/exercises/chest-press-lever-seated.jpg","machine_name":"DHZ Seated Chest Press, Plate Loaded","alternative_exercises":["brustpresse","brustpresse-hebel"]}$seed$::jsonb);

-- Brustpresse Hebel
select public.upsert_seed_exercise($seed${"slug":"brustpresse-hebel","name":"Brustpresse Hebel","category":"chest","equipment":"machine","grip_id":null,"grip_notes":"Waagerechte Griffe (proniert) für die klassische Druckbewegung, senkrechte Griffe (neutral) für eine schulterfreundlichere Variante. Handgelenke gerade halten.","primary_muscles":["chest"],"secondary_muscles":["triceps","front_delts"],"description":"Scheibenbeladene Iso-Lateral-Brustpresse mit zwei unabhängig beweglichen Hebelarmen und jeweils senkrechten und waagerechten Griffen. Beide Seiten arbeiten getrennt, sodass eine Seite die andere nicht ausgleichen kann.","setup":["Gewichtsscheiben auf beiden Seiten gleich laden und mit Verschlüssen sichern.","Sitz so einstellen, dass die gewählten Griffe auf Höhe der mittleren Brust liegen.","Rücken und Kopf an das Rückenpolster anlehnen, Füße flach auf den Boden stellen.","Entweder die waagerechten oder die senkrechten Griffe fassen, Handgelenke gerade.","Schulterblätter nach hinten und unten ziehen und Rumpf anspannen."],"execution":["Beide Hebelarme gleichzeitig und gleichmäßig nach vorne drücken.","Ellenbogen am Ende nicht hart durchstrecken.","Brust gespannt halten, Schulterblätter bleiben am Polster.","Hebelarme langsam und kontrolliert zurückführen.","In der hinteren Position leichte Dehnung der Brust spüren, Gewicht nicht aufsetzen lassen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer leichten Dehnung der Brust in der hinteren Position bis kurz vor die Armstreckung. Beide Arme über den gleichen Weg führen.","breathing":"Beim Drücken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Eine Seite läuft der anderen voraus, die Hebelarme bewegen sich ungleichmäßig.","Schultern rollen beim Drücken nach vorne.","Rücken löst sich vom Polster.","Hebelarme fallen in der exzentrischen Phase unkontrolliert zurück.","Griffe werden mit den Fingern statt mit der ganzen Hand gehalten."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Bei Schulterbeschwerden auf die senkrechten Griffe wechseln.","Die Übung lässt sich auch einarmig ausführen, dann die freie Hand am Rahmen abstützen.","Beide Seiten gleich beladen, damit die Belastung symmetrisch bleibt."],"cable_setup":null,"muscle_focus":["Schulterblätter nach hinten und unten am Polster halten, Ellenbogen etwa 45 Grad vom Rumpf abgewinkelt; die Brust führt die Oberarme nach vorne-innen, die Schultern bleiben hinten.","Vollen Bewegungsradius nutzen und die gedehnte hintere Position bewusst mitnehmen, ohne das Gewicht aufzusetzen; dort ist der Reiz auf die Brust am größten.","Beide Hebelarme gleich schnell führen und die Exzentrik etwa zwei Sekunden lang kontrollieren; die unabhängigen Arme decken Seitenunterschiede auf.","Gewicht so wählen, dass die Brust den Satz begrenzt und nicht Trizeps oder vordere Schulter übernehmen."],"requirements":["Scheibenbeladene Iso-Lateral-Brustpresse mit zwei unabhängigen Hebelarmen und senkrechten sowie waagerechten Griffen","Gewichtsscheiben und Scheibenverschlüsse","Höhenverstellbarer Sitz mit Rückenpolster"],"grip_alternatives":[],"image_url":"/exercises/chest-press-lever.jpg","machine_name":"DHZ Chest Press, Plate Loaded (Iso-Lateral)","alternative_exercises":["brustpresse","brustpresse-hebel-sitzend"]}$seed$::jsonb);

-- Brustpresse vertikal
select public.upsert_seed_exercise($seed${"slug":"brustpresse-vertikal","name":"Brustpresse vertikal","category":"chest","equipment":"machine","grip_id":null,"grip_notes":"Pronierte Griffe (Handflächen nach vorne), die der Maschine folgend leicht nach innen laufen. Handgelenke gerade halten, nicht abknicken.","primary_muscles":["chest"],"secondary_muscles":["triceps","front_delts"],"description":"Steckgewicht-Brustpresse mit aufrechtem Rückenpolster, bei der die Griffe während der Druckbewegung leicht nach vorne zusammenlaufen. Die konvergierende Bahn unterstützt die Kontraktion der Brust am Ende der Bewegung.","setup":["Gewicht am Steckgewichtsblock wählen und den Stift vollständig einstecken.","Sitz so einstellen, dass die Griffe auf Höhe der mittleren Brust liegen.","Rücken und Kopf vollständig an das Rückenpolster anlehnen.","Füße flach auf den Boden stellen.","Griffe fassen, Schulterblätter nach hinten und unten ziehen."],"execution":["Griffe kontrolliert nach vorne drücken und der leicht zusammenlaufenden Bahn folgen.","In der vorderen Position Brust kurz anspannen, Ellenbogen nicht hart durchstrecken.","Schulterblätter bleiben während der gesamten Bewegung am Polster.","Gewicht langsam zurückführen, bis die Hände etwa auf Brusthöhe neben dem Körper sind.","Gewichtsblock nicht aufsetzen lassen, Spannung halten.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer leichten Dehnung der Brust in der hinteren Position bis kurz vor die Armstreckung. Nicht weiter zurückführen, als die Schultern schmerzfrei zulassen.","breathing":"Beim Drücken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Sitz zu niedrig, Griffe liegen auf Schulterhöhe.","Schultern rollen beim Drücken nach vorne.","Rücken löst sich vom Polster.","Gewicht wird mit Schwung aus der hinteren Position gedrückt.","Handgelenke knicken beim Zusammenlaufen der Griffe ab."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","In der vorderen Position kurz halten, um die Kontraktion der Brust zu nutzen.","Erst dann Gewicht erhöhen, wenn alle Sätze im oberen Wiederholungsbereich sauber ausgeführt werden."],"cable_setup":null,"muscle_focus":["Griffe auf Höhe der mittleren Brust einstellen, Schulterblätter nach hinten und unten am Polster halten, Ellenbogen etwa 45 Grad vom Rumpf abgewinkelt.","Der zusammenlaufenden Bahn vorne folgen und die Brust dort kurz anspannen; hinten so weit zurückführen, dass die Brust spürbar gedehnt ist.","Exzentrik etwa zwei Sekunden lang kontrollieren und den Gewichtsblock nicht aufsetzen lassen, damit die Spannung in der gedehnten Position erhalten bleibt.","Gewicht so wählen, dass die Brust den Satz begrenzt, nicht die Handgelenke oder der Trizeps."],"requirements":["Brustpresse mit Steckgewichtsblock und konvergierender Griffbahn","Höhenverstellbarer Sitz mit aufrechtem Rückenpolster"],"grip_alternatives":[],"image_url":"/exercises/chest-press-vertical.jpg","machine_name":"DHZ Chest Press Vertical, Steckgewicht","alternative_exercises":["brustpresse","brustpresse-hebel"]}$seed$::jsonb);

-- Schrägbankdrücken Hebelmaschine
select public.upsert_seed_exercise($seed${"slug":"schraegbankdruecken-hebelmaschine","name":"Schrägbankdrücken Hebelmaschine","category":"chest","equipment":"machine","grip_id":null,"grip_notes":"Pronierte Griffe (Handflächen nach vorne) an den Hebelarmen, etwas weiter als schulterbreit. Handgelenke gerade halten.","primary_muscles":["upper_chest","chest"],"secondary_muscles":["triceps","front_delts"],"description":"Scheibenbeladene Hebelmaschine mit einem auf etwa 30 bis 45 Grad geneigten Rückenpolster, die die Druckbewegung nach vorne-oben führt. Belastet vor allem den oberen Anteil der Brust.","setup":["Gewichtsscheiben auf beiden Seiten gleich laden und mit Verschlüssen sichern.","Sitz so einstellen, dass die Griffe auf Höhe der oberen Brust liegen.","Rücken und Kopf an das geneigte Polster anlehnen, Füße flach auf den Boden stellen.","Griffe fassen, Handgelenke gerade, Ellenbogen unterhalb der Griffe.","Schulterblätter nach hinten und unten ziehen und Rumpf anspannen."],"execution":["Hebelarme kontrolliert nach vorne-oben drücken.","Ellenbogen am Ende nicht hart durchstrecken.","Spannung in der oberen Brust halten, Schulterblätter bleiben am Polster.","Hebelarme langsam zurückführen, bis die Hände etwa auf Höhe der oberen Brust sind.","In der hinteren Position leichte Dehnung spüren, Gewicht nicht aufsetzen lassen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer leichten Dehnung der Brust in der hinteren Position bis kurz vor die Armstreckung. Nicht tiefer gehen, als die Schultern schmerzfrei zulassen.","breathing":"Beim Drücken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Sitz zu niedrig, Griffe liegen auf Schulterhöhe statt auf Höhe der oberen Brust.","Schultern rollen beim Drücken nach vorne.","Rücken löst sich vom Polster, Lendenwirbelsäule wird überstreckt.","Hebelarme fallen in der exzentrischen Phase unkontrolliert zurück.","Ellenbogen werden am Ende hart durchgestreckt."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Beide Seiten gleich beladen, damit die Belastung symmetrisch bleibt.","Wenn die Schultern unangenehm belastet sind, Sitz etwas höher stellen."],"cable_setup":null,"muscle_focus":["Griffe auf Höhe der oberen Brust einstellen, Schulterblätter nach hinten und unten am geneigten Polster halten, Ellenbogen etwa 45 Grad vom Rumpf abgewinkelt; die Druckrichtung nach vorne-oben betont die obere Brust.","Hebelarme bis in die gedehnte hintere Position zurückführen, ohne das Gewicht aufzusetzen; die gedehnte Position ist der wirksamste Teil der Bewegung.","Exzentrik etwa zwei Sekunden lang kontrollieren und vorne kurz vor der Armstreckung stoppen, damit die Brust unter Spannung bleibt.","Gewicht so wählen, dass die obere Brust den Satz begrenzt und die Schultern nicht nach vorne rollen; bei Bedarf den Sitz etwas höher stellen."],"requirements":["Scheibenbeladene Schrägdruckmaschine (Hebelmaschine) mit auf etwa 30 bis 45 Grad geneigtem Rückenpolster","Gewichtsscheiben und Scheibenverschlüsse","Höhenverstellbarer Sitz"],"grip_alternatives":[],"image_url":"/exercises/incline-press-lever.jpg","machine_name":"DHZ Incline Chest Press, Plate Loaded (zweite Station)","alternative_exercises":["schraegbankdruecken-maschine","schraegbankdruecken-hebel-flex"]}$seed$::jsonb);

-- Schrägbankdrücken Hebel liegend
select public.upsert_seed_exercise($seed${"slug":"schraegbankdruecken-hebel-liegend","name":"Schrägbankdrücken Hebel liegend","category":"chest","equipment":"machine","grip_id":null,"grip_notes":"Pronierter Griff (Handflächen nach vorne) an der Stange des Hebelarms, etwas weiter als schulterbreit. Handgelenke gerade halten, Stange in der Handwurzel ablegen.","primary_muscles":["upper_chest","chest"],"secondary_muscles":["triceps","front_delts"],"description":"Schrägbank mit einem hinter dem Kopf gelagerten, scheibenbeladenen Hebelarm, dessen Stange auf einer festen Bogenbahn nach oben gedrückt wird. Geführte Alternative zum Schrägbankdrücken mit freier Langhantel.","setup":["Gewichtsscheiben auf den Hebelarm laden und mit Verschlüssen sichern.","Auf die Schrägbank legen, Kopf, Schultern und Gesäß liegen auf dem Polster.","Füße flach auf den Boden stellen und Rumpf anspannen.","Stange etwas weiter als schulterbreit fassen, Handgelenke gerade.","Schulterblätter nach hinten und unten ziehen, Hebelarm aus der Ablage lösen."],"execution":["Stange kontrolliert nach oben drücken und der Bahn des Hebelarms folgen.","Ellenbogen am Ende nicht hart durchstrecken.","Spannung in der oberen Brust halten, Schulterblätter bleiben auf dem Polster.","Stange langsam zurückführen, bis sie etwa auf Höhe der oberen Brust ist.","Hebelarm nicht auf der Brust ablegen, Spannung halten.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von der Stange knapp über der oberen Brust bis kurz vor die Armstreckung. Nicht tiefer gehen, als die Schultern schmerzfrei zulassen.","breathing":"Beim Drücken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Gesäß hebt sich beim Drücken vom Polster ab.","Schultern rollen beim Drücken nach vorne.","Ellenbogen stehen zu weit vom Körper ab.","Stange fällt in der exzentrischen Phase unkontrolliert zurück.","Handgelenke knicken unter der Stange nach hinten ab."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Nach dem letzten Satz den Hebelarm kontrolliert in die Ablage zurückführen.","Die geführte Bahn eignet sich, um die Druckbewegung ohne Balancearbeit mit höherer Last zu trainieren."],"cable_setup":null,"muscle_focus":["Schulterblätter nach hinten und unten auf dem Polster fixieren, Ellenbogen etwa 45 Grad vom Rumpf abgewinkelt; die Stange trifft die obere Brust, nicht den Hals.","Stange bis knapp über die obere Brust absenken, damit die Brust in der gedehnten Position unter Last arbeitet; oben kurz vor der Armstreckung stoppen.","Exzentrik etwa zwei Sekunden lang kontrollieren; Gesäß und Schultern bleiben auf dem Polster, die Füße stabilisieren über den Boden.","Gewicht so wählen, dass die obere Brust den Satz begrenzt und nicht Trizeps oder vordere Schulter übernehmen."],"requirements":["Schrägbank mit hinter dem Kopf gelagertem, scheibenbeladenem Hebelarm (Hebel-Schrägdruckbank)","Gewichtsscheiben und Scheibenverschlüsse","Ablage beziehungsweise Haken für den Hebelarm"],"grip_alternatives":[],"image_url":"/exercises/incline-press-lever-bench.jpg","machine_name":"DHZ Flex Press-Station mit Hebel über Kopf","alternative_exercises":["schraegbankdruecken-maschine","schraegbankdruecken-hebelmaschine"]}$seed$::jsonb);

-- Schrägbankdrücken Hebel FLEX
select public.upsert_seed_exercise($seed${"slug":"schraegbankdruecken-hebel-flex","name":"Schrägbankdrücken Hebel FLEX","category":"chest","equipment":"machine","grip_id":null,"grip_notes":"Zwei Griffpositionen an den Hebelarmen: die äußere, weitere Position für mehr Dehnung der Brust, die innere, engere Position für eine schulterfreundlichere Bahn. Handgelenke gerade halten.","primary_muscles":["upper_chest","chest"],"secondary_muscles":["triceps","front_delts"],"description":"Scheibenbeladene Schrägdruckmaschine, deren Hebelarme auf einer Bogenbahn nach vorne-oben laufen und zwei Griffpositionen bieten. Die Bogenbahn bringt die Hände am Ende der Bewegung leicht zusammen.","setup":["Gewichtsscheiben auf beiden Seiten gleich laden und mit Verschlüssen sichern.","Sitz so einstellen, dass die gewählte Griffposition auf Höhe der oberen Brust liegt.","Rücken und Kopf an das Rückenpolster anlehnen, Füße flach auf den Boden stellen.","Eine der beiden Griffpositionen wählen und mit beiden Händen gleich fassen.","Schulterblätter nach hinten und unten ziehen und Rumpf anspannen."],"execution":["Hebelarme kontrolliert nach vorne-oben drücken und der Bogenbahn folgen.","In der vorderen Position Brust kurz anspannen, Ellenbogen nicht hart durchstrecken.","Schulterblätter bleiben während der gesamten Bewegung am Polster.","Hebelarme langsam zurückführen, bis die Hände etwa auf Höhe der oberen Brust sind.","In der hinteren Position leichte Dehnung spüren, Gewicht nicht aufsetzen lassen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer leichten Dehnung der Brust in der hinteren Position bis kurz vor die Armstreckung. Die Bogenbahn vollständig nutzen, soweit die Schultern schmerzfrei bleiben.","breathing":"Beim Drücken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Beide Hände fassen unterschiedliche Griffpositionen.","Schultern rollen beim Drücken nach vorne.","Rücken löst sich vom Polster.","Hebelarme fallen in der exzentrischen Phase unkontrolliert zurück.","Ellenbogen werden am Ende hart durchgestreckt."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Griffposition pro Trainingseinheit festlegen und notieren, damit Gewichte vergleichbar bleiben.","Bei Schulterbeschwerden die engere Griffposition verwenden."],"cable_setup":null,"muscle_focus":["Gewählte Griffposition auf Höhe der oberen Brust bringen, Schulterblätter nach hinten und unten am Polster halten, Ellenbogen etwa 45 Grad vom Rumpf abgewinkelt.","Die äußere Griffposition verlängert den Weg in die gedehnte Position und setzt dort den stärkeren Reiz auf die Brust; die innere Position ist schulterfreundlicher.","Bogenbahn bis in die gedehnte hintere Position nutzen, vorne die Brust kurz anspannen und die Exzentrik etwa zwei Sekunden lang kontrollieren.","Gewicht so wählen, dass die obere Brust den Satz begrenzt und die Schultern nicht nach vorne rollen."],"requirements":["Scheibenbeladene Schrägdruckmaschine mit Bogenbahn und zwei Griffpositionen (FLEX-Bauart)","Gewichtsscheiben und Scheibenverschlüsse","Höhenverstellbarer Sitz mit Rückenpolster"],"grip_alternatives":[],"image_url":"/exercises/incline-press-flex.jpg","machine_name":"DHZ Flex Incline Chest Press (A702L)","alternative_exercises":["schraegbankdruecken-maschine","schraegbankdruecken-hebelmaschine"]}$seed$::jsonb);

-- Bankdrücken Langhantel
select public.upsert_seed_exercise($seed${"slug":"bankdruecken-langhantel","name":"Bankdrücken Langhantel","category":"chest","equipment":"barbell","grip_id":null,"grip_notes":"Pronierter Griff (Handflächen nach vorne), etwas weiter als schulterbreit, Daumen umschließen die Stange. Stange in der Handwurzel ablegen, Handgelenke gerade.","primary_muscles":["chest"],"secondary_muscles":["triceps","front_delts"],"description":"Freie Druckübung auf der Flachbank mit Langhantel und Ablage, die Brust, vordere Schulter und Trizeps belastet. Grundübung für den Oberkörper, bei der Stabilität und Technik gleichermaßen gefordert sind.","setup":["Sicherheitsablagen so einstellen, dass die Stange knapp über der Brust abgefangen wird, wenn sie abgelegt werden muss.","Ablage so einstellen, dass die Stange mit fast gestreckten Armen erreichbar ist.","Gewichtsscheiben beidseitig gleich laden und mit Verschlüssen sichern.","Auf die Bank legen, Augen etwa unter der Stange, Füße flach auf den Boden stellen.","Schulterblätter nach hinten und unten ziehen, Stange etwas weiter als schulterbreit fassen.","Stange aus der Ablage heben und über der Schulter stabilisieren."],"execution":["Stange kontrolliert zur mittleren Brust absenken.","Ellenbogen etwa 45 bis 60 Grad vom Körper abgewinkelt halten.","Stange leicht die Brust berühren lassen, ohne sie abzulegen.","Stange nach oben drücken, bis die Arme fast gestreckt sind.","Schulterblätter und Gesäß bleiben während der gesamten Bewegung auf der Bank.","Nach dem letzten Satz die Stange kontrolliert in die Ablage zurückführen."],"range_of_motion":"Von der Stange an der mittleren Brust bis kurz vor die Armstreckung. Wenn die Schultern in der tiefen Position unangenehm belastet sind, Griffweite verringern.","breathing":"Beim Drücken ausatmen, beim Absenken einatmen. Bei höheren Lasten kurz vor dem Absenken einatmen und die Luft bis zum Drücken halten.","common_mistakes":["Sicherheitsablagen nicht eingestellt oder zu niedrig.","Gesäß hebt sich beim Drücken von der Bank ab.","Ellenbogen stehen 90 Grad vom Körper ab.","Stange prallt von der Brust ab.","Handgelenke knicken unter der Stange nach hinten ab."],"tips":["Bei schweren Sätzen einen Trainingspartner zum Absichern bitten, der die Stange im Zweifel mit anheben kann.","Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Erst dann Gewicht erhöhen, wenn alle Sätze im oberen Wiederholungsbereich sauber ausgeführt werden.","Füße fest in den Boden drücken, um den Rumpf zu stabilisieren."],"cable_setup":null,"muscle_focus":["Schulterblätter nach hinten und unten in die Bank drücken und dort halten; Ellenbogen etwa 45 bis 60 Grad vom Rumpf abgewinkelt, damit die Brust die Last trägt und das Schultergelenk nicht überlastet wird.","Stange bis zur mittleren Brust absenken und die gedehnte Position bewusst mitnehmen, ohne die Stange abprallen zu lassen; dort ist der Reiz auf die Brust am größten.","Exzentrik etwa zwei Sekunden lang kontrollieren, oben kurz vor der Armstreckung stoppen; Gesäß bleibt auf der Bank, Füße fest am Boden.","Griff etwas weiter als schulterbreit; ein engerer Griff verschiebt die Arbeit zum Trizeps. Gewicht so wählen, dass die Brust den Satz begrenzt."],"requirements":["Flachbank mit Hantelablage (Bankdrückstation)","Langhantel mit Gewichtsscheiben und Verschlüssen","Sicherheitsablagen oder Trainingspartner zum Absichern"],"grip_alternatives":[],"image_url":"/exercises/flat-bench-rack.jpg","machine_name":"Olympic Flat Bench mit Hantelablage","alternative_exercises":["brustpresse","brustpresse-hebel"]}$seed$::jsonb);

-- Schrägbankdrücken Langhantel
select public.upsert_seed_exercise($seed${"slug":"schraegbankdruecken-langhantel","name":"Schrägbankdrücken Langhantel","category":"chest","equipment":"barbell","grip_id":null,"grip_notes":"Pronierter Griff (Handflächen nach vorne), etwas weiter als schulterbreit, Daumen umschließen die Stange. Stange in der Handwurzel ablegen, Handgelenke gerade.","primary_muscles":["upper_chest","chest"],"secondary_muscles":["triceps","front_delts"],"description":"Freie Druckübung auf der etwa 30 Grad geneigten Schrägbank mit Langhantel und Ablage, die vor allem den oberen Anteil der Brust belastet. Ergänzung zum flachen Bankdrücken.","setup":["Sicherheitsablagen so einstellen, dass die Stange knapp über der oberen Brust abgefangen wird, wenn sie abgelegt werden muss.","Ablage so einstellen, dass die Stange mit fast gestreckten Armen erreichbar ist.","Gewichtsscheiben beidseitig gleich laden und mit Verschlüssen sichern.","Auf die Schrägbank setzen, Rücken und Kopf anlehnen, Füße flach auf den Boden stellen.","Schulterblätter nach hinten und unten ziehen, Stange etwas weiter als schulterbreit fassen.","Stange aus der Ablage heben und über der Schulter stabilisieren."],"execution":["Stange kontrolliert zur oberen Brust absenken.","Ellenbogen etwa 45 bis 60 Grad vom Körper abgewinkelt halten.","Stange leicht die obere Brust berühren lassen, ohne sie abzulegen.","Stange nach oben drücken, bis die Arme fast gestreckt sind.","Rücken und Gesäß bleiben während der gesamten Bewegung am Polster.","Nach dem letzten Satz die Stange kontrolliert in die Ablage zurückführen."],"range_of_motion":"Von der Stange an der oberen Brust bis kurz vor die Armstreckung. Nicht tiefer gehen, als die Schultern schmerzfrei zulassen.","breathing":"Beim Drücken ausatmen, beim Absenken einatmen.","common_mistakes":["Sicherheitsablagen nicht eingestellt oder zu niedrig.","Stange wird zu weit Richtung Hals abgesenkt.","Ellenbogen stehen 90 Grad vom Körper ab.","Rücken löst sich vom Polster, Lendenwirbelsäule wird überstreckt.","Stange prallt von der Brust ab."],"tips":["Bei schweren Sätzen einen Trainingspartner zum Absichern bitten.","Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Mit einer geringeren Last als beim flachen Bankdrücken starten, da die Schrägposition weniger Kraft zulässt."],"cable_setup":null,"muscle_focus":["Schulterblätter nach hinten und unten am Polster halten, Ellenbogen etwa 45 bis 60 Grad vom Rumpf abgewinkelt; die Stange zur oberen Brust führen, nicht zum Hals.","Ein Bankwinkel um 30 Grad betont die obere Brust; steilere Winkel verlagern die Arbeit zunehmend auf die vordere Schulter.","Gedehnte Position mit der Stange an der oberen Brust bewusst mitnehmen, Exzentrik etwa zwei Sekunden lang kontrollieren und oben kurz vor der Armstreckung stoppen.","Gewicht so wählen, dass die obere Brust den Satz begrenzt; mit weniger Last als beim flachen Bankdrücken starten."],"requirements":["Schrägbank (etwa 30 Grad) mit Hantelablage","Langhantel mit Gewichtsscheiben und Verschlüssen","Sicherheitsablagen oder Trainingspartner zum Absichern"],"grip_alternatives":[],"image_url":"/exercises/incline-bench-rack.jpg","machine_name":"Olympic Incline Bench mit Hantelablage","alternative_exercises":["schraegbankdruecken-maschine"]}$seed$::jsonb);

-- Schulterpresse Maschine
select public.upsert_seed_exercise($seed${"slug":"schulterpresse-maschine","name":"Schulterpresse Maschine","category":"shoulders","equipment":"machine","grip_id":null,"grip_notes":"Pronierte Griffe (Handflächen nach vorne) oder neutrale Griffe, je nach Griffwahl an der Maschine. Handgelenke gerade halten.","primary_muscles":["front_delts","side_delts"],"secondary_muscles":["triceps","traps"],"description":"Steckgewicht-Schulterpresse mit Rückenpolster, bei der die Griffe in der Ausgangsposition auf Schulterhöhe liegen und senkrecht nach oben gedrückt werden. Geführte Druckübung für die vordere und seitliche Schulter.","setup":["Gewicht am Steckgewichtsblock wählen und den Stift vollständig einstecken.","Sitz so einstellen, dass die Griffe in der Ausgangsposition etwa auf Schulterhöhe liegen.","Rücken und Kopf an das Rückenpolster anlehnen, Füße flach auf den Boden stellen.","Griffe fassen, Handgelenke gerade, Ellenbogen unterhalb der Griffe.","Schultern bewusst nach unten ziehen und Rumpf anspannen."],"execution":["Griffe kontrolliert nach oben drücken.","Ellenbogen am Ende nicht hart durchstrecken.","Schultern unten lassen, nicht Richtung Ohren ziehen.","Gewicht langsam zurückführen, bis die Oberarme etwa waagerecht sind.","Gewichtsblock nicht aufsetzen lassen, Spannung halten.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von etwa waagerechten Oberarmen bis kurz vor die Armstreckung. Nicht tiefer gehen, als die Schultern schmerzfrei zulassen.","breathing":"Beim Drücken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Sitz zu niedrig, Griffe liegen deutlich über Schulterhöhe.","Rücken löst sich vom Polster, Lendenwirbelsäule wird überstreckt.","Schultern wandern beim Drücken Richtung Ohren.","Gewicht wird mit Schwung aus der unteren Position gedrückt.","Ellenbogen werden am Ende hart durchgestreckt."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Bei Schulterbeschwerden neutrale Griffe wählen, falls vorhanden.","Erst dann Gewicht erhöhen, wenn alle Sätze im oberen Wiederholungsbereich sauber ausgeführt werden."],"cable_setup":null,"muscle_focus":["Griffe in der Ausgangsposition auf Schulterhöhe, Schultern aktiv nach unten gezogen; so arbeiten vordere und seitliche Schulter statt des Trapezmuskels.","Vollen Bewegungsradius nutzen: unten bis zu etwa waagerechten Oberarmen, damit die Schulter in der gedehnten Position unter Last ist; oben kurz vor der Armstreckung stoppen.","Exzentrik etwa zwei Sekunden lang kontrollieren und den Gewichtsblock nicht aufsetzen lassen.","Gewicht so wählen, dass die Schulter den Satz begrenzt und nicht der Trizeps; Rücken bleibt ohne Hohlkreuz am Polster."],"requirements":["Schulterpresse mit Steckgewichtsblock","Höhenverstellbarer Sitz mit Rückenpolster"],"grip_alternatives":[],"image_url":"/exercises/shoulder-press-selectorized.jpg","machine_name":"DHZ Shoulder Press, Steckgewicht","alternative_exercises":["schulterdruecken-maschine","multi-press-maschine"]}$seed$::jsonb);

-- Scott Curl
select public.upsert_seed_exercise($seed${"slug":"scott-curl","name":"Scott Curl","category":"biceps","equipment":"barbell","grip_id":null,"grip_notes":"Supinierter Griff (Handflächen nach oben) an der SZ-Hantel oder Langhantel, etwa schulterbreit. Die SZ-Hantel entlastet die Handgelenke, die gerade Langhantel betont die Supination.","primary_muscles":["biceps"],"secondary_muscles":["forearms"],"description":"Bizepscurl am Scott-Pult, bei dem die Oberarme flächig auf dem geneigten Polster aufliegen und dadurch kein Schwung aus Schulter oder Rumpf möglich ist. Betont die Bizepsarbeit über einen klar begrenzten Bewegungsweg.","setup":["Sitz so einstellen, dass die Achseln oben an der Polsterkante anliegen und die Oberarme flächig auf dem Polster liegen.","SZ-Hantel oder Langhantel beidseitig gleich laden und mit Verschlüssen sichern.","Hantel aus der Ablage nehmen oder reichen lassen, Griff etwa schulterbreit, Handflächen nach oben.","Oberkörper aufrecht, Brust an das Polster, Füße flach auf den Boden stellen.","Arme kontrolliert strecken, ohne die Ellenbogen am Ende zu überstrecken."],"execution":["Hantel kontrolliert nach oben curlen, Oberarme bleiben auf dem Polster.","In der oberen Position den Bizeps kurz anspannen, Unterarme etwa senkrecht.","Handgelenke während der gesamten Bewegung gerade halten.","Hantel langsam absenken, bis die Arme fast gestreckt sind.","In der unteren Position Spannung halten, nicht in die Ellenbogen fallen lassen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von fast gestreckten Armen bis zur Position mit etwa senkrechten Unterarmen. Die Ellenbogen unten nicht vollständig durchdrücken, da der Bizeps in dieser Position unter Dehnung hohe Last trägt.","breathing":"Beim Curlen ausatmen, beim Absenken einatmen.","common_mistakes":["Ellenbogen heben sich beim Curlen vom Polster ab.","Hantel wird in der exzentrischen Phase fallen gelassen.","Ellenbogen werden in der unteren Position hart durchgestreckt.","Handgelenke knicken beim Curlen nach innen ab.","Oberkörper richtet sich auf und löst sich vom Polster."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Mit einer geringeren Last als beim stehenden Curl starten, da kein Schwung möglich ist.","Bei Beschwerden in den Handgelenken auf die SZ-Hantel wechseln.","Nach dem letzten Satz die Hantel kontrolliert in die Ablage legen oder reichen lassen."],"cable_setup":null,"muscle_focus":["Oberarme flächig auf dem Polster, Achseln an der Polsterkante; so kann die Schulter nicht mithelfen und der Bizeps trägt die gesamte Last.","Untere, gedehnte Position bis fast zur Armstreckung nutzen; am Scott-Pult trägt der Bizeps dort hohe Last, deshalb die Ellenbogen nicht hart durchdrücken.","Exzentrik etwa zwei bis drei Sekunden lang kontrollieren, oben kurz anspannen; Handgelenke gerade halten und nicht einrollen.","Gewicht so wählen, dass der Bizeps den Satz begrenzt und nicht Unterarme oder Handgelenke."],"requirements":["Scott-Pult (Preacher-Bank) mit Hantelablage","SZ-Stange oder kurze Langhantel","Gewichtsscheiben und Verschlüsse"],"grip_alternatives":[],"image_url":"/exercises/preacher-curl-bench.jpg","machine_name":"Preacher Curl Bench (Scott-Pult)","alternative_exercises":["kurzhantelcurl","kabelcurl"]}$seed$::jsonb);

-- Latzug Hebel
select public.upsert_seed_exercise($seed${"slug":"latzug-hebel","name":"Latzug Hebel","category":"back","equipment":"machine","grip_id":null,"grip_notes":"Pronierte oder neutrale Griffe an den Hebelarmen, je nach gewählter Griffposition. Beide Hebelarme sind unabhängig, daher beide Seiten gleichmäßig ziehen. Handgelenke gerade halten.","primary_muscles":["lats"],"secondary_muscles":["biceps","upper_back","forearms","rear_delts"],"description":"Scheibenbeladener Iso-Lateral-Latzug mit zwei unabhängigen Hebelarmen, die den Zug in einer festen Bahn führen. Vertikale Zugübung für den Latissimus, die sich auch einseitig ausführen lässt.","setup":["Gewichtsscheiben auf beiden Hebelarmen gleich beladen und sichern.","Oberschenkelpolster so einstellen, dass die Beine fest fixiert sind.","Hinsetzen, Füße flach auf den Boden, Oberschenkel unter das Polster bringen.","Griffe fassen, Arme gestreckt, Oberkörper aufrecht und leicht nach hinten geneigt.","Schultern vor der ersten Wiederholung bewusst nach unten ziehen."],"execution":["Beide Hebelarme gleichzeitig nach unten ziehen, die Ellenbogen führen die Bewegung.","Schulterblätter nach unten und zusammen ziehen, Brust bleibt angehoben.","In der Endposition kurz halten, Griffe befinden sich etwa auf Höhe der oberen Brust.","Hebelarme langsam zurückführen, Arme kontrolliert strecken.","Oben die Schultern leicht nach oben kommen lassen, um den Lat zu dehnen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von vollständig gestreckten Armen bis die Griffe etwa auf Höhe der oberen Brust sind. Der Bewegungsradius ist durch die Hebelbahn vorgegeben; die Scheiben sollen oben nicht aufsetzen.","breathing":"Beim Ziehen ausatmen, beim Zurückführen einatmen.","common_mistakes":["Oberkörper lehnt sich stark nach hinten und zieht mit Schwung.","Schultern bleiben während des Zugs am Ohr.","Beide Hebelarme werden ungleich beladen oder ungleich schnell bewegt.","Gewicht fällt nach oben zurück, keine Kontrolle in der exzentrischen Phase.","Griffe werden mit den Armen statt mit den Ellenbogen geführt."],"tips":["Exzentrische Phase bewusst zwei bis drei Sekunden lang ausführen.","Einseitige Ausführung nutzen, um Unterschiede zwischen beiden Seiten auszugleichen.","Scheiben auf beiden Seiten in kleinen Schritten erhöhen, erst wenn alle Sätze sauber sind.","Daumen auf die Griffe legen statt zu umschließen, um weniger mit den Unterarmen zu arbeiten."],"cable_setup":null,"muscle_focus":["Ellenbogen zur Hüfte ziehen, nicht die Hände zur Brust; Schulterblätter nach unten und zusammen, Brust angehoben. So übernimmt der Latissimus statt des Bizeps.","Oben die Arme vollständig strecken und die Schultern leicht nach oben kommen lassen; die gedehnte Position ist der wirksamste Teil der Bewegung.","Exzentrik zwei bis drei Sekunden lang kontrollieren und die Scheiben oben nicht aufsetzen lassen.","Gewicht so wählen, dass der Latissimus den Satz begrenzt und der Oberkörper nicht mit Schwung nach hinten arbeitet."],"requirements":["Scheibenbeladener Iso-Lateral-Latzug (Hebelmaschine) mit zwei unabhängigen Hebelarmen","Gewichtsscheiben und Scheibenverschlüsse","Einstellbares Oberschenkelpolster"],"grip_alternatives":[],"image_url":"/exercises/lat-pulldown-lever.jpg","machine_name":"DHZ Lat Pulldown, Plate Loaded","alternative_exercises":["neutraler-latzug","breiter-latzug"]}$seed$::jsonb);

-- Rudern Hebel sitzend
select public.upsert_seed_exercise($seed${"slug":"rudern-hebel-sitzend","name":"Rudern Hebel sitzend","category":"back","equipment":"machine","grip_id":null,"grip_notes":"Neutrale Griffe (Handflächen zeigen zueinander) an den Hebelarmen. Handgelenke gerade, Griffe nicht verkrampft umschließen.","primary_muscles":["lats","mid_back"],"secondary_muscles":["biceps","rear_delts","forearms","upper_back"],"description":"Scheibenbeladene Rudermaschine mit Brustpolster und zwei unabhängigen Hebelarmen. Horizontale Zugübung für Latissimus und mittleren Rücken, bei der der Rumpf durch das Polster abgestützt wird.","setup":["Gewichtsscheiben auf beiden Hebelarmen gleich beladen und sichern.","Sitzhöhe so einstellen, dass die Griffe etwa auf Höhe der unteren Brust liegen.","Hinsetzen, Brust fest an das Polster legen, Füße flach auf die Fußstützen stellen.","Neutrale Griffe fassen, Arme gestreckt, Schulterblätter leicht nach vorne kommen lassen.","Rumpf anspannen, Blick geradeaus."],"execution":["Beide Griffe gleichzeitig zum Körper ziehen, Ellenbogen nah am Körper nach hinten führen.","Schulterblätter am Ende der Bewegung zusammen ziehen.","Brust bleibt während der gesamten Bewegung am Polster.","In der Endposition kurz halten.","Hebelarme langsam zurückführen, Arme kontrolliert strecken.","Schulterblätter am vorderen Ende leicht lösen, um den Rücken zu dehnen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von gestreckten Armen mit leicht vorgeschobenen Schulterblättern bis die Ellenbogen etwa auf Höhe des Rumpfes sind. Nicht weiter ziehen, wenn dafür die Brust vom Polster abhebt.","breathing":"Beim Ziehen ausatmen, beim Zurückführen einatmen.","common_mistakes":["Brust löst sich vom Polster und der Oberkörper lehnt sich nach hinten.","Schultern ziehen beim Rudern nach oben in Richtung Ohr.","Bewegung kommt aus den Armen statt aus den Schulterblättern.","Gewicht wird nach vorne fallen gelassen.","Sitz zu hoch oder zu niedrig, Zugrichtung passt nicht zur Brusthöhe."],"tips":["Vorstellen, die Ellenbogen nach hinten zu ziehen statt die Griffe zur Brust.","Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Einseitige Ausführung ist durch die unabhängigen Hebelarme möglich und hilft bei Seitenunterschieden.","Griffe mit den Fingern haken statt fest zu umschließen, um die Unterarme zu entlasten."],"cable_setup":null,"muscle_focus":["Ellenbogen nah am Körper nach hinten ziehen, Brust bleibt am Polster; so arbeiten Latissimus und mittlerer Rücken statt der Arme.","Vorne die Arme vollständig strecken und die Schulterblätter nach vorne gleiten lassen, damit der Rücken in der gedehnten Position unter Last ist.","Am Ende die Schulterblätter zusammenziehen, kurz halten und die Exzentrik etwa zwei Sekunden lang kontrollieren.","Gewicht so wählen, dass der Rücken den Satz begrenzt und die Brust nicht vom Polster abhebt."],"requirements":["Scheibenbeladene Rudermaschine (Hebelmaschine) mit Brustpolster und zwei unabhängigen Hebelarmen","Gewichtsscheiben und Scheibenverschlüsse","Höhenverstellbarer Sitz mit Fußstützen"],"grip_alternatives":[],"image_url":"/exercises/seated-row-lever.jpg","machine_name":"DHZ Low Row, Plate Loaded","alternative_exercises":["brustgestuetztes-rudern","enges-rudern"]}$seed$::jsonb);

-- Beinpresse 45°
select public.upsert_seed_exercise($seed${"slug":"beinpresse-45-grad","name":"Beinpresse 45°","category":"quads","equipment":"machine","grip_id":null,"grip_notes":"Hände an den seitlichen Haltegriffen, um Rücken und Becken am Polster zu halten. Griffe nicht zum Mitdrücken nutzen.","primary_muscles":["quads","glutes"],"secondary_muscles":["hamstrings"],"description":"Scheibenbeladene Beinpresse, bei der der Schlitten auf einer 45-Grad-Schiene geführt wird. Grundübung für die Beine mit hoher Belastbarkeit, bei der kein Gleichgewicht gehalten werden muss.","setup":["Gewichtsscheiben beidseitig gleich beladen und sichern.","Rückenlehne so einstellen, dass das Becken in der unteren Position am Polster bleibt.","Hinsetzen, Rücken und Gesäß vollständig an das Polster legen.","Füße etwa schulterbreit mittig auf der Fußplatte, Zehen leicht nach außen.","Schlitten mit gestreckten Beinen leicht anheben und Sicherheitsriegel nach außen klappen.","Hände an die seitlichen Haltegriffe legen."],"execution":["Schlitten langsam absenken, Knie in Richtung der Zehen beugen.","So tief absenken, wie das Becken am Polster bleibt.","Über die ganze Fußsohle nach oben drücken, Fersen bleiben auf der Platte.","Knie oben nicht vollständig durchstrecken.","Knie während der Bewegung in Linie mit den Füßen halten.","Nächste Wiederholung ohne Abfedern in der unteren Position beginnen."],"range_of_motion":"Beine bis etwa 90 Grad oder etwas tiefer beugen, solange das Becken nicht vom Polster abhebt. Oben kurz vor der vollen Kniestreckung stoppen.","breathing":"Beim Drücken ausatmen, beim Absenken einatmen.","common_mistakes":["Becken rollt in der unteren Position vom Polster ab und der untere Rücken rundet sich.","Knie werden oben hart durchgestreckt.","Knie fallen beim Drücken nach innen.","Fersen heben von der Fußplatte ab.","Sicherheitsriegel werden vor dem Satz nicht geöffnet oder danach nicht wieder eingeklappt."],"tips":["Sicherheitsriegel nach jedem Satz wieder einklappen, bevor die Beine entlastet werden.","Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Höhere Fußposition belastet Gesäß und hintere Oberschenkel stärker, tiefere Fußposition die Oberschenkelvorderseite.","Gewicht in kleinen Schritten erhöhen, erst wenn die Tiefe in allen Sätzen gleich bleibt."],"cable_setup":null,"muscle_focus":["Tiefe nur so weit, wie das Becken am Polster bleibt; sobald es abrollt, verlagert sich die Last auf den unteren Rücken statt auf Oberschenkel und Gesäß.","Innerhalb dieser Grenze die volle Beugung bis 90 Grad oder etwas tiefer nutzen; die gedehnte Position der Oberschenkelvorderseite setzt den stärksten Reiz.","Die Fußposition steuert den Schwerpunkt: tief und schulterbreit für die Oberschenkelvorderseite, höher auf der Platte für Gesäß und hintere Oberschenkel.","Exzentrik zwei bis drei Sekunden lang kontrollieren, oben kurz vor der Kniestreckung stoppen und das Gewicht so wählen, dass die Beine den Satz begrenzen."],"requirements":["Scheibenbeladene 45-Grad-Beinpresse mit Sicherheitsriegeln","Gewichtsscheiben und Scheibenverschlüsse","Einstellbare Rückenlehne"],"grip_alternatives":[],"image_url":"/exercises/leg-press-45.jpg","machine_name":"Leg Press 45°, Plate Loaded","alternative_exercises":["beinpresse","hackenschmidt"]}$seed$::jsonb);

-- Multipresse Kniebeuge
select public.upsert_seed_exercise($seed${"slug":"multipresse-kniebeuge","name":"Multipresse Kniebeuge","category":"quads","equipment":"smith_machine","grip_id":null,"grip_notes":"Stange etwas breiter als schulterbreit mit pronierten Händen fassen, die Hände sichern die Stange auf dem oberen Rücken. Ellenbogen unter der Stange, Handgelenke gerade.","primary_muscles":["quads","glutes"],"secondary_muscles":["hamstrings","abs"],"description":"Kniebeuge an der geführten Stange der Multipresse, bei der die Stange in einer festen Bahn läuft. Geeignet, um die Beuge ohne Balanceanteil zu trainieren und die Bewegung mit Sicherheitsstopps abzusichern.","setup":["Sicherheitsstopps knapp unterhalb der tiefsten Position der Beuge einstellen.","Stange auf Höhe der oberen Brust einhängen, Scheiben beidseitig gleich beladen und sichern.","Unter die Stange treten und die Stange auf dem oberen Rücken ablegen, nicht auf dem Nacken.","Füße etwa schulterbreit und leicht vor der Stange aufstellen, Zehen leicht nach außen.","Stange durch Drehen aus den Haken lösen, Rumpf anspannen."],"execution":["Hüfte und Knie gleichzeitig beugen und kontrolliert nach unten gehen.","Knie folgen der Richtung der Zehen.","Oberkörper bleibt aufrecht, Blick geradeaus.","Tiefe erreichen, bei der der untere Rücken neutral bleibt.","Über die ganze Fußsohle nach oben drücken, Fersen bleiben am Boden.","Oben kurz vor der vollen Kniestreckung stoppen.","Nach dem letzten Satz die Stange wieder in die Haken drehen."],"range_of_motion":"Bis die Oberschenkel etwa parallel zum Boden sind oder so tief, wie der untere Rücken neutral bleibt. Oben nicht hart durchstrecken.","breathing":"Beim Absenken einatmen, beim Hochdrücken ausatmen.","common_mistakes":["Füße stehen direkt unter der Stange, dadurch kippt der Oberkörper nach vorne.","Knie fallen nach innen.","Unterer Rücken rundet sich in der tiefen Position.","Sicherheitsstopps werden nicht eingestellt.","Fersen heben beim Hochdrücken vom Boden ab."],"tips":["Vor dem ersten Arbeitssatz mit leerer Stange prüfen, ob die Sicherheitsstopps passend eingestellt sind.","Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Füße weiter nach vorne stellen, um Gesäß und hintere Oberschenkel stärker einzubeziehen.","Gewicht erst erhöhen, wenn Tiefe und Technik in allen Sätzen gleich bleiben."],"cable_setup":null,"muscle_focus":["Füße leicht vor der Stange aufstellen, damit der Oberkörper aufrecht bleibt und die Last auf Oberschenkelvorderseite und Gesäß liegt.","So tief gehen, wie der untere Rücken neutral bleibt; die tiefe, gedehnte Position setzt den stärksten Reiz auf Oberschenkel und Gesäß.","Knie in Richtung der Zehen führen, Fersen am Boden, Exzentrik etwa zwei Sekunden lang kontrollieren; oben kurz vor der Kniestreckung stoppen.","Füße weiter vorne verschieben die Arbeit zu Gesäß und hinteren Oberschenkeln; Gewicht so wählen, dass die Beine den Satz begrenzen."],"requirements":["Multipresse (Smith Machine) mit einstellbaren Sicherheitsstopps","Gewichtsscheiben und Scheibenverschlüsse"],"grip_alternatives":[],"image_url":"/exercises/smith-machine.jpg","machine_name":"Smith Machine (Multipresse)","alternative_exercises":["kniebeuge","hackenschmidt"]}$seed$::jsonb);

-- Adduktoren Maschine
select public.upsert_seed_exercise($seed${"slug":"adduktoren-maschine","name":"Adduktoren Maschine","category":"adductors","equipment":"machine","grip_id":null,"grip_notes":"Hände an den seitlichen Haltegriffen, um das Becken ruhig am Polster zu halten.","primary_muscles":["adductors"],"secondary_muscles":[],"description":"Steckgewichtmaschine, bei der die Beine gegen Polster an den Innenseiten der Oberschenkel zusammengeführt werden. Isolierte Übung für die Adduktoren.","setup":["Gewicht am Steckgewicht wählen.","Hinsetzen, Rücken an die Lehne, Oberschenkel innen an die Polster legen.","Startweite über den Einstellhebel so wählen, dass die Dehnung spürbar, aber angenehm ist.","Füße auf die Fußstützen stellen, Hände an die Haltegriffe.","Becken und Rücken fest am Polster, Rumpf anspannen."],"execution":["Beine kontrolliert zusammenführen, bis sich die Polster fast berühren.","In der Endposition kurz anspannen.","Beine langsam wieder nach außen führen.","Bewegung an der eingestellten Startweite stoppen, ohne dass das Gewicht aufsetzt.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer angenehm gedehnten Startposition bis die Polster fast zusammen sind. Die Startweite in kleinen Schritten vergrößern, nicht in die maximale Dehnung gehen.","breathing":"Beim Zusammenführen ausatmen, beim Öffnen einatmen.","common_mistakes":["Startweite zu groß gewählt, dadurch Zug in der Leiste.","Beine schnellen zusammen und das Gewicht wird nach außen fallen gelassen.","Becken kippt oder der Rücken löst sich vom Polster.","Gewicht setzt in der offenen Position auf und die Spannung geht verloren."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Startweite erst vergrößern, wenn sich der aktuelle Bewegungsradius sauber ausführen lässt.","Moderate Gewichte und höhere Wiederholungszahlen sind hier sinnvoll.","Als Ergänzung zu Kniebeuge und Beinpresse einsetzen."],"cable_setup":null,"muscle_focus":["Startweite so wählen, dass die Innenseite der Oberschenkel spürbar gedehnt ist, aber kein Zug in der Leiste entsteht; die gedehnte Position ist der wirksamste Teil der Bewegung.","Beine kontrolliert zusammenführen, am Ende kurz anspannen und das Gewicht nicht aufsetzen lassen, damit die Spannung in der Dehnung erhalten bleibt.","Becken und Rücken bleiben am Polster; jedes Kippen nimmt den Adduktoren Last ab.","Exzentrik zwei bis drei Sekunden lang kontrollieren und das Gewicht so wählen, dass die Adduktoren den Satz begrenzen."],"requirements":["Adduktoren-Maschine mit Steckgewichtsblock und Innenpolstern","Einstellhebel für die Startweite"],"grip_alternatives":[],"image_url":"/exercises/adductor-machine.jpg","machine_name":"DHZ Adductor, Steckgewicht","alternative_exercises":["abduktoren-maschine"]}$seed$::jsonb);

-- Abduktoren Maschine
select public.upsert_seed_exercise($seed${"slug":"abduktoren-maschine","name":"Abduktoren Maschine","category":"adductors","equipment":"machine","grip_id":null,"grip_notes":"Hände an den seitlichen Haltegriffen, um das Becken ruhig am Polster zu halten.","primary_muscles":["abductors","glutes"],"secondary_muscles":[],"description":"Steckgewichtmaschine, bei der die Beine gegen Polster an den Außenseiten der Oberschenkel nach außen gedrückt werden. Isolierte Übung für die Abduktoren und die seitlichen Gesäßmuskeln.","setup":["Gewicht am Steckgewicht wählen.","Hinsetzen, Rücken an die Lehne, Oberschenkel außen an die Polster legen.","Polster über den Einstellhebel so stellen, dass die Beine in der Startposition geschlossen sind.","Füße auf die Fußstützen stellen, Hände an die Haltegriffe.","Becken und Rücken fest am Polster, Rumpf anspannen."],"execution":["Beine kontrolliert gegen die Polster nach außen drücken.","So weit öffnen, wie das Becken ruhig am Polster bleibt.","In der Endposition kurz anspannen.","Beine langsam wieder zusammenführen.","Bewegung stoppen, bevor das Gewicht aufsetzt.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von geschlossenen Beinen bis zu einer Öffnung, bei der Becken und Rücken am Polster bleiben. Nicht mit Schwung in die Endposition gehen.","breathing":"Beim Öffnen ausatmen, beim Zusammenführen einatmen.","common_mistakes":["Oberkörper lehnt sich nach vorne oder das Becken kippt, um mehr Weite zu erreichen.","Beine schnellen nach außen und fallen danach zurück.","Gewicht setzt in der geschlossenen Position auf.","Füße verlieren den Kontakt zu den Fußstützen."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Leichte Vorneigung des Oberkörpers mit geradem Rücken verschiebt die Belastung stärker auf das Gesäß.","Moderate Gewichte und höhere Wiederholungszahlen sind hier sinnvoll.","Als Ergänzung zu Hip Thrust und Kniebeuge einsetzen."],"cable_setup":null,"muscle_focus":["Becken fest am Polster, Beine gegen die Außenpolster drücken; so arbeiten Abduktoren und seitliches Gesäß statt des unteren Rückens.","Leichte Vorneigung mit geradem Rücken verlagert die Last stärker auf das seitliche Gesäß (Gluteus medius); aufrechtes Sitzen betont die Abduktoren.","Bewegung über den vollen Radius bis zu der Öffnung, bei der das Becken ruhig bleibt; am Ende kurz anspannen und das Gewicht nicht aufsetzen lassen.","Exzentrik zwei bis drei Sekunden lang kontrollieren und das Gewicht so wählen, dass die Abduktoren den Satz begrenzen."],"requirements":["Abduktoren-Maschine mit Steckgewichtsblock und Außenpolstern","Einstellhebel für die Startposition"],"grip_alternatives":[],"image_url":"/exercises/abductor-machine.jpg","machine_name":"DHZ Abductor, Steckgewicht","alternative_exercises":["adduktoren-maschine"]}$seed$::jsonb);

-- Air Bike
select public.upsert_seed_exercise($seed${"slug":"air-bike","name":"Air Bike","category":"cardio","equipment":"cardio","grip_id":null,"grip_notes":"Hände an den beweglichen Armhebeln, Griffe locker umschließen. Alternativ die festen Griffe in der Mitte nutzen, wenn nur die Beine arbeiten sollen.","primary_muscles":["quads"],"secondary_muscles":["hamstrings","calves","triceps","front_delts"],"description":"Fahrrad mit Luftwiderstand und beweglichen Armhebeln, bei dem Beine und Arme gleichzeitig arbeiten. Der Widerstand steigt mit dem Tempo; geeignet für Aufwärmen, Intervalle und Ausdauertraining.","setup":["Sattelhöhe so einstellen, dass das Knie in der unteren Pedalstellung leicht gebeugt bleibt.","Sattel in der Länge so stellen, dass die Armhebel mit leicht gebeugten Ellenbogen erreichbar sind.","Füße mittig auf die Pedale stellen, Riemen falls vorhanden schließen.","Aufrecht sitzen, Rumpf anspannen, Griffe fassen.","Mit niedrigem Tempo starten und die Konsole bei Bedarf auf Zeit oder Intervall stellen."],"execution":["Gleichmäßig in die Pedale treten, Beine arbeiten über die ganze Umdrehung.","Armhebel abwechselnd drücken und ziehen, Bewegung aus Schulter und Rumpf.","Oberkörper bleibt stabil, kein Wippen im Sattel.","Tempo steigern, um den Widerstand zu erhöhen; Tempo senken, um ihn zu verringern.","Bei Intervallen Belastungs- und Erholungsphasen klar voneinander trennen.","Zum Schluss ein bis zwei Minuten locker austreten."],"range_of_motion":"Volle Pedalumdrehung mit leichter Kniebeugung im unteren Punkt. Armhebel über den vollen Hebelweg drücken und ziehen, ohne die Ellenbogen am Ende hart durchzustrecken.","breathing":"Gleichmäßig und tief atmen, Atemrhythmus an das Tempo anpassen. Nicht die Luft anhalten.","common_mistakes":["Sattel zu niedrig, dadurch sind die Knie stark gebeugt.","Oberkörper rundet sich und zieht nur noch mit den Armen.","Tempo zu Beginn zu hoch, die Belastung lässt sich nicht über die geplante Dauer halten.","Füße rutschen von den Pedalen, weil die Riemen nicht geschlossen sind."],"tips":["Dauer in Minuten im Feld Wiederholungen eintragen; Gewicht bleibt 0 oder kann als Widerstandsstufe genutzt werden, falls das Gerät eine hat.","Für Intervalle etwa 20 bis 40 Sekunden hohes Tempo mit ein bis zwei Minuten lockerem Treten abwechseln.","Für reines Beintraining die festen Griffe nutzen und die Armhebel ruhen lassen.","Progression über längere Dauer oder mehr Distanz beziehungsweise Kalorien bei gleicher Zeit."],"cable_setup":null,"muscle_focus":["Der Widerstand steigt mit dem Tempo; Belastung über die Trittfrequenz steuern, nicht über Wippen im Sattel.","Beine arbeiten über die ganze Pedalumdrehung, Armhebel aus Schulter und Rumpf drücken und ziehen; so verteilt sich die Belastung auf Ober- und Unterkörper.","Sattelhöhe mit leicht gebeugtem Knie im unteren Punkt hält die Oberschenkelvorderseite im arbeitsfähigen Bereich.","Für reines Beintraining die festen Griffe nutzen; bei Intervallen Belastung und Erholung klar trennen und das Tempo so wählen, dass es über die geplante Dauer haltbar ist."],"requirements":["Air Bike mit Luftwiderstand und beweglichen Armhebeln","Verstellbarer Sattel (Höhe und Länge)"],"grip_alternatives":[],"image_url":"/exercises/air-bike.jpg","machine_name":"USAEON Air Bike","alternative_exercises":[]}$seed$::jsonb);

-- Rudergerät
select public.upsert_seed_exercise($seed${"slug":"rudergeraet","name":"Rudergerät","category":"cardio","equipment":"cardio","grip_id":null,"grip_notes":"Griff mit beiden Händen etwa schulterbreit von oben fassen, Handgelenke gerade. Griff locker halten, die Finger haken, nicht verkrampfen.","primary_muscles":["quads","lats"],"secondary_muscles":["hamstrings","glutes","biceps","mid_back"],"description":"Rudergerät mit Magnet- oder Luftwiderstand, bei dem Beine, Rumpf und Arme nacheinander arbeiten. Ganzkörper-Ausdauerübung, die sich für Aufwärmen, Intervalle und Dauerbelastung eignet.","setup":["Widerstandsstufe am Gerät einstellen, für den Einstieg eine mittlere Stufe wählen.","Auf den Rollsitz setzen, Füße in die Fußschalen stellen und Riemen über dem Fußballen schließen.","Griff fassen, Knie beugen und mit aufrechtem Oberkörper nach vorne rollen.","Schienbeine etwa senkrecht, Arme gestreckt, Rumpf angespannt.","Konsole bei Bedarf auf Zeit, Distanz oder Intervall stellen."],"execution":["Zuerst die Beine strecken und den Sitz nach hinten schieben, Arme bleiben gestreckt.","Dann den Oberkörper leicht nach hinten lehnen, etwa auf elf Uhr.","Zuletzt den Griff zum unteren Brustbereich ziehen, Ellenbogen nah am Körper.","Rückweg in umgekehrter Reihenfolge: Arme strecken, Oberkörper nach vorne, dann Knie beugen.","Kontrolliert nach vorne rollen, nicht mit Schwung in die Startposition fallen.","Schlagfrequenz gleichmäßig halten, etwa 20 bis 28 Schläge pro Minute für Dauerbelastung."],"range_of_motion":"Vom eingerollten Start mit senkrechten Schienbeinen bis zu gestreckten Beinen, leichter Rücklage und Griff am unteren Brustbereich. Der Zug ist etwa doppelt so schnell wie die Rückführung.","breathing":"Beim Zug ausatmen, beim Vorrollen einatmen. Atmung gleichmäßig an den Schlagrhythmus koppeln.","common_mistakes":["Arme ziehen zu früh, bevor die Beine gestreckt sind.","Oberkörper lehnt sich zu weit nach hinten oder rundet sich beim Vorrollen.","Knie werden auf dem Rückweg zu früh gebeugt und kommen dem Griff in die Quere.","Griff wird zum Hals statt zur unteren Brust gezogen.","Schlagfrequenz zu hoch, dadurch wird der Zug unkontrolliert."],"tips":["Dauer in Minuten im Feld Wiederholungen eintragen; im Feld Gewicht kann die Widerstandsstufe notiert werden, sonst bleibt es 0.","Reihenfolge Beine, Rumpf, Arme bei langsamem Tempo einüben, bevor die Intensität steigt.","Progression über längere Dauer oder eine bessere Zeit pro 500 Meter bei gleicher Schlagfrequenz.","Für Intervalle Zugphasen von ein bis zwei Minuten mit lockeren Erholungsphasen abwechseln."],"cable_setup":null,"muscle_focus":["Reihenfolge Beine, Rumpf, Arme einhalten: erst die Beine strecken, dann den Oberkörper leicht zurücklehnen, zuletzt den Griff zur unteren Brust ziehen. So kommt der größte Teil der Kraft aus den Beinen.","Schlagzahl moderat halten, etwa 20 bis 28 Schläge pro Minute; Intensität über die Kraft pro Zug steuern, nicht über die Frequenz.","Rückweg in umgekehrter Reihenfolge und etwa doppelt so lang wie der Zug; der untere Rücken bleibt dabei gerade.","Widerstandsstufe mittel wählen; eine hohe Stufe macht den Zug schwerfällig und verschiebt die Belastung auf den Rücken."],"requirements":["Rudergerät mit Magnet- oder Luftwiderstand (Rollsitz, Fußschalen mit Riemen)","Konsole für Zeit, Distanz oder Intervall"],"grip_alternatives":[],"image_url":"/exercises/rowing-machine.jpg","machine_name":"Rudergerät (Neolymp)","alternative_exercises":[]}$seed$::jsonb);

-- Ski Erg
select public.upsert_seed_exercise($seed${"slug":"ski-erg","name":"Ski Erg","category":"cardio","equipment":"cardio","grip_id":null,"grip_notes":"Beide Griffe von oben fassen, Handflächen zeigen nach unten beziehungsweise zueinander. Griffe locker halten, der Zug kommt aus Rumpf und Latissimus, nicht aus den Fingern.","primary_muscles":["lats","abs"],"secondary_muscles":["triceps","hamstrings","glutes"],"description":"Ski-Ergometer, bei dem die Griffe von oben nach unten gezogen werden, ähnlich dem Doppelstockschub beim Skilanglauf. Belastet Latissimus und Bauch über die Rumpfbeuge; geeignet für Aufwärmen, Intervalle und Ausdauertraining.","setup":["Widerstandsstufe am Gerät einstellen, für den Einstieg eine mittlere Stufe wählen.","Etwa eine Armlänge vor dem Gerät stehen, Füße hüftbreit.","Griffe fassen und mit gestreckten Armen über Kopf in die Startposition bringen.","Knie leicht gebeugt, Rumpf angespannt, Blick nach vorne.","Konsole bei Bedarf auf Zeit, Distanz oder Intervall stellen."],"execution":["Griffe zügig nach unten ziehen, der Oberkörper beugt sich dabei aus der Hüfte nach vorne.","Hüfte und Knie leicht mitbeugen, Rücken bleibt gerade.","Griffe an den Oberschenkeln vorbei nach hinten führen, Arme am Ende fast gestreckt.","Oberkörper wieder aufrichten und die Arme kontrolliert nach oben in die Startposition bringen.","Der Zug ist zügig und kräftig, die Rückführung ruhiger.","Rhythmus gleichmäßig halten."],"range_of_motion":"Von gestreckten Armen über Kopf bis die Griffe hinter den Oberschenkeln sind, mit Rumpfbeuge aus der Hüfte. Rückführung bis zur Streckung über Kopf, ohne ins Hohlkreuz zu fallen.","breathing":"Beim Zug nach unten ausatmen, beim Aufrichten einatmen. Atmung gleichmäßig an den Rhythmus koppeln.","common_mistakes":["Rücken rundet sich beim Zug nach unten.","Zug kommt nur aus den Armen, Rumpf und Hüfte bleiben steif.","Zu nah am Gerät gestanden, dadurch fehlt Platz für die Rumpfbeuge.","Griffe werden oben zu weit nach hinten geführt und der untere Rücken überstreckt."],"tips":["Dauer in Minuten im Feld Wiederholungen eintragen; im Feld Gewicht kann die Widerstandsstufe notiert werden, sonst bleibt es 0.","Bewegung bei niedrigem Tempo einüben, bevor die Intensität steigt.","Progression über längere Dauer oder mehr Distanz bei gleicher Zeit.","Für Intervalle 30 bis 60 Sekunden zügiger Zug mit lockeren Erholungsphasen abwechseln."],"cable_setup":null,"muscle_focus":["Der Zug kommt aus der Hüftbeuge mit dem Rumpf: Oberkörper aus der Hüfte nach vorne beugen, Latissimus und Bauch ziehen die Griffe nach unten, die Arme übertragen die Kraft.","Hüfte und Knie leicht mitbeugen, Rücken gerade; ein runder Rücken nimmt Latissimus und Bauch die Arbeit ab.","Oben die Arme gestreckt über Kopf bringen, ohne ins Hohlkreuz zu fallen; so arbeitet der Latissimus aus der gedehnten Position.","Zug zügig, Rückführung ruhiger; Intensität über die Kraft pro Zug steuern, Widerstandsstufe mittel."],"requirements":["Ski-Ergometer mit Griffen über Kopf (Luft- oder Magnetwiderstand)","Etwa eine Armlänge Platz vor dem Gerät"],"grip_alternatives":[],"image_url":"/exercises/ski-erg.jpg","machine_name":"Ski-Ergometer (Rogue)","alternative_exercises":[]}$seed$::jsonb);

-- Laufband
select public.upsert_seed_exercise($seed${"slug":"laufband","name":"Laufband","category":"cardio","equipment":"cardio","grip_id":null,"grip_notes":"Hände frei und locker mitschwingen lassen. Haltegriffe nur zum Aufsteigen, Absteigen oder kurzen Abstützen nutzen.","primary_muscles":["quads","calves"],"secondary_muscles":["hamstrings","glutes"],"description":"Laufband mit einstellbarer Geschwindigkeit und Steigung für Gehen, zügiges Gehen und Laufen. Geeignet für Aufwärmen, Dauerbelastung und Intervalle.","setup":["Beidbeinig auf die seitlichen Trittflächen stellen, nicht auf das stehende Band.","Not-Stopp-Clip an der Kleidung befestigen.","Band mit niedriger Geschwindigkeit starten und auf das Band treten.","Geschwindigkeit und Steigung schrittweise auf das geplante Niveau erhöhen.","Aufrecht laufen oder gehen, Blick nach vorne, nicht auf die Füße."],"execution":["Tempo und Steigung über die geplante Dauer gleichmäßig halten.","Mit dem Fuß unter dem Körper aufsetzen, Schritte kurz und locker halten.","Arme locker mitschwingen lassen, Schultern entspannt.","Bei Steigung den Oberkörper leicht nach vorne neigen, nicht an den Griffen festhalten.","Bei Intervallen die Geschwindigkeit stufenweise erhöhen und senken, nicht abrupt.","Zum Schluss zwei bis drei Minuten im Gehen auslaufen, dann Band stoppen und absteigen."],"range_of_motion":"Natürliche Schrittlänge bei aufrechtem Oberkörper. Schrittfrequenz lieber erhöhen, als die Schritte zu verlängern.","breathing":"Gleichmäßig und tief atmen, Atemrhythmus an die Schritte koppeln. Nicht die Luft anhalten.","common_mistakes":["Dauerhaftes Festhalten an den Griffen, besonders bei Steigung.","Schritte zu lang, der Fuß setzt weit vor dem Körper auf.","Blick nach unten auf die Füße oder zur Seite.","Not-Stopp-Clip nicht befestigt.","Abstieg vom laufenden Band ohne vorheriges Abbremsen."],"tips":["Dauer in Minuten im Feld Wiederholungen eintragen; Gewicht bleibt 0 oder kann als Widerstandsstufe genutzt werden, zum Beispiel für die Steigung in Prozent.","Progression über längere Dauer, höhere Geschwindigkeit oder mehr Steigung, jeweils nur eine Größe gleichzeitig erhöhen.","Steigung von ein bis zwei Prozent beim Laufen gleicht den fehlenden Luftwiderstand aus.","Für Intervalle etwa eine Minute schnelleres Tempo mit ein bis zwei Minuten lockerem Gehen oder Laufen abwechseln."],"cable_setup":null,"muscle_focus":["Für Gesäß und Waden Steigung statt Tempo erhöhen; schon 5 bis 10 Prozent Steigung im zügigen Gehen belasten Gesäß und Waden deutlich stärker als flaches Laufen.","Fuß unter dem Körper aufsetzen, Schritte kurz und schnell; lange Schritte vor dem Körper bremsen und belasten die Knie.","Hände frei lassen und nicht an den Griffen festhalten; Festhalten nimmt die Belastung aus Beinen und Gesäß.","Ein bis zwei Prozent Steigung beim Laufen gleichen den fehlenden Luftwiderstand aus; nur eine Größe gleichzeitig steigern: Dauer, Tempo oder Steigung."],"requirements":["Laufband mit einstellbarer Geschwindigkeit und Steigung","Not-Stopp-Clip"],"grip_alternatives":[],"image_url":"/exercises/treadmill.jpg","machine_name":"USAEON Laufband","alternative_exercises":[]}$seed$::jsonb);


-- >>>>>>>>>> 0006_seed_templates.sql <<<<<<<<<<

-- ============================================================
-- 0006_seed_templates.sql
-- GENERIERT aus supabase/seed/templates.json via `npm run db:generate` – nicht manuell bearbeiten.
-- Standard-Trainingspläne (Vorlagen), werden bei Registrierung je Benutzer kopiert.
-- ============================================================

-- Oberkörper A
select public.upsert_seed_template($seed${"name":"Oberkörper A","sort_order":1,"exercises":[{"slug":"schraegbankdruecken-maschine","sets":3,"rep_min":6,"rep_max":10},{"slug":"pec-deck","sets":3,"rep_min":6,"rep_max":10},{"slug":"neutraler-latzug","sets":3,"rep_min":8,"rep_max":12},{"slug":"breites-rudern","sets":3,"rep_min":8,"rep_max":12},{"slug":"schulterdruecken-maschine","sets":2,"rep_min":8,"rep_max":12},{"slug":"seitheben-maschine","sets":2,"rep_min":12,"rep_max":15},{"slug":"trizepsdruecken-kabel","sets":2,"rep_min":10,"rep_max":15},{"slug":"incline-curl-hinterm-koerper","sets":2,"rep_min":10,"rep_max":15}]}$seed$::jsonb);

-- Unterkörper
select public.upsert_seed_template($seed${"name":"Unterkörper","sort_order":2,"exercises":[{"slug":"hackenschmidt","sets":3,"rep_min":6,"rep_max":10},{"slug":"beinpresse","sets":2,"rep_min":10,"rep_max":12},{"slug":"beinbeuger","sets":3,"rep_min":8,"rep_max":12},{"slug":"beinstrecker","sets":2,"rep_min":10,"rep_max":15},{"slug":"hyperextensions","sets":2,"rep_min":10,"rep_max":15},{"slug":"wadenheben-stehend","sets":3,"rep_min":10,"rep_max":15},{"slug":"crunch-maschine","sets":3,"rep_min":10,"rep_max":15}]}$seed$::jsonb);

-- Oberkörper B
select public.upsert_seed_template($seed${"name":"Oberkörper B","sort_order":3,"exercises":[{"slug":"schraegbankdruecken-maschine","sets":2,"rep_min":8,"rep_max":12},{"slug":"enges-rudern","sets":3,"rep_min":8,"rep_max":12},{"slug":"neutraler-latzug","sets":2,"rep_min":8,"rep_max":12},{"slug":"butterfly","sets":2,"rep_min":10,"rep_max":15},{"slug":"reverse-butterfly","sets":2,"rep_min":12,"rep_max":15},{"slug":"seitheben-maschine","sets":2,"rep_min":12,"rep_max":15},{"slug":"hammercurl-kabel","sets":2,"rep_min":10,"rep_max":15},{"slug":"ueberkopf-trizeps-extension","sets":2,"rep_min":10,"rep_max":12}]}$seed$::jsonb);


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
