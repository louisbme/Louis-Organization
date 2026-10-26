#!/usr/bin/env node
/**
 * Erzeugt aus den JSON-Seed-Dateien die SQL-Migrationen
 *   supabase/migrations/0005_seed_exercises.sql
 *   supabase/migrations/0006_seed_templates.sql
 * und bündelt alle Migrationen in supabase/bundle.sql.
 *
 * Aufruf: npm run db:generate
 */
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const exercisesDir = join(root, "supabase", "seed", "exercises");
const migrationsDir = join(root, "supabase", "migrations");

const CATEGORIES = ["chest", "back", "shoulders", "biceps", "triceps", "quads", "hamstrings", "glutes", "calves", "abs", "forearms", "adductors", "cardio"];
const EQUIPMENT = ["machine", "cable", "barbell", "dumbbell", "bodyweight", "smith_machine", "bench", "other", "cardio"];
const GRIPS = ["neutral_parallel", "wide_lat_bar", "close_v_grip", "rope", "single_handle", "strap_handle", "straight_bar", "ez_bar", "v_bar_triceps", "ankle_strap"];
const MUSCLES = ["chest", "upper_chest", "front_delts", "side_delts", "rear_delts", "traps", "lats", "upper_back", "mid_back", "lower_back", "biceps", "triceps", "forearms", "abs", "obliques", "quads", "hamstrings", "glutes", "calves", "adductors", "abductors"];
const REQUIRED = ["slug", "name", "category", "equipment", "grip_id", "grip_notes", "primary_muscles", "secondary_muscles", "description", "setup", "execution", "range_of_motion", "breathing", "common_mistakes", "tips", "cable_setup", "muscle_focus", "requirements", "grip_alternatives"];
const OPTIONAL = ["image_url", "animation_url", "machine_name", "alternative_exercises", "bodyweight_factor"];
const CABLE_FIELDS = ["cable", "height", "grip_width", "body_position", "foot_position", "movement_direction", "elbow_position", "end_position", "return"];

const errors = [];
const exercises = [];
const slugs = new Set();

for (const file of readdirSync(exercisesDir).filter((f) => f.endsWith(".json")).sort()) {
  const list = JSON.parse(readFileSync(join(exercisesDir, file), "utf8"));
  if (!Array.isArray(list)) {
    errors.push(`${file}: kein Array`);
    continue;
  }
  for (const ex of list) {
    const ctx = `${file} → ${ex.slug ?? ex.name ?? "?"}`;
    for (const key of REQUIRED) {
      if (!(key in ex)) errors.push(`${ctx}: Feld "${key}" fehlt`);
    }
    if (typeof ex.slug !== "string" || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(ex.slug)) errors.push(`${ctx}: ungültiger slug`);
    if (slugs.has(ex.slug)) errors.push(`${ctx}: slug doppelt`);
    slugs.add(ex.slug);
    if (!CATEGORIES.includes(ex.category)) errors.push(`${ctx}: ungültige category "${ex.category}"`);
    if (!EQUIPMENT.includes(ex.equipment)) errors.push(`${ctx}: ungültiges equipment "${ex.equipment}"`);
    if (ex.grip_id !== null && !GRIPS.includes(ex.grip_id)) errors.push(`${ctx}: ungültige grip_id "${ex.grip_id}"`);
    if (ex.equipment !== "cable" && ex.grip_id !== null) errors.push(`${ctx}: grip_id nur bei Kabelübungen`);
    for (const m of [...ex.primary_muscles, ...ex.secondary_muscles]) {
      if (!MUSCLES.includes(m)) errors.push(`${ctx}: ungültige Muskel-ID "${m}"`);
    }
    if (ex.primary_muscles.length < 1) errors.push(`${ctx}: primary_muscles leer`);
    for (const key of Object.keys(ex)) {
      if (!REQUIRED.includes(key) && !OPTIONAL.includes(key)) errors.push(`${ctx}: unbekanntes Feld "${key}"`);
    }
    if (ex.image_url !== undefined && ex.image_url !== null && !/^(\/|https?:\/\/)/.test(ex.image_url)) errors.push(`${ctx}: image_url muss mit / oder http beginnen`);
    if (ex.bodyweight_factor !== undefined) {
      if (ex.equipment !== "bodyweight") errors.push(`${ctx}: bodyweight_factor nur bei Körpergewichtsübungen`);
      if (typeof ex.bodyweight_factor !== "number" || ex.bodyweight_factor < 0 || ex.bodyweight_factor > 2) errors.push(`${ctx}: bodyweight_factor muss zwischen 0 und 2 liegen`);
    }
    for (const key of ["setup", "execution", "common_mistakes", "tips", "muscle_focus", "requirements"]) {
      if (!Array.isArray(ex[key]) || ex[key].length === 0) errors.push(`${ctx}: ${key} leer`);
    }
    if (!Array.isArray(ex.grip_alternatives)) errors.push(`${ctx}: grip_alternatives muss ein Array sein`);
    else {
      for (const g of ex.grip_alternatives) if (!GRIPS.includes(g)) errors.push(`${ctx}: ungültige Alternative "${g}"`);
      if (ex.equipment !== "cable" && ex.grip_alternatives.length > 0) errors.push(`${ctx}: grip_alternatives nur bei Kabelübungen`);
      if (ex.grip_alternatives.includes(ex.grip_id)) errors.push(`${ctx}: grip_alternatives enthält den Standardgriff`);
    }
    if (ex.equipment === "cable") {
      if (!ex.cable_setup || typeof ex.cable_setup !== "object") errors.push(`${ctx}: cable_setup fehlt`);
      else {
        for (const f of CABLE_FIELDS) {
          if (f === "height" && ex.cable_setup.seat_position) continue;
          if (!ex.cable_setup[f]) errors.push(`${ctx}: cable_setup.${f} fehlt`);
        }
      }
    } else if (ex.cable_setup !== null) {
      errors.push(`${ctx}: cable_setup muss null sein`);
    }
    exercises.push(ex);
  }
}

