import crypto from "crypto";
import bcrypt from "bcryptjs";
import prisma from "./prisma";
import { encrypt, decrypt } from "./encryption";
import { MitrooClient, ExternalMission, ExternalShift, ExternalShiftMember } from "./mitrooClient";

const EXTERNAL_BASE_URL =
  process.env.MITROO_EXTERNAL_BASE_URL ?? "https://mitroo.redcross.gr";

const TRAINER_MISSION_TYPE_IDS = new Set([71, 36, 86, 33, 83]);
const TRAINING_MISSION_TYPE_IDS = new Set([81]);
const TEP_MISSION_TYPE_IDS = new Set([85]);
const VOLUNTEER_MISSION_TYPE_IDS = new Set([56, 57]);
const SANITARY_MISSION_TYPE_IDS = new Set([60, 16]);

// Strip "Σαβ 16-05-2026 11:00-16:00, " prefix embedded in service names from original Mitroo
const SERVICE_NAME_TIMESTAMP_RE =
  /^(Δευ|Τρι|Τετ|Πεμ|Παρ|Σαβ|Κυρ)\s+\d{2}-\d{2}-\d{4}\s+\d{2}:\d{2}-\d{2}:\d{2},\s*/;

function cleanServiceName(raw: string): string {
  return raw.replace(SERVICE_NAME_TIMESTAMP_RE, "").trim();
}

let _serviceTypeIdMap: Map<number, number> | null = null;

async function getServiceTypeIdMap(): Promise<Map<number, number>> {
  if (_serviceTypeIdMap) return _serviceTypeIdMap;
  const types = await prisma.serviceType.findMany({
    where: { externalMissionTypeId: { not: null } },
    select: { id: true, externalMissionTypeId: true },
  });
  _serviceTypeIdMap = new Map();
  for (const t of types) {
    if (t.externalMissionTypeId != null) {
      _serviceTypeIdMap.set(t.externalMissionTypeId, t.id);
    }
  }
  return _serviceTypeIdMap;
}

function lookupServiceTypeId(map: Map<number, number>, missionTypeId: unknown): number | null {
  const id = Number(missionTypeId);
  if (!Number.isFinite(id)) return null;
  return map.get(id) ?? null;
}

function mapMissionStatus(statusId: unknown): 'active' | 'closed' | 'completed' | 'finalized' {
  const id = Number(statusId);
  if (id === 3) return 'closed';
  if (id === 4) return 'completed';
  if (id === 9) return 'finalized';
  return 'active';
}

// The external Mitroo system stores datetimes in Europe/Athens local time without a
// timezone indicator. These helpers convert between Athens local strings and UTC Dates.

function getAthensOffsetMinutes(date: Date): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Europe/Athens",
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
    hour12: false,
  }).formatToParts(date);
  const get = (type: string) => parseInt(parts.find((p) => p.type === type)?.value ?? "0", 10);
  const athensMs = Date.UTC(get("year"), get("month") - 1, get("day"), get("hour") % 24, get("minute"), get("second"));
  return Math.round((athensMs - date.getTime()) / 60000);
}

function parseAthensDatetime(raw: string | undefined): Date | undefined {
  if (!raw) return undefined;
  const naive = new Date(raw.trim().replace(" ", "T") + "Z");
  if (isNaN(naive.getTime())) return undefined;
  return new Date(naive.getTime() - getAthensOffsetMinutes(naive) * 60000);
}

function formatAthensDate(d: Date | null | undefined): string {
  if (!d) return "";
  const shifted = new Date(d.getTime() + getAthensOffsetMinutes(d) * 60000);
  return shifted.toISOString().slice(0, 10);
}

function formatAthensDatetime(d: Date | null | undefined): string {
  if (!d) return "";
  const shifted = new Date(d.getTime() + getAthensOffsetMinutes(d) * 60000);
  return shifted.toISOString().slice(0, 16).replace("T", " ");
}

export interface SyncResult {
  created: number;
  updated: number;
  errors: string[];
}

// Status IDs in original Mitroo:
//   1 = ΑΡΧΙΚΗ (pending/initial), 3 = accepted, 4 = rejected (cancelled by admin),
//   6 = ΠΑΡΟΥΣΙΑΣΤΗΚΕ (participated), 7 = ΔΕΝ ΠΑΡΟΥΣΙΑΣΤΗΚΕ (no-show → rejected).
// Any other status (e.g. cancelled-by-member) is not imported to avoid phantom "applied for" records.
const mapApplicationStatus = (statusId: unknown): "requested" | "accepted" | "rejected" | "participated" | null => {
  const id = Number(statusId);
  if (id === 1) return "requested";
  if (id === 3) return "accepted";
  if (id === 4) return "rejected";
  if (id === 6) return "participated";
  if (id === 7) return "rejected";
  return null;
};

async function getClient(departmentId: number): Promise<MitrooClient> {
  const config = await prisma.departmentSyncConfig.findUnique({
    where: { departmentId },
  });
  if (!config) throw new Error(`No sync config for department ${departmentId}`);
  const password = decrypt(config.externalPassword);
  const client = new MitrooClient(EXTERNAL_BASE_URL);
  await client.login(config.externalUsername, password);
  return client;
}

async function setSyncStatus(
  departmentId: number,
  type: "user" | "service" | "finalized",
  status: "success" | "failed",
  error?: string,
) {
  const data: Record<string, unknown> = { lastSyncStatus: status };
  if (type === "user") data.lastUserSyncAt = new Date();
  else if (type === "finalized") data.lastFinalizedSyncAt = new Date();
  else data.lastServiceSyncAt = new Date();
  if (error) data.lastSyncError = error.slice(0, 1000);
  else data.lastSyncError = null;

  await prisma.departmentSyncConfig.update({
    where: { departmentId },
    data,
  });
}

/** Safely convert external hour values to finite integers, defaulting to 0. */
const parseHours = (value: unknown) => {
  if (value == null) return 0;
  if (typeof value === "number") {
    return Number.isFinite(value) ? Math.trunc(value) : 0;
  }
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (!trimmed) return 0;
    const timeMatch = trimmed.match(/^(\d+)\s*:\s*(\d{1,2})$/);
    if (timeMatch) {
      const hours = Number(timeMatch[1]);
      const minutes = Number(timeMatch[2]);
      if (Number.isFinite(hours) && Number.isFinite(minutes)) {
        return Math.trunc(hours + minutes / 60);
      }
      return 0;
    }
    const normalized = trimmed.replace(",", ".").replace(/[^\d.\-]/g, "");
    const num = Number(normalized);
    return Number.isFinite(num) ? Math.trunc(num) : 0;
  }
  const num = Number(value);
  return Number.isFinite(num) ? Math.trunc(num) : 0;
};

type DefaultHours = {
  defaultHours: number;
  defaultHoursVol: number;
  defaultHoursTraining: number;
  defaultHoursTrainers: number;
  defaultHoursTEP: number;
};

const remapDefaultHoursByMissionType = (
  missionTypeId: unknown,
  hours: DefaultHours,
): DefaultHours => {
  const id = Number(missionTypeId);
  if (!Number.isFinite(id)) return hours;

  const total =
    hours.defaultHours +
    hours.defaultHoursVol +
    hours.defaultHoursTraining +
    hours.defaultHoursTrainers +
    hours.defaultHoursTEP;

  if (TRAINER_MISSION_TYPE_IDS.has(id)) {
    return {
      defaultHours: 0,
      defaultHoursVol: 0,
      defaultHoursTraining: 0,
      defaultHoursTrainers: total,
      defaultHoursTEP: 0,
    };
  }

  if (TRAINING_MISSION_TYPE_IDS.has(id)) {
    return {
      defaultHours: 0,
      defaultHoursVol: 0,
      defaultHoursTraining: total,
      defaultHoursTrainers: 0,
      defaultHoursTEP: 0,
    };
  }

  if (TEP_MISSION_TYPE_IDS.has(id)) {
    return {
      defaultHours: 0,
      defaultHoursVol: 0,
      defaultHoursTraining: 0,
      defaultHoursTrainers: 0,
      defaultHoursTEP: total,
    };
  }

  if (VOLUNTEER_MISSION_TYPE_IDS.has(id)) {
    return {
      defaultHours: 0,
      defaultHoursVol: total,
      defaultHoursTraining: 0,
      defaultHoursTrainers: 0,
      defaultHoursTEP: 0,
    };
  }

  if (SANITARY_MISSION_TYPE_IDS.has(id)) {
    return {
      defaultHours: total,
      defaultHoursVol: 0,
      defaultHoursTraining: 0,
      defaultHoursTrainers: 0,
      defaultHoursTEP: 0,
    };
  }

  return hours;
};

// ── HTML scraping for mission detail pages ──────────────────────────────────
// Used as a fallback for finished/finalized missions where _with_members returns
// empty and grid_get_shiftapplications doesn't include them.

interface ParsedApplication {
  applicationId: number;
  memberId: number;
  status: "requested" | "accepted" | "rejected" | "participated";
  hoursVolunteering: number;
  hoursSanitary: number;
  hoursTraining: number;
  hoursRetraining: number;
  hoursTEP: number;
}

const mapApplicationLabelToStatus = (
  label: string,
): "requested" | "accepted" | "rejected" | "participated" | null => {
  const trimmed = label.trim().toUpperCase();
  if (trimmed.startsWith("ΠΑΡΟΥΣΙΑΣΤΗΚΕ")) return "participated";
  if (trimmed.startsWith("ΟΡΙΣΤΙΚΟΠΟΙΗΜΕΝΗ")) return "participated";
  if (trimmed.startsWith("ΕΓΚΕΚΡΙΜΕΝΗ")) return "accepted";
  if (trimmed.startsWith("ΔΟΚ.") || trimmed.startsWith("ΔΟΚΙΜΗ")) return "accepted";
  if (trimmed.startsWith("ΝΕΑ") || trimmed.startsWith("ΑΡΧΙΚΗ")) return "requested";
  if (trimmed.startsWith("ΜΗ ΕΓΚΕΚΡΙΜΕΝΗ") || trimmed.startsWith("ΑΠΟΡΡΙΦΘΗΚΕ")) return "rejected";
  if (trimmed.startsWith("ΔΕΝ ΠΑΡΟΥΣΙΑΣΤΗΚΕ")) return "rejected";
  if (trimmed.startsWith("ΑΚΥΡΩΜΕΝΗ")) return "rejected";
  return null;
};

