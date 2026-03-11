import { Router, Request, Response } from "express";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate } from "../middleware/auth";

const router = Router();
router.use(authenticate);

const createSchema = z.object({
  name: z.string().min(1).max(255),
  type: z.string().min(1).max(100),
  registrationNumber: z.string().optional(),
  serialNumber: z.string().optional(),
  departmentId: z.number().int().optional().nullable(),
  meterType: z.enum(["km", "hours"]),
  currentMeter: z.number().min(0).optional(),
  location: z.string().optional(),
  description: z.string().optional(),
});

const logSchema = z.object({
  userId: z.number().int(),
  serviceId: z.number().int().optional().nullable(),
  startAt: z.string().datetime(),
  endAt: z.string().datetime(),
  meterStart: z.number().min(0),
  meterEnd: z.number().min(0),
  comment: z.string().optional(),
});

// ── GET /api/vehicles ───────────────────────────
router.get("/", async (req: Request, res: Response) => {
  const { departmentId } = req.query;
  const where: any = {};
  if (departmentId) where.departmentId = Number(departmentId);

  const vehicles = await prisma.vehicle.findMany({
    where,
    include: { department: { select: { id: true, name: true } } },
    orderBy: { name: "asc" },
  });
  res.json(vehicles);
});

// ── POST /api/vehicles ──────────────────────────
router.post("/", async (req: Request, res: Response) => {
  try {
    const data = createSchema.parse(req.body);
    const vehicle = await prisma.vehicle.create({
      data,
      include: { department: { select: { id: true, name: true } } },
    });
    res.status(201).json(vehicle);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// GET /api/vehicles/available — vehicles not currently in use
router.get("/available/list", async (req: Request, res: Response) => {
  const { search } = req.query;

  // Get IDs of vehicles currently in use (have open logs)
  const openLogs = await prisma.vehicleLog.findMany({
    where: { endAt: null },
    select: { vehicleId: true },
  });
  const inUseIds = openLogs.map((l) => l.vehicleId);

  const where: any = {};
  if (inUseIds.length > 0) {
    where.id = { notIn: inUseIds };
  }
  if (search && typeof search === "string" && search.trim()) {
    where.OR = [
      { name: { contains: search, mode: "insensitive" } },
      { registrationNumber: { contains: search, mode: "insensitive" } },
      { type: { contains: search, mode: "insensitive" } },
    ];
  }

  const vehicles = await prisma.vehicle.findMany({
    where,
    include: { department: { select: { id: true, name: true } } },
    orderBy: { name: "asc" },
  });
  res.json(vehicles);
});

// GET /api/vehicles/my/active — current user's active vehicle logs
router.get("/my/active", async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const logs = await prisma.vehicleLog.findMany({
    where: { userId, endAt: null },
    include: {
      vehicle: {
        select: {
          id: true, name: true, type: true, meterType: true,
          registrationNumber: true, currentMeter: true,
        },
      },
    },
    orderBy: { startAt: "desc" },
  });
  res.json(logs);
});

// ── GET /api/vehicles/:id ───────────────────────
router.get("/:id", async (req: Request, res: Response) => {
  const vehicle = await prisma.vehicle.findUnique({
    where: { id: Number(req.params.id) },
    include: {
      department: true,
      logs: {
        include: {
          user: { select: { id: true, forename: true, surname: true } },
          service: { select: { id: true, name: true } },
        },
        orderBy: { startAt: "desc" },
        take: 50,
      },
    },
  });
  if (!vehicle) { res.status(404).json({ error: "Vehicle not found" }); return; }
  res.json(vehicle);
});

// ── PATCH /api/vehicles/:id ─────────────────────
router.patch("/:id", async (req: Request, res: Response) => {
  try {
    const data = createSchema.partial().parse(req.body);
    const vehicle = await prisma.vehicle.update({
      where: { id: Number(req.params.id) },
      data,
      include: { department: { select: { id: true, name: true } } },
    });
    res.json(vehicle);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── DELETE /api/vehicles/:id ────────────────────
router.delete("/:id", async (req: Request, res: Response) => {
  await prisma.vehicle.delete({ where: { id: Number(req.params.id) } });
  res.status(204).end();
});

// ── Vehicle logs ────────────────────────────────

// ── GET /api/vehicles/:id/logs ──────────────────
router.get("/:id/logs", async (req: Request, res: Response) => {
  const logs = await prisma.vehicleLog.findMany({
    where: { vehicleId: Number(req.params.id) },
    include: {
      user: { select: { id: true, forename: true, surname: true } },
      service: { select: { id: true, name: true } },
    },
    orderBy: { startAt: "desc" },
  });
  res.json(logs);
});

// ── POST /api/vehicles/:id/logs ─────────────────
router.post("/:id/logs", async (req: Request, res: Response) => {
  try {
    const data = logSchema.parse(req.body);

    if (data.meterEnd < data.meterStart) {
      res.status(400).json({ error: "meter_end must be >= meter_start" });
      return;
    }
    if (new Date(data.endAt) <= new Date(data.startAt)) {
      res.status(400).json({ error: "end_at must be after start_at" });
      return;
    }

    const log = await prisma.vehicleLog.create({
      data: {
        vehicleId: Number(req.params.id),
        userId: data.userId,
        serviceId: data.serviceId,
        startAt: new Date(data.startAt),
        endAt: new Date(data.endAt),
        meterStart: data.meterStart,
        meterEnd: data.meterEnd,
        comment: data.comment,
      },
    });

    // Update vehicle current meter
    await prisma.vehicle.update({
      where: { id: Number(req.params.id) },
      data: { currentMeter: data.meterEnd },
    });

    res.status(201).json(log);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── DELETE /api/vehicles/logs/:logId ────────────
router.delete("/logs/:logId", async (req: Request, res: Response) => {
  await prisma.vehicleLog.delete({ where: { id: Number(req.params.logId) } });
  res.status(204).end();
});

// ── Self-service vehicle take / return ──────────

// POST /api/vehicles/:id/take — start using a vehicle
router.post("/:id/take", async (req: Request, res: Response) => {
  const vehicleId = Number(req.params.id);
  const userId = req.user!.userId;

  const vehicle = await prisma.vehicle.findUnique({ where: { id: vehicleId } });
  if (!vehicle) { res.status(404).json({ error: "Vehicle not found" }); return; }

  // Check vehicle isn't already in use (open log exists)
  const openLog = await prisma.vehicleLog.findFirst({
    where: { vehicleId, endAt: null },
  });
  if (openLog) {
    res.status(400).json({ error: "Το όχημα χρησιμοποιείται ήδη" });
    return;
  }

  const meterStart = req.body.meterStart != null ? Number(req.body.meterStart) : Number(vehicle.currentMeter);
  if (isNaN(meterStart) || meterStart < 0) {
    res.status(400).json({ error: "Invalid meterStart" });
    return;
  }

  const log = await prisma.vehicleLog.create({
    data: {
      vehicleId,
      userId,
      serviceId: req.body.serviceId ? Number(req.body.serviceId) : null,
      startAt: new Date(),
      meterStart,
      comment: req.body.comment,
    },
    include: {
      vehicle: { select: { id: true, name: true, type: true, meterType: true, registrationNumber: true } },
    },
  });

  res.json(log);
});

// POST /api/vehicles/:id/return — finish using a vehicle
router.post("/:id/return", async (req: Request, res: Response) => {
  const vehicleId = Number(req.params.id);
  const userId = req.user!.userId;

  // Find the user's open log for this vehicle
  const openLog = await prisma.vehicleLog.findFirst({
    where: { vehicleId, userId, endAt: null },
  });
  if (!openLog) {
    res.status(400).json({ error: "Δεν έχετε ανοιχτό αρχείο για αυτό το όχημα" });
    return;
  }

  const meterEnd = Number(req.body.meterEnd);
  if (isNaN(meterEnd) || meterEnd < 0) {
    res.status(400).json({ error: "Invalid meterEnd" });
    return;
  }
  if (meterEnd < Number(openLog.meterStart)) {
    res.status(400).json({ error: "Τα τελικά πρέπει να είναι >= αρχικά" });
    return;
  }

  const log = await prisma.vehicleLog.update({
    where: { id: openLog.id },
    data: {
      endAt: new Date(),
      meterEnd,
      comment: req.body.comment ?? openLog.comment,
    },
    include: {
      vehicle: { select: { id: true, name: true, type: true, meterType: true, registrationNumber: true } },
    },
  });

  // Update vehicle current meter
  await prisma.vehicle.update({
    where: { id: vehicleId },
    data: { currentMeter: meterEnd },
  });

  res.json(log);
});

export default router;
