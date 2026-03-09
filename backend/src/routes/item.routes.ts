import { Router, Request, Response } from "express";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate } from "../middleware/auth";

const router = Router();
router.use(authenticate);

// ── Helpers ─────────────────────────────────────

/** Check whether the caller is a global admin or has `itemAdmin` role in any department. */
async function isItemManager(req: Request): Promise<boolean> {
  if (req.user?.isAdmin) return true;
  const count = await prisma.userDepartment.count({
    where: { userId: req.user!.userId, role: "itemAdmin" },
  });
  return count > 0;
}

// Shared include used when returning a single item with full relations.
const ITEM_DETAIL_INCLUDE = {
  containedBy: { select: { id: true, name: true } },
  contents: {
    select: {
      id: true,
      name: true,
      barCode: true,
      imagePath: true,
      isContainer: true,
      location: true,
      assignedTo: { select: { id: true, forename: true, surname: true } },
    },
  },
  assignedTo: { select: { id: true, forename: true, surname: true, ename: true } },
  itemServices: {
    include: {
      service: { select: { id: true, name: true } },
      user: { select: { id: true, forename: true, surname: true } },
    },
    orderBy: { assignedAt: "desc" as const },
  },
};

// ── Schemas ─────────────────────────────────────

const createSchema = z.object({
  name: z.string().min(1).max(255),
  description: z.string().optional(),
  barCode: z.string().optional().nullable(),
  containedById: z.number().int().optional().nullable(),
  isContainer: z.boolean().optional(),
  location: z.string().optional().nullable(),
  expirationDate: z.string().optional().nullable(), // ISO-8601
  availableForAssignment: z.boolean().optional(),
});

const assignServiceSchema = z.object({
  serviceId: z.number().int(),
  userId: z.number().int(),
  itemId: z.number().int(),
  comment: z.string().optional(),
});

const assignUserSchema = z.object({
  userId: z.number().int(),
});

// ── GET /api/items ──────────────────────────────
router.get("/", async (req: Request, res: Response) => {
  const { containerId, search, barCode, available } = req.query;
  const where: any = {};
  if (containerId) where.containedById = Number(containerId);
  if (search) where.name = { contains: String(search), mode: "insensitive" };
  if (barCode) where.barCode = String(barCode);
  if (available === "true") {
    where.availableForAssignment = true;
    where.assignedToId = null; // only show unassigned items
  }

  const items = await prisma.item.findMany({
    where,
    include: {
      containedBy: { select: { id: true, name: true } },
      assignedTo: { select: { id: true, forename: true, surname: true } },
      _count: { select: { contents: true } },
    },
    orderBy: { name: "asc" },
  });
  res.json(items);
});

// ── GET /api/items/barcode/:code ────────────────
// Returns all items matching a barcode (useful after scanning a barcode)
router.get("/barcode/:code", async (req: Request, res: Response) => {
  const items = await prisma.item.findMany({
    where: { barCode: String(req.params.code) },
    include: {
      containedBy: { select: { id: true, name: true } },
      assignedTo: { select: { id: true, forename: true, surname: true } },
      _count: { select: { contents: true } },
    },
    orderBy: { name: "asc" },
  });
  res.json(items);
});

// ── POST /api/items ─────────────────────────────
router.post("/", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  try {
    const body = createSchema.parse(req.body);
    const data: any = { ...body };
    // Convert ISO string to Date
    if (data.expirationDate) data.expirationDate = new Date(data.expirationDate);
    // If containedById is set, verify the target is a container
    if (data.containedById) {
      const parent = await prisma.item.findUnique({ where: { id: data.containedById } });
      if (!parent || !parent.isContainer) {
        res.status(400).json({ error: "Target item is not a container" });
        return;
      }
    }
    const item = await prisma.item.create({ data, include: ITEM_DETAIL_INCLUDE });
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
    include: ITEM_DETAIL_INCLUDE,
  });
  if (!item) { res.status(404).json({ error: "Item not found" }); return; }
  res.json(item);
});

