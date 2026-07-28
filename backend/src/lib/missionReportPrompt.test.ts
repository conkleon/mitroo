// backend/src/lib/missionReportPrompt.test.ts
import { buildPressReleasePrompt } from "./missionReportPrompt";
import { MissionReportData } from "./missionReportData";

const SAMPLE_DATA: MissionReportData = {
  missions: [
    {
      id: 1,
      name: "Πλημμύρες Αττικής",
      departmentName: "Κεντρικό Τμήμα",
      location: "Αθήνα",
      startAt: "2026-06-01T08:00:00.000Z",
      endAt: "2026-06-02T20:00:00.000Z",
      lifecycleStatus: "completed",
    },
  ],
  personnel: [
    { userId: 1, fullName: "Γιώργος Παπαδόπουλος", rank: "Α", status: "accepted", hours: 12 },
  ],
  vehicles: [
    {
      vehicleId: 1,
      vehicleName: "Ασθενοφόρο 1",
      driverFullName: "Μαρία Ιωάννου",
      meterType: "km",
      startAt: "2026-06-01T08:00:00.000Z",
      endAt: "2026-06-01T18:00:00.000Z",
      distance: 45,
      destination: "Νοσοκομείο ΚΑΤ",
    },
  ],
  items: [
    { itemName: "Φορείο", userFullName: "Γιώργος Παπαδόπουλος", assignedAt: "2026-06-01T08:00:00.000Z", comment: null },
  ],
  victims: [
    { id: 1, chiefComplaint: "Κάταγμα άκρου", medicalHistory: null, notes: null, isFinalized: true },
  ],
  totals: { personnelCount: 1, totalHours: 12, vehicleCount: 1, itemCount: 1, victimCount: 1 },
};

describe("buildPressReleasePrompt", () => {
  it("includes mission names, aggregate counts, and asks for a Greek press release", () => {
    const prompt = buildPressReleasePrompt(SAMPLE_DATA, [
      { chiefComplaint: "Κάταγμα άκρου", medicalHistory: null, notes: null },
    ]);

    expect(prompt).toContain("Πλημμύρες Αττικής");
    expect(prompt).toContain("Κεντρικό Τμήμα");
    expect(prompt).toContain("1 άτομα προσωπικού");
    expect(prompt).toContain("1 οχήματα");
    expect(prompt).toContain("1 τραυματίες");
    expect(prompt).toContain("Κάταγμα άκρου");
    expect(prompt).toContain("ΔΕΛΤΙΟ ΤΥΠΟΥ");
  });

  it("omits victim section text when there are no victims", () => {
    const prompt = buildPressReleasePrompt({ ...SAMPLE_DATA, victims: [], totals: { ...SAMPLE_DATA.totals, victimCount: 0 } }, []);
    expect(prompt).toContain("0 τραυματίες");
    expect(prompt).not.toContain("Κάταγμα άκρου");
  });
});
