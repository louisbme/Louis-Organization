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
