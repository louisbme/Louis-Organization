import Link from "next/link";
import { HeroLogo } from "@/components/brand/logo";
import { APP_TAGLINE } from "@/lib/config";

export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="relative flex min-h-dvh flex-col bg-bg">
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 bg-cover bg-center opacity-[0.22] [mask-image:linear-gradient(to_bottom,black,transparent_85%)]"
        style={{ backgroundImage: "url(/images/gym-hero.jpg)" }}
      />
      <div aria-hidden className="pointer-events-none absolute inset-0 bg-gradient-to-b from-bg/40 via-bg/80 to-bg" />
      <div className="safe-top relative mx-auto flex w-full max-w-md flex-1 flex-col px-5 py-10 sm:py-16">
        <Link href="/login" className="mb-3 self-center animate-fade-up">
          <HeroLogo />
        </Link>
        <p className="mb-10 text-center text-sm text-muted animate-fade-up [animation-delay:60ms]">{APP_TAGLINE}</p>
        <main className="flex-1 animate-fade-up [animation-delay:120ms]">{children}</main>
      </div>
    </div>
  );
}
