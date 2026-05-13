import { Router, Request, Response } from "express";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate, isMissionAdminInDepartment } from "../middleware/auth";
import { sendServiceEnrollmentEmail, sendServiceStatusEmail } from "../lib/email";
import { sendPushToUser } from "../lib/webpush";
import {
  writeBackNewService,
  writeBackAssignment,
  writeBackRejection,
  writeBackHoursUpdate,
  writeBackServiceDelete,
} from "../lib/mitrooSync";

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

// ── GET /api/services ───────────────────────────
router.get("/", async (req: Request, res: Response) => {
  const { departmentId, includeEnrollments, fromDate, toDate, specializationId, pastOnly, includeExpired } = req.query;
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

  // Filter by specialization visibility
  if (specializationId) {
    where.visibility = {
      some: { specializationId: Number(specializationId) },
    };
  }

  const includeBlock: any = {
    department: { select: { id: true, name: true } },
    responsibleUser: { select: { id: true, eame: true, forename: true, surname: true, imagePath: true } },
    visibility: { include: { specialization: { select: { id: true, name: true } } } },
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

  const services = await prisma.service.findMany({
    where,
    include: includeBlock,
    orderBy: { startAt: "asc" },
  });
  res.json(services);
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
          // services with NO visibility restrictions → visible to all dept members
          { visibility: { none: {} } },
          // services whose required specializations overlap the user's
          { visibility: { some: { specializationId: { in: specIds } } } },
        ],
      },
    ];
  }

  const services = await prisma.service.findMany({
    where,
    include: {
      department: { select: { id: true, name: true } },
      responsibleUser: { select: { id: true, eame: true, forename: true, surname: true, imagePath: true } },
      visibility: { include: { specialization: { select: { id: true, name: true } } } },
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
    res.status(201).json(service);

    // Fire-and-forget: create corresponding mission+shift in original Mitroo
    writeBackNewService(service.id).catch(() => {});
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── GET /api/services/:id ───────────────────────
router.get("/:id", async (req: Request, res: Response) => {
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
      visibility: { include: { specialization: true } },
    },
  });
  if (!service) { res.status(404).json({ error: "Service not found" }); return; }
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

// ── DELETE /api/services/:id ────────────────────
router.delete("/:id", async (req: Request, res: Response) => {
  const service = await prisma.service.findUnique({ where: { id: Number(req.params.id) }, select: { departmentId: true } });
  if (!service) { res.status(404).json({ error: "Service not found" }); return; }
  if (!await requireServiceAdmin(req, res, service.departmentId)) return;
  try {
    await writeBackServiceDelete(Number(req.params.id));
  } catch (e) {
    console.error("[service] writeBackServiceDelete error:", e);
  }
  await prisma.service.delete({ where: { id: Number(req.params.id) } });
  res.status(204).end();
});

// ── POST /api/services/:id/enroll ───────────────
// User requests to join (or admin directly accepts)
router.post("/:id/enroll", async (req: Request, res: Response) => {
  try {
    const requesterId = req.user!.userId;
    const serviceId = Number(req.params.id);

    const service = await prisma.service.findUnique({
      where: { id: serviceId },
      include: { department: { select: { id: true, name: true } } },
    });
    if (!service) { res.status(404).json({ error: "Service not found" }); return; }

    const isServiceAdmin = req.user!.isAdmin || await isMissionAdminInDepartment(requesterId, service.departmentId);

    let targetUserId: number;
    let status: "requested" | "accepted" | "rejected";

    if (isServiceAdmin) {
      const data = enrollSchema.parse(req.body);
      targetUserId = data.userId ?? requesterId;
      status = data.status ?? "requested";
    } else {
      targetUserId = requesterId;
      status = "requested";
      const membership = await prisma.userDepartment.count({
        where: { userId: requesterId, departmentId: service.departmentId },
      });
      if (!membership) {
        res.status(403).json({ error: "Δεν ανήκετε σε αυτό το τμήμα" });
        return;
      }
    }

    const record = await prisma.userService.create({
      data: {
        userId: targetUserId,
        serviceId,
        status,
        hours: service.defaultHours,
        hoursVol: service.defaultHoursVol,
        hoursTraining: service.defaultHoursTraining,
        hoursTrainers: service.defaultHoursTrainers,
        hoursTEP: service.defaultHoursTEP,
      },
      include: {
        user: { select: { id: true, eame: true, forename: true, surname: true, email: true } },
      },
    });

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
  });
  if (!record) { res.status(404).json({ error: "Δεν βρέθηκε εγγραφή" }); return; }
  if (record.status !== "requested") {
    res.status(409).json({ error: "Η αίτηση έχει ήδη διεκπεραιωθεί" });
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
    const record = await prisma.userService.update({
      where: { userId_serviceId: { userId: uid, serviceId: sid } },
      data: { status },
      include: { user: { select: { id: true, email: true, forename: true, surname: true } } },
    });

    res.json(record);

    // Fire-and-forget: approve shift application in original Mitroo when accepted
    if (status === "accepted") {
      writeBackAssignment(sid, uid).catch((e) => console.error("[service] writeBackAssignment error:", e));
    } else if (status === "rejected") {
      writeBackRejection(sid, uid).catch((e) => console.error("[service] writeBackRejection error:", e));
    }

    // Fire-and-forget: notify the enrolled user on accept/reject
    if (status === "accepted" || status === "rejected") {
      const userName = `${record.user.forename} ${record.user.surname}`.trim();
      sendServiceStatusEmail(record.user.email, userName, service.name, status).catch(() => {});
      sendPushToUser(record.user.id, {
        title: "Ενημέρωση αίτησης",
        body: `Η αίτησή σας για "${service.name}" ${status === "accepted" ? "εγκρίθηκε" : "απορρίφθηκε"}`,
      }).catch(() => {});
    }
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── PATCH /api/services/:sid/users/:uid/hours ───
router.patch("/:sid/users/:uid/hours", async (req: Request, res: Response) => {
  const service = await prisma.service.findUnique({ where: { id: Number(req.params.sid) }, select: { departmentId: true } });
  if (!service) { res.status(404).json({ error: "Service not found" }); return; }
  if (!await requireServiceAdmin(req, res, service.departmentId)) return;
  const { hours, hoursVol, hoursTraining, hoursTrainers, hoursTEP } = req.body;
  const record = await prisma.userService.update({
    where: { userId_serviceId: { userId: Number(req.params.uid), serviceId: Number(req.params.sid) } },
    data: {
      ...(typeof hours === "number" && { hours }),
      ...(typeof hoursVol === "number" && { hoursVol }),
      ...(typeof hoursTraining === "number" && { hoursTraining }),
      ...(typeof hoursTrainers === "number" && { hoursTrainers }),
      ...(typeof hoursTEP === "number" && { hoursTEP }),
    },
  });
  res.json(record);

  writeBackHoursUpdate(Number(req.params.sid), Number(req.params.uid))
    .catch((e) => console.error("[service] writeBackHoursUpdate error:", e));
});

// ── DELETE /api/services/:sid/users/:uid ────────
router.delete("/:sid/users/:uid", async (req: Request, res: Response) => {
  const service = await prisma.service.findUnique({ where: { id: Number(req.params.sid) }, select: { departmentId: true } });
  if (!service) { res.status(404).json({ error: "Service not found" }); return; }
  if (!await requireServiceAdmin(req, res, service.departmentId)) return;
  await prisma.userService.delete({
    where: { userId_serviceId: { userId: Number(req.params.uid), serviceId: Number(req.params.sid) } },
  });
  res.status(204).end();
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

// ── Service visibility (specialization requirements) ──

// ── POST /api/services/:id/visibility ───────────
router.post("/:id/visibility", async (req: Request, res: Response) => {
  const serviceId = Number(req.params.id);
  const service = await prisma.service.findUnique({ where: { id: serviceId }, select: { departmentId: true } });
  if (!service) { res.status(404).json({ error: "Service not found" }); return; }
  if (!await requireServiceAdmin(req, res, service.departmentId)) return;
  const specId = Number(req.body.specializationId);
  const record = await prisma.serviceVisibility.upsert({
    where: { serviceId_specializationId: { serviceId, specializationId: specId } },
    update: {},
    create: { serviceId, specializationId: specId },
    include: { specialization: true },
  });
  res.status(201).json(record);
});

// ── DELETE /api/services/:sid/visibility/:specId ─
router.delete("/:sid/visibility/:specId", async (req: Request, res: Response) => {
  const serviceId = Number(req.params.sid);
  const service = await prisma.service.findUnique({ where: { id: serviceId }, select: { departmentId: true } });
  if (!service) { res.status(404).json({ error: "Service not found" }); return; }
  if (!await requireServiceAdmin(req, res, service.departmentId)) return;
  await prisma.serviceVisibility.delete({
    where: {
      serviceId_specializationId: { serviceId, specializationId: Number(req.params.specId) },
    },
  });
  res.status(204).end();
});

export default router;
