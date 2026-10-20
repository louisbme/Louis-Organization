-- ============================================================
-- 0010_remove_machine_images.sql
-- Maschinenfotos entfernt: Standardübungen zeigen nur noch die Muskelkarte.
-- ============================================================

update public.exercises
set image_url = null
where owner_id is null and image_url like '/exercises/%';
