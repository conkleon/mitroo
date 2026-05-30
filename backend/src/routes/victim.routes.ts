/// <reference path="../fhir/fhir4.d.ts" />
import { Router, Request, Response } from "express";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate, isMissionAdminInDepartment, authenticateOrApiKey } from "../middleware/auth";
import { victimToBundle } from "../fhir/victimToBundle";
import { bundleToVictim } from "../fhir/bundleToVictim";

const router = Router();

// ── FHIR routes (authenticateOrApiKey bypasses global JWT middleware) ──

// ── GET /api/victims/:id/fhir ────────────────────
router.get("/:id/fhir", authenticateOrApiKey, async (req: Request, res: Response) => {
  const victimId = parseInt(req.params.id as string);
  const userId = req.user!.userId;
  const isAdmin = req.user!.isAdmin;

  if (!(await canReadVictim(victimId, userId, isAdmin))) {
    res.status(403).json({ error: "Δεν έχετε δικαίωμα" });
    return;
  }

  const victim = await prisma.victim.findUnique({
    where: { id: victimId },
    include: { vitalSigns: true, treatments: true },
  });

  if (!victim) {
    res.status(404).json({ error: "Δεν βρέθηκε" });
    return;
  }

  const bundle = victimToBundle(victim);
  res.setHeader("Content-Type", "application/fhir+json");
  res.json(bundle);
});

// ── POST /api/victims/fhir ───────────────────────
router.post("/fhir", authenticateOrApiKey, async (req: Request, res: Response) => {
  const body = req.body;

  if (!body || body.resourceType !== "Bundle") {
    res.status(400).json({ error: "Expected FHIR R4 Bundle" });
    return;
  }

  let victimInput;
  try {
    victimInput = bundleToVictim(body as fhir4.Bundle);
  } catch (err: any) {
    res.status(400).json({ error: err.message ?? "Invalid Bundle" });
    return;
  }

  try {
    const data = createSchema.parse(victimInput);
    const victim = await prisma.victim.create({
      data: {
        ...data,
        dateOfBirth: data.dateOfBirth ? new Date(data.dateOfBirth) : undefined,
        createdById: req.user!.userId,
      },
    });
    res.status(201).json(victim);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(422).json({ error: "Μη έγκυρα δεδομένα", details: err.errors });
      return;
    }
    throw err;
  }
});

router.use(authenticate);

// ── Zod schemas ──────────────────────────────────

const createSchema = z.object({
  name: z.string().min(1).max(255),
  age: z.number().int().optional().nullable(),
  dateOfBirth: z.string().datetime().optional().nullable(),
  gender: z.enum(["male", "female", "other", "unknown"]).optional().nullable(),
  address: z.string().optional().nullable(),
  city: z.string().max(255).optional().nullable(),
  postalCode: z.string().max(20).optional().nullable(),
  telephone: z.string().max(30).optional().nullable(),
  emergencyContact: z.string().max(255).optional().nullable(),
  emergencyPhone: z.string().max(30).optional().nullable(),
  chiefComplaint: z.string().optional().nullable(),
  allergies: z.string().optional().nullable(),
  medications: z.string().optional().nullable(),
  medicalHistory: z.string().optional().nullable(),
  gcsEye: z.number().int().optional().nullable(),
  gcsVerbal: z.number().int().optional().nullable(),
  gcsMotor: z.number().int().optional().nullable(),
  gcsTotal: z.number().int().optional().nullable(),
  avpu: z.enum(["ALERT", "VOICE", "PAIN", "UNRESPONSIVE"]).optional().nullable(),
  latitude: z.number().optional().nullable(),
  longitude: z.number().optional().nullable(),
  locationNotes: z.string().optional().nullable(),
  serviceId: z.number().int().optional().nullable(),
  notes: z.string().optional().nullable(),
});

