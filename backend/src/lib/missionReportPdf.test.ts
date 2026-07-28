import pdfParse from "pdf-parse";
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

const NARRATIVE = "Δοκιμαστικό κείμενο δελτίου τύπου.";

async function extractText(buffer: Buffer): Promise<string> {
  const parsed = await pdfParse(buffer);
  return parsed.text;
}

describe("renderMissionReportPdf", () => {
  it("produces a valid, non-empty PDF buffer", async () => {
    const buffer = await renderMissionReportPdf(SAMPLE_DATA, NARRATIVE);

    expect(Buffer.isBuffer(buffer)).toBe(true);
    expect(buffer.length).toBeGreaterThan(100);
    expect(buffer.subarray(0, 5).toString("latin1")).toBe("%PDF-");
  });

  // Round-trip check: a Helvetica-only (WinAnsi) document renders Greek as mojibake,
  // which still yields a structurally valid PDF. Extracting the text back out is the
  // only way to prove the Greek glyphs actually survived into the document.
  it("round-trips Greek text through the rendered PDF", async () => {
    const buffer = await renderMissionReportPdf(SAMPLE_DATA, NARRATIVE);
    const text = await extractText(buffer);

    // Title, section headers, mission data and the narrative must all be readable Greek.
    expect(text).toContain("Αναφορά Αποστολής");
    expect(text).toContain("ΔΕΛΤΙΟ ΤΥΠΟΥ");
    expect(text).toContain("Αποστολές");
    expect(text).toContain("Πλημμύρες Αττικής");
    expect(text).toContain("Κεντρικό Τμήμα");
    expect(text).toContain(NARRATIVE);
  }, 30000);
});
