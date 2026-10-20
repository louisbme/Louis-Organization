"use client";

import * as React from "react";
import type { ProfileRow, UserSettingsRow } from "@/lib/supabase/types";

export interface UserContextValue {
  userId: string;
  email: string;
  profile: ProfileRow;
  settings: UserSettingsRow;
}

const UserContext = React.createContext<UserContextValue | null>(null);

export function UserProvider({ value, children }: { value: UserContextValue; children: React.ReactNode }) {
  return <UserContext.Provider value={value}>{children}</UserContext.Provider>;
}

export function useUser(): UserContextValue {
  const ctx = React.useContext(UserContext);
  if (!ctx) throw new Error("useUser muss innerhalb von UserProvider verwendet werden");
  return ctx;
}
