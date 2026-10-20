import { cn } from "@/lib/utils/cn";

/**
 * Eigene, einheitliche Griff-Illustrationen (Linienstil, passend zum Design).
 * Nachempfunden den gängigen Kabelzug-Anbauten, keine Fremdbilder.
 */
export function GripIcon({ gripId, className }: { gripId: string | null; className?: string }) {
  const common = {
    viewBox: "0 0 160 100",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 3,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    className: cn("h-full w-full", className),
    "aria-hidden": true,
  };
  const ring = <path d="M80 8v8M74 16h12a4 4 0 0 1 4 4v4H70v-4a4 4 0 0 1 4-4Z" />;

  switch (gripId) {
    case "neutral_parallel":
      // Zwei parallele Griffe am Bügel (Parallel-/MAG-Griff)
      return (
        <svg {...common}>
          {ring}
          <path d="M80 28v10" />
          <path d="M40 38h80" />
          <path d="M48 38v8M112 38v8" />
          <path d="M44 46h12a3 3 0 0 1 3 3v30a3 3 0 0 1-3 3H44a3 3 0 0 1-3-3V49a3 3 0 0 1 3-3Z" fill="currentColor" fillOpacity="0.12" />
          <path d="M104 46h12a3 3 0 0 1 3 3v30a3 3 0 0 1-3 3h-12a3 3 0 0 1-3-3V49a3 3 0 0 1 3-3Z" fill="currentColor" fillOpacity="0.12" />
        </svg>
      );
    case "wide_lat_bar":
      // Lange Latzugstange, Enden abgewinkelt
      return (
        <svg {...common}>
          {ring}
          <path d="M80 28v12" />
          <path d="M60 40h40" />
          <path d="M8 76l16-20h112l16 20" strokeWidth={5} />
          <path d="M28 56h20M112 56h20" strokeWidth={7} strokeOpacity="0.35" />
        </svg>
      );
    case "close_v_grip":
      // Enger V-Griff (Triangel)
      return (
        <svg {...common}>
          {ring}
          <path d="M80 28v8" />
          <path d="M80 36L46 70M80 36l34 34" strokeWidth={4} />
          <path d="M40 70h26M94 70h26" strokeWidth={9} strokeOpacity="0.35" />
          <path d="M40 70h26M94 70h26" strokeWidth={3} />
        </svg>
      );
    case "rope":
      // Seil mit zwei Endknäufen
      return (
        <svg {...common}>
          {ring}
          <path d="M80 28v6" />
          <path d="M80 34c-18 4-34 16-34 34M80 34c18 4 34 16 34 34" strokeWidth={6} strokeOpacity="0.35" />
          <path d="M80 34c-18 4-34 16-34 34M80 34c18 4 34 16 34 34" strokeDasharray="6 5" />
          <path d="M40 66h12v16H40zM108 66h12v16h-12z" fill="currentColor" fillOpacity="0.2" />
        </svg>
      );
    case "single_handle":
      // Einzelgriff (D-Griff)
      return (
        <svg {...common}>
          {ring}
          <path d="M80 28v10" />
          <path d="M58 38h44" />
          <path d="M58 38v16a22 22 0 0 0 44 0V38" />
          <path d="M64 76h32" strokeWidth={9} strokeOpacity="0.35" />
          <path d="M64 76h32" />
        </svg>
      );
    case "strap_handle":
      // Handschlaufe (weicher Schlaufengriff mit Karabiner)
      return (
        <svg {...common}>
          {ring}
          <path d="M80 28v6" />
          <path d="M74 34h12l3 6-9 8-9-8z" />
          <path d="M80 48c-24 0-36 10-36 22s12 20 36 20 36-8 36-20-12-22-36-22Z" strokeWidth={8} strokeOpacity="0.3" />
          <path d="M80 48c-24 0-36 10-36 22s12 20 36 20 36-8 36-20-12-22-36-22Z" />
        </svg>
      );
    case "straight_bar":
      // Gerade kurze Stange (Bizeps-Trizeps-Stange)
      return (
        <svg {...common}>
          {ring}
          <path d="M80 28v18" />
          <path d="M20 66h120" strokeWidth={7} />
          <path d="M28 66h30M102 66h30" strokeWidth={9} strokeOpacity="0.3" />
        </svg>
      );
    case "ez_bar":
      // SZ-Stange
      return (
        <svg {...common}>
          {ring}
          <path d="M80 28v18" />
          <path d="M14 66l18-8 16 12 14-12 16 12 16-12 18 8 14-8 14 8" strokeWidth={6} />
          <path d="M14 60v12M146 60v12" strokeWidth={5} />
        </svg>
      );
    case "v_bar_triceps":
      // Trizeps-V-Stange
      return (
        <svg {...common}>
          {ring}
          <path d="M80 28v8" />
          <path d="M80 36L42 64M80 36l38 28" strokeWidth={6} />
          <path d="M42 64v14M118 64v14" strokeWidth={9} strokeOpacity="0.35" />
          <path d="M42 64v14M118 64v14" strokeWidth={4} />
        </svg>
      );
    case "ankle_strap":
      // Fußschlaufe
      return (
        <svg {...common}>
          {ring}
          <path d="M80 28v8" />
          <path d="M72 36h16" />
          <rect x="40" y="46" width="80" height="34" rx="17" />
          <path d="M60 46v34M100 46v34" strokeWidth={2} strokeOpacity="0.6" />
          <path d="M80 36v10" />
        </svg>
      );
    default:
      return (
        <svg {...common}>
          <circle cx="80" cy="50" r="28" />
        </svg>
      );
  }
}
