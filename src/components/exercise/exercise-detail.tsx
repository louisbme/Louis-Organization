import type { ExerciseDetail as ExerciseDetailType } from "@/lib/services/exercises";
import type { ExerciseRecordsRow } from "@/lib/supabase/types";
import { CATEGORY_LABELS, EQUIPMENT_LABELS, muscleLabel } from "@/lib/utils/labels";
import { formatDate, formatVolume, formatWeight } from "@/lib/utils/format";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, SectionLabel } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { MuscleMap } from "@/components/muscle-map/muscle-map";
import { GripIcon } from "@/components/exercise/grip-icon";
import { EquipmentIcon } from "@/components/exercise/equipment-icon";
import { ExerciseVisual } from "@/components/exercise/exercise-visual";
import { AddToPlanButton, CustomExerciseActions, FavoriteButton } from "@/components/exercise/exercise-actions";

interface Props {
  exercise: ExerciseDetailType;
  records: ExerciseRecordsRow | null;
  backHref?: string;
}

export function ExerciseDetail({ exercise, records, backHref = "/exercises" }: Props) {
  const showForearmHint =
    exercise.secondary_muscles.includes("forearms") && !exercise.primary_muscles.includes("forearms");

  return (
    <div className="space-y-5">
      <PageHeader
        title={exercise.name}
        eyebrow={`${CATEGORY_LABELS[exercise.category]} · ${EQUIPMENT_LABELS[exercise.equipment]}`}
        backHref={backHref}
        actions={<FavoriteButton exerciseId={exercise.id} initial={exercise.is_favorite} />}
      />

      {exercise.description ? <p className="text-sm leading-relaxed text-muted">{exercise.description}</p> : null}

      {/* Muskelkarte */}
      <Card>
        <CardContent className="pt-5">
          <MuscleMap primary={exercise.primary_muscles} secondary={exercise.secondary_muscles} />
          <div className="mt-5 grid grid-cols-2 gap-4">
            <div>
              <SectionLabel>Primär</SectionLabel>
              <ul className="mt-1.5 space-y-1">
                {exercise.primary_muscles.map((m) => (
                  <li key={m} className="text-sm font-medium">
                    {muscleLabel(m)}
                  </li>
                ))}
              </ul>
            </div>
            <div>
              <SectionLabel>Sekundär</SectionLabel>
              {exercise.secondary_muscles.length === 0 ? (
                <p className="mt-1.5 text-sm text-muted">–</p>
              ) : (
                <ul className="mt-1.5 space-y-1">
                  {exercise.secondary_muscles.map((m) => (
                    <li key={m} className="text-sm text-muted">
                      {muscleLabel(m)}
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </div>
          {showForearmHint ? (
            <p className="mt-4 text-xs text-faint">Unterarme sekundär beteiligt (Griffkraft).</p>
          ) : null}
        </CardContent>
      </Card>

      <ExerciseVisual
        name={exercise.name}
        imageUrl={exercise.image_url}
        equipment={exercise.equipment}
        category={exercise.category}
      />

      {/* Equipment + Griff */}
      <Card>
        <CardContent className="space-y-5 pt-5">
          <div className="flex items-center gap-3">
            <div className="flex h-11 w-11 items-center justify-center rounded-lg bg-subtle text-muted">
              <EquipmentIcon equipment={exercise.equipment} strokeWidth={1.7} />
            </div>
            <div>
              <SectionLabel>Equipment</SectionLabel>
              <p className="text-sm font-medium">{EQUIPMENT_LABELS[exercise.equipment]}</p>
            </div>
          </div>

          {exercise.grip || exercise.grip_notes ? (
            <div className="border-t border-border pt-5">
              <SectionLabel>Griff</SectionLabel>
              {exercise.grip ? (
                <div className="mt-2 flex items-start gap-3">
                  <div className="flex h-14 w-20 shrink-0 items-center justify-center rounded-lg border border-border bg-subtle text-fg">
                    <GripIcon gripId={exercise.grip.id} />
                  </div>
                  <div className="min-w-0">
                    <p className="text-sm font-medium">{exercise.grip.name_de}</p>
                    <p className="mt-0.5 text-xs leading-relaxed text-muted">{exercise.grip.description}</p>
                  </div>
                </div>
              ) : null}
              {exercise.grip_notes ? (
                <p className="mt-3 text-sm leading-relaxed text-muted">{exercise.grip_notes}</p>
              ) : null}
            </div>
          ) : null}
        </CardContent>
      </Card>

      {/* Kabel-Setup */}
      {exercise.cable ? (
        <Card>
          <CardContent className="pt-5">
            <SectionLabel>Kabel-Setup</SectionLabel>
            <dl className="mt-3 grid grid-cols-1 gap-x-6 gap-y-3 sm:grid-cols-2">
              {(
                [
                  ["Kabel", exercise.cable.cable],
                  ["Höhe", exercise.cable.height],
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

      <StepsCard title="Ausführung" steps={exercise.execution} numbered />
      <StepsCard title="Setup / Startposition" steps={exercise.setup} numbered />

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

      {records ? (
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
      </div>
      {exercise.is_custom ? <Badge>Eigene Übung</Badge> : null}
    </div>
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
              <span className="tnum mt-0.5 w-5 shrink-0 text-xs font-semibold text-faint">
                {numbered ? `${i + 1}.` : "–"}
              </span>
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
    <div className="rounded-xl border border-border bg-subtle px-3 py-3">
      <p className="text-[11px] font-medium uppercase tracking-wider text-faint">{label}</p>
      <p className="tnum mt-1 text-base font-semibold">{value}</p>
      {date ? <p className="text-xs text-faint">{formatDate(date)}</p> : null}
    </div>
  );
}
