# Trainingslog

Private Fitness-Tracking-Web-App für eine kleine Gruppe. Trainingspläne, satzgenaues Tracking mit Progressive Overload, Historie, Fortschrittsgrafiken, Übungsdatenbank mit Muskelkarte, Kalender und Gruppen-Stats. Dark Mode, Mobile First, keine KI, keine Social-Funktionen.

## Tech Stack

| Bereich | Technologie |
|---|---|
| Frontend | Next.js 15 (App Router), React 19, TypeScript (strict) |
| Styling | Tailwind CSS 4, eigene Design-Tokens (Dark/Light) |
| Backend / DB / Auth | Supabase (Postgres, Auth, Row Level Security, optional Storage) |
| Charts | Recharts |
| Deployment | Vercel |
| Kosten | läuft innerhalb der kostenlosen Kontingente von Supabase und Vercel |

Keine OpenAI-/Claude-API, keine Analytics, keine Payments, keine externen Bilddatenbanken.

## Funktionen

- **Auth**: E-Mail + Passwort, Registrierung mit Nickname, Passwort vergessen, Logout, geschützte Routen (Middleware).
- **Dashboard**: tägliches Motivationszitat, nächstes Training (Rotation A → B → C), letztes Training, Volumenverlauf, 7-Tage- und Gesamtstatistik, Schnellzugriffe.
- **Trainingspläne**: drei vorkonfigurierte Pläne (Oberkörper A, Unterkörper, Oberkörper B) pro Benutzer aus Vorlagen kopiert; Übungen hinzufügen, entfernen, austauschen, sortieren, Sätze und Wiederholungsbereich ändern, umbenennen, duplizieren, neue Pläne.
- **Aktives Training**: große +/- Eingaben für Gewicht und Wiederholungen, optional RIR, Aufwärmsätze, vorherige Werte, Double-Progression-Vorschlag („Gewicht erhöhen/halten“), Trainingsdauer, Rest Timer (60/90/120/180 s oder eigene Zeit), Übung spontan hinzufügen, lokaler Zwischenstand (localStorage) mit Synchronisierung nach Verbindungsabbruch.
- **Historie**: Liste mit Filtern (Zeitraum, Training, Übung), Detailansicht mit allen Sätzen und Volumen, Notizen.
- **Fortschritt**: Zeiträume 1 W / 1 M / 6 M / 12 M / Gesamt; Volumen, Trainingsanzahl, Dauer, Körpergewicht (optional), Kraftentwicklung je Übung (Top-Satz, Wiederholungen, geschätztes 1RM, Volumen), Bestleistungen.
- **Übungsdatenbank**: 50 Standardübungen mit Setup, Ausführung, Bewegungsradius, Atmung, Fehlern, Tipps; Kabelübungen mit konkretem Griff (Griff-Icons) und vollständigem Kabel-Setup; wiederverwendbare SVG-Muskelkarte (Front/Rück) mit primären und sekundären Muskeln; Favoriten; eigene Übungen.
- **Kalender**: Monatsansicht, ±10 Jahre, Tage als Training / Rest Day / Freizeit / Party / Anderer Tag markieren, Notizen; abgeschlossene Trainings werden automatisch eingetragen.
- **Stats**: private Übersicht aller Mitglieder (Nickname, Trainings, Zeit, Volumen, letztes Training), nur für angemeldete Benutzer.
- **Profil & Einstellungen**: Nickname, E-Mail, Passwort, Gewichtseinheit, Gewichtsschritt, Rest-Timer-Standard, RIR anzeigen, Theme.

## Lokale Installation

Voraussetzungen: Node.js ≥ 20, npm, ein Supabase-Projekt (kostenloser Plan reicht).

```bash
npm install
cp .env.example .env.local   # Werte eintragen, siehe unten
npm run dev                  # http://localhost:3000
```

Solange `.env.local` fehlt oder Platzhalter enthält, zeigt die App eine Setup-Seite.

