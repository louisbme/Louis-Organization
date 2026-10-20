"use client";

import * as React from "react";
import Link from "next/link";
import { Search, Star, ChevronRight, Plus } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import type { EquipmentType, ExerciseCategory } from "@/lib/supabase/types";
import type { ExerciseListItem } from "@/lib/services/exercises";
import { CATEGORY_LABELS, CATEGORY_ORDER, EQUIPMENT_LABELS, EQUIPMENT_ORDER } from "@/lib/utils/labels";
import { EquipmentIcon } from "@/components/exercise/equipment-icon";
import { EmptyState } from "@/components/ui/states";
import { Button } from "@/components/ui/button";

interface ExerciseBrowserProps {
  items: ExerciseListItem[];
  mode?: "browse" | "pick";
  onPick?: (item: ExerciseListItem) => void;
  showCreateLink?: boolean;
}

type CategoryFilter = ExerciseCategory | "all";
type EquipmentFilter = EquipmentType | "all";

export function ExerciseBrowser({ items, mode = "browse", onPick, showCreateLink = true }: ExerciseBrowserProps) {
  const [query, setQuery] = React.useState("");
  const [category, setCategory] = React.useState<CategoryFilter>("all");
  const [equipment, setEquipment] = React.useState<EquipmentFilter>("all");
  const [favoritesOnly, setFavoritesOnly] = React.useState(false);

  const filtered = React.useMemo(() => {
    const q = query.trim().toLowerCase();
    return items
      .filter((e) => (category === "all" ? true : e.category === category))
      .filter((e) => (equipment === "all" ? true : e.equipment === equipment))
      .filter((e) => (favoritesOnly ? e.is_favorite : true))
      .filter((e) => (q ? e.name.toLowerCase().includes(q) || CATEGORY_LABELS[e.category].toLowerCase().includes(q) : true))
      .sort((a, b) => Number(b.is_favorite) - Number(a.is_favorite) || a.name.localeCompare(b.name, "de"));
  }, [items, query, category, equipment, favoritesOnly]);

  const grouped = React.useMemo(() => {
    const favorites = filtered.filter((e) => e.is_favorite);
    const rest = filtered.filter((e) => !e.is_favorite);
    const byCategory = new Map<ExerciseCategory, ExerciseListItem[]>();
    for (const e of rest) {
      const list = byCategory.get(e.category) ?? [];
      list.push(e);
      byCategory.set(e.category, list);
    }
    return { favorites, byCategory };
  }, [filtered]);

  const hasFilters = query || category !== "all" || equipment !== "all" || favoritesOnly;

  return (
    <div className="space-y-4">
      <div className="relative">
        <Search className="pointer-events-none absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-faint" />
        <input
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Übung suchen"
          className="h-12 w-full rounded-xl border border-border bg-subtle pl-11 pr-4 text-base placeholder:text-faint focus:border-border-strong focus:outline-none focus:ring-2 focus:ring-[var(--ring)]"
          autoComplete="off"
        />
      </div>

      <div className="-mx-4 overflow-x-auto px-4 sm:mx-0 sm:px-0">
        <div className="flex w-max gap-2 pb-1">
          <FilterChip active={favoritesOnly} onClick={() => setFavoritesOnly((v) => !v)}>
            <Star className={cn("h-3.5 w-3.5", favoritesOnly && "fill-current")} /> Favoriten
          </FilterChip>
          <FilterChip active={category === "all"} onClick={() => setCategory("all")}>
            Alle
          </FilterChip>
          {CATEGORY_ORDER.map((c) => (
            <FilterChip key={c} active={category === c} onClick={() => setCategory(category === c ? "all" : c)}>
              {CATEGORY_LABELS[c]}
            </FilterChip>
          ))}
        </div>
      </div>
      <div className="-mx-4 overflow-x-auto px-4 sm:mx-0 sm:px-0">
        <div className="flex w-max gap-2 pb-1">
          {EQUIPMENT_ORDER.filter((e) => e !== "other" && e !== "bench").map((eq) => (
            <FilterChip key={eq} active={equipment === eq} onClick={() => setEquipment(equipment === eq ? "all" : eq)}>
              <EquipmentIcon equipment={eq} className="h-3.5 w-3.5" /> {EQUIPMENT_LABELS[eq]}
            </FilterChip>
          ))}
        </div>
      </div>

      {filtered.length === 0 ? (
        <EmptyState
          title="Keine Übungen gefunden"
          description={hasFilters ? "Andere Suche oder Filter ausprobieren." : "Noch keine Übungen vorhanden."}
          action={
            showCreateLink && mode === "browse" ? (
              <Link href="/exercises/new">
                <Button variant="secondary">
                  <Plus className="h-4 w-4" /> Eigene Übung erstellen
                </Button>
              </Link>
            ) : undefined
          }
        />
      ) : (
        <div className="space-y-6">
          {grouped.favorites.length > 0 ? (
            <Group title="Favoriten" count={grouped.favorites.length}>
              {grouped.favorites.map((e) => (
                <Row key={e.id} item={e} mode={mode} onPick={onPick} />
              ))}
            </Group>
          ) : null}
          {CATEGORY_ORDER.filter((c) => grouped.byCategory.has(c)).map((c) => (
            <Group key={c} title={CATEGORY_LABELS[c]} count={grouped.byCategory.get(c)!.length}>
              {grouped.byCategory.get(c)!.map((e) => (
                <Row key={e.id} item={e} mode={mode} onPick={onPick} />
              ))}
            </Group>
          ))}
        </div>
      )}
    </div>
  );
}

