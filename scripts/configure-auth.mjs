#!/usr/bin/env node
/**
 * Setzt die Supabase-Auth-Konfiguration über die Management API:
 *   - Site URL und erlaubte Redirect-URLs
 *   - E-Mail-Templates auf token_hash-Links (geräteübergreifend gültig)
 *
 * Benötigt SUPABASE_ACCESS_TOKEN (sbp_...), optional SUPABASE_PROJECT_REF
 * (sonst aus NEXT_PUBLIC_SUPABASE_URL in .env.local), SITE_URL und
 * MAILER_AUTOCONFIRM=false, falls neue Nutzer ihre E-Mail bestätigen sollen.
 *
 * Aufruf: SUPABASE_ACCESS_TOKEN=sbp_... SITE_URL=https://deine-app.vercel.app npm run auth:configure
 * Mit eigenen E-Mail-Templates (nur mit SMTP-Provider/bezahltem Plan): ... npm run auth:configure -- --with-templates
 */
import { existsSync, readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const token = process.env.SUPABASE_ACCESS_TOKEN;
if (!token) {
  console.error("SUPABASE_ACCESS_TOKEN fehlt.");
  process.exit(1);
}
let ref = process.env.SUPABASE_PROJECT_REF;
if (!ref && existsSync(join(root, ".env.local"))) {
  const m = readFileSync(join(root, ".env.local"), "utf8").match(/NEXT_PUBLIC_SUPABASE_URL=https:\/\/([a-z0-9]+)\.supabase\.co/);
  if (m) ref = m[1];
}
if (!ref) {
  console.error("SUPABASE_PROJECT_REF fehlt.");
  process.exit(1);
}
const siteUrl = (process.env.SITE_URL ?? "https://trainingslog-psi.vercel.app").replace(/\/$/, "");
const allowList = [`${siteUrl}/**`, "http://localhost:3000/**"].join(",");

const base = `https://api.supabase.com/v1/projects/${ref}/config/auth`;
const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };

const before = await (await fetch(base, { headers })).json();
console.log("Vorher:", { site_url: before.site_url, uri_allow_list: before.uri_allow_list, mailer_autoconfirm: before.mailer_autoconfirm });

const autoconfirm = process.env.MAILER_AUTOCONFIRM !== "false";
const withTemplates = process.argv.includes("--with-templates");

const link = (type, next) => `<p><a href="{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=${type}&next=${next}">`;
const templates = {
  mailer_subjects_confirmation: "Trainingslog: E-Mail bestätigen",
  mailer_templates_confirmation_content: `<h2>Willkommen bei Trainingslog</h2><p>Bitte bestätige deine E-Mail-Adresse:</p>${link("email", "/dashboard")}E-Mail bestätigen</a></p>`,
  mailer_subjects_recovery: "Trainingslog: Passwort zurücksetzen",
  mailer_templates_recovery_content: `<h2>Passwort zurücksetzen</h2><p>Klicke auf den Link, um ein neues Passwort zu vergeben:</p>${link("recovery", "/reset-password")}Neues Passwort festlegen</a></p>`,
  mailer_subjects_email_change: "Trainingslog: E-Mail-Änderung bestätigen",
  mailer_templates_email_change_content: `<h2>E-Mail-Adresse ändern</h2><p>Bestätige die Änderung deiner E-Mail-Adresse auf {{ .NewEmail }}:</p>${link("email_change", "/settings")}Änderung bestätigen</a></p>`,
};

// Basis: URLs + Autoconfirm. E-Mail-Templates nur mit --with-templates
// (im Free Tier nur mit eigenem SMTP-Provider änderbar).
const patch = {
  site_url: siteUrl,
  uri_allow_list: allowList,
  mailer_autoconfirm: autoconfirm,
  ...(withTemplates ? templates : {}),
};

const res = await fetch(base, { method: "PATCH", headers, body: JSON.stringify(patch) });
const text = await res.text();
if (!res.ok) {
  console.error(`Fehler HTTP ${res.status}: ${text.slice(0, 800)}`);
  process.exit(1);
}
const after = JSON.parse(text);
console.log("Nachher:", { site_url: after.site_url, uri_allow_list: after.uri_allow_list, mailer_autoconfirm: after.mailer_autoconfirm });
console.log(withTemplates ? "E-Mail-Templates gesetzt." : "E-Mail-Templates unverändert (Option --with-templates, benötigt eigenen SMTP-Provider oder bezahlten Plan).");
console.log("Fertig.");
