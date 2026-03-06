import { Router, Request, Response } from "express";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate } from "../middleware/auth";

const router = Router();
router.use(authenticate);

const createSchema = z.object({
  departmentId: z.number().int(),
  name: z.string().min(1).max(255),
  description: z.string().optional(),
  location: z.string().optional(),
  carrier: z.string().max(255).optional(),
  defaultHours: z.number().int().min(0).optional(),
  defaultHoursVol: z.number().int().min(0).optional(),
  defaultHoursTraining: z.number().int().min(0).optional(),
  defaultHoursTrainers: z.number().int().min(0).optional(),
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

// ── GET /api/services ───────────────────────────
router.get("/", async (req: Request, res: Response) => {
  const { departmentId } = req.query;
  const where: any = {};
  if (departmentId) where.departmentId = Number(departmentId);

  const services = await prisma.service.findMany({
    where,
    include: {
      department: { select: { id: true, name: true } },
      visibility: { include: { specialization: { select: { id: true, name: true } } } },
      _count: { select: { userServices: true, itemServices: true } },
    },
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
    const service = await prisma.service.create({
      data: {
        ...data,
        startAt: data.startAt ? new Date(data.startAt) : undefined,
        endAt: data.endAt ? new Date(data.endAt) : undefined,
      },
      include: { department: { select: { id: true, name: true } } },
    });
    res.status(201).json(service);
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
      userServices: {
        include: { user: { select: { id: true, ename: true, forename: true, surname: true, imagePath: true } } },
      },
      itemServices: { include: { item: true, user: { select: { id: true, forename: true, surname: true } } } },
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
    const data = createSchema.partial().parse(req.body);
    const service = await prisma.service.update({
      where: { id: Number(req.params.id) },
      data: {
        ...data,
        startAt: data.startAt ? new Date(data.startAt) : undefined,
        endAt: data.endAt ? new Date(data.endAt) : undefined,
      },
    });
    res.json(service);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── DELETE /api/services/:id ────────────────────
router.delete("/:id", async (req: Request, res: Response) => {
  await prisma.service.delete({ where: { id: Number(req.params.id) } });
  res.status(204).end();
});

// ── POST /api/services/:id/enroll ───────────────
// User requests to join (or admin directly accepts)
router.post("/:id/enroll", async (req: Request, res: Response) => {
  try {
    const data = enrollSchema.parse(req.body);
    const serviceId = Number(req.params.id);

    // Grab default hours from the service
    const service = await prisma.service.findUnique({ where: { id: serviceId } });
    if (!service) { res.status(404).json({ error: "Service not found" }); return; }

    const record = await prisma.userService.create({
      data: {
        userId: data.userId,
        serviceId,
        status: data.status ?? "requested",
        hours: service.defaultHours,
        hoursVol: service.defaultHoursVol,
        hoursTraining: service.defaultHoursTraining,
        hoursTrainers: service.defaultHoursTrainers,
      },
      include: { user: { select: { id: true, ename: true, forename: true, surname: true } } },
    });
    res.status(201).json(record);
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
    const { status } = statusSchema.parse(req.body);
    const record = await prisma.userService.update({
      where: { userId_serviceId: { userId: Number(req.params.uid), serviceId: Number(req.params.sid) } },
      data: { status },
    });
    res.json(record);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── PATCH /api/services/:sid/users/:uid/hours ───
router.patch("/:sid/users/:uid/hours", async (req: Request, res: Response) => {
  const { hours, hoursVol, hoursTraining, hoursTrainers } = req.body;
  const record = await prisma.userService.update({
    where: { userId_serviceId: { userId: Number(req.params.uid), serviceId: Number(req.params.sid) } },
    data: {
      ...(typeof hours === "number" && { hours }),
      ...(typeof hoursVol === "number" && { hoursVol }),
      ...(typeof hoursTraining === "number" && { hoursTraining }),
      ...(typeof hoursTrainers === "number" && { hoursTrainers }),
    },
  });
  res.json(record);
});

// ── DELETE /api/services/:sid/users/:uid ────────
router.delete("/:sid/users/:uid", async (req: Request, res: Response) => {
  await prisma.userService.delete({
    where: { userId_serviceId: { userId: Number(req.params.uid), serviceId: Number(req.params.sid) } },
  });
  res.status(204).end();
});

// ── Service visibility (specialization requirements) ──

// ── POST /api/services/:id/visibility ───────────
router.post("/:id/visibility", async (req: Request, res: Response) => {
  const { specializationId } = req.body;
  const serviceId = Number(req.params.id);
  const specId = Number(specializationId);
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
  await prisma.serviceVisibility.delete({
    where: {
      serviceId_specializationId: { serviceId: Number(req.params.sid), specializationId: Number(req.params.specId) },
    },
  });
  res.status(204).end();
});

export default router;