function FilterChip({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "inline-flex h-9 shrink-0 items-center gap-1.5 rounded-full border px-3.5 text-sm font-medium transition-colors touch-manipulation",
        active ? "border-accent bg-accent-soft text-accent" : "border-border bg-card text-muted hover:text-fg"
      )}
    >
      {children}
    </button>
  );
}

function Group({ title, count, children }: { title: string; count: number; children: React.ReactNode }) {
  return (
    <section>
      <div className="mb-2 flex items-baseline justify-between px-1">
        <h2 className="text-[11px] font-semibold uppercase tracking-[0.12em] text-faint">{title}</h2>
        <span className="text-xs text-faint">{count}</span>
      </div>
      <div className="divide-y divide-border overflow-hidden rounded-[var(--radius-card)] border border-border bg-card">
        {children}
      </div>
    </section>
  );
}

function Row({ item, mode, onPick }: { item: ExerciseListItem; mode: "browse" | "pick"; onPick?: (i: ExerciseListItem) => void }) {
  const content = (
    <>
      <div className="flex h-12 w-12 shrink-0 items-center justify-center overflow-hidden rounded-lg bg-subtle text-muted">
        {item.image_url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={item.image_url} alt="" loading="lazy" decoding="async" className="h-full w-full bg-white object-contain p-0.5" />
        ) : (
          <EquipmentIcon equipment={item.equipment} className="h-5 w-5" strokeWidth={1.7} />
        )}
      </div>
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium text-fg">{item.name}</p>
        <p className="truncate text-xs text-muted">
          {CATEGORY_LABELS[item.category]} · {EQUIPMENT_LABELS[item.equipment]}
          {item.is_custom ? " · Eigene Übung" : ""}
        </p>
      </div>
      {item.is_favorite ? <Star className="h-4 w-4 shrink-0 fill-current text-accent" /> : null}
      {mode === "pick" ? <Plus className="h-4 w-4 shrink-0 text-faint" /> : <ChevronRight className="h-4 w-4 shrink-0 text-faint" />}
    </>
  );
  const className = "flex min-h-16 w-full items-center gap-3 px-4 py-2.5 text-left hover:bg-subtle touch-manipulation";
  if (mode === "pick") {
    return (
      <button type="button" onClick={() => onPick?.(item)} className={className}>
        {content}
      </button>
    );
  }
  return (
    <Link href={`/exercises/${item.slug}`} className={className}>
      {content}
    </Link>
  );
}
