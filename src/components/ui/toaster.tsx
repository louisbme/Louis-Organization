"use client";

import { Toaster as SonnerToaster } from "sonner";

export function Toaster() {
  return (
    <SonnerToaster
      position="top-center"
      duration={3000}
      closeButton={false}
      toastOptions={{
        style: {
          background: "var(--bg-card)",
          color: "var(--fg)",
          border: "1px solid var(--border)",
          borderRadius: "12px",
          fontSize: "14px",
        },
      }}
    />
  );
}
