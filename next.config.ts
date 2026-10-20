import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  images: {
    // Übungsbilder werden als normale <img> geladen (austauschbare Quelle, z. B. Supabase Storage).
    remotePatterns: [],
  },
  experimental: {
    // Dynamische Seiten 30 s im Client-Router-Cache halten: Navigation fühlt sich sofort an.
    // Mutationen rufen router.refresh() auf, daher bleiben Daten nach Änderungen aktuell.
    staleTimes: { dynamic: 30, static: 180 },
  },
};

export default nextConfig;