## Environment Variables

| Variable | Beschreibung |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Projekt-URL, z. B. `https://abcdefgh.supabase.co` (Dashboard → Project Settings → API) |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Publishable Key (`sb_publishable_…`) bzw. Anon Key |
| `NEXT_PUBLIC_SITE_URL` | optional, Basis-URL der App für E-Mail-Redirects |

Niemals echte Keys ins Repository committen. `.env.local` ist über `.gitignore` ausgeschlossen, `.env.example` enthält nur Platzhalter.

## Supabase Setup

### 1. Datenbank einrichten

Variante A (ohne CLI, empfohlen für den Start): Im Supabase Dashboard unter **SQL Editor** den Inhalt von [`supabase/bundle.sql`](supabase/bundle.sql) einfügen und ausführen. Die Datei enthält alle Migrationen in der richtigen Reihenfolge.

Variante B (Supabase CLI):

```bash
supabase link --project-ref <project-ref>
supabase db push          # führt supabase/migrations/*.sql aus
```

Migrationen:

| Datei | Inhalt |
|---|---|
| `0001_schema.sql` | Tabellen, Enums, Indexe, Foreign Keys, `updated_at`-Trigger |
| `0002_functions.sql` | Trigger für neue Benutzer, RPCs (Training starten/abschließen, Statistiken, Bestleistungen), Seed-Hilfsfunktionen |
| `0003_rls.sql` | Row Level Security für alle Tabellen |
| `0004_seed_static.sql` | Muskelgruppen, Griffe, Motivationszitate |
| `0005_seed_exercises.sql` | 50 Standardübungen (generiert) |
| `0006_seed_templates.sql` | drei Standard-Trainingspläne (generiert) |

Die Migrationen sind idempotent bezüglich der Seed-Daten (Upsert) und können nach Anpassungen erneut ausgeführt werden.

### 2. Seed-Daten pflegen

Die Übungen liegen als JSON in `supabase/seed/exercises/*.json` (Schema: `supabase/seed/SCHEMA.md`), die Vorlagenpläne in `supabase/seed/templates.json`. Nach Änderungen:

```bash
npm run db:generate   # validiert die JSON-Dateien, erzeugt 0005/0006 und supabase/bundle.sql
```

Danach die erzeugte SQL erneut in Supabase ausführen.

### 3. Auth konfigurieren

Im Dashboard unter **Authentication → URL Configuration**:

- Site URL: lokal `http://localhost:3000`, später die Vercel-URL.
- Redirect URLs: `http://localhost:3000/**` und `https://<deine-app>.vercel.app/**`.

Unter **Authentication → Providers → Email** bleibt nur E-Mail/Passwort aktiv (keine Social Logins).

Empfohlen für geräteübergreifende Bestätigungslinks (**Authentication → Email Templates**):

- Confirm signup: `{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=email&next=/dashboard`
- Reset password: `{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=recovery&next=/reset-password`
- Change email: `{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=email_change&next=/settings`

Die Standard-Templates funktionieren ebenfalls (Route `/auth/callback`), dann muss der Link aber auf demselben Gerät geöffnet werden, auf dem die Aktion gestartet wurde.

Optional kann „Confirm email“ deaktiviert werden, dann sind Benutzer nach der Registrierung sofort angemeldet.

### 4. Storage (optional)

Bilder sind nicht erforderlich; jede Übung funktioniert mit `image_url = NULL` und einem einheitlichen Placeholder. Für eigene Bilder:

1. Bucket `exercise-assets` anlegen (öffentlich lesbar für Standardübungen).
2. Datei hochladen, öffentliche URL in `exercises.image_url` eintragen (Standardübungen über SQL/Admin, eigene Übungen über das Formular).

## Benutzerablauf

