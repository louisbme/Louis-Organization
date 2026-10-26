"use client";

import * as React from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { toast } from "sonner";
import { Trash2, Pencil } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { deleteSession, updateSessionNotes } from "@/lib/services/sessions";
import { friendlyError } from "@/lib/utils/errors";
import { Button } from "@/components/ui/button";
import { Sheet } from "@/components/ui/sheet";
import { Textarea } from "@/components/ui/input";

export function SessionActions({ sessionId, notes, backHref = "/history" }: { sessionId: string; notes: string | null; backHref?: string }) {
  const router = useRouter();
  const params = useSearchParams();
  const [confirm, setConfirm] = React.useState(false);
  const [editNotes, setEditNotes] = React.useState(false);
  const [value, setValue] = React.useState(notes ?? "");
  const [busy, setBusy] = React.useState(false);

  React.useEffect(() => {
    if (params.get("done") === "1") {
      toast.success("Training abgeschlossen");
      router.replace(`/history/${sessionId}`);
    }
  }, [params, router, sessionId]);

  const remove = async () => {
    setBusy(true);
    try {
      await deleteSession(createClient(), sessionId);
      toast.success("Training gelöscht");
      router.push(backHref);
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
      setBusy(false);
    }
  };

  const saveNotes = async () => {
    setBusy(true);
    try {
      await updateSessionNotes(createClient(), sessionId, value.trim() || null);
      setEditNotes(false);
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="flex gap-2">
      <Button variant="secondary" onClick={() => setEditNotes(true)} fullWidth>
        <Pencil className="h-4 w-4" /> Notiz
      </Button>
      <Button variant="danger" onClick={() => setConfirm(true)}>
        <Trash2 className="h-4 w-4" /> Löschen
      </Button>
      <Sheet open={editNotes} onClose={() => setEditNotes(false)} title="Notiz" footer={<Button fullWidth onClick={saveNotes} loading={busy}>Speichern</Button>}>
        <Textarea value={value} onChange={(e) => setValue(e.target.value)} maxLength={500} rows={4} />
      </Sheet>
      <Sheet
        open={confirm}
        onClose={() => setConfirm(false)}
        title="Training löschen?"
        description="Alle Sätze dieses Trainings werden dauerhaft entfernt."
        footer={
          <div className="flex gap-2">
            <Button variant="secondary" fullWidth onClick={() => setConfirm(false)}>Abbrechen</Button>
            <Button variant="danger" fullWidth onClick={remove} loading={busy}>Löschen</Button>
          </div>
        }
      >
        <div />
      </Sheet>
    </div>
  );
}