const vitalSignSchema = z.object({
  systolicBP: z.number().int().optional().nullable(),
  diastolicBP: z.number().int().optional().nullable(),
  heartRate: z.number().int().optional().nullable(),
  respiratoryRate: z.number().int().optional().nullable(),
  oxygenSat: z.number().int().optional().nullable(),
  temperature: z.number().optional().nullable(),
  bloodGlucose: z.number().optional().nullable(),
  painScore: z.number().int().optional().nullable(),
  measuredAt: z.string().datetime().optional(),
  notes: z.string().optional().nullable(),
  measuredBy: z.string().max(255).optional().nullable(),
});

const treatmentSchema = z.object({
  action: z.string().min(1),
  materialUsed: z.string().optional().nullable(),
  notes: z.string().optional().nullable(),
  itemId: z.number().int().optional().nullable(),
  consumedNote: z.string().optional().nullable(),
  performedAt: z.string().datetime().optional(),
  performedBy: z.string().max(255).optional().nullable(),
});

// ── Access helpers ───────────────────────────────

async function canReadVictim(
  victimId: number,
  userId: number,
  isAdmin: boolean,
): Promise<boolean> {
  if (isAdmin) return true;

  const victim = await prisma.victim.findUnique({
    where: { id: victimId },
    select: { createdById: true, serviceId: true },
  });
  if (!victim) return false;

  if (victim.createdById === userId) return true;

  if (victim.serviceId) {
    const service = await prisma.service.findUnique({
      where: { id: victim.serviceId },
      select: { departmentId: true },
    });
    if (service) {
      const isMissionAdmin = await isMissionAdminInDepartment(
        userId,
        service.departmentId,
      );
      if (isMissionAdmin) return true;

      const enrollment = await prisma.userService.findUnique({
        where: {
          userId_serviceId: { userId, serviceId: victim.serviceId },
        },
      });
      if (enrollment && enrollment.status === "accepted") return true;
    }
  }

  return false;
}

async function canWriteVictim(
  victimId: number,
  userId: number,
  isAdmin: boolean,
): Promise<{ allowed: boolean; isFinalized: boolean }> {
  const victim = await prisma.victim.findUnique({
    where: { id: victimId },
    select: { createdById: true, isFinalized: true, serviceId: true },
  });
  if (!victim) return { allowed: false, isFinalized: false };

  if (isAdmin) return { allowed: true, isFinalized: victim.isFinalized };

  if (victim.isFinalized) {
    if (victim.serviceId) {
      const service = await prisma.service.findUnique({
        where: { id: victim.serviceId },
        select: { departmentId: true },
      });
      if (service && await isMissionAdminInDepartment(userId, service.departmentId)) {
        return { allowed: true, isFinalized: true };
      }
    }
    return { allowed: false, isFinalized: true };
  }

  if (victim.createdById === userId) return { allowed: true, isFinalized: false };

  if (victim.serviceId) {
    const service = await prisma.service.findUnique({
      where: { id: victim.serviceId },
      select: { departmentId: true },
    });
    if (service && await isMissionAdminInDepartment(userId, service.departmentId)) {
      return { allowed: true, isFinalized: false };
    }
  }

  return { allowed: false, isFinalized: false };
}

// ── GET /api/victims ─────────────────────────────

