import { cn } from "@/lib/utils/cn";
import type { EquipmentType, ExerciseCategory } from "@/lib/supabase/types";
import { CATEGORY_LABELS, EQUIPMENT_LABELS } from "@/lib/utils/labels";
import { EquipmentIcon } from "@/components/exercise/equipment-icon";

interface ExerciseVisualProps {
  name: string;
  imageUrl: string | null;
  animationUrl?: string | null;
  equipment: EquipmentType;
  category: ExerciseCategory;
  className?: string;
  size?: "sm" | "lg";
}

const isVideo = (url: string) => /\.(mp4|webm|mov)(\?|$)/i.test(url);

/**
 * Darstellung der Übung:
 * 1. Ausführungs-Animation (GIF, WebP oder MP4), falls hinterlegt
 * 2. sonst Foto der Maschine / Übung
 * 3. sonst einheitlicher Placeholder
 * Alle Quellen sind austauschbar (image_url / animation_url in der Datenbank).
 */
export function ExerciseVisual({ name, imageUrl, animationUrl, equipment, category, className, size = "lg" }: ExerciseVisualProps) {
  const src = animationUrl ?? imageUrl;
  if (src) {
    return (
      <div className={cn("overflow-hidden rounded-[var(--radius-control)] bg-subtle", size === "lg" ? "aspect-[4/3] sm:aspect-[16/9]" : "aspect-square", className)}>
        {isVideo(src) ? (
          <video src={src} autoPlay loop muted playsInline className="h-full w-full object-cover" aria-label={name} />
        ) : (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={src} alt={name} loading="lazy" decoding="async" className="h-full w-full object-cover" />
        )}
      </div>
    );
  }
  return (
    <div
      className={cn(
        "relative flex items-center justify-center overflow-hidden rounded-[var(--radius-control)] bg-subtle text-muted",
        size === "lg" ? "aspect-[16/9]" : "aspect-square",
        className
      )}
      aria-label={`${name} – ${EQUIPMENT_LABELS[equipment]}`}
      role="img"
    >
      <div
        className="absolute inset-0 opacity-[0.35]"
        style={{
          backgroundImage:
            "linear-gradient(var(--border) 1px, transparent 1px), linear-gradient(90deg, var(--border) 1px, transparent 1px)",
          backgroundSize: "24px 24px",
        }}
      />
      <div className="relative flex flex-col items-center gap-2">
        <EquipmentIcon equipment={equipment} className={size === "lg" ? "h-12 w-12" : "h-7 w-7"} strokeWidth={1.5} />
        {size === "lg" ? (
          <p className="text-xs font-medium uppercase tracking-[0.12em] text-faint">
            {EQUIPMENT_LABELS[equipment]} · {CATEGORY_LABELS[category]}
          </p>
        ) : null}
      </div>
    </div>
  );
}
