import Link from "next/link";
import { cn } from "@/lib/utils/cn";

/** Runder Avatar mit Initiale (kein Foto-Upload nötig). */
export function Avatar({ name, className, size = 36 }: { name: string; className?: string; size?: number }) {
  const initial = (name.trim().charAt(0) || "?").toUpperCase();
  return (
    <span
      aria-hidden
      className={cn("inline-flex shrink-0 items-center justify-center rounded-full bg-subtle font-semibold text-fg", className)}
      style={{ width: size, height: size, fontSize: Math.round(size * 0.42) }}
    >
      {initial}
    </span>
  );
}

/** Avatar als Link zum Profilbereich (Mehr), wie in Apple Fitness oben rechts. */
export function AvatarLink({ name, href = "/more", className }: { name: string; href?: string; className?: string }) {
  return (
    <Link
      href={href}
      aria-label="Profil und mehr"
      className={cn("press flex h-11 w-11 shrink-0 items-center justify-center rounded-full", className)}
    >
      <Avatar name={name} />
    </Link>
  );
}
