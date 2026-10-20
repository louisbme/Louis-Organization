#!/usr/bin/env node
/**
 * Spielt alle Migrationen über die Supabase Management API ein (ohne Supabase CLI).
 *
 * Benötigt:
 *   SUPABASE_ACCESS_TOKEN  Personal Access Token (sbp_...), erstellen unter
 *                          https://supabase.com/dashboard/account/tokens
 *   SUPABASE_PROJECT_REF   Projekt-Referenz (der Teil vor .supabase.co), oder
 *                          wird aus NEXT_PUBLIC_SUPABASE_URL in .env.local abgeleitet
 *
 * Aufruf: SUPABASE_ACCESS_TOKEN=sbp_... npm run db:apply
 * Der Token wird nur für diesen Lauf verwendet und nirgends gespeichert.
 */
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const token = process.env.SUPABASE_ACCESS_TOKEN;
if (!token) {
  console.error("SUPABASE_ACCESS_TOKEN fehlt (Personal Access Token, beginnt mit sbp_).");
  process.exit(1);
}

let ref = process.env.SUPABASE_PROJECT_REF;
if (!ref) {
  const envPath = join(root, ".env.local");
  if (existsSync(envPath)) {
    const m = readFileSync(envPath, "utf8").match(/NEXT_PUBLIC_SUPABASE_URL=https:\/\/([a-z0-9]+)\.supabase\.co/);
    if (m) ref = m[1];
  }
}
if (!ref) {
  console.error("SUPABASE_PROJECT_REF fehlt und konnte nicht aus .env.local abgeleitet werden.");
  process.exit(1);
}

const migrationsDir = join(root, "supabase", "migrations");
const files = readdirSync(migrationsDir).filter((f) => f.endsWith(".sql")).sort();
const only = process.argv.slice(2);
const selected = only.length ? files.filter((f) => only.some((o) => f.includes(o))) : files;

async function runSql(query) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ query }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${text.slice(0, 500)}`);
  return text;
}

console.log(`Projekt ${ref}: ${selected.length} Migration(en)`);
for (const file of selected) {
  const sql = readFileSync(join(migrationsDir, file), "utf8");
  process.stdout.write(`  ${file} … `);
  try {
    await runSql(sql);
    console.log("ok");
  } catch (e) {
    console.log("FEHLER");
    console.error(`    ${e.message}`);
    process.exit(1);
  }
}

const check = await runSql(
  "select (select count(*) from public.exercises) as exercises, (select count(*) from public.workout_plan_templates) as templates, (select count(*) from public.quotes) as quotes"
);
console.log("Prüfung:", check);
console.log("Fertig.");
