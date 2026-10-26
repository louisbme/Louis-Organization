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
-- Seitheben Kabel bleibt eine eigene Übung (ursprünglich zusammengeführt, auf Wunsch wiederhergestellt)
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
