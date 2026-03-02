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

export default router;
