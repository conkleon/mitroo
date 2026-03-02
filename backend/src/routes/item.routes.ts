import { Router, Request, Response } from "express";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate } from "../middleware/auth";

const router = Router();
router.use(authenticate);

const createSchema = z.object({
  name: z.string().min(1).max(255),
  description: z.string().optional(),
  barCode: z.string().optional(),
  containedById: z.number().int().optional().nullable(),
  isContainer: z.boolean().optional(),
  location: z.string().optional(),
});

const assignSchema = z.object({
  serviceId: z.number().int(),
  userId: z.number().int(),
  itemId: z.number().int(),
  comment: z.string().optional(),
});

// ── GET /api/items ──────────────────────────────
router.get("/", async (req: Request, res: Response) => {
  const { containerId, search } = req.query;
  const where: any = {};
  if (containerId) where.containedById = Number(containerId);
  if (search) where.name = { contains: String(search), mode: "insensitive" };

  const items = await prisma.item.findMany({
    where,
    include: { containedBy: { select: { id: true, name: true } }, _count: { select: { contents: true } } },
    orderBy: { name: "asc" },
  });
  res.json(items);
});

// ── POST /api/items ─────────────────────────────
router.post("/", async (req: Request, res: Response) => {
  try {
    const data = createSchema.parse(req.body);
    const item = await prisma.item.create({ data });
    res.status(201).json(item);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── GET /api/items/:id ──────────────────────────
router.get("/:id", async (req: Request, res: Response) => {
  const item = await prisma.item.findUnique({
    where: { id: Number(req.params.id) },
    include: {
      containedBy: { select: { id: true, name: true } },
      contents: { select: { id: true, name: true, barCode: true, imagePath: true } },
      itemServices: {
        include: {
          service: { select: { id: true, name: true } },
          user: { select: { id: true, forename: true, surname: true } },
        },
        orderBy: { assignedAt: "desc" },
      },
    },
  });
  if (!item) { res.status(404).json({ error: "Item not found" }); return; }
  res.json(item);
});

// ── PATCH /api/items/:id ────────────────────────
router.patch("/:id", async (req: Request, res: Response) => {
  try {
    const data = createSchema.partial().parse(req.body);
    const item = await prisma.item.update({ where: { id: Number(req.params.id) }, data });
    res.json(item);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── DELETE /api/items/:id ───────────────────────
router.delete("/:id", async (req: Request, res: Response) => {
  await prisma.item.delete({ where: { id: Number(req.params.id) } });
  res.status(204).end();
});

// ── Item ↔ Service assignments ──────────────────

// ── POST /api/items/assign ──────────────────────
router.post("/assign", async (req: Request, res: Response) => {
  try {
    const data = assignSchema.parse(req.body);
    const record = await prisma.itemService.create({
      data,
      include: { item: true, service: { select: { id: true, name: true } }, user: { select: { id: true, forename: true, surname: true } } },
    });
    res.status(201).json(record);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── DELETE /api/items/assign/:id ────────────────
router.delete("/assign/:id", async (req: Request, res: Response) => {
  await prisma.itemService.delete({ where: { id: Number(req.params.id) } });
  res.status(204).end();
});

export default router;
