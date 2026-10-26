import {
  LayoutGrid,
  Dumbbell,
  ClipboardList,
  History,
  TrendingUp,
  BookOpen,
  CalendarDays,
  Users,
  User,
  Settings,
  ShieldCheck,
  type LucideIcon,
} from "lucide-react";

export interface NavItem {
  href: string;
  label: string;
  icon: LucideIcon;
}

export const PRIMARY_NAV: NavItem[] = [
  { href: "/dashboard", label: "Start", icon: LayoutGrid },
  { href: "/workout", label: "Training", icon: Dumbbell },
  { href: "/plans", label: "Pläne", icon: ClipboardList },
  { href: "/history", label: "Verlauf", icon: History },
  { href: "/progress", label: "Fortschritt", icon: TrendingUp },
  { href: "/exercises", label: "Übungen", icon: BookOpen },
  { href: "/calendar", label: "Kalender", icon: CalendarDays },
  { href: "/stats", label: "Stats", icon: Users },
];

export const SECONDARY_NAV: NavItem[] = [
  { href: "/profile", label: "Profil", icon: User },
  { href: "/settings", label: "Einstellungen", icon: Settings },
];

/** Nur für Admins */
export const ADMIN_NAV: NavItem[] = [{ href: "/admin", label: "Verwaltung", icon: ShieldCheck }];

/** Mobile Tab-Leiste: fünf Bereiche, alles Weitere über den Avatar (Mehr) */
export const MOBILE_NAV: NavItem[] = [
  { href: "/dashboard", label: "Start", icon: LayoutGrid },
  { href: "/workout", label: "Training", icon: Dumbbell },
  { href: "/exercises", label: "Übungen", icon: BookOpen },
  { href: "/history", label: "Verlauf", icon: History },
  { href: "/progress", label: "Fortschritt", icon: TrendingUp },
];

export const MORE_NAV: NavItem[] = [
  { href: "/plans", label: "Trainingspläne", icon: ClipboardList },
  { href: "/history?tab=calendar", label: "Kalender", icon: CalendarDays },
  { href: "/stats", label: "Stats", icon: Users },
  { href: "/profile", label: "Profil", icon: User },
  { href: "/settings", label: "Einstellungen", icon: Settings },
];

export function isActivePath(pathname: string, href: string): boolean {
  if (href === "/more") {
    return pathname === "/more" || [...MORE_NAV, ...ADMIN_NAV].some((i) => pathname === i.href || pathname.startsWith(i.href + "/"));
  }
  return pathname === href || pathname.startsWith(href + "/");
}
