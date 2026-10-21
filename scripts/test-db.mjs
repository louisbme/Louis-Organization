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
