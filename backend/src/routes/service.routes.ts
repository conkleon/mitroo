import { Router, Request, Response } from "express";
import { z } from "zod";
import { Prisma } from "@prisma/client";
import prisma from "../lib/prisma";
import { authenticate, isMissionAdminInDepartment } from "../middleware/auth";
import { sendServiceEnrollmentEmail, sendServiceStatusEmail } from "../lib/email";
import { sendPushToUser } from "../lib/webpush";
import { getIO } from "../socket";
import {
  writeBackNewService,
  writeBackAssignment,
  writeBackRejection,
  writeBackParticipation,
  writeBackHoursUpdate,
  writeBackServiceDelete,
  syncEnrollmentRequestOrThrow,
  writeBackUnenroll,
  writeBackServiceClose,
  writeBackServiceComplete,
  syncSingleService,
} from "../lib/mitrooSync";
import { MitrooRemoteError } from "../lib/mitrooClient";

async function addToMissionChat(serviceId: number, userId: number): Promise<void> {
  const missionChat = await prisma.chat.findFirst({
    where: { type: "mission", serviceId },
    select: { id: true },
  });
  if (!missionChat) return;

  await prisma.chatMember.createMany({
    data: { chatId: missionChat.id, userId },
    skipDuplicates: true,
  });

  getIO().to(`user:${userId}`).emit("chat:member-joined", {
    chatId: missionChat.id,
    userId,
  });
}

async function removeFromMissionChat(serviceId: number, userId: number): Promise<void> {
  const missionChat = await prisma.chat.findFirst({
    where: { type: "mission", serviceId },
    select: { id: true },
  });
  if (!missionChat) return;

  await prisma.chatMember.deleteMany({
    where: { chatId: missionChat.id, userId },
  });

  getIO().to(`user:${userId}`).emit("chat:member-left", {
    chatId: missionChat.id,
    userId,
  });
}

const router = Router();
router.use(authenticate);

const createSchema = z.object({
  departmentId: z.number().int(),
  name: z.string().min(1).max(255),
  description: z.string().optional(),
  location: z.string().optional(),
  carrier: z.string().max(255).optional(),
  responsibleUserId: z.number().int().nullable().optional(),
  defaultHours: z.number().int().min(0).optional(),
  defaultHoursVol: z.number().int().min(0).optional(),
  defaultHoursTraining: z.number().int().min(0).optional(),
  defaultHoursTrainers: z.number().int().min(0).optional(),
  defaultHoursTEP: z.number().int().min(0).optional(),
  maxParticipants: z.number().int().min(1).optional(),
  startAt: z.string().datetime().optional(),
  endAt: z.string().datetime().optional(),
  serviceTypeId: z.number().int().optional().nullable(),
});

const enrollSchema = z.object({
  userId: z.number().int(),
  status: z.enum(["requested", "accepted", "rejected"]).optional(),
});

const statusSchema = z.object({
  status: z.enum(["requested", "accepted", "rejected"]),
});

async function requireServiceAdmin(req: Request, res: Response, departmentId: number): Promise<boolean> {
  if (req.user!.isAdmin) return true;
  const allowed = await isMissionAdminInDepartment(req.user!.userId, departmentId);
  if (!allowed) {
    res.status(403).json({ error: "Δεν έχετε δικαίωμα" });
    return false;
  }
  return true;
}

// Wire-format normalizer: Prisma enum values use underscores but the API wire
// format uses hyphens (e.g. not_participated → not-participated).
function normalizeServiceWireFormat(svc: any): any {
  if (svc.userServices) {
    for (const us of svc.userServices) {
      us.status = (us.status as string).replace(/_/g, '-');
    }
  }
  return svc;
}

