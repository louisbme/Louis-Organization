import Link from "next/link";
import { Play, ClipboardList, CalendarDays, Users } from "lucide-react";
import { subDays } from "date-fns";
import { requireUser } from "@/lib/auth/require-user";
import { listPlans, getNextPlanInRotation } from "@/lib/services/plans";
import { getActiveSession, listSessions } from "@/lib/services/sessions";
import { getUserStats, getSessionPoints } from "@/lib/services/stats";
import { formatDate, formatDuration, formatRelativeDay, formatVolume } from "@/lib/utils/format";
import { TrendChart, type TrendPoint } from "@/components/charts/trend-chart";
import { Button } from "@/components/ui/button";
import { Card, CardContent, SectionLabel } from "@/components/ui/card";
import { Stat } from "@/components/ui/stat";
import { EmptyState } from "@/components/ui/states";
import { AvatarLink } from "@/components/ui/avatar";
import { List, ListHeader, ListRow } from "@/components/ui/list";

export const metadata = { title: "Start" };

function greeting(date: Date): string {
  const h = date.getHours();
  if (h < 5) return "Gute Nacht";
  if (h < 11) return "Guten Morgen";
  if (h < 18) return "Hallo";
  return "Guten Abend";
}

export default async function DashboardPage() {
  const { supabase, user, profile, settings } = await requireUser();
  const now = new Date();
  const weekAgo = subDays(now, 7).toISOString();

  const [plans, activeSession, recentSessions, stats, weekSessions, points] = await Promise.all([
    listPlans(supabase, user.id),
    getActiveSession(supabase, user.id),
    listSessions(supabase, user.id, { limit: 5 }),
    getUserStats(supabase),
    listSessions(supabase, user.id, { from: weekAgo }),
    getSessionPoints(supabase, user.id, subDays(now, 60).toISOString()),
  ]);

  const lastSession = recentSessions[0] ?? null;
  const nextPlan = getNextPlanInRotation(plans, lastSession?.plan_id ?? null);
  const unit = settings.weight_unit;

  const weekDuration = weekSessions.reduce((s, x) => s + (x.duration_seconds ?? 0), 0);
  const weekVolume = weekSessions.reduce((s, x) => s + x.total_volume, 0);

  const chartData: TrendPoint[] = points.slice(-10).map((p) => ({
    x: formatDate(p.started_at, "d.M."),
    label: formatDate(p.started_at, "EEE, d. MMM"),
    y: p.total_volume,
    extra: `${p.total_sets} Sätze · ${formatDuration(p.duration_seconds)}`,
  }));

  return (
    <div className="stagger space-y-5">
      <header className="flex items-end justify-between gap-4">
        <div className="min-w-0">
          <p className="text-[13px] font-semibold uppercase tracking-[0.06em] text-muted">{formatDate(now, "EEEE, d. MMMM")}</p>
          <h1 className="text-balance text-3xl leading-[1.1] text-fg">
            {greeting(now)}, {profile.nickname}
          </h1>
        </div>
        <AvatarLink name={profile.nickname} className="lg:hidden" />
      </header>

      {/* Nächstes Training / Aktives Training */}
      <Card className={activeSession ? "ring-1 ring-accent/40" : undefined}>
        <CardContent className="pt-5">
          {activeSession ? (
            <>
              <SectionLabel className="text-accent">Aktives Training</SectionLabel>
              <p className="mt-1 text-xl font-semibold">{activeSession.name}</p>
              <p className="text-sm text-muted">Gestartet {formatRelativeDay(activeSession.started_at).toLowerCase()}</p>
              <Link href={`/workout/${activeSession.id}`} className="mt-4 block">
                <Button size="lg" fullWidth>
                  <Play className="h-4 w-4" fill="currentColor" /> Training fortsetzen
                </Button>
              </Link>
            </>
          ) : nextPlan ? (
            <>
              <SectionLabel>Nächstes Training</SectionLabel>
              <p className="mt-1 text-xl font-semibold">{nextPlan.name}</p>
              <p className="text-sm text-muted">
                {nextPlan.exercises.length} Übungen · {nextPlan.exercises.reduce((s, e) => s + e.target_sets, 0)} Sätze geplant
              </p>
              <div className="mt-4 flex gap-2">
                <Link href={`/workout?plan=${nextPlan.id}`} className="flex-1">
                  <Button size="lg" fullWidth>
                    <Play className="h-4 w-4" fill="currentColor" /> Training starten
                  </Button>
                </Link>
                <Link href="/workout">
                  <Button size="lg" variant="secondary">
                    Anderes
                  </Button>
                </Link>
              </div>
            </>
          ) : (
            <EmptyState
              title="Noch kein Trainingsplan"
              description="Lege einen Plan an, um ein Training zu starten."
              action={
                <Link href="/plans">
                  <Button>Plan erstellen</Button>
                </Link>
              }
            />
          )}
        </CardContent>
      </Card>

      {/* Letzte 7 Tage */}
      <section>
        <ListHeader>Letzte 7 Tage</ListHeader>
        <div className="grid grid-cols-3 gap-3">
          <Stat label="Trainings" value={weekSessions.length} />
          <Stat label="Zeit" value={formatDuration(weekDuration)} />
          <Stat label="Volumen" value={formatVolume(weekVolume, unit)} />
        </div>
      </section>

      {/* Volumenverlauf */}
      <Card>
        <CardContent className="pt-5">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-base font-semibold">Volumen je Training</p>
              <p className="text-sm text-muted">Letzte 10 Trainings</p>
            </div>
            <Link href="/progress" className="text-sm font-semibold text-accent">
              Fortschritt
            </Link>
          </div>
          <div className="mt-3">
            <TrendChart data={chartData} type="bar" height={150} format={{ kind: "volume", unit }} emptyLabel="Nach dem ersten Training erscheint hier dein Volumenverlauf." />
          </div>
        </CardContent>
      </Card>

      {/* Letzte Trainings */}
      {recentSessions.length > 0 ? (
        <section>
          <ListHeader
            trailing={
              <Link href="/history" className="font-semibold text-accent">
                Alle
              </Link>
            }
          >
            Letzte Trainings
          </ListHeader>
          <List>
            {recentSessions.map((s) => (
              <ListRow
                key={s.id}
                href={`/history/${s.id}`}
                title={s.name}
                subtitle={`${formatRelativeDay(s.started_at)} · ${formatDuration(s.duration_seconds)} · ${s.total_sets} Sätze`}
                trailing={formatVolume(s.total_volume, unit)}
                chevron
              />
            ))}
          </List>
        </section>
      ) : null}

      {/* Gesamt */}
      <section>
        <ListHeader>Gesamt</ListHeader>
        <div className="grid grid-cols-3 gap-3">
          <Stat label="Trainings" value={stats.total_workouts} />
          <Stat label="Zeit" value={formatDuration(stats.total_duration_seconds)} />
          <Stat label="Volumen" value={formatVolume(stats.total_volume, unit)} />
        </div>
      </section>

      {/* Schnellzugriff */}
      <List>
        <ListRow href="/plans" leading={<ClipboardList className="h-5 w-5" strokeWidth={1.9} />} title="Trainingspläne" chevron />
        <ListRow href="/calendar" leading={<CalendarDays className="h-5 w-5" strokeWidth={1.9} />} title="Kalender" chevron />
        <ListRow href="/stats" leading={<Users className="h-5 w-5" strokeWidth={1.9} />} title="Gruppen-Stats" chevron />
      </List>
    </div>
  );
}
