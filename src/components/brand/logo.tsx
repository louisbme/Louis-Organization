import { cn } from "@/lib/utils/cn";
import { APP_NAME } from "@/lib/config";

/** Bildmarke „FY“ (public/brand/logo.png, weiß auf Schwarz), als abgerundetes Quadrat. */
export function LogoMark({ className, size = 32 }: { className?: string; size?: number }) {
  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src="/brand/logo.svg"
      alt={APP_NAME}
      width={size}
      height={size}
      className={cn("shrink-0 rounded-[22%] bg-black object-cover ring-1 ring-white/10", className)}
      style={{ width: size, height: size }}
    />
  );
}

/** Bildmarke plus Schriftzug „FORM YOURSELF“ */
export function Wordmark({ className, size = 32 }: { className?: string; size?: number }) {
  return (
    <span className={cn("inline-flex items-center gap-2.5", className)}>
      <LogoMark size={size} />
      <span className="font-sans text-[15px] font-semibold uppercase tracking-[0.22em] text-fg">{APP_NAME}</span>
    </span>
  );
}

/** Großes Logo mit Schriftzug für Login und Setup (public/brand/wordmark.png). */
export function HeroLogo({ className }: { className?: string }) {
  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img src="/brand/wordmark.png" alt={APP_NAME} width={320} height={160} className={cn("h-auto w-56 sm:w-64", className)} />
  );
}
