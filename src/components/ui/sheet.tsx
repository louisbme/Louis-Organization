"use client";

import * as React from "react";
import { createPortal } from "react-dom";
import { X } from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface SheetProps {
  open: boolean;
  onClose: () => void;
  title?: string;
  description?: string;
  children: React.ReactNode;
  /** Auf Desktop zentriert, auf Mobile als Bottom Sheet */
  size?: "md" | "lg";
  footer?: React.ReactNode;
}

/**
 * Modal / Bottom Sheet ohne externe Abhängigkeit.
 * Wird per Portal direkt in <body> gerendert, damit position: fixed immer den Viewport meint
 * (auch wenn ein Vorfahr ein transform trägt, z. B. durch Animationen).
 */
export function Sheet({ open, onClose, title, description, children, size = "md", footer }: SheetProps) {
  const panelRef = React.useRef<HTMLDivElement>(null);
  const [mounted, setMounted] = React.useState(false);
  React.useEffect(() => setMounted(true), []);

  React.useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = prev;
    };
  }, [open, onClose]);

  if (!open || !mounted) return null;

  return createPortal(
    <div
      className="fixed inset-0 z-50 flex items-end justify-center sm:items-center sm:p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby={title ? "sheet-title" : undefined}
    >
      <div className="absolute inset-0 animate-fade-in bg-black/60" onClick={onClose} aria-hidden />
      <div
        ref={panelRef}
        className={cn(
          "relative flex max-h-[92dvh] w-full flex-col overflow-hidden rounded-t-2xl border border-border bg-card animate-sheet-in sm:rounded-2xl",
          size === "lg" ? "sm:max-w-2xl" : "sm:max-w-md"
        )}
      >
        <div className="flex items-start justify-between gap-4 px-5 pt-5 pb-3">
          <div className="min-w-0">
            {title ? (
              <h2 id="sheet-title" className="text-lg font-semibold tracking-tight">
                {title}
              </h2>
            ) : null}
            {description ? <p className="mt-0.5 text-sm text-muted">{description}</p> : null}
          </div>
          <button
            type="button"
            onClick={onClose}
            className="-mr-2 -mt-1 flex h-9 w-9 shrink-0 items-center justify-center rounded-lg text-muted hover:bg-subtle hover:text-fg"
            aria-label="Schließen"
          >
            <X className="h-5 w-5" />
          </button>
        </div>
        <div className="flex-1 overflow-y-auto px-5 pb-5">{children}</div>
        {footer ? <div className="border-t border-border bg-card px-5 py-4 safe-bottom">{footer}</div> : null}
      </div>
    </div>,
    document.body
  );
}