for (const ex of exercises) {
  for (const alt of ex.alternative_exercises ?? []) {
    if (!slugs.has(alt)) errors.push(`${ex.slug}: alternative_exercises verweist auf unbekannten Slug "${alt}"`);
    if (alt === ex.slug) errors.push(`${ex.slug}: alternative_exercises verweist auf sich selbst`);
  }
  if (ex.image_url && ex.equipment === "dumbbell") errors.push(`${ex.slug}: Kurzhantelübungen bekommen kein Gerätefoto`);
}

const templates = JSON.parse(readFileSync(join(root, "supabase", "seed", "templates.json"), "utf8"));
for (const t of templates) {
  for (const e of t.exercises) {
    if (!slugs.has(e.slug)) errors.push(`Vorlage "${t.name}": Übung "${e.slug}" existiert nicht`);
  }
}

if (errors.length) {
  console.error("Seed-Validierung fehlgeschlagen:\n" + errors.map((e) => "  - " + e).join("\n"));
  process.exit(1);
}

/** Dollar-Quoting: sicher gegen Anführungszeichen im JSON. */
const dq = (obj) => {
  const json = JSON.stringify(obj);
  if (json.includes("$seed$")) throw new Error("Unerwartete Zeichenfolge $seed$ in den Daten");
  return `$seed$${json}$seed$::jsonb`;
};

const exerciseSql = [
  "-- ============================================================",
  "-- 0005_seed_exercises.sql",
  "-- GENERIERT aus supabase/seed/exercises/*.json via `npm run db:generate` – nicht manuell bearbeiten.",
  `-- ${exercises.length} Standardübungen`,
  "-- ============================================================",
  "",
  ...exercises.map((ex) => `-- ${ex.name}\nselect public.upsert_seed_exercise(${dq(ex)});\n`),
].join("\n");

const templateSql = [
  "-- ============================================================",
  "-- 0006_seed_templates.sql",
  "-- GENERIERT aus supabase/seed/templates.json via `npm run db:generate` – nicht manuell bearbeiten.",
  "-- Standard-Trainingspläne (Vorlagen), werden bei Registrierung je Benutzer kopiert.",
  "-- ============================================================",
  "",
  ...templates.map((t) => `-- ${t.name}\nselect public.upsert_seed_template(${dq(t)});\n`),
].join("\n");

writeFileSync(join(migrationsDir, "0005_seed_exercises.sql"), exerciseSql);
writeFileSync(join(migrationsDir, "0006_seed_templates.sql"), templateSql);

// Bundle aller Migrationen (für den Supabase SQL-Editor)
const migrationFiles = readdirSync(migrationsDir).filter((f) => f.endsWith(".sql")).sort();
const bundle = [
  "-- ============================================================",
  "-- bundle.sql – alle Migrationen in Reihenfolge (GENERIERT via `npm run db:generate`)",
  "-- Für den Supabase SQL-Editor: komplette Datei einfügen und ausführen.",
  "-- ============================================================",
  "",
  ...migrationFiles.map((f) => `\n-- >>>>>>>>>> ${f} <<<<<<<<<<\n\n${readFileSync(join(migrationsDir, f), "utf8")}`),
].join("\n");
writeFileSync(join(root, "supabase", "bundle.sql"), bundle);

console.log(`OK: ${exercises.length} Übungen, ${templates.length} Vorlagen, ${migrationFiles.length} Migrationen gebündelt.`);