// ── PATCH /api/items/:id ────────────────────────
router.patch("/:id", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  try {
    const body = createSchema.partial().parse(req.body);
    const data: any = { ...body };
    if (data.expirationDate !== undefined) {
      data.expirationDate = data.expirationDate ? new Date(data.expirationDate) : null;
    }
    if (data.containedById) {
      const parent = await prisma.item.findUnique({ where: { id: data.containedById } });
      if (!parent || !parent.isContainer) {
        res.status(400).json({ error: "Target item is not a container" });
        return;
      }
    }
    const item = await prisma.item.update({
      where: { id: Number(req.params.id) },
      data,
      include: ITEM_DETAIL_INCLUDE,
    });
    res.json(item);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── DELETE /api/items/:id ───────────────────────
router.delete("/:id", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  await prisma.item.delete({ where: { id: Number(req.params.id) } });
  res.status(204).end();
});

// ── Self-assign: regular user claims an available item ─────

// POST /api/items/:id/self-assign
router.post("/:id/self-assign", async (req: Request, res: Response) => {
  const itemId = Number(req.params.id);
  const userId = req.user!.userId;

  const item = await prisma.item.findUnique({ where: { id: itemId } });
  if (!item) { res.status(404).json({ error: "Item not found" }); return; }
  if (!item.availableForAssignment) {
    res.status(400).json({ error: "Item is not available for assignment" }); return;
  }
  if (item.assignedToId) {
    res.status(400).json({ error: "Item is already assigned to someone" }); return;
  }

  const updated = await prisma.item.update({
    where: { id: itemId },
    data: { assignedToId: userId },
    include: ITEM_DETAIL_INCLUDE,
  });
  res.json(updated);
});

// POST /api/items/:id/self-unassign
router.post("/:id/self-unassign", async (req: Request, res: Response) => {
  const itemId = Number(req.params.id);
  const userId = req.user!.userId;

  const item = await prisma.item.findUnique({ where: { id: itemId } });
  if (!item) { res.status(404).json({ error: "Item not found" }); return; }
  if (item.assignedToId !== userId) {
    res.status(403).json({ error: "Item is not assigned to you" }); return;
  }

  const updated = await prisma.item.update({
    where: { id: itemId },
    data: { assignedToId: null },
    include: ITEM_DETAIL_INCLUDE,
  });
  res.json(updated);
});

// ── Assign / unassign item to a user ────────────

// POST /api/items/:id/assign-user
router.post("/:id/assign-user", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  try {
    const { userId } = assignUserSchema.parse(req.body);
    const item = await prisma.item.update({
      where: { id: Number(req.params.id) },
      data: { assignedToId: userId },
      include: ITEM_DETAIL_INCLUDE,
    });
    res.json(item);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// DELETE /api/items/:id/assign-user
router.delete("/:id/assign-user", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  const item = await prisma.item.update({
    where: { id: Number(req.params.id) },
    data: { assignedToId: null },
    include: ITEM_DETAIL_INCLUDE,
  });
  res.json(item);
});

// ── Move item into / out of a container ─────────

// PATCH /api/items/:id/move
router.patch("/:id/move", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  const { containerId } = req.body; // null = remove from container
  if (containerId != null) {
    const parent = await prisma.item.findUnique({ where: { id: containerId } });
    if (!parent || !parent.isContainer) {
      res.status(400).json({ error: "Target item is not a container" });
      return;
    }
    // Prevent placing a container inside itself
    if (containerId === Number(req.params.id)) {
      res.status(400).json({ error: "Cannot place an item inside itself" });
      return;
    }
  }
  const item = await prisma.item.update({
    where: { id: Number(req.params.id) },
    data: { containedById: containerId ?? null },
    include: ITEM_DETAIL_INCLUDE,
  });
  res.json(item);
});

// ── Item ↔ Service assignments ──────────────────

// POST /api/items/assign
router.post("/assign", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  try {
    const data = assignServiceSchema.parse(req.body);
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

// DELETE /api/items/assign/:id
router.delete("/assign/:id", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  await prisma.itemService.delete({ where: { id: Number(req.params.id) } });
  res.status(204).end();
});

export default router;
