import { renderMissionReportPdf } from "./missionReportPdf";
import { MissionReportData } from "./missionReportData";

const SAMPLE_DATA: MissionReportData = {
  missions: [
    { id: 1, name: "Πλημμύρες Αττικής", departmentName: "Κεντρικό Τμήμα", location: "Αθήνα", startAt: null, endAt: null, lifecycleStatus: "completed" },
  ],
  personnel: [],
  vehicles: [],
  items: [],
  victims: [],
  totals: { personnelCount: 0, totalHours: 0, vehicleCount: 0, itemCount: 0, victimCount: 0 },
};

describe("renderMissionReportPdf", () => {
  it("produces a valid, non-empty PDF buffer", async () => {
    const buffer = await renderMissionReportPdf(SAMPLE_DATA, "Δοκιμαστικό κείμενο δελτίου τύπου.");

    expect(Buffer.isBuffer(buffer)).toBe(true);
    expect(buffer.length).toBeGreaterThan(100);
    expect(buffer.subarray(0, 5).toString("latin1")).toBe("%PDF-");
  });
});
