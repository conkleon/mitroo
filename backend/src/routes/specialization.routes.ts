import { Router, Request, Response } from "express";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate } from "../middleware/auth";

const router = Router();
router.use(authenticate);

const createSchema = z.object({
  name: z.string().min(1).max(255),
  description: z.string().optional(),
  hoursTraining: z.number().int().min(0).optional(),
  rootId: z.number().int().optional().nullable(),
});

// ── GET /api/specializations ────────────────────
router.get("/", async (_req: Request, res: Response) => {
  const specs = await prisma.specialization.findMany({
    include: {
      root: { select: { id: true, name: true } },
      _count: { select: { children: true, users: true } },
    },
    orderBy: { name: "asc" },
  });
  res.json(specs);
});

// ── POST /api/specializations ───────────────────
router.post("/", async (req: Request, res: Response) => {
  try {
    const data = createSchema.parse(req.body);
    const spec = await prisma.specialization.create({ data });
    res.status(201).json(spec);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── GET /api/specializations/:id ────────────────
router.get("/:id", async (req: Request, res: Response) => {
  const spec = await prisma.specialization.findUnique({
    where: { id: Number(req.params.id) },
    include: {
      root: { select: { id: true, name: true } },
      children: { select: { id: true, name: true } },
      users: {
        include: { user: { select: { id: true, ename: true, forename: true, surname: true } } },
      },
    },
  });
  if (!spec) { res.status(404).json({ error: "Specialization not found" }); return; }
  res.json(spec);
});

// ── PATCH /api/specializations/:id ──────────────
router.patch("/:id", async (req: Request, res: Response) => {
  try {
    const data = createSchema.partial().parse(req.body);
    const spec = await prisma.specialization.update({ where: { id: Number(req.params.id) }, data });
    res.json(spec);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── DELETE /api/specializations/:id ─────────────
router.delete("/:id", async (req: Request, res: Response) => {
  await prisma.specialization.delete({ where: { id: Number(req.params.id) } });
  res.status(204).end();
});

export default router;
