import Link from "next/link";
import { ArrowRight, Play, ClipboardList, History, TrendingUp } from "lucide-react";
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

export const metadata = { title: "Dashboard" };

export default async function DashboardPage() {
  const { supabase, user, profile, settings } = await requireUser();
  const weekAgo = subDays(new Date(), 7).toISOString();

  const [plans, activeSession, recentSessions, stats, weekSessions, points] = await Promise.all([
    listPlans(supabase, user.id),
    getActiveSession(supabase, user.id),
    listSessions(supabase, user.id, { limit: 5 }),
    getUserStats(supabase),
    listSessions(supabase, user.id, { from: weekAgo }),
    getSessionPoints(supabase, user.id, subDays(new Date(), 60).toISOString()),
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
      <header>
        <p className="text-sm text-muted">Hallo {profile.nickname}</p>
        <h1 className="text-3xl font-extrabold tracking-[-0.03em] sm:text-4xl">Dashboard</h1>
      </header>

      {/* Nächstes Training / Aktives Training */}
      <Card className="border-accent/30">
        <CardContent className="pt-5">
          {activeSession ? (
            <>
              <SectionLabel>Aktives Training</SectionLabel>
              <p className="mt-1 text-xl font-semibold">{activeSession.name}</p>
              <p className="text-sm text-muted">Gestartet {formatRelativeDay(activeSession.started_at)}</p>
              <Link href={`/workout/${activeSession.id}`} className="mt-4 block">
                <Button size="lg" fullWidth>
                  <Play className="h-4 w-4" /> Training fortsetzen
                </Button>
              </Link>
            </>
          ) : nextPlan ? (
            <>
              <SectionLabel>Nächstes Training</SectionLabel>
              <p className="mt-1 text-xl font-semibold">{nextPlan.name}</p>
              <p className="text-sm text-muted">
                {nextPlan.exercises.length} Übungen ·{" "}
                {nextPlan.exercises.reduce((s, e) => s + e.target_sets, 0)} Sätze geplant
              </p>
              <div className="mt-4 flex gap-2">
                <Link href={`/workout?plan=${nextPlan.id}`} className="flex-1">
                  <Button size="lg" fullWidth>
                    <Play className="h-4 w-4" /> Training starten
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

      {/* Letztes Training */}
      <Card>
        <CardContent className="pt-5">
          <div className="flex items-center justify-between">
            <SectionLabel>Letztes Training</SectionLabel>
            {lastSession ? (
              <Link href={`/history/${lastSession.id}`} className="text-xs font-medium text-accent">
                Details
              </Link>
            ) : null}
          </div>
          {lastSession ? (
            <div className="mt-2">
              <p className="text-lg font-semibold">{lastSession.name}</p>
              <p className="text-sm text-muted">{formatRelativeDay(lastSession.started_at)}</p>
              <div className="mt-3 grid grid-cols-3 gap-2 text-center">
                <Mini label="Dauer" value={formatDuration(lastSession.duration_seconds)} />
                <Mini label="Sätze" value={String(lastSession.total_sets)} />
                <Mini label="Volumen" value={formatVolume(lastSession.total_volume, unit)} />
              </div>
            </div>
          ) : (
            <p className="mt-2 text-sm text-muted">Noch kein Training abgeschlossen.</p>
          )}
        </CardContent>
      </Card>

      {/* Fortschritt */}
      <Card>
        <CardContent className="pt-5">
          <div className="flex items-center justify-between">
            <SectionLabel>Volumen je Training</SectionLabel>
            <Link href="/progress" className="text-xs font-medium text-accent">
              Fortschritt
            </Link>
          </div>
          <div className="mt-3">
            <TrendChart data={chartData} type="bar" height={150} format={{ kind: "volume", unit }} emptyLabel="Nach dem ersten Training erscheint hier dein Volumenverlauf." />
          </div>
        </CardContent>
      </Card>

      {/* Quick Stats */}
      <section>
        <SectionLabel className="mb-2 px-1">Letzte 7 Tage</SectionLabel>
        <div className="grid grid-cols-3 gap-3">
          <Stat label="Trainings" value={weekSessions.length} />
          <Stat label="Zeit" value={formatDuration(weekDuration)} />
          <Stat label="Volumen" value={formatVolume(weekVolume, unit)} />
        </div>
      </section>

      <section>
        <SectionLabel className="mb-2 px-1">Gesamt</SectionLabel>
        <div className="grid grid-cols-3 gap-3">
          <Stat label="Trainings" value={stats.total_workouts} />
          <Stat label="Zeit" value={formatDuration(stats.total_duration_seconds)} />
          <Stat label="Volumen" value={formatVolume(stats.total_volume, unit)} />
        </div>
      </section>

      {/* Schnellzugriff */}
      <div className="grid grid-cols-3 gap-3">
        <QuickLink href="/plans" icon={<ClipboardList className="h-5 w-5" />} label="Pläne" />
        <QuickLink href="/history" icon={<History className="h-5 w-5" />} label="Historie" />
        <QuickLink href="/progress" icon={<TrendingUp className="h-5 w-5" />} label="Fortschritt" />
      </div>

      {/* Letzte Trainings */}
      {recentSessions.length > 0 ? (
        <section>
          <div className="mb-2 flex items-center justify-between px-1">
            <SectionLabel>Letzte Trainings</SectionLabel>
            <Link href="/history" className="text-xs font-medium text-accent">
              Alle
            </Link>
          </div>
          <Card className="divide-y divide-border overflow-hidden">
            {recentSessions.map((s) => (
              <Link key={s.id} href={`/history/${s.id}`} className="flex items-center justify-between gap-3 px-5 py-3.5 hover:bg-subtle">
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium">{s.name}</p>
                  <p className="text-xs text-muted">
                    {formatRelativeDay(s.started_at)} · {formatDuration(s.duration_seconds)} · {s.total_sets} Sätze
                  </p>
                </div>
                <div className="flex items-center gap-2">
                  <span className="tnum text-sm text-muted">{formatVolume(s.total_volume, unit)}</span>
                  <ArrowRight className="h-4 w-4 text-faint" />
                </div>
              </Link>
            ))}
          </Card>
        </section>
      ) : null}
    </div>
  );
}

function Mini({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg bg-subtle px-2 py-2">
      <p className="text-[10px] font-medium uppercase tracking-wider text-faint">{label}</p>
      <p className="tnum mt-0.5 text-sm font-semibold">{value}</p>
    </div>
  );
}

function QuickLink({ href, icon, label }: { href: string; icon: React.ReactNode; label: string }) {
  return (
    <Link
      href={href}
      className="card-interactive press flex h-20 flex-col items-center justify-center gap-1.5 rounded-[var(--radius-card)] border border-border bg-card text-sm font-medium text-muted hover:bg-subtle hover:text-fg"
    >
      {icon}
      {label}
    </Link>
  );
}