function parseApplicationsFromHtml(html: string): Map<number, ParsedApplication[]> {
  const result = new Map<number, ParsedApplication[]>();

  // Find all shift_id markers and their positions
  const shiftMarkers: { shiftId: number; pos: number }[] = [];
  const shiftRe = /data-shift_id\s*=\s*["'](\d+)["']/gi;
  let shiftMatch: RegExpExecArray | null;
  while ((shiftMatch = shiftRe.exec(html)) !== null) {
    shiftMarkers.push({ shiftId: Number(shiftMatch[1]), pos: shiftMatch.index });
  }

  // Find all application rows
  const appRowRe = /<tr[^>]*id="shift_application_item_(\d+)"[^>]*>([\s\S]*?)<\/tr>/gi;
  let appMatch: RegExpExecArray | null;
  let appRowCount = 0;
  let skippedNoShiftId = 0;
  let skippedNoMemberId = 0;
  let skippedNoStatus = 0;
  while ((appMatch = appRowRe.exec(html)) !== null) {
    appRowCount++;
    const appId = Number(appMatch[1]);
    const rowHtml = appMatch[2];
    const rowPos = appMatch.index;

    // Find the nearest shift_id before this row
    let shiftId = 0;
    for (let i = shiftMarkers.length - 1; i >= 0; i--) {
      if (shiftMarkers[i].pos < rowPos) {
        shiftId = shiftMarkers[i].shiftId;
        break;
      }
    }
    if (!shiftId) { skippedNoShiftId++; continue; }

    // Parse member_id from data-member_id attribute
    const memberMatch = rowHtml.match(/data-member_id\s*=\s*["'](\d+)["']/i);
    if (!memberMatch) { skippedNoMemberId++; continue; }
    const memberId = Number(memberMatch[1]);

    // Parse status label from <span class='task-cat...'>
    const statusMatch = rowHtml.match(/<span[^>]*class=['"]task-cat[^'"]*['"][^>]*>([^<]*)<\/span>/i);
    if (!statusMatch) { skippedNoStatus++; continue; }
    const rawStatusText = statusMatch[1].trim();
    const status = mapApplicationLabelToStatus(rawStatusText);
    if (!status) {
      skippedNoStatus++;
      if (skippedNoStatus <= 3) {
        console.warn(`[mitrooSync] parseApplicationsFromHtml: unrecognised status label: "${rawStatusText}"`);
      }
      continue;
    }

    // Parse hours from classed <td> cells
    const extractHours = (pattern: RegExp): number => {
      const m = rowHtml.match(pattern);
      if (!m) return 0;
      const num = parseFloat(m[1]);
      return Number.isFinite(num) ? num : 0;
    };

    const hoursVolunteering = extractHours(/class="[^"]*hours_volunteering[^"]*"[^>]*>([\d.]+)<\/td>/i);
    const hoursSanitary = extractHours(/class="[^"]*hours_sanitary[^"]*"[^>]*>([\d.]+)<\/td>/i);
    const hoursTraining = extractHours(/class="[^"]*hours_training[^"]*"[^>]*>([\d.]+)<\/td>/i);
    const hoursRetraining = extractHours(/class="[^"]*hours_retraining[^"]*"[^>]*>([\d.]+)<\/td>/i);
    const hoursTEP = extractHours(/class="[^"]*hours_tep[^"]*"[^>]*>([\d.]+)<\/td>/i);

    const app: ParsedApplication = {
      applicationId: appId,
      memberId,
      status,
      hoursVolunteering,
      hoursSanitary,
      hoursTraining,
      hoursRetraining,
      hoursTEP,
    };

    if (!result.has(shiftId)) result.set(shiftId, []);
    result.get(shiftId)!.push(app);
  }

  if (result.size === 0) {
    console.warn(
      `[mitrooSync] parseApplicationsFromHtml: found ${appRowCount} app row(s), ${shiftMarkers.length} shift marker(s) ` +
      `— skipped: noShiftId=${skippedNoShiftId}, noMemberId=${skippedNoMemberId}, noStatus=${skippedNoStatus}`,
    );
  }

  return result;
}

// ── Shared batch helpers ────────────────────────────────────────────────────

async function buildServiceMap(departmentId: number): Promise<{
  byShiftId: Map<number, number>;
  byMissionId: Map<number, number>;
}> {
  const allServices = await prisma.service.findMany({
    where: { departmentId },
    select: { id: true, externalShiftId: true, externalMissionId: true },
  });
  const byShiftId = new Map<number, number>();
  const byMissionId = new Map<number, number>();
  for (const s of allServices) {
    if (s.externalShiftId != null) byShiftId.set(s.externalShiftId, s.id);
    else if (s.externalMissionId != null) byMissionId.set(s.externalMissionId, s.id);
  }
  return { byShiftId, byMissionId };
}

async function batchFetchUsers(externalIds: Set<number>): Promise<Map<number, number>> {
  if (externalIds.size === 0) return new Map();
  const users = await prisma.user.findMany({
    where: { externalId: { in: Array.from(externalIds) } },
    select: { id: true, externalId: true },
  });
  const map = new Map<number, number>();
  for (const u of users) {
    if (u.externalId != null) map.set(u.externalId, u.id);
  }
  return map;
}

// ── Sync volunteers → Users ────────────────────────────────────────────────

// Shared per-mission processing loop: fetches shifts, upserts services
// using pre-built service maps, and batch-executes DB writes.
// Returns a map of externalShiftId → serviceId for downstream application sync.
async function processMissions(
  departmentId: number,
  missions: ExternalMission[],
  client: MitrooClient,
  result: SyncResult,
): Promise<Map<number, number>> {
  const typeIdMap = await getServiceTypeIdMap();
  const { byShiftId, byMissionId } = await buildServiceMap(departmentId);
  const shiftToServiceId = new Map(byShiftId);

  const updateOps: Array<ReturnType<typeof prisma.service.update>> = [];
  const createOps: Array<ReturnType<typeof prisma.service.create>> = [];
  const createShiftIds: number[] = [];

  for (const mission of missions) {
    const missionId = Number(mission.id);
    const lifecycleStatus = mapMissionStatus(mission.mission_status_id);

    let shifts: ExternalShift[] = [];
    try {
      shifts = await client.fetchShiftsForMission(missionId);
      console.log(`[mitrooSync] processMissions: mission_id=${missionId} lifecycleStatus=${lifecycleStatus} got ${shifts.length} shift(s)`);
    } catch (e) {
      result.errors.push(`mission_id=${missionId}: failed to fetch shifts: ${e}`);
      console.error(`[mitrooSync] processMissions: mission_id=${missionId}: fetchShiftsForMission FAILED:`, e);
      continue;
    }

    if (shifts.length === 0) {
      console.warn(`[mitrooSync] processMissions: mission_id=${missionId}: no shifts — creating mission-level stub service`);
      try {
        const rawName = (mission.title as string | undefined)?.trim() || `Mission ${missionId}`;
        const name = cleanServiceName(rawName);
        const startAt = parseAthensDatetime(mission.start_date as string | undefined);
        const endAt = parseAthensDatetime(mission.end_date as string | undefined);
        const location = (mission.location_text as string | undefined)?.trim() || null;
        const serviceTypeId = lookupServiceTypeId(typeIdMap, mission.mission_type_id);
        const existingStubId = byMissionId.get(missionId);

        if (existingStubId) {
          updateOps.push(
            prisma.service.update({
              where: { id: existingStubId },
              data: { name, startAt, endAt, location, serviceTypeId, lifecycleStatus },
            }),
          );
          result.updated++;
        } else {
          createOps.push(
            prisma.service.create({
              data: {
                departmentId,
                name,
                externalMissionId: missionId,
                startAt,
                endAt,
                location,
                serviceTypeId,
                lifecycleStatus,
              },
            }),
          );
          result.created++;
        }
      } catch (e: unknown) {
        result.errors.push(`mission_id=${missionId} (stub): ${e}`);
      }
      continue;
    }

    for (const shift of shifts) {
      try {
        const externalShiftId = Number(shift.id);
        const rawName =
          (shift.name as string) ??
          (shift.title as string) ??
          (mission.title as string) ??
          `Shift ${externalShiftId}`;
        const name = cleanServiceName(rawName);

        const startAt = parseAthensDatetime(shift.shift_start_date as string | undefined);
        const endAt = parseAthensDatetime(shift.shift_end_date as string | undefined);
        const rawHours: DefaultHours = {
          defaultHours: parseHours(shift.hours_sanitary),
          defaultHoursVol: parseHours(shift.hours_volunteering),
          defaultHoursTraining: parseHours(shift.hours_training),
          defaultHoursTrainers: parseHours(shift.hours_retraining),
          defaultHoursTEP: parseHours(shift.hours_tep),
        };
        const mappedHours = remapDefaultHoursByMissionType(
          mission.mission_type_id,
          rawHours,
        );
        const {
          defaultHours,
          defaultHoursVol,
          defaultHoursTraining,
          defaultHoursTrainers,
          defaultHoursTEP,
        } = mappedHours;

        const location = (mission.location_text as string | undefined)?.trim() || null;
        const serviceTypeId = lookupServiceTypeId(typeIdMap, mission.mission_type_id);

        const existingId = byShiftId.get(externalShiftId);

        if (existingId) {
          updateOps.push(
            prisma.service.update({
              where: { id: existingId },
              data: {
                name,
                startAt,
                endAt,
                location,
                externalMissionId: missionId,
                defaultHours,
                defaultHoursVol,
                defaultHoursTraining,
                defaultHoursTrainers,
                defaultHoursTEP,
                serviceTypeId,
                lifecycleStatus,
              },
            }),
          );
          result.updated++;
        } else {
          createOps.push(
            prisma.service.create({
              data: {
                departmentId,
                name,
                externalShiftId,
                externalMissionId: missionId,
                startAt,
                endAt,
                location,
                defaultHours,
                defaultHoursVol,
                defaultHoursTraining,
                defaultHoursTrainers,
                defaultHoursTEP,
                serviceTypeId,
                lifecycleStatus,
              },
            }),
          );
          createShiftIds.push(externalShiftId);
          result.created++;
        }
      } catch (e: unknown) {
        result.errors.push(`shift_id=${shift.id}: ${e}`);
      }
    }
  }

  // Batch execute all accumulated updates
  const batchSize = 200;
  for (let i = 0; i < updateOps.length; i += batchSize) {
    await prisma.$transaction(updateOps.slice(i, i + batchSize));
  }

  // Execute creates in transaction batches to capture returned IDs
  for (let i = 0; i < createOps.length; i += batchSize) {
    const batch = createOps.slice(i, i + batchSize);
    const results = await prisma.$transaction(batch);
    for (let j = 0; j < results.length; j++) {
      const shiftIdx = i + j;
      if (shiftIdx < createShiftIds.length) {
        shiftToServiceId.set(createShiftIds[shiftIdx], results[j].id);
      }
    }
  }

  return shiftToServiceId;
}

export async function syncUsers(departmentId: number): Promise<SyncResult> {
  const result: SyncResult = { created: 0, updated: 0, errors: [] };
  try {
    const client = await getClient(departmentId);
    const volunteers = await client.fetchVolunteers();

    console.log(`[mitrooSync] syncUsers: fetched ${volunteers.length} volunteers`);
    if (volunteers.length > 0) {
      console.log("[mitrooSync] Sample volunteer fields:", Object.keys(volunteers[0]));
    }

    const externalIds = Array.from(
      new Set(
        volunteers
          .map((v) => Number(v.id))
          .filter((id) => Number.isFinite(id) && id > 0),
      ),
    );
    const eames = Array.from(
      new Set(
        volunteers
          .map((v) => (v.registration_code as string | undefined)?.trim())
          .filter((value): value is string => Boolean(value)),
      ),
    );

    const existingUsers = await prisma.user.findMany({
      where: {
        OR: [
          { externalId: { in: externalIds } },
          { eame: { in: eames } },
        ],
      },
      select: { id: true, externalId: true, eame: true },
    });

    const existingByExternalId = new Map<number, { id: number; externalId: number | null }>();
    const existingByEame = new Map<string, { id: number; externalId: number | null }>();
    for (const user of existingUsers) {
      if (user.externalId != null) {
        existingByExternalId.set(user.externalId, { id: user.id, externalId: user.externalId });
      }
      existingByEame.set(user.eame, { id: user.id, externalId: user.externalId });
    }

    const updates: Array<ReturnType<typeof prisma.user.update>> = [];
    const updatedUserIds: number[] = [];
    const createData: Array<{
      externalId: number;
      email: string;
      forename: string;
      surname: string;
      eame: string;
      password: string;
    }> = [];

    for (const v of volunteers) {
      try {
        const externalId = Number(v.id);
        if (!externalId) continue;

        const forename = (v.first_name as string) ?? "";
        const surname = (v.last_name as string) ?? "";
        const email = `ext.${externalId}@mitroo.sync`;
        const eame =
          (v.registration_code as string)?.trim() || `EXT-${externalId}`;

        const existing =
          existingByExternalId.get(externalId) ??
          existingByEame.get(eame);

        if (existing) {
          updates.push(
            prisma.user.update({
              where: { id: existing.id },
              data: {
                forename,
                surname,
                // Link the account if found by eame but externalId wasn't set yet
                ...(existing.externalId == null ? { externalId } : {}),
              },
            }),
          );
          updatedUserIds.push(existing.id);
          result.updated++;
        } else {
          const rawPassword = crypto.randomBytes(15).toString("base64url");
          const hashed = await bcrypt.hash(rawPassword, 12);
          createData.push({
            externalId,
            email,
            forename,
            surname,
            eame,
            password: hashed,
          });
        }
      } catch (e: unknown) {
        result.errors.push(`id=${v.id}: ${e}`);
      }
    }

    const batchSize = 200;
    for (let i = 0; i < updates.length; i += batchSize) {
      await prisma.$transaction(updates.slice(i, i + batchSize));
    }

    // Ensure all updated users are linked to this department
    for (let i = 0; i < updatedUserIds.length; i += batchSize) {
      const batch = updatedUserIds.slice(i, i + batchSize);
      const upserts = batch.map((uid) =>
        prisma.userDepartment.upsert({
          where: { userId_departmentId: { userId: uid, departmentId } },
          update: {},
          create: { userId: uid, departmentId, role: "volunteer" },
        }),
      );
      await prisma.$transaction(upserts);
    }

    for (let i = 0; i < createData.length; i += batchSize) {
      const batch = createData.slice(i, i + batchSize);
      const created = await prisma.user.createMany({
        data: batch,
        skipDuplicates: true,
      });
      result.created += created.count;

      const batchExternalIds = batch.map((row) => row.externalId);
      const createdUsers = await prisma.user.findMany({
        where: { externalId: { in: batchExternalIds } },
        select: { id: true },
      });
      const userDepartmentUpserts = createdUsers.map((user) =>
        prisma.userDepartment.upsert({
          where: { userId_departmentId: { userId: user.id, departmentId } },
          update: {},
          create: { userId: user.id, departmentId, role: "volunteer" },
        }),
      );
      if (userDepartmentUpserts.length) {
        await prisma.$transaction(userDepartmentUpserts);
      }
    }

    await setSyncStatus(departmentId, "user", "success");
  } catch (e: unknown) {
    const msg = String(e);
    result.errors.push(msg);
    await setSyncStatus(departmentId, "user", "failed", msg).catch(() => {});
  }
  return result;
}

// ── Application sync for completed missions via HTML scraping ────────────────

async function syncApplicationsViaHtml(
  departmentId: number,
  client: MitrooClient,
  missions: ExternalMission[],
  shiftToServiceId: Map<number, number>,
  result: SyncResult,
): Promise<void> {
  if (missions.length === 0) return;

  console.log(
    `[mitrooSync] syncApplicationsViaHtml: scraping ${missions.length} mission detail page(s)`,
  );

  for (const mission of missions) {
    const missionId = Number(mission.id);
    try {
      const html = await client.fetchMissionDetailHtml(missionId);
      const parsedAppsByShift = parseApplicationsFromHtml(html);
      if (parsedAppsByShift.size === 0) {
        // Diagnostic: check what's in the HTML
        const hasShiftMarkers = /data-shift_id/i.test(html);
        const hasAppRows = /shift_application_item/i.test(html);
        const hasTaskCat = /task-cat/i.test(html);
        console.warn(
          `[mitrooSync] syncApplicationsViaHtml: mission_id=${missionId}: HTML parsing returned 0 apps. ` +
          `HTML length=${html.length}, hasShiftMarkers=${hasShiftMarkers}, hasAppRows=${hasAppRows}, hasTaskCat=${hasTaskCat}`,
        );
        if (!hasAppRows && !hasTaskCat) {
          // Dump first 500 chars to see what we got
          console.warn(
            `[mitrooSync] syncApplicationsViaHtml: mission_id=${missionId}: HTML preview:`,
            html.slice(0, 500),
          );
        }
        continue;
      }

      const userExternalIds = new Set<number>();
      for (const apps of parsedAppsByShift.values()) {
        for (const app of apps) {
          if (app.memberId > 0) userExternalIds.add(app.memberId);
        }
      }
      const userByExternal = await batchFetchUsers(userExternalIds);

      let matchedShifts = 0;
      let unmatchedShifts = 0;
      let createdShifts = 0;
      let processedApps = 0;
      let skippedNoUser = 0;
      for (const [shiftId, apps] of parsedAppsByShift) {
        let serviceId = shiftToServiceId.get(shiftId);
        if (!serviceId) {
          // The pre-built map (from fetchShiftsForMission) didn't include this shift.
          // This happens when the API endpoint and the HTML detail page return different
          // shift IDs.  Fall back to a direct DB lookup, or create the service on the fly.
          const existing = await prisma.service.findFirst({
            where: { externalShiftId: shiftId },
            select: { id: true },
          });
          if (existing) {
            serviceId = existing.id;
            shiftToServiceId.set(shiftId, serviceId);
          } else {
            // Try to find a mission-level stub (created when fetchShiftsForMission returned empty)
            const stub = await prisma.service.findFirst({
              where: { externalMissionId: missionId, externalShiftId: null },
              select: { id: true },
            });
            if (stub) {
              await prisma.service.update({
                where: { id: stub.id },
                data: { externalShiftId: shiftId },
              });
              serviceId = stub.id;
              shiftToServiceId.set(shiftId, serviceId);
              result.updated++;
            } else {
              // Create a minimal service so we can attach applications
              try {
                const typeIdMap = await getServiceTypeIdMap();
                const rawName = (mission.title as string | undefined)?.trim() || `Mission ${missionId}`;
                const name = cleanServiceName(rawName);
                const startAt = parseAthensDatetime(mission.start_date as string | undefined);
                const endAt = parseAthensDatetime(mission.end_date as string | undefined);
                const location = (mission.location_text as string | undefined)?.trim() || null;
                const serviceTypeId = lookupServiceTypeId(typeIdMap, mission.mission_type_id);
                const lifecycleStatus = mapMissionStatus(mission.mission_status_id);

                const created = await prisma.service.create({
                  data: {
                    departmentId,
                    name,
                    externalShiftId: shiftId,
                    externalMissionId: missionId,
                    startAt,
                    endAt,
                    location,
                    serviceTypeId,
                    lifecycleStatus,
                  },
                });
                serviceId = created.id;
                shiftToServiceId.set(shiftId, serviceId);
                createdShifts++;
                result.created++;
              } catch (e: unknown) {
                unmatchedShifts++;
                console.warn(
                  `[mitrooSync] syncApplicationsViaHtml: mission_id=${missionId}: shift_id=${shiftId} ` +
                  `not in service map and failed to create: ${e}`,
                );
                continue;
              }
            }
          }
        }
        matchedShifts++;
        for (const app of apps) {
          try {
            const userId = userByExternal.get(app.memberId);
            if (!userId) { skippedNoUser++; continue; }
            await upsertUserService(
              serviceId,
              userId,
              app.status,
              app.hoursSanitary,
              app.hoursVolunteering,
              app.hoursTraining,
              app.hoursRetraining,
              app.hoursTEP,
              app.applicationId,
              result,
            );
            processedApps++;
          } catch (e: unknown) {
            result.errors.push(
              `mission=${missionId} app=${app.applicationId}: ${e}`,
            );
          }
        }
      }
      console.log(
        `[mitrooSync] syncApplicationsViaHtml: mission_id=${missionId}: ` +
        `${matchedShifts} shift(s) matched, ${unmatchedShifts} unmatched, ${createdShifts} created, ` +
        `${processedApps} app(s) upserted, ${skippedNoUser} skipped (no local user)`,
      );
    } catch (e) {
      console.warn(
        `[mitrooSync] syncApplicationsViaHtml: mission_id=${missionId}: HTML scraping failed:`,
        e,
      );
    }
  }
}

// ── Per-lifecycle-status sync functions ──────────────────────────────────────

export async function syncActiveServices(departmentId: number): Promise<SyncResult> {
  const result: SyncResult = { created: 0, updated: 0, errors: [] };
  try {
    const client = await getClient(departmentId);
    console.log("[mitrooSync] syncActiveServices: fetching open missions...");
    const missions = await client.fetchOpenMissions();
    console.log(`[mitrooSync] syncActiveServices: open=${missions.length}`);
    await processMissions(departmentId, missions, client, result);
    console.log(
      `[mitrooSync] syncActiveServices: services done — created=${result.created} updated=${result.updated} errors=${result.errors.length}`,
    );
    const appResult = await syncShiftApplications(departmentId);
    result.created += appResult.created;
    result.updated += appResult.updated;
    result.errors.push(...appResult.errors);
    await setSyncStatus(departmentId, "service", "success");
  } catch (e: unknown) {
    const msg = String(e);
    result.errors.push(msg);
    console.error("[mitrooSync] syncActiveServices: FATAL error:", e);
    await setSyncStatus(departmentId, "service", "failed", msg).catch(() => {});
  }
  return result;
}

export async function syncClosedServices(departmentId: number): Promise<SyncResult> {
  const result: SyncResult = { created: 0, updated: 0, errors: [] };
  try {
    const client = await getClient(departmentId);
    console.log("[mitrooSync] syncClosedServices: fetching closed missions...");
    const missions = await client.fetchClosedMissions();
    console.log(`[mitrooSync] syncClosedServices: closed=${missions.length}`);
    const shiftToServiceId = await processMissions(departmentId, missions, client, result);
    console.log(
      `[mitrooSync] syncClosedServices: services done — created=${result.created} updated=${result.updated} errors=${result.errors.length}`,
    );
    await syncApplicationsViaHtml(departmentId, client, missions, shiftToServiceId, result);
    await setSyncStatus(departmentId, "service", "success");
  } catch (e: unknown) {
    const msg = String(e);
    result.errors.push(msg);
    console.error("[mitrooSync] syncClosedServices: FATAL error:", e);
    await setSyncStatus(departmentId, "service", "failed", msg).catch(() => {});
  }
  return result;
}

export async function syncCompletedServices(departmentId: number): Promise<SyncResult> {
  const result: SyncResult = { created: 0, updated: 0, errors: [] };
  try {
    const client = await getClient(departmentId);
    console.log("[mitrooSync] syncCompletedServices: fetching finished missions...");
    const missions = await client.fetchFinishedMissions();
    console.log(`[mitrooSync] syncCompletedServices: finished=${missions.length}`);
    const shiftToServiceId = await processMissions(departmentId, missions, client, result);
    console.log(
      `[mitrooSync] syncCompletedServices: services done — created=${result.created} updated=${result.updated} errors=${result.errors.length}`,
    );
    await syncApplicationsViaHtml(departmentId, client, missions, shiftToServiceId, result);
    await setSyncStatus(departmentId, "service", "success");
  } catch (e: unknown) {
    const msg = String(e);
    result.errors.push(msg);
    console.error("[mitrooSync] syncCompletedServices: FATAL error:", e);
    await setSyncStatus(departmentId, "service", "failed", msg).catch(() => {});
  }
  return result;
}

// ── Composite: sync all lifecycle statuses in one call ───────────────────────

export async function syncAllServices(departmentId: number): Promise<SyncResult> {
  const result: SyncResult = { created: 0, updated: 0, errors: [] };
  try {
    const client = await getClient(departmentId);

    console.log("[mitrooSync] syncAllServices: fetching open missions...");
    const openMissions = await client.fetchOpenMissions();
    console.log(`[mitrooSync] syncAllServices: open=${openMissions.length}`);

    console.log("[mitrooSync] syncAllServices: fetching closed missions...");
    const closedMissions = await client.fetchClosedMissions();
    console.log(`[mitrooSync] syncAllServices: closed=${closedMissions.length}`);

    console.log("[mitrooSync] syncAllServices: fetching finished missions...");
    const finishedMissions = await client.fetchFinishedMissions();
    console.log(`[mitrooSync] syncAllServices: finished=${finishedMissions.length}`);

    console.log("[mitrooSync] syncAllServices: fetching finalized missions...");
    const finalizedMissions = await client.fetchFinalizedMissions();
    console.log(`[mitrooSync] syncAllServices: finalized=${finalizedMissions.length}`);

    // Process all four statuses sequentially (shared PHP session)
    await processMissions(departmentId, openMissions, client, result);
    const closedShiftMap = await processMissions(departmentId, closedMissions, client, result);
    const completedShiftMap = await processMissions(departmentId, finishedMissions, client, result);
    await processFinalizedMissions(departmentId, client, finalizedMissions, result);

    console.log(
      `[mitrooSync] syncAllServices: all services done — created=${result.created} updated=${result.updated} errors=${result.errors.length}`,
    );

    // Application sync: one bulk call covers open missions (grid_get_shiftapplications),
    // then HTML scrape for closed + completed (not covered by grid endpoint).
    // Finalized missions handle their own app sync inside processFinalizedMissions.
    const appResult = await syncShiftApplications(departmentId);
    result.created += appResult.created;
    result.updated += appResult.updated;
    result.errors.push(...appResult.errors);

    await syncApplicationsViaHtml(departmentId, client, closedMissions, closedShiftMap, result);
    await syncApplicationsViaHtml(departmentId, client, finishedMissions, completedShiftMap, result);

    console.log(
      `[mitrooSync] syncAllServices: all done — created=${result.created} updated=${result.updated} errors=${result.errors.length}`,
    );

    await setSyncStatus(departmentId, "service", "success");
  } catch (e: unknown) {
    const msg = String(e);
    result.errors.push(msg);
    console.error("[mitrooSync] syncAllServices: FATAL error:", e);
    await setSyncStatus(departmentId, "service", "failed", msg).catch(() => {});
  }
  return result;
}

// ── Process finalized missions (shared by syncFinalizedServices + syncAllServices) ─

async function processFinalizedMissions(
  departmentId: number,
  client: MitrooClient,
  missions: ExternalMission[],
  result: SyncResult,
): Promise<void> {
  if (missions.length === 0) return;

  const typeIdMap = await getServiceTypeIdMap();

  for (const mission of missions) {
    const missionId = Number(mission.id);
    const lifecycleStatus = mapMissionStatus(mission.mission_status_id);

    let shifts: ExternalShift[] = [];
    try {
      shifts = await client.fetchShiftsForMission(missionId);
    } catch (e) {
      result.errors.push(`mission_id=${missionId}: failed to fetch shifts: ${e}`);
      console.error(`[mitrooSync] processFinalizedMissions: mission_id=${missionId}: fetchShiftsForMission FAILED:`, e);
      continue;
    }

    // For finalized missions, the _with_members endpoint often returns members
    // whose application_status_id is not in the 1-7 range that mapApplicationStatus
    // recognises, so all members get silently skipped. HTML scraping always uses
    // text labels which we can map reliably. Always scrape HTML as the primary
    // source; also try _with_members as a supplement (e.g. when HTML scraping
    // finds nothing but the endpoint returns usable data).
    let membersByShift: Map<number, ExternalShiftMember[]> = new Map();
    let parsedAppsByShift: Map<number, ParsedApplication[]> = new Map();

    // Always scrape HTML for finalized missions — primary source for applications.
    // Do this regardless of whether fetchShiftsForMission returned shifts, because
    // the API and HTML may disagree on shift IDs.
    try {
      console.log(`[mitrooSync] processFinalizedMissions: mission_id=${missionId}: scraping HTML detail page`);
      const html = await client.fetchMissionDetailHtml(missionId);
      parsedAppsByShift = parseApplicationsFromHtml(html);
      if (parsedAppsByShift.size > 0) {
        let totalApps = 0;
        for (const apps of parsedAppsByShift.values()) totalApps += apps.length;
        console.log(`[mitrooSync] processFinalizedMissions: mission_id=${missionId}: scraped ${totalApps} application(s) across ${parsedAppsByShift.size} shift(s)`);
      } else {
        const hasShiftMarkers = /data-shift_id/i.test(html);
        const hasAppRows = /shift_application_item/i.test(html);
        const hasTaskCat = /task-cat/i.test(html);
        console.warn(
          `[mitrooSync] processFinalizedMissions: mission_id=${missionId}: HTML scraping found no applications. ` +
          `HTML length=${html.length}, hasShiftMarkers=${hasShiftMarkers}, hasAppRows=${hasAppRows}, hasTaskCat=${hasTaskCat}`,
        );
        if (!hasAppRows && !hasTaskCat) {
          console.warn(
            `[mitrooSync] processFinalizedMissions: mission_id=${missionId}: HTML preview:`,
            html.slice(0, 500),
          );
        }
      }
    } catch (e) {
      console.warn(`[mitrooSync] processFinalizedMissions: mission_id=${missionId}: HTML scraping failed:`, e);
    }

    // Also try _with_members as a supplement
    try {
      membersByShift = await client.fetchShiftMembersForMission(missionId);
      if (membersByShift.size > 0) {
        console.log(`[mitrooSync] processFinalizedMissions: mission_id=${missionId}: got embedded members for ${membersByShift.size} shift(s)`);
      }
    } catch (e) {
      console.warn(`[mitrooSync] processFinalizedMissions: mission_id=${missionId}: fetchShiftMembersForMission failed:`, e);
    }

    // Build a map of user external IDs to batch-fetch local users
    const userExternalIds = new Set<number>();
    for (const members of membersByShift.values()) {
      for (const m of members) {
        const uid = Number(m.member_id);
        if (uid > 0) userExternalIds.add(uid);
      }
    }
    for (const apps of parsedAppsByShift.values()) {
      for (const app of apps) {
        if (app.memberId > 0) userExternalIds.add(app.memberId);
      }
    }

    // Batch-fetch users for this mission's members
    const users = userExternalIds.size > 0
      ? await prisma.user.findMany({
          where: { externalId: { in: Array.from(userExternalIds) } },
          select: { id: true, externalId: true },
        })
      : [];
    const userByExternal = new Map<number, number>();
    for (const u of users) {
      if (u.externalId != null) userByExternal.set(u.externalId, u.id);
    }

    let missionMembersProcessed = 0;
    let missionMembersSkippedNoStatus = 0;
    let missionHtmlMatchedShifts = 0;
    let missionHtmlUnmatchedShifts = 0;
    let missionHtmlCreatedShifts = 0;
    let missionHtmlAppsProcessed = 0;
    let missionHtmlAppsSkippedNoUser = 0;
    const processedHtmlShiftIds = new Set<number>();

    if (shifts.length === 0 && parsedAppsByShift.size === 0) {
      // No API shifts and no HTML apps — create a mission-level stub for visibility
      const rawName = (mission.title as string | undefined)?.trim() || `Mission ${missionId}`;
      const name = cleanServiceName(rawName);
      const startAt = parseAthensDatetime(mission.start_date as string | undefined);
      const endAt = parseAthensDatetime(mission.end_date as string | undefined);
      const location = (mission.location_text as string | undefined)?.trim() || null;
      const serviceTypeId = lookupServiceTypeId(typeIdMap, mission.mission_type_id);

      const existingStub = await prisma.service.findFirst({
        where: { externalMissionId: missionId, externalShiftId: null },
        select: { id: true },
      });

      if (existingStub) {
        await prisma.service.update({
          where: { id: existingStub.id },
          data: { name, startAt, endAt, location, serviceTypeId, lifecycleStatus },
        });
        result.updated++;
      } else {
        await prisma.service.create({
          data: {
            departmentId,
            name,
            externalMissionId: missionId,
            startAt,
            endAt,
            location,
            serviceTypeId,
            lifecycleStatus,
          },
        });
        result.created++;
      }

      console.log(
        `[mitrooSync] processFinalizedMissions: mission_id=${missionId}: ` +
        `0 API shifts, 0 HTML apps — created stub only`,
      );
      continue;
    }

    for (const shift of shifts) {
      try {
        const externalShiftId = Number(shift.id);
        const rawName =
          (shift.name as string) ??
          (shift.title as string) ??
          (mission.title as string) ??
          `Shift ${externalShiftId}`;
        const name = cleanServiceName(rawName);

        const startAt = parseAthensDatetime(shift.shift_start_date as string | undefined);
        const endAt = parseAthensDatetime(shift.shift_end_date as string | undefined);
        const rawHours: DefaultHours = {
          defaultHours: parseHours(shift.hours_sanitary),
          defaultHoursVol: parseHours(shift.hours_volunteering),
          defaultHoursTraining: parseHours(shift.hours_training),
          defaultHoursTrainers: parseHours(shift.hours_retraining),
          defaultHoursTEP: parseHours(shift.hours_tep),
        };
        const mappedHours = remapDefaultHoursByMissionType(
          mission.mission_type_id,
          rawHours,
        );
        const {
          defaultHours,
          defaultHoursVol,
          defaultHoursTraining,
          defaultHoursTrainers,
          defaultHoursTEP,
        } = mappedHours;

        const existing = await prisma.service.findFirst({
          where: { externalShiftId },
          select: { id: true },
        });

        const location = (mission.location_text as string | undefined)?.trim() || null;
        const serviceTypeId = lookupServiceTypeId(typeIdMap, mission.mission_type_id);

        let serviceId: number;
        if (existing) {
          serviceId = existing.id;
          await prisma.service.update({
            where: { id: existing.id },
            data: {
              name,
              startAt,
              endAt,
              location,
              externalMissionId: missionId,
              defaultHours,
              defaultHoursVol,
              defaultHoursTraining,
              defaultHoursTrainers,
              defaultHoursTEP,
              serviceTypeId,
              lifecycleStatus,
            },
          });
          result.updated++;
        } else {
          const created = await prisma.service.create({
            data: {
              departmentId,
              name,
              externalShiftId,
              externalMissionId: missionId,
              startAt,
              endAt,
              location,
              defaultHours,
              defaultHoursVol,
              defaultHoursTraining,
              defaultHoursTrainers,
              defaultHoursTEP,
              serviceTypeId,
              lifecycleStatus,
            },
          });
          serviceId = created.id;
          result.created++;
        }

        // Process embedded members for this shift (_with_members endpoint)
        const embeddedMembers = membersByShift.get(externalShiftId);
        if (embeddedMembers) {
          for (const member of embeddedMembers) {
            try {
              const externalUserId = Number(member.member_id);
              const externalApplicationId = Number(member.id);
              if (!externalUserId || !externalApplicationId) continue;

              const userId = userByExternal.get(externalUserId);
              if (!userId) continue;

              const status = mapApplicationStatus(member.application_status_id);
              if (status === null) { missionMembersSkippedNoStatus++; continue; }

              const hours = parseHours(member.hours_sanitary);
              const hoursVol = parseHours(member.hours_volunteering);
              const hoursTraining = parseHours(member.hours_training);
              const hoursTrainers = parseHours(member.hours_retraining);
              const hoursTEP = parseHours(member.hours_tep);

              await upsertUserService(
                serviceId, userId, status,
                hours, hoursVol, hoursTraining, hoursTrainers, hoursTEP,
                externalApplicationId, result,
              );
              missionMembersProcessed++;
            } catch (e: unknown) {
              result.errors.push(`member_id=${member.member_id} shift_id=${externalShiftId}: ${e}`);
            }
          }
        }

        // Process scraped HTML applications for this shift (primary source for finalized)
        const parsedApps = parsedAppsByShift.get(externalShiftId);
        if (parsedApps) {
          missionHtmlMatchedShifts++;
          processedHtmlShiftIds.add(externalShiftId);
          for (const app of parsedApps) {
            try {
              const userId = userByExternal.get(app.memberId);
              if (!userId) { missionHtmlAppsSkippedNoUser++; continue; }

              await upsertUserService(
                serviceId, userId, app.status,
                app.hoursSanitary, app.hoursVolunteering, app.hoursTraining,
                app.hoursRetraining, app.hoursTEP,
                app.applicationId, result,
              );
              missionHtmlAppsProcessed++;
            } catch (e: unknown) {
              result.errors.push(`html_app member_id=${app.memberId} shift_id=${externalShiftId}: ${e}`);
            }
          }
        } else if (parsedAppsByShift.size > 0) {
          missionHtmlUnmatchedShifts++;
          console.warn(
            `[mitrooSync] processFinalizedMissions: mission_id=${missionId}: shift_id=${externalShiftId} not found in HTML apps ` +
            `(HTML has shift IDs: ${[...parsedAppsByShift.keys()].join(',')})`,
          );
        }
      } catch (e: unknown) {
        result.errors.push(`shift_id=${shift.id}: ${e}`);
        console.error(`[mitrooSync] processFinalizedMissions: shift_id=${shift.id}: ERROR:`, e);
      }
    }

    // Process any HTML-scraped shift IDs that weren't matched to an API shift.
    // This handles the case where fetchShiftsForMission and the HTML detail page
    // return different shift IDs for the same mission.
    for (const [htmlShiftId, apps] of parsedAppsByShift) {
      if (processedHtmlShiftIds.has(htmlShiftId)) continue;

      const existing = await prisma.service.findFirst({
        where: { externalShiftId: htmlShiftId },
        select: { id: true },
      });
      let svcId: number;
      if (existing) {
        svcId = existing.id;
      } else {
        const stub = await prisma.service.findFirst({
          where: { externalMissionId: missionId, externalShiftId: null },
          select: { id: true },
        });
        if (stub) {
          await prisma.service.update({
            where: { id: stub.id },
            data: {
              externalShiftId: htmlShiftId,
              lifecycleStatus,
              name: cleanServiceName((mission.title as string | undefined)?.trim() || `Mission ${missionId}`),
            },
          });
          svcId = stub.id;
          result.updated++;
        } else {
          try {
            const rawName = (mission.title as string | undefined)?.trim() || `Mission ${missionId}`;
            const name = cleanServiceName(rawName);
            const startAt = parseAthensDatetime(mission.start_date as string | undefined);
            const endAt = parseAthensDatetime(mission.end_date as string | undefined);
            const location = (mission.location_text as string | undefined)?.trim() || null;
            const serviceTypeId = lookupServiceTypeId(typeIdMap, mission.mission_type_id);
            const created = await prisma.service.create({
              data: {
                departmentId,
                name,
                externalShiftId: htmlShiftId,
                externalMissionId: missionId,
                startAt,
                endAt,
                location,
                serviceTypeId,
                lifecycleStatus,
              },
            });
            svcId = created.id;
            missionHtmlCreatedShifts++;
            result.created++;
          } catch (e: unknown) {
            console.warn(
              `[mitrooSync] processFinalizedMissions: mission_id=${missionId}: shift_id=${htmlShiftId} ` +
              `not in API shifts and failed to create service: ${e}`,
            );
            continue;
          }
        }
      }

      missionHtmlCreatedShifts++;
      for (const app of apps) {
        try {
          const userId = userByExternal.get(app.memberId);
          if (!userId) { missionHtmlAppsSkippedNoUser++; continue; }
          await upsertUserService(
            svcId, userId, app.status,
            app.hoursSanitary, app.hoursVolunteering, app.hoursTraining,
            app.hoursRetraining, app.hoursTEP,
            app.applicationId, result,
          );
          missionHtmlAppsProcessed++;
        } catch (e: unknown) {
          result.errors.push(`html_app member_id=${app.memberId} shift_id=${htmlShiftId}: ${e}`);
        }
      }
    }

    // Per-mission diagnostic summary
    console.log(
      `[mitrooSync] processFinalizedMissions: mission_id=${missionId}: ` +
      `${shifts.length} API shift(s), ` +
      `_with_members: ${missionMembersProcessed} processed, ${missionMembersSkippedNoStatus} skipped (no status), ` +
      `HTML: ${missionHtmlMatchedShifts} shift(s) matched, ${missionHtmlUnmatchedShifts} unmatched, ${missionHtmlCreatedShifts} created, ` +
      `${missionHtmlAppsProcessed} app(s) upserted, ${missionHtmlAppsSkippedNoUser} skipped (no local user)`,
    );
  }
}

// ── Sync finalized missions ────────────────────────────────────────────

async function upsertUserService(
  serviceId: number,
  userId: number,
  status: "requested" | "accepted" | "rejected" | "participated",
  hours: number,
  hoursVol: number,
  hoursTraining: number,
  hoursTrainers: number,
  hoursTEP: number,
  externalApplicationId: number,
  result: SyncResult,
) {
  const existing = await prisma.userService.findUnique({
    where: { userId_serviceId: { userId, serviceId } },
    select: { userId: true },
  });
  if (existing) {
    await prisma.userService.update({
      where: { userId_serviceId: { userId, serviceId } },
      data: { status, hours, hoursVol, hoursTraining, hoursTrainers, hoursTEP, externalApplicationId },
    });
    result.updated++;
  } else {
    await prisma.userService.create({
      data: { userId, serviceId, status, hours, hoursVol, hoursTraining, hoursTrainers, hoursTEP, externalApplicationId },
    });
    result.created++;
  }
}

export async function syncFinalizedServices(departmentId: number): Promise<SyncResult> {
  const result: SyncResult = { created: 0, updated: 0, errors: [] };
  try {
    const client = await getClient(departmentId);

    console.log("[mitrooSync] syncFinalizedServices: fetching finalized missions...");
    const finalizedMissions = await client.fetchFinalizedMissions();
    console.log(`[mitrooSync] syncFinalizedServices: finalized=${finalizedMissions.length}`);

    await processFinalizedMissions(departmentId, client, finalizedMissions, result);

    console.log(`[mitrooSync] syncFinalizedServices: done — created=${result.created} updated=${result.updated} errors=${result.errors.length}`);

    await setSyncStatus(departmentId, "finalized", "success");
  } catch (e: unknown) {
    const msg = String(e);
    result.errors.push(msg);
    console.error("[mitrooSync] syncFinalizedServices: FATAL error:", e);
    await setSyncStatus(departmentId, "finalized", "failed", msg).catch(() => {});
  }
  return result;
}

// ── Sync shift applications → UserServices ─────────────────────────────────

export async function syncShiftApplications(departmentId: number): Promise<SyncResult> {
  const result: SyncResult = { created: 0, updated: 0, errors: [] };
  try {
    const config = await prisma.departmentSyncConfig.findUnique({
      where: { departmentId },
      select: { departmentId: true },
    });
    if (!config) return result;

    const client = await getClient(departmentId);
    const applications = await client.fetchShiftApplications();

    console.log(
      `[mitrooSync] syncShiftApplications: fetched ${applications.length} applications`,
    );

    const shiftIds = Array.from(
      new Set(
        applications
          .map((app) => Number(app.mission_shift_id))
          .filter((id) => Number.isFinite(id) && id > 0),
      ),
    );
    const userExternalIds = Array.from(
      new Set(
        applications
          .map((app) => Number(app.member_id))
          .filter((id) => Number.isFinite(id) && id > 0),
      ),
    );

    const [services, users] = await Promise.all([
      prisma.service.findMany({
        where: { departmentId, externalShiftId: { in: shiftIds } },
        select: { id: true, externalShiftId: true },
      }),
      prisma.user.findMany({
        where: { externalId: { in: userExternalIds } },
        select: { id: true, externalId: true },
      }),
    ]);

    const serviceByShift = new Map<number, number>();
    for (const svc of services) {
      if (svc.externalShiftId != null) serviceByShift.set(svc.externalShiftId, svc.id);
    }

    const userByExternal = new Map<number, number>();
    for (const usr of users) {
      if (usr.externalId != null) userByExternal.set(usr.externalId, usr.id);
    }

    const existingUserServices = await prisma.userService.findMany({
      where: {
        serviceId: { in: services.map((s) => s.id) },
        userId: { in: users.map((u) => u.id) },
      },
      select: { userId: true, serviceId: true },
    });

    const existingKeys = new Set(
      existingUserServices.map((row) => `${row.userId}:${row.serviceId}`),
    );

    const updates: Array<ReturnType<typeof prisma.userService.update>> = [];
    const createData: Array<{
      userId: number;
      serviceId: number;
      status: "requested" | "accepted" | "rejected" | "participated";
      hours: number;
      hoursVol: number;
      hoursTraining: number;
      hoursTrainers: number;
      hoursTEP: number;
      externalApplicationId: number;
    }> = [];

    for (const app of applications) {
      try {
        const externalShiftId = Number(app.mission_shift_id);
        const externalUserId = Number(app.member_id);
        const externalApplicationId = Number(app.id);
        if (!externalShiftId || !externalUserId || !externalApplicationId) continue;

        const serviceId = serviceByShift.get(externalShiftId);
        if (!serviceId) continue;

        const userId = userByExternal.get(externalUserId);
        if (!userId) continue;

        const status = mapApplicationStatus(app.application_status_id);
        if (status === null) continue;

        const hours = parseHours(app.hours_sanitary);
        const hoursVol = parseHours(app.hours_volunteering);
        const hoursTraining = parseHours(app.hours_training);
        const hoursTrainers = parseHours(app.hours_retraining);
        const hoursTEP = parseHours(app.hours_tep);

        const key = `${userId}:${serviceId}`;
        if (existingKeys.has(key)) {
          updates.push(
            prisma.userService.update({
              where: { userId_serviceId: { userId, serviceId } },
              data: {
                status,
                hours,
                hoursVol,
                hoursTraining,
                hoursTrainers,
                hoursTEP,
                externalApplicationId,
              },
            }),
          );
          result.updated++;
        } else {
          createData.push({
            userId,
            serviceId,
            status,
            hours,
            hoursVol,
            hoursTraining,
            hoursTrainers,
            hoursTEP,
            externalApplicationId,
          });
        }
      } catch (e: unknown) {
        result.errors.push(`application_id=${app.id}: ${e}`);
      }
    }

    const batchSize = 200;
    for (let i = 0; i < updates.length; i += batchSize) {
      await prisma.$transaction(updates.slice(i, i + batchSize));
    }
    for (let i = 0; i < createData.length; i += batchSize) {
      const batch = createData.slice(i, i + batchSize);
      const created = await prisma.userService.createMany({
        data: batch,
        skipDuplicates: true,
      });
      result.created += created.count;
    }

    await setSyncStatus(departmentId, "service", "success");
  } catch (e: unknown) {
    const msg = String(e);
    result.errors.push(msg);
    await setSyncStatus(departmentId, "service", "failed", msg).catch(() => {});
  }
  return result;
}

// ── Write-back: new service → create mission + shift ───────────────────────

export async function writeBackNewService(serviceId: number): Promise<void> {
  const service = await prisma.service.findUnique({
    where: { id: serviceId },
    select: {
      id: true,
      name: true,
      description: true,
      location: true,
      startAt: true,
      endAt: true,
      departmentId: true,
      externalShiftId: true,
      defaultHours: true,
      defaultHoursVol: true,
      defaultHoursTraining: true,
      defaultHoursTrainers: true,
      defaultHoursTEP: true,
      maxParticipants: true,
      serviceType: { select: { externalMissionTypeId: true } },
    },
  });
  if (!service || service.externalShiftId) return;

  const config = await prisma.departmentSyncConfig.findUnique({
    where: { departmentId: service.departmentId },
    select: { syncEnabled: true },
  });
  if (!config?.syncEnabled) return;

  try {
    const client = await getClient(service.departmentId);

    const startAt = service.startAt ?? service.endAt;
    if (!startAt) {
      console.warn(`[mitrooSync] writeBackNewService: skipped — service ${serviceId} has no dates`);
      return;
    }
    const endAt = service.endAt ?? startAt;

    const missionTypeId = service.serviceType?.externalMissionTypeId ?? undefined;

    const missionId = await client.createMission({
      title: service.name,
      start_date: formatAthensDate(startAt),
      end_date: formatAthensDate(endAt),
      location_text: service.location ?? "",
      comments: service.description ?? "",
      mission_type_id: missionTypeId,
    });

    const shiftId = await client.createShift({
      mission_id: missionId,
      shift_start_date: formatAthensDatetime(startAt),
      shift_end_date: formatAthensDatetime(endAt),
      total_participants: service.maxParticipants ?? 100,
      hours_sanitary: service.defaultHours ?? 0,
      hours_volunteering: service.defaultHoursVol ?? 0,
      hours_training: service.defaultHoursTraining ?? 0,
      hours_retraining: service.defaultHoursTrainers ?? 0,
      hours_tep: service.defaultHoursTEP ?? 0,
      mission_type_id: missionTypeId,
    });

    await client.changeMissionStatus(missionId, 22);

    await prisma.service.update({
      where: { id: serviceId },
      data: { externalShiftId: shiftId, externalMissionId: missionId },
    });

    console.log(
      `[mitrooSync] writeBackNewService: service ${serviceId} → mission ${missionId}, shift ${shiftId}`,
    );
  } catch (e) {
    console.error(`[mitrooSync] writeBackNewService failed for service ${serviceId}:`, e);
  }
}

// ── Write-back: deleted service → cancel shift/mission ───────────────────────

export async function writeBackServiceDelete(serviceId: number): Promise<void> {
  const service = await prisma.service.findUnique({
    where: { id: serviceId },
    select: {
      id: true,
      name: true,
      startAt: true,
      endAt: true,
      departmentId: true,
      externalShiftId: true,
      externalMissionId: true,
    },
  });
  if (!service) {
    console.log(`[mitrooSync] writeBackServiceDelete: skipped — service ${serviceId} not found`);
    return;
  }
  const missing: string[] = [];
  if (!service.externalShiftId) missing.push("externalShiftId");
  if (!service.externalMissionId) missing.push("externalMissionId");
  if (missing.length) {
    console.log(
      `[mitrooSync] writeBackServiceDelete: skipped — service ${serviceId} missing ${missing.join(", ")}`,
    );
    return;
  }

  const config = await prisma.departmentSyncConfig.findUnique({
    where: { departmentId: service.departmentId },
    select: { syncEnabled: true },
  });
  if (!config?.syncEnabled) return;

  try {
    const client = await getClient(service.departmentId);

    const formatDateTime = (d: Date | null | undefined) =>
      d ? d.toISOString().slice(0, 16).replace("T", " ") : "";
    const startAt = service.startAt ?? service.endAt;
    const endAt = service.endAt ?? service.startAt;
    const window = startAt
      ? `${formatDateTime(startAt)}${endAt ? `-${formatDateTime(endAt)}` : ""}`
      : "";
    // External system expects Greek cancellation messages for mission shift notifications.
    // Strip control characters and angle brackets to avoid injection in external email messages.
    const safeName = String(service.name ?? "").replace(/[\r\n<>]+/g, " ").trim();
    const emailMessage = window
      ? `Η βάρδια ${safeName} (${window}) έχει ακυρωθεί.`
      : `Η βάρδια ${safeName} έχει ακυρωθεί.`;

    await client.cancelShift({
      missionId: Number(service.externalMissionId),
      shiftId: Number(service.externalShiftId),
      emailMessage,
    });

    const otherServices = await prisma.service.count({
      where: {
        externalMissionId: service.externalMissionId,
        id: { not: serviceId },
      },
    });

    if (otherServices === 0) {
      await client.cancelMission(Number(service.externalMissionId));
    }

    console.log(
      `[mitrooSync] writeBackServiceDelete: cancelled shift ${service.externalShiftId} (mission ${service.externalMissionId})`,
    );
  } catch (e) {
    console.error(`[mitrooSync] writeBackServiceDelete failed for service ${serviceId}:`, e);
  }
}

// ── Write-back: user assignment → approve shift application ────────────────

export async function writeBackAssignment(serviceId: number, userId: number): Promise<void> {
  const [userService, service, user] = await Promise.all([
    prisma.userService.findUnique({
      where: { userId_serviceId: { userId, serviceId } },
      select: { externalApplicationId: true },
    }),
    prisma.service.findUnique({
      where: { id: serviceId },
      select: {
        externalShiftId: true,
        externalMissionId: true,
        departmentId: true,
        defaultHours: true,
        defaultHoursVol: true,
        defaultHoursTraining: true,
        defaultHoursTrainers: true,
        defaultHoursTEP: true,
      },
    }),
    prisma.user.findUnique({
      where: { id: userId },
      select: { externalId: true },
    }),
  ]);

  console.log(`[mitrooSync] writeBackAssignment: service=${serviceId} user=${userId}`, {
    externalShiftId: service?.externalShiftId,
    externalMissionId: service?.externalMissionId,
    externalApplicationId: userService?.externalApplicationId,
    externalId: user?.externalId,
  });

  if (!service?.externalShiftId) {
    console.log(`[mitrooSync] writeBackAssignment: skipped — service has no externalShiftId`);
    return;
  }

  const config = await prisma.departmentSyncConfig.findUnique({
    where: { departmentId: service.departmentId },
    select: { syncEnabled: true },
  });
  if (!config?.syncEnabled) {
    console.log(`[mitrooSync] writeBackAssignment: skipped — sync not enabled for dept ${service.departmentId}`);
    return;
  }

  try {
    const client = await getClient(service.departmentId);

    const pushHours = async (applicationId: number) => {
      if (!service.externalMissionId) return;
      await client.updateApplicationHours(applicationId, service.externalMissionId, {
        sanitary: service.defaultHours ?? 0,
        volunteering: service.defaultHoursVol ?? 0,
        training: service.defaultHoursTraining ?? 0,
        retraining: service.defaultHoursTrainers ?? 0,
        tep: service.defaultHoursTEP ?? 0,
      });
    };

    if (userService?.externalApplicationId) {
      await client.approveShiftApplication(userService.externalApplicationId);
      await pushHours(userService.externalApplicationId);
      console.log(
        `[mitrooSync] writeBackAssignment: approved application ${userService.externalApplicationId}`,
      );
    } else if (user?.externalId) {
      console.log(`[mitrooSync] writeBackAssignment: adding user ${user.externalId} to shift ${service.externalShiftId}`);
      try {
        await client.addUserToShift(service.externalShiftId, user.externalId);
      } catch (addErr) {
        // User may already have an application (e.g. from a previous partial run) — log and continue to lookup
        console.warn(`[mitrooSync] writeBackAssignment: addUserToShift failed (will try to find existing application): ${addErr}`);
      }

      // addUserToShift response doesn't return the application ID — look it up from shift members
      const applicationId = await client.findApplicationIdForMember(
        service.externalShiftId,
        user.externalId,
      );
      console.log(`[mitrooSync] writeBackAssignment: resolved applicationId=${applicationId}`);

      if (applicationId) {
        await prisma.userService.update({
          where: { userId_serviceId: { userId, serviceId } },
          data: { externalApplicationId: applicationId },
        });
        await client.approveShiftApplication(applicationId);
        await pushHours(applicationId);
        console.log(
          `[mitrooSync] writeBackAssignment: added+approved+hours for application ${applicationId}, user ${userId}`,
        );
      } else {
        console.warn(
          `[mitrooSync] writeBackAssignment: could not resolve application ID for user ${userId} — manual approval needed in original Mitroo`,
        );
      }
    } else {
      console.log(`[mitrooSync] writeBackAssignment: skipped — user has no externalId`);
    }
  } catch (e) {
    console.error(
      `[mitrooSync] writeBackAssignment failed for service ${serviceId}, user ${userId}:`,
      e,
    );
  }
}

export async function writeBackHoursUpdate(serviceId: number, userId: number): Promise<void> {
  const [userService, service, user] = await Promise.all([
    prisma.userService.findUnique({
      where: { userId_serviceId: { userId, serviceId } },
      select: {
        externalApplicationId: true,
        hours: true,
        hoursVol: true,
        hoursTraining: true,
        hoursTrainers: true,
        hoursTEP: true,
      },
    }),
    prisma.service.findUnique({
      where: { id: serviceId },
      select: { externalShiftId: true, externalMissionId: true, departmentId: true },
    }),
    prisma.user.findUnique({
      where: { id: userId },
      select: { externalId: true },
    }),
  ]);

  if (!service?.externalShiftId || !service.externalMissionId) return;

  const config = await prisma.departmentSyncConfig.findUnique({
    where: { departmentId: service.departmentId },
    select: { syncEnabled: true },
  });
  if (!config?.syncEnabled) return;

  try {
    const client = await getClient(service.departmentId);

    let applicationId = userService?.externalApplicationId ?? null;
    if (!applicationId && user?.externalId) {
      applicationId = await client.findApplicationIdForMember(
        service.externalShiftId,
        user.externalId,
      );
    }
    if (!applicationId) {
      console.log(`[mitrooSync] writeBackHoursUpdate: no application found for user ${userId} — skipping`);
      return;
    }

    await client.updateApplicationHours(applicationId, service.externalMissionId, {
      sanitary: userService?.hours ?? 0,
      volunteering: userService?.hoursVol ?? 0,
      training: userService?.hoursTraining ?? 0,
      retraining: userService?.hoursTrainers ?? 0,
      tep: userService?.hoursTEP ?? 0,
    });
    console.log(`[mitrooSync] writeBackHoursUpdate: updated hours for application ${applicationId}`);
  } catch (e) {
    console.error(`[mitrooSync] writeBackHoursUpdate failed for service ${serviceId}, user ${userId}:`, e);
  }
}

export async function writeBackRejection(
  serviceId: number,
  userId: number,
  knownApplicationId?: number | null,
): Promise<void> {
  console.log(`[mitrooSync] writeBackRejection: START serviceId=${serviceId} userId=${userId} knownApplicationId=${knownApplicationId}`);

  const [userService, service, user] = await Promise.all([
    knownApplicationId !== undefined
      ? null
      : prisma.userService.findUnique({
          where: { userId_serviceId: { userId, serviceId } },
          select: { externalApplicationId: true },
        }),
    prisma.service.findUnique({
      where: { id: serviceId },
      select: { externalShiftId: true, departmentId: true },
    }),
    prisma.user.findUnique({
      where: { id: userId },
      select: { externalId: true },
    }),
  ]);

  console.log(`[mitrooSync] writeBackRejection: DB lookup — userService=${JSON.stringify(userService)} service=${JSON.stringify(service)} user.externalId=${user?.externalId}`);

  if (!service?.externalShiftId) {
    console.log(`[mitrooSync] writeBackRejection: SKIP — service has no externalShiftId`);
    return;
  }

  const config = await prisma.departmentSyncConfig.findUnique({
    where: { departmentId: service.departmentId },
    select: { syncEnabled: true },
  });
  console.log(`[mitrooSync] writeBackRejection: deptId=${service.departmentId} syncEnabled=${config?.syncEnabled}`);

  if (!config?.syncEnabled) {
    console.log(`[mitrooSync] writeBackRejection: SKIP — sync not enabled for department ${service.departmentId}`);
    return;
  }

  try {
    const client = await getClient(service.departmentId);

    let applicationId = knownApplicationId ?? userService?.externalApplicationId ?? null;
    console.log(`[mitrooSync] writeBackRejection: applicationId after known/DB lookup = ${applicationId}`);

    if (!applicationId && user?.externalId) {
      console.log(`[mitrooSync] writeBackRejection: falling back to findApplicationIdForMember(shiftId=${service.externalShiftId}, externalUserId=${user.externalId})`);
      applicationId = await client.findApplicationIdForMember(
        service.externalShiftId,
        user.externalId,
      );
      console.log(`[mitrooSync] writeBackRejection: fallback result = ${applicationId}`);
    }

    if (!applicationId) {
      console.log(`[mitrooSync] writeBackRejection: SKIP — no application found for user ${userId} (known=${knownApplicationId}, db=${userService?.externalApplicationId}, userExternalId=${user?.externalId})`);
      return;
    }

    console.log(`[mitrooSync] writeBackRejection: calling cancelShiftApplication(${applicationId})`);
    await client.cancelShiftApplication(applicationId);

    // Clear externalApplicationId so a subsequent acceptance creates a fresh application
    // rather than trying to approve the now-cancelled one.
    // The UserService record may already be deleted (admin removal), so use updateMany
    // with a service+user filter instead of the compound unique.
    await prisma.userService.updateMany({
      where: { userId, serviceId, externalApplicationId: applicationId },
      data: { externalApplicationId: null },
    });

    console.log(`[mitrooSync] writeBackRejection: SUCCESS — cancelled application ${applicationId} for user ${userId}`);
  } catch (e) {
    console.error(`[mitrooSync] writeBackRejection: FAILED for service ${serviceId}, user ${userId}:`, e);
  }
}

// ── Write-back: enrollment request → create shift application ─────────────

export async function writeBackEnrollmentRequest(serviceId: number, userId: number): Promise<void> {
  const [service, user] = await Promise.all([
    prisma.service.findUnique({
      where: { id: serviceId },
      select: { externalShiftId: true, departmentId: true },
    }),
    prisma.user.findUnique({
      where: { id: userId },
      select: { externalId: true },
    }),
  ]);

  if (!service?.externalShiftId) {
    console.log(`[mitrooSync] writeBackEnrollmentRequest: skipped — service has no externalShiftId`);
    return;
  }
  if (!user?.externalId) {
    console.log(`[mitrooSync] writeBackEnrollmentRequest: skipped — user has no externalId`);
    return;
  }

  const config = await prisma.departmentSyncConfig.findUnique({
    where: { departmentId: service.departmentId },
    select: { syncEnabled: true },
  });
  if (!config?.syncEnabled) return;

  try {
    const client = await getClient(service.departmentId);

    let applicationId: number | null = null;

    try {
      applicationId = await client.addUserToShift(service.externalShiftId, user.externalId);
    } catch (addErr) {
      // addUserToShift may throw when the user already has an application for this shift.
      // Fall through to try finding the existing application ID.
      console.warn(
        `[mitrooSync] writeBackEnrollmentRequest: addUserToShift threw, will try findApplicationIdForMember: ${addErr}`,
      );
    }

    if (!applicationId) {
      applicationId = await client.findApplicationIdForMember(
        service.externalShiftId,
        user.externalId,
      );
    }

    if (applicationId) {
      await prisma.userService.update({
        where: { userId_serviceId: { userId, serviceId } },
        data: { externalApplicationId: applicationId },
      });
      console.log(
        `[mitrooSync] writeBackEnrollmentRequest: saved application ${applicationId} for user ${userId} in shift ${service.externalShiftId}`,
      );
    } else {
      console.log(
        `[mitrooSync] writeBackEnrollmentRequest: could not create or find application for user ${userId} in shift ${service.externalShiftId}`,
      );
    }
  } catch (e) {
    console.error(
      `[mitrooSync] writeBackEnrollmentRequest failed for service ${serviceId}, user ${userId}:`,
      e,
    );
  }
}

// ── Write-back: unenroll → cancel member shift application ────────────────

export async function writeBackUnenroll(
  serviceId: number,
  userId: number,
  knownApplicationId?: number | null,
): Promise<void> {
  const [userService, service, user] = await Promise.all([
    knownApplicationId !== undefined
      ? null
      : prisma.userService.findUnique({
          where: { userId_serviceId: { userId, serviceId } },
          select: { externalApplicationId: true },
        }),
    prisma.service.findUnique({
      where: { id: serviceId },
      select: { externalShiftId: true, departmentId: true },
    }),
    prisma.user.findUnique({
      where: { id: userId },
      select: { externalId: true },
    }),
  ]);

  if (!service?.externalShiftId) {
    console.log(`[mitrooSync] writeBackUnenroll: skipped — service has no externalShiftId`);
    return;
  }

  const config = await prisma.departmentSyncConfig.findUnique({
    where: { departmentId: service.departmentId },
    select: { syncEnabled: true },
  });
  if (!config?.syncEnabled) return;

  try {
    const client = await getClient(service.departmentId);

    let applicationId = knownApplicationId ?? userService?.externalApplicationId ?? null;

    if (!applicationId && user?.externalId) {
      applicationId = await client.findApplicationIdForMember(
        service.externalShiftId,
        user.externalId,
      );
    }

    if (!applicationId) {
      console.log(`[mitrooSync] writeBackUnenroll: no application found for user ${userId} — skipping`);
      return;
    }

    await client.cancelShiftApplication(applicationId);
    console.log(
      `[mitrooSync] writeBackUnenroll: cancelled application ${applicationId} for user ${userId}`,
    );
  } catch (e) {
    console.error(
      `[mitrooSync] writeBackUnenroll failed for service ${serviceId}, user ${userId}:`,
      e,
    );
  }
}

// ── Write-back: close service → set mission status to closed ──────────────

export async function writeBackServiceClose(serviceId: number): Promise<void> {
  const MITROO_MISSION_STATUS_CLOSED = 3;
  try {
    const service = await prisma.service.findUnique({
      where: { id: serviceId },
      select: { externalMissionId: true, departmentId: true, name: true },
    });
    if (!service?.externalMissionId) {
      console.log(`[mitrooSync] writeBackServiceClose: service ${serviceId} has no externalMissionId — skipping`);
      return;
    }
    const client = await getClient(service.departmentId);
    await client.changeMissionStatus(service.externalMissionId, MITROO_MISSION_STATUS_CLOSED);
    console.log(`[mitrooSync] writeBackServiceClose: SUCCESS — mission ${service.externalMissionId} closed`);
  } catch (e) {
    console.error(`[mitrooSync] writeBackServiceClose: FAILED for service ${serviceId}:`, e);
  }
}

// ── Write-back: complete service → mark participated + set mission completed ─

export async function writeBackServiceComplete(serviceId: number): Promise<void> {
  const MITROO_MISSION_STATUS_COMPLETED = 4;
  try {
    const service = await prisma.service.findUnique({
      where: { id: serviceId },
      select: {
        externalMissionId: true,
        departmentId: true,
        userServices: {
          where: { status: "participated" },
          select: { externalApplicationId: true },
        },
      },
    });
    if (!service?.externalMissionId) {
      console.log(`[mitrooSync] writeBackServiceComplete: service ${serviceId} has no externalMissionId — skipping`);
      return;
    }
    const client = await getClient(service.departmentId);

    for (const us of service.userServices) {
      if (!us.externalApplicationId) continue;
      try {
        await client.markShiftApplicationParticipated(us.externalApplicationId);
      } catch (e) {
        console.error(`[mitrooSync] writeBackServiceComplete: failed to mark application ${us.externalApplicationId}:`, e);
      }
    }

    await client.changeMissionStatus(service.externalMissionId, MITROO_MISSION_STATUS_COMPLETED);
    console.log(`[mitrooSync] writeBackServiceComplete: SUCCESS — mission ${service.externalMissionId} completed`);
  } catch (e) {
    console.error(`[mitrooSync] writeBackServiceComplete: FAILED for service ${serviceId}:`, e);
  }
}

// ── Per-user sync: pull applications from original Mitroo ─────────────────

export async function syncUserApplications(userId: number): Promise<SyncResult> {
  const result: SyncResult = { created: 0, updated: 0, errors: [] };

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { externalId: true, departments: { select: { departmentId: true } } },
  });
  if (!user?.externalId) {
    console.log(`[mitrooSync] syncUserApplications: skipped — user ${userId} has no externalId`);
    return result;
  }

  const departmentIds = user.departments.map((d) => d.departmentId);
  if (!departmentIds.length) return result;

  const configs = await prisma.departmentSyncConfig.findMany({
    where: { departmentId: { in: departmentIds } },
    select: { departmentId: true },
  });
  if (!configs.length) return result;

  for (const config of configs) {
    try {
      const client = await getClient(config.departmentId);
      const applications = await client.fetchShiftApplications();

      const userApps = applications.filter(
        (app) => Number(app.member_id) === user.externalId,
      );

      // ── Ensure services exist for shifts this user has applied to ─────────
      // Only creates missing ones; no updates to avoid excessive writes.
      const userShiftIds = Array.from(new Set(
        userApps
          .map((app) => Number(app.mission_shift_id))
          .filter((id) => Number.isFinite(id) && id > 0),
      ));

      if (userShiftIds.length > 0) {
        const existingServices = await prisma.service.findMany({
          where: { departmentId: config.departmentId, externalShiftId: { in: userShiftIds } },
          select: { externalShiftId: true },
        });
        const existingShiftSet = new Set(existingServices.map((s) => s.externalShiftId));
        const missingShiftIds = new Set(userShiftIds.filter((id) => !existingShiftSet.has(id)));

        if (missingShiftIds.size > 0) {
          // Group missing shift IDs by mission_id to minimise fetchShiftsForMission calls
          const missionToMissingShifts = new Map<number, Set<number>>();
          for (const app of userApps) {
            const shiftId = Number(app.mission_shift_id);
            const missionId = Number(app.mission_id);
            if (!missingShiftIds.has(shiftId)) continue;
            if (!Number.isFinite(missionId) || missionId <= 0) continue;
            if (!missionToMissingShifts.has(missionId)) {
              missionToMissingShifts.set(missionId, new Set());
            }
            missionToMissingShifts.get(missionId)!.add(shiftId);
          }

          for (const [missionId, shiftIds] of missionToMissingShifts) {
            try {
              const shifts = await client.fetchShiftsForMission(missionId);
              for (const shift of shifts) {
                const externalShiftId = Number(shift.id);
                if (!shiftIds.has(externalShiftId)) continue;

                // Guard against a race where another process created the service between
                // our batch check and now (mirrors the pattern used in syncServices).
                const alreadyExists = await prisma.service.findFirst({
                  where: { externalShiftId },
                  select: { id: true },
                });
                if (alreadyExists) continue;

                const rawName =
                  (shift.name as string | undefined) ??
                  (shift.title as string | undefined) ??
                  `Shift ${externalShiftId}`;
                const name = cleanServiceName(rawName);

                const startAt = shift.shift_start_date
                  ? new Date(shift.shift_start_date as string)
                  : undefined;
                const endAt = shift.shift_end_date
                  ? new Date(shift.shift_end_date as string)
                  : undefined;

                await prisma.service.create({
                  data: {
                    departmentId: config.departmentId,
                    name,
                    externalShiftId,
                    externalMissionId: missionId,
                    startAt,
                    endAt,
                    defaultHours: parseHours(shift.hours_sanitary),
                    defaultHoursVol: parseHours(shift.hours_volunteering),
                    defaultHoursTraining: parseHours(shift.hours_training),
                    defaultHoursTrainers: parseHours(shift.hours_retraining),
                    defaultHoursTEP: parseHours(shift.hours_tep),
                  },
                });
                result.created++;
                console.log(
                  `[mitrooSync] syncUserApplications: created stub service for shift ${externalShiftId} (mission ${missionId})`,
                );
              }
            } catch (e) {
              result.errors.push(`mission_id=${missionId}: failed to fetch/create service: ${e}`);
            }
          }
        }
      }
      // ── End service stub creation ─────────────────────────────────────────

      for (const app of userApps) {
        try {
          const externalShiftId = Number(app.mission_shift_id);
          const externalApplicationId = Number(app.id);
          if (!externalShiftId || !externalApplicationId) continue;

          const service = await prisma.service.findFirst({
            where: { departmentId: config.departmentId, externalShiftId },
            select: { id: true },
          });
          if (!service) continue;

          const status = mapApplicationStatus(app.application_status_id);
          if (status === null) continue;

          const existing = await prisma.userService.findUnique({
            where: { userId_serviceId: { userId, serviceId: service.id } },
            select: { userId: true },
          });

          if (existing) {
            await prisma.userService.update({
              where: { userId_serviceId: { userId, serviceId: service.id } },
              data: {
                status,
                hours: parseHours(app.hours_sanitary),
                hoursVol: parseHours(app.hours_volunteering),
                hoursTraining: parseHours(app.hours_training),
                hoursTrainers: parseHours(app.hours_retraining),
                hoursTEP: parseHours(app.hours_tep),
                externalApplicationId,
              },
            });
            result.updated++;
          } else {
            await prisma.userService.create({
              data: {
                userId,
                serviceId: service.id,
                status,
                hours: parseHours(app.hours_sanitary),
                hoursVol: parseHours(app.hours_volunteering),
                hoursTraining: parseHours(app.hours_training),
                hoursTrainers: parseHours(app.hours_retraining),
                hoursTEP: parseHours(app.hours_tep),
                externalApplicationId,
              },
            });
            result.created++;
          }
        } catch (e: unknown) {
          result.errors.push(`application_id=${app.id}: ${e}`);
        }
      }
    } catch (e: unknown) {
      result.errors.push(`dept=${config.departmentId}: ${e}`);
    }
  }

  if (result.created || result.updated || result.errors.length) {
    console.log(
      `[mitrooSync] syncUserApplications: user ${userId} — created=${result.created} updated=${result.updated} errors=${result.errors.length}`,
    );
  }
  return result;
}

// ── Per-user sync: ensure department membership from original Mitroo ───────

export async function syncUserDepartments(userId: number): Promise<SyncResult> {
  const result: SyncResult = { created: 0, updated: 0, errors: [] };

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { externalId: true, departments: { select: { departmentId: true } } },
  });
  if (!user?.externalId) return result;

  const configs = await prisma.departmentSyncConfig.findMany({
    where: { syncEnabled: true },
    select: { departmentId: true },
  });
  if (!configs.length) return result;

  const existingDeptIds = new Set(user.departments.map((d) => d.departmentId));

  for (const config of configs) {
    try {
      const client = await getClient(config.departmentId);
      const volunteers = await client.fetchVolunteers();

      const match = volunteers.find((v) => Number(v.id) === user.externalId);
      if (!match) continue;

      const deptName = (match.member_department as string | undefined)?.trim();
      if (!deptName) continue;

      let localDept = await prisma.department.findFirst({
        where: { name: { equals: deptName, mode: "insensitive" } },
        select: { id: true },
      });
      if (!localDept) {
        localDept = await prisma.department.create({
          data: { name: deptName },
          select: { id: true },
        });
        console.log(
          `[mitrooSync] syncUserDepartments: auto-created department "${deptName}" (id=${localDept.id})`,
        );
      }

      if (existingDeptIds.has(localDept.id)) {
        // Already linked; skip
        continue;
      }

      await prisma.userDepartment.upsert({
        where: { userId_departmentId: { userId, departmentId: localDept.id } },
        update: {},
        create: { userId, departmentId: localDept.id, role: "volunteer" },
      });
      result.created++;
      existingDeptIds.add(localDept.id);
    } catch (e: unknown) {
      result.errors.push(`dept=${config.departmentId}: ${e}`);
    }
  }

  if (result.created || result.errors.length) {
    console.log(
      `[mitrooSync] syncUserDepartments: user ${userId} — created=${result.created} errors=${result.errors.length}`,
    );
  }
  return result;
}

