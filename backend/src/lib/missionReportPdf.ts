import PDFDocument from "pdfkit";
import { MissionReportData } from "./missionReportData";

// pdfkit's built-in fonts (Helvetica & co.) are WinAnsi-encoded and have no Greek
// glyphs, so every Greek string would render as mojibake. DejaVu Sans is a Unicode
// TTF with full Greek + Latin coverage; resolve it through the module resolver so
// the path is correct regardless of the process cwd.
const BODY_FONT_PATH = require.resolve("dejavu-fonts-ttf/ttf/DejaVuSans.ttf");
const BOLD_FONT_PATH = require.resolve("dejavu-fonts-ttf/ttf/DejaVuSans-Bold.ttf");

export function renderMissionReportPdf(data: MissionReportData, narrativeText: string): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ margin: 50 });
    const chunks: Buffer[] = [];
    doc.on("data", (chunk) => chunks.push(chunk));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);

    // Register + select the Unicode font BEFORE any .text() call.
    doc.registerFont("body", BODY_FONT_PATH);
    doc.registerFont("bold", BOLD_FONT_PATH);
    doc.font("body");

    doc.font("bold").fontSize(18).text("Αναφορά Αποστολής", { align: "center" });
    doc.moveDown(1.5);

    doc.font("bold").fontSize(14).text("ΔΕΛΤΙΟ ΤΥΠΟΥ");
    doc.moveDown(0.5);
    doc.font("body").fontSize(11).text(narrativeText, { align: "justify" });
    doc.moveDown(1.5);

    doc.font("bold").fontSize(14).text("Αποστολές");
    doc.moveDown(0.5);
    data.missions.forEach((m) => {
      doc.font("body").fontSize(11).text(`${m.name} — ${m.departmentName} (${m.startAt ?? "-"} έως ${m.endAt ?? "-"})`);
    });
    doc.moveDown(1);

    doc.font("bold").fontSize(14).text("Προσωπικό");
    doc.moveDown(0.5);
    if (data.personnel.length === 0) {
      doc.font("body").fontSize(11).text("Δεν καταχωρήθηκε προσωπικό.");
    }
    data.personnel.forEach((p) => {
      doc.font("body").fontSize(11).text(`${p.fullName} (${p.rank}) — ${p.status} — ${p.hours} ώρες`);
    });
    doc.moveDown(1);

    doc.font("bold").fontSize(14).text("Οχήματα");
    doc.moveDown(0.5);
    if (data.vehicles.length === 0) {
      doc.font("body").fontSize(11).text("Δεν καταχωρήθηκε χρήση οχημάτων.");
    }
    data.vehicles.forEach((v) => {
      doc.font("body").fontSize(11).text(`${v.vehicleName} — οδηγός: ${v.driverFullName} — ${v.distance ?? "-"} ${v.meterType}`);
    });
    doc.moveDown(1);

    doc.font("bold").fontSize(14).text("Υλικό");
    doc.moveDown(0.5);
    if (data.items.length === 0) {
      doc.font("body").fontSize(11).text("Δεν καταχωρήθηκε χρήση υλικού.");
    }
    data.items.forEach((i) => {
      doc.font("body").fontSize(11).text(`${i.itemName} — ${i.userFullName}`);
    });
    doc.moveDown(1);

    doc.font("bold").fontSize(14).text("Διασωθέντες / Τραυματίες");
    doc.moveDown(0.5);
    doc.font("body").fontSize(11).text(`Σύνολο: ${data.totals.victimCount}`);

    doc.end();
  });
}
