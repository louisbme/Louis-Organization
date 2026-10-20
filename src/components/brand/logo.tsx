import { cn } from "@/lib/utils/cn";

export function LogoMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 64 64" className={cn("h-8 w-8", className)} aria-hidden>
      <rect width="64" height="64" rx="14" className="fill-fg" />
      <rect x="12" y="29" width="40" height="6" rx="3" className="fill-accent" />
      <rect x="8" y="22" width="8" height="20" rx="3" className="fill-bg" />
      <rect x="48" y="22" width="8" height="20" rx="3" className="fill-bg" />
    </svg>
  );
}

export function Wordmark({ className }: { className?: string }) {
  return (
    <span className={cn("inline-flex items-center gap-2.5", className)}>
      <LogoMark />
      <span className="text-base font-semibold tracking-tight">Trainingslog</span>
    </span>
  );
}