// ── Auto-save credentials on login + fire syncServices ─────────────────────
// Called fire-and-forget after any successful external Mitroo login so that
// credentials are always up-to-date and sync runs without manual setup.

export async function autoUpdateSyncConfig(
  memberDepartment: string,
  username: string,
  password: string,
  userId?: number,
): Promise<void> {
  let dept = await prisma.department.findFirst({
    where: { name: { equals: memberDepartment, mode: "insensitive" } },
    select: { id: true },
  });
  if (!dept) {
    try {
      dept = await prisma.department.create({
        data: { name: memberDepartment },
        select: { id: true },
      });
      console.log(`[mitrooSync] autoUpdateSyncConfig: auto-created department "${memberDepartment}"`);
    } catch {
      // Race: another concurrent login may have just created it
      dept = await prisma.department.findFirst({
        where: { name: { equals: memberDepartment, mode: "insensitive" } },
        select: { id: true },
      });
      if (!dept) return;
    }
  }

  const encryptedPassword = encrypt(password);
  await prisma.departmentSyncConfig.upsert({
    where: { departmentId: dept.id },
    // Update credentials only — preserve syncEnabled so admins can opt out of write-backs
    update: { externalUsername: username, externalPassword: encryptedPassword },
    create: {
      departmentId: dept.id,
      externalUsername: username,
      externalPassword: encryptedPassword,
      syncEnabled: true,
    },
  });
  console.log(`[mitrooSync] autoUpdateSyncConfig: credentials updated for dept ${dept.id}`);

  // Promote the triggering user to missionAdmin for this department
  if (userId) {
    await prisma.userDepartment.upsert({
      where: { userId_departmentId: { userId, departmentId: dept.id } },
      update: { role: "missionAdmin" },
      create: { userId, departmentId: dept.id, role: "missionAdmin" },
    });
    console.log(`[mitrooSync] autoUpdateSyncConfig: promoted user ${userId} to missionAdmin in dept ${dept.id}`);
  }

  syncAllServices(dept.id).catch((e) =>
    console.error(`[mitrooSync] autoUpdateSyncConfig: syncAllServices failed for dept ${dept!.id}:`, e),
  );
}

// ── Hourly cron: sync all departments that have credentials ─────────────────

export async function autoSyncAllDepartments(): Promise<void> {
  const configs = await prisma.departmentSyncConfig.findMany({
    select: { departmentId: true },
  });
  if (!configs.length) return;
  console.log(`[mitrooSync] autoSyncAllDepartments: syncing ${configs.length} department(s)`);
  for (const config of configs) {
    syncAllServices(config.departmentId).catch((e) =>
      console.error(`[mitrooSync] autoSyncAllDepartments: dept ${config.departmentId} failed:`, e),
    );
  }
}
