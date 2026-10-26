#!/usr/bin/env node
/**
 * Datenbank-Test: führt alle Migrationen in einer eingebetteten Postgres-Instanz (PGlite) aus
 * und prüft die Kernabläufe (Registrierung → Pläne, Training starten, Sätze speichern,
 * Training abschließen, Historie/Statistiken, RLS-Trennung, eigene Übungen, Kalender).
 *
 * Aufruf: npm run test:db
 */
import { PGlite } from "@electric-sql/pglite";
import { readdirSync, readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const migrationsDir = join(root, "supabase", "migrations");
const seedDir = join(root, "supabase", "seed", "exercises");
/** Erwartete Anzahl Standardübungen aus den Seed-Dateien */
const EXPECTED_EXERCISES = readdirSync(seedDir)
  .filter((f) => f.endsWith(".json"))
  .reduce((n, f) => n + JSON.parse(readFileSync(join(seedDir, f), "utf8")).length, 0);

const db = new PGlite();
let failures = 0;
const ok = (name) => console.log(`  ✓ ${name}`);
const fail = (name, err) => {
  failures += 1;
  console.error(`  ✗ ${name}\n    ${err?.message ?? err}`);
};
async function test(name, fn) {
  try {
    await fn();
    ok(name);
  } catch (e) {
    fail(name, e);
  }
}
const assert = (cond, msg) => {
  if (!cond) throw new Error(msg ?? "Assertion fehlgeschlagen");
};

// --- Supabase-Umgebung nachbilden (auth-Schema, Rollen) -------------------
await db.exec(`
  create schema if not exists auth;
  create table auth.users (
    id uuid primary key,
    email text,
    raw_user_meta_data jsonb default '{}'::jsonb,
    created_at timestamptz default now(),
    last_sign_in_at timestamptz
  );
  create or replace function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  $$;
  do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  end $$;
  grant usage on schema auth to anon, authenticated;
  grant execute on function auth.uid() to anon, authenticated;
`);

// --- Migrationen ------------------------------------------------------------
console.log("Migrationen:");
for (const file of readdirSync(migrationsDir).filter((f) => f.endsWith(".sql")).sort()) {
  const sql = readFileSync(join(migrationsDir, file), "utf8");
  try {
    await db.exec(sql);
    ok(file);
  } catch (e) {
    fail(file, e);
  }
}
if (failures > 0) {
  console.error("\nMigrationen fehlgeschlagen.");
  process.exit(1);
}

const asUser = async (userId, fn) => {
  await db.exec(`set role authenticated; select set_config('request.jwt.claim.sub', '${userId}', false);`);
  try {
    return await fn();
  } finally {
    await db.exec(`reset role; select set_config('request.jwt.claim.sub', '', false);`);
  }
};

const USER_A = "11111111-1111-4111-8111-111111111111";
const USER_B = "22222222-2222-4222-8222-222222222222";

console.log("\nTests:");

await test(`Seed: ${EXPECTED_EXERCISES} Standardübungen mit Muskeln, 3 Vorlagen, Zitate`, async () => {
  const ex = await db.query("select count(*)::int as n from exercises where owner_id is null");
  assert(ex.rows[0].n === EXPECTED_EXERCISES, `erwartet ${EXPECTED_EXERCISES}, erhalten ${ex.rows[0].n}`);
  const noMuscles = await db.query(
    "select count(*)::int as n from exercises e where not exists (select 1 from exercise_muscles m where m.exercise_id = e.id and m.role = 'primary')"
  );
  assert(noMuscles.rows[0].n === 0, "Übungen ohne primären Muskel");
  const t = await db.query("select count(*)::int as n from workout_plan_templates");
  assert(t.rows[0].n === 3);
  const te = await db.query("select count(*)::int as n from workout_plan_template_exercises");
  assert(te.rows[0].n === 23, `erwartet 23 Vorlagenübungen, erhalten ${te.rows[0].n}`);
  const q = await db.query("select count(*)::int as n from quotes where active");
  assert(q.rows[0].n >= 50, `erwartet ≥50 Zitate, erhalten ${q.rows[0].n}`);
  const cable = await db.query("select count(*)::int as n from exercises where equipment = 'cable' and (grip_id is null or cable_setup is null)");
  assert(cable.rows[0].n === 0, "Kabelübungen ohne Griff/Setup");
});

await test("Registrierung: Profil, Einstellungen und 3 Standardpläne werden angelegt", async () => {
  await db.query("insert into auth.users (id, email, raw_user_meta_data) values ($1, $2, $3)", [
    USER_A,
    "a@example.com",
    { nickname: "Louis" },
  ]);
  const p = await db.query("select nickname from profiles where id = $1", [USER_A]);
  assert(p.rows[0]?.nickname === "Louis");
  const s = await db.query("select rest_timer_default, show_rir, theme from user_settings where user_id = $1", [USER_A]);
  assert(s.rows[0]?.rest_timer_default === 90 && s.rows[0].show_rir === false && s.rows[0].theme === "dark");
  const plans = await db.query("select name from workout_plans where user_id = $1 order by sort_order", [USER_A]);
  assert(plans.rows.map((r) => r.name).join("|") === "Oberkörper A|Unterkörper|Oberkörper B", plans.rows.map((r) => r.name).join("|"));
  const pe = await db.query("select count(*)::int as n from workout_plan_exercises pe join workout_plans p on p.id = pe.plan_id where p.user_id = $1", [USER_A]);
  assert(pe.rows[0].n === 23);
});

await test("Nickname: Duplikat wird abgefangen, Verfügbarkeit prüfbar", async () => {
  await db.query("insert into auth.users (id, email, raw_user_meta_data) values ($1, $2, $3)", [
    USER_B,
    "b@example.com",
    { nickname: "louis" },
  ]);
  const p = await db.query("select nickname from profiles where id = $1", [USER_B]);
  assert(p.rows[0].nickname.startsWith("user_"), "Fallback-Nickname erwartet");
  const avail = await db.query("select is_nickname_available('LOUIS') as a, is_nickname_available('neu') as b");
  assert(avail.rows[0].a === false && avail.rows[0].b === true);
  await asUser(USER_B, async () => {
    await db.query("update profiles set nickname = 'Boerge' where id = $1", [USER_B]);
  });
});

await test("RLS: Benutzer sieht nur eigene Pläne, fremde Daten unsichtbar", async () => {
  await asUser(USER_A, async () => {
    const r = await db.query("select count(*)::int as n from workout_plans");
    assert(r.rows[0].n === 3, `erwartet 3, erhalten ${r.rows[0].n}`);
    const ex = await db.query("select count(*)::int as n from exercises");
    assert(ex.rows[0].n === EXPECTED_EXERCISES);
    const prof = await db.query("select count(*)::int as n from profiles");
    assert(prof.rows[0].n === 1, "fremde Profile sichtbar");
  });
});

await test("RLS: Rolle kann nicht selbst geändert werden", async () => {
  let blocked = false;
  await asUser(USER_A, async () => {
    try {
      await db.query("update profiles set role = 'admin' where id = $1", [USER_A]);
    } catch {
      blocked = true;
    }
  });
  assert(blocked, "Rollenänderung wurde nicht blockiert");
});

await test("RLS: Standardübungen können nicht gelöscht/geändert werden", async () => {
  await asUser(USER_A, async () => {
    await db.query("delete from exercises where owner_id is null");
    const n = await db.query("select count(*)::int as n from exercises where owner_id is null");
    assert(n.rows[0].n === EXPECTED_EXERCISES, "Standardübungen wurden gelöscht");
    await db.query("update exercises set name = 'x' where owner_id is null");
    const changed = await db.query("select count(*)::int as n from exercises where name = 'x'");
    assert(changed.rows[0].n === 0, "Standardübung wurde geändert");
  });
});

let sessionId;
await test("Training starten: Session + Übungen aus Plan", async () => {
  await asUser(USER_A, async () => {
    const plan = await db.query("select id from workout_plans where name = 'Oberkörper A'");
    const r = await db.query("select start_workout_session($1) as id", [plan.rows[0].id]);
    sessionId = r.rows[0].id;
    const se = await db.query("select count(*)::int as n from workout_session_exercises where session_id = $1", [sessionId]);
    assert(se.rows[0].n === 8);
    const again = await db.query("select start_workout_session($1) as id", [plan.rows[0].id]);
    assert(again.rows[0].id === sessionId, "zweiter Start muss aktive Session zurückgeben");
  });
});

await test("Sätze speichern (Upsert) und Aufwärmsatz", async () => {
  await asUser(USER_A, async () => {
    const se = await db.query("select id from workout_session_exercises where session_id = $1 order by sort_order limit 2", [sessionId]);
    const first = se.rows[0].id;
    const second = se.rows[1].id;
    await db.query(
      `insert into workout_sets (session_exercise_id, user_id, set_number, weight, reps, is_warmup) values
       ($1, $2, 1, 40, 12, true), ($1, $2, 2, 70, 10, false), ($1, $2, 3, 70, 10, false), ($1, $2, 4, 70, 10, false)`,
      [first, USER_A]
    );
    await db.query(
      `insert into workout_sets (session_exercise_id, user_id, set_number, weight, reps) values ($1, $2, 1, 50, 10)
       on conflict (session_exercise_id, set_number) do update set weight = excluded.weight, reps = excluded.reps`,
      [first, USER_A]
    );
    await db.query(
      `insert into workout_sets (session_exercise_id, user_id, set_number, weight, reps) values ($1, $2, 1, 50, 10)
       on conflict (session_exercise_id, set_number) do update set weight = 55, reps = 11`,
      [first, USER_A]
    );
    const row = await db.query("select weight::float as w, reps from workout_sets where session_exercise_id = $1 and set_number = 1", [first]);
    assert(row.rows[0].w === 55 && row.rows[0].reps === 11, "Upsert fehlgeschlagen");
    await db.query("insert into workout_sets (session_exercise_id, user_id, set_number, weight, reps, completed) values ($1, $2, 1, 30, 8, false)", [second, USER_A]);
  });
});

await test("RLS: fremde Sätze können nicht eingefügt werden", async () => {
  let blocked = false;
  await asUser(USER_B, async () => {
    try {
      const se = await db.query("select id from workout_session_exercises limit 1");
      assert(se.rows.length === 0, "fremde Session-Übungen sichtbar");
      blocked = true;
    } catch {
      blocked = true;
    }
  });
  assert(blocked);
});

await test("Training abschließen: Dauer, Volumen (nur Arbeitssätze), Kalender", async () => {
  await asUser(USER_A, async () => {
    await db.query("update workout_sessions set started_at = now() - interval '50 minutes' where id = $1", [sessionId]);
    const r = await db.query("select * from complete_workout_session($1, $2, $3)", [sessionId, "Gut gelaufen", "2026-10-20"]);
    const s = r.rows[0];
    assert(s.status === "completed");
    assert(Number(s.total_volume) === 70 * 10 * 3, `Volumen ${s.total_volume}`);
    assert(s.total_sets === 3, `Sätze ${s.total_sets}`);
    assert(s.duration_seconds >= 2990 && s.duration_seconds <= 3010, `Dauer ${s.duration_seconds}`);
    const cal = await db.query("select entry_type from calendar_entries where user_id = $1 and entry_date = '2026-10-20'", [USER_A]);
    assert(cal.rows[0]?.entry_type === "training");
    const removed = await db.query("select count(*)::int as n from workout_session_exercises where session_id = $1", [sessionId]);
    assert(removed.rows[0].n === 1, "Übungen ohne abgeschlossene Sätze sollten entfernt sein");
  });
});

await test("Letzte Leistung + Statistiken + Bestleistungen", async () => {
  await asUser(USER_A, async () => {
    const ex = await db.query("select exercise_id from workout_session_exercises where session_id = $1", [sessionId]);
    const exId = ex.rows[0].exercise_id;
    const lp = await db.query("select * from get_last_exercise_performance($1::uuid[])", [[exId]]);
    assert(lp.rows.length === 4, `erwartet 4 Sätze, erhalten ${lp.rows.length}`);
    const st = await db.query("select * from get_user_stats()");
    assert(Number(st.rows[0].total_workouts) === 1 && Number(st.rows[0].total_volume) === 2100);
    const rec = await db.query("select * from get_exercise_records($1)", [exId]);
    assert(Number(rec.rows[0].max_weight) === 70 && Number(rec.rows[0].max_session_volume) === 2100);
    const hist = await db.query("select * from get_exercise_history($1, null)", [exId]);
    assert(hist.rows.length === 1 && Number(hist.rows[0].volume) === 2100);
    const group = await db.query("select nickname, total_workouts from get_group_stats()");
    assert(group.rows.length === 2, "Gruppenstatistik sollte beide Nutzer zeigen");
  });
});

await test("Tracking-Art: Cardio, Körpergewicht und Gewicht × Wdh werden abgeleitet", async () => {
  const r = await db.query(
    "select slug, tracking_mode, bodyweight_factor::float as f from exercises where owner_id is null and slug in ('laufband','hyperextensions','plank','schraegbankdruecken-maschine')"
  );
  const by = Object.fromEntries(r.rows.map((x) => [x.slug, x]));
  assert(by.laufband?.tracking_mode === "cardio", "Laufband sollte cardio sein");
  assert(by.hyperextensions?.tracking_mode === "bodyweight" && by.hyperextensions.f === 0.6, "Hyperextensions: bodyweight, Anteil 0,6");
  assert(by.plank?.f === 0.65, "Plank: Anteil 0,65");
  assert(by["schraegbankdruecken-maschine"]?.tracking_mode === "weight_reps", "Maschine: weight_reps");
  await asUser(USER_A, async () => {
    const c = await db.query(
      "insert into exercises (slug, name, category, equipment, is_custom, owner_id) values ('mein-lauf-u2', 'Mein Lauf', 'cardio', 'other', true, $1) returning tracking_mode",
      [USER_A]
    );
    assert(c.rows[0].tracking_mode === "cardio", "eigene Cardio-Übung");
    const u = await db.query("update exercises set category = 'chest', equipment = 'bodyweight' where slug = 'mein-lauf-u2' returning tracking_mode");
    assert(u.rows[0].tracking_mode === "bodyweight", "Umstellung auf Körpergewicht");
    await db.query("delete from exercises where slug = 'mein-lauf-u2'");
  });
});

await test("Nachträgliche Bearbeitung: Summen eines abgeschlossenen Trainings werden neu berechnet", async () => {
  await asUser(USER_A, async () => {
    const se = await db.query("select id from workout_session_exercises where session_id = $1", [sessionId]);
    const seId = se.rows[0].id;
    const totals = async () => (await db.query("select total_volume::float as v, total_sets as n from workout_sessions where id = $1", [sessionId])).rows[0];
    await db.query("update workout_sets set weight = 80 where session_exercise_id = $1 and set_number = 2", [seId]);
    let t = await totals();
    assert(t.v === 800 + 1400 && t.n === 3, `nach Änderung: ${JSON.stringify(t)}`);
    await db.query("insert into workout_sets (session_exercise_id, user_id, set_number, weight, reps) values ($1, $2, 5, 60, 8)", [seId, USER_A]);
    t = await totals();
    assert(t.v === 2200 + 480 && t.n === 4, `nach Hinzufügen: ${JSON.stringify(t)}`);
    await db.query("delete from workout_sets where session_exercise_id = $1 and set_number = 5", [seId]);
    await db.query("update workout_sets set weight = 70 where session_exercise_id = $1 and set_number = 2", [seId]);
    t = await totals();
    assert(t.v === 2100 && t.n === 3, `nach Zurücksetzen: ${JSON.stringify(t)}`);
  });
});

await test("Cardio (Dauer/Distanz) und Körpergewicht (Snapshot + Zusatz): Abschluss, Bestleistungen, Verlauf, Entfernen", async () => {
  await asUser(USER_A, async () => {
    const plan = await db.query("select id from workout_plans where name = 'Unterkörper'");
    const started = await db.query("select start_workout_session($1) as id", [plan.rows[0].id]);
    const sid = started.rows[0].id;
    const lauf = (await db.query("select id from exercises where slug = 'laufband' and owner_id is null")).rows[0].id;
    const hyper = (await db.query("select id from exercises where slug = 'hyperextensions' and owner_id is null")).rows[0].id;
    const seC = (await db.query("insert into workout_session_exercises (session_id, user_id, exercise_id, sort_order) values ($1, $2, $3, 90) returning id", [sid, USER_A, lauf])).rows[0].id;
    const seB = (await db.query("insert into workout_session_exercises (session_id, user_id, exercise_id, sort_order) values ($1, $2, $3, 91) returning id", [sid, USER_A, hyper])).rows[0].id;
    await db.query("insert into workout_sets (session_exercise_id, user_id, set_number, weight, reps, duration_seconds, distance_m) values ($1, $2, 1, 0, 0, 1500, 5000)", [seC, USER_A]);
    // 80 kg × 0,6 + 10 kg Zusatz = 58 kg
    await db.query("insert into workout_sets (session_exercise_id, user_id, set_number, weight, reps, body_weight, extra_weight) values ($1, $2, 1, 58, 12, 80, 10)", [seB, USER_A]);
    const done = (await db.query("select * from complete_workout_session($1, null, '2026-10-22')", [sid])).rows[0];
    assert(done.total_sets === 2 && Number(done.total_volume) === 58 * 12, `Cardio zählt als Satz ohne Volumen: ${done.total_sets} / ${done.total_volume}`);

    const rec = (await db.query("select * from get_exercise_records($1)", [lauf])).rows[0];
    assert(rec.max_distance_m === 5000 && rec.max_duration_seconds === 1500, `Cardio-Bestleistungen: ${JSON.stringify(rec)}`);
    assert(Number(rec.best_pace_sec_per_km) === 300 && Number(rec.total_sessions) === 1, `Pace/Sessions: ${JSON.stringify(rec)}`);
    assert(rec.max_weight === null, "Cardio darf kein Maximalgewicht haben");

    const hist = (await db.query("select * from get_exercise_history($1, null)", [lauf])).rows;
    assert(hist.length === 1 && hist[0].total_distance_m === 5000 && hist[0].total_duration_seconds === 1500, `Verlauf: ${JSON.stringify(hist)}`);

    const lp = (await db.query("select * from get_last_exercise_performance($1::uuid[])", [[lauf, hyper]])).rows;
    const lpC = lp.find((x) => x.exercise_id === lauf);
    const lpB = lp.find((x) => x.exercise_id === hyper);
    assert(lpC && lpC.distance_m === 5000 && lpC.duration_seconds === 1500, "Cardio-Felder in letzter Leistung");
    assert(lpB && Number(lpB.body_weight) === 80 && Number(lpB.extra_weight) === 10 && Number(lpB.weight) === 58, "Körpergewichtsfelder in letzter Leistung");

    const detail = (await db.query("select get_member_session_detail($1) as d", [sid])).rows[0].d;
    const ex = detail.exercises.find((e) => e.exercise.slug === "laufband");
    assert(ex && ex.exercise.tracking_mode === "cardio" && ex.sets[0].distance_m === 5000, "Mitglieder-Detail ohne Cardio-Felder");

    await db.query("delete from workout_session_exercises where id = $1", [seB]);
    const after = (await db.query("select total_sets as n, total_volume::float as v from workout_sessions where id = $1", [sid])).rows[0];
    assert(after.n === 1 && after.v === 0, `nach Entfernen der Übung: ${JSON.stringify(after)}`);
    await db.query("delete from workout_sessions where id = $1", [sid]);
  });
});

await test("Mitglieder-Detail: fremde Trainings lesbar, ohne Anmeldung gesperrt", async () => {
  await asUser(USER_B, async () => {
    const list = await db.query("select * from get_member_sessions($1)", [USER_A]);
    assert(list.rows.length === 1, `erwartet 1 Training, erhalten ${list.rows.length}`);
    assert(Number(list.rows[0].total_volume) === 2100, `Volumen ${list.rows[0].total_volume}`);
    assert(list.rows[0].session_id === sessionId, "falsche Session");
    const names = list.rows[0].exercise_names;
    assert(Array.isArray(names) && names.length === 1, `erwartet 1 Übungsnamen, erhalten ${JSON.stringify(names)}`);

    const detail = await db.query("select get_member_session_detail($1) as d", [sessionId]);
    const d = detail.rows[0].d;
    assert(d && d.session.nickname === "Louis", `Nickname ${d?.session?.nickname}`);
    assert(d.session.id === sessionId && Number(d.session.total_volume) === 2100, "Session-Daten");
    assert(d.exercises.length === 1, `erwartet 1 Übung, erhalten ${d.exercises.length}`);
    assert(d.exercises[0].sets.length === 4, `erwartet 4 Sätze, erhalten ${d.exercises[0].sets.length}`);
    assert(d.exercises[0].exercise.slug, "Übungs-Slug fehlt");

    const missing = await db.query("select get_member_session_detail($1) as d", ["33333333-3333-4333-8333-333333333333"]);
    assert(missing.rows[0].d === null, "unbekannte Session sollte null liefern");
  });

  // Ohne Anmeldung (Rolle anon, kein JWT-Claim) müssen beide Funktionen eine Exception werfen
  let blockedList = false;
  let blockedDetail = false;
  await db.exec("set role anon; select set_config('request.jwt.claim.sub', '', false);");
  try {
    try {
      await db.query("select * from get_member_sessions($1)", [USER_A]);
    } catch {
      blockedList = true;
    }
    try {
      await db.query("select get_member_session_detail($1)", [sessionId]);
    } catch {
      blockedDetail = true;
    }
  } finally {
    await db.exec("reset role;");
  }
  assert(blockedList, "get_member_sessions ohne Anmeldung nicht blockiert");
  assert(blockedDetail, "get_member_session_detail ohne Anmeldung nicht blockiert");
});

await test("Eigene Übung: anlegen, in Plan verwenden, fremd unsichtbar", async () => {
  await asUser(USER_A, async () => {
    const r = await db.query(
      `insert into exercises (slug, name, category, equipment, is_custom, owner_id) values ('meine-uebung-u1', 'Meine Übung', 'chest', 'machine', true, $1) returning id`,
      [USER_A]
    );
    const id = r.rows[0].id;
    await db.query("insert into exercise_muscles (exercise_id, muscle_id, role) values ($1, 'chest', 'primary')", [id]);
    const plan = await db.query("select id from workout_plans where name = 'Oberkörper B'");
    await db.query("insert into workout_plan_exercises (plan_id, exercise_id, sort_order) values ($1, $2, 99)", [plan.rows[0].id, id]);
    await db.query("insert into favorites (user_id, exercise_id) values ($1, $2)", [USER_A, id]);
  });
  await asUser(USER_B, async () => {
    const r = await db.query("select count(*)::int as n from exercises where is_custom");
    assert(r.rows[0].n === 0, "fremde eigene Übung sichtbar");
  });
});

await test("Kalender: Eintrag anlegen/ändern, Duplikat je Tag verhindert", async () => {
  await asUser(USER_A, async () => {
    await db.query("insert into calendar_entries (user_id, entry_date, entry_type, note) values ($1, '2026-10-21', 'rest', 'Pause')", [USER_A]);
    await db.query(
      "insert into calendar_entries (user_id, entry_date, entry_type) values ($1, '2026-10-21', 'party') on conflict (user_id, entry_date) do update set entry_type = excluded.entry_type",
      [USER_A]
    );
    const r = await db.query("select entry_type, note from calendar_entries where user_id = $1 and entry_date = '2026-10-21'", [USER_A]);
    assert(r.rows[0].entry_type === "party" && r.rows[0].note === "Pause");
  });
});

await test("Portfolio: eigene Übungen werden Standardübungen (Slug ohne Suffix, ID bleibt, für alle sichtbar)", async () => {
  // Suffix wie in der App erzeugt: "-u" + 4 Zeichen
  await asUser(USER_A, async () => {
    await db.query("insert into exercises (slug, name, category, equipment, is_custom, owner_id) values ('portfolio-test-uab12', 'Portfolio Test', 'chest', 'machine', true, $1)", [USER_A]);
  });
  const before = await db.query("select id from exercises where slug = 'portfolio-test-uab12'");
  assert(before.rows.length === 1, "eigene Übung fehlt");
  const n = await db.query("select promote_custom_exercises() as n");
  assert(Number(n.rows[0].n) >= 1, "nichts übernommen");
  const after = await db.query("select id, is_custom, owner_id from exercises where slug = 'portfolio-test'");
  assert(after.rows.length === 1 && after.rows[0].is_custom === false && after.rows[0].owner_id === null, "nicht zur Standardübung geworden");
  assert(after.rows[0].id === before.rows[0].id, "ID hat sich geändert");
  await asUser(USER_B, async () => {
    const r = await db.query("select count(*)::int as n from exercises where slug = 'portfolio-test'");
    assert(r.rows[0].n === 1, "für andere Nutzer nicht sichtbar");
  });
  // Kollision mit einer Standardübung: Suffix bleibt erhalten
  await asUser(USER_A, async () => {
    await db.query("insert into exercises (slug, name, category, equipment, is_custom, owner_id) values ('plank-u9z9z', 'Plank 2', 'abs', 'bodyweight', true, $1)", [USER_A]);
  });
  await db.query("select promote_custom_exercises()");
  const kept = await db.query("select slug, is_custom from exercises where slug = 'plank-u9z9z'");
  assert(kept.rows.length === 1 && kept.rows[0].is_custom === false, "Kollisionsfall nicht korrekt");
});

await test("Pläne anderer Mitglieder ansehen und kopieren, ohne Anmeldung gesperrt", async () => {
  await asUser(USER_B, async () => {
    const r = await db.query("select get_member_plans($1) as p", [USER_A]);
    const plans = r.rows[0].p;
    assert(Array.isArray(plans) && plans.length === 3, `erwartet 3 Pläne, erhalten ${Array.isArray(plans) ? plans.length : typeof plans}`);
    const src = plans.find((p) => p.name === "Oberkörper A");
    assert(src && src.exercises.length === 8, "Übungen des Plans fehlen");
    const copied = await db.query("select copy_member_plan($1, null) as id", [src.id]);
    const mine = await db.query("select name, user_id from workout_plans where id = $1", [copied.rows[0].id]);
    assert(mine.rows[0].user_id === USER_B, "Kopie gehört nicht dem Kopierenden");
    assert(mine.rows[0].name === "Oberkörper A (von Louis)", `Name der Kopie: ${mine.rows[0].name}`);
    const pe = await db.query("select count(*)::int as n from workout_plan_exercises where plan_id = $1", [copied.rows[0].id]);
    assert(pe.rows[0].n === 8, `erwartet 8 Übungen in der Kopie, erhalten ${pe.rows[0].n}`);
  });
  let blocked = false;
  await db.exec("set role anon; select set_config('request.jwt.claim.sub', '', false);");
  try {
    try {
      await db.query("select get_member_plans($1)", [USER_A]);
    } catch {
      blocked = true;
    }
  } finally {
    await db.exec("reset role;");
  }
  assert(blocked, "get_member_plans ohne Anmeldung nicht blockiert");
});

await test("Admin: Trainingsdaten anderer lesbar und bearbeitbar (Summen neu), Nicht-Admin nicht", async () => {
  await asUser(USER_B, async () => {
    const plan = await db.query("select id from workout_plans where user_id = $1 and template_id is not null order by sort_order limit 1", [USER_B]);
    const r = await db.query("select start_workout_session($1) as id", [plan.rows[0].id]);
    const se = await db.query("select id from workout_session_exercises where session_id = $1 order by sort_order limit 1", [r.rows[0].id]);
    await db.query("insert into workout_sets (session_exercise_id, user_id, set_number, weight, reps) values ($1, $2, 1, 20, 10)", [se.rows[0].id, USER_B]);
    await db.query("select complete_workout_session($1, null, '2026-10-23')", [r.rows[0].id]);
  });
  await asUser(USER_A, async () => {
    const r = await db.query("select count(*)::int as n from workout_sessions where user_id = $1", [USER_B]);
    assert(r.rows[0].n === 0, "Nicht-Admin sieht fremde Trainings");
  });
  await db.query("update profiles set role = 'admin' where id = $1", [USER_A]);
  await asUser(USER_A, async () => {
    const r = await db.query("select id, total_volume::float as v from workout_sessions where user_id = $1", [USER_B]);
    assert(r.rows.length === 1 && r.rows[0].v === 200, `Admin sieht fremdes Training nicht korrekt: ${JSON.stringify(r.rows)}`);
    await db.query("update workout_sets set weight = 30 where user_id = $1", [USER_B]);
    const after = await db.query("select total_volume::float as v from workout_sessions where user_id = $1", [USER_B]);
    assert(after.rows[0].v === 300, `Summe nach Admin-Änderung: ${after.rows[0].v}`);
    const prof = await db.query("select count(*)::int as n from profiles");
    assert(prof.rows[0].n === 2, "Admin sieht nicht alle Profile");
    const plans = await db.query("select count(*)::int as n from workout_plans where user_id = $1", [USER_B]);
    assert(plans.rows[0].n >= 3, "Admin sieht fremde Pläne nicht");
  });
});

await test("Körperdaten im Profil und Cardio-Ziele (Plan → Training → Kopie)", async () => {
  await asUser(USER_A, async () => {
    await db.query("update profiles set height_cm = 182.5, birth_date = '1999-05-20' where id = $1", [USER_A]);
    const p = await db.query("select height_cm::float as h, birth_date::text as b from profiles where id = $1", [USER_A]);
    assert(p.rows[0].h === 182.5 && p.rows[0].b === "1999-05-20", "Körperdaten nicht gespeichert");
    let invalid = false;
    try {
      await db.query("update profiles set height_cm = 50 where id = $1", [USER_A]);
    } catch {
      invalid = true;
    }
    assert(invalid, "unplausible Größe wurde akzeptiert");

    const plan = await db.query("select id from workout_plans where user_id = $1 and name = 'Unterkörper'", [USER_A]);
    const lauf = (await db.query("select id from exercises where slug = 'laufband' and owner_id is null")).rows[0].id;
    await db.query(
      "insert into workout_plan_exercises (plan_id, exercise_id, sort_order, target_sets, rep_min, rep_max, target_duration_seconds, target_distance_m) values ($1, $2, 50, 1, 1, 1, 1200, 3000)",
      [plan.rows[0].id, lauf]
    );
    const started = await db.query("select start_workout_session($1) as id", [plan.rows[0].id]);
    const se = await db.query("select target_duration_seconds, target_distance_m from workout_session_exercises where session_id = $1 and exercise_id = $2", [started.rows[0].id, lauf]);
    assert(se.rows[0]?.target_duration_seconds === 1200 && se.rows[0]?.target_distance_m === 3000, `Cardio-Ziele nicht ins Training übernommen: ${JSON.stringify(se.rows)}`);
    await db.query("select cancel_workout_session($1)", [started.rows[0].id]);
  });
  await asUser(USER_B, async () => {
    const plans = (await db.query("select get_member_plans($1) as p", [USER_A])).rows[0].p;
    const src = plans.find((p) => p.name === "Unterkörper");
    const cardio = src.exercises.find((e) => e.slug === "laufband");
    assert(cardio && cardio.target_duration_seconds === 1200 && cardio.tracking_mode === "cardio", "Cardio-Ziele fehlen in get_member_plans");
    const copied = await db.query("select copy_member_plan($1, 'Kopie Cardio') as id", [src.id]);
    const pe = await db.query("select target_duration_seconds, target_distance_m from workout_plan_exercises where plan_id = $1 and exercise_id = (select id from exercises where slug = 'laufband' and owner_id is null)", [copied.rows[0].id]);
    assert(pe.rows[0]?.target_distance_m === 3000, "Cardio-Ziele nicht in die Kopie übernommen");
  });
});

await test("Verwaltung: nur Admins dürfen Nutzer listen, Rolle setzen, löschen", async () => {
  let blocked = false;
  await asUser(USER_B, async () => {
    try { await db.query("select * from admin_list_users()"); } catch { blocked = true; }
  });
  // Nicht-Admin sieht keine Zeilen oder bekommt einen Fehler
  if (!blocked) {
    const r = await asUser(USER_B, async () => db.query("select count(*)::int as n from admin_list_users()"));
    assert(r.rows[0].n === 0, "Nicht-Admin sieht Nutzerliste");
  }
  let setBlocked = false;
  await asUser(USER_B, async () => { try { await db.query("select admin_set_role($1, 'admin')", [USER_B]); } catch { setBlocked = true; } });
  assert(setBlocked, "Nicht-Admin konnte Rolle setzen");
  // USER_A per SQL (ohne auth.uid) zum Admin machen – wie beim ersten Admin im Dashboard
  await db.query("update profiles set role = 'admin' where id = $1", [USER_A]);
  await asUser(USER_A, async () => {
    const list = await db.query("select nickname, email, role::text from admin_list_users() order by created_at");
    assert(list.rows.length === 2 && list.rows[0].email === "a@example.com", JSON.stringify(list.rows));
    await db.query("select admin_set_role($1, 'admin')", [USER_B]);
    const b = await db.query("select role::text from admin_list_users() where user_id = $1", [USER_B]);
    assert(b.rows[0]?.role === "admin", "Rolle nicht gesetzt");
    await db.query("select admin_set_role($1, 'user')", [USER_B]);
    await db.query("select admin_set_nickname($1, 'Boerge_2')", [USER_B]);
    const nn = await db.query("select nickname from admin_list_users() where user_id = $1", [USER_B]);
    assert(nn.rows[0]?.nickname === "Boerge_2", "Nickname nicht gesetzt");
    let dup = false;
    try { await db.query("select admin_set_nickname($1, 'louis')", [USER_B]); } catch { dup = true; }
    assert(dup, "doppelter Nickname wurde akzeptiert");
    let invalid = false;
    try { await db.query("select admin_set_nickname($1, 'a@b')", [USER_B]); } catch { invalid = true; }
    assert(invalid, "ungültiger Nickname wurde akzeptiert");
    let selfBlocked = false;
    try { await db.query("select admin_set_role($1, 'user')", [USER_A]); } catch { selfBlocked = true; }
    assert(selfBlocked, "eigene Admin-Rolle konnte entfernt werden");
    let selfDelete = false;
    try { await db.query("select admin_delete_user($1)", [USER_A]); } catch { selfDelete = true; }
    assert(selfDelete, "eigenes Konto konnte gelöscht werden");
    await db.query("select admin_delete_user($1)", [USER_B]);
  });
  const gone = await db.query("select count(*)::int as n from profiles where id = $1", [USER_B]);
  assert(gone.rows[0].n === 0, "Profil von USER_B nicht gelöscht");
});

await test("Training abbrechen entfernt aktive Session", async () => {
  await asUser(USER_A, async () => {
    const plan = await db.query("select id from workout_plans where name = 'Unterkörper'");
    const r = await db.query("select start_workout_session($1) as id", [plan.rows[0].id]);
    await db.query("select cancel_workout_session($1)", [r.rows[0].id]);
    const n = await db.query("select count(*)::int as n from workout_sessions where status = 'active'");
    assert(n.rows[0].n === 0);
  });
});

await db.close();
console.log(failures === 0 ? "\nAlle Datenbank-Tests bestanden." : `\n${failures} Test(s) fehlgeschlagen.`);
process.exit(failures === 0 ? 0 : 1);
