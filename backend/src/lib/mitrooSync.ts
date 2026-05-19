import crypto from "crypto";
import bcrypt from "bcryptjs";
import prisma from "./prisma";
import { encrypt, decrypt } from "./encryption";
import { MitrooClient } from "./mitrooClient";

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

export interface SyncResult {
  created: number;
  updated: number;
  errors: string[];
}

// Status IDs in original Mitroo: 1 = ΑΡΧΙΚΗ (pending/initial), 3 = accepted, 4 = rejected.
// Any other status (e.g. cancelled-by-member) is not imported to avoid phantom "applied for" records.
const mapApplicationStatus = (statusId: unknown): "requested" | "accepted" | "rejected" | null => {
  const id = Number(statusId);
  if (id === 1) return "requested";
  if (id === 3) return "accepted";
  if (id === 4) return "rejected";
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
  type: "user" | "service",
  status: "success" | "failed",
  error?: string,
) {
  const data: Record<string, unknown> = { lastSyncStatus: status };
  if (type === "user") data.lastUserSyncAt = new Date();
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

// ── Sync volunteers → Users ────────────────────────────────────────────────

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

// ── Sync missions/shifts → Services ────────────────────────────────────────

export async function syncServices(departmentId: number): Promise<SyncResult> {
  const result: SyncResult = { created: 0, updated: 0, errors: [] };
  try {
    const client = await getClient(departmentId);
    const missions = await client.fetchMissions();

    console.log(`[mitrooSync] syncServices: fetched ${missions.length} missions`);
    if (missions.length > 0) {
      console.log("[mitrooSync] Sample mission fields:", Object.keys(missions[0]));
    }

    const typeIdMap = await getServiceTypeIdMap();

    for (const mission of missions) {
      const missionId = Number(mission.id);
      let shifts = [];
      try {
        shifts = await client.fetchShiftsForMission(missionId);
      } catch (e) {
        result.errors.push(`mission_id=${missionId}: failed to fetch shifts: ${e}`);
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

          const startAt = shift.shift_start_date
            ? new Date(shift.shift_start_date as string)
            : undefined;
          const endAt = shift.shift_end_date
            ? new Date(shift.shift_end_date as string)
            : undefined;
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

          if (existing) {
            const serviceTypeId = lookupServiceTypeId(typeIdMap, mission.mission_type_id);
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
              },
            });
            result.updated++;
          } else {
            const serviceTypeId = lookupServiceTypeId(typeIdMap, mission.mission_type_id);
            const newService = await prisma.service.create({
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
              },
            });
            result.created++;
          }
        } catch (e: unknown) {
          result.errors.push(`shift_id=${shift.id}: ${e}`);
        }
      }
    }

    const appResult = await syncShiftApplications(departmentId);
    result.created += appResult.created;
    result.updated += appResult.updated;
    result.errors.push(...appResult.errors);

    await setSyncStatus(departmentId, "service", "success");
  } catch (e: unknown) {
    const msg = String(e);
    result.errors.push(msg);
    await setSyncStatus(departmentId, "service", "failed", msg).catch(() => {});
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
      status: "requested" | "accepted" | "rejected";
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

    const formatDate = (d: Date | null | undefined) =>
      d ? d.toISOString().slice(0, 10) : "";
    const formatDateTime = (d: Date | null | undefined) =>
      d ? d.toISOString().slice(0, 16).replace("T", " ") : "";
    const startAt = service.startAt ?? service.endAt;
    if (!startAt) {
      console.warn(`[mitrooSync] writeBackNewService: skipped — service ${serviceId} has no dates`);
      return;
    }
    const endAt = service.endAt ?? startAt;

    const missionTypeId = service.serviceType?.externalMissionTypeId ?? undefined;

    const missionId = await client.createMission({
      title: service.name,
      start_date: formatDate(startAt),
      end_date: formatDate(endAt),
      location_text: service.location ?? "",
      comments: service.description ?? "",
      mission_type_id: missionTypeId,
    });

    const shiftId = await client.createShift({
      mission_id: missionId,
      shift_start_date: formatDateTime(startAt),
      shift_end_date: formatDateTime(endAt),
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

export async function writeBackRejection(serviceId: number, userId: number): Promise<void> {
  const [userService, service, user] = await Promise.all([
    prisma.userService.findUnique({
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

  if (!service?.externalShiftId) return;

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
      console.log(`[mitrooSync] writeBackRejection: no application found for user ${userId} — skipping`);
      return;
    }

    await client.cancelMemberShiftApplication(applicationId);
    console.log(`[mitrooSync] writeBackRejection: cancelled application ${applicationId} for user ${userId}`);
  } catch (e) {
    console.error(`[mitrooSync] writeBackRejection failed for service ${serviceId}, user ${userId}:`, e);
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

    const applicationId = await client.addUserToShift(service.externalShiftId, user.externalId);
    if (applicationId) {
      await prisma.userService.update({
        where: { userId_serviceId: { userId, serviceId } },
        data: { externalApplicationId: applicationId },
      });
      console.log(
        `[mitrooSync] writeBackEnrollmentRequest: created application ${applicationId} for user ${userId} in shift ${service.externalShiftId}`,
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

export async function writeBackUnenroll(serviceId: number, userId: number): Promise<void> {
  const [userService, service, user] = await Promise.all([
    prisma.userService.findUnique({
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

    let applicationId = userService?.externalApplicationId ?? null;

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

    await client.cancelMemberShiftApplication(applicationId);
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

  syncServices(dept.id).catch((e) =>
    console.error(`[mitrooSync] autoUpdateSyncConfig: syncServices failed for dept ${dept!.id}:`, e),
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
    syncServices(config.departmentId).catch((e) =>
      console.error(`[mitrooSync] autoSyncAllDepartments: dept ${config.departmentId} failed:`, e),
    );
  }
}
