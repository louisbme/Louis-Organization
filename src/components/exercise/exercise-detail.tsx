import Link from "next/link";
import { ExternalLink, PlayCircle } from "lucide-react";
import type { ExerciseDetail as ExerciseDetailType } from "@/lib/services/exercises";
import type { ExerciseRecordsRow, GripRow } from "@/lib/supabase/types";
import { CATEGORY_LABELS, EQUIPMENT_LABELS, muscleLabel } from "@/lib/utils/labels";
import { formatClock, formatDate, formatDistance, formatPace, formatVolume, formatWeight } from "@/lib/utils/format";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, SectionLabel } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { MuscleList, MuscleMap } from "@/components/muscle-map/muscle-map";
import { GripIcon } from "@/components/exercise/grip-icon";
import { EquipmentIcon } from "@/components/exercise/equipment-icon";
import { ExerciseVisual } from "@/components/exercise/exercise-visual";
import { AddToPlanButton, CustomExerciseActions, FavoriteButton } from "@/components/exercise/exercise-actions";

interface Props {
  exercise: ExerciseDetailType;
  records: ExerciseRecordsRow | null;
  backHref?: string;
  /** Admin darf Standardübungen bearbeiten */
  canEditStandard?: boolean;
}

export function ExerciseDetail({ exercise, records, backHref = "/exercises", canEditStandard = false }: Props) {
  const showForearmHint =
    exercise.secondary_muscles.includes("forearms") && !exercise.primary_muscles.includes("forearms");
  const isCable = exercise.equipment === "cable";

  return (
    <div className="stagger space-y-5">
      <PageHeader
        title={exercise.name}
        eyebrow={`${CATEGORY_LABELS[exercise.category]} · ${EQUIPMENT_LABELS[exercise.equipment]}`}
        backHref={backHref}
        actions={<FavoriteButton exerciseId={exercise.id} initial={exercise.is_favorite} />}
      />

      {exercise.description ? <p className="text-sm leading-relaxed text-muted">{exercise.description}</p> : null}

      {/* Muskelkarte + Primär/Sekundär */}
      <Card>
        <CardContent className="pt-5">
          <MuscleMap primary={exercise.primary_muscles} secondary={exercise.secondary_muscles} />
          <div className="mt-5">
            <MuscleList primary={exercise.primary_muscles} secondary={exercise.secondary_muscles} label={muscleLabel} />
          </div>
          {showForearmHint ? <p className="mt-3 text-xs text-faint">Unterarme sekundär beteiligt (Griffkraft).</p> : null}
        </CardContent>
      </Card>

      {/* Kabelturm: Höhe und Griff zuerst */}
      {isCable && exercise.cable ? (
        <Card>
          <CardContent className="pt-5">
            <SectionLabel>Kabelturm</SectionLabel>
            {exercise.cable.seat_position && !exercise.cable.height ? (
              <div className="mt-3 flex items-start gap-4">
                <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-[var(--radius-control)] bg-subtle text-fg">
                  <SeatIcon />
                </div>
                <div className="min-w-0">
                  <p className="text-[11px] font-medium uppercase tracking-[0.12em] text-faint">Sitzposition</p>
                  <p className="text-sm leading-relaxed">{exercise.cable.seat_position}</p>
                  <p className="mt-1 text-xs text-faint">{exercise.cable.cable}</p>
                </div>
              </div>
            ) : (
              <div className="mt-3 flex items-start gap-4">
                <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-[var(--radius-control)] bg-subtle text-fg">
                  <CableHeightIcon height={exercise.cable.height} />
                </div>
                <div className="min-w-0">
                  <p className="text-[11px] font-medium uppercase tracking-[0.12em] text-faint">Rollenhöhe</p>
                  <p className="text-lg font-semibold">{heightLabel(exercise.cable.height)}</p>
                  <p className="mt-0.5 text-sm text-muted">{heightNote(exercise.cable.height)}</p>
                </div>
              </div>
            )}

            {exercise.grip ? (
              <div className="mt-5 border-t border-border pt-5">
                <p className="text-[11px] font-medium uppercase tracking-[0.12em] text-faint">Empfohlener Griff</p>
                <GripRowView grip={exercise.grip} highlight />
                {exercise.grip_notes ? <p className="mt-2 text-sm leading-relaxed text-muted">{exercise.grip_notes}</p> : null}
              </div>
            ) : null}

            {exercise.alternative_grips.length > 0 ? (
              <div className="mt-5 border-t border-border pt-5">
                <p className="text-[11px] font-medium uppercase tracking-[0.12em] text-faint">Alternative Griffe</p>
                <div className="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-2">
                  {exercise.alternative_grips.map((g) => (
                    <GripRowView key={g.id} grip={g} />
                  ))}
                </div>
              </div>
            ) : null}

            <dl className="mt-5 grid grid-cols-1 gap-x-6 gap-y-3 border-t border-border pt-5 sm:grid-cols-2">
              {(
                [
                  ["Griffbreite", exercise.cable.grip_width],
                  ["Körperposition", exercise.cable.body_position],
                  ["Fußposition", exercise.cable.foot_position],
                  ["Bewegungsrichtung", exercise.cable.movement_direction],
                  ["Ellenbogen", exercise.cable.elbow_position],
                  ["Endposition", exercise.cable.end_position],
                  ["Rückführung", exercise.cable.return],
                ] as const
              ).map(([label, value]) => (
                <div key={label}>
                  <dt className="text-xs font-medium text-faint">{label}</dt>
                  <dd className="mt-0.5 text-sm leading-relaxed">{value}</dd>
                </div>
              ))}
            </dl>
          </CardContent>
        </Card>
      ) : null}

      {/* Verwandte Übungen (ohne Gerätefotos) */}
      {exercise.alternatives.length > 0 ? (
        <Card>
          <CardContent className="pt-5">
            <SectionLabel>Alternativen</SectionLabel>
            <div className="no-scrollbar -mx-5 mt-3 flex gap-2 overflow-x-auto px-5 pb-1">
              {exercise.alternatives.map((alt) => (
                <Link
                  key={alt.slug}
                  href={`/exercises/${alt.slug}`}
                  className="press inline-flex h-9 shrink-0 items-center gap-1.5 rounded-full bg-subtle px-3.5 text-sm font-medium text-fg hover:bg-hover"
                >
                  {alt.name}
                </Link>
              ))}
            </div>
          </CardContent>
        </Card>
      ) : null}

      {/* Varianten derselben Übung */}
      {exercise.variants.length > 0 ? (
        <Card>
          <CardContent className="pt-5">
            <SectionLabel>Varianten</SectionLabel>
            <p className="mt-1 text-sm text-muted">Eine Übung, mehrere Ausführungen. Die Unterschiede und was sie bewirken:</p>
            <div className="mt-3 divide-y divide-border">
              {exercise.variants.map((v, i) => (
                <div key={i} className="flex items-start gap-3 py-3 first:pt-0 last:pb-0">
                  <span className="display tnum mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-subtle text-xs">{i + 1}</span>
                  <div className="min-w-0 flex-1">
                    <p className="text-base font-semibold">{v.name}</p>
                    <p className="mt-0.5 text-sm leading-relaxed text-muted">{v.description}</p>
                    {v.source_url ? (
                      <a href={v.source_url} target="_blank" rel="noreferrer noopener" className="mt-1 inline-flex items-center gap-1 text-sm font-semibold text-accent">
                        Animation ansehen <ExternalLink className="h-3.5 w-3.5" />
                      </a>
                    ) : null}
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      ) : null}

      {/* Wie getrackt wird */}
      {exercise.tracking_mode !== "weight_reps" ? (
        <Card>
          <CardContent className="pt-5">
            <SectionLabel>So wird getrackt</SectionLabel>
            {exercise.tracking_mode === "cardio" ? (
              <p className="mt-1.5 text-base leading-relaxed">
                Als <span className="font-semibold">Dauer und Distanz</span> statt Gewicht und Wiederholungen. Pace wird automatisch berechnet.
              </p>
            ) : (
              <p className="mt-1.5 text-base leading-relaxed">
                Mit <span className="font-semibold">Körpergewicht</span>: Etwa {Math.round(exercise.bodyweight_factor * 100)} % deines Körpergewichts werden bewegt,
                Zusatz- oder Gegengewicht kommt dazu. Die reale Last wird sofort berechnet und fließt in Volumen und Bestleistungen ein.
              </p>
            )}
          </CardContent>
        </Card>
      ) : null}

      {/* Das brauchst du */}
      <Card>
        <CardContent className="pt-5">
          <SectionLabel>Das brauchst du</SectionLabel>
          <div className="mt-2 flex items-center gap-2 text-sm font-medium">
            <EquipmentIcon equipment={exercise.equipment} className="h-5 w-5 text-muted" strokeWidth={1.7} />
            {EQUIPMENT_LABELS[exercise.equipment]}
            {exercise.machine_name ? <span className="text-muted">· im Studio: {exercise.machine_name}</span> : null}
          </div>
          {exercise.requirements.length > 0 ? (
            <ul className="mt-2 space-y-1.5">
              {exercise.requirements.map((r, i) => (
                <li key={i} className="flex gap-2 text-sm leading-relaxed text-muted">
                  <span className="mt-2 h-1 w-1 shrink-0 rounded-full bg-faint" />
                  <span>{r}</span>
                </li>
              ))}
            </ul>
          ) : null}
          {!isCable && (exercise.grip || exercise.grip_notes) ? (
            <div className="mt-4 border-t border-border pt-4">
              <p className="text-[11px] font-medium uppercase tracking-[0.12em] text-faint">Griff</p>
              {exercise.grip ? <GripRowView grip={exercise.grip} /> : null}
              {exercise.grip_notes ? <p className="mt-2 text-sm leading-relaxed text-muted">{exercise.grip_notes}</p> : null}
            </div>
          ) : null}
        </CardContent>
      </Card>

      {exercise.animation_url ? (
        <div className="space-y-2">
          <SectionLabel className="px-1">Ausführung</SectionLabel>
          <ExerciseVisual name={exercise.name} animationUrl={exercise.animation_url} equipment={exercise.equipment} category={exercise.category} />
        </div>
      ) : null}

      {exercise.animation_source_url ? (
        <a
          href={exercise.animation_source_url}
          target="_blank"
          rel="noreferrer noopener"
          className="card-interactive press flex items-center justify-between gap-3 rounded-[var(--radius-card)] bg-card px-5 py-4"
        >
          <span className="flex min-w-0 items-center gap-3">
            <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-accent-soft text-accent">
              <PlayCircle className="h-5 w-5" strokeWidth={2.2} />
            </span>
            <span className="min-w-0">
              <span className="block text-base font-semibold">Ausführung als Animation ansehen</span>
              <span className="block truncate text-sm text-muted">Öffnet die Übungsseite bei MODUSX</span>
            </span>
          </span>
          <ExternalLink className="h-4 w-4 shrink-0 text-faint" />
        </a>
      ) : null}

      <StepsCard title="Ausführung" steps={exercise.execution} numbered />
      <StepsCard title="Setup / Startposition" steps={exercise.setup} numbered />
      <StepsCard title="So triffst du den Muskel" steps={exercise.muscle_focus} />

      {exercise.range_of_motion || exercise.breathing ? (
        <Card>
          <CardContent className="space-y-4 pt-5">
            {exercise.range_of_motion ? (
              <div>
                <SectionLabel>Bewegungsradius</SectionLabel>
                <p className="mt-1.5 text-sm leading-relaxed">{exercise.range_of_motion}</p>
              </div>
            ) : null}
            {exercise.breathing ? (
              <div>
                <SectionLabel>Atmung</SectionLabel>
                <p className="mt-1.5 text-sm leading-relaxed">{exercise.breathing}</p>
              </div>
            ) : null}
          </CardContent>
        </Card>
      ) : null}

      <StepsCard title="Häufige Fehler" steps={exercise.common_mistakes} />
      <StepsCard title="Tipps" steps={exercise.tips} />

      {records && exercise.tracking_mode === "cardio" ? (
        <Card>
          <CardContent className="pt-5">
            <SectionLabel>Bestleistungen</SectionLabel>
            <div className="mt-3 grid grid-cols-2 gap-3">
              <Record label="Längste Distanz" value={records.max_distance_m ? formatDistance(records.max_distance_m) : "–"} date={records.max_distance_at} />
              <Record label="Längste Dauer" value={records.max_duration_seconds ? formatClock(records.max_duration_seconds) : "–"} date={records.max_duration_at} />
              <Record label="Beste Pace" value={records.best_pace_sec_per_km ? formatPace(records.best_pace_sec_per_km) : "–"} date={records.best_pace_at} />
              <Record label="Einheiten" value={String(records.total_sessions)} date={null} />
            </div>
          </CardContent>
        </Card>
      ) : records ? (
        <Card>
          <CardContent className="pt-5">
            <SectionLabel>Bestleistungen</SectionLabel>
            <div className="mt-3 grid grid-cols-2 gap-3">
              <Record label="Schwerstes Gewicht" value={records.max_weight !== null ? `${formatWeight(records.max_weight)} × ${records.max_weight_reps}` : "–"} date={records.max_weight_at} />
              <Record label="Meiste Wdh" value={records.max_reps !== null ? `${records.max_reps} × ${formatWeight(records.max_reps_weight ?? 0)}` : "–"} date={records.max_reps_at} />
              <Record label="Geschätztes 1RM" value={records.best_est_1rm !== null ? formatWeight(records.best_est_1rm) : "–"} date={records.best_est_1rm_at} />
              <Record label="Größtes Volumen" value={records.max_session_volume !== null ? formatVolume(records.max_session_volume) : "–"} date={records.max_session_volume_at} />
            </div>
          </CardContent>
        </Card>
      ) : null}

      <div className="space-y-3 pt-2">
        <AddToPlanButton exerciseId={exercise.id} exerciseName={exercise.name} />
        {exercise.is_custom ? <CustomExerciseActions exerciseId={exercise.id} slug={exercise.slug} /> : null}
        {canEditStandard ? (
          <Link href={`/exercises/${exercise.slug}/edit`} className="press flex h-11 items-center justify-center gap-2 rounded-full bg-subtle text-base font-semibold hover:bg-hover">
            Standardübung bearbeiten (Admin)
          </Link>
        ) : null}
      </div>
      {exercise.is_custom ? <Badge>Eigene Übung</Badge> : null}
    </div>
  );
}

function GripRowView({ grip, highlight = false }: { grip: GripRow; highlight?: boolean }) {
  return (
    <div className={`mt-2 flex items-center gap-3 rounded-xl border px-3 py-2.5 ${highlight ? "border-border-strong bg-subtle" : "border-border"}`}>
      <div className="flex h-14 w-[5.5rem] shrink-0 items-center justify-center overflow-hidden rounded-lg bg-card text-fg">
        {grip.image_url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={grip.image_url} alt={grip.name_de} loading="lazy" className="h-full w-full object-contain p-1" />
        ) : (
          <GripIcon gripId={grip.id} className="p-1.5" />
        )}
      </div>
      <div className="min-w-0">
        <p className="text-sm font-medium">{grip.name_de}</p>
        <p className="mt-0.5 line-clamp-2 text-xs leading-relaxed text-muted">{grip.description}</p>
      </div>
    </div>
  );
}

/** Höhenangabe aus cable_setup.height: erster Begriff vor Komma/Klammer */
function heightLabel(height: string): string {
  return height.split(/[,(–-]/)[0].trim();
}
function heightNote(height: string): string {
  const rest = height.slice(heightLabel(height).length).replace(/^[\s,(–-]+/, "").replace(/\)$/, "");
  return rest;
}

function SeatIcon() {
  return (
    <svg viewBox="0 0 48 48" className="h-8 w-8" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M14 10v18h18" />
      <path d="M10 28h26v6H10z" />
      <path d="M14 34v8M32 34v8" />
    </svg>
  );
}

/** Kleines Icon: Kabelturm mit markierter Rollenhöhe */
function CableHeightIcon({ height }: { height: string }) {
  const h = height.toLowerCase();
  const y = h.startsWith("ganz oben") ? 8 : h.startsWith("über kopf") ? 14 : h.startsWith("schulter") ? 20 : h.startsWith("brust") ? 24 : h.startsWith("hüft") ? 30 : h.startsWith("knie") ? 36 : 42;
  return (
    <svg viewBox="0 0 48 48" className="h-8 w-8" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" aria-hidden>
      <path d="M16 4v40M32 4v40M12 44h24" strokeOpacity="0.5" />
      <circle cx="24" cy={y} r="4" fill="currentColor" />
      <path d={`M28 ${y}h10`} />
    </svg>
  );
}

function StepsCard({ title, steps, numbered = false }: { title: string; steps: string[]; numbered?: boolean }) {
  if (!steps || steps.length === 0) return null;
  return (
    <Card>
      <CardContent className="pt-5">
        <SectionLabel>{title}</SectionLabel>
        <ol className="mt-3 space-y-2.5">
          {steps.map((s, i) => (
            <li key={i} className="flex gap-3 text-sm leading-relaxed">
              <span className="tnum mt-0.5 w-5 shrink-0 text-xs font-semibold text-faint">{numbered ? `${i + 1}.` : "–"}</span>
              <span>{s}</span>
            </li>
          ))}
        </ol>
      </CardContent>
    </Card>
  );
}

function Record({ label, value, date }: { label: string; value: string; date: string | null }) {
  return (
    <div className="rounded-[var(--radius-control)] bg-subtle px-3.5 py-3">
      <p className="text-[13px] font-medium text-muted">{label}</p>
      <p className="display tnum mt-1 text-base">{value}</p>
      {date ? <p className="text-xs text-faint">{formatDate(date)}</p> : null}
    </div>
  );
}
