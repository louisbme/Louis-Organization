import { LogOut } from "lucide-react";
import { requireUser } from "@/lib/auth/require-user";
import { formatDate } from "@/lib/utils/format";
import { PageHeader } from "@/components/ui/page-header";
import { Avatar } from "@/components/ui/avatar";
import { List, ListRow } from "@/components/ui/list";
import { ADMIN_NAV, MORE_NAV } from "@/components/nav/nav-items";

export const metadata = { title: "Mehr" };

export default async function MorePage() {
  const { user, profile } = await requireUser();
  const items = profile.role === "admin" ? [...MORE_NAV, ...ADMIN_NAV] : MORE_NAV;
  return (
    <div className="space-y-4">
      <PageHeader title="Mehr" />
      <List>
        <ListRow
          href="/profile"
          leading={<Avatar name={profile.nickname} size={40} />}
          title={<span className="font-semibold">{profile.nickname}</span>}
          subtitle={`${user.email ?? ""} · dabei seit ${formatDate(profile.created_at, "MMM yyyy")}`}
          chevron
          className="min-h-[64px]"
        />
      </List>
      <List>
        {items.map((item) => {
          const Icon = item.icon;
          return <ListRow key={item.href} href={item.href} leading={<Icon className="h-5 w-5" strokeWidth={1.9} />} title={item.label} chevron />;
        })}
      </List>
      <List>
        <form action="/auth/signout" method="post">
          <button type="submit" className="press flex min-h-[52px] w-full items-center justify-center gap-2 px-4 text-base font-semibold text-danger hover:bg-subtle">
            <LogOut className="h-5 w-5" strokeWidth={2} />
            Abmelden
          </button>
        </form>
      </List>
    </div>
  );
}
