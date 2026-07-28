import PDFDocument from "pdfkit";
import { MissionReportData } from "./missionReportData";

export function renderMissionReportPdf(data: MissionReportData, narrativeText: string): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ margin: 50 });
    const chunks: Buffer[] = [];
    doc.on("data", (chunk) => chunks.push(chunk));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);

    doc.fontSize(18).text("Αναφορά Αποστολής", { align: "center" });
    doc.moveDown(1.5);

    doc.fontSize(14).text("ΔΕΛΤΙΟ ΤΥΠΟΥ");
    doc.moveDown(0.5);
    doc.fontSize(11).text(narrativeText, { align: "justify" });
    doc.moveDown(1.5);

    doc.fontSize(14).text("Αποστολές");
    doc.moveDown(0.5);
    data.missions.forEach((m) => {
      doc.fontSize(11).text(`${m.name} — ${m.departmentName} (${m.startAt ?? "-"} έως ${m.endAt ?? "-"})`);
    });
    doc.moveDown(1);

    doc.fontSize(14).text("Προσωπικό");
    doc.moveDown(0.5);
    if (data.personnel.length === 0) {
      doc.fontSize(11).text("Δεν καταχωρήθηκε προσωπικό.");
    }
    data.personnel.forEach((p) => {
      doc.fontSize(11).text(`${p.fullName} (${p.rank}) — ${p.status} — ${p.hours} ώρες`);
    });
    doc.moveDown(1);

    doc.fontSize(14).text("Οχήματα");
    doc.moveDown(0.5);
    if (data.vehicles.length === 0) {
      doc.fontSize(11).text("Δεν καταχωρήθηκε χρήση οχημάτων.");
    }
    data.vehicles.forEach((v) => {
      doc.fontSize(11).text(`${v.vehicleName} — οδηγός: ${v.driverFullName} — ${v.distance ?? "-"} ${v.meterType}`);
    });
    doc.moveDown(1);

    doc.fontSize(14).text("Υλικό");
    doc.moveDown(0.5);
    if (data.items.length === 0) {
      doc.fontSize(11).text("Δεν καταχωρήθηκε χρήση υλικού.");
    }
    data.items.forEach((i) => {
      doc.fontSize(11).text(`${i.itemName} — ${i.userFullName}`);
    });
    doc.moveDown(1);

    doc.fontSize(14).text("Διασωθέντες / Τραυματίες");
    doc.moveDown(0.5);
    doc.fontSize(11).text(`Σύνολο: ${data.totals.victimCount}`);

    doc.end();
  });
}
