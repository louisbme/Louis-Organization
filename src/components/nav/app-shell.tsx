"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { LogOut, Play } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { useUser } from "@/lib/context/user-context";
import { Wordmark } from "@/components/brand/logo";
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
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-60 flex-col border-r border-border bg-bg lg:flex">
        <div className="px-5 pt-6 pb-4">
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
          <div className="flex items-center justify-between gap-2 rounded-xl px-2 py-2">
            <div className="min-w-0">
              <p className="truncate text-sm font-medium">{profile.nickname}</p>
              <p className="text-xs text-faint">Angemeldet</p>
            </div>
            <form action="/auth/signout" method="post">
              <button
                type="submit"
                className="flex h-9 w-9 items-center justify-center rounded-lg text-muted hover:bg-subtle hover:text-fg"
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
      <div className="lg:pl-60">
        <main
          className={cn(
            "mx-auto w-full max-w-5xl px-4 sm:px-6 lg:px-8 lg:pt-8",
            // Auf dem Trainingsbildschirm trägt der klebende Kopf die Safe-Area selbst
            isWorkoutScreen ? "pt-0 pb-6" : "safe-top pt-5 pb-28 lg:pb-12",
            showBanner && "pb-40 lg:pb-24"
          )}
        >
          <PageTransition>{children}</PageTransition>
        </main>
      </div>

      {/* Aktives Training – Hinweisleiste */}
      {showBanner ? (
        <div className="fixed inset-x-0 bottom-[calc(4rem+env(safe-area-inset-bottom,0px))] z-30 px-4 lg:bottom-6 lg:left-60 lg:px-8">
          <Link
            href={`/workout/${activeSession.id}`}
            className="mx-auto flex max-w-5xl items-center justify-between gap-3 rounded-xl border border-accent/40 bg-card px-4 py-3 shadow-lg"
          >
            <div className="flex items-center gap-3">
              <span className="relative flex h-2.5 w-2.5">
                <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-accent opacity-60" />
                <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-accent" />
              </span>
              <div>
                <p className="text-sm font-medium">Training läuft</p>
                <p className="text-xs text-muted">{activeSession.name}</p>
              </div>
            </div>
            <span className="inline-flex items-center gap-1.5 text-sm font-medium text-accent">
              <Play className="h-4 w-4" /> Fortsetzen
            </span>
          </Link>
        </div>
      ) : null}

      {/* Mobile Bottom Navigation */}
      {!isWorkoutScreen ? (
        <nav className="fixed inset-x-0 bottom-0 z-30 border-t border-border bg-bg safe-bottom lg:hidden">
          <ul className="grid h-16 grid-cols-6">
            {MOBILE_NAV.map((item) => {
              const active = isActivePath(pathname, item.href);
              const Icon = item.icon;
              return (
                <li key={item.href}>
                  <Link
                    href={item.href}
                    className={cn(
                      "relative flex h-full flex-col items-center justify-center gap-1 text-[11px] font-medium transition-colors duration-200 touch-manipulation",
                      active ? "text-accent" : "text-faint hover:text-fg"
                    )}
                    aria-current={active ? "page" : undefined}
                  >
                    <span
                      className={cn(
                        "absolute top-0 h-0.5 w-8 rounded-full bg-accent transition-all duration-300",
                        active ? "scale-x-100 opacity-100" : "scale-x-0 opacity-0"
                      )}
                    />
                    <Icon className={cn("h-5 w-5 transition-transform duration-200", active && "-translate-y-px")} strokeWidth={active ? 2.2 : 1.8} />
                    <span className="text-[10px] leading-none">{item.label}</span>
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
        "press flex h-10 items-center gap-3 rounded-lg px-3 text-sm font-medium",
        active ? "bg-subtle text-fg" : "text-muted hover:bg-subtle/60 hover:text-fg"
      )}
      aria-current={active ? "page" : undefined}
    >
      <Icon className={cn("h-[18px] w-[18px]", active ? "text-accent" : "")} strokeWidth={1.9} />
      {item.label}
    </Link>
  );
}