router.get("/", async (req: Request, res: Response) => {
  const { serviceId, search, dateFrom, dateTo, status, createdByIds, page, limit } = req.query;
  const userId = req.user!.userId;
  const isAdmin = req.user!.isAdmin;

  try {
    const where: any = {};

    if (serviceId) {
      where.serviceId = Number(serviceId);
    }

    if (typeof createdByIds === "string" && createdByIds.trim().length > 0) {
      const ids = createdByIds.split(",").map((s) => Number(s.trim())).filter((n) => !isNaN(n));
      if (ids.length > 0) {
        where.createdById = { in: ids };
      }
    }

    // Search filter — case-insensitive name contains
    if (typeof search === "string" && search.trim().length > 0) {
      where.name = { contains: search.trim(), mode: "insensitive" };
    }

    // Date range filter
    if (typeof dateFrom === "string" && dateFrom) {
      const from = new Date(dateFrom);
      if (!isNaN(from.getTime())) {
        where.createdAt = { ...(where.createdAt ?? {}), gte: from };
      }
    }
    if (typeof dateTo === "string" && dateTo) {
      const to = new Date(dateTo);
      if (!isNaN(to.getTime())) {
        to.setHours(23, 59, 59, 999);
        where.createdAt = { ...(where.createdAt ?? {}), lte: to };
      }
    }

    // Status filter
    if (status === "open") {
      where.isFinalized = false;
    } else if (status === "finalized") {
      where.isFinalized = true;
    }

    // Access control (non-admin)
    if (!isAdmin) {
      const missionAdminDeptIds: number[] = [];
      const userDeptIds = await prisma.userDepartment.findMany({
        where: { userId, role: "missionAdmin" },
        select: { departmentId: true },
      });
      missionAdminDeptIds.push(...userDeptIds.map((d) => d.departmentId));

      where.OR = [
        { createdById: userId },
        ...(missionAdminDeptIds.length > 0
          ? [
              {
                service: {
                  departmentId: { in: missionAdminDeptIds },
                },
              },
            ]
          : []),
        {
          service: {
            userServices: {
              some: { userId, status: "accepted" },
            },
          },
        },
      ];
    }

    // Pagination
    const pageNum = Math.max(1, Number(page) || 1);
    const limitNum = Math.min(100, Math.max(1, Number(limit) || 20));
    const skip = (pageNum - 1) * limitNum;

    const [data, total] = await Promise.all([
      prisma.victim.findMany({
        where,
        orderBy: { createdAt: "desc" },
        skip,
        take: limitNum,
        select: {
          id: true,
          name: true,
          age: true,
          gender: true,
          chiefComplaint: true,
          isFinalized: true,
          createdAt: true,
          service: { select: { id: true, name: true } },
          createdBy: { select: { id: true, forename: true, surname: true } },
        },
      }),
      prisma.victim.count({ where }),
    ]);

    res.json({ data, total, page: pageNum, limit: limitNum });
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Μη έγκυρα δεδομένα", details: err.errors });
      return;
    }
    throw err;
  }
});

// ── GET /api/victims/:id ─────────────────────────

router.get("/:id", async (req: Request, res: Response) => {
  const id = Number(req.params.id);
  if (isNaN(id)) { res.status(400).json({ error: "Άκυρο ID" }); return; }

  const allowed = await canReadVictim(id, req.user!.userId, req.user!.isAdmin);
  if (!allowed) { res.status(404).json({ error: "Δεν βρέθηκε" }); return; }

  try {
    const victim = await prisma.victim.findUnique({
      where: { id },
      include: {
        createdBy: { select: { id: true, forename: true, surname: true } },
        finalizedBy: { select: { id: true, forename: true, surname: true } },
        service: { select: { id: true, name: true } },
        vitalSigns: { orderBy: { measuredAt: "desc" } },
        treatments: {
          orderBy: { performedAt: "desc" },
          include: { item: { select: { id: true, name: true } } },
        },
      },
    });
    if (!victim) { res.status(404).json({ error: "Δεν βρέθηκε" }); return; }
    res.json(victim);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Μη έγκυρα δεδομένα", details: err.errors });
      return;
    }
    throw err;
  }
});

// ── POST /api/victims ────────────────────────────

router.post("/", async (req: Request, res: Response) => {
  try {
    const data = createSchema.parse(req.body);

    let gcsTotal = data.gcsTotal;
    if (gcsTotal == null && data.gcsEye != null && data.gcsVerbal != null && data.gcsMotor != null) {
      gcsTotal = data.gcsEye + data.gcsVerbal + data.gcsMotor;
    }

    const dateOfBirth = "dateOfBirth" in data
      ? (data.dateOfBirth ? new Date(data.dateOfBirth) : null)
      : undefined;

    const victim = await prisma.victim.create({
      data: {
        ...data,
        dateOfBirth,
        gcsTotal,
        createdById: req.user!.userId,
      },
      select: { id: true },
    });

    res.status(201).json(victim);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Μη έγκυρα δεδομένα", details: err.errors });
      return;
    }
    throw err;
  }
});

// ── PATCH /api/victims/:id ────────────────────────

