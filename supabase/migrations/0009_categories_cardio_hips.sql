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
