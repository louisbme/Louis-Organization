import Link from "next/link";
import { Wordmark } from "@/components/brand/logo";

export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-dvh flex-col bg-bg">
      <div className="mx-auto flex w-full max-w-md flex-1 flex-col px-5 py-10 sm:py-16">
        <Link href="/login" className="mb-10 self-start">
          <Wordmark />
        </Link>
        <main className="flex-1">{children}</main>
        <p className="mt-10 text-center text-xs text-faint">Private Nutzung · Kein Social Login · Keine KI</p>
      </div>
    </div>
  );
}
