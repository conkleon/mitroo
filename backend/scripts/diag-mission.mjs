import { PrismaClient } from "@prisma/client";

const missionIds = process.argv.slice(2).map(Number).filter(Boolean);
if (!missionIds.length) { console.log("Usage: node diag-mission.mjs <id1> <id2> ..."); process.exit(1); }
const p = new PrismaClient();

async function main() {
  const { diagMissionHours } = await import("../dist/lib/mitrooSync.js");

  for (const missionId of missionIds) {
    const svc = await p.service.findFirst({
      where: { externalMissionId: missionId },
      select: { id: true, departmentId: true, name: true, lifecycleStatus: true, serviceType: { select: { externalMissionTypeId: true } } },
    });
    if (!svc) { console.log(`MISSION ${missionId}: NOT FOUND locally`); continue; }
    const typeId = svc.serviceType?.externalMissionTypeId ?? "?";
    console.log(`\nMISSION ${missionId} (type=${typeId} ${svc.lifecycleStatus}): "${svc.name.slice(0, 60)}"`);

    const diag = await diagMissionHours(svc.departmentId, missionId);
    let anyMismatch = false;

    for (const s of diag.shifts) {
      let hSan = 0, hVol = 0, hTrain = 0, hRetrain = 0, hTep = 0;
      for (const a of s.htmlApps) { hSan += a.san; hVol += a.vol; hTrain += a.training; hRetrain += a.retraining; hTep += a.tep; }
      const htmlTotal = hSan + hVol + hTrain + hRetrain + hTep;

      let lSan = 0, lVol = 0, lTrain = 0, lRetrain = 0, lTep = 0;
      for (const u of s.localUserServices) { lSan += u.hours; lVol += u.hoursVol; lTrain += u.hoursTraining; lRetrain += u.hoursTrainers; lTep += u.hoursTEP; }
      const localTotal = lSan + lVol + lTrain + lRetrain + lTep;

      const dSan = hSan - lSan, dVol = hVol - lVol, dTrain = hTrain - lTrain, dRetrain = hRetrain - lRetrain, dTep = hTep - lTep;
      const dTotal = htmlTotal - localTotal;

      if (dTotal !== 0) {
        anyMismatch = true;
        const parts = [];
        if (dSan) parts.push(`san=${dSan > 0 ? "+" + dSan : dSan}`);
        if (dVol) parts.push(`vol=${dVol > 0 ? "+" + dVol : dVol}`);
        if (dTrain) parts.push(`train=${dTrain > 0 ? "+" + dTrain : dTrain}`);
        if (dRetrain) parts.push(`retrain=${dRetrain > 0 ? "+" + dRetrain : dRetrain}`);
        if (dTep) parts.push(`tep=${dTep > 0 ? "+" + dTep : dTep}`);
        console.log(`  Δ shift ${s.externalShiftId}: HTML[${s.htmlApps.length}app ${htmlTotal}h] local[${s.localUserServices.length}usr ${localTotal}h] | ${parts.join(" ")}`);
      }

      // Per-app detail when mismatch exists
      if (dTotal !== 0 && s.htmlApps.length <= 10) {
        for (const a of s.htmlApps) {
          const isZero = a.san === 0 && a.vol === 0 && a.training === 0 && a.retraining === 0 && a.tep === 0;
          console.log(`    html member=${a.memberId} ${a.status}: san=${a.san} vol=${a.vol} train=${a.training} retrain=${a.retraining} tep=${a.tep}${isZero ? " ← ALL ZERO" : ""}`);
        }
        for (const u of s.localUserServices) {
          console.log(`    local user=${u.userId} ${u.status}: san=${u.hours} vol=${u.hoursVol} train=${u.hoursTraining} retrain=${u.hoursTrainers} tep=${u.hoursTEP}`);
        }
      }
    }
    if (!anyMismatch) console.log(`  ALL MATCH ✓`);
  }
  await p.$disconnect();
}

main().catch((e) => { console.error(e); process.exit(1); });
