"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { createClient } from "@/lib/supabase/client";
import { useUser } from "@/lib/context/user-context";
import type { ProfileRow } from "@/lib/supabase/types";
import { updateBodyData } from "@/lib/services/profile";
import { upsertBodyWeight } from "@/lib/services/stats";
import { formatDate, toDateKey } from "@/lib/utils/format";
import { friendlyError } from "@/lib/utils/errors";
import { Button } from "@/components/ui/button";
import { Card, CardContent, SectionLabel } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";

interface Props {
  profile: ProfileRow;
  bodyWeight: { weight: number; entry_date: string } | null;
}

/** Verwaltung: Körperdaten eines anderen Nutzers (Gewicht, Größe, Geburtsdatum) pflegen. */
export function AdminBodyData({ profile, bodyWeight: initialBodyWeight }: Props) {
  const router = useRouter();
  const { settings } = useUser();
  const db = React.useMemo(() => createClient(), []);
  const [weight, setWeight] = React.useState(initialBodyWeight ? String(initialBodyWeight.weight).replace(".", ",") : "");
  const [saved, setSaved] = React.useState(initialBodyWeight);
  const [height, setHeight] = React.useState(profile.height_cm ? String(profile.height_cm).replace(".", ",") : "");
  const [birthDate, setBirthDate] = React.useState(profile.birth_date ?? "");
  const [busy, setBusy] = React.useState(false);

  const saveWeight = async () => {
    const v = parseFloat(weight.replace(",", "."));
    if (!v || v <= 0 || v >= 500) {
      toast.error("Bitte ein gültiges Gewicht eingeben (z. B. 82,5).");
      return;
    }
    setBusy(true);
    try {
      const today = toDateKey(new Date());
      await upsertBodyWeight(db, profile.id, today, Math.round(v * 100) / 100);
      setSaved({ weight: Math.round(v * 100) / 100, entry_date: today });
      toast.success(`Gewicht von ${profile.nickname} eingetragen`);
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      setBusy(false);
    }
  };

  const saveHeight = async () => {
    const raw = height.trim();
    const v = raw ? parseFloat(raw.replace(",", ".")) : null;
    if (v !== null && (Number.isNaN(v) || v < 100 || v > 250)) {
      toast.error("Größe bitte in Zentimetern zwischen 100 und 250 angeben.");
      setHeight(profile.height_cm ? String(profile.height_cm).replace(".", ",") : "");
      return;
    }
    if ((v ?? null) === (profile.height_cm ?? null)) return;
    try {
      await updateBodyData(db, profile.id, { height_cm: v === null ? null : Math.round(v * 10) / 10 });
      toast.success("Größe gespeichert");
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
    }
  };

  const saveBirthDate = async (value: string) => {
    setBirthDate(value);
    if ((value || null) === (profile.birth_date ?? null)) return;
    try {
      await updateBodyData(db, profile.id, { birth_date: value || null });
      toast.success("Geburtsdatum gespeichert");
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
    }
  };

  return (
    <Card>
      <CardContent className="space-y-4 pt-5">
        <SectionLabel>Körperdaten</SectionLabel>
        <Field
          label={`Körpergewicht (${settings.weight_unit})`}
          htmlFor="adminBodyWeight"
          hint={saved ? `Zuletzt eingetragen am ${formatDate(saved.entry_date)}. Wird für Körpergewichtsübungen verwendet.` : "Noch kein Gewicht eingetragen."}
        >
          <div className="flex gap-2">
            <Input id="adminBodyWeight" inputMode="decimal" value={weight} onChange={(e) => setWeight(e.target.value)} placeholder="z. B. 82,5" className="max-w-[10rem]" />
            <Button variant="secondary" onClick={saveWeight} loading={busy} disabled={!weight.trim()}>
              Heute eintragen
            </Button>
          </div>
        </Field>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Field label="Größe (cm)" htmlFor="adminHeight">
            <Input id="adminHeight" inputMode="decimal" value={height} onChange={(e) => setHeight(e.target.value)} onBlur={saveHeight} placeholder="z. B. 182" />
          </Field>
          <Field label="Geburtsdatum" htmlFor="adminBirthDate">
            <Input id="adminBirthDate" type="date" value={birthDate} onChange={(e) => saveBirthDate(e.target.value)} max={toDateKey(new Date())} />
          </Field>
        </div>
      </CardContent>
    </Card>
  );
}
