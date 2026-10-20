import { cn } from "@/lib/utils/cn";
import type { EquipmentType, ExerciseCategory } from "@/lib/supabase/types";
import { CATEGORY_LABELS, EQUIPMENT_LABELS } from "@/lib/utils/labels";
import { EquipmentIcon } from "@/components/exercise/equipment-icon";

interface ExerciseVisualProps {
  name: string;
  imageUrl: string | null;
  equipment: EquipmentType;
  category: ExerciseCategory;
  className?: string;
  size?: "sm" | "lg";
}

/**
 * Bild der Übung, falls vorhanden – sonst ein hochwertiger, einheitlicher Placeholder.
 * Die Bildquelle ist austauschbar (image_url in der Datenbank / Supabase Storage).
 */
export function ExerciseVisual({ name, imageUrl, equipment, category, className, size = "lg" }: ExerciseVisualProps) {
  if (imageUrl) {
    return (
      <div className={cn("overflow-hidden rounded-xl border border-border bg-subtle", className)}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={imageUrl} alt={name} loading="lazy" className="h-full w-full object-cover" />
      </div>
    );
  }
  return (
    <div
      className={cn(
        "relative flex items-center justify-center overflow-hidden rounded-xl border border-border bg-subtle text-muted",
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
