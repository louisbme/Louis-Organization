import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  images: {
    // Übungsbilder werden als normale <img> geladen (austauschbare Quelle, z. B. Supabase Storage).
    remotePatterns: [],
  },
};

export default nextConfig;
