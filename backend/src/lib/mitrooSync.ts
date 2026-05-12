import crypto from "crypto";
import bcrypt from "bcryptjs";
import prisma from "./prisma";
import { encrypt, decrypt } from "./encryption";
import { MitrooClient } from "./mitrooClient";

const EXTERNAL_BASE_URL =
  process.env.MITROO_EXTERNAL_BASE_URL ?? "https://mitroo.redcross.gr";

export interface SyncResult {
  created: number;
  updated: number;
  errors: string[];
}

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

    for (const v of volunteers) {
      try {
        const externalId = Number(v.member_id);
        const email = (v.email as string)?.trim()?.toLowerCase();
        if (!email || !externalId) continue;

        const forename = (v.firstname as string) ?? "";
        const surname = (v.lastname as string) ?? "";
        const phone = (v.mobile as string) ?? (v.phone as string) ?? undefined;
        const address = (v.address as string) ?? undefined;

        const existing = await prisma.user.findFirst({
          where: { OR: [{ externalId }, { email }] },
          select: { id: true },
        });

        if (existing) {
          await prisma.user.update({
            where: { id: existing.id },
            data: { externalId, forename, surname, phonePrimary: phone, address },
          });
          result.updated++;
        } else {
          const rawPassword = crypto.randomBytes(15).toString("base64url");
          const hashed = await bcrypt.hash(rawPassword, 12);
          const eame = `EXT-${externalId}`;

          const user = await prisma.user.create({
            data: {
              externalId,
              email,
              forename,
              surname,
              eame,
              password: hashed,
              phonePrimary: phone,
              address,
            },
          });

          await prisma.userDepartment.upsert({
            where: { userId_departmentId: { userId: user.id, departmentId } },
            update: {},
            create: { userId: user.id, departmentId, role: "volunteer" },
          });
          result.created++;
        }
      } catch (e: unknown) {
        result.errors.push(`member_id=${v.member_id}: ${e}`);
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

    for (const mission of missions) {
      const missionId = Number(mission.mission_id);
      let shifts = [];
      try {
        shifts = await client.fetchShiftsForMission(missionId);
      } catch (e) {
        result.errors.push(`mission_id=${missionId}: failed to fetch shifts: ${e}`);
        continue;
      }

      for (const shift of shifts) {
        try {
          const externalShiftId = Number(shift.shift_id);
          const name =
            (shift.name as string) ??
            (shift.title as string) ??
            (mission.name as string) ??
            (mission.title as string) ??
            `Shift ${externalShiftId}`;

          const startAt = shift.shift_start_date
            ? new Date(shift.shift_start_date as string)
            : undefined;
          const endAt = shift.shift_end_date
            ? new Date(shift.shift_end_date as string)
            : undefined;

          const existing = await prisma.service.findFirst({
            where: { externalShiftId },
            select: { id: true },
          });

          if (existing) {
            await prisma.service.update({
              where: { id: existing.id },
              data: { name, startAt, endAt, externalMissionId: missionId },
            });
            result.updated++;
          } else {
            await prisma.service.create({
              data: {
                departmentId,
                name,
                externalShiftId,
                externalMissionId: missionId,
                startAt,
                endAt,
              },
            });
            result.created++;
          }
        } catch (e: unknown) {
          result.errors.push(`shift_id=${shift.shift_id}: ${e}`);
        }
      }
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
      startAt: true,
      endAt: true,
      departmentId: true,
      externalShiftId: true,
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

    const fmt = (d: Date | null | undefined) =>
      d ? d.toISOString().slice(0, 16).replace("T", " ") : "";

    const missionId = await client.createMission(
      service.name,
      fmt(service.startAt),
      fmt(service.endAt),
    );

    const shiftId = await client.createShift({
      mission_id: missionId,
      shift_start_date: fmt(service.startAt),
      shift_end_date: fmt(service.endAt),
    });

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

// ── Write-back: user assignment → approve shift application ────────────────

export async function writeBackAssignment(serviceId: number, userId: number): Promise<void> {
  const [userService, service] = await Promise.all([
    prisma.userService.findUnique({
      where: { userId_serviceId: { userId, serviceId } },
      select: { externalApplicationId: true },
    }),
    prisma.service.findUnique({
      where: { id: serviceId },
      select: { externalShiftId: true, departmentId: true },
    }),
  ]);

  if (!userService?.externalApplicationId || !service?.externalShiftId) return;

  const config = await prisma.departmentSyncConfig.findUnique({
    where: { departmentId: service.departmentId },
    select: { syncEnabled: true },
  });
  if (!config?.syncEnabled) return;

  try {
    const client = await getClient(service.departmentId);
    await client.approveShiftApplication(userService.externalApplicationId);
    console.log(
      `[mitrooSync] writeBackAssignment: approved application ${userService.externalApplicationId}`,
    );
  } catch (e) {
    console.error(
      `[mitrooSync] writeBackAssignment failed for service ${serviceId}, user ${userId}:`,
      e,
    );
  }
}
