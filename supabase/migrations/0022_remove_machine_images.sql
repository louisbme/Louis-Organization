-- ============================================================
-- 0022_remove_machine_images.sql
-- Gerätefotos werden in der App nicht mehr gezeigt: Bildverweise entfernen.
-- Die Spalte bleibt aus Kompatibilitätsgründen bestehen und ist überall null.
-- ============================================================

update public.exercises set image_url = null where image_url is not null;
