import { Router, Request, Response } from "express";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate, requireAdmin } from "../middleware/auth";

const router = Router();
router.use(authenticate);

const createSchema = z.object({
  name: z.string().min(1).max(255),
  externalMissionTypeId: z.number().int().optional().nullable(),
  isDefaultVisible: z.boolean().optional(),
});

const updateSchema = createSchema.partial();

// ── GET /api/service-types ──────────────────────
router.get("/", async (_req: Request, res: Response) => {
  const types = await prisma.serviceType.findMany({
    include: {
      _count: { select: { specializations: true, services: true } },
    },
    orderBy: { name: "asc" },
  });
  res.json(types);
});

// ── POST /api/service-types ─────────────────────
router.post("/", requireAdmin, async (req: Request, res: Response) => {
  try {
    const data = createSchema.parse(req.body);
    const serviceType = await prisma.serviceType.create({ data });
    res.status(201).json(serviceType);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── PATCH /api/service-types/:id ────────────────
router.patch("/:id", requireAdmin, async (req: Request, res: Response) => {
  try {
    const data = updateSchema.parse(req.body);
    const serviceType = await prisma.serviceType.update({
      where: { id: Number(req.params.id) },
      data,
      include: { _count: { select: { specializations: true, services: true } } },
    });
    res.json(serviceType);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── DELETE /api/service-types/:id ───────────────
router.delete("/:id", requireAdmin, async (req: Request, res: Response) => {
  await prisma.serviceType.delete({ where: { id: Number(req.params.id) } });
  res.status(204).end();
});

// ── GET /api/service-types/:id/specializations ──
router.get("/:id/specializations", async (req: Request, res: Response) => {
  const rows = await prisma.specializationServiceType.findMany({
    where: { serviceTypeId: Number(req.params.id) },
    include: { specialization: { select: { id: true, name: true } } },
  });
  res.json(rows);
});

// ── PUT /api/service-types/:id/specializations ──
router.put("/:id/specializations", requireAdmin, async (req: Request, res: Response) => {
  const schema = z.object({ specializationIds: z.array(z.number().int()) });
  const { specializationIds } = schema.parse(req.body);
  const serviceTypeId = Number(req.params.id);

  await prisma.$transaction([
    prisma.specializationServiceType.deleteMany({ where: { serviceTypeId } }),
    prisma.specializationServiceType.createMany({
      data: specializationIds.map((sid) => ({ specializationId: sid, serviceTypeId })),
    }),
  ]);

  res.json({ ok: true });
});

export default router;