router.patch("/:id", async (req: Request, res: Response) => {
  const id = Number(req.params.id);
  if (isNaN(id)) { res.status(400).json({ error: "Άκυρο ID" }); return; }

  const access = await canWriteVictim(id, req.user!.userId, req.user!.isAdmin);
  if (!access.allowed) {
    res.status(access.isFinalized ? 403 : 404).json({
      error: access.isFinalized ? "Το περιστατικό έχει οριστικοποιηθεί" : "Δεν βρέθηκε",
    });
    return;
  }

  try {
    const data = createSchema.partial().parse(req.body);

    const existing = data.gcsEye !== undefined || data.gcsVerbal !== undefined || data.gcsMotor !== undefined
      ? await prisma.victim.findUnique({ where: { id }, select: { gcsEye: true, gcsVerbal: true, gcsMotor: true } })
      : null;

    let gcsTotal = data.gcsTotal;
    if (gcsTotal === undefined && existing) {
      const eye = data.gcsEye ?? existing.gcsEye;
      const verbal = data.gcsVerbal ?? existing.gcsVerbal;
      const motor = data.gcsMotor ?? existing.gcsMotor;
      if (eye != null && verbal != null && motor != null) {
        gcsTotal = eye + verbal + motor;
      }
    }

    const dateOfBirth = "dateOfBirth" in data
      ? (data.dateOfBirth ? new Date(data.dateOfBirth) : null)
      : undefined;

    const victim = await prisma.victim.update({
      where: { id },
      data: { ...data, dateOfBirth, gcsTotal },
    });

    res.json(victim);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Μη έγκυρα δεδομένα", details: err.errors });
      return;
    }
    if (err?.code === "P2025") {
      res.status(404).json({ error: "Δεν βρέθηκε" });
      return;
    }
    throw err;
  }
});

// ── DELETE /api/victims/:id ───────────────────────

router.delete("/:id", async (req: Request, res: Response) => {
  const id = Number(req.params.id);
  if (isNaN(id)) { res.status(400).json({ error: "Άκυρο ID" }); return; }

  const access = await canWriteVictim(id, req.user!.userId, req.user!.isAdmin);
  if (!access.allowed) {
    res.status(access.isFinalized ? 403 : 404).json({
      error: access.isFinalized ? "Το περιστατικό έχει οριστικοποιηθεί" : "Δεν βρέθηκε",
    });
    return;
  }

  try {
    await prisma.victim.delete({ where: { id } });
    res.status(204).send();
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Μη έγκυρα δεδομένα", details: err.errors });
      return;
    }
    if (err?.code === "P2025") {
      res.status(404).json({ error: "Δεν βρέθηκε" });
      return;
    }
    throw err;
  }
});

// ── POST /api/victims/:id/finalize ───────────────

router.post("/:id/finalize", async (req: Request, res: Response) => {
  const id = Number(req.params.id);
  if (isNaN(id)) { res.status(400).json({ error: "Άκυρο ID" }); return; }

  const userId = req.user!.userId;
  const isAdmin = req.user!.isAdmin;

  const victim = await prisma.victim.findUnique({
    where: { id },
    select: { createdById: true, isFinalized: true, serviceId: true },
  });
  if (!victim) { res.status(404).json({ error: "Δεν βρέθηκε" }); return; }

  if (victim.isFinalized) {
    res.status(400).json({ error: "Το περιστατικό έχει ήδη οριστικοποιηθεί" });
    return;
  }

  let allowed = isAdmin || victim.createdById === userId;
  if (!allowed && victim.serviceId) {
    const service = await prisma.service.findUnique({
      where: { id: victim.serviceId },
      select: { departmentId: true },
    });
    if (service) {
      allowed = await isMissionAdminInDepartment(userId, service.departmentId);
    }
  }

  if (!allowed) { res.status(403).json({ error: "Δεν έχετε δικαίωμα" }); return; }

  try {
    const updated = await prisma.victim.update({
      where: { id },
      data: {
        isFinalized: true,
        finalizedAt: new Date(),
        finalizedById: userId,
      },
    });
    res.json(updated);
  } catch (err: any) {
    if (err?.code === "P2025") { res.status(404).json({ error: "Δεν βρέθηκε" }); return; }
    throw err;
  }
});

