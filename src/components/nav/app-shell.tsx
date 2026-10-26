"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { LogOut, Play } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { useUser } from "@/lib/context/user-context";
import { Wordmark } from "@/components/brand/logo";
import { Avatar } from "@/components/ui/avatar";
import { ADMIN_NAV, MOBILE_NAV, PRIMARY_NAV, SECONDARY_NAV, isActivePath } from "@/components/nav/nav-items";
import { PageTransition } from "@/components/theme/page-transition";

interface AppShellProps {
  activeSession: { id: string; name: string } | null;
  children: React.ReactNode;
}

export function AppShell({ activeSession, children }: AppShellProps) {
  const pathname = usePathname();
  const { profile } = useUser();
  const isWorkoutScreen = pathname.startsWith("/workout/");
  const showBanner = !!activeSession && !isWorkoutScreen;

  return (
    <div className="min-h-dvh bg-bg">
      {/* Desktop Sidebar */}
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-64 flex-col border-r border-border bg-card/60 backdrop-blur-xl lg:flex">
        <div className="px-5 pb-4 pt-6">
          <Link href="/dashboard">
            <Wordmark />
          </Link>
        </div>
        <nav className="flex-1 space-y-0.5 px-3">
          {PRIMARY_NAV.map((item) => (
            <SidebarLink key={item.href} item={item} active={isActivePath(pathname, item.href)} />
          ))}
          <div className="my-3 border-t border-border" />
          {SECONDARY_NAV.map((item) => (
            <SidebarLink key={item.href} item={item} active={isActivePath(pathname, item.href)} />
          ))}
          {profile.role === "admin"
            ? ADMIN_NAV.map((item) => <SidebarLink key={item.href} item={item} active={isActivePath(pathname, item.href)} />)
            : null}
        </nav>
        <div className="border-t border-border p-3">
          <div className="flex items-center gap-3 rounded-[12px] px-2 py-2">
            <Avatar name={profile.nickname} size={32} />
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-semibold">{profile.nickname}</p>
              <p className="text-xs text-faint">Angemeldet</p>
            </div>
            <form action="/auth/signout" method="post">
              <button
                type="submit"
                className="press flex h-9 w-9 items-center justify-center rounded-full text-muted hover:bg-subtle hover:text-fg"
                aria-label="Abmelden"
                title="Abmelden"
              >
                <LogOut className="h-4 w-4" />
              </button>
            </form>
          </div>
        </div>
      </aside>

      {/* Inhalt */}
      <div className="lg:pl-64">
        <main
          className={cn(
            "mx-auto w-full max-w-5xl px-4 sm:px-6 lg:px-8 lg:pt-8",
            // Auf dem Trainingsbildschirm trägt der klebende Kopf die Safe-Area selbst
            isWorkoutScreen ? "pb-6 pt-0" : "safe-top pb-32 pt-4 lg:pb-12",
            showBanner && "pb-44 lg:pb-24"
          )}
        >
          <PageTransition>{children}</PageTransition>
        </main>
      </div>

      {/* Aktives Training: schwebende Hinweiskarte über der Tab-Leiste */}
      {showBanner ? (
        <div className="fixed inset-x-0 bottom-[calc(6rem+env(safe-area-inset-bottom,0px))] z-30 px-4 lg:bottom-6 lg:left-64 lg:px-8">
          <Link
            href={`/workout/${activeSession.id}`}
            className="glass press mx-auto flex max-w-md items-center justify-between gap-3 rounded-full py-2 pl-4 pr-2 shadow-[var(--shadow-float)] lg:max-w-5xl lg:rounded-[20px] lg:px-5 lg:py-3"
          >
            <div className="flex min-w-0 items-center gap-3">
              <span className="relative flex h-2.5 w-2.5 shrink-0">
                <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-accent opacity-60" />
                <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-accent" />
              </span>
              <div className="min-w-0">
                <p className="truncate text-sm font-semibold">Training läuft</p>
                <p className="truncate text-xs text-muted">{activeSession.name}</p>
              </div>
            </div>
            <span className="inline-flex h-9 shrink-0 items-center gap-1.5 rounded-full bg-accent-fill px-4 text-sm font-semibold text-accent-fg">
              <Play className="h-3.5 w-3.5" fill="currentColor" /> Weiter
            </span>
          </Link>
        </div>
      ) : null}

      {/* Mobile Tab-Leiste: schwebend, durchscheinend, fünf Bereiche */}
      {!isWorkoutScreen ? (
        <nav className="fixed inset-x-0 bottom-0 z-30 px-4 pb-[calc(0.5rem+env(safe-area-inset-bottom,0px))] pt-2 lg:hidden" aria-label="Hauptnavigation">
          <ul className="glass mx-auto flex h-[66px] max-w-md items-center justify-around rounded-full px-1 shadow-[var(--shadow-float)]">
            {MOBILE_NAV.map((item) => {
              const active = isActivePath(pathname, item.href);
              const Icon = item.icon;
              return (
                <li key={item.href} className="flex-1">
                  <Link
                    href={item.href}
                    className={cn(
                      "press flex h-full flex-col items-center justify-center gap-0.5 py-1 text-[11px] font-medium transition-colors duration-200 touch-manipulation",
                      active ? "text-accent" : "text-muted hover:text-fg"
                    )}
                    aria-current={active ? "page" : undefined}
                  >
                    <span className={cn("flex h-7 w-12 items-center justify-center rounded-full transition-colors duration-200", active && "bg-accent-soft")}>
                      <Icon className="h-[22px] w-[22px]" strokeWidth={active ? 2.4 : 1.9} />
                    </span>
                    <span className="leading-none">{item.label}</span>
                  </Link>
                </li>
              );
            })}
          </ul>
        </nav>
      ) : null}
    </div>
  );
}

function SidebarLink({ item, active }: { item: { href: string; label: string; icon: React.ElementType }; active: boolean }) {
  const Icon = item.icon;
  return (
    <Link
      href={item.href}
      className={cn(
        "press flex h-11 items-center gap-3 rounded-[12px] px-3 text-base font-medium",
        active ? "bg-subtle text-fg" : "text-muted hover:bg-subtle/60 hover:text-fg"
      )}
      aria-current={active ? "page" : undefined}
    >
      <Icon className={cn("h-5 w-5", active ? "text-accent" : "")} strokeWidth={active ? 2.2 : 1.9} />
      {item.label}
    </Link>
  );
}
