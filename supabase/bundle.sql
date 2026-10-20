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
  'machine', 'cable', 'barbell', 'dumbbell', 'bodyweight', 'smith_machine', 'bench', 'other'
);
create type public.exercise_category as enum (
  'chest', 'back', 'shoulders', 'biceps', 'triceps', 'quads', 'hamstrings', 'glutes', 'calves', 'abs', 'forearms'
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
    setup, execution, range_of_motion, breathing, common_mistakes, tips, cable_setup, image_url
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
    nullif(p ->> 'image_url', '')
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
    image_url = coalesce(public.exercises.image_url, excluded.image_url)
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
  ('calves', 'Waden', 'back', 63)
on conflict (id) do update set name_de = excluded.name_de, region = excluded.region, sort_order = excluded.sort_order;

insert into public.grips (id, name_de, description, sort_order) values
  ('neutral_parallel', 'Neutraler Parallelgriff', 'Zwei parallele Griffe, Handflächen zeigen zueinander. Schulterfreundlich, gut für Latzug und Rudern.', 10),
  ('wide_lat_bar', 'Breiter Latzuggriff', 'Lange, leicht gebogene Stange für breiten pronierten Griff. Betont Latissimus und oberen Rücken.', 20),
  ('close_v_grip', 'Enger V-Griff', 'Kompakter V-förmiger Doppelgriff, Handflächen zueinander. Für enges Rudern und engen Latzug.', 30),
  ('rope', 'Seil', 'Seil mit zwei Endknäufen. Erlaubt neutrale Handstellung und das Auseinanderziehen am Ende der Bewegung.', 40),
  ('single_handle', 'Einzelgriff', 'Einzelner D-Griff für einarmige Übungen. Erlaubt freie Handstellung und großen Bewegungsradius.', 50),
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
-- 50 Standardübungen
-- ============================================================

-- Schrägbankdrücken Maschine
select public.upsert_seed_exercise($seed${"slug":"schraegbankdruecken-maschine","name":"Schrägbankdrücken Maschine","category":"chest","equipment":"machine","grip_id":null,"grip_notes":"Pronierte Griffe (Handflächen nach vorne) oder neutrale Griffe, je nach Maschine. Handgelenke gerade halten.","primary_muscles":["upper_chest","chest"],"secondary_muscles":["triceps","front_delts"],"description":"Geführte Druckbewegung in Schrägposition, die vor allem den oberen Anteil der Brust belastet. Gut geeignet als erste Druckübung im Oberkörpertraining.","setup":["Sitz so einstellen, dass die Griffe ungefähr auf Höhe der mittleren bis oberen Brust liegen.","Rücken und Kopf vollständig an das Polster anlehnen.","Füße flach auf den Boden stellen.","Schulterblätter kontrolliert nach hinten und unten ziehen.","Griffe fassen, Handgelenke gerade, Ellenbogen leicht unterhalb der Griffe."],"execution":["Griffe kontrolliert nach vorne-oben drücken.","Ellenbogen am Ende nicht aggressiv durchstrecken.","Spannung in der Brust halten, Schulterblätter bleiben hinten.","Gewicht langsam und kontrolliert zurückführen.","In der Endposition leichte Dehnung der Brust spüren, ohne dass das Gewicht aufsetzt.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Voller Bewegungsradius, soweit die Schultern schmerzfrei bleiben. In der unteren Position die Griffe etwa auf Brusthöhe bringen, oben kurz vor dem Durchstrecken stoppen.","breathing":"Beim Drücken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Schultern rollen beim Drücken nach vorne.","Sitz zu niedrig, Griffe liegen auf Schulterhöhe.","Gewicht wird mit Schwung aus der unteren Position gedrückt.","Ellenbogen werden am Ende hart durchgestreckt.","Rücken löst sich vom Polster."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Erst dann Gewicht erhöhen, wenn alle Sätze im oberen Wiederholungsbereich sauber ausgeführt werden.","Wenn die Schultern unangenehm belastet sind, Sitz etwas höher stellen oder Griffweite ändern."],"cable_setup":null}$seed$::jsonb);

-- Brustpresse
select public.upsert_seed_exercise($seed${"slug":"brustpresse","name":"Brustpresse","category":"chest","equipment":"machine","grip_id":null,"grip_notes":"Pronierte Griffe (Handflächen nach vorne) oder neutrale Griffe, je nach Maschine. Handgelenke gerade halten, Griffe nicht zu fest umklammern.","primary_muscles":["chest"],"secondary_muscles":["triceps","front_delts"],"description":"Geführte horizontale Druckbewegung im Sitzen, die die gesamte Brustmuskulatur belastet. Geeignet als Grundübung für die Brust, wenn eine stabile Führung gewünscht ist.","setup":["Sitz so einstellen, dass die Griffe etwa auf Höhe der mittleren Brust liegen.","Rücken und Kopf vollständig an das Polster anlehnen.","Füße flach auf den Boden oder auf die Fußstütze stellen.","Schulterblätter nach hinten und unten ziehen, Brust leicht anheben.","Griffe fassen, Handgelenke gerade, Ellenbogen etwa auf Höhe der Griffe oder leicht darunter."],"execution":["Griffe kontrolliert nach vorne drücken, bis die Arme fast gestreckt sind.","Ellenbogen am Ende nicht hart durchstrecken.","Schulterblätter während der gesamten Bewegung hinten am Polster lassen.","Gewicht langsam zurückführen, Ellenbogen wandern nach hinten.","In der Startposition leichte Dehnung der Brust spüren, Gewicht nicht aufsetzen lassen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer leichten Dehnung der Brust mit den Griffen etwa auf Brusthöhe bis kurz vor die vollständige Armstreckung. Bewegungsradius nur so groß wählen, wie die Schultern schmerzfrei bleiben.","breathing":"Beim Drücken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Schultern rollen beim Drücken nach vorne, Schulterblätter lösen sich vom Polster.","Sitz zu hoch oder zu tief, Griffe liegen nicht auf Brusthöhe.","Ellenbogen werden am Ende hart durchgestreckt.","Gewicht wird mit Schwung aus der hinteren Position gedrückt.","Handgelenke knicken nach hinten ab."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Ellenbogen etwa 45 bis 60 Grad vom Körper abspreizen, um die Schultern zu entlasten.","Falls vorhanden, das Fußpedal nutzen, um die Griffe in die Ausgangsposition zu bringen.","Erst Gewicht erhöhen, wenn alle Sätze sauber ausgeführt werden."],"cable_setup":null}$seed$::jsonb);

-- Pec Deck
select public.upsert_seed_exercise($seed${"slug":"pec-deck","name":"Pec Deck","category":"chest","equipment":"machine","grip_id":null,"grip_notes":"Unterarme liegen an den Polstern an, Hände halten die Griffe locker oder liegen flach auf. Nicht mit den Händen drücken, die Kraft kommt aus den Unterarmen und Ellenbogen.","primary_muscles":["chest"],"secondary_muscles":["front_delts"],"description":"Geführte Adduktionsbewegung an der Maschine mit Armpolstern, bei der die Brust ohne Belastung der Handgelenke isoliert wird. Geeignet als Isolationsübung nach den Druckübungen.","setup":["Sitz so einstellen, dass die Polster etwa auf Höhe der mittleren Brust liegen und die Oberarme waagerecht sind.","Rücken und Kopf an das Polster anlehnen, Füße flach auf den Boden stellen.","Unterarme an die Polster legen, Ellenbogen etwa 90 Grad gebeugt.","Schulterblätter nach hinten und unten ziehen, Brust leicht anheben.","Startposition so wählen, dass eine leichte Dehnung in der Brust spürbar ist."],"execution":["Polster über die Ellenbogen kontrolliert vor dem Körper zusammenführen.","Vorstellen, die Ellenbogen zueinander zu bringen statt die Hände.","In der Endposition kurz halten und die Brust bewusst anspannen.","Polster langsam zurückführen, bis die Oberarme etwa in der Schulterlinie sind.","Schulterblätter bleiben während der gesamten Bewegung hinten.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer leichten Dehnung mit den Oberarmen etwa in der Schulterlinie bis zum Zusammenführen der Polster vor der Brust. Nicht weiter nach hinten öffnen, als die Schultern schmerzfrei zulassen.","breathing":"Beim Zusammenführen ausatmen, beim Öffnen einatmen.","common_mistakes":["Schultern rollen nach vorne, Schulterblätter lösen sich vom Polster.","Bewegung wird aus den Händen statt aus den Ellenbogen geführt.","Polster werden zu weit nach hinten geöffnet, Schulter wird überdehnt.","Gewicht fällt in der exzentrischen Phase unkontrolliert zurück.","Sitz zu niedrig, Ellenbogen liegen deutlich über der Schulterlinie."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang ausführen.","In der Endposition eine Sekunde halten, um die Kontraktion zu betonen.","Leichtes bis mittleres Gewicht wählen, der Fokus liegt auf der Muskelspannung."],"cable_setup":null}$seed$::jsonb);

-- Butterfly
select public.upsert_seed_exercise($seed${"slug":"butterfly","name":"Butterfly","category":"chest","equipment":"machine","grip_id":null,"grip_notes":"Handgriffe neutral oder leicht proniert fassen, je nach Maschine. Arme fast gestreckt mit leichter Ellenbogenbeuge, Handgelenke gerade.","primary_muscles":["chest"],"secondary_muscles":["front_delts","biceps"],"description":"Geführte Fly-Bewegung an der Maschine mit Handgriffen und fast gestreckten Armen, die die Brust über einen großen Bewegungsradius dehnt und kontrahiert. Geeignet als Isolationsübung für die Brust.","setup":["Sitz so einstellen, dass die Griffe etwa auf Höhe der mittleren Brust bis Schulter liegen.","Rücken und Kopf an das Polster anlehnen, Füße flach auf den Boden stellen.","Griffe fassen, Arme fast gestreckt mit leichter Beuge im Ellenbogen.","Schulterblätter nach hinten und unten ziehen, Brust leicht anheben.","Startposition so wählen, dass eine leichte Dehnung der Brust spürbar ist."],"execution":["Griffe in einem weiten Bogen vor der Brust zusammenführen.","Ellenbogenwinkel während der gesamten Bewegung konstant halten.","In der Endposition kurz halten und die Brust anspannen.","Griffe langsam und kontrolliert zurückführen, bis die Hände etwa in der Schulterlinie sind.","Schulterblätter bleiben hinten am Polster.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer leichten Dehnung mit den Händen etwa in der Schulterlinie bis zum Zusammenführen der Griffe vor der Brust. Die Öffnung nicht erzwingen, Bewegungsradius an die Schulterbeweglichkeit anpassen.","breathing":"Beim Zusammenführen ausatmen, beim Öffnen einatmen.","common_mistakes":["Ellenbogen werden während der Bewegung stark gebeugt, die Übung wird zur Druckbewegung.","Griffe werden zu weit nach hinten geöffnet, Schulter wird überdehnt.","Schultern rollen beim Zusammenführen nach vorne.","Gewicht wird mit Schwung aus der Dehnposition geführt.","Rücken löst sich vom Polster, um mehr Gewicht zu bewegen."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Leichtes bis mittleres Gewicht wählen, der Fokus liegt auf Dehnung und Kontraktion.","Bei Beschwerden im Ellenbogen oder Bizeps auf die Pec-Deck-Variante mit Armpolstern wechseln."],"cable_setup":null}$seed$::jsonb);

-- Kabel-Flys
select public.upsert_seed_exercise($seed${"slug":"kabel-flys","name":"Kabel-Flys","category":"chest","equipment":"cable","grip_id":"single_handle","grip_notes":"Einzelgriffe in beiden Händen, neutraler Griff (Handflächen zeigen zueinander oder leicht nach vorne). Alternativ ohne Griff direkt am Kabelende, falls die Griffe stören.","primary_muscles":["chest"],"secondary_muscles":["front_delts"],"description":"Fly-Bewegung am Doppelkabelzug mit Rollen auf Schulter- bis Brusthöhe, die die Brust horizontal mit konstanter Spannung belastet. Geeignet als Isolationsübung mit gleichmäßigem Widerstand über den gesamten Bewegungsradius.","setup":["Beide Rollen des Doppelkabelzugs auf Schulter- bis Brusthöhe einstellen und Einzelgriffe einhängen.","Einen Griff nach dem anderen fassen und einen Schritt nach vorne in die Mitte gehen.","Schrittstellung einnehmen, Rumpf anspannen, Oberkörper leicht nach vorne geneigt.","Arme seitlich mit leichter Ellenbogenbeuge halten, Hände etwa in der Schulterlinie.","Schulterblätter nach hinten und unten ziehen, Brust leicht anheben."],"execution":["Griffe in einem weiten Bogen vor der Brust zusammenführen.","Ellenbogenwinkel während der gesamten Bewegung konstant halten.","In der Endposition die Hände vor der Brust zusammenbringen und die Brust anspannen.","Griffe langsam und kontrolliert zurückführen, bis die Hände wieder etwa in der Schulterlinie sind.","Oberkörper und Rumpf bleiben während der Bewegung stabil.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer leichten Dehnung mit den Händen etwa in der Schulterlinie bis zum Zusammenführen der Hände vor der Brust. Die Dehnposition nicht erzwingen.","breathing":"Beim Zusammenführen ausatmen, beim Öffnen einatmen.","common_mistakes":["Ellenbogen werden stark gebeugt, die Bewegung wird zum Drücken.","Oberkörper schwingt mit und erzeugt Schwung aus dem Rumpf.","Schultern rollen beim Zusammenführen nach vorne.","Hände werden zu weit nach hinten geführt, Schulter wird überdehnt.","Gewicht zieht die Arme in der exzentrischen Phase unkontrolliert zurück."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Leichtes bis mittleres Gewicht wählen, da die Hebelverhältnisse ungünstig sind.","Hände in der Endposition leicht überkreuzen, um die Kontraktion zu verlängern.","Schrittstellung von Satz zu Satz wechseln, um einseitige Belastung zu vermeiden."],"cable_setup":{"cable":"Doppelkabelzug (Cable Crossover)","height":"Rollen auf Schulter- bis Brusthöhe","grip_width":"Einzelgriffe, neutraler Griff, Hände starten etwa in der Schulterlinie","body_position":"Stehend in der Mitte zwischen den Säulen, Oberkörper leicht nach vorne geneigt, Rumpf angespannt, Schulterblätter hinten und unten","foot_position":"Schrittstellung, vorderer Fuß flach, hinterer Fuß auf dem Ballen, Knie leicht gebeugt","movement_direction":"Horizontal in einem Bogen von außen nach vorne-innen vor die Brust","elbow_position":"Leicht gebeugt, Winkel bleibt über die gesamte Bewegung konstant","end_position":"Hände vor der Brust zusammengeführt, Brust angespannt, Schultern bleiben hinten","return":"Langsam und kontrolliert, bis die Hände etwa in der Schulterlinie sind und eine leichte Dehnung spürbar ist"}}$seed$::jsonb);

-- Kabel-Flys von unten
select public.upsert_seed_exercise($seed${"slug":"kabel-flys-von-unten","name":"Kabel-Flys von unten","category":"chest","equipment":"cable","grip_id":"single_handle","grip_notes":"Einzelgriffe in beiden Händen, neutraler Griff (Handflächen zeigen zueinander bzw. nach oben). Alternativ ohne Griff direkt am Kabelende.","primary_muscles":["upper_chest","chest"],"secondary_muscles":["front_delts"],"description":"Fly-Bewegung am Doppelkabelzug mit Rollen in der unteren Position, bei der die Arme von unten nach oben-vorne zusammengeführt werden. Belastet vor allem den oberen Anteil der Brust.","setup":["Beide Rollen des Doppelkabelzugs in die unterste Position bringen und Einzelgriffe einhängen.","Griffe fassen und einen Schritt nach vorne in die Mitte gehen.","Schrittstellung einnehmen, Rumpf anspannen, Oberkörper aufrecht oder leicht nach vorne geneigt.","Arme seitlich-unten mit leichter Ellenbogenbeuge halten, Handflächen zeigen nach vorne-oben.","Schulterblätter nach hinten und unten ziehen, Brust leicht anheben."],"execution":["Griffe in einem Bogen von unten nach oben-vorne zusammenführen.","Ellenbogenwinkel während der gesamten Bewegung konstant halten.","In der Endposition die Hände etwa auf Höhe der oberen Brust bis Kinn zusammenbringen.","Obere Brust kurz bewusst anspannen.","Griffe langsam und kontrolliert nach unten-außen zurückführen.","Oberkörper bleibt stabil, kein Mitschwingen aus dem Rumpf.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von den seitlich-unten gehaltenen Armen bis die Hände vor der oberen Brust zusammenkommen. Nicht über die Schulterhöhe hinaus führen, um die Schultern nicht unnötig zu belasten.","breathing":"Beim Zusammenführen nach oben ausatmen, beim Zurückführen einatmen.","common_mistakes":["Schultern ziehen beim Anheben nach oben zum Ohr.","Bewegung wird zum Frontheben, Ellenbogen stark gebeugt und Arme vor dem Körper angehoben.","Oberkörper lehnt sich nach hinten, um das Gewicht zu bewegen.","Hände werden in der Endposition deutlich über die Schulter geführt.","Gewicht zieht die Arme unkontrolliert nach unten zurück."],"tips":["Leichtes Gewicht wählen und in der Endposition eine Sekunde halten.","Vorstellen, die Oberarme zueinander zu führen, nicht die Hände nach oben zu heben.","Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren."],"cable_setup":{"cable":"Doppelkabelzug (Cable Crossover)","height":"Rollen ganz unten","grip_width":"Einzelgriffe, neutraler Griff, Hände starten seitlich-unten neben den Hüften","body_position":"Stehend in der Mitte zwischen den Säulen, Oberkörper aufrecht bis leicht nach vorne geneigt, Rumpf angespannt, Schulterblätter hinten und unten","foot_position":"Schrittstellung, Knie leicht gebeugt, Gewicht gleichmäßig verteilt","movement_direction":"Von unten-außen in einem Bogen nach oben-vorne vor die obere Brust","elbow_position":"Leicht gebeugt, Winkel bleibt konstant, Ellenbogen zeigen leicht nach außen-unten","end_position":"Hände vor der oberen Brust bis Kinnhöhe zusammengeführt, obere Brust angespannt, Schultern unten","return":"Langsam und kontrolliert nach unten-außen bis zur Startposition neben den Hüften"}}$seed$::jsonb);

-- Kabel-Flys von oben
select public.upsert_seed_exercise($seed${"slug":"kabel-flys-von-oben","name":"Kabel-Flys von oben","category":"chest","equipment":"cable","grip_id":"single_handle","grip_notes":"Einzelgriffe in beiden Händen, neutraler Griff (Handflächen zeigen zueinander bzw. nach unten-innen). Alternativ ohne Griff direkt am Kabelende.","primary_muscles":["chest"],"secondary_muscles":["front_delts","triceps"],"description":"Fly-Bewegung am Doppelkabelzug mit Rollen in der oberen Position, bei der die Arme von oben nach unten-vorne zusammengeführt werden. Belastet vor allem den unteren Anteil der Brust.","setup":["Beide Rollen des Doppelkabelzugs in die oberste Position bringen und Einzelgriffe einhängen.","Griffe fassen und einen Schritt nach vorne in die Mitte gehen.","Schrittstellung einnehmen, Rumpf anspannen, Oberkörper leicht nach vorne geneigt.","Arme seitlich-oben mit leichter Ellenbogenbeuge halten, Hände etwas über Schulterhöhe.","Schulterblätter nach hinten und unten ziehen, Brust leicht anheben."],"execution":["Griffe in einem Bogen von oben nach unten-vorne zusammenführen.","Ellenbogenwinkel während der gesamten Bewegung konstant halten.","In der Endposition die Hände etwa auf Höhe der unteren Brust bis Bauchnabel zusammenbringen.","Untere Brust kurz bewusst anspannen.","Griffe langsam und kontrolliert nach oben-außen zurückführen.","Oberkörper bleibt in seiner Neigung, kein Mitschwingen aus dem Rumpf.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von den seitlich-oben gehaltenen Armen mit leichter Dehnung bis die Hände vor der unteren Brust zusammenkommen. Die Dehnposition oben nicht erzwingen.","breathing":"Beim Zusammenführen nach unten ausatmen, beim Zurückführen einatmen.","common_mistakes":["Oberkörper wird stark nach vorne geklappt, die Bewegung kommt aus dem Rumpf.","Ellenbogen werden stark gebeugt, die Übung wird zum Drücken nach unten.","Schultern rollen beim Zusammenführen nach vorne.","Arme werden in der Startposition zu weit nach hinten geführt.","Gewicht zieht die Arme unkontrolliert nach oben zurück."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Hände in der Endposition leicht überkreuzen, um die Kontraktion zu verlängern.","Leichtes bis mittleres Gewicht wählen, der Fokus liegt auf der Muskelspannung.","Schrittstellung von Satz zu Satz wechseln."],"cable_setup":{"cable":"Doppelkabelzug (Cable Crossover)","height":"Rollen ganz oben","grip_width":"Einzelgriffe, neutraler Griff, Hände starten seitlich etwas über Schulterhöhe","body_position":"Stehend in der Mitte zwischen den Säulen, Oberkörper etwa 15 bis 30 Grad nach vorne geneigt, Rumpf angespannt, Schulterblätter hinten und unten","foot_position":"Schrittstellung, vorderer Fuß flach, hinterer Fuß auf dem Ballen, Knie leicht gebeugt","movement_direction":"Von oben-außen in einem Bogen nach unten-vorne vor die untere Brust","elbow_position":"Leicht gebeugt, Winkel bleibt konstant, Ellenbogen zeigen nach außen-oben","end_position":"Hände vor der unteren Brust bis Bauchnabelhöhe zusammengeführt, untere Brust angespannt, Schultern bleiben hinten","return":"Langsam und kontrolliert nach oben-außen, bis eine leichte Dehnung in der Brust spürbar ist"}}$seed$::jsonb);

-- Schulterdrücken Maschine
select public.upsert_seed_exercise($seed${"slug":"schulterdruecken-maschine","name":"Schulterdrücken Maschine","category":"shoulders","equipment":"machine","grip_id":null,"grip_notes":"Pronierte Griffe (Handflächen nach vorne) oder neutrale Griffe, je nach Maschine. Neutrale Griffe sind meist schulterfreundlicher. Handgelenke gerade halten.","primary_muscles":["front_delts","side_delts"],"secondary_muscles":["triceps","traps"],"description":"Geführte vertikale Druckbewegung im Sitzen, die vor allem die vordere und seitliche Schulter belastet. Geeignet als Grundübung für die Schulter mit stabiler Führung.","setup":["Sitz so einstellen, dass die Griffe in der Startposition etwa auf Schulterhöhe oder leicht darunter liegen.","Rücken und Kopf an das Polster anlehnen, Füße flach auf den Boden stellen.","Griffe fassen, Handgelenke gerade, Unterarme möglichst senkrecht.","Rumpf anspannen, Rippen nicht nach vorne herausdrücken.","Schultern bewusst nach unten ziehen, nicht zu den Ohren hochziehen."],"execution":["Griffe kontrolliert nach oben drücken.","Ellenbogen am Ende nicht hart durchstrecken.","Schultern während des Drückens unten lassen, nicht hochziehen.","Gewicht langsam zurückführen, bis die Griffe etwa auf Schulterhöhe sind.","Rücken bleibt während der gesamten Bewegung am Polster.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von den Griffen etwa auf Schulterhöhe bis kurz vor die vollständige Armstreckung. Unten nur so tief, wie die Schultern schmerzfrei bleiben.","breathing":"Beim Drücken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Schultern werden beim Drücken zu den Ohren hochgezogen.","Rücken wölbt sich stark ins Hohlkreuz, Rippen werden herausgedrückt.","Sitz zu hoch, Griffe liegen deutlich unter der Schulter.","Ellenbogen werden am Ende hart durchgestreckt.","Gewicht wird mit Schwung aus der unteren Position gedrückt."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Bei Beschwerden in der Schulter neutrale Griffe wählen oder Sitz etwas höher stellen.","Erst Gewicht erhöhen, wenn alle Sätze sauber und ohne Hohlkreuz ausgeführt werden."],"cable_setup":null}$seed$::jsonb);

-- Seitheben Maschine
select public.upsert_seed_exercise($seed${"slug":"seitheben-maschine","name":"Seitheben Maschine","category":"shoulders","equipment":"machine","grip_id":null,"grip_notes":"Polster liegen an den Oberarmen knapp oberhalb der Ellenbogen an. Griffe locker fassen oder Hände nur anlegen, nicht mit den Händen heben.","primary_muscles":["side_delts"],"secondary_muscles":["traps"],"description":"Geführtes Seitheben an der Maschine mit Polstern an den Oberarmen, das die seitliche Schulter isoliert. Geeignet für kontrollierte Isolationsarbeit ohne Ausweichbewegungen des Rumpfes.","setup":["Sitz so einstellen, dass die Drehachse der Maschine etwa auf Höhe der Schultergelenke liegt.","Oberkörper aufrecht an das Polster anlehnen, Füße flach auf den Boden stellen.","Oberarme an die Polster legen, Ellenbogen etwa 90 Grad gebeugt.","Schultern bewusst nach unten ziehen, Brust leicht anheben.","Rumpf anspannen."],"execution":["Oberarme über die Polster seitlich nach oben führen.","Bewegung aus den Ellenbogen führen, nicht aus den Händen.","Bis etwa Schulterhöhe anheben, Schultern bleiben unten.","In der Endposition kurz halten.","Arme langsam und kontrolliert zurückführen.","Gewicht unten nicht aufsetzen lassen, Spannung halten."],"range_of_motion":"Von den Oberarmen neben dem Körper bis etwa Schulterhöhe. Nicht über die Schulterhöhe hinaus heben, da dann vermehrt der Trapezmuskel übernimmt.","breathing":"Beim Anheben ausatmen, beim Absenken einatmen.","common_mistakes":["Schultern werden beim Anheben zu den Ohren hochgezogen.","Oberarme werden über die Schulterhöhe hinaus gehoben.","Sitz zu niedrig oder zu hoch, Drehachse stimmt nicht mit der Schulter überein.","Gewicht fällt in der exzentrischen Phase unkontrolliert zurück.","Oberkörper lehnt sich nach hinten, um das Gewicht zu bewegen."],"tips":["Leichtes bis mittleres Gewicht wählen, der Fokus liegt auf der seitlichen Schulter.","Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","In der Endposition eine Sekunde halten."],"cable_setup":null}$seed$::jsonb);

-- Seitheben Kabel
select public.upsert_seed_exercise($seed${"slug":"seitheben-kabel","name":"Seitheben Kabel","category":"shoulders","equipment":"cable","grip_id":"single_handle","grip_notes":"Einzelgriff in einer Hand, neutraler Griff mit lockerem Daumen. Alternativ ohne Griff direkt am Kabelende oder mit Handschlaufe, um weniger mit der Hand zu arbeiten.","primary_muscles":["side_delts"],"secondary_muscles":["traps","front_delts"],"description":"Einarmiges Seitheben am Kabelzug mit der Rolle unten, das die seitliche Schulter mit konstanter Spannung belastet. Geeignet als Isolationsübung mit gleichmäßigem Widerstand auch in der unteren Position.","setup":["Rolle ganz unten oder leicht über dem Boden einstellen und Einzelgriff einhängen.","Seitlich zur Säule stellen, die arbeitende Hand ist von der Säule abgewandt.","Griff fassen, das Kabel läuft vor oder hinter dem Körper zur Säule.","Freie Hand an der Säule abstützen, Rumpf anspannen, Oberkörper aufrecht.","Arm mit leichter Ellenbogenbeuge neben dem Körper halten, Schulter bewusst nach unten ziehen."],"execution":["Arm seitlich nach oben führen, der Ellenbogen führt die Bewegung.","Bis etwa Schulterhöhe anheben, Hand und Ellenbogen etwa auf gleicher Höhe.","Schulter bleibt während der gesamten Bewegung unten.","In der Endposition kurz halten.","Arm langsam und kontrolliert zurückführen, bis er wieder neben dem Körper ist.","Spannung unten halten, Gewicht nicht aufsetzen lassen.","Nach dem Satz die Seite wechseln."],"range_of_motion":"Vom Arm neben bzw. leicht vor dem Körper bis etwa Schulterhöhe. Nicht über die Schulterhöhe hinaus heben.","breathing":"Beim Anheben ausatmen, beim Absenken einatmen.","common_mistakes":["Schulter wird beim Anheben zum Ohr hochgezogen.","Oberkörper neigt sich zur Seite oder schwingt mit.","Arm wird über die Schulterhöhe hinaus gehoben.","Hand liegt in der Endposition deutlich über dem Ellenbogen.","Gewicht zieht den Arm unkontrolliert zurück."],"tips":["Leichtes Gewicht wählen, die Übung reagiert empfindlich auf Schwung.","Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Vorstellen, den Ellenbogen zur Seite wegzuschieben, nicht die Hand anzuheben.","Kabel hinter dem Körper führen, wenn die seitliche Schulter stärker isoliert werden soll."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einarmig","height":"Rolle ganz unten oder leicht über dem Boden","grip_width":"Einzelgriff in einer Hand, neutraler Griff, Daumen locker","body_position":"Seitlich zur Säule stehend, aufrecht, freie Hand an der Säule abgestützt, Rumpf angespannt, Schulter unten","foot_position":"Hüftbreit oder leichte Schrittstellung, Knie leicht gebeugt","movement_direction":"Seitlich nach oben in einem Bogen bis etwa Schulterhöhe","elbow_position":"Leicht gebeugt, Winkel bleibt konstant, Ellenbogen führt die Bewegung und bleibt auf Höhe der Hand oder leicht darüber","end_position":"Oberarm etwa waagerecht auf Schulterhöhe, Schulter unten, kurz halten","return":"Langsam und kontrolliert zurück neben den Körper, Spannung am Kabel bleibt erhalten"}}$seed$::jsonb);

-- Reverse Butterfly
select public.upsert_seed_exercise($seed${"slug":"reverse-butterfly","name":"Reverse Butterfly","category":"shoulders","equipment":"machine","grip_id":null,"grip_notes":"Neutrale Griffe (Handflächen zeigen zueinander) oder pronierte Griffe, je nach Maschine. Griffe locker fassen, Handgelenke gerade, die Bewegung kommt aus den Ellenbogen und Schulterblättern.","primary_muscles":["rear_delts"],"secondary_muscles":["upper_back","traps","mid_back"],"description":"Geführte Reverse-Fly-Bewegung an der umgekehrten Pec-Deck-Maschine, die die hintere Schulter und den oberen Rücken belastet. Geeignet als Isolationsübung für die hintere Schulter und als Ausgleich zu Druckübungen.","setup":["Griffe der Maschine in die vordere Position stellen, sodass die Arme vor dem Körper starten.","Sitz so einstellen, dass die Griffe etwa auf Schulterhöhe liegen.","Mit der Brust zum Polster setzen, Brustbein am Polster anlehnen, Füße flach auf den Boden stellen.","Griffe fassen, Arme fast gestreckt mit leichter Ellenbogenbeuge.","Schultern nach unten ziehen, Rumpf anspannen."],"execution":["Griffe in einem weiten Bogen nach hinten-außen führen.","Ellenbogenwinkel während der gesamten Bewegung konstant halten.","Bewegung aus der hinteren Schulter und den Schulterblättern führen, nicht aus den Händen.","In der Endposition kurz halten, Hände etwa in der Schulterlinie oder leicht dahinter.","Griffe langsam und kontrolliert nach vorne zurückführen.","Brust bleibt am Polster, Gewicht vorne nicht aufsetzen lassen."],"range_of_motion":"Von den Armen vor dem Körper bis die Hände etwa in der Schulterlinie oder leicht dahinter sind. Nicht weiter nach hinten erzwingen.","breathing":"Beim Öffnen nach hinten ausatmen, beim Zurückführen einatmen.","common_mistakes":["Schultern werden zu den Ohren hochgezogen.","Ellenbogen werden stark gebeugt, die Übung wird zum Rudern.","Brust löst sich vom Polster, Oberkörper schwingt mit.","Gewicht wird mit Schwung nach hinten gerissen.","Gewicht fällt in der exzentrischen Phase unkontrolliert zurück."],"tips":["Leichtes bis mittleres Gewicht wählen, die hintere Schulter ist ein kleiner Muskel.","Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Vorstellen, die Ellenbogen nach hinten-außen zu ziehen.","Neutraler Griff legt den Fokus stärker auf die hintere Schulter, pronierter Griff mehr auf den oberen Rücken."],"cable_setup":null}$seed$::jsonb);

-- Kabel Reverse Fly
select public.upsert_seed_exercise($seed${"slug":"kabel-reverse-fly","name":"Kabel Reverse Fly","category":"shoulders","equipment":"cable","grip_id":"single_handle","grip_notes":"Einzelgriffe oder ohne Griff direkt am Kabelende bzw. an der Kugel fassen. Kabel überkreuz greifen: die rechte Hand hält das linke Kabel, die linke Hand das rechte Kabel.","primary_muscles":["rear_delts"],"secondary_muscles":["upper_back","traps"],"description":"Reverse-Fly-Bewegung am Doppelkabelzug mit Rollen auf Schulterhöhe und überkreuz gegriffenen Kabeln. Belastet die hintere Schulter mit konstanter Spannung und eignet sich als Isolationsübung für den hinteren Schulteranteil.","setup":["Beide Rollen des Doppelkabelzugs auf Schulterhöhe einstellen, Einzelgriffe einhängen oder Kabelenden direkt nutzen.","In die Mitte zwischen die Säulen stellen und die Kabel überkreuz fassen.","Einen Schritt zurückgehen, bis die Kabel unter Spannung sind.","Hüftbreiter Stand oder leichte Schrittstellung, Rumpf anspannen, Oberkörper aufrecht.","Arme vor der Brust fast gestreckt mit leichter Ellenbogenbeuge halten, Schultern nach unten ziehen."],"execution":["Arme in einem weiten Bogen nach außen-hinten führen.","Ellenbogenwinkel während der gesamten Bewegung konstant halten.","Bewegung aus der hinteren Schulter führen, Schulterblätter am Ende leicht zusammenziehen.","In der Endposition kurz halten, Hände etwa in der Schulterlinie.","Arme langsam und kontrolliert nach vorne zurückführen, bis sich die Hände wieder vor der Brust überkreuzen.","Oberkörper bleibt stabil, kein Mitschwingen."],"range_of_motion":"Von den vor der Brust überkreuzten Armen bis die Hände etwa in der Schulterlinie sind. Nicht weiter nach hinten erzwingen.","breathing":"Beim Öffnen nach außen ausatmen, beim Zurückführen einatmen.","common_mistakes":["Schultern werden zu den Ohren hochgezogen.","Ellenbogen werden stark gebeugt, die Übung wird zum Rudern.","Oberkörper lehnt sich nach hinten, um das Gewicht zu bewegen.","Gewicht zieht die Arme in der exzentrischen Phase unkontrolliert zurück.","Zu viel Gewicht, der Bewegungsradius wird deutlich kleiner."],"tips":["Leichtes Gewicht wählen und auf saubere Ausführung achten.","Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Vorstellen, die Hände an eine Wand hinter dem Körper zu führen."],"cable_setup":{"cable":"Doppelkabelzug (Cable Crossover)","height":"Rollen auf Schulterhöhe","grip_width":"Kabel überkreuz gegriffen, Einzelgriffe oder direkt am Kabelende, neutraler Griff","body_position":"Stehend in der Mitte zwischen den Säulen, aufrecht, Rumpf angespannt, Schultern unten, Arme vor der Brust","foot_position":"Hüftbreit oder leichte Schrittstellung, Knie leicht gebeugt","movement_direction":"Horizontal in einem Bogen von vorne nach außen-hinten","elbow_position":"Leicht gebeugt, Winkel bleibt konstant, Ellenbogen etwa auf Schulterhöhe","end_position":"Arme seitlich etwa in der Schulterlinie, Schulterblätter leicht zusammengezogen, kurz halten","return":"Langsam und kontrolliert nach vorne, bis sich die Hände vor der Brust wieder überkreuzen, Spannung bleibt erhalten"}}$seed$::jsonb);

-- Face Pull
select public.upsert_seed_exercise($seed${"slug":"face-pull","name":"Face Pull","category":"shoulders","equipment":"cable","grip_id":"rope","grip_notes":"Seilgriff mit neutralem Griff, Daumen zeigen zum Körper. Alternativ Handflächen nach unten (proniert) fassen, dann liegt der Fokus stärker auf dem oberen Rücken.","primary_muscles":["rear_delts"],"secondary_muscles":["upper_back","traps","side_delts"],"description":"Zugübung am Kabelzug mit Seilgriff, bei der das Seil auf Gesichtshöhe zum Kopf gezogen wird. Belastet die hintere Schulter und den oberen Rücken und eignet sich als Ausgleichsübung zu Druckbewegungen.","setup":["Rolle auf Gesichts- bis Stirnhöhe einstellen und Seilgriff einhängen.","Seil mit neutralem Griff fassen, Daumen zeigen zum Körper.","Ein bis zwei Schritte zurückgehen, bis das Kabel unter Spannung ist.","Hüftbreiter Stand oder Schrittstellung, Rumpf anspannen, Oberkörper aufrecht.","Arme gestreckt nach vorne, Schultern bewusst nach unten ziehen."],"execution":["Seil in Richtung Gesicht ziehen, Ellenbogen führen die Bewegung nach hinten-außen.","Seilenden auseinanderziehen, Hände kommen neben die Ohren.","Ellenbogen hoch auf Schulterhöhe und außen halten.","In der Endposition Schulterblätter zusammenziehen und kurz halten.","Seil langsam und kontrolliert zurückführen, Arme strecken.","Schultern am Ende leicht nach vorne kommen lassen, ohne den Oberkörper mitzuziehen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von vollständig gestreckten Armen bis die Hände neben den Ohren und die Ellenbogen etwa in der Schulterlinie sind. Nicht über die Schulterlinie hinaus ziehen.","breathing":"Beim Ziehen ausatmen, beim Zurückführen einatmen.","common_mistakes":["Ellenbogen sinken nach unten, die Übung wird zum Rudern.","Oberkörper lehnt sich nach hinten, Bewegung kommt aus dem Rumpf.","Schultern werden zu den Ohren hochgezogen.","Seil wird nur zum Gesicht gezogen, ohne die Enden auseinanderzuziehen.","Gewicht zieht die Arme unkontrolliert zurück."],"tips":["Leichtes bis mittleres Gewicht wählen und auf hohe Ellenbogen achten.","Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Vorstellen, in der Endposition eine Doppelbizeps-Pose einzunehmen.","Bei Platzmangel auch kniend oder im Halbkniestand ausführbar."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, eine Seite","height":"Rolle auf Gesichts- bis Stirnhöhe","grip_width":"Seilgriff, neutraler Griff, Daumen zum Körper, Hände am Ende neben den Ohren","body_position":"Stehend mit ein bis zwei Schritten Abstand zur Säule, aufrecht, Rumpf angespannt, Schultern unten","foot_position":"Hüftbreit oder Schrittstellung, Knie leicht gebeugt","movement_direction":"Horizontal von vorne in Richtung Gesicht, Seilenden werden dabei nach außen gezogen","elbow_position":"Ellenbogen hoch etwa auf Schulterhöhe, zeigen nach außen und wandern nach hinten","end_position":"Hände neben den Ohren, Ellenbogen in der Schulterlinie, Schulterblätter zusammengezogen","return":"Langsam und kontrolliert bis zur vollen Armstreckung, Spannung am Kabel bleibt erhalten"}}$seed$::jsonb);

-- Neutraler Latzug
select public.upsert_seed_exercise($seed${"slug":"neutraler-latzug","name":"Neutraler Latzug","category":"back","equipment":"cable","grip_id":"neutral_parallel","grip_notes":"Neutraler Parallelgriff (Handflächen zeigen zueinander), etwa schulterbreit. Alternativ: breiter Latzuggriff für mehr Betonung der äußeren Lat-Anteile.","primary_muscles":["lats"],"secondary_muscles":["biceps","upper_back","forearms","rear_delts"],"description":"Vertikale Zugübung am Latzug mit neutralem Griff, die den Latissimus über einen großen Bewegungsradius belastet. Schulterfreundliche Variante des Latzugs.","setup":["Oberschenkelpolster so einstellen, dass die Beine fest fixiert sind.","Neutralen Parallelgriff am oberen Kabel einhängen.","Griff fassen, hinsetzen und Oberschenkel unter das Polster bringen.","Oberkörper aufrecht, leicht nach hinten geneigt, Brust leicht angehoben.","Arme gestreckt, Schultern bewusst nach unten ziehen, bevor die Bewegung beginnt."],"execution":["Griff in Richtung obere Brust ziehen, Ellenbogen führen die Bewegung nach unten.","Schulterblätter nach unten und zusammen ziehen.","In der Endposition kurz halten, Griff befindet sich etwa auf Höhe des Kinns bis der oberen Brust.","Gewicht langsam zurückführen, Arme kontrolliert strecken.","Schultern am oberen Ende leicht nach oben kommen lassen, um den Lat zu dehnen.","Ohne Schwung die nächste Wiederholung beginnen."],"range_of_motion":"Von vollständig gestreckten Armen bis der Griff etwa auf Höhe des Kinns bzw. der oberen Brust ist. Nicht bis zum Bauch ziehen.","breathing":"Beim Ziehen ausatmen, beim Strecken der Arme einatmen.","common_mistakes":["Oberkörper wird stark nach hinten gelehnt und die Bewegung mit Schwung ausgeführt.","Schultern bleiben während des Zugs oben am Ohr.","Griff wird mit den Armen statt mit den Ellenbogen geführt.","Gewicht fällt nach oben zurück, keine Kontrolle in der exzentrischen Phase.","Ellenbogen weichen weit nach hinten aus, sodass der Rücken rund wird."],"tips":["Daumen auf die Griffe legen statt zu umschließen, um weniger mit den Unterarmen zu arbeiten.","Vorstellen, die Ellenbogen in die Hosentaschen zu ziehen.","Die exzentrische Phase bewusst zwei bis drei Sekunden lang ausführen."],"cable_setup":{"cable":"Kabelturm mit Latzug-Station oder integrierter Latzug","height":"Rolle ganz oben","grip_width":"Schulterbreit, neutral (Handflächen zueinander)","body_position":"Aufrecht sitzend, leichte Rücklage von etwa 10 bis 20 Grad, Brust angehoben, Rumpf stabil","foot_position":"Füße flach auf dem Boden, Oberschenkel unter dem Polster fixiert","movement_direction":"Vertikal von oben nach unten in Richtung obere Brust","elbow_position":"Ellenbogen zeigen nach unten und leicht nach vorne, bleiben nah am Körper","end_position":"Griff auf Höhe des Kinns bis der oberen Brust, Schulterblätter nach unten und zusammengezogen","return":"Langsam und kontrolliert bis zur vollen Armstreckung, Schultern am Ende leicht nach oben kommen lassen"}}$seed$::jsonb);

-- Breiter Latzug
select public.upsert_seed_exercise($seed${"slug":"breiter-latzug","name":"Breiter Latzug","category":"back","equipment":"cable","grip_id":"wide_lat_bar","grip_notes":"Breite Latzugstange, pronierter Griff (Handflächen nach vorne), Hände deutlich weiter als schulterbreit an den gebogenen Enden der Stange. Alternativ: etwas enger greifen, wenn die Schultern in der gestreckten Position unangenehm belastet sind.","primary_muscles":["lats"],"secondary_muscles":["upper_back","biceps","forearms","rear_delts"],"description":"Vertikale Zugübung am Latzug mit breitem, proniertem Griff, die den Latissimus und den oberen Rücken belastet. Klassische Übung für die Rückenbreite.","setup":["Breite Latzugstange am oberen Kabel einhängen.","Oberschenkelpolster so einstellen, dass die Beine fest fixiert sind.","Stange deutlich weiter als schulterbreit mit proniertem Griff fassen, hinsetzen und Oberschenkel unter das Polster bringen.","Oberkörper aufrecht mit leichter Rücklage, Brust angehoben, Blick nach vorne.","Arme gestreckt, Schultern bewusst nach unten ziehen, bevor die Bewegung beginnt."],"execution":["Stange in Richtung obere Brust ziehen, Ellenbogen führen die Bewegung nach unten und leicht nach außen.","Schulterblätter nach unten und zusammen ziehen, Brust bleibt angehoben.","In der Endposition kurz halten, Stange befindet sich etwa auf Höhe der oberen Brust.","Gewicht langsam zurückführen, Arme kontrolliert strecken.","Am oberen Ende die Schultern leicht nach oben kommen lassen, um den Lat zu dehnen.","Ohne Schwung die nächste Wiederholung beginnen."],"range_of_motion":"Von vollständig gestreckten Armen bis die Stange etwa auf Höhe der oberen Brust ist. Nicht bis zum Bauch ziehen und nicht hinter den Nacken.","breathing":"Beim Ziehen ausatmen, beim Strecken der Arme einatmen.","common_mistakes":["Oberkörper wird stark nach hinten gelehnt und die Stange mit Schwung gezogen.","Stange wird hinter den Nacken gezogen.","Schultern bleiben während des Zugs oben am Ohr.","Bewegung kommt vor allem aus den Armen statt aus den Ellenbogen und Schulterblättern.","Gewicht fällt nach oben zurück, keine Kontrolle in der exzentrischen Phase."],"tips":["Die Ellenbogen bewusst nach unten in Richtung Hüfte führen, nicht nach hinten.","Die exzentrische Phase zwei bis drei Sekunden lang kontrollieren.","Wenn die Schultern bei sehr breitem Griff unangenehm belastet sind, etwas enger greifen oder auf den neutralen Latzug wechseln."],"cable_setup":{"cable":"Kabelturm mit Latzug-Station oder integrierter Latzug","height":"Rolle ganz oben","grip_width":"Deutlich weiter als schulterbreit, proniert (Handflächen nach vorne)","body_position":"Aufrecht sitzend, leichte Rücklage von etwa 10 bis 20 Grad, Brust angehoben, Rumpf stabil","foot_position":"Füße flach auf dem Boden, Oberschenkel unter dem Polster fixiert","movement_direction":"Vertikal von oben nach unten in Richtung obere Brust","elbow_position":"Ellenbogen zeigen nach unten und leicht nach außen, bleiben etwa in der Ebene des Oberkörpers","end_position":"Stange auf Höhe der oberen Brust, Schulterblätter nach unten und zusammengezogen","return":"Langsam und kontrolliert bis zur vollen Armstreckung, Schultern am Ende leicht nach oben kommen lassen"}}$seed$::jsonb);

-- Enges Rudern
select public.upsert_seed_exercise($seed${"slug":"enges-rudern","name":"Enges Rudern","category":"back","equipment":"cable","grip_id":"close_v_grip","grip_notes":"Enger V-Griff, neutral (Handflächen zeigen zueinander). Alternativ: neutraler Parallelgriff in Schulterbreite, wenn der enge Griff die Handgelenke unangenehm belastet.","primary_muscles":["lats","mid_back"],"secondary_muscles":["biceps","forearms","rear_delts"],"description":"Horizontale Zugübung am sitzenden Kabelzug mit engem V-Griff, die den Latissimus und den mittleren Rücken belastet. Geeignet als Grundübung für die Rückendicke.","setup":["V-Griff am unteren Kabel der Ruderstation einhängen.","Hinsetzen, Füße auf die Fußplatten stellen, Knie leicht gebeugt.","Griff mit beiden Händen fassen und den Oberkörper aufrichten.","Brust angehoben, Rücken gerade, Schultern nach unten ziehen.","Arme gestreckt, Gewicht leicht abheben, sodass von Beginn an Spannung auf dem Kabel ist."],"execution":["Griff in Richtung unterer Bauch bzw. Nabel ziehen, Ellenbogen führen die Bewegung nah am Körper nach hinten.","Schulterblätter zusammen ziehen, Oberkörper bleibt aufrecht.","In der Endposition kurz halten, Griff berührt beinahe den Bauch.","Gewicht langsam zurückführen, Arme kontrolliert strecken.","Am Ende die Schulterblätter leicht nach vorne kommen lassen, um den Rücken zu dehnen.","Ohne Schwung aus dem Oberkörper die nächste Wiederholung beginnen."],"range_of_motion":"Von gestreckten Armen mit leicht nach vorne gezogenen Schulterblättern bis der Griff den unteren Bauch fast berührt. Der Oberkörper bewegt sich dabei nur wenige Grad.","breathing":"Beim Ziehen ausatmen, beim Strecken der Arme einatmen.","common_mistakes":["Oberkörper pendelt stark vor und zurück, Bewegung kommt aus dem unteren Rücken.","Schultern ziehen während des Zugs nach oben zu den Ohren.","Ellenbogen weichen nach außen aus, Griff wird zur Brust statt zum Bauch gezogen.","Rücken wird in der gestreckten Position stark gerundet.","Gewicht wird in der exzentrischen Phase einfach nach vorne gelassen."],"tips":["Vorstellen, die Ellenbogen nach hinten in die Hosentaschen zu ziehen.","In der Endposition eine Sekunde halten, um die Kontraktion im Rücken zu spüren.","Die exzentrische Phase zwei bis drei Sekunden lang ausführen.","Bei Beschwerden im unteren Rücken leichter beginnen und den Oberkörper bewusst stabil halten."],"cable_setup":{"cable":"Sitzende Ruderstation oder Kabelturm mit unterer Rolle","height":"Rolle unten, etwa auf Höhe des unteren Bauchs in sitzender Position","grip_width":"Eng, neutral (Handflächen zueinander) am V-Griff","body_position":"Aufrecht sitzend, Brust angehoben, Rumpf stabil, Oberkörper nahezu senkrecht","foot_position":"Füße auf den Fußplatten, Knie leicht gebeugt","movement_direction":"Horizontal von vorne nach hinten in Richtung unterer Bauch","elbow_position":"Ellenbogen eng am Körper, zeigen nach hinten","end_position":"Griff am unteren Bauch, Schulterblätter zusammengezogen, Oberkörper aufrecht","return":"Langsam und kontrolliert bis zur Armstreckung, Schulterblätter am Ende leicht nach vorne kommen lassen"}}$seed$::jsonb);

-- Breites Rudern
select public.upsert_seed_exercise($seed${"slug":"breites-rudern","name":"Breites Rudern","category":"back","equipment":"cable","grip_id":"wide_lat_bar","grip_notes":"Breite Latzugstange, pronierter Griff (Handrücken nach oben), Hände deutlich weiter als schulterbreit. Alternativ: gerade Stange in etwas engerer Griffweite.","primary_muscles":["upper_back","mid_back"],"secondary_muscles":["lats","rear_delts","biceps","forearms"],"description":"Horizontale Zugübung am sitzenden Kabelzug mit breiter Stange und proniertem Griff, die vor allem den oberen und mittleren Rücken belastet. Gute Ergänzung zum engen Rudern.","setup":["Breite Latzugstange am unteren Kabel der Ruderstation einhängen.","Hinsetzen, Füße auf die Fußplatten stellen, Knie leicht gebeugt.","Stange deutlich weiter als schulterbreit mit proniertem Griff fassen.","Oberkörper aufrichten, Brust angehoben, Schultern nach unten ziehen.","Arme gestreckt, Gewicht leicht abheben, sodass Spannung auf dem Kabel ist."],"execution":["Stange in Richtung untere Brust bzw. oberer Bauch ziehen.","Ellenbogen führen die Bewegung etwas weiter außen als beim engen Rudern, etwa 45 Grad vom Körper abgespreizt.","Schulterblätter zusammen ziehen, Oberkörper bleibt aufrecht.","In der Endposition kurz halten, Stange befindet sich nah an der unteren Brust.","Gewicht langsam zurückführen, Arme kontrolliert strecken.","Am Ende die Schulterblätter leicht nach vorne kommen lassen, ohne den Rücken rund zu machen.","Ohne Schwung die nächste Wiederholung beginnen."],"range_of_motion":"Von gestreckten Armen mit leicht nach vorne gezogenen Schulterblättern bis die Stange die untere Brust fast berührt. Der Oberkörper bleibt dabei nahezu senkrecht.","breathing":"Beim Ziehen ausatmen, beim Strecken der Arme einatmen.","common_mistakes":["Oberkörper pendelt stark nach hinten, um das Gewicht zu bewegen.","Ellenbogen fliegen weit nach außen auf Schulterhöhe, Schultern rollen nach vorne.","Stange wird zum Bauch gezogen, dadurch verlagert sich die Belastung vom oberen Rücken weg.","Schultern ziehen nach oben zu den Ohren.","Keine Kontrolle in der exzentrischen Phase."],"tips":["Fokus auf das Zusammenziehen der Schulterblätter, nicht auf die Arme.","Gewicht etwas leichter wählen als beim engen Rudern, da die Hebelverhältnisse ungünstiger sind.","Die exzentrische Phase zwei bis drei Sekunden lang kontrollieren."],"cable_setup":{"cable":"Sitzende Ruderstation oder Kabelturm mit unterer Rolle","height":"Rolle unten, etwa auf Höhe des Bauchs in sitzender Position","grip_width":"Deutlich weiter als schulterbreit, proniert (Handrücken nach oben)","body_position":"Aufrecht sitzend, Brust angehoben, Rumpf stabil, Oberkörper nahezu senkrecht","foot_position":"Füße auf den Fußplatten, Knie leicht gebeugt","movement_direction":"Horizontal von vorne nach hinten in Richtung untere Brust bzw. oberer Bauch","elbow_position":"Ellenbogen etwa 45 Grad vom Körper abgespreizt, zeigen nach hinten-außen","end_position":"Stange nah an der unteren Brust, Schulterblätter zusammengezogen, Oberkörper aufrecht","return":"Langsam und kontrolliert bis zur Armstreckung, Schulterblätter am Ende leicht nach vorne kommen lassen"}}$seed$::jsonb);

-- Brustgestütztes Rudern
select public.upsert_seed_exercise($seed${"slug":"brustgestuetztes-rudern","name":"Brustgestütztes Rudern","category":"back","equipment":"machine","grip_id":null,"grip_notes":"Neutrale oder pronierte Griffe, je nach Maschine. Neutraler Griff mit Ellenbogen nah am Körper betont eher den Latissimus, pronierter Griff mit Ellenbogen weiter außen eher den oberen Rücken. Handgelenke gerade halten.","primary_muscles":["mid_back","lats"],"secondary_muscles":["upper_back","rear_delts","biceps","forearms"],"description":"Horizontale Zugübung an einer Rudermaschine mit Brustpolster, das den Oberkörper stabilisiert und den unteren Rücken entlastet. Geeignet, um den Rücken ohne Ausweichbewegungen des Rumpfes zu trainieren.","setup":["Sitz so einstellen, dass die Griffe etwa auf Höhe der unteren Brust liegen.","Brust fest an das Polster legen, Füße flach auf den Boden oder die Fußplatten stellen.","Griffe fassen, Handgelenke gerade, Arme gestreckt.","Schultern bewusst nach unten ziehen, Brust bleibt am Polster.","Rumpf anspannen, bevor die Bewegung beginnt."],"execution":["Griffe kontrolliert nach hinten ziehen, Ellenbogen führen die Bewegung.","Schulterblätter zusammen ziehen, Brust bleibt die ganze Zeit am Polster.","In der Endposition kurz halten, Ellenbogen befinden sich etwa auf Höhe des Rumpfes oder leicht dahinter.","Gewicht langsam zurückführen, Arme kontrolliert strecken.","Am Ende die Schulterblätter leicht nach vorne kommen lassen, um den Rücken zu dehnen.","Ohne Schwung die nächste Wiederholung beginnen."],"range_of_motion":"Von gestreckten Armen mit leicht nach vorne gezogenen Schulterblättern bis die Ellenbogen etwa auf Höhe des Rumpfes oder leicht dahinter sind. Die Brust löst sich dabei nicht vom Polster.","breathing":"Beim Ziehen ausatmen, beim Strecken der Arme einatmen.","common_mistakes":["Brust löst sich vom Polster, um das Gewicht mit dem Oberkörper zu bewegen.","Schultern ziehen nach oben zu den Ohren.","Bewegung kommt vor allem aus den Armen, Schulterblätter bleiben vorne.","Sitz zu niedrig oder zu hoch, Griffe liegen auf Schulterhöhe oder Bauchhöhe.","Gewicht wird in der exzentrischen Phase einfach nach vorne gelassen."],"tips":["In der Endposition eine Sekunde halten, um die Kontraktion im Rücken zu spüren.","Die exzentrische Phase zwei bis drei Sekunden lang kontrollieren.","Gut geeignet als Alternative zum Kabelrudern, wenn der untere Rücken entlastet werden soll."],"cable_setup":null}$seed$::jsonb);

-- Kabelrudern einarmig
select public.upsert_seed_exercise($seed${"slug":"kabelrudern-einarmig","name":"Kabelrudern einarmig","category":"back","equipment":"cable","grip_id":"single_handle","grip_notes":"Einzelgriff, neutral (Handfläche zeigt zum Körper). Alternativ: Griff während des Zugs leicht eindrehen, sodass die Handfläche am Ende nach innen-oben zeigt.","primary_muscles":["lats","mid_back"],"secondary_muscles":["biceps","forearms","rear_delts"],"description":"Einarmige horizontale Zugübung am Kabelzug, die den Latissimus und den mittleren Rücken belastet. Geeignet, um Seitenunterschiede auszugleichen und den Bewegungsradius pro Seite zu vergrößern.","setup":["Einzelgriff am Kabelzug einhängen, Rolle etwa auf Bauchhöhe einstellen.","Sitzend an der Ruderstation oder stehend in Schrittstellung vor dem Kabelturm positionieren.","Griff mit einer Hand fassen, die freie Hand stützt sich am Gerät oder auf dem vorderen Oberschenkel ab.","Oberkörper aufrecht, Brust angehoben, Rumpf anspannen.","Arm gestreckt, Schulter nach unten ziehen, Gewicht leicht abheben, sodass Spannung auf dem Kabel ist."],"execution":["Griff in Richtung Hüfte bzw. unterer Bauch ziehen, Ellenbogen führt die Bewegung nah am Körper nach hinten.","Schulterblatt der arbeitenden Seite nach hinten und unten ziehen.","In der Endposition kurz halten, Ellenbogen befindet sich leicht hinter dem Rumpf.","Gewicht langsam zurückführen, Arm kontrolliert strecken.","Am Ende das Schulterblatt leicht nach vorne kommen lassen, ohne den Oberkörper zu verdrehen.","Alle Wiederholungen auf einer Seite ausführen, dann die Seite wechseln."],"range_of_motion":"Von gestrecktem Arm mit leicht nach vorne gezogenem Schulterblatt bis der Ellenbogen leicht hinter dem Rumpf ist. Der Oberkörper bleibt dabei stabil und dreht sich nur minimal mit.","breathing":"Beim Ziehen ausatmen, beim Strecken des Arms einatmen.","common_mistakes":["Oberkörper dreht sich stark mit, um das Gewicht zu bewegen.","Schulter zieht während des Zugs nach oben zum Ohr.","Ellenbogen weicht nach außen aus, Griff wird zur Brust statt zur Hüfte gezogen.","Zu schweres Gewicht, Bewegung wird aus dem Bizeps statt aus dem Rücken ausgeführt.","Keine Kontrolle in der exzentrischen Phase."],"tips":["Mit der schwächeren Seite beginnen und die Wiederholungszahl auf der stärkeren Seite daran anpassen.","Vorstellen, den Ellenbogen nach hinten in die Hosentasche zu ziehen.","Die exzentrische Phase zwei bis drei Sekunden lang kontrollieren."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, eine Seite; alternativ sitzende Ruderstation","height":"Rolle etwa auf Bauchhöhe (sitzend) bzw. auf Hüft- bis Bauchhöhe (stehend)","grip_width":"Einzelgriff, eine Hand, neutral (Handfläche zum Körper)","body_position":"Sitzend aufrecht oder stehend in Schrittstellung mit leicht nach vorne geneigtem Oberkörper, Rumpf stabil, freie Hand stützt","foot_position":"Sitzend: Füße auf den Fußplatten; stehend: Schrittstellung, gegenüberliegendes Bein vorne","movement_direction":"Horizontal von vorne nach hinten in Richtung Hüfte bzw. unterer Bauch","elbow_position":"Ellenbogen eng am Körper, zeigt nach hinten","end_position":"Griff an der Hüfte, Ellenbogen leicht hinter dem Rumpf, Schulterblatt nach hinten und unten gezogen","return":"Langsam und kontrolliert bis zur Armstreckung, Schulterblatt am Ende leicht nach vorne kommen lassen"}}$seed$::jsonb);

-- Reverse Fly Kurzhantel
select public.upsert_seed_exercise($seed${"slug":"reverse-fly-kurzhantel","name":"Reverse Fly Kurzhantel","category":"back","equipment":"dumbbell","grip_id":null,"grip_notes":"Neutraler Griff (Handflächen zeigen zueinander) oder pronierter Griff (Handrücken nach oben). Hanteln locker in den Händen halten, Ellenbogen während der gesamten Bewegung leicht gebeugt.","primary_muscles":["rear_delts","upper_back"],"secondary_muscles":["traps","mid_back"],"description":"Seitliches Anheben der Arme in vorgebeugter Position, das die hintere Schulter und den oberen Rücken belastet. Geeignet als Ergänzung zu Zugübungen und als Ausgleich zu Druckübungen.","setup":["Leichte Kurzhanteln wählen.","Oberkörper etwa 45 Grad bis fast parallel zum Boden nach vorne neigen, Knie leicht gebeugt, Rücken gerade.","Alternativ bäuchlings auf eine Schrägbank legen, Brust auf dem Polster.","Hanteln unter der Brust hängen lassen, Arme fast gestreckt, Ellenbogen leicht gebeugt.","Rumpf anspannen, Nacken in Verlängerung der Wirbelsäule, Blick nach unten.","Schultern nach unten ziehen, bevor die Bewegung beginnt."],"execution":["Arme seitlich nach außen-oben anheben, Ellenbogen bleiben leicht gebeugt.","Bewegung aus den Schultern und Schulterblättern führen, nicht aus den Armen.","Anheben, bis die Oberarme etwa auf Höhe des Rückens sind.","In der Endposition kurz halten, Schulterblätter leicht zusammen ziehen.","Hanteln langsam und kontrolliert wieder absenken.","Unten die Spannung halten, Hanteln nicht zusammenschlagen lassen."],"range_of_motion":"Von hängenden Armen bis die Oberarme etwa auf Höhe des Rückens sind. Höher als die Rückenlinie ist nicht notwendig.","breathing":"Beim Anheben ausatmen, beim Absenken einatmen.","common_mistakes":["Oberkörper richtet sich beim Anheben auf, um Schwung zu holen.","Zu schweres Gewicht, Ellenbogen werden stark gebeugt und die Bewegung wird zum Rudern.","Schultern ziehen nach oben zu den Ohren.","Rücken wird in der vorgebeugten Position rund.","Hanteln werden einfach fallen gelassen, keine Kontrolle beim Absenken."],"tips":["Deutlich leichter beginnen als bei Ruderübungen, die hintere Schulter ist ein kleiner Muskel.","Daumen leicht nach unten drehen, um die hintere Schulter stärker zu betonen.","Die Variante auf der Schrägbank nimmt den unteren Rücken aus der Übung.","Höhere Wiederholungszahlen mit sauberer Technik sind hier sinnvoller als schweres Gewicht."],"cable_setup":null}$seed$::jsonb);

-- Straight Arm Pulldown
select public.upsert_seed_exercise($seed${"slug":"straight-arm-pulldown","name":"Straight Arm Pulldown","category":"back","equipment":"cable","grip_id":"straight_bar","grip_notes":"Gerade Stange, pronierter Griff etwa schulterbreit. Alternativ: Seil mit neutralem Griff (Handflächen zueinander), erlaubt am Ende etwas mehr Bewegung an der Hüfte vorbei.","primary_muscles":["lats"],"secondary_muscles":["triceps","rear_delts","abs"],"description":"Zugübung am oberen Kabel mit fast gestreckten Armen, bei der der Latissimus ohne nennenswerte Beteiligung des Bizeps arbeitet. Geeignet als Isolations- oder Vorermüdungsübung für den Rücken.","setup":["Gerade Stange am oberen Kabel einhängen.","Etwa einen Schritt vom Kabelturm entfernt aufstellen, Füße hüftbreit, Knie leicht gebeugt.","Stange schulterbreit mit proniertem Griff fassen, Arme nach vorne-oben gestreckt.","Oberkörper leicht nach vorne neigen, Rücken gerade, Rumpf anspannen.","Schultern nach unten ziehen, Ellenbogen leicht gebeugt und in dieser Position fixieren."],"execution":["Stange in einem Bogen nach unten zu den Oberschenkeln ziehen, Arme bleiben fast gestreckt.","Bewegung aus den Schultern führen, Ellenbogenwinkel bleibt unverändert.","Schulterblätter nach unten ziehen, Oberkörper bleibt stabil.","In der Endposition kurz halten, Stange berührt beinahe die Oberschenkel.","Stange langsam und kontrolliert wieder nach oben führen.","Oben die Dehnung im Latissimus spüren, ohne den Rücken zu überstrecken.","Ohne Schwung aus dem Oberkörper die nächste Wiederholung beginnen."],"range_of_motion":"Von Armen etwa auf Höhe des Kopfes oder leicht darüber bis die Stange die Oberschenkel fast berührt. Oben nur so weit, wie der Rücken gerade bleibt.","breathing":"Beim Ziehen nach unten ausatmen, beim Zurückführen nach oben einatmen.","common_mistakes":["Ellenbogen werden während des Zugs gebeugt, die Übung wird zum Trizepsdrücken.","Oberkörper pendelt mit, um das Gewicht zu bewegen.","Schultern rollen nach vorne und ziehen nach oben.","Zu schweres Gewicht, die Bewegung wird kurz und ruckartig.","Rücken wird in der oberen Position stark überstreckt."],"tips":["Leichtes Gewicht wählen und die Spannung im Latissimus über den gesamten Bewegungsradius halten.","Vorstellen, die Stange mit den Ellenbogen statt mit den Händen nach unten zu drücken.","Die exzentrische Phase zwei bis drei Sekunden lang ausführen.","Mit dem Seil lässt sich die Endposition etwas weiter an der Hüfte vorbei führen."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug mit oberer Rolle","height":"Rolle ganz oben","grip_width":"Schulterbreit, proniert (Handrücken nach oben) an der geraden Stange","body_position":"Stehend, etwa einen Schritt vom Turm entfernt, Oberkörper leicht nach vorne geneigt, Rücken gerade, Rumpf angespannt","foot_position":"Hüftbreit, Knie leicht gebeugt, Gewicht gleichmäßig auf beiden Füßen","movement_direction":"Bogenförmig von vorne-oben nach unten zu den Oberschenkeln","elbow_position":"Leicht gebeugt und während der gesamten Bewegung unverändert","end_position":"Stange an den Oberschenkeln, Schulterblätter nach unten gezogen, Oberkörper stabil","return":"Langsam und kontrolliert nach oben bis etwa auf Kopfhöhe, Dehnung im Latissimus, Rücken bleibt gerade"}}$seed$::jsonb);

-- Hyperextensions
select public.upsert_seed_exercise($seed${"slug":"hyperextensions","name":"Hyperextensions","category":"back","equipment":"bodyweight","grip_id":null,"grip_notes":"Arme vor der Brust verschränkt oder Hände an den Schläfen. Mit Zusatzgewicht: Hantelscheibe oder Kurzhantel vor der Brust halten.","primary_muscles":["lower_back","glutes"],"secondary_muscles":["hamstrings"],"description":"Rumpfstreckung an der 45-Grad-Rückenstrecker-Bank, die den unteren Rücken, das Gesäß und die hintere Oberschenkelmuskulatur belastet. Geeignet als Ergänzung im Rücken- oder Beintraining und zur Kräftigung der Rumpfrückseite.","setup":["Hüftpolster so einstellen, dass die Oberkante knapp unterhalb des Hüftknochens liegt und die Hüfte frei beugen kann.","Fersen fest gegen die Fußplatte stellen, Füße hüftbreit.","Oberkörper auf dem Polster ablegen, Arme vor der Brust verschränken.","Rumpf anspannen, Nacken in Verlängerung der Wirbelsäule.","Oberkörper aufrichten, bis der Körper eine gerade Linie von Kopf bis Ferse bildet."],"execution":["Oberkörper langsam aus der Hüfte nach unten absenken, Wirbelsäule bleibt neutral.","So weit absenken, wie der Rücken gerade bleibt, etwa bis der Oberkörper senkrecht ist.","Gesäß und hintere Oberschenkel anspannen und den Oberkörper kontrolliert wieder anheben.","Anheben, bis Oberkörper und Beine eine gerade Linie bilden.","In der Endposition kurz halten, ohne weiter nach oben zu überstrecken.","Nächste Wiederholung kontrolliert beginnen."],"range_of_motion":"Von der geraden Linie zwischen Oberkörper und Beinen bis der Oberkörper etwa senkrecht hängt. In der Endposition nicht über die gerade Linie hinaus überstrecken.","breathing":"Beim Absenken einatmen, beim Anheben ausatmen.","common_mistakes":["Oberkörper wird in der Endposition über die gerade Linie hinaus überstreckt.","Rücken wird beim Absenken rund, Bewegung kommt aus der Wirbelsäule statt aus der Hüfte.","Polster zu hoch eingestellt, Hüfte kann nicht frei beugen.","Bewegung wird mit Schwung ausgeführt.","Kopf wird in den Nacken gelegt."],"tips":["Zunächst mit Körpergewicht beginnen, Zusatzgewicht erst dann, wenn die Technik stabil ist.","Für mehr Betonung des Gesäßes die Füße leicht nach außen drehen und bewusst aus der Hüfte arbeiten.","Die exzentrische Phase zwei bis drei Sekunden lang kontrollieren."],"cable_setup":null}$seed$::jsonb);

-- Wrist Curl
select public.upsert_seed_exercise($seed${"slug":"wrist-curl","name":"Wrist Curl","category":"forearms","equipment":"dumbbell","grip_id":null,"grip_notes":"Supinierter Griff (Handflächen nach oben), Kurzhantel locker in den Fingern. Alternativ: Langhantel mit beiden Händen, etwa schulterbreit.","primary_muscles":["forearms"],"secondary_muscles":[],"description":"Isolierte Beugung des Handgelenks mit der Kurzhantel, die die Beugemuskulatur des Unterarms belastet. Geeignet als Ergänzung am Ende des Arm- oder Rückentrainings.","setup":["Leichte Kurzhantel wählen, sitzend auf einer Bank Platz nehmen.","Unterarm auf dem Oberschenkel oder auf der Bank ablegen, Handfläche zeigt nach oben.","Handgelenk ragt über das Knie bzw. die Bankkante hinaus, sodass es sich frei bewegen kann.","Hantel locker greifen, Finger leicht geöffnet.","Unterarm bleibt während der gesamten Bewegung auf der Unterlage."],"execution":["Handgelenk langsam nach unten beugen, Hantel in die Finger rollen lassen.","In der unteren Position die Dehnung im Unterarm kurz halten.","Hantel mit den Fingern wieder greifen und das Handgelenk nach oben beugen.","In der oberen Position kurz halten, Unterarm bleibt auf der Unterlage.","Hantel langsam und kontrolliert wieder absenken.","Nach allen Wiederholungen die Seite wechseln."],"range_of_motion":"Von der vollständig gestreckten Position mit geöffneten Fingern bis zur vollen Beugung des Handgelenks nach oben. Der Unterarm bewegt sich dabei nicht.","breathing":"Beim Beugen nach oben ausatmen, beim Absenken einatmen.","common_mistakes":["Unterarm hebt sich von der Unterlage ab, die Bewegung kommt aus dem Ellenbogen.","Zu schweres Gewicht, der Bewegungsradius wird sehr klein.","Hantel wird mit Schwung nach oben geworfen.","Keine Kontrolle beim Absenken."],"tips":["Leichtes Gewicht und höhere Wiederholungszahlen wählen, die Unterarmmuskulatur reagiert gut darauf.","Die Hantel bewusst bis in die Finger rollen lassen, um den vollen Bewegungsradius zu nutzen.","Tempo langsam halten, etwa zwei Sekunden pro Phase."],"cable_setup":null}$seed$::jsonb);

-- Reverse Wrist Curl
select public.upsert_seed_exercise($seed${"slug":"reverse-wrist-curl","name":"Reverse Wrist Curl","category":"forearms","equipment":"dumbbell","grip_id":null,"grip_notes":"Pronierter Griff (Handflächen nach unten), Hantel fest umschlossen. Alternativ: Langhantel oder EZ-Stange mit beiden Händen, etwa schulterbreit.","primary_muscles":["forearms"],"secondary_muscles":[],"description":"Isolierte Streckung des Handgelenks mit der Kurzhantel, die die Streckmuskulatur des Unterarms belastet. Geeignet als Ausgleich zum Wrist Curl und zur Kräftigung der Unterarmaußenseite.","setup":["Deutlich leichtere Kurzhantel als beim Wrist Curl wählen, sitzend auf einer Bank Platz nehmen.","Unterarm auf dem Oberschenkel oder auf der Bank ablegen, Handfläche zeigt nach unten.","Handgelenk ragt über das Knie bzw. die Bankkante hinaus, sodass es sich frei bewegen kann.","Hantel fest umschließen, Handgelenk in neutraler Ausgangsposition.","Unterarm bleibt während der gesamten Bewegung auf der Unterlage."],"execution":["Handgelenk langsam nach unten beugen, Handrücken bewegt sich in Richtung Boden.","In der unteren Position die Dehnung an der Unterarmaußenseite kurz halten.","Handgelenk kontrolliert nach oben strecken, Handrücken bewegt sich in Richtung Unterarm.","In der oberen Position kurz halten, Unterarm bleibt auf der Unterlage.","Hantel langsam und kontrolliert wieder absenken.","Nach allen Wiederholungen die Seite wechseln."],"range_of_motion":"Von der vollständig gebeugten Position nach unten bis zur vollen Streckung des Handgelenks nach oben. Der Unterarm bewegt sich dabei nicht.","breathing":"Beim Strecken nach oben ausatmen, beim Absenken einatmen.","common_mistakes":["Zu schweres Gewicht, die Streckmuskulatur ist deutlich schwächer als die Beugemuskulatur.","Unterarm hebt sich von der Unterlage ab, die Bewegung kommt aus dem Ellenbogen.","Bewegungsradius wird sehr klein, nur das obere Drittel wird genutzt.","Hantel wird mit Schwung nach oben geworfen."],"tips":["Mit etwa der Hälfte des Gewichts vom Wrist Curl beginnen und bei Bedarf anpassen.","Leichtes Gewicht und höhere Wiederholungszahlen wählen.","Tempo langsam halten, etwa zwei Sekunden pro Phase.","Bei Beschwerden im Ellenbogen das Gewicht reduzieren oder den Bewegungsradius verkleinern."],"cable_setup":null}$seed$::jsonb);

-- Hackenschmidt
select public.upsert_seed_exercise($seed${"slug":"hackenschmidt","name":"Hackenschmidt","category":"quads","equipment":"machine","grip_id":null,"grip_notes":"Haltegriffe neben den Schulterpolstern fassen, Hände bleiben locker. Füße mittig auf der Plattform, etwa schulterbreit, Fußspitzen leicht nach außen.","primary_muscles":["quads"],"secondary_muscles":["glutes","hamstrings"],"description":"Geführte Kniebeuge an der Hackenschmidt-Maschine, bei der der Rücken am Schlitten anliegt und die Bewegung in einer festen Bahn verläuft. Gut geeignet, um den Quadrizeps mit hoher Kontrolle und ohne freie Stabilisation zu belasten.","setup":["Rücken und Schultern vollständig an das Rückenpolster und die Schulterpolster anlegen.","Füße mittig und etwa schulterbreit auf der Plattform platzieren, Fußspitzen leicht nach außen.","Haltegriffe fassen und die Sicherungen der Maschine lösen.","Rumpf anspannen, unterer Rücken bleibt am Polster.","Knie in der Startposition leicht gebeugt lassen, nicht durchgestreckt."],"execution":["Schlitten kontrolliert absenken, Knie beugen sich in Richtung Fußspitzen.","Fersen bleiben während der gesamten Bewegung auf der Plattform.","So tief absenken, wie Beweglichkeit und Becken am Polster es zulassen.","Kurz in der unteren Position stoppen, ohne das Gewicht abzusetzen.","Über die ganze Fußsohle nach oben drücken, bis die Knie fast gestreckt sind.","Knie oben nicht durchdrücken, Spannung im Oberschenkel halten."],"range_of_motion":"Absenken, bis die Oberschenkel etwa parallel zur Plattform stehen oder so weit, wie das Becken am Polster bleibt. Oben kurz vor der vollen Kniestreckung stoppen.","breathing":"Beim Hochdrücken ausatmen, beim Absenken einatmen.","common_mistakes":["Fersen heben sich in der unteren Position von der Plattform ab.","Knie fallen nach innen, statt in Richtung Fußspitzen zu zeigen.","Becken kippt unten vom Polster weg, unterer Rücken rundet sich.","Knie werden oben vollständig durchgestreckt und die Spannung geht verloren.","Füße stehen zu weit unten auf der Plattform, Fersen finden keinen Halt."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Füße etwas höher auf der Plattform platzieren, wenn Gesäß und hintere Oberschenkel stärker beteiligt sein sollen.","Sicherungen vor dem Satz prüfen und erst nach dem letzten Satz wieder einrasten lassen.","Erst dann Gewicht erhöhen, wenn die Tiefe über alle Wiederholungen gleich bleibt."],"cable_setup":null}$seed$::jsonb);

-- Beinpresse
select public.upsert_seed_exercise($seed${"slug":"beinpresse","name":"Beinpresse","category":"quads","equipment":"machine","grip_id":null,"grip_notes":"Haltegriffe seitlich am Sitz fassen, um das Becken stabil zu halten. Füße mittig auf der Platte, etwa schulterbreit, Fußspitzen leicht nach außen.","primary_muscles":["quads"],"secondary_muscles":["glutes","hamstrings"],"description":"Geführte Druckübung an der 45-Grad- oder horizontalen Beinpresse, bei der der Oberkörper fixiert ist und die Beine das Gewicht wegdrücken. Gut geeignet, um Quadrizeps und Gesäß mit hoher Last und geringer Stabilisationsanforderung zu trainieren.","setup":["Rückenlehne so einstellen, dass unterer Rücken und Becken vollständig am Polster anliegen.","Füße mittig und etwa schulterbreit auf die Platte stellen, Fußspitzen leicht nach außen.","Haltegriffe fassen, Rumpf anspannen.","Platte leicht wegdrücken und die Sicherungen lösen.","Startposition mit leicht gebeugten Knien einnehmen, Fersen fest auf der Platte."],"execution":["Platte kontrolliert absenken, Knie beugen sich in Richtung Fußspitzen.","So weit absenken, wie das Becken am Polster bleibt.","Unten kurz stoppen, ohne dass das Gewicht aufsetzt.","Über die ganze Fußsohle wegdrücken, Fersen bleiben auf der Platte.","Knie am Ende nicht vollständig durchstrecken.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von leicht gebeugten Knien bis zu einem Kniewinkel von etwa 90 Grad oder tiefer, solange das Becken am Polster bleibt. Oben kurz vor der vollen Streckung stoppen.","breathing":"Beim Wegdrücken ausatmen, beim Absenken einatmen.","common_mistakes":["Becken hebt sich unten vom Polster ab, unterer Rücken rundet sich.","Knie werden oben vollständig durchgestreckt.","Knie fallen beim Drücken nach innen.","Fersen heben sich von der Platte ab, Druck kommt nur aus den Zehen.","Gewicht wird unten mit Schwung abgefangen."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Hände an den Griffen lassen und nicht gegen die Knie drücken.","Höhere Fußposition auf der Platte verlagert die Belastung mehr auf Gesäß und hintere Oberschenkel, tiefere Position mehr auf den Quadrizeps.","Sicherungen vor dem Satz prüfen und erst nach dem letzten Satz einrasten lassen."],"cable_setup":null}$seed$::jsonb);

-- Beinstrecker
select public.upsert_seed_exercise($seed${"slug":"beinstrecker","name":"Beinstrecker","category":"quads","equipment":"machine","grip_id":null,"grip_notes":"Haltegriffe seitlich am Sitz fassen, um das Becken im Sitz zu halten. Keine Griffarbeit nötig, Hände bleiben locker.","primary_muscles":["quads"],"secondary_muscles":[],"description":"Isolationsübung an der Maschine, bei der die Knie gegen Widerstand gestreckt werden. Gut geeignet, um den Quadrizeps gezielt und ohne Belastung von Hüfte und Rücken zu trainieren.","setup":["Rückenlehne so einstellen, dass die Drehachse der Maschine auf Höhe des Kniegelenks liegt.","Beinpolster so einstellen, dass es knapp oberhalb des Sprunggelenks am Schienbein anliegt.","Rücken vollständig an das Polster anlehnen, Haltegriffe fassen.","Oberschenkel liegen flach auf dem Sitz, Fußspitzen leicht angezogen.","Gewicht so wählen, dass die Streckung kontrolliert möglich ist."],"execution":["Beine kontrolliert strecken, bis die Knie fast gestreckt sind.","In der Endposition ein bis zwei Sekunden halten und den Quadrizeps anspannen.","Oberschenkel bleiben auf dem Sitz, Becken bleibt am Polster.","Gewicht langsam zurückführen, bis der Kniewinkel etwa 90 Grad erreicht.","Gewicht nicht aufsetzen lassen, Spannung halten.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von etwa 90 Grad Kniebeugung bis zur fast vollständigen Streckung. Bei Beschwerden im Knie den Bewegungsradius in der unteren Position verkleinern.","breathing":"Beim Strecken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Gewicht wird mit Schwung nach oben geschleudert.","Becken hebt sich vom Sitz ab, um mehr Gewicht zu bewegen.","Drehachse der Maschine liegt nicht auf Kniehöhe, Knie wird ungünstig belastet.","Gewicht fällt in der exzentrischen Phase unkontrolliert zurück.","Polster liegt zu hoch am Schienbein, Hebel wird ungünstig."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Fußspitzen leicht nach oben ziehen, um die Spannung im Quadrizeps zu erhöhen.","Einbeinige Ausführung, um Seitenunterschiede auszugleichen.","Mit moderatem Gewicht und höheren Wiederholungszahlen beginnen, dann schrittweise steigern."],"cable_setup":null}$seed$::jsonb);

-- Bulgarian Split Squat
select public.upsert_seed_exercise($seed${"slug":"bulgarian-split-squat","name":"Bulgarian Split Squat","category":"quads","equipment":"dumbbell","grip_id":null,"grip_notes":"Kurzhanteln neutral an den Seiten halten, Arme hängen locker, Handgelenke gerade. Alternativ eine Kurzhantel vor der Brust halten (Goblet-Position) für mehr Rumpfstabilität.","primary_muscles":["quads","glutes"],"secondary_muscles":["hamstrings","abs"],"description":"Einbeinige Kniebeuge mit dem hinteren Fuß auf einer Bank, bei der das vordere Bein die Hauptlast trägt. Gut geeignet, um Quadrizeps und Gesäß einseitig zu belasten und Seitenunterschiede auszugleichen.","setup":["Bank hinter sich aufstellen, Kurzhanteln an den Seiten halten.","Mit dem Rücken zur Bank einen großen Schritt nach vorne machen.","Hinteren Fuß mit dem Fußrücken oder den Zehen auf der Bank ablegen.","Vorderer Fuß steht flach und so weit vorne, dass das Knie unten etwa über dem Mittelfuß bleibt.","Oberkörper aufrecht, Blick nach vorne, Rumpf anspannen."],"execution":["Vorderes Knie kontrolliert beugen und das Becken gerade nach unten absenken.","Vorderes Knie zeigt in Richtung Fußspitze, Ferse bleibt am Boden.","Hinteres Knie nähert sich dem Boden, ohne aufzusetzen.","Oberkörper bleibt aufrecht oder leicht nach vorne geneigt.","Über die ganze Fußsohle des vorderen Fußes nach oben drücken.","Oben Knie nicht durchstrecken, Spannung halten.","Nach allen Wiederholungen die Seite wechseln."],"range_of_motion":"Absenken, bis der vordere Oberschenkel etwa parallel zum Boden steht oder das hintere Knie knapp über dem Boden ist, je nach Beweglichkeit. Oben kurz vor der vollen Streckung stoppen.","breathing":"Beim Hochdrücken ausatmen, beim Absenken einatmen.","common_mistakes":["Vorderer Fuß steht zu nah an der Bank, Knie wandert weit über die Fußspitze.","Vorderes Knie fällt nach innen.","Oberkörper kippt stark nach vorne oder dreht sich ein.","Hinteres Bein drückt aktiv mit und übernimmt einen Teil der Arbeit.","Ferse des vorderen Fußes hebt sich vom Boden ab."],"tips":["Zuerst ohne Zusatzgewicht die Fußposition finden, dann Kurzhanteln hinzunehmen.","Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Leichte Vorlage des Oberkörpers betont das Gesäß, aufrechte Haltung mehr den Quadrizeps.","Bei Gleichgewichtsproblemen mit einer Hand leicht an einem Rack abstützen."],"cable_setup":null}$seed$::jsonb);

-- Kniebeuge
select public.upsert_seed_exercise($seed${"slug":"kniebeuge","name":"Kniebeuge","category":"quads","equipment":"barbell","grip_id":null,"grip_notes":"Pronierter Griff etwas weiter als schulterbreit, Stange liegt auf dem oberen Trapez (High Bar) oder etwas tiefer auf den hinteren Schultern (Low Bar). Handgelenke möglichst gerade, Ellenbogen zeigen nach unten.","primary_muscles":["quads","glutes"],"secondary_muscles":["hamstrings","lower_back","abs"],"description":"Freie Kniebeuge mit der Langhantel im Nacken, bei der Knie und Hüfte gemeinsam gebeugt und gestreckt werden. Grundübung für Quadrizeps und Gesäß, die zusätzlich Rumpf und unteren Rücken fordert.","setup":["Stange im Rack etwa auf Höhe des oberen Brustbeins ablegen, Sicherheitsstangen knapp unterhalb der tiefsten Position einstellen.","Unter die Stange treten, Stange auf dem oberen Trapez ablegen und Griff etwas weiter als schulterbreit fassen.","Schulterblätter zusammenziehen, Rumpf anspannen und Stange aus dem Rack heben.","Ein bis zwei kleine Schritte zurück, Füße etwa schulterbreit, Fußspitzen leicht nach außen.","Blick nach vorne, Stange steht über dem Mittelfuß."],"execution":["Vor dem Absenken einatmen und den Rumpf anspannen.","Hüfte und Knie gleichzeitig beugen, Becken nach hinten und unten absenken.","Knie zeigen in Richtung Fußspitzen, Fersen bleiben am Boden.","So tief absenken, wie der Rücken neutral bleibt.","Über die ganze Fußsohle nach oben drücken, Hüfte und Schultern steigen gemeinsam.","Oben aufrecht stehen, Knie nicht hart durchstrecken.","Nach dem letzten Satz Stange kontrolliert zurück ins Rack führen."],"range_of_motion":"Tiefe nach Beweglichkeit wählen, in der Regel bis die Oberschenkel etwa parallel zum Boden stehen oder tiefer. Sobald das Becken unten einrollt oder die Fersen abheben, ist der sinnvolle Bewegungsradius erreicht.","breathing":"Oben einatmen und die Spannung während des Absenkens halten, beim Hochdrücken nach dem schwersten Punkt ausatmen.","common_mistakes":["Knie fallen nach innen.","Fersen heben sich vom Boden ab, Gewicht verlagert sich auf die Zehen.","Hüfte steigt beim Hochdrücken schneller als die Schultern, Oberkörper kippt nach vorne.","Unterer Rücken rundet sich in der tiefen Position.","Sicherheitsstangen werden nicht eingestellt oder liegen zu hoch."],"tips":["Technik zuerst mit der leeren Stange oder leichtem Gewicht festigen.","Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Bei eingeschränkter Sprunggelenkbeweglichkeit Fersen leicht erhöhen oder Schuhe mit erhöhter Ferse nutzen.","Gewicht in kleinen Schritten steigern, wenn Tiefe und Rückenposition stabil bleiben."],"cable_setup":null}$seed$::jsonb);

-- Ausfallschritte
select public.upsert_seed_exercise($seed${"slug":"ausfallschritte","name":"Ausfallschritte","category":"glutes","equipment":"dumbbell","grip_id":null,"grip_notes":"Kurzhanteln neutral an den Seiten halten, Arme hängen locker, Schultern hinten. Handgelenke gerade.","primary_muscles":["glutes","quads"],"secondary_muscles":["hamstrings","abs"],"description":"Schrittbewegung mit Kurzhanteln, bei der ein Bein nach vorne gesetzt und das Becken abgesenkt wird, entweder gehend (Walking Lunges) oder auf der Stelle. Gut geeignet für Gesäß und Oberschenkel sowie für Gleichgewicht und einseitige Stabilität.","setup":["Kurzhanteln an den Seiten halten, Füße hüftbreit, Oberkörper aufrecht.","Ausreichend Platz nach vorne sicherstellen, besonders bei gehender Ausführung.","Rumpf anspannen, Blick nach vorne.","Schrittlänge so wählen, dass das vordere Knie unten etwa über dem Mittelfuß bleibt."],"execution":["Mit einem Bein einen großen Schritt nach vorne machen und den Fuß flach aufsetzen.","Becken gerade nach unten absenken, beide Knie beugen sich.","Vorderes Knie zeigt in Richtung Fußspitze, Ferse bleibt am Boden.","Hinteres Knie nähert sich dem Boden, ohne hart aufzusetzen.","Über die ganze Fußsohle des vorderen Fußes nach oben drücken.","Bei Walking Lunges das hintere Bein direkt in den nächsten Schritt führen, auf der Stelle zurück in die Ausgangsposition.","Seiten gleichmäßig abwechseln."],"range_of_motion":"Absenken, bis der vordere Oberschenkel etwa parallel zum Boden steht und das hintere Knie knapp über dem Boden ist, je nach Beweglichkeit. Oben kurz vor der vollen Kniestreckung stoppen.","breathing":"Beim Hochdrücken ausatmen, beim Absenken einatmen.","common_mistakes":["Schritt zu kurz, vorderes Knie wandert weit über die Fußspitze.","Vorderes Knie fällt nach innen.","Oberkörper kippt nach vorne oder dreht sich zur Seite.","Hinteres Knie schlägt auf den Boden auf.","Abdruck erfolgt über die Zehen statt über die ganze Fußsohle."],"tips":["Zuerst ohne Zusatzgewicht die Schrittlänge finden, dann Kurzhanteln hinzunehmen.","Leichte Vorlage des Oberkörpers betont das Gesäß stärker.","Exzentrische Phase kontrolliert ausführen, nicht in die untere Position fallen.","Bei Gleichgewichtsproblemen Ausfallschritte auf der Stelle statt gehend ausführen."],"cable_setup":null}$seed$::jsonb);

-- Beinbeuger
select public.upsert_seed_exercise($seed${"slug":"beinbeuger","name":"Beinbeuger","category":"hamstrings","equipment":"machine","grip_id":null,"grip_notes":"Haltegriffe fassen, um Becken und Oberkörper stabil zu halten. Liegend: Griffe vorne unter dem Polster, Hüfte bleibt auf dem Polster. Sitzend: Griffe seitlich, Rücken am Polster, Oberschenkelpolster fest fixiert.","primary_muscles":["hamstrings"],"secondary_muscles":["calves","glutes"],"description":"Isolationsübung an der Maschine, bei der die Knie gegen Widerstand gebeugt werden, liegend oder sitzend. Gut geeignet, um die hintere Oberschenkelmuskulatur gezielt zu trainieren.","setup":["Maschine so einstellen, dass die Drehachse auf Höhe des Kniegelenks liegt.","Beinpolster knapp oberhalb der Ferse an der Achillessehne anlegen.","Liegend: Hüfte flach auf dem Polster, Oberkörper abgelegt, Griffe fassen.","Sitzend: Rücken am Polster, Oberschenkelpolster fest auf den Oberschenkeln fixieren, Griffe fassen.","Beine in der Startposition fast gestreckt, Fußspitzen leicht angezogen."],"execution":["Fersen kontrolliert in Richtung Gesäß ziehen.","Becken bleibt dabei stabil auf oder am Polster.","In der Endposition kurz halten und die hinteren Oberschenkel anspannen.","Gewicht langsam zurückführen, bis die Beine fast gestreckt sind.","Gewicht nicht aufsetzen lassen, Spannung halten.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von fast gestreckten Beinen bis zu einem Kniewinkel von etwa 90 Grad oder enger, soweit das Becken stabil bleibt. Die Dehnung in der gestreckten Position bewusst kontrollieren.","breathing":"Beim Beugen ausatmen, beim Strecken einatmen.","common_mistakes":["Hüfte hebt sich liegend vom Polster ab, unterer Rücken überstreckt.","Gewicht wird mit Schwung nach oben gezogen.","Beine werden am Ende nicht wieder kontrolliert gestreckt.","Polster liegt zu hoch an der Wade, Hebel wird ungünstig.","Sitzend: Oberschenkelpolster zu locker, Oberschenkel heben sich ab."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Sitzende Variante erlaubt eine stärkere Dehnung, liegende Variante eine stärkere Endkontraktion; beide lassen sich abwechseln.","Einbeinige Ausführung, um Seitenunterschiede auszugleichen.","Fußspitzen gestreckt halten, um den Anteil der Waden zu verringern und die hinteren Oberschenkel stärker zu betonen."],"cable_setup":null}$seed$::jsonb);

-- Rumänisches Kreuzheben
select public.upsert_seed_exercise($seed${"slug":"rumaenisches-kreuzheben","name":"Rumänisches Kreuzheben","category":"hamstrings","equipment":"barbell","grip_id":null,"grip_notes":"Pronierter Griff etwa schulterbreit, Stange nah an den Oberschenkeln. Bei nachlassender Griffkraft Zughilfen nutzen.","primary_muscles":["hamstrings","glutes"],"secondary_muscles":["lower_back","forearms","upper_back"],"description":"Hüftdominante Beugebewegung mit der Langhantel, bei der die Knie leicht gebeugt bleiben und die Stange nah am Körper abgesenkt wird. Gut geeignet, um hintere Oberschenkel und Gesäß über eine Dehnung zu belasten.","setup":["Stange aus dem Rack oder vom Boden in den aufrechten Stand bringen, Füße hüftbreit.","Pronierter Griff etwa schulterbreit, Arme gestreckt, Stange liegt an den Oberschenkeln.","Knie leicht beugen und diesen Winkel während der Bewegung beibehalten.","Schulterblätter leicht nach hinten ziehen, Brust angehoben, Rücken neutral.","Rumpf anspannen, Gewicht auf der ganzen Fußsohle."],"execution":["Hüfte nach hinten schieben, Oberkörper neigt sich nach vorne.","Stange gleitet nah an den Oberschenkeln nach unten.","Rücken bleibt neutral, Blick folgt dem Oberkörper.","So tief absenken, wie der Rücken neutral bleibt und die Dehnung in den hinteren Oberschenkeln spürbar ist.","Hüfte nach vorne schieben und aufrichten, Gesäß anspannen.","Oben aufrecht stehen, unteren Rücken nicht überstrecken."],"range_of_motion":"Von der aufrechten Position bis die Stange etwa auf Höhe der Knie oder des oberen Schienbeins ist. Die Tiefe wird durch die neutrale Rückenposition begrenzt, nicht durch den Boden.","breathing":"Oben einatmen, während des Absenkens die Spannung halten, beim Aufrichten ausatmen.","common_mistakes":["Unterer Rücken rundet sich in der tiefen Position.","Stange entfernt sich vom Körper, Hebel auf den unteren Rücken steigt.","Knie werden stark gebeugt, Bewegung wird zur Kniebeuge.","Oben wird der untere Rücken überstreckt.","Schultern hängen nach vorne, Oberkörper verliert die Spannung."],"tips":["Technik zuerst mit leichtem Gewicht festigen und auf die Dehnung in den hinteren Oberschenkeln achten.","Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Zughilfen nutzen, wenn die Griffkraft vor den hinteren Oberschenkeln nachlässt.","Alternativ mit Kurzhanteln ausführen, wenn keine Langhantel verfügbar ist."],"cable_setup":null}$seed$::jsonb);

-- Hip Thrust
select public.upsert_seed_exercise($seed${"slug":"hip-thrust","name":"Hip Thrust","category":"glutes","equipment":"barbell","grip_id":null,"grip_notes":"Stange mit proniertem Griff etwa schulterbreit außen am Polster halten, nur zum Stabilisieren, nicht ziehen. Alternativ: Hip-Thrust-Maschine mit Gurt oder Polster über der Hüfte, Haltegriffe seitlich.","primary_muscles":["glutes"],"secondary_muscles":["hamstrings","quads"],"description":"Hüftstreckung gegen Widerstand mit dem oberen Rücken auf einer Bank und der Langhantel auf der Hüfte. Gut geeignet, um das Gesäß in der gestreckten Endposition stark zu belasten.","setup":["Stabile Bank quer hinter sich stellen, Höhe etwa Kniehöhe.","Polster auf die Stange legen und Stange über die Hüfte rollen.","Oberen Rücken unterhalb der Schulterblätter auf der Bankkante ablegen.","Füße hüftbreit so aufstellen, dass die Unterschenkel in der Endposition etwa senkrecht stehen.","Rippen nach unten, Kinn leicht eingezogen, Rumpf anspannen."],"execution":["Über die Fersen die Hüfte nach oben drücken.","Gesäß in der Endposition bewusst anspannen, Hüfte vollständig gestreckt.","Oben bilden Schultern, Hüfte und Knie eine Linie, unterer Rücken bleibt neutral.","Ein bis zwei Sekunden oben halten.","Hüfte kontrolliert absenken, bis die Stange knapp über dem Boden ist.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von knapp über dem Boden bis zur vollständigen Hüftstreckung. Die Endposition wird durch das Gesäß erreicht, nicht durch Überstrecken des unteren Rückens.","breathing":"Beim Hochdrücken ausatmen, beim Absenken einatmen.","common_mistakes":["Unterer Rücken wird oben überstreckt, statt die Hüfte zu strecken.","Kopf kippt nach hinten, Blick geht an die Decke.","Füße stehen zu weit vorne, Belastung geht in die hinteren Oberschenkel.","Füße stehen zu nah am Gesäß, Quadrizeps übernimmt.","Bewegung wird mit Schwung ausgeführt, keine Pause oben."],"tips":["Blick während der gesamten Bewegung in Richtung Knie halten.","Oben ein bis zwei Sekunden halten und das Gesäß bewusst anspannen.","Gewichtsscheiben mit Stoppern gegen Verrutschen sichern und Bank gegen Wegrutschen fixieren.","Zu Beginn Technik ohne Zusatzgewicht oder nur mit der Stange üben."],"cable_setup":null}$seed$::jsonb);

-- Kabel Kickback
select public.upsert_seed_exercise($seed${"slug":"kabel-kickback","name":"Kabel Kickback","category":"glutes","equipment":"cable","grip_id":"ankle_strap","grip_notes":"Fußschlaufe am Sprunggelenk des Arbeitsbeins befestigen, fest, aber nicht einschnürend. Hände stützen sich am Kabelturm ab. Alternativ eine gepolsterte Manschette nutzen, wenn vorhanden.","primary_muscles":["glutes"],"secondary_muscles":["hamstrings"],"description":"Einbeinige Hüftstreckung am unteren Kabelzug mit Fußschlaufe, bei der das Bein nach hinten-oben geführt wird. Gut geeignet als Isolationsübung für das Gesäß mit leichtem bis moderatem Gewicht.","setup":["Fußschlaufe am unteren Kabel einhängen und am Sprunggelenk des Arbeitsbeins befestigen.","Mit dem Gesicht zum Kabelturm stellen, Hände am Turm abstützen.","Oberkörper leicht nach vorne neigen, Rücken neutral, Rumpf anspannen.","Standbein leicht gebeugt, Gewicht auf der ganzen Fußsohle.","Arbeitsbein leicht vor dem Körper, Spannung im Kabel aufnehmen."],"execution":["Arbeitsbein kontrolliert nach hinten-oben führen, Knie bleibt fast gestreckt.","Bewegung kommt aus der Hüfte, Gesäß anspannen.","Becken bleibt stabil, unterer Rücken überstreckt nicht.","In der Endposition ein bis zwei Sekunden halten.","Bein langsam zurückführen, bis es leicht vor dem Körper ist.","Nach allen Wiederholungen die Seite wechseln."],"range_of_motion":"Vom leichten Vorschwung bis zur vollständigen Hüftstreckung. Die Höhe des Beins wird durch die stabile Beckenposition begrenzt, nicht durch Überstrecken des Rückens.","breathing":"Beim Führen des Beins nach hinten ausatmen, beim Zurückführen einatmen.","common_mistakes":["Unterer Rücken überstreckt, um das Bein höher zu bringen.","Bewegung wird mit Schwung aus dem Vorschwung ausgeführt.","Oberkörper dreht sich ein oder weicht zur Seite aus.","Knie des Arbeitsbeins beugt sich stark, Bewegung wird zum Beinbeugen.","Zu viel Gewicht, Bewegungsradius wird klein."],"tips":["Leichtes bis moderates Gewicht wählen und auf die Kontraktion im Gesäß konzentrieren.","Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Fußspitze des Arbeitsbeins leicht nach außen drehen, um das Gesäß stärker zu spüren.","Höhere Wiederholungszahlen (12 bis 20) sind bei dieser Übung sinnvoll."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einarmig mit einem Kabel","height":"Rolle ganz unten","grip_width":"Keine Griffarbeit, Fußschlaufe am Sprunggelenk; Hände stützen sich am Turm ab","body_position":"Stehend mit dem Gesicht zum Turm, Oberkörper leicht nach vorne geneigt, Rücken neutral, Rumpf angespannt, Hände am Turm","foot_position":"Standbein leicht gebeugt, Fuß flach auf dem Boden; Arbeitsbein mit Schlaufe leicht vor dem Körper","movement_direction":"Bein nach hinten-oben, in Verlängerung des Rumpfes","elbow_position":"Arme leicht gebeugt am Turm, dienen nur der Stabilisierung","end_position":"Bein hinter dem Körper, Hüfte vollständig gestreckt, Gesäß angespannt, Becken stabil","return":"Langsam und kontrolliert über etwa zwei Sekunden, bis das Bein leicht vor dem Körper ist, ohne dass das Gewicht aufsetzt"}}$seed$::jsonb);

-- Wadenheben stehend
select public.upsert_seed_exercise($seed${"slug":"wadenheben-stehend","name":"Wadenheben stehend","category":"calves","equipment":"machine","grip_id":null,"grip_notes":"Haltegriffe oder Schulterpolster der stehenden Wadenmaschine nutzen, Hände bleiben locker. Alternativ: Smith-Maschine mit Stange im Nacken oder Stufe mit Kurzhantel in einer Hand und Abstützen mit der anderen.","primary_muscles":["calves"],"secondary_muscles":[],"description":"Plantarflexion im Stand gegen Widerstand, bei der die gesamte Wadenmuskulatur einschließlich des zweigelenkigen Gastrocnemius belastet wird. Gut geeignet als Grundübung für die Waden.","setup":["Schulterpolster so einstellen, dass die Beine im Stand fast gestreckt sind und das Gewicht leicht abhebt.","Fußballen auf die Kante der Plattform stellen, Fersen frei, Füße hüftbreit.","Knie fast gestreckt, aber nicht durchgedrückt.","Rumpf anspannen, Oberkörper aufrecht.","Fersen kontrolliert absenken, um die Startposition in der Dehnung einzunehmen."],"execution":["Fersen so hoch wie möglich anheben, auf die Fußballen drücken.","In der oberen Position ein bis zwei Sekunden halten.","Fersen langsam absenken, bis eine deutliche Dehnung in der Wade spürbar ist.","In der unteren Position kurz halten, ohne zu federn.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Volle Dehnung unten mit Fersen deutlich unter der Plattformkante bis zum höchsten Punkt auf den Fußballen. Der Kniewinkel bleibt während der gesamten Bewegung gleich.","breathing":"Beim Anheben der Fersen ausatmen, beim Absenken einatmen.","common_mistakes":["Bewegung wird federnd und mit Schwung aus der Dehnung ausgeführt.","Knie werden während der Bewegung gebeugt und gestreckt.","Bewegungsradius ist zu klein, keine Dehnung unten.","Füße rutschen auf der Plattform nach vorne.","Oberkörper kippt nach vorne oder hinten."],"tips":["Oben kurze Pause einlegen, unten die Dehnung ein bis zwei Sekunden halten.","Höhere Wiederholungszahlen (12 bis 20) mit vollem Bewegungsradius sind bei Waden in der Regel sinnvoll.","Einbeinige Ausführung, um Seitenunterschiede auszugleichen.","Ohne Maschine: Stufe mit Kurzhantel in einer Hand, andere Hand stützt sich ab."],"cable_setup":null}$seed$::jsonb);

-- Wadenheben sitzend
select public.upsert_seed_exercise($seed${"slug":"wadenheben-sitzend","name":"Wadenheben sitzend","category":"calves","equipment":"machine","grip_id":null,"grip_notes":"Haltegriffe am Oberschenkelpolster fassen, um das Polster zu sichern und den Oberkörper stabil zu halten. Hände bleiben locker, keine Zugarbeit.","primary_muscles":["calves"],"secondary_muscles":[],"description":"Plantarflexion im Sitzen gegen Widerstand mit gebeugten Knien, bei der vor allem der Soleus belastet wird, weil der Gastrocnemius durch die Kniebeugung entlastet ist. Sinnvolle Ergänzung zum stehenden Wadenheben.","setup":["Polster so einstellen, dass es fest auf dem unteren Oberschenkel knapp oberhalb der Knie aufliegt.","Fußballen auf die Kante der Plattform stellen, Fersen frei, Füße hüftbreit.","Knie etwa im rechten Winkel, Oberkörper aufrecht.","Haltegriffe fassen und die Sicherung der Maschine lösen.","Fersen kontrolliert absenken, um die Startposition in der Dehnung einzunehmen."],"execution":["Fersen so hoch wie möglich anheben, auf die Fußballen drücken.","In der oberen Position ein bis zwei Sekunden halten.","Fersen langsam absenken, bis eine deutliche Dehnung in der Wade spürbar ist.","Unten kurz halten, ohne zu federn.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Volle Dehnung unten bis zum höchsten Punkt auf den Fußballen. Der Kniewinkel bleibt während der gesamten Bewegung gleich, damit der Soleus gezielt arbeitet.","breathing":"Beim Anheben der Fersen ausatmen, beim Absenken einatmen.","common_mistakes":["Bewegung wird federnd und mit Schwung aus der Dehnung ausgeführt.","Bewegungsradius ist zu klein, keine Dehnung unten.","Polster liegt zu weit oben auf dem Oberschenkel, Hebel wird ungünstig.","Oberkörper wird nach vorne gebeugt, um mit dem Rücken mitzuhelfen."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Höhere Wiederholungszahlen (12 bis 20) mit vollem Bewegungsradius sind hier sinnvoll.","Mit stehendem Wadenheben kombinieren, um Gastrocnemius und Soleus gemeinsam zu trainieren."],"cable_setup":null}$seed$::jsonb);

-- Incline Curl
select public.upsert_seed_exercise($seed${"slug":"incline-curl","name":"Incline Curl","category":"biceps","equipment":"dumbbell","grip_id":null,"grip_notes":"Supinierter Griff (Handflächen zeigen nach vorne bzw. oben), Kurzhanteln locker aber sicher umschließen. Handgelenke gerade halten, nicht einknicken.","primary_muscles":["biceps"],"secondary_muscles":["forearms"],"description":"Kurzhantelcurl auf der Schrägbank, bei dem die Arme seitlich und leicht hinter dem Körper hängen. Durch die vorgedehnte Position wird der Bizeps über einen großen Bewegungsradius belastet.","setup":["Rückenlehne der Bank auf etwa 45 bis 60 Grad einstellen.","Kurzhanteln aufnehmen und sich mit dem Rücken vollständig an die Lehne setzen.","Kopf und oberer Rücken liegen an, Füße flach auf dem Boden.","Arme seitlich und leicht hinter der Körperlinie hängen lassen, Handflächen zeigen nach vorne.","Schultern nach hinten und unten ziehen, Oberarme ruhig halten."],"execution":["Kurzhanteln kontrolliert nach oben curlen, nur der Unterarm bewegt sich.","Oberarme bleiben während der gesamten Bewegung an ihrer Position.","In der oberen Position den Bizeps kurz bewusst anspannen.","Gewicht langsam absenken, bis die Arme fast gestreckt sind.","Am unteren Ende die Dehnung im Bizeps spüren, ohne die Ellenbogen hart durchzustrecken.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von fast gestreckten Armen in der gedehnten Position bis zur vollen Beugung, soweit die Oberarme an ihrer Position bleiben. Unten nicht in die Ellenbogen fallen lassen.","breathing":"Beim Curlen ausatmen, beim Absenken einatmen.","common_mistakes":["Oberarme wandern beim Curlen nach vorne, dadurch geht die Vordehnung verloren.","Schultern rollen nach vorne und lösen sich von der Lehne.","Gewicht wird unten fallen gelassen statt kontrolliert abgesenkt.","Handgelenke knicken beim Curlen nach innen ein.","Zu viel Gewicht, sodass der Oberkörper mitschwingt."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Eher leichteres Gewicht wählen als bei stehenden Curls, da die gedehnte Position mehr fordert.","Wenn die Schulter in der gedehnten Position unangenehm ist, Bank etwas steiler stellen."],"cable_setup":null}$seed$::jsonb);

-- Incline Curl hinterm Körper
select public.upsert_seed_exercise($seed${"slug":"incline-curl-hinterm-koerper","name":"Incline Curl hinterm Körper","category":"biceps","equipment":"dumbbell","grip_id":null,"grip_notes":"Supinierter Griff, Handflächen zeigen während der gesamten Bewegung nach vorne bzw. oben. Handgelenke gerade, kein Umklappen in der oberen Position.","primary_muscles":["biceps"],"secondary_muscles":["forearms","front_delts"],"description":"Variante des Incline Curls mit steilerer Bank, bei der die Oberarme bewusst hinter der Körperlinie bleiben. Dadurch wird der lange Bizepskopf in einer stark gedehnten Position belastet.","setup":["Rückenlehne der Bank auf etwa 60 bis 75 Grad einstellen.","Kurzhanteln aufnehmen und sich mit Rücken und Kopf vollständig anlehnen.","Füße flach auf den Boden stellen, Rumpf anspannen.","Arme hängen lassen und die Oberarme bewusst leicht hinter die Körperlinie bringen.","Schultern nach hinten und unten ziehen, Brust leicht anheben."],"execution":["Kurzhanteln kontrolliert nach oben curlen, Ellenbogen bleiben hinter der Körperlinie.","Nur der Unterarm bewegt sich, der Oberarm bleibt an seiner Position.","Oben den Bizeps kurz anspannen, ohne die Ellenbogen nach vorne zu ziehen.","Gewicht langsam absenken und die Dehnung im Bizeps zulassen.","Unten kurz vor der vollen Streckung stoppen und Spannung halten.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von fast gestreckten Armen in starker Vordehnung bis zu einer Beugung von etwa 90 bis 110 Grad. Die obere Position ist bewusst kürzer, da die Oberarme hinten bleiben.","breathing":"Beim Curlen ausatmen, beim Absenken einatmen.","common_mistakes":["Ellenbogen wandern beim Curlen nach vorne, dadurch entspricht die Übung einem normalen Incline Curl.","Schultern rollen nach vorne, um das Gewicht leichter zu bewegen.","Bank zu flach eingestellt, sodass die Arme nicht hinter die Körperlinie kommen.","Zu viel Gewicht, der Bewegungsradius wird unten verkürzt.","Handgelenke klappen oben nach innen."],"tips":["Deutlich leichteres Gewicht als beim Kurzhantelcurl wählen, die gedehnte Position ist anspruchsvoll.","Exzentrische Phase etwa drei Sekunden lang ausführen.","Vorstellen, die Ellenbogen während der ganzen Wiederholung nach hinten zu drücken.","Bei Beschwerden in der vorderen Schulter die Bank etwas flacher stellen."],"cable_setup":null}$seed$::jsonb);

-- Hammercurl Kabel
select public.upsert_seed_exercise($seed${"slug":"hammercurl-kabel","name":"Hammercurl Kabel","category":"biceps","equipment":"cable","grip_id":"rope","grip_notes":"Neutraler Griff am Seil (Daumen zeigen nach oben), Seilenden etwa schulterbreit fassen. Alternativ: einzelner Griff mit neutraler Handstellung einarmig.","primary_muscles":["biceps","forearms"],"secondary_muscles":[],"description":"Curl am Kabelzug mit neutralem Griff am Seil, der neben dem Bizeps vor allem den Brachialis und den Brachioradialis belastet. Durch das Kabel bleibt die Spannung über den gesamten Bewegungsradius erhalten.","setup":["Seil am unteren Kabel einhängen und Gewicht einstellen.","Seilenden mit neutralem Griff fassen, Daumen zeigen nach oben.","Einen Schritt vom Turm zurücktreten, bis das Gewicht leicht angehoben ist.","Aufrecht stehen, Füße etwa hüftbreit, Knie leicht gebeugt.","Ellenbogen seitlich am Körper, Schultern nach hinten und unten."],"execution":["Seil kontrolliert nach oben curlen, Handstellung bleibt neutral.","Ellenbogen bleiben am Körper und wandern nicht nach vorne.","In der oberen Position kurz halten und Oberarm anspannen.","Gewicht langsam absenken, bis die Arme fast gestreckt sind.","Spannung am unteren Ende halten, das Gewicht nicht aufsetzen lassen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von fast gestreckten Armen bis zur vollen Beugung, soweit die Ellenbogen am Körper bleiben. Das Gewicht sollte unten nicht auf dem Stapel aufliegen.","breathing":"Beim Curlen ausatmen, beim Absenken einatmen.","common_mistakes":["Ellenbogen wandern nach vorne, dadurch arbeitet die vordere Schulter mit.","Oberkörper lehnt sich zurück und erzeugt Schwung.","Handgelenke drehen oben in eine supinierte Position.","Gewicht fällt unten auf den Stapel zurück.","Schultern ziehen beim Curlen nach oben."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Für mehr Betonung des Brachioradialis die Seilenden am Ende leicht auseinanderziehen.","Wenn der Oberkörper mitschwingt, Gewicht reduzieren oder mit dem Rücken an eine Stütze stellen."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einzelnes Kabel","height":"Rolle ganz unten","grip_width":"Neutral am Seil, etwa schulterbreit, Daumen zeigen nach oben","body_position":"Aufrecht stehend, etwa einen Schritt vom Turm entfernt, leichte Vorlage, Rumpf stabil","foot_position":"Füße hüftbreit, parallel oder leichte Schrittstellung, Knie leicht gebeugt","movement_direction":"Von unten nach oben in Richtung Schultern, Unterarm rotiert um den Ellenbogen","elbow_position":"Ellenbogen seitlich am Körper, bleiben während der Bewegung an ihrer Position","end_position":"Hände etwa auf Höhe der Schultern, Unterarme vollständig gebeugt, Oberarm angespannt","return":"Langsam und kontrolliert bis fast zur vollen Streckung, Gewicht bleibt in der Luft"}}$seed$::jsonb);

-- Kabelcurl
select public.upsert_seed_exercise($seed${"slug":"kabelcurl","name":"Kabelcurl","category":"biceps","equipment":"cable","grip_id":"straight_bar","grip_notes":"Supinierter Griff an der geraden Stange, etwa schulterbreit. Alternativ: EZ-Stange, wenn die Handgelenke bei gerader Stange unangenehm belastet werden.","primary_muscles":["biceps"],"secondary_muscles":["forearms"],"description":"Stehender Bizepscurl am unteren Kabelzug mit gerader Stange. Das Kabel hält die Spannung über den gesamten Bewegungsradius, auch in der oberen Position.","setup":["Gerade Stange am unteren Kabel einhängen und Gewicht einstellen.","Stange mit supiniertem Griff etwa schulterbreit fassen.","Einen Schritt vom Turm zurücktreten, bis das Gewicht leicht angehoben ist.","Aufrecht stehen, Füße hüftbreit, Knie leicht gebeugt, Rumpf angespannt.","Ellenbogen seitlich am Körper, Schultern nach hinten und unten."],"execution":["Stange kontrolliert nach oben curlen, nur die Unterarme bewegen sich.","Ellenbogen bleiben am Körper und wandern nicht nach vorne oder hinten.","In der oberen Position kurz halten und den Bizeps anspannen.","Stange langsam absenken, bis die Arme fast gestreckt sind.","Unten Spannung halten, Gewicht nicht auf dem Stapel aufsetzen lassen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von fast gestreckten Armen bis zur vollen Beugung, soweit die Ellenbogen an ihrer Position bleiben. Oben nicht die Ellenbogen anheben, um die Stange höher zu bringen.","breathing":"Beim Curlen ausatmen, beim Absenken einatmen.","common_mistakes":["Oberkörper lehnt sich zurück und erzeugt Schwung aus der Hüfte.","Ellenbogen wandern nach vorne, um die Stange höher zu bringen.","Handgelenke knicken oben nach innen ein.","Gewicht fällt unten unkontrolliert zurück.","Schultern ziehen während des Curls nach oben."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren.","Bei Beschwerden in den Handgelenken auf die EZ-Stange wechseln.","Wenn der Oberkörper mitschwingt, Gewicht reduzieren oder mit dem Rücken an eine Stütze stellen.","Erst Gewicht erhöhen, wenn alle Sätze ohne Schwung ausgeführt werden."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einzelnes Kabel","height":"Rolle ganz unten","grip_width":"Schulterbreit, supiniert (Handflächen nach oben), an gerader Stange oder EZ-Stange","body_position":"Aufrecht stehend, etwa einen Schritt vom Turm entfernt, Rumpf angespannt, Oberkörper ruhig","foot_position":"Füße hüftbreit, parallel, Knie leicht gebeugt","movement_direction":"Von unten nach oben in Richtung Schultern, Unterarm rotiert um den Ellenbogen","elbow_position":"Ellenbogen seitlich am Körper, bleiben während der Bewegung an ihrer Position","end_position":"Stange etwa auf Höhe der oberen Brust, Unterarme vollständig gebeugt, Bizeps angespannt","return":"Langsam und kontrolliert bis fast zur vollen Streckung, Gewicht bleibt in der Luft"}}$seed$::jsonb);

-- Kurzhantelcurl
select public.upsert_seed_exercise($seed${"slug":"kurzhantelcurl","name":"Kurzhantelcurl","category":"biceps","equipment":"dumbbell","grip_id":null,"grip_notes":"Supinierter Griff, Handflächen zeigen nach oben. Alternativ: Start mit neutraler Handstellung und Drehen der Hand während des Curls (Supination). Handgelenke gerade halten.","primary_muscles":["biceps"],"secondary_muscles":["forearms"],"description":"Klassischer Bizepscurl mit Kurzhanteln, stehend oder sitzend, beidarmig oder im Wechsel. Grundübung für den Bizeps mit freier Bewegung und ohne Gerätebindung.","setup":["Kurzhanteln aufnehmen und aufrecht stehen oder auf einer Bank mit aufrechter Lehne sitzen.","Füße hüftbreit, Knie leicht gebeugt, Rumpf angespannt.","Arme hängen gestreckt seitlich am Körper, Handflächen zeigen nach vorne.","Schultern nach hinten und unten ziehen, Brust leicht anheben.","Ellenbogen leicht vor der Körpermitte, nah am Rumpf."],"execution":["Kurzhanteln kontrolliert nach oben curlen, beidarmig oder im Wechsel.","Oberarme bleiben an ihrer Position, nur die Unterarme bewegen sich.","In der oberen Position den Bizeps kurz anspannen.","Gewicht langsam absenken, bis die Arme fast gestreckt sind.","Unten nicht in die Ellenbogen fallen lassen, Spannung halten.","Nächste Wiederholung ohne Schwung aus Hüfte oder Rücken beginnen."],"range_of_motion":"Von fast gestreckten Armen bis zur vollen Beugung, soweit die Oberarme an ihrer Position bleiben. Die Hantel muss oben nicht die Schulter berühren.","breathing":"Beim Curlen ausatmen, beim Absenken einatmen.","common_mistakes":["Oberkörper schwingt zurück, um das Gewicht in Bewegung zu bringen.","Ellenbogen wandern nach vorne, dadurch arbeitet die vordere Schulter mit.","Handgelenke knicken oben nach innen ein.","Gewicht wird unten fallen gelassen statt kontrolliert abgesenkt.","Im Wechsel wird der ruhende Arm vollständig entspannt."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Sitzende Ausführung reduziert Schwung aus dem Oberkörper.","Beim Curl im Wechsel den ruhenden Arm leicht gebeugt und unter Spannung halten.","Erst Gewicht erhöhen, wenn alle Sätze ohne Schwung ausgeführt werden."],"cable_setup":null}$seed$::jsonb);

-- Trizepsdrücken Kabel
select public.upsert_seed_exercise($seed${"slug":"trizepsdruecken-kabel","name":"Trizepsdrücken Kabel","category":"triceps","equipment":"cable","grip_id":"v_bar_triceps","grip_notes":"Neutraler Griff an der V-förmigen Trizepsstange, Handgelenke gerade. Alternativ: Seil oder gerade Stange, je nach Verfügbarkeit und Handgelenkskomfort.","primary_muscles":["triceps"],"secondary_muscles":[],"description":"Trizepsdrücken am oberen Kabelzug mit der V-förmigen Trizepsstange. Der neutrale Griff ist handgelenkschonend und erlaubt eine stabile Führung der Bewegung.","setup":["V-förmige Trizepsstange am oberen Kabel einhängen und Gewicht einstellen.","Stange mit neutralem Griff fassen, Handgelenke gerade.","Einen kleinen Schritt vom Turm zurücktreten, Oberkörper leicht nach vorne neigen.","Füße hüftbreit oder in leichter Schrittstellung, Knie leicht gebeugt.","Ellenbogen seitlich am Körper fixieren, Schultern nach hinten und unten."],"execution":["Stange kontrolliert nach unten drücken, bis die Arme gestreckt sind.","Ellenbogen bleiben am Körper, nur die Unterarme bewegen sich.","In der unteren Position den Trizeps kurz anspannen.","Gewicht langsam zurückführen, bis die Unterarme etwa waagerecht oder etwas höher sind.","Oben Spannung halten, das Gewicht nicht auf dem Stapel aufsetzen lassen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer Beugung von etwa 90 Grad oder etwas mehr bis zur vollen Streckung. Die Ellenbogen bleiben dabei die gesamte Zeit an ihrer Position.","breathing":"Beim Drücken nach unten ausatmen, beim Zurückführen einatmen.","common_mistakes":["Ellenbogen wandern nach vorne oder außen, dadurch arbeitet die Schulter mit.","Oberkörper drückt mit und erzeugt Schwung von oben.","Gewicht fällt oben unkontrolliert zurück.","Handgelenke knicken unten ein.","Schultern ziehen nach oben."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Vorstellen, die Ellenbogen an die Rippen zu klemmen.","Wenn der Oberkörper mitdrückt, Gewicht reduzieren."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einzelnes Kabel","height":"Rolle ganz oben","grip_width":"Neutral an der V-förmigen Trizepsstange, Hände eng beieinander","body_position":"Stehend, leichte Vorlage von etwa 10 bis 20 Grad, Rumpf angespannt, Oberkörper ruhig","foot_position":"Füße hüftbreit oder leichte Schrittstellung, Knie leicht gebeugt","movement_direction":"Von oben nach unten, Unterarm rotiert um den Ellenbogen","elbow_position":"Ellenbogen seitlich am Körper fixiert, bleiben während der Bewegung an ihrer Position","end_position":"Arme vollständig gestreckt, Stange etwa auf Höhe der Oberschenkel, Trizeps angespannt","return":"Langsam und kontrolliert, bis die Unterarme etwa waagerecht sind, Gewicht bleibt in der Luft"}}$seed$::jsonb);

-- Trizepsdrücken Stange
select public.upsert_seed_exercise($seed${"slug":"trizepsdruecken-stange","name":"Trizepsdrücken Stange","category":"triceps","equipment":"cable","grip_id":"straight_bar","grip_notes":"Pronierter Griff (Handflächen nach unten), etwa schulterbreit. Alternativ: EZ-Stange, wenn die Handgelenke bei gerader Stange unangenehm belastet werden.","primary_muscles":["triceps"],"secondary_muscles":["forearms"],"description":"Trizepsdrücken am oberen Kabelzug mit gerader Stange und proniertem Griff. Erlaubt eine stabile beidarmige Ausführung und eine gute Kontrolle des Gewichts.","setup":["Gerade Stange am oberen Kabel einhängen und Gewicht einstellen.","Stange mit proniertem Griff etwa schulterbreit fassen.","Einen kleinen Schritt vom Turm zurücktreten, Oberkörper leicht nach vorne neigen.","Füße hüftbreit oder in leichter Schrittstellung, Knie leicht gebeugt.","Ellenbogen seitlich am Körper fixieren, Schultern nach hinten und unten."],"execution":["Stange kontrolliert nach unten drücken, bis die Arme gestreckt sind.","Ellenbogen bleiben am Körper, nur die Unterarme bewegen sich.","Unten den Trizeps kurz anspannen, Handgelenke gerade halten.","Gewicht langsam zurückführen, bis die Unterarme etwa waagerecht oder etwas höher sind.","Oben Spannung halten, das Gewicht nicht auf dem Stapel aufsetzen lassen.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer Beugung von etwa 90 Grad oder etwas mehr bis zur vollen Streckung. Die Ellenbogen bleiben dabei an ihrer Position.","breathing":"Beim Drücken nach unten ausatmen, beim Zurückführen einatmen.","common_mistakes":["Ellenbogen wandern nach vorne oder außen.","Oberkörper drückt mit und erzeugt Schwung von oben.","Handgelenke knicken unten nach unten ab.","Gewicht fällt oben unkontrolliert zurück.","Griff zu breit, dadurch weichen die Ellenbogen nach außen."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Bei Beschwerden in den Handgelenken auf die EZ-Stange oder das Seil wechseln.","Vorstellen, die Ellenbogen an die Rippen zu klemmen.","Wenn der Oberkörper mitdrückt, Gewicht reduzieren."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einzelnes Kabel","height":"Rolle ganz oben","grip_width":"Schulterbreit, proniert (Handflächen nach unten), an gerader Stange oder EZ-Stange","body_position":"Stehend, leichte Vorlage von etwa 10 bis 20 Grad, Rumpf angespannt, Oberkörper ruhig","foot_position":"Füße hüftbreit oder leichte Schrittstellung, Knie leicht gebeugt","movement_direction":"Von oben nach unten, Unterarm rotiert um den Ellenbogen","elbow_position":"Ellenbogen seitlich am Körper fixiert, bleiben während der Bewegung an ihrer Position","end_position":"Arme vollständig gestreckt, Stange etwa auf Höhe der Oberschenkel, Trizeps angespannt","return":"Langsam und kontrolliert, bis die Unterarme etwa waagerecht sind, Gewicht bleibt in der Luft"}}$seed$::jsonb);

-- Trizepsdrücken Seil
select public.upsert_seed_exercise($seed${"slug":"trizepsdruecken-seil","name":"Trizepsdrücken Seil","category":"triceps","equipment":"cable","grip_id":"rope","grip_notes":"Neutraler Griff am Seil, Seilenden fest umschließen. Alternativ: V-förmige Trizepsstange, wenn kein Seil verfügbar ist.","primary_muscles":["triceps"],"secondary_muscles":[],"description":"Trizepsdrücken am oberen Kabelzug mit Seil, bei dem die Seilenden am Ende der Bewegung auseinandergezogen werden. Erlaubt eine vollständige Streckung und eine deutliche Endkontraktion des Trizeps.","setup":["Seil am oberen Kabel einhängen und Gewicht einstellen.","Seilenden mit neutralem Griff fassen, Daumen zeigen nach oben.","Einen kleinen Schritt vom Turm zurücktreten, Oberkörper leicht nach vorne neigen.","Füße hüftbreit oder in leichter Schrittstellung, Knie leicht gebeugt.","Ellenbogen seitlich am Körper fixieren, Schultern nach hinten und unten."],"execution":["Seil kontrolliert nach unten drücken, Ellenbogen bleiben am Körper.","Kurz vor der vollen Streckung die Seilenden nach außen auseinanderziehen.","In der unteren Position den Trizeps kurz anspannen, Handrücken zeigen nach außen.","Hände wieder zusammenführen und das Gewicht langsam zurückführen.","Oben stoppen, wenn die Unterarme etwa waagerecht oder etwas höher sind.","Spannung halten und die nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer Beugung von etwa 90 Grad oder etwas mehr bis zur vollen Streckung mit auseinandergezogenen Seilenden. Die Ellenbogen bleiben dabei an ihrer Position.","breathing":"Beim Drücken nach unten ausatmen, beim Zurückführen einatmen.","common_mistakes":["Seilenden werden nicht auseinandergezogen, die Endkontraktion fehlt.","Ellenbogen wandern nach vorne oder außen.","Oberkörper drückt mit und erzeugt Schwung von oben.","Gewicht fällt oben unkontrolliert zurück.","Schultern ziehen während der Bewegung nach oben."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Das Auseinanderziehen der Seilenden erst kurz vor der vollen Streckung beginnen.","Wenn der Oberkörper mitdrückt, Gewicht reduzieren."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einzelnes Kabel","height":"Rolle ganz oben","grip_width":"Neutral am Seil, Hände oben eng beieinander, unten auseinandergezogen","body_position":"Stehend, leichte Vorlage von etwa 10 bis 20 Grad, Rumpf angespannt, Oberkörper ruhig","foot_position":"Füße hüftbreit oder leichte Schrittstellung, Knie leicht gebeugt","movement_direction":"Von oben nach unten, am Ende leicht nach außen zu den Seiten der Oberschenkel","elbow_position":"Ellenbogen seitlich am Körper fixiert, bleiben während der Bewegung an ihrer Position","end_position":"Arme vollständig gestreckt, Seilenden seitlich neben den Oberschenkeln, Trizeps angespannt","return":"Hände zusammenführen, langsam und kontrolliert zurück bis die Unterarme etwa waagerecht sind"}}$seed$::jsonb);

-- Überkopf Trizeps Extension
select public.upsert_seed_exercise($seed${"slug":"ueberkopf-trizeps-extension","name":"Überkopf Trizeps Extension","category":"triceps","equipment":"cable","grip_id":"rope","grip_notes":"Neutraler Griff am Seil, Seilenden fest umschließen, Handgelenke gerade. Alternativ: einzelner Griff für die einarmige Ausführung.","primary_muscles":["triceps"],"secondary_muscles":[],"description":"Trizepsstreckung über dem Kopf am Kabelzug, bei der die Oberarme neben dem Kopf gehalten werden. Durch die gestreckte Schulterposition wird vor allem der lange Trizepskopf belastet.","setup":["Seil am Kabel einhängen und Rolle unten oder auf Hüfthöhe einstellen.","Seil fassen, sich mit dem Rücken zum Turm drehen und in Schrittstellung gehen.","Hände mit dem Seil hinter den Kopf bringen, Ellenbogen zeigen nach vorne-oben.","Oberkörper leicht nach vorne neigen, Rumpf anspannen, Rücken gerade.","Oberarme neben dem Kopf ruhig halten, Schultern nach unten ziehen."],"execution":["Arme kontrolliert nach vorne-oben strecken, Oberarme bleiben an ihrer Position.","Nur die Unterarme bewegen sich, Ellenbogen zeigen weiter nach vorne-oben.","In der gestreckten Position den Trizeps kurz anspannen.","Gewicht langsam zurückführen und die Dehnung im Trizeps zulassen.","Hinten stoppen, wenn die Unterarme etwa parallel zum Oberarm sind.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer vollständigen Beugung mit gedehntem Trizeps hinter dem Kopf bis zur vollen Streckung nach vorne-oben. Die Oberarme bleiben dabei neben dem Kopf.","breathing":"Beim Strecken ausatmen, beim Zurückführen einatmen.","common_mistakes":["Ellenbogen weichen seitlich nach außen aus.","Oberarme wandern beim Strecken nach unten, dadurch wird die Bewegung zum Drücken.","Unterer Rücken fällt ins Hohlkreuz, Rumpfspannung fehlt.","Gewicht fällt hinten unkontrolliert zurück.","Zu viel Gewicht, der Bewegungsradius hinten wird verkürzt."],"tips":["Exzentrische Phase etwa zwei bis drei Sekunden lang kontrollieren und die Dehnung bewusst zulassen.","Eher leichteres Gewicht wählen, die gedehnte Position des langen Kopfes ist anspruchsvoll.","Bauch anspannen, um ein Hohlkreuz zu vermeiden.","Bei Beschwerden in der Schulter die Rolle etwas höher einstellen."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einzelnes Kabel","height":"Rolle ganz unten oder auf Hüfthöhe","grip_width":"Neutral am Seil, Hände eng beieinander, Daumen zeigen nach oben","body_position":"Mit dem Rücken zum Turm stehend, Oberkörper leicht nach vorne geneigt, Rumpf angespannt, Rücken gerade","foot_position":"Schrittstellung, vorderes Bein leicht gebeugt, hinteres Bein gestreckt für Stabilität","movement_direction":"Von hinter dem Kopf nach vorne-oben, Unterarm rotiert um den Ellenbogen","elbow_position":"Ellenbogen neben dem Kopf, zeigen nach vorne-oben, bleiben an ihrer Position","end_position":"Arme vollständig gestreckt nach vorne-oben, Trizeps angespannt, Oberarme weiter neben dem Kopf","return":"Langsam und kontrolliert, bis die Unterarme hinter dem Kopf etwa parallel zu den Oberarmen sind"}}$seed$::jsonb);

-- Kabel Extension einarmig
select public.upsert_seed_exercise($seed${"slug":"kabel-extension-einarmig","name":"Kabel Extension einarmig","category":"triceps","equipment":"cable","grip_id":"single_handle","grip_notes":"Einzelner Griff mit neutraler oder pronierter Handstellung, je nach Komfort. Alternativ: Seil mit nur einer Hand fassen oder ohne Griff direkt am Kabelende greifen.","primary_muscles":["triceps"],"secondary_muscles":[],"description":"Einarmiges Trizepsdrücken am oberen Kabelzug, bei dem die freie Hand am Turm stützt. Erlaubt eine gezielte Arbeit pro Seite und den Ausgleich von Kraftunterschieden.","setup":["Einzelnen Griff am oberen Kabel einhängen und Gewicht einstellen.","Griff mit einer Hand fassen, neutrale oder pronierte Handstellung.","Einen kleinen Schritt vom Turm zurücktreten, Oberkörper leicht nach vorne neigen.","Freie Hand zur Stabilisierung am Turm abstützen.","Ellenbogen des arbeitenden Arms seitlich am Körper fixieren, Schulter nach unten."],"execution":["Griff kontrolliert nach unten drücken, bis der Arm gestreckt ist.","Ellenbogen bleibt am Körper, nur der Unterarm bewegt sich.","Unten den Trizeps kurz anspannen.","Gewicht langsam zurückführen, bis der Unterarm etwa waagerecht oder etwas höher ist.","Oben Spannung halten, das Gewicht nicht auf dem Stapel aufsetzen lassen.","Nach dem Satz die Seite wechseln."],"range_of_motion":"Von einer Beugung von etwa 90 Grad oder etwas mehr bis zur vollen Streckung. Der Ellenbogen bleibt dabei an seiner Position.","breathing":"Beim Drücken nach unten ausatmen, beim Zurückführen einatmen.","common_mistakes":["Ellenbogen wandert nach vorne oder außen.","Oberkörper dreht sich zur arbeitenden Seite und erzeugt Schwung.","Schulter zieht nach oben.","Gewicht fällt oben unkontrolliert zurück.","Zu viel Gewicht, sodass der Rumpf mitarbeitet."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Mit der schwächeren Seite beginnen und die Wiederholungszahl auf der stärkeren Seite daran anpassen.","Vorstellen, den Ellenbogen an die Rippen zu klemmen."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einzelnes Kabel","height":"Rolle ganz oben","grip_width":"Einzelner Griff, neutral oder proniert, Handgelenk gerade","body_position":"Stehend, leichte Vorlage von etwa 10 bis 20 Grad, freie Hand am Turm abgestützt, Rumpf angespannt","foot_position":"Füße hüftbreit oder leichte Schrittstellung, Knie leicht gebeugt","movement_direction":"Von oben nach unten, Unterarm rotiert um den Ellenbogen","elbow_position":"Ellenbogen seitlich am Körper fixiert, bleibt während der Bewegung an seiner Position","end_position":"Arm vollständig gestreckt, Griff etwa auf Höhe des Oberschenkels, Trizeps angespannt","return":"Langsam und kontrolliert, bis der Unterarm etwa waagerecht ist, Gewicht bleibt in der Luft"}}$seed$::jsonb);

-- Crunch Maschine
select public.upsert_seed_exercise($seed${"slug":"crunch-maschine","name":"Crunch Maschine","category":"abs","equipment":"machine","grip_id":null,"grip_notes":"Griffe oder Polster je nach Maschine locker halten, nicht mit den Armen ziehen. Bei Brustpolster die Arme nur zur Fixierung auflegen.","primary_muscles":["abs"],"secondary_muscles":["obliques"],"description":"Geführte Crunch-Bewegung an der Maschine, bei der der Widerstand über einen Gewichtsstapel eingestellt wird. Gut geeignet, um die Bauchmuskulatur mit Zusatzgewicht gezielt zu trainieren.","setup":["Sitz so einstellen, dass die Drehachse der Maschine etwa auf Höhe des unteren Brustkorbs liegt.","Füße unter die Fußpolster bringen oder flach auf den Boden stellen.","Griffe oder Brustpolster locker fassen bzw. anlegen.","Rücken an das Polster lehnen, Schultern locker.","Leichtes Gewicht wählen, bis der Bewegungsablauf sicher sitzt."],"execution":["Oberkörper kontrolliert nach vorne einrollen, Bewegung aus der Brustwirbelsäule.","Brustbein in Richtung Becken ziehen, der Rücken wird dabei rund.","In der Endposition den Bauch kurz bewusst anspannen.","Gewicht langsam zurückführen, ohne den Rücken ins Hohlkreuz zu bringen.","Oben stoppen, bevor das Gewicht auf dem Stapel aufsetzt.","Nächste Wiederholung ohne Schwung beginnen."],"range_of_motion":"Von einer leicht gestreckten Ausgangsposition bis zum vollständig eingerollten Oberkörper. Die Bewegung kommt aus der Brustwirbelsäule, nicht aus der Hüfte.","breathing":"Beim Einrollen ausatmen, beim Zurückführen einatmen.","common_mistakes":["Bewegung kommt aus der Hüfte statt aus der Wirbelsäule, die Hüftbeuger arbeiten statt des Bauchs.","Mit den Armen an den Griffen gezogen statt mit dem Bauch eingerollt.","Gewicht fällt oben unkontrolliert zurück.","Zu viel Gewicht, der Bewegungsradius wird klein.","Luft wird während der Bewegung angehalten."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Beim Einrollen bewusst ausatmen, das unterstützt die Anspannung des Bauchs.","Lieber leichtes Gewicht mit vollem Bewegungsradius als schweres Gewicht mit kurzer Bewegung.","Vorstellen, die Rippen in Richtung Becken zu ziehen."],"cable_setup":null}$seed$::jsonb);

-- Kabel Crunch
select public.upsert_seed_exercise($seed${"slug":"kabel-crunch","name":"Kabel Crunch","category":"abs","equipment":"cable","grip_id":"rope","grip_notes":"Seil mit neutralem Griff fassen und die Hände seitlich am Kopf oder im Nacken halten. Alternativ: Griff an der Stirn abstützen, Position während des Satzes nicht verändern.","primary_muscles":["abs"],"secondary_muscles":["obliques"],"description":"Kniender Crunch am oberen Kabelzug, bei dem der Oberkörper gegen den Widerstand des Kabels eingerollt wird. Erlaubt eine gut steuerbare Belastung der Bauchmuskulatur mit Zusatzgewicht.","setup":["Seil am oberen Kabel einhängen und Gewicht einstellen.","Seil fassen und sich mit dem Gesicht zum Turm hinknien, etwa eine Armlänge entfernt.","Hände mit dem Seil seitlich am Kopf oder im Nacken halten.","Hüfte in einer stabilen Position fixieren, Oberschenkel etwa senkrecht.","Oberkörper aufrecht, leichte Vorspannung im Bauch."],"execution":["Oberkörper kontrolliert nach unten einrollen, Bewegung aus der Brustwirbelsäule.","Ellenbogen in Richtung Oberschenkel führen, der Rücken wird dabei rund.","Hüfte bleibt während der Bewegung an ihrer Position.","In der Endposition den Bauch kurz bewusst anspannen.","Oberkörper langsam wieder aufrichten, Spannung im Bauch halten.","Oben stoppen, bevor das Gewicht auf dem Stapel aufsetzt."],"range_of_motion":"Von einem aufrechten, leicht vorgespannten Oberkörper bis zum vollständig eingerollten Rumpf. Die Hüfte bleibt stabil, nur die Wirbelsäule rollt ein.","breathing":"Beim Einrollen ausatmen, beim Aufrichten einatmen.","common_mistakes":["Hüfte bewegt sich nach hinten, die Bewegung kommt aus den Hüftbeugern.","Mit den Armen am Seil gezogen statt mit dem Bauch eingerollt.","Hände verändern während des Satzes ihre Position am Kopf.","Gewicht fällt oben unkontrolliert zurück.","Rücken bleibt gerade, der Oberkörper wird nur nach vorne gekippt."],"tips":["Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Vorstellen, die Rippen in Richtung Becken zu ziehen.","Lieber leichtes Gewicht mit vollem Bewegungsradius als schweres Gewicht mit kurzer Bewegung.","Eine Matte unter die Knie legen."],"cable_setup":{"cable":"Kabelturm oder Doppelkabelzug, einzelnes Kabel","height":"Rolle ganz oben","grip_width":"Neutral am Seil, Hände seitlich am Kopf oder im Nacken, eng beieinander","body_position":"Kniend mit dem Gesicht zum Turm, etwa eine Armlänge entfernt, Oberkörper aufrecht, Hüfte stabil","foot_position":"Knie hüftbreit auf dem Boden, Fußrücken oder Zehen abgelegt","movement_direction":"Einrollen von oben nach unten, Brustbein in Richtung Becken","elbow_position":"Ellenbogen zeigen nach unten und bleiben nah am Kopf, keine aktive Armbewegung","end_position":"Rumpf vollständig eingerollt, Ellenbogen in Richtung Oberschenkel, Bauch angespannt","return":"Langsam und kontrolliert aufrichten, bis der Oberkörper fast aufrecht ist, Gewicht bleibt in der Luft"}}$seed$::jsonb);

-- Hanging Knee Raise
select public.upsert_seed_exercise($seed${"slug":"hanging-knee-raise","name":"Hanging Knee Raise","category":"abs","equipment":"bodyweight","grip_id":null,"grip_notes":"Pronierter oder neutraler Griff an der Klimmzugstange, etwa schulterbreit. Alternativ: Armschlaufen, wenn die Griffkraft vor dem Bauch ermüdet.","primary_muscles":["abs"],"secondary_muscles":["obliques","forearms"],"description":"Hängendes Anziehen der Knie an der Klimmzugstange oder in Armschlaufen, bei dem das Becken leicht eingerollt wird. Bauchübung mit dem eigenen Körpergewicht, die zusätzlich die Griffkraft fordert.","setup":["Klimmzugstange etwa schulterbreit fassen oder Oberarme in Armschlaufen einhängen.","Frei hängen, Beine gestreckt oder leicht gebeugt, Füße ohne Bodenkontakt.","Schultern aktiv nach unten ziehen, nicht passiv in den Gelenken hängen.","Rumpf anspannen und den Körper zur Ruhe bringen, bevor die Bewegung beginnt."],"execution":["Knie kontrolliert in Richtung Brust anziehen.","Am Ende der Bewegung das Becken leicht einrollen, der untere Rücken rundet sich dabei etwas.","In der oberen Position den Bauch kurz bewusst anspannen.","Beine langsam absenken, bis die Ausgangsposition erreicht ist.","Unten kurz zur Ruhe kommen, damit kein Schwung entsteht.","Nächste Wiederholung aus dem Stand heraus beginnen."],"range_of_motion":"Von gestreckt hängenden Beinen bis zu angezogenen Knien mit leicht eingerolltem Becken. Die Knie müssen nicht die Brust berühren, das Einrollen des Beckens ist entscheidend.","breathing":"Beim Anziehen der Knie ausatmen, beim Absenken einatmen.","common_mistakes":["Körper schwingt vor und zurück, die Bewegung kommt aus dem Schwung.","Becken wird nicht eingerollt, nur die Hüftbeuger heben die Beine.","Beine fallen unkontrolliert nach unten.","Schultern hängen passiv in den Gelenken.","Zu schnelles Tempo, das Einrollen des Beckens wird übersprungen."],"tips":["Jede Wiederholung erst beginnen, wenn der Körper ruhig hängt.","Exzentrische Phase etwa zwei Sekunden lang kontrollieren.","Als Progression die Beine zunehmend gestreckt halten oder die Bewegung langsamer ausführen.","Wenn die Griffkraft vor dem Bauch ermüdet, Armschlaufen verwenden."],"cable_setup":null}$seed$::jsonb);

-- Plank
select public.upsert_seed_exercise($seed${"slug":"plank","name":"Plank","category":"abs","equipment":"bodyweight","grip_id":null,"grip_notes":"Unterarme flach auf dem Boden, Hände locker geöffnet oder zu Fäusten geschlossen. Ellenbogen etwa unter den Schultern.","primary_muscles":["abs"],"secondary_muscles":["obliques","glutes"],"description":"Isometrischer Unterarmstütz, bei dem der Körper in einer geraden Linie gehalten wird. Grundübung für die Rumpfstabilität, die über die Haltedauer statt über Wiederholungen gesteuert wird.","setup":["Unterarme flach auf den Boden legen, Ellenbogen etwa unter den Schultern.","Beine nach hinten strecken, Füße etwa hüftbreit auf den Zehenspitzen.","Körper in eine gerade Linie von Kopf bis Fersen bringen.","Blick auf den Boden richten, Nacken in Verlängerung der Wirbelsäule.","Bauch und Gesäß anspannen, Becken leicht nach hinten kippen."],"execution":["Position halten, Rumpfspannung über die gesamte Dauer aufrechterhalten.","Becken bleibt in neutraler Position, weder abgesenkt noch angehoben.","Gleichmäßig weiteratmen, ohne die Spannung zu verlieren.","Schultern aktiv vom Boden wegdrücken, oberer Rücken bleibt stabil.","Halten, solange die gerade Linie sauber gehalten werden kann.","Kontrolliert ablegen, wenn die Position nicht mehr gehalten werden kann."],"range_of_motion":"Keine Bewegung, die Position wird statisch gehalten. Entscheidend ist die gerade Körperlinie ohne Absinken der Hüfte.","breathing":"Gleichmäßig und ruhig weiteratmen, die Luft nicht anhalten. Bei jeder Ausatmung die Bauchspannung bewusst beibehalten.","common_mistakes":["Hüfte sinkt ab, der untere Rücken fällt ins Hohlkreuz.","Gesäß wird zu hoch gehoben, der Körper bildet ein Dreieck.","Kopf hängt nach unten oder wird in den Nacken gelegt.","Luft wird angehalten.","Schultern sacken zwischen den Schulterblättern ein."],"tips":["Haltedauer in Sekunden kann als Wiederholungszahl eingetragen werden, zum Beispiel 45 für 45 Sekunden.","Lieber kürzere Haltezeiten mit sauberer Linie als lange Haltezeiten mit abgesenkter Hüfte.","Als Progression die Haltedauer schrittweise verlängern oder die Füße enger stellen.","Gesäß bewusst anspannen, das stabilisiert das Becken."],"cable_setup":null}$seed$::jsonb);


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
