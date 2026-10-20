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
