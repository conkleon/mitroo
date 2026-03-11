import { Router, Request, Response } from "express";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate } from "../middleware/auth";

const router = Router();
router.use(authenticate);

/** Check whether the caller is a global admin or has `itemAdmin` role in any department. */
async function isItemManager(req: Request): Promise<boolean> {
  if (req.user?.isAdmin) return true;
  const count = await prisma.userDepartment.count({
    where: { userId: req.user!.userId, role: "itemAdmin" },
  });
  return count > 0;
}

const createSchema = z.object({
  name: z.string().min(1).max(255),
  departmentId: z.number().int(),
});

const updateSchema = z.object({
  name: z.string().min(1).max(255),
});

// ── GET /api/item-categories ──
// Returns all categories, optionally filtered by departmentId.
router.get("/", async (req: Request, res: Response) => {
  const { departmentId } = req.query;
  const where: any = {};
  if (departmentId) where.departmentId = Number(departmentId);

  const categories = await prisma.itemCategory.findMany({
    where,
    include: {
      department: { select: { id: true, name: true } },
      _count: { select: { items: true } },
    },
    orderBy: [{ departmentId: "asc" }, { name: "asc" }],
  });
  res.json(categories);
});

// ── POST /api/item-categories ──
router.post("/", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  try {
    const body = createSchema.parse(req.body);
    const category = await prisma.itemCategory.create({
      data: body,
      include: {
        department: { select: { id: true, name: true } },
        _count: { select: { items: true } },
      },
    });
    res.status(201).json(category);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Validation failed", details: err.errors });
      return;
    }
    if (err.code === "P2002") {
      res.status(409).json({ error: "Category with this name already exists in this department" });
      return;
    }
    throw err;
  }
});

// ── PATCH /api/item-categories/:id ──
router.patch("/:id", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  try {
    const body = updateSchema.parse(req.body);
    const category = await prisma.itemCategory.update({
      where: { id: Number(req.params.id) },
      data: body,
      include: {
        department: { select: { id: true, name: true } },
        _count: { select: { items: true } },
      },
    });
    res.json(category);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Validation failed", details: err.errors });
      return;
    }
    if (err.code === "P2002") {
      res.status(409).json({ error: "Category with this name already exists in this department" });
      return;
    }
    throw err;
  }
});

// ── DELETE /api/item-categories/:id ──
router.delete("/:id", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  await prisma.itemCategory.delete({ where: { id: Number(req.params.id) } });
  res.status(204).end();
});

export default router;
