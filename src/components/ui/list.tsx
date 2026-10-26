import * as React from "react";
import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { cn } from "@/lib/utils/cn";

/** Gruppierte Liste nach iOS: eine Fläche, Trennlinien eingerückt ab Textbeginn. */
export function List({ className, children, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div className={cn("overflow-hidden rounded-[var(--radius-card)] bg-card", className)} {...props}>
      {children}
    </div>
  );
}

/** Abschnittsüberschrift über einer Liste */
export function ListHeader({ children, trailing, className }: { children: React.ReactNode; trailing?: React.ReactNode; className?: string }) {
  return (
    <div className={cn("mb-2 flex items-baseline justify-between px-4", className)}>
      <h2 className="font-sans text-[13px] font-semibold uppercase tracking-[0.06em] text-muted">{children}</h2>
      {trailing ? <span className="text-[13px] text-faint">{trailing}</span> : null}
    </div>
  );
}

interface ListRowProps {
  href?: string;
  onClick?: () => void;
  leading?: React.ReactNode;
  title: React.ReactNode;
  subtitle?: React.ReactNode;
  trailing?: React.ReactNode;
  /** Pfeil rechts (Navigation) */
  chevron?: boolean;
  disabled?: boolean;
  className?: string;
  tone?: "default" | "danger";
}

/**
 * Listenzeile: mindestens 52 pt hoch, Titel 17 pt, Untertitel 15 pt.
 * Als Link, Button oder passive Zeile.
 */
export function ListRow({ href, onClick, leading, title, subtitle, trailing, chevron, disabled, className, tone = "default" }: ListRowProps) {
  const content = (
    <>
      {leading ? <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-[10px] bg-subtle text-muted">{leading}</div> : null}
      <div className="min-w-0 flex-1">
        <div className={cn("truncate text-base", tone === "danger" ? "text-danger" : "text-fg")}>{title}</div>
        {subtitle ? <div className="truncate text-sm text-muted">{subtitle}</div> : null}
      </div>
      {trailing ? <div className="tnum shrink-0 text-sm text-muted">{trailing}</div> : null}
      {chevron ? <ChevronRight className="h-4 w-4 shrink-0 text-faint" strokeWidth={2.4} /> : null}
    </>
  );
  const base = cn(
    "relative flex min-h-[52px] w-full items-center gap-3 px-4 py-2 text-left touch-manipulation",
    "after:pointer-events-none after:absolute after:bottom-0 after:right-0 after:h-px after:bg-border after:content-['']",
    leading ? "after:left-[68px]" : "after:left-4",
    "last:after:hidden",
    (href || onClick) && !disabled && "press hover:bg-subtle",
    disabled && "opacity-50",
    className
  );
  if (href && !disabled) {
    return (
      <Link href={href} className={base}>
        {content}
      </Link>
    );
  }
  if (onClick) {
    return (
      <button type="button" onClick={onClick} disabled={disabled} className={base}>
        {content}
      </button>
    );
  }
  return <div className={base}>{content}</div>;
}
