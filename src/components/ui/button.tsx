"use client";

import * as React from "react";
import { Loader2 } from "lucide-react";
import { cn } from "@/lib/utils/cn";

type Variant = "primary" | "secondary" | "ghost" | "danger" | "outline" | "plain";
type Size = "sm" | "md" | "lg" | "icon" | "icon-sm";

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  size?: Size;
  loading?: boolean;
  fullWidth?: boolean;
}

/**
 * Button-Stile nach iOS: prominent (gefüllt, Akzent), gefüllt grau (secondary),
 * nur Text in Akzentfarbe (plain), neutral ohne Fläche (ghost), destruktiv (danger).
 */
const variantClasses: Record<Variant, string> = {
  primary: "bg-accent-fill text-accent-fg font-semibold hover:brightness-110",
  secondary: "bg-subtle text-fg font-semibold hover:bg-hover",
  outline: "bg-transparent text-fg font-semibold border border-border-strong hover:bg-subtle",
  ghost: "bg-transparent text-muted hover:bg-subtle hover:text-fg",
  plain: "bg-transparent text-accent font-semibold hover:bg-accent-soft",
  danger: "bg-danger-soft text-danger font-semibold hover:brightness-110",
};

const sizeClasses: Record<Size, string> = {
  sm: "h-9 px-4 text-sm rounded-full gap-1.5",
  md: "h-11 px-5 text-base rounded-full gap-2",
  lg: "h-[52px] px-6 text-base rounded-full gap-2",
  icon: "h-11 w-11 rounded-full",
  "icon-sm": "h-9 w-9 rounded-full",
};

export const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { className, variant = "primary", size = "md", loading = false, fullWidth, disabled, children, type = "button", ...props },
  ref
) {
  return (
    <button
      ref={ref}
      type={type}
      disabled={disabled || loading}
      className={cn(
        "press inline-flex items-center justify-center select-none whitespace-nowrap disabled:opacity-40 disabled:pointer-events-none touch-manipulation",
        variantClasses[variant],
        sizeClasses[size],
        fullWidth && "w-full",
        className
      )}
      {...props}
    >
      {loading ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden /> : null}
      {children}
    </button>
  );
});