// ── GET /api/services ───────────────────────────
router.get("/", async (req: Request, res: Response) => {
  const { departmentId, includeEnrollments, fromDate, toDate, search, specializationId, pastOnly, includeExpired, lifecycleStatus, page, limit } = req.query;
  const where: any = {};
  if (departmentId) where.departmentId = Number(departmentId);

  // Date range filters
  if (fromDate || toDate) {
    where.startAt = {};
    if (fromDate) where.startAt.gte = new Date(fromDate as string);
    if (toDate) where.startAt.lte = new Date(toDate as string);
  }

  // Only past services (endAt < now)
  if (pastOnly === "true") {
    where.endAt = { lt: new Date() };
  } else if (includeExpired !== "true" && !fromDate && !toDate) {
    // By default, exclude services that have already ended
    const now = new Date();
    where.OR = [
      { endAt: { gte: now } },
      { endAt: null, startAt: { gte: now } },
      { endAt: null, startAt: null },
    ];
  }

  // Filter by specialization via service type chain
  if (specializationId) {
    where.serviceType = {
      specializations: {
        some: { specializationId: Number(specializationId) },
      },
    };
  }

  // Full-text search across name, location, carrier, description
  if (search) {
    const q = search as string;
    where.AND = [
      ...(where.AND ?? []),
      {
        OR: [
          { name: { contains: q, mode: 'insensitive' } },
          { location: { contains: q, mode: 'insensitive' } },
          { carrier: { contains: q, mode: 'insensitive' } },
          { description: { contains: q, mode: 'insensitive' } },
        ],
      },
    ];
  }

  // Filter by lifecycle status
  if (lifecycleStatus) {
    const statuses = (Array.isArray(lifecycleStatus) ? lifecycleStatus : [lifecycleStatus]) as string[];
    const allowed = ['active', 'closed', 'completed', 'finalized'];
    if (!statuses.every((s) => allowed.includes(s))) {
      res.status(400).json({ error: 'Invalid lifecycleStatus value' });
      return;
    }
    where.lifecycleStatus = { in: statuses };
  }

  const includeBlock: any = {
    department: { select: { id: true, name: true } },
    responsibleUser: { select: { id: true, eame: true, forename: true, surname: true, imagePath: true } },
    serviceType: { select: { id: true, name: true } },
    _count: { select: { userServices: true, itemServices: true } },
  };

  // When admin requests enrollments, include user details per service
  if (includeEnrollments === "true") {
    includeBlock.userServices = {
      include: {
        user: {
          select: { id: true, eame: true, forename: true, surname: true, imagePath: true },
        },
      },
    };
  }

  const pageRaw = page ? parseInt(page as string, 10) : NaN;
  const limitRaw = limit ? parseInt(limit as string, 10) : NaN;
  const pageNum = isNaN(pageRaw) ? 1 : pageRaw;
  const limitNum = isNaN(limitRaw) ? undefined : limitRaw;

  // Validate pagination params if provided
  if (limitNum !== undefined && (limitNum < 1 || !Number.isInteger(limitNum))) {
    res.status(400).json({ error: "Invalid limit parameter" });
    return;
  }
  if (page && (pageNum < 1 || !Number.isInteger(pageNum))) {
    res.status(400).json({ error: "Invalid page parameter" });
    return;
  }

  const queryOptions: any = {
    where,
    include: includeBlock,
    orderBy: { startAt: "asc" },
  };
  if (limitNum !== undefined && pageNum > 0) {
    queryOptions.skip = (pageNum - 1) * limitNum;
    queryOptions.take = limitNum;
  }

  const services = await prisma.service.findMany(queryOptions);
  res.json(services.map(normalizeServiceWireFormat));
});

