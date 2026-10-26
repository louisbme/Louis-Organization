import { notFound, redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/require-user";
import { getProfile } from "@/lib/services/profile";
import { listSessions } from "@/lib/services/sessions";
import { listPlans } from "@/lib/services/plans";
import { formatDuration, formatRelativeDay, formatVolume } from "@/lib/utils/format";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState } from "@/components/ui/states";
import { List, ListHeader, ListRow } from "@/components/ui/list";

export const metadata = { title: "Trainingsdaten" };

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Admin: Trainings und Pläne eines Nutzers öffnen und bearbeiten. */
export default async function AdminUserPage({ params }: { params: Promise<{ userId: string }> }) {
  const { userId } = await params;
  if (!UUID_RE.test(userId)) notFound();
  const { supabase, profile, settings } = await requireUser();
  if (profile.role !== "admin") redirect("/dashboard");
  const [target, sessions, plans] = await Promise.all([
    getProfile(supabase, userId),
    listSessions(supabase, userId, { limit: 200 }),
    listPlans(supabase, userId, true),
  ]);
  if (!target) notFound();
  const unit = settings.weight_unit;

  return (
    <div className="space-y-5">
      <PageHeader
        title={target.nickname}
        eyebrow="Trainingsdaten bearbeiten"
        backHref="/admin"
        backLabel="Verwaltung"
        description={`${sessions.length} Trainings · ${plans.length} Pläne. Änderungen wirken direkt im Konto von ${target.nickname}.`}
        compact
      />

      <section>
        <ListHeader>Trainingspläne</ListHeader>
        {plans.length === 0 ? (
          <EmptyState title="Keine Pläne" />
        ) : (
          <List>
            {plans.map((p) => (
              <ListRow
                key={p.id}
                href={`/plans/${p.id}`}
                title={p.name}
                subtitle={`${p.exercises.length} Übungen · ${p.exercises.reduce((s, e) => s + e.target_sets, 0)} Sätze${p.is_archived ? " · archiviert" : ""}`}
                chevron
              />
            ))}
          </List>
        )}
      </section>

      <section>
        <ListHeader trailing={String(sessions.length)}>Trainings</ListHeader>
        {sessions.length === 0 ? (
          <EmptyState title="Noch keine Trainings" />
        ) : (
          <List>
            {sessions.map((s) => (
              <ListRow
                key={s.id}
                href={`/history/${s.id}`}
                title={s.name}
                subtitle={
                  <>
                    {formatRelativeDay(s.started_at)} · {formatDuration(s.duration_seconds)} · {s.total_sets} Sätze
                    <span className="block truncate text-xs text-faint">{s.exercise_names.join(" · ")}</span>
                  </>
                }
                trailing={formatVolume(s.total_volume, unit)}
                chevron
              />
            ))}
          </List>
        )}
      </section>
    </div>
  );
}
