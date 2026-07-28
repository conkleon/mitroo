import { MissionReportData } from "./missionReportData";
import { VictimNarrativeInput } from "./missionReportAnonymize";

export function buildPressReleasePrompt(
  data: MissionReportData,
  anonymizedVictims: VictimNarrativeInput[],
): string {
  const missionLines = data.missions
    .map((m) => `- ${m.name} (${m.departmentName}), ${m.startAt ?? "άγνωστη ημερομηνία"} έως ${m.endAt ?? "εν εξελίξει"}`)
    .join("\n");

  const victimLines = anonymizedVictims
    .map((v) => [v.chiefComplaint, v.medicalHistory, v.notes].filter(Boolean).join(" — "))
    .filter((line) => line.length > 0)
    .map((line) => `- ${line}`)
    .join("\n");

  return [
    "Είσαι υπεύθυνος επικοινωνίας ενός οργανισμού διάσωσης και παρέχεις υπηρεσίες έκτακτης ανάγκης.",
    "Με βάση τα παρακάτω στοιχεία, συνέταξε ένα επίσημο ΔΕΛΤΙΟ ΤΥΠΟΥ στα ελληνικά, σε μορφή ενιαίας παραγράφου ή δύο σύντομων παραγράφων, κατάλληλο για δημόσια ανακοίνωση.",
    "",
    "Αποστολές:",
    missionLines,
    "",
    `Σύνολα: ${data.totals.personnelCount} άτομα προσωπικού, ${data.totals.totalHours} συνολικές ώρες, ${data.totals.vehicleCount} οχήματα, ${data.totals.itemCount} τεμάχια υλικού, ${data.totals.victimCount} τραυματίες/διασωθέντες.`,
    "",
    ...(victimLines
      ? ["Σύνοψη περιστατικών (χωρίς προσωπικά στοιχεία):", victimLines, ""]
      : []),
    "Γράψε το κείμενο σε επίσημο, αντικειμενικό ύφος, χωρίς να αναφέρεις ονόματα ή προσωπικά στοιχεία διασωθέντων.",
  ].join("\n");
}