// ── GET /api/services/my ────────────────────────
// Returns services visible to the authenticated user:
//   • Global admins see ALL services (no department/specialization filter)
//   • Regular users: service must be in one of the user's departments
//     AND (service has no visibility restrictions OR user has a matching specialization)
router.get("/my", async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const isAdmin = req.user!.isAdmin;

  // Gather user's department IDs and specialization IDs
  const [userDepts, userSpecs] = await Promise.all([
    prisma.userDepartment.findMany({ where: { userId }, select: { departmentId: true } }),
    prisma.userSpecialization.findMany({ where: { userId }, select: { specializationId: true } }),
  ]);

  const deptIds = userDepts.map((d) => d.departmentId);
  const specIds = userSpecs.map((s) => s.specializationId);

  // Build the WHERE clause – admins bypass department & specialization filters
  // Only return upcoming/current services (not yet ended)
  const now = new Date();
  const upcomingFilter = {
    OR: [
      { endAt: { gte: now } },          // end date in the future
      { endAt: null, startAt: { gte: now } }, // no end date but starts in the future
      { endAt: null, startAt: null },    // no dates at all → still relevant
    ],
  };
  const where: any = { ...upcomingFilter };
  if (!isAdmin) {
    where.departmentId = { in: deptIds };
    where.AND = [
      {
        OR: [
          // services with no type → visible to all (safety net)
          { serviceTypeId: null },
          // services with default-visible types
          { serviceType: { isDefaultVisible: true } },
          // services whose types are assigned to the user's specializations
          { serviceType: { specializations: { some: { specializationId: { in: specIds } } } } },
        ],
      },
    ];
  }

  const services = await prisma.service.findMany({
    where,
    include: {
      department: { select: { id: true, name: true } },
      responsibleUser: { select: { id: true, eame: true, forename: true, surname: true, imagePath: true } },
      serviceType: {
        include: {
          specializations: { include: { specialization: { select: { id: true, name: true } } } },
        },
      },
      // Include ONLY the current user's enrollment so the client knows if already applied
      userServices: {
        where: { userId },
        select: { userId: true, status: true },
      },
      _count: { select: { userServices: true, itemServices: true } },
    },
    orderBy: { startAt: "asc" },
  });

  res.json(services);
});

