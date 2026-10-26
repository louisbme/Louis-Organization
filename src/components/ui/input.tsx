"use client";

import * as React from "react";
import { cn } from "@/lib/utils/cn";

const base =
  "w-full rounded-[12px] bg-subtle text-base text-fg placeholder:text-faint transition-shadow focus:outline-none focus:ring-2 focus:ring-[var(--ring)] disabled:opacity-50";

export interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  invalid?: boolean;
}

export const Input = React.forwardRef<HTMLInputElement, InputProps>(function Input({ className, invalid, ...props }, ref) {
  return <input ref={ref} className={cn(base, "h-12 px-4", invalid && "ring-2 ring-danger", className)} {...props} />;
});

export interface TextareaProps extends React.TextareaHTMLAttributes<HTMLTextAreaElement> {
  invalid?: boolean;
}

export const Textarea = React.forwardRef<HTMLTextAreaElement, TextareaProps>(function Textarea({ className, invalid, ...props }, ref) {
  return <textarea ref={ref} className={cn(base, "min-h-24 px-4 py-3", invalid && "ring-2 ring-danger", className)} {...props} />;
});

export interface SelectProps extends React.SelectHTMLAttributes<HTMLSelectElement> {
  invalid?: boolean;
}

export const Select = React.forwardRef<HTMLSelectElement, SelectProps>(function Select({ className, invalid, children, ...props }, ref) {
  return (
    <div className="relative">
      <select ref={ref} className={cn(base, "h-12 appearance-none px-4 pr-10", invalid && "ring-2 ring-danger", className)} {...props}>
        {children}
      </select>
      <svg
        aria-hidden
        className="pointer-events-none absolute right-4 top-1/2 h-4 w-4 -translate-y-1/2 text-faint"
        viewBox="0 0 16 16"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.8"
      >
        <path d="M4 6l4 4 4-4" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    </div>
  );
});
