import { cn } from "@/lib/utils/cn";
import { APP_NAME } from "@/lib/config";

/** Logo: Foto (public/brand/logo.jpg), rund maskiert. */
export function LogoMark({ className }: { className?: string }) {
  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src="/brand/logo.jpg"
      alt={APP_NAME}
      width={32}
      height={32}
      className={cn("h-8 w-8 rounded-lg object-cover ring-1 ring-border", className)}
    />
  );
}

export function Wordmark({ className }: { className?: string }) {
  return (
    <span className={cn("inline-flex items-center gap-2.5", className)}>
      <LogoMark />
      <span className="text-base font-semibold tracking-[0.18em]">{APP_NAME}</span>
    </span>
  );
}
