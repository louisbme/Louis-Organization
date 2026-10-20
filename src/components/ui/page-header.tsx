import * as React from "react";
import Link from "next/link";
import { ChevronLeft } from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface PageHeaderProps {
  title: string;
  description?: string;
  backHref?: string;
  actions?: React.ReactNode;
  className?: string;
  eyebrow?: string;
}

export function PageHeader({ title, description, backHref, actions, className, eyebrow }: PageHeaderProps) {
  return (
    <header className={cn("mb-5 flex items-start justify-between gap-4", className)}>
      <div className="min-w-0">
        {backHref ? (
          <Link
            href={backHref}
            className="-ml-1 mb-1 inline-flex items-center gap-0.5 text-sm text-muted hover:text-fg"
          >
            <ChevronLeft className="h-4 w-4" /> Zurück
          </Link>
        ) : null}
        {eyebrow ? (
          <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-faint">{eyebrow}</p>
        ) : null}
        <h1 className="truncate text-2xl font-semibold tracking-tight sm:text-3xl">{title}</h1>
        {description ? <p className="mt-1 text-sm text-muted">{description}</p> : null}
      </div>
      {actions ? <div className="flex shrink-0 items-center gap-2">{actions}</div> : null}
    </header>
  );
}