1. Registrieren (E-Mail, Passwort, Passwort bestätigen, Nickname) → E-Mail bestätigen → anmelden.
2. Der Datenbank-Trigger `handle_new_user` legt Profil, Einstellungen und die drei Standardpläne an.
3. Dashboard → Training starten → Sätze speichern → Training abschließen.
4. Historie, Fortschritt, Kalender und Stats füllen sich automatisch.

Der erste Admin (optional) wird per SQL gesetzt: `update profiles set role = 'admin' where nickname = '…';` Admins dürfen Standardübungen pflegen.

## Tests und Qualität

```bash
npm run typecheck   # TypeScript strict
npm run lint        # ESLint (next/core-web-vitals)
npm run test:db     # führt alle Migrationen in einer eingebetteten Postgres-Instanz (PGlite) aus
                    # und prüft Registrierung, RLS-Trennung, Training starten/abschließen,
                    # Sätze speichern, Statistiken, eigene Übungen, Kalender
npm run check       # alle drei zusammen
npm run build       # Produktions-Build
```

Manuell geprüft werden sollten zusätzlich: Login/Logout, Plan bearbeiten, Übung hinzufügen, Progress-Grafiken und das Mobile-Layout (Bottom Navigation, Tracking-Ansicht).

## Vercel Deployment

1. Repository auf GitHub pushen.
2. In Vercel **New Project** → Repository importieren (Framework: Next.js, keine weiteren Einstellungen nötig).
3. Environment Variables setzen: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` (Production und Preview).
4. Deploy. Danach die Vercel-URL in Supabase als Site URL / Redirect URL eintragen.

Jeder Push auf `main` löst ein Production-Deployment aus, Pull Requests erhalten Preview-Deployments.

## GitHub Workflow

- `main` ist deploybar. Features in Branches entwickeln, per Pull Request mergen.
- Vor dem Commit: `npm run check`.
- Keine Secrets committen (`.env*` ist ignoriert, nur `.env.example` ist versioniert).

## Projektstruktur

```
src/
  app/                 Routen (App Router)
    (auth)/            login, register, forgot-password, reset-password
    (app)/             dashboard, workout, plans, history, progress, exercises, calendar, stats, profile, settings, more
    auth/              Route Handler: callback, confirm, signout
  components/          UI-Primitives, Navigation, Muskelkarte, Feature-Komponenten
  lib/
    supabase/          Browser-/Server-Client, Middleware, Datenbank-Typen
    services/          Datenzugriff (profile, exercises, plans, sessions, stats, calendar, quotes)
    utils/             Formatierung, Labels, Progression, Fehlertexte
    validation/        Zod-Schemas
supabase/
  migrations/          SQL-Migrationen (reproduzierbar)
  seed/                Übungs- und Vorlagen-JSON + Schema
  bundle.sql           alle Migrationen in einer Datei (generiert)
scripts/               generate-seed.mjs, test-db.mjs
```

## Datenmodell (Kurzfassung)

`profiles`, `user_settings`, `muscle_groups`, `grips`, `exercises`, `exercise_muscles`, `workout_plan_templates`, `workout_plan_template_exercises`, `workout_plans`, `workout_plan_exercises`, `workout_sessions`, `workout_session_exercises`, `workout_sets`, `calendar_entries`, `favorites`, `quotes`, `body_weight_entries`.

Alle benutzerbezogenen Tabellen tragen `user_id` bzw. `owner_id` und sind per RLS auf `auth.uid()` beschränkt. Standardübungen (`owner_id IS NULL`) sind für alle angemeldeten Benutzer lesbar, aber nur für Admins veränderbar. Vorlagenpläne und Benutzerpläne sind getrennt, sodass Vorlagen später aktualisiert werden können, ohne bestehende Pläne zu verändern.

## Lizenz / Assets

Alle Grafiken (Logo, Muskelkarte, Griff- und Equipment-Icons) sind eigene SVGs. Motivationssätze sind eigene Formulierungen. Keine fremden App-Assets.
