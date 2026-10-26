import * as React from "react";
import Link from "next/link";
import { ChevronLeft } from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface PageHeaderProps {
  title: string;
  description?: string;
  backHref?: string;
  /** Beschriftung des Zurück-Links (Standard: „Zurück“) */
  backLabel?: string;
  actions?: React.ReactNode;
  className?: string;
  eyebrow?: string;
  /** Kleiner Titel (Unterseiten) statt großem Titel */
  compact?: boolean;
}

/**
 * Seitentitel nach iOS: großer Titel (34 pt) für Hauptbereiche, Zurück-Link in Akzentfarbe,
 * Aktionen am rechten Rand.
 */
export function PageHeader({ title, description, backHref, backLabel = "Zurück", actions, className, eyebrow, compact }: PageHeaderProps) {
  return (
    <header className={cn("mb-5", className)}>
      {backHref ? (
        <Link href={backHref} className="press -ml-1.5 mb-2 inline-flex h-9 items-center gap-0.5 pr-2 text-base font-medium text-accent">
          <ChevronLeft className="h-5 w-5" strokeWidth={2.4} /> {backLabel}
        </Link>
      ) : null}
      <div className="flex items-end justify-between gap-4">
        <div className="min-w-0">
          {eyebrow ? <p className="mb-1 text-[13px] font-semibold uppercase tracking-[0.06em] text-muted">{eyebrow}</p> : null}
          <h1 className={cn("truncate text-fg", compact ? "text-2xl" : "text-3xl")}>{title}</h1>
          {description ? <p className="mt-1 text-sm text-muted">{description}</p> : null}
        </div>
        {actions ? <div className="flex shrink-0 items-center gap-2 pb-0.5">{actions}</div> : null}
      </div>
    </header>
  );
}
