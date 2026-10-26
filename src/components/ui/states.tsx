import * as React from "react";
import { Loader2 } from "lucide-react";
import { cn } from "@/lib/utils/cn";

export function Spinner({ className }: { className?: string }) {
  return <Loader2 className={cn("h-5 w-5 animate-spin text-muted", className)} aria-label="Lädt" />;
}

export function LoadingBlock({ label = "Lädt …" }: { label?: string }) {
  return (
    <div className="flex items-center justify-center gap-2 py-16 text-sm text-muted">
      <Spinner /> {label}
    </div>
  );
}

export function Skeleton({ className }: { className?: string }) {
  return <div className={cn("animate-pulse rounded-[12px] bg-subtle", className)} />;
}

export function EmptyState({
  icon,
  title,
  description,
  action,
  className,
}: {
  icon?: React.ReactNode;
  title: string;
  description?: string;
  action?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("flex flex-col items-center justify-center rounded-[var(--radius-card)] bg-card px-6 py-12 text-center", className)}>
      {icon ? <div className="mb-3 text-faint">{icon}</div> : null}
      <p className="text-base font-semibold text-fg">{title}</p>
      {description ? <p className="mt-1 max-w-sm text-sm text-muted">{description}</p> : null}
      {action ? <div className="mt-5">{action}</div> : null}
    </div>
  );
}

export function ErrorState({
  title = "Daten konnten nicht geladen werden",
  description = "Bitte Verbindung prüfen und die Seite neu laden.",
  action,
}: {
  title?: string;
  description?: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="rounded-[var(--radius-card)] bg-danger-soft px-5 py-6 text-center">
      <p className="font-semibold text-danger">{title}</p>
      <p className="mt-1 text-sm text-muted">{description}</p>
      {action ? <div className="mt-4">{action}</div> : null}
    </div>
  );
}
