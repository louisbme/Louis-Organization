import { cn } from "@/lib/utils/cn";
import { APP_MONOGRAM, APP_NAME } from "@/lib/config";

/** Monogramm: nur der Anfangsbuchstabe, klar und typografisch. */
export function LogoMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 64 64" className={cn("h-8 w-8", className)} aria-hidden>
      <rect width="64" height="64" rx="16" className="fill-fg" />
      <text
        x="50%"
        y="50%"
        dominantBaseline="central"
        textAnchor="middle"
        fontFamily="var(--font-geist-sans), ui-sans-serif, system-ui, sans-serif"
        fontWeight="700"
        fontSize="38"
        letterSpacing="-1"
        className="fill-bg"
      >
        {APP_MONOGRAM}
      </text>
    </svg>
  );
}

export function Wordmark({ className }: { className?: string }) {
  return (
    <span className={cn("inline-flex items-center gap-2.5", className)}>
      <LogoMark />
      <span className="text-base font-semibold tracking-[0.18em]">{APP_NAME}</span>
    </span>
  );
}
