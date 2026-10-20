-- ============================================================
-- 0007_media_and_storage.sql
-- Griff-Bilder, Ausführungs-Animationen, Storage-Bucket, Maschinenfotos
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

-- ------------------------------------------------------------
-- Maschinenfotos aus dem Studio (vom Nutzer bereitgestellt, liegen unter public/exercises)
-- Nur setzen, wenn noch kein Bild hinterlegt ist.
-- ------------------------------------------------------------
with mapping(slug, url) as (
  values
    ('schraegbankdruecken-maschine', '/exercises/incline-press-plate.jpg'),
    ('brustpresse', '/exercises/chest-press.jpg'),
    ('pec-deck', '/exercises/pec-deck-rear-delt.jpg'),
    ('butterfly', '/exercises/pec-deck-rear-delt.jpg'),
    ('reverse-butterfly', '/exercises/pec-deck-rear-delt.jpg'),
    ('neutraler-latzug', '/exercises/lat-pulldown-neutral.jpg'),
    ('breiter-latzug', '/exercises/lat-pulldown-wide.jpg'),
    ('brustgestuetztes-rudern', '/exercises/chest-supported-row.jpg'),
    ('reverse-fly-kurzhantel', '/exercises/dumbbell-area.jpg'),
    ('hyperextensions', '/exercises/hyperextension-bench.jpg'),
    ('wrist-curl', '/exercises/flat-bench.jpg'),
    ('reverse-wrist-curl', '/exercises/flat-bench.jpg'),
    ('schulterdruecken-maschine', '/exercises/shoulder-press-plate.jpg'),
    ('hackenschmidt', '/exercises/hack-squat.jpg'),
    ('beinpresse', '/exercises/leg-press-seated.jpg'),
    ('beinstrecker', '/exercises/leg-extension-curl.jpg'),
    ('beinbeuger', '/exercises/seated-leg-curl.jpg'),
    ('bulgarian-split-squat', '/exercises/adjustable-bench.jpg'),
    ('kniebeuge', '/exercises/half-rack.jpg'),
    ('rumaenisches-kreuzheben', '/exercises/half-rack.jpg'),
    ('ausfallschritte', '/exercises/dumbbell-area.jpg'),
    ('hip-thrust', '/exercises/flat-bench.jpg'),
    ('incline-curl', '/exercises/adjustable-bench.jpg'),
    ('incline-curl-hinterm-koerper', '/exercises/adjustable-bench.jpg'),
    ('kurzhantelcurl', '/exercises/dumbbell-area.jpg'),
    ('crunch-maschine', '/exercises/abdominal-machine.jpg'),
    ('hanging-knee-raise', '/exercises/knee-raise-station.jpg')
)
update public.exercises e
set image_url = m.url
from mapping m
where e.slug = m.slug and e.owner_id is null and e.image_url is null;

-- Alle Kabelübungen: Foto des Kabelturms
update public.exercises
set image_url = '/exercises/cable-station.jpg'
where owner_id is null and equipment = 'cable' and image_url is null;
