import type { EquipmentType, ExerciseCategory } from "@/lib/supabase/types";
import { cn } from "@/lib/utils/cn";
import { EquipmentIcon } from "@/components/exercise/equipment-icon";

interface ExerciseVisualProps {
  name: string;
  /** GIF, WebP oder MP4 der Ausführung (optional) */
  animationUrl: string | null;
  equipment: EquipmentType;
  category: ExerciseCategory;
  className?: string;
  size?: "lg" | "sm";
}

/**
 * Ausführungs-Animation einer Übung. Ohne Animation ein ruhiger Platzhalter mit Equipment-Symbol.
 * Gerätefotos gibt es in der App nicht mehr.
 */
export function ExerciseVisual({ name, animationUrl, equipment, className, size = "lg" }: ExerciseVisualProps) {
  if (animationUrl) {
    const isVideo = /\.(mp4|webm)(\?|$)/i.test(animationUrl);
    return (
      <div className={cn("overflow-hidden rounded-[var(--radius-control)] bg-subtle", size === "lg" ? "aspect-[4/3] sm:aspect-[16/9]" : "aspect-square", className)}>
        {isVideo ? (
          <video src={animationUrl} autoPlay loop muted playsInline className="h-full w-full object-contain" aria-label={`Ausführung: ${name}`} />
        ) : (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={animationUrl} alt={`Ausführung: ${name}`} loading="lazy" decoding="async" className="h-full w-full object-contain" />
        )}
      </div>
    );
  }
  return (
    <div
      className={cn(
        "relative flex items-center justify-center overflow-hidden rounded-[var(--radius-control)] bg-subtle text-muted",
        size === "lg" ? "aspect-[4/3] sm:aspect-[16/9]" : "aspect-square",
        className
      )}
      aria-hidden
    >
      <EquipmentIcon equipment={equipment} className={size === "lg" ? "h-12 w-12" : "h-6 w-6"} strokeWidth={1.4} />
    </div>
  );
}