// ── POST /api/victims/:id/vital-signs ─────────────

router.post("/:id/vital-signs", async (req: Request, res: Response) => {
  const victimId = Number(req.params.id);
  if (isNaN(victimId)) { res.status(400).json({ error: "Άκυρο ID" }); return; }

  const access = await canWriteVictim(victimId, req.user!.userId, req.user!.isAdmin);
  if (!access.allowed) {
    res.status(access.isFinalized ? 403 : 404).json({
      error: access.isFinalized ? "Το περιστατικό έχει οριστικοποιηθεί" : "Δεν βρέθηκε",
    });
    return;
  }

  try {
    const data = vitalSignSchema.parse(req.body);
    const measuredAt = data.measuredAt ? new Date(data.measuredAt) : undefined;

    const vs = await prisma.vitalSign.create({
      data: { ...data, measuredAt, victimId },
    });
    res.status(201).json(vs);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Μη έγκυρα δεδομένα", details: err.errors });
      return;
    }
    throw err;
  }
});

// ── DELETE /api/victims/:id/vital-signs/:vsId ──────

router.delete("/:id/vital-signs/:vsId", async (req: Request, res: Response) => {
  const victimId = Number(req.params.id);
  const vsId = Number(req.params.vsId);
  if (isNaN(victimId) || isNaN(vsId)) { res.status(400).json({ error: "Άκυρο ID" }); return; }

  const access = await canWriteVictim(victimId, req.user!.userId, req.user!.isAdmin);
  if (!access.allowed) {
    res.status(access.isFinalized ? 403 : 404).json({
      error: access.isFinalized ? "Το περιστατικό έχει οριστικοποιηθεί" : "Δεν βρέθηκε",
    });
    return;
  }

  try {
    await prisma.vitalSign.delete({ where: { id: vsId, victimId } });
    res.status(204).end();
  } catch (err: any) {
    if (err?.code === "P2025") { res.status(404).json({ error: "Δεν βρέθηκε" }); return; }
    throw err;
  }
});

// ── POST /api/victims/:id/treatments ──────────────

router.post("/:id/treatments", async (req: Request, res: Response) => {
  const victimId = Number(req.params.id);
  if (isNaN(victimId)) { res.status(400).json({ error: "Άκυρο ID" }); return; }

  const access = await canWriteVictim(victimId, req.user!.userId, req.user!.isAdmin);
  if (!access.allowed) {
    res.status(access.isFinalized ? 403 : 404).json({
      error: access.isFinalized ? "Το περιστατικό έχει οριστικοποιηθεί" : "Δεν βρέθηκε",
    });
    return;
  }

  try {
    const data = treatmentSchema.parse(req.body);
    const performedAt = data.performedAt ? new Date(data.performedAt) : undefined;

    const treatment = await prisma.treatment.create({
      data: { ...data, performedAt, victimId },
      include: { item: { select: { id: true, name: true } } },
    });
    res.status(201).json(treatment);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Μη έγκυρα δεδομένα", details: err.errors });
      return;
    }
    throw err;
  }
});

// ── DELETE /api/victims/:id/treatments/:tId ────────

router.delete("/:id/treatments/:tId", async (req: Request, res: Response) => {
  const victimId = Number(req.params.id);
  const tId = Number(req.params.tId);
  if (isNaN(victimId) || isNaN(tId)) { res.status(400).json({ error: "Άκυρο ID" }); return; }

  const access = await canWriteVictim(victimId, req.user!.userId, req.user!.isAdmin);
  if (!access.allowed) {
    res.status(access.isFinalized ? 403 : 404).json({
      error: access.isFinalized ? "Το περιστατικό έχει οριστικοποιηθεί" : "Δεν βρέθηκε",
    });
    return;
  }

  try {
    await prisma.treatment.delete({ where: { id: tId, victimId } });
    res.status(204).end();
  } catch (err: any) {
    if (err?.code === "P2025") { res.status(404).json({ error: "Δεν βρέθηκε" }); return; }
    throw err;
  }
});

export default router;
