"use client";

import * as React from "react";
import { toast } from "sonner";
import { createClient } from "@/lib/supabase/client";
import { useUser } from "@/lib/context/user-context";
import { listExercises, type ExerciseListItem } from "@/lib/services/exercises";
import { friendlyError } from "@/lib/utils/errors";
import { Sheet } from "@/components/ui/sheet";
import { LoadingBlock } from "@/components/ui/states";
import { ExerciseBrowser } from "@/components/exercise/exercise-browser";

interface ExercisePickerSheetProps {
  open: boolean;
  onClose: () => void;
  onPick: (item: ExerciseListItem) => void;
  title?: string;
  excludeIds?: string[];
}

export function ExercisePickerSheet({ open, onClose, onPick, title = "Übung auswählen", excludeIds = [] }: ExercisePickerSheetProps) {
  const { userId } = useUser();
  const [items, setItems] = React.useState<ExerciseListItem[] | null>(null);

  React.useEffect(() => {
    if (!open || items) return;
    const db = createClient();
    listExercises(db, userId)
      .then(setItems)
      .catch((e) => toast.error(friendlyError(e)));
  }, [open, items, userId]);

  const visible = React.useMemo(() => (items ?? []).filter((i) => !excludeIds.includes(i.id)), [items, excludeIds]);

  return (
    <Sheet open={open} onClose={onClose} title={title} size="lg">
      {items === null ? (
        <LoadingBlock label="Übungen laden …" />
      ) : (
        <ExerciseBrowser items={visible} mode="pick" onPick={onPick} showCreateLink={false} />
      )}
    </Sheet>
  );
}
