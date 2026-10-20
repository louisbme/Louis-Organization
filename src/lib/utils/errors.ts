/** Übersetzt technische Fehlermeldungen in verständliche Hinweise. */
export function friendlyError(error: unknown, fallback = "Etwas ist schiefgelaufen. Bitte erneut versuchen."): string {
  const message =
    typeof error === "string"
      ? error
      : error && typeof error === "object" && "message" in error && typeof (error as { message: unknown }).message === "string"
        ? (error as { message: string }).message
        : "";

  const m = message.toLowerCase();
  if (!m) return fallback;
  if (m.includes("failed to fetch") || m.includes("network") || m.includes("fetch failed")) {
    return "Keine Verbindung. Bitte Internetverbindung prüfen.";
  }
  if (m.includes("invalid login credentials")) return "E-Mail oder Passwort ist falsch.";
  if (m.includes("email not confirmed")) return "Bitte zuerst die E-Mail-Adresse bestätigen.";
  if (m.includes("user already registered") || m.includes("already been registered")) {
    return "Für diese E-Mail existiert bereits ein Konto.";
  }
  if (m.includes("password should be at least")) return "Das Passwort muss mindestens 8 Zeichen lang sein.";
  if (m.includes("rate limit") || m.includes("too many requests")) {
    return "Zu viele Versuche. Bitte kurz warten.";
  }
  if (m.includes("jwt") || m.includes("not authenticated") || m.includes("nicht angemeldet")) {
    return "Sitzung abgelaufen. Bitte erneut anmelden.";
  }
  if (m.includes("duplicate key") || m.includes("unique")) return "Dieser Eintrag existiert bereits.";
  if (m.includes("violates foreign key") && m.includes("workout_session_exercises")) {
    return "Diese Übung wurde bereits in Trainings verwendet und kann nicht gelöscht werden.";
  }
  if (m.includes("keine berechtigung")) return "Keine Berechtigung für diese Aktion.";
  if (m.includes("eigene admin-rolle")) return "Die eigene Admin-Rolle kann nicht entfernt werden.";
  if (m.includes("eigene konto")) return "Das eigene Konto kann hier nicht gelöscht werden.";
  if (m.includes("row-level security") || m.includes("permission denied")) {
    return "Keine Berechtigung für diese Aktion.";
  }
  if (m.includes("new password should be different")) return "Das neue Passwort muss sich vom alten unterscheiden.";
  if (m.includes("same_password")) return "Das neue Passwort muss sich vom alten unterscheiden.";
  return fallback;
}
