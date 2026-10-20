"use client";

import * as React from "react";
import { Loader2 } from "lucide-react";
import { cn } from "@/lib/utils/cn";

type Variant = "primary" | "secondary" | "ghost" | "danger" | "outline";
type Size = "sm" | "md" | "lg" | "icon";

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  size?: Size;
  loading?: boolean;
  fullWidth?: boolean;
}

const variantClasses: Record<Variant, string> = {
  primary: "bg-accent text-accent-fg hover:bg-accent-strong active:bg-accent-strong font-semibold",
  secondary: "bg-subtle text-fg hover:bg-hover border border-border",
  outline: "bg-transparent text-fg border border-border-strong hover:bg-subtle",
  ghost: "bg-transparent text-muted hover:bg-subtle hover:text-fg",
  danger: "bg-danger-soft text-danger hover:bg-[rgba(248,113,113,0.2)] border border-transparent",
};

const sizeClasses: Record<Size, string> = {
  sm: "h-9 px-3 text-sm rounded-lg gap-1.5",
  md: "h-11 px-4 text-sm rounded-xl gap-2",
  lg: "h-13 px-5 text-base rounded-xl gap-2",
  icon: "h-11 w-11 rounded-xl",
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
        "inline-flex items-center justify-center select-none whitespace-nowrap transition-colors duration-150 disabled:opacity-50 disabled:pointer-events-none touch-manipulation",
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
