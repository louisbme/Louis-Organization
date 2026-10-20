import { cn } from "@/lib/utils/cn";
import { ANTERIOR, POSTERIOR, type AnatomyMuscle, type AnatomyRegion } from "@/components/muscle-map/anatomy-data";

export type View = "front" | "back";
type Intensity = "primary" | "secondary" | "none";

/** Zuordnung der App-Muskelgruppen zu den anatomischen Regionen je Ansicht */
export const MUSCLE_TO_ANATOMY: Record<string, { front: AnatomyMuscle[]; back: AnatomyMuscle[] }> = {
  chest: { front: ["chest"], back: [] },
  upper_chest: { front: ["chest"], back: [] },
  front_delts: { front: ["front-deltoids"], back: [] },
  side_delts: { front: ["front-deltoids"], back: ["back-deltoids"] },
  rear_delts: { front: [], back: ["back-deltoids"] },
  traps: { front: ["neck"], back: ["trapezius"] },
  lats: { front: [], back: ["upper-back"] },
  upper_back: { front: [], back: ["upper-back", "trapezius"] },
  mid_back: { front: [], back: ["upper-back"] },
  lower_back: { front: [], back: ["lower-back"] },
  biceps: { front: ["biceps"], back: [] },
  triceps: { front: [], back: ["triceps"] },
  forearms: { front: ["forearm"], back: ["forearm"] },
  abs: { front: ["abs"], back: [] },
  obliques: { front: ["obliques"], back: [] },
  quads: { front: ["quadriceps"], back: [] },
  hamstrings: { front: [], back: ["hamstring"] },
  glutes: { front: [], back: ["gluteal"] },
  calves: { front: ["calves"], back: ["calves"] },
  adductors: { front: ["adductor"], back: ["adductor"] },
  abductors: { front: ["abductors"], back: ["abductors"] },
};

/** Nicht-muskuläre Flächen (Kopf, Hals, Knie): dezenter als Muskeln */
const STRUCTURAL: AnatomyMuscle[] = ["head", "knees", "left-soleus", "right-soleus"];

function intensities(view: View, primary: string[], secondary: string[]): Map<AnatomyMuscle, Intensity> {
  const map = new Map<AnatomyMuscle, Intensity>();
  for (const m of secondary) for (const r of MUSCLE_TO_ANATOMY[m]?.[view] ?? []) map.set(r, "secondary");
  for (const m of primary) for (const r of MUSCLE_TO_ANATOMY[m]?.[view] ?? []) map.set(r, "primary");
  return map;
}

function Figure({
  view,
  primary,
  secondary,
  compact,
  interactive,
}: {
  view: View;
  primary: string[];
  secondary: string[];
  compact?: boolean;
  interactive?: boolean;
}) {
  const regions: AnatomyRegion[] = view === "front" ? ANTERIOR : POSTERIOR;
  const map = intensities(view, primary, secondary);
  return (
    <figure className="flex flex-col items-center">
      <svg
        viewBox="0 0 100 200"
        role="img"
        aria-label={view === "front" ? "Muskelkarte Vorderansicht" : "Muskelkarte Rückansicht"}
        className={cn("h-auto w-full", compact ? "max-w-[84px]" : "max-w-[150px] sm:max-w-[170px]")}
      >
        <defs>
          <linearGradient id={`mm-base-${view}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="var(--muscle-base-light)" />
            <stop offset="1" stopColor="var(--muscle-base)" />
          </linearGradient>
          <linearGradient id={`mm-primary-${view}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="var(--muscle-primary-light)" />
            <stop offset="1" stopColor="var(--muscle-primary)" />
          </linearGradient>
        </defs>
        {regions.map((r) => {
          const i = map.get(r.muscle) ?? "none";
          const structural = STRUCTURAL.includes(r.muscle);
          const fill =
            i === "primary"
              ? `url(#mm-primary-${view})`
              : i === "secondary"
                ? "var(--muscle-secondary)"
                : structural
                  ? "var(--muscle-structural)"
                  : `url(#mm-base-${view})`;
          return r.svgPoints.map((points, idx) => (
            <polygon
              key={`${r.muscle}-${idx}`}
              points={points}
              fill={fill}
              stroke="var(--muscle-outline)"
              strokeWidth={0.55}
              strokeLinejoin="round"
              data-muscle={r.muscle}
              data-intensity={i}
              className={cn(interactive && "transition-[fill] duration-300")}
            />
          ));
        })}
      </svg>
      {!compact ? (
        <figcaption className="mt-2 text-[11px] font-medium uppercase tracking-[0.12em] text-faint">
          {view === "front" ? "Vorne" : "Hinten"}
        </figcaption>
      ) : null}
    </figure>
  );
}

interface MuscleMapProps {
  primary: string[];
  secondary: string[];
  views?: View[];
  className?: string;
  showLegend?: boolean;
  compact?: boolean;
}

/** Anatomische Muskelkarte mit primär (rot) und sekundär (hell) hervorgehobenen Muskeln. */
export function MuscleMap({ primary, secondary, views = ["front", "back"], className, showLegend = true, compact = false }: MuscleMapProps) {
  return (
    <div className={cn("flex flex-col items-center", className)}>
      <div className={cn("flex items-start justify-center", compact ? "gap-2" : "gap-6 sm:gap-10")}>
        {views.map((v) => (
          <Figure key={v} view={v} primary={primary} secondary={secondary} compact={compact} interactive={!compact} />
        ))}
      </div>
      {showLegend && !compact ? (
        <div className="mt-4 flex items-center gap-5 text-xs text-muted">
          <span className="inline-flex items-center gap-2">
            <span className="h-2.5 w-2.5 rounded-sm" style={{ background: "var(--muscle-primary)" }} /> Primär
          </span>
          <span className="inline-flex items-center gap-2">
            <span className="h-2.5 w-2.5 rounded-sm" style={{ background: "var(--muscle-secondary)" }} /> Sekundär
          </span>
        </div>
      ) : null}
    </div>
  );
}
