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
          borderRadius: "16px",
          fontSize: "15px",
          boxShadow: "var(--shadow-float)",
        },
      }}
    />
  );
}
