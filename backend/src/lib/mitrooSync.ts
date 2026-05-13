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

/** Safely convert external hour values to finite numbers, defaulting to 0. */
const parseHours = (value: unknown) => {
  const num = Number(value ?? 0);
  return Number.isFinite(num) ? num : 0;
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

    for (const v of volunteers) {
      try {
        const externalId = Number(v.id);
        if (!externalId) continue;

        const forename = (v.first_name as string) ?? "";
        const surname = (v.last_name as string) ?? "";
        const email = `ext.${externalId}@mitroo.sync`;
        const eame =
          (v.registration_code as string)?.trim() || `EXT-${externalId}`;

        const existing = await prisma.user.findFirst({
          where: { OR: [{ externalId }, { eame }] },
          select: { id: true, externalId: true },
        });

        if (existing) {
          await prisma.user.update({
            where: { id: existing.id },
            data: {
              forename,
              surname,
              // Link the account if found by eame but externalId wasn't set yet
              ...(existing.externalId == null ? { externalId } : {}),
            },
          });
          result.updated++;
        } else {
          const rawPassword = crypto.randomBytes(15).toString("base64url");
          const hashed = await bcrypt.hash(rawPassword, 12);

          const user = await prisma.user.create({
            data: {
              externalId,
              email,
              forename,
              surname,
              eame,
              password: hashed,
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
        result.errors.push(`id=${v.id}: ${e}`);
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
          const name =
            (shift.name as string) ??
            (shift.title as string) ??
            (mission.title as string) ??
            `Shift ${externalShiftId}`;

          const startAt = shift.shift_start_date
            ? new Date(shift.shift_start_date as string)
            : undefined;
          const endAt = shift.shift_end_date
            ? new Date(shift.shift_end_date as string)
            : undefined;
          const defaultHours = parseHours(shift.hours_sanitary);
          const defaultHoursVol = parseHours(shift.hours_volunteering);
          const defaultHoursTraining = parseHours(shift.hours_training);
          const defaultHoursTrainers = parseHours(shift.hours_retraining);
          const defaultHoursTEP = parseHours(shift.hours_tep);

          const existing = await prisma.service.findFirst({
            where: { externalShiftId },
            select: { id: true },
          });

          if (existing) {
            await prisma.service.update({
              where: { id: existing.id },
              data: {
                name,
                startAt,
                endAt,
                externalMissionId: missionId,
                defaultHours,
                defaultHoursVol,
                defaultHoursTraining,
                defaultHoursTrainers,
                defaultHoursTEP,
              },
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
                defaultHours,
                defaultHoursVol,
                defaultHoursTraining,
                defaultHoursTrainers,
                defaultHoursTEP,
              },
            });
            result.created++;
          }
        } catch (e: unknown) {
          result.errors.push(`shift_id=${shift.id}: ${e}`);
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

    const missionId = await client.createMission({
      title: service.name,
      start_date: formatDate(startAt),
      end_date: formatDate(endAt),
      location_text: service.location ?? "",
      comments: service.description ?? "",
    });

    const shiftId = await client.createShift({
      mission_id: missionId,
      shift_start_date: formatDateTime(startAt),
      shift_end_date: formatDateTime(endAt),
      hours_sanitary: service.defaultHours ?? 0,
      hours_volunteering: service.defaultHoursVol ?? 0,
      hours_training: service.defaultHoursTraining ?? 0,
      hours_retraining: service.defaultHoursTrainers ?? 0,
      hours_tep: service.defaultHoursTEP ?? 0,
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
  if (!service?.externalShiftId) return;

  const config = await prisma.departmentSyncConfig.findUnique({
    where: { departmentId: service.departmentId },
    select: { syncEnabled: true },
  });
  if (!config?.syncEnabled) return;

  if (!service.externalMissionId) {
    console.warn(
      `[mitrooSync] writeBackServiceDelete: skipped — service ${serviceId} missing externalMissionId`,
    );
    return;
  }

  try {
    const client = await getClient(service.departmentId);

    const formatDateTime = (d: Date | null | undefined) =>
      d ? d.toISOString().slice(0, 16).replace("T", " ") : "";
    const startAt = service.startAt ?? service.endAt;
    const endAt = service.endAt ?? service.startAt;
    const window = startAt
      ? `${formatDateTime(startAt)}${endAt ? `-${formatDateTime(endAt)}` : ""}`
      : "";
    const emailMessage = window
      ? `Η βάρδια ${service.name} (${window}) έχει ακυρωθεί.`
      : `Η βάρδια ${service.name} έχει ακυρωθεί.`;

    await client.cancelShift({
      missionId: service.externalMissionId,
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
      await client.cancelMission(service.externalMissionId);
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

    await client.cancelShiftApplication(applicationId);
    console.log(`[mitrooSync] writeBackRejection: cancelled application ${applicationId} for user ${userId}`);
  } catch (e) {
    console.error(`[mitrooSync] writeBackRejection failed for service ${serviceId}, user ${userId}:`, e);
  }
}
