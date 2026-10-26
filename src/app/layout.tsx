import type { Metadata, Viewport } from "next";
import { Montserrat } from "next/font/google";
import { Toaster } from "@/components/ui/toaster";
import { APP_DESCRIPTION, APP_NAME } from "@/lib/config";
import "./globals.css";

/** Montserrat nur für große Titel und Kennzahlen; Text und Bedienelemente nutzen die Systemschrift. */
const montserrat = Montserrat({ variable: "--font-montserrat", subsets: ["latin"], weight: ["600", "700", "800"], display: "swap" });

export const metadata: Metadata = {
  title: { default: APP_NAME, template: `%s · ${APP_NAME}` },
  description: APP_DESCRIPTION,
  applicationName: APP_NAME,
  manifest: "/manifest.webmanifest",
  appleWebApp: { capable: true, statusBarStyle: "black-translucent", title: APP_NAME },
  icons: {
    icon: [
      { url: "/icons/favicon-64.png", type: "image/png", sizes: "64x64" },
      { url: "/icons/icon-192.png", type: "image/png", sizes: "192x192" },
    ],
    apple: "/icons/apple-touch-icon.png",
  },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: dark)", color: "#000000" },
    { media: "(prefers-color-scheme: light)", color: "#f2f2f7" },
  ],
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
};

/** Setzt das Theme vor dem ersten Paint (verhindert Flackern). */
const themeScript = `(function(){try{var t=localStorage.getItem('theme');if(t==='light'||(t==='system'&&window.matchMedia('(prefers-color-scheme: light)').matches)){document.documentElement.setAttribute('data-theme','light');}}catch(e){}})();`;

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="de" data-theme="dark" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
      </head>
      <body className={`${montserrat.variable} antialiased`}>
        {children}
        <Toaster />
      </body>
    </html>
  );
}
