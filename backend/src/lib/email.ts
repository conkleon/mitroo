import nodemailer from "nodemailer";

const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || "localhost",
  port: parseInt(process.env.SMTP_PORT || "587", 10),
  secure: process.env.SMTP_SECURE === "true",
  auth: {
    user: process.env.SMTP_USER || "",
    pass: process.env.SMTP_PASS || "",
  },
});

const FROM = process.env.SMTP_FROM || "Mitroo <noreply@mitroo.local>";
const APP_NAME = process.env.APP_NAME || "Mitroo";
const FRONTEND_URL = process.env.FRONTEND_URL || "http://localhost:8079";

export async function sendPasswordResetEmail(to: string, token: string, forename: string) {
  const resetLink = `${FRONTEND_URL}/reset-password?token=${encodeURIComponent(token)}`;
  await transporter.sendMail({
    from: FROM,
    to,
    subject: `${APP_NAME} – Επαναφορά κωδικού`,
    html: `
      <div style="font-family:sans-serif;max-width:500px;margin:auto;padding:24px">
        <h2 style="color:#DC2626">Επαναφορά Κωδικού</h2>
        <p>Γεια σου <strong>${forename}</strong>,</p>
        <p>Ζητήθηκε επαναφορά του κωδικού πρόσβασης του λογαριασμού σου στο ${APP_NAME}.</p>
        <p>Πάτησε τον παρακάτω σύνδεσμο μέσα σε <strong>1 ώρα</strong>:</p>
        <p style="text-align:center;margin:24px 0">
          <a href="${resetLink}"
             style="background:#DC2626;color:#fff;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:600">
            Αλλαγή κωδικού
          </a>
        </p>
        <p style="font-size:12px;color:#6B7280">Αν δεν ζήτησες εσύ αυτή την αλλαγή, αγνόησε αυτό το email.</p>
      </div>
    `,
  });
}

export async function sendInviteEmail(to: string, forename: string, password: string) {
  const loginLink = `${FRONTEND_URL}/login`;
  await transporter.sendMail({
    from: FROM,
    to,
    subject: `${APP_NAME} – Πρόσκληση στην πλατφόρμα`,
    html: `
      <div style="font-family:sans-serif;max-width:500px;margin:auto;padding:24px">
        <h2 style="color:#DC2626">Καλωσήρθες στο ${APP_NAME}!</h2>
        <p>Γεια σου <strong>${forename}</strong>,</p>
        <p>Δημιουργήθηκε λογαριασμός για εσένα στο ${APP_NAME}.</p>
        <p>Τα στοιχεία σύνδεσής σου:</p>
        <table style="border-collapse:collapse;margin:16px 0;font-size:14px">
          <tr><td style="padding:6px 12px;font-weight:600">Email:</td><td style="padding:6px 12px">${to}</td></tr>
          <tr><td style="padding:6px 12px;font-weight:600">Κωδικός:</td><td style="padding:6px 12px;font-family:monospace;background:#F3F4F6;border-radius:4px">${password}</td></tr>
        </table>
        <p>Σε παρακαλούμε <strong>άλλαξε τον κωδικό σου</strong> μετά την πρώτη σύνδεση.</p>
        <p style="text-align:center;margin:24px 0">
          <a href="${loginLink}"
             style="background:#DC2626;color:#fff;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:600">
            Σύνδεση
          </a>
        </p>
      </div>
    `,
  });
}
