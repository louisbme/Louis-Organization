import { cn } from "@/lib/utils/cn";
import { BACK_REGIONS, FRONT_REGIONS, MUSCLE_REGIONS, SILHOUETTE, type Region, type View } from "@/components/muscle-map/regions";

type Intensity = "primary" | "secondary" | "none";

interface MuscleMapProps {
  primary: string[];
  secondary: string[];
  views?: View[];
  className?: string;
  showLegend?: boolean;
  /** Kompakte Darstellung (z. B. in Karten) */
  compact?: boolean;
}

function regionIntensity(view: View, primary: string[], secondary: string[]): Map<string, Intensity> {
  const map = new Map<string, Intensity>();
  for (const m of secondary) {
    for (const r of MUSCLE_REGIONS[m]?.[view] ?? []) map.set(r, "secondary");
  }
  for (const m of primary) {
    for (const r of MUSCLE_REGIONS[m]?.[view] ?? []) map.set(r, "primary");
  }
  return map;
}

const FILL: Record<Intensity, string> = {
  primary: "var(--muscle-primary)",
  secondary: "var(--muscle-secondary)",
  none: "transparent",
};

function RegionPaths({ regions, intensities }: { regions: Region[]; intensities: Map<string, Intensity> }) {
  return (
    <>
      {regions.map((r) => {
        const intensity = intensities.get(r.id) ?? "none";
        const props = {
          d: r.d,
          fill: FILL[intensity],
          stroke: intensity === "none" ? "var(--muscle-outline)" : "none",
          strokeWidth: 0.6,
          opacity: intensity === "none" ? 0.5 : 1,
        };
        return (
          <g key={r.id} data-region={r.id} data-intensity={intensity}>
            <path {...props} />
            {r.mirror ? <path {...props} transform="matrix(-1 0 0 1 200 0)" /> : null}
          </g>
        );
      })}
    </>
  );
}

function Body({ view, primary, secondary, compact }: { view: View; primary: string[]; secondary: string[]; compact?: boolean }) {
  const regions = view === "front" ? FRONT_REGIONS : BACK_REGIONS;
  const intensities = regionIntensity(view, primary, secondary);
  return (
    <figure className="flex flex-col items-center">
      <svg
        viewBox="0 0 200 420"
        role="img"
        aria-label={view === "front" ? "Muskelkarte Vorderansicht" : "Muskelkarte Rückansicht"}
        className={cn("h-auto w-full", compact ? "max-w-[90px]" : "max-w-[170px]")}
      >
        <g fill="var(--muscle-base)" stroke="var(--muscle-outline)" strokeWidth="0.8" strokeLinejoin="round">
          {SILHOUETTE.map((s) => (
            <g key={s.id}>
              <path d={s.d} />
              {s.mirror ? <path d={s.d} transform="matrix(-1 0 0 1 200 0)" /> : null}
            </g>
          ))}
        </g>
        <RegionPaths regions={regions} intensities={intensities} />
      </svg>
      {!compact ? (
        <figcaption className="mt-2 text-[11px] font-medium uppercase tracking-[0.12em] text-faint">
          {view === "front" ? "Vorne" : "Hinten"}
        </figcaption>
      ) : null}
    </figure>
  );
}

export function MuscleMap({
  primary,
  secondary,
  views = ["front", "back"],
  className,
  showLegend = true,
  compact = false,
}: MuscleMapProps) {
  return (
    <div className={cn("flex flex-col items-center", className)}>
      <div className={cn("flex items-start justify-center", compact ? "gap-2" : "gap-6 sm:gap-10")}>
        {views.map((v) => (
          <Body key={v} view={v} primary={primary} secondary={secondary} compact={compact} />
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
