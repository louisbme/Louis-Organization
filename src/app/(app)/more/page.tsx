import Link from "next/link";
import { ChevronRight, LogOut } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card } from "@/components/ui/card";
import { MORE_NAV } from "@/components/nav/nav-items";

export const metadata = { title: "Mehr" };

export default function MorePage() {
  return (
    <div>
      <PageHeader title="Mehr" />
      <Card className="divide-y divide-border overflow-hidden">
        {MORE_NAV.map((item) => {
          const Icon = item.icon;
          return (
            <Link
              key={item.href}
              href={item.href}
              className="flex h-14 items-center gap-4 px-5 text-sm font-medium hover:bg-subtle"
            >
              <Icon className="h-5 w-5 text-muted" strokeWidth={1.9} />
              <span className="flex-1">{item.label}</span>
              <ChevronRight className="h-4 w-4 text-faint" />
            </Link>
          );
        })}
        <form action="/auth/signout" method="post">
          <button
            type="submit"
            className="flex h-14 w-full items-center gap-4 px-5 text-left text-sm font-medium text-danger hover:bg-subtle"
          >
            <LogOut className="h-5 w-5" strokeWidth={1.9} />
            Abmelden
          </button>
        </form>
      </Card>
    </div>
  );
}
