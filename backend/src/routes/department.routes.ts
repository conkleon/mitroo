import { Router, Request, Response } from "express";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate, requireAdmin } from "../middleware/auth";

const router = Router();
router.use(authenticate);

const createSchema = z.object({
  name: z.string().min(1).max(255),
  description: z.string().optional(),
  location: z.string().optional(),
});

const memberSchema = z.object({
  userId: z.number().int(),
  role: z.enum(["missionAdmin", "itemAdmin", "volunteer"]),
});

// ── GET /api/departments ────────────────────────
router.get("/", async (_req: Request, res: Response) => {
  const departments = await prisma.department.findMany({
    include: {
      _count: { select: { services: true, userDepartments: true, vehicles: true } },
    },
    orderBy: { name: "asc" },
  });
  res.json(departments);
});

// ── POST /api/departments ───────────────────────
router.post("/", requireAdmin, async (req: Request, res: Response) => {
  try {
    const data = createSchema.parse(req.body);
    const dept = await prisma.department.create({ data });
    res.status(201).json(dept);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── GET /api/departments/:id ────────────────────
router.get("/:id", async (req: Request, res: Response) => {
  const dept = await prisma.department.findUnique({
    where: { id: Number(req.params.id) },
    include: {
      services: { orderBy: { startAt: "desc" }, take: 20 },
      userDepartments: {
        include: { user: { select: { id: true, ename: true, forename: true, surname: true, imagePath: true } } },
      },
      vehicles: true,
    },
  });
  if (!dept) { res.status(404).json({ error: "Department not found" }); return; }
  res.json(dept);
});

// ── PATCH /api/departments/:id ──────────────────
router.patch("/:id", async (req: Request, res: Response) => {
  try {
    const data = createSchema.partial().parse(req.body);
    const dept = await prisma.department.update({ where: { id: Number(req.params.id) }, data });
    res.json(dept);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── DELETE /api/departments/:id ─────────────────
router.delete("/:id", requireAdmin, async (req: Request, res: Response) => {
  await prisma.department.delete({ where: { id: Number(req.params.id) } });
  res.status(204).end();
});

// ── GET /api/departments/:id/members ────────────
router.get("/:id/members", async (req: Request, res: Response) => {
  const members = await prisma.userDepartment.findMany({
    where: { departmentId: Number(req.params.id) },
    include: { user: { select: { id: true, ename: true, forename: true, surname: true, email: true, imagePath: true } } },
  });
  res.json(members);
});

// ── POST /api/departments/:id/members ───────────
router.post("/:id/members", async (req: Request, res: Response) => {
  try {
    const data = memberSchema.parse(req.body);
    const member = await prisma.userDepartment.create({
      data: { departmentId: Number(req.params.id), userId: data.userId, role: data.role },
      include: { user: { select: { id: true, ename: true, forename: true, surname: true } } },
    });
    res.status(201).json(member);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── PATCH /api/departments/:deptId/members/:userId
router.patch("/:deptId/members/:userId", async (req: Request, res: Response) => {
  const { role } = req.body;
  const record = await prisma.userDepartment.update({
    where: {
      userId_departmentId: { userId: Number(req.params.userId), departmentId: Number(req.params.deptId) },
    },
    data: { role },
  });
  res.json(record);
});

// ── DELETE /api/departments/:deptId/members/:userId
router.delete("/:deptId/members/:userId", async (req: Request, res: Response) => {
  await prisma.userDepartment.delete({
    where: {
      userId_departmentId: { userId: Number(req.params.userId), departmentId: Number(req.params.deptId) },
    },
  });
  res.status(204).end();
});

export default router;
