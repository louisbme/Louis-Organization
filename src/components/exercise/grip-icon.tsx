import { cn } from "@/lib/utils/cn";

/** Einfache, einheitliche Griff-Icons (eigene SVGs, keine externen Assets). */
export function GripIcon({ gripId, className }: { gripId: string | null; className?: string }) {
  const common = {
    viewBox: "0 0 64 40",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 2.2,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    className: cn("h-10 w-16", className),
    "aria-hidden": true,
  };

  switch (gripId) {
    case "neutral_parallel":
      return (
        <svg {...common}>
          <path d="M32 4v8" />
          <path d="M18 12h28" />
          <path d="M22 12v6M42 12v6" />
          <rect x="17" y="18" width="10" height="16" rx="3" />
          <rect x="37" y="18" width="10" height="16" rx="3" />
        </svg>
      );
    case "wide_lat_bar":
      return (
        <svg {...common}>
          <path d="M32 4v8" />
          <path d="M26 12h12" />
          <path d="M4 24c8-10 48-10 56 0" />
          <path d="M4 24v6M60 24v6" />
          <path d="M12 21v6M52 21v6" strokeWidth={3} />
        </svg>
      );
    case "close_v_grip":
      return (
        <svg {...common}>
          <path d="M32 4v8" />
          <path d="M32 12l-10 12M32 12l10 12" />
          <rect x="14" y="22" width="12" height="12" rx="3" />
          <rect x="38" y="22" width="12" height="12" rx="3" />
        </svg>
      );
    case "rope":
      return (
        <svg {...common}>
          <path d="M32 4v6" />
          <path d="M32 10c-6 6-10 10-12 18M32 10c6 6 10 10 12 18" />
          <path d="M20 28v6M44 28v6" strokeWidth={4} />
          <path d="M26 16l-2 2M38 16l2 2M23 22l-2 2M41 22l2 2" strokeWidth={1.5} />
        </svg>
      );
    case "single_handle":
      return (
        <svg {...common}>
          <path d="M32 4v8" />
          <path d="M24 12h16" />
          <path d="M24 12v8a8 8 0 0 0 16 0v-8" />
          <path d="M26 30h12" strokeWidth={4} />
        </svg>
      );
    case "straight_bar":
      return (
        <svg {...common}>
          <path d="M32 4v8" />
          <path d="M24 12h16" />
          <path d="M24 12v8M40 12v8" />
          <path d="M8 24h48" strokeWidth={3} />
          <path d="M14 21v6M50 21v6" strokeWidth={3} />
        </svg>
      );
    case "ez_bar":
      return (
        <svg {...common}>
          <path d="M32 4v8" />
          <path d="M24 12h16" />
          <path d="M24 12v8M40 12v8" />
          <path d="M8 26l10-4 8 6 6-6 8 6 10-4" strokeWidth={3} />
          <path d="M8 23v6M56 23v6" strokeWidth={3} />
        </svg>
      );
    case "v_bar_triceps":
      return (
        <svg {...common}>
          <path d="M32 4v8" />
          <path d="M32 12l-14 10M32 12l14 10" strokeWidth={3} />
          <path d="M18 22v8M46 22v8" strokeWidth={3} />
        </svg>
      );
    case "ankle_strap":
      return (
        <svg {...common}>
          <path d="M32 4v10" />
          <path d="M22 14h20" />
          <rect x="18" y="18" width="28" height="12" rx="6" />
          <path d="M26 18v12M38 18v12" strokeWidth={1.5} />
        </svg>
      );
    default:
      return (
        <svg {...common}>
          <circle cx="32" cy="20" r="10" />
        </svg>
      );
  }
}
