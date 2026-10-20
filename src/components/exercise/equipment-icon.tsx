import type { EquipmentType } from "@/lib/supabase/types";
import { cn } from "@/lib/utils/cn";

/** Einheitliche Equipment-Symbole (eigene SVGs). */
export function EquipmentIcon({
  equipment,
  className,
  strokeWidth = 2,
}: {
  equipment: EquipmentType;
  className?: string;
  strokeWidth?: number;
}) {
  const common = {
    viewBox: "0 0 48 48",
    fill: "none",
    stroke: "currentColor",
    strokeWidth,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    className: cn("h-6 w-6", className),
    "aria-hidden": true,
  };
  switch (equipment) {
    case "machine":
      return (
        <svg {...common}>
          <path d="M10 40V12M38 40V12" />
          <path d="M10 12h28" />
          <path d="M14 26h10v6H14zM28 20h6v10h-6z" />
          <path d="M6 40h36" />
        </svg>
      );
    case "cable":
      return (
        <svg {...common}>
          <circle cx="24" cy="10" r="4" />
          <path d="M24 14v16" />
          <path d="M8 8v32M40 8v32" />
          <path d="M18 30h12v6H18z" />
        </svg>
      );
    case "barbell":
      return (
        <svg {...common}>
          <path d="M4 24h40" />
          <path d="M10 16v16M14 14v20M34 14v20M38 16v16" strokeWidth={3} />
        </svg>
      );
    case "dumbbell":
      return (
        <svg {...common}>
          <path d="M16 24h16" />
          <path d="M10 16v16M14 14v20M34 14v20M38 16v16" strokeWidth={3} />
        </svg>
      );
    case "bodyweight":
      return (
        <svg {...common}>
          <circle cx="24" cy="9" r="4" />
          <path d="M24 13v14M14 20l10 4 10-4M24 27l-7 13M24 27l7 13" />
        </svg>
      );
    case "smith_machine":
      return (
        <svg {...common}>
          <path d="M8 6v36M40 6v36" />
          <path d="M12 24h24" strokeWidth={3} />
          <path d="M14 18v12M34 18v12" strokeWidth={3} />
        </svg>
      );
    case "bench":
      return (
        <svg {...common}>
          <path d="M6 22h36v6H6z" />
          <path d="M12 28v12M36 28v12M6 40h12M30 40h12" />
        </svg>
      );
    case "cardio":
      return (
        <svg {...common}>
          <path d="M4 26h8l4-10 6 20 6-16 4 6h12" />
        </svg>
      );
    default:
      return (
        <svg {...common}>
          <circle cx="24" cy="24" r="12" />
        </svg>
      );
  }
}