// ── POST /api/services ──────────────────────────
router.post("/", async (req: Request, res: Response) => {
  try {
    const data = createSchema.parse(req.body);
    if (!await requireServiceAdmin(req, res, data.departmentId)) return;
    const service = await prisma.service.create({
      data: {
        ...data,
        startAt: data.startAt ? new Date(data.startAt) : undefined,
        endAt: data.endAt ? new Date(data.endAt) : undefined,
      },
      include: { department: { select: { id: true, name: true } } },
    });

    // Create the corresponding mission+shift in the original Mitroo system.
    // If that fails, don't keep the local service either.
    try {
      await writeBackNewService(service.id);
    } catch (syncErr) {
      await prisma.service.delete({ where: { id: service.id } }).catch(() => {});
      const message = syncErr instanceof MitrooRemoteError
        ? syncErr.message
        : "Η δημιουργία απέτυχε στο σύστημα Mitroo";
      res.status(502).json({ error: message });
      return;
    }

    const created = await prisma.service.findUnique({
      where: { id: service.id },
      include: { department: { select: { id: true, name: true } } },
    });
    res.status(201).json(created);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── GET /api/services/:id ───────────────────────
// Visible to global admins, or to users whose department matches the service's
// department AND (the service type is default-visible or matches one of the
// user's specializations) — mirrors GET /services/my.
router.get("/:id", async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const isAdmin = req.user!.isAdmin;

  const service = await prisma.service.findUnique({
    where: { id: Number(req.params.id) },
    include: {
      department: true,
      responsibleUser: { select: { id: true, eame: true, forename: true, surname: true, imagePath: true } },
      userServices: {
        include: {
          user: {
            select: {
              id: true, eame: true, forename: true, surname: true, imagePath: true,
              assignedItems: {
                select: { id: true, name: true, barCode: true, isContainer: true, location: true, imagePath: true, expirationDate: true },
              },
            },
          },
        },
      },
      vehicleLogs: { include: { vehicle: true } },
      serviceType: {
        include: {
          specializations: { include: { specialization: { select: { id: true, name: true } } } },
        },
      },
    },
  });
  if (!service) { res.status(404).json({ error: "Service not found" }); return; }

  if (!isAdmin) {
    const [inDept, userSpecs] = await Promise.all([
      prisma.userDepartment.count({ where: { userId, departmentId: service.departmentId } }),
      prisma.userSpecialization.findMany({ where: { userId }, select: { specializationId: true } }),
    ]);
    if (inDept === 0) {
      res.status(403).json({ error: "Δεν έχετε δικαίωμα" });
      return;
    }
    const specIds = userSpecs.map((s) => s.specializationId);
    const visible =
      !service.serviceTypeId ||
      service.serviceType?.isDefaultVisible ||
      service.serviceType?.specializations.some((s) => specIds.includes(s.specializationId));
    if (!visible) {
      res.status(403).json({ error: "Δεν έχετε δικαίωμα" });
      return;
    }
  }

  res.json(service);
});

// ── PATCH /api/services/:id ─────────────────────
router.patch("/:id", async (req: Request, res: Response) => {
  try {
    const service = await prisma.service.findUnique({ where: { id: Number(req.params.id) }, select: { departmentId: true } });
    if (!service) { res.status(404).json({ error: "Service not found" }); return; }
    if (!await requireServiceAdmin(req, res, service.departmentId)) return;
    const data = createSchema.partial().parse(req.body);
    const updated = await prisma.service.update({
      where: { id: Number(req.params.id) },
      data: {
        ...data,
        startAt: data.startAt ? new Date(data.startAt) : undefined,
        endAt: data.endAt ? new Date(data.endAt) : undefined,
      },
    });
    res.json(updated);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── POST /api/services/:id/close ────────────────
router.post("/:id/close", async (req: Request, res: Response) => {
  const serviceId = Number(req.params.id);
  const service = await prisma.service.findUnique({
    where: { id: serviceId },
    include: {
      userServices: {
        where: { status: "accepted" },
        include: { user: { select: { id: true } } },
      },
    },
  });
  if (!service) { res.status(404).json({ error: "Service not found" }); return; }
  if (!await requireServiceAdmin(req, res, service.departmentId)) return;
  if (service.lifecycleStatus !== "active") {
    res.status(409).json({ error: "Η υπηρεσία δεν είναι σε κατάσταση active" });
    return;
  }

  try {
    await writeBackServiceClose(serviceId);
  } catch (syncErr) {
    const message = syncErr instanceof MitrooRemoteError
      ? syncErr.message
      : "Το κλείσιμο απέτυχε στο σύστημα Mitroo";
    res.status(502).json({ error: message });
    return;
  }

  await prisma.service.update({
    where: { id: serviceId },
    data: { lifecycleStatus: "closed" },
  });

  const acceptedUserIds = service.userServices.map((us) => us.user.id);
  for (const userId of acceptedUserIds) {
    sendPushToUser(userId, {
      title: "Επιβεβαίωση Υπηρεσίας",
      body: `Η συμμετοχή σας στην υπηρεσία "${service.name}" επιβεβαιώθηκε.`,
      tag: `service-closed-${serviceId}`,
      route: `/services/${serviceId}`,
    }).catch(() => {});
  }

  res.json({ lifecycleStatus: "closed" });
});

// ── POST /api/services/:id/complete ─────────────
router.post("/:id/complete", async (req: Request, res: Response) => {
  const serviceId = Number(req.params.id);
  const service = await prisma.service.findUnique({
    where: { id: serviceId },
    select: { departmentId: true, lifecycleStatus: true },
  });
  if (!service) { res.status(404).json({ error: "Service not found" }); return; }
  if (!await requireServiceAdmin(req, res, service.departmentId)) return;
  if (service.lifecycleStatus !== "closed") {
    res.status(409).json({ error: "Η υπηρεσία πρέπει πρώτα να κλείσει" });
    return;
  }

  const acceptedUserIds = (await prisma.userService.findMany({
    where: { serviceId, status: "accepted" },
    select: { userId: true },
  })).map((us) => us.userId);

  await prisma.$transaction([
    prisma.userService.updateMany({
      where: { serviceId, status: "accepted" },
      data: { status: "participated" },
    }),
    prisma.service.update({
      where: { id: serviceId },
      data: { lifecycleStatus: "completed" },
    }),
  ]);

  try {
    await writeBackServiceComplete(serviceId);
  } catch (syncErr) {
    // Remote system rejected the completion — roll back the local state too.
    await prisma.$transaction([
      prisma.userService.updateMany({
        where: { serviceId, userId: { in: acceptedUserIds }, status: "participated" },
        data: { status: "accepted" },
      }),
      prisma.service.update({
        where: { id: serviceId },
        data: { lifecycleStatus: "closed" },
      }),
    ]);
    const message = syncErr instanceof MitrooRemoteError
      ? syncErr.message
      : "Η ολοκλήρωση απέτυχε στο σύστημα Mitroo";
    res.status(502).json({ error: message });
    return;
  }

  res.json({ lifecycleStatus: "completed" });
});

// ── DELETE /api/services/:id ────────────────────
router.delete("/:id", async (req: Request, res: Response) => {
  const service = await prisma.service.findUnique({ where: { id: Number(req.params.id) }, select: { departmentId: true } });
  if (!service) { res.status(404).json({ error: "Service not found" }); return; }
  if (!await requireServiceAdmin(req, res, service.departmentId)) return;
  try {
    await writeBackServiceDelete(Number(req.params.id));
  } catch (syncErr) {
    const message = syncErr instanceof MitrooRemoteError
      ? syncErr.message
      : "Η διαγραφή απέτυχε στο σύστημα Mitroo";
    res.status(502).json({ error: message });
    return;
  }
  await prisma.service.delete({ where: { id: Number(req.params.id) } });
  res.status(204).end();
});

// ── POST /api/services/:id/enroll ───────────────
// Self-enroll with "requested" is open to all authenticated users.
// Enrolling others or setting accepted/rejected requires admin/missionAdmin.
router.post("/:id/enroll", async (req: Request, res: Response) => {
  try {
    const requesterId = req.user!.userId;
    const serviceId = Number(req.params.id);

    const service = await prisma.service.findUnique({
      where: { id: serviceId },
      include: { department: { select: { id: true, name: true } } },
    });
    if (!service) { res.status(404).json({ error: "Service not found" }); return; }

    const data = enrollSchema.parse(req.body);
    const targetUserId = data.userId ?? requesterId;
    const status = data.status ?? "requested";

    // Self-enrollment with "requested" status is allowed for any authenticated user.
    // Admin or missionAdmin is required otherwise (enrolling others, setting accepted/rejected).
    const isSelfRequest = targetUserId === requesterId && status === "requested";
    const isServiceAdmin = req.user!.isAdmin || await isMissionAdminInDepartment(requesterId, service.departmentId);
    if (!isSelfRequest && !isServiceAdmin) {
      res.status(403).json({ error: "Δεν έχετε δικαίωμα" });
      return;
    }

    // For self-requests, if this service exists in the original Mitroo system,
    // the request must be accepted there too before we accept it locally.
    // If the remote system rejects it, surface its original message and do
    // not create the local enrollment record either.
    let externalApplicationId: number | undefined;
    if (isSelfRequest) {
      try {
        const applicationId = await syncEnrollmentRequestOrThrow(serviceId, targetUserId);
        if (applicationId != null) externalApplicationId = applicationId;
      } catch (syncErr) {
        const message = syncErr instanceof MitrooRemoteError
          ? syncErr.message
          : "Η αίτηση απέτυχε στο σύστημα Mitroo";
        res.status(502).json({ error: message });
        return;
      }
    }

    let record = await prisma.userService.create({
      data: {
        userId: targetUserId,
        serviceId,
        status,
        hours: service.defaultHours,
        hoursVol: service.defaultHoursVol,
        hoursTraining: service.defaultHoursTraining,
        hoursTrainers: service.defaultHoursTrainers,
        hoursTEP: service.defaultHoursTEP,
        ...(externalApplicationId != null ? { externalApplicationId } : {}),
      },
      include: {
        user: { select: { id: true, eame: true, forename: true, surname: true, email: true } },
      },
    });

    // Admin directly enrolling someone as "accepted" — sync to Mitroo before
    // committing locally; if it fails there, undo the local enrollment too.
    if (status === "accepted") {
      try {
        await writeBackAssignment(serviceId, targetUserId);
        record = await prisma.userService.update({
          where: { userId_serviceId: { userId: targetUserId, serviceId } },
          data: {},
          include: { user: { select: { id: true, eame: true, forename: true, surname: true, email: true } } },
        });
      } catch (syncErr) {
        await prisma.userService.delete({ where: { userId_serviceId: { userId: targetUserId, serviceId } } }).catch(() => {});
        const message = syncErr instanceof MitrooRemoteError
          ? syncErr.message
          : "Η αποδοχή απέτυχε στο σύστημα Mitroo";
        res.status(502).json({ error: message });
        return;
      }
    }

    res.status(201).json(record);

    // Fire-and-forget: notify missionAdmins (excluding the requester themselves)
    if (status === "requested") {
      const applicantName = `${record.user.forename} ${record.user.surname}`.trim();
      prisma.userDepartment.findMany({
        where: { departmentId: service.departmentId, role: "missionAdmin", userId: { not: targetUserId } },
        include: { user: { select: { id: true, email: true, forename: true, surname: true } } },
      }).then((admins) => {
        return Promise.allSettled(admins.flatMap((admin) => {
          const adminName = `${admin.user.forename} ${admin.user.surname}`.trim();
          return [
            sendServiceEnrollmentEmail(admin.user.email, adminName, applicantName, service.name).catch(() => {}),
            sendPushToUser(admin.user.id, {
              title: "Νέα αίτηση",
              body: `${applicantName} αιτήθηκε για "${service.name}"`,
              tag: `service-enroll-${serviceId}`,
              route: `/services/${serviceId}`,
            }).catch(() => {}),
          ];
        }));
      }).catch(() => {});
    }
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    if (err?.code === "P2002") { res.status(409).json({ error: "Ήδη εγγεγραμμένος σε αυτή την υπηρεσία" }); return; }
    throw err;
  }
});

// ── DELETE /api/services/:id/unenroll ────────────
// Current user withdraws their own "requested" enrollment
router.delete("/:id/unenroll", async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const serviceId = Number(req.params.id);
  const record = await prisma.userService.findUnique({
    where: { userId_serviceId: { userId, serviceId } },
    select: { externalApplicationId: true, status: true },
  });
  if (!record) { res.status(404).json({ error: "Δεν βρέθηκε εγγραφή" }); return; }
  if (record.status !== "requested") {
    res.status(409).json({ error: "Η αίτηση έχει ήδη διεκπεραιωθεί" });
    return;
  }
  const externalApplicationId = record.externalApplicationId ?? null;
  try {
    await writeBackUnenroll(serviceId, userId, externalApplicationId);
  } catch (syncErr) {
    const message = syncErr instanceof MitrooRemoteError
      ? syncErr.message
      : "Η ακύρωση απέτυχε στο σύστημα Mitroo";
    res.status(502).json({ error: message });
    return;
  }
  await prisma.userService.delete({ where: { userId_serviceId: { userId, serviceId } } });
  res.status(204).end();
});

// ── PATCH /api/services/:sid/users/:uid/status ──
router.patch("/:sid/users/:uid/status", async (req: Request, res: Response) => {
  try {
    const sid = Number(req.params.sid);
    const uid = Number(req.params.uid);
    const service = await prisma.service.findUnique({ where: { id: sid }, select: { departmentId: true, name: true } });
    if (!service) { res.status(404).json({ error: "Service not found" }); return; }
    if (!await requireServiceAdmin(req, res, service.departmentId)) return;
    const { status } = statusSchema.parse(req.body);

    const existing = await prisma.userService.findUnique({
      where: { userId_serviceId: { userId: uid, serviceId: sid } },
      select: { userId: true },
    });
    if (!existing) { res.status(404).json({ error: "Δεν βρέθηκε εγγραφή χρήστη" }); return; }

    // Sync to the original Mitroo system before committing the status change
    // locally; if it fails there, don't apply the change here either.
    if (status === "accepted") {
      try {
        await writeBackAssignment(sid, uid);
      } catch (syncErr) {
        const message = syncErr instanceof MitrooRemoteError
          ? syncErr.message
          : "Η αποδοχή απέτυχε στο σύστημα Mitroo";
        res.status(502).json({ error: message });
        return;
      }
    } else if (status === "rejected") {
      try {
        await writeBackRejection(sid, uid);
      } catch (syncErr) {
        const message = syncErr instanceof MitrooRemoteError
          ? syncErr.message
          : "Η απόρριψη απέτυχε στο σύστημα Mitroo";
        res.status(502).json({ error: message });
        return;
      }
    }

    const record = await prisma.userService.update({
      where: { userId_serviceId: { userId: uid, serviceId: sid } },
      data: { status },
      include: { user: { select: { id: true, email: true, forename: true, surname: true } } },
    });

    res.json(record);

    if (status === "accepted") {
      addToMissionChat(sid, uid).catch((e) => console.error("[service] addToMissionChat error:", e));
    } else if (status === "rejected") {
      // Remove user from the mission chat for this service
      removeFromMissionChat(sid, uid).catch((e) => console.error("[service] removeFromMissionChat error:", e));
    }

    // Fire-and-forget: notify the enrolled user on accept/reject
    if (status === "accepted" || status === "rejected") {
      const userName = `${record.user.forename} ${record.user.surname}`.trim();
      sendServiceStatusEmail(record.user.email, userName, service.name, status).catch(() => {});
      sendPushToUser(record.user.id, {
        title: "Ενημέρωση αίτησης",
        body: `Η αίτησή σας για "${service.name}" ${status === "accepted" ? "εγκρίθηκε" : "απορρίφθηκε"}`,
        tag: `service-status-${sid}`,
        route: `/services/${sid}`,
      }).catch(() => {});
    }
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2025') {
      res.status(404).json({ error: "Δεν βρέθηκε εγγραφή χρήστη" });
      return;
    }
    throw err;
  }
});

// ── PATCH /api/services/:sid/users/:uid/participation ──
router.patch("/:sid/users/:uid/participation", async (req: Request, res: Response) => {
  try {
    const sid = Number(req.params.sid);
    const uid = Number(req.params.uid);
    const service = await prisma.service.findUnique({
      where: { id: sid },
      select: { departmentId: true, lifecycleStatus: true },
    });
    if (!service) { res.status(404).json({ error: "Service not found" }); return; }
    if (!await requireServiceAdmin(req, res, service.departmentId)) return;
    if (service.lifecycleStatus !== "closed" && service.lifecycleStatus !== "completed") {
      res.status(409).json({ error: "Η υπηρεσία δεν είναι σε κατάσταση closed ή completed" });
      return;
    }
    const participationSchema = z.object({ status: z.enum(["participated", "not-participated"]) });
    const { status } = participationSchema.parse(req.body);
    const prismaStatus = status === "not-participated" ? "not_participated" : "participated";

    const existing = await prisma.userService.findUnique({
      where: { userId_serviceId: { userId: uid, serviceId: sid } },
      select: { userId: true },
    });
    if (!existing) { res.status(404).json({ error: "Δεν βρέθηκε εγγραφή συμμετοχής" }); return; }

    if (status === "not-participated") {
      try {
        await writeBackRejection(sid, uid);
      } catch (syncErr) {
        const message = syncErr instanceof MitrooRemoteError
          ? syncErr.message
          : "Η ενημέρωση απέτυχε στο σύστημα Mitroo";
        res.status(502).json({ error: message });
        return;
      }
    } else {
      try {
        await writeBackParticipation(sid, uid);
      } catch (syncErr) {
        const message = syncErr instanceof MitrooRemoteError
          ? syncErr.message
          : "Η ενημέρωση απέτυχε στο σύστημα Mitroo";
        res.status(502).json({ error: message });
        return;
      }
    }

    const record = await prisma.userService.update({
      where: { userId_serviceId: { userId: uid, serviceId: sid } },
      data: { status: prismaStatus },
      include: { user: { select: { id: true, eame: true, forename: true, surname: true } } },
    });
    res.json({ ...record, status: (record.status as string).replace(/_/g, '-') });
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2025') {
      res.status(404).json({ error: "Δεν βρέθηκε εγγραφή συμμετοχής" });
      return;
    }
    throw err;
  }
});

// ── PATCH /api/services/:sid/users/:uid/hours ───
router.patch("/:sid/users/:uid/hours", async (req: Request, res: Response) => {
  const sid = Number(req.params.sid);
  const uid = Number(req.params.uid);
  const service = await prisma.service.findUnique({ where: { id: sid }, select: { departmentId: true } });
  if (!service) { res.status(404).json({ error: "Service not found" }); return; }
  if (!await requireServiceAdmin(req, res, service.departmentId)) return;
  const { hours, hoursVol, hoursTraining, hoursTrainers, hoursTEP } = req.body;

  const previous = await prisma.userService.findUnique({
    where: { userId_serviceId: { userId: uid, serviceId: sid } },
    select: { hours: true, hoursVol: true, hoursTraining: true, hoursTrainers: true, hoursTEP: true },
  });
  if (!previous) { res.status(404).json({ error: "Δεν βρέθηκε εγγραφή συμμετοχής" }); return; }

  const record = await prisma.userService.update({
    where: { userId_serviceId: { userId: uid, serviceId: sid } },
    data: {
      ...(typeof hours === "number" && { hours }),
      ...(typeof hoursVol === "number" && { hoursVol }),
      ...(typeof hoursTraining === "number" && { hoursTraining }),
      ...(typeof hoursTrainers === "number" && { hoursTrainers }),
      ...(typeof hoursTEP === "number" && { hoursTEP }),
    },
  });

  // writeBackHoursUpdate reads the new hours values back from the DB, so the
  // local update must happen first — roll it back if the remote sync fails.
  try {
    await writeBackHoursUpdate(sid, uid);
  } catch (syncErr) {
    await prisma.userService.update({
      where: { userId_serviceId: { userId: uid, serviceId: sid } },
      data: previous,
    }).catch(() => {});
    const message = syncErr instanceof MitrooRemoteError
      ? syncErr.message
      : "Η ενημέρωση ωρών απέτυχε στο σύστημα Mitroo";
    res.status(502).json({ error: message });
    return;
  }

  res.json(record);
});

// ── DELETE /api/services/:sid/users/:uid ────────
router.delete("/:sid/users/:uid", async (req: Request, res: Response) => {
  const sid = Number(req.params.sid);
  const uid = Number(req.params.uid);
  console.log(`[service] DELETE /${sid}/users/${uid} — admin removing user from service`);
  const service = await prisma.service.findUnique({ where: { id: sid }, select: { departmentId: true } });
  if (!service) { res.status(404).json({ error: "Service not found" }); return; }
  if (!await requireServiceAdmin(req, res, service.departmentId)) return;

  // Read externalApplicationId before deleting the record
  const record = await prisma.userService.findUnique({
    where: { userId_serviceId: { userId: uid, serviceId: sid } },
    select: { externalApplicationId: true },
  });
  if (!record) { res.status(404).json({ error: "Δεν βρέθηκε εγγραφή χρήστη" }); return; }
  const externalApplicationId = record.externalApplicationId ?? null;
  console.log(`[service] DELETE /${sid}/users/${uid} — externalApplicationId from DB = ${externalApplicationId}`);

  try {
    await writeBackRejection(sid, uid, externalApplicationId);
  } catch (syncErr) {
    const message = syncErr instanceof MitrooRemoteError
      ? syncErr.message
      : "Η αφαίρεση απέτυχε στο σύστημα Mitroo";
    res.status(502).json({ error: message });
    return;
  }

  await prisma.userService.delete({
    where: { userId_serviceId: { userId: uid, serviceId: sid } },
  });
  res.status(204).end();
  console.log(`[service] DELETE /${sid}/users/${uid} — record deleted`);

  // Cleanup chat membership — internal, not a Mitroo interaction.
  removeFromMissionChat(sid, uid)
    .catch((e) => console.error("[service] removeFromMissionChat error:", e));
});

// ── PATCH /api/services/:id/responsible ──────────
router.patch("/:id/responsible", async (req: Request, res: Response) => {
  const serviceId = Number(req.params.id);
  const service = await prisma.service.findUnique({ where: { id: serviceId }, select: { departmentId: true } });
  if (!service) { res.status(404).json({ error: "Service not found" }); return; }
  if (!await requireServiceAdmin(req, res, service.departmentId)) return;
  const { responsibleUserId } = req.body;
  const updated = await prisma.service.update({
    where: { id: serviceId },
    data: { responsibleUserId: responsibleUserId ?? null },
    include: { responsibleUser: { select: { id: true, eame: true, forename: true, surname: true, imagePath: true } } },
  });
  res.json(updated);
});

// ── POST /api/services/:id/sync ─────────────────
router.post("/:id/sync", async (req: Request, res: Response) => {
  const sid = Number(req.params.id);
  if (!Number.isFinite(sid)) { res.status(400).json({ error: "Invalid service ID" }); return; }
  try {
    const svc = await prisma.service.findUnique({
      where: { id: sid },
      select: { departmentId: true, externalMissionId: true },
    });
    if (!svc) { res.status(404).json({ error: "Service not found" }); return; }
    if (!svc.externalMissionId) { res.status(400).json({ error: "Service has no external mission ID" }); return; }
    if (!await requireServiceAdmin(req, res, svc.departmentId)) return;
    const result = await syncSingleService(sid);
    res.json({ ok: true, ...result });
  } catch (err: any) {
    res.status(500).json({ error: "Sync failed", details: err?.message });
  }
});

export default router;
