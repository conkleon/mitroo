import { Router, Request, Response } from "express";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate, requireAdmin } from "../middleware/auth";

const router = Router();
router.use(authenticate);

const USER_SELECT = {
  id: true, ename: true, forename: true, surname: true, email: true,
  phonePrimary: true, phoneSecondary: true, address: true,
  birthDate: true, imagePath: true, extraInfo: true, isAdmin: true,
  createdAt: true, updatedAt: true,
};

const updateSchema = z.object({
  forename: z.string().min(1).optional(),
  surname: z.string().min(1).optional(),
  email: z.string().email().optional(),
  phonePrimary: z.string().optional().nullable(),
  phoneSecondary: z.string().optional().nullable(),
  address: z.string().optional().nullable(),
  birthDate: z.string().datetime().optional().nullable(),
  extraInfo: z.string().optional().nullable(),
  isAdmin: z.boolean().optional(),
});

// ── GET /api/users ──────────────────────────────
router.get("/", async (_req: Request, res: Response) => {
  const users = await prisma.user.findMany({
    select: { ...USER_SELECT, departments: { include: { department: { select: { id: true, name: true } } } } },
    orderBy: { surname: "asc" },
  });
  res.json(users);
});

// ── GET /api/users/:id ──────────────────────────
router.get("/:id", async (req: Request, res: Response) => {
  const user = await prisma.user.findUnique({
    where: { id: Number(req.params.id) },
    select: {
      ...USER_SELECT,
      departments: { include: { department: true } },
      specializations: { include: { specialization: true } },
    },
  });
  if (!user) { res.status(404).json({ error: "User not found" }); return; }
  res.json(user);
});

// ── PATCH /api/users/:id ────────────────────────
router.patch("/:id", async (req: Request, res: Response) => {
  try {
    const data = updateSchema.parse(req.body);
    // Only admins can change isAdmin flag
    if (data.isAdmin !== undefined && !req.user!.isAdmin) {
      res.status(403).json({ error: "Only admins can change admin flag" });
      return;
    }
    const user = await prisma.user.update({
      where: { id: Number(req.params.id) },
      data: {
        ...data,
        birthDate: data.birthDate ? new Date(data.birthDate) : data.birthDate === null ? null : undefined,
      },
      select: USER_SELECT,
    });
    res.json(user);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── DELETE /api/users/:id ───────────────────────
router.delete("/:id", requireAdmin, async (req: Request, res: Response) => {
  await prisma.user.delete({ where: { id: Number(req.params.id) } });
  res.status(204).end();
});

// ── GET /api/users/:id/specializations ──────────
router.get("/:id/specializations", async (req: Request, res: Response) => {
  const specs = await prisma.userSpecialization.findMany({
    where: { userId: Number(req.params.id) },
    include: { specialization: true },
  });
  res.json(specs);
});

// ── POST /api/users/:id/specializations ─────────
router.post("/:id/specializations", async (req: Request, res: Response) => {
  const { specializationId } = req.body;
  const record = await prisma.userSpecialization.create({
    data: { userId: Number(req.params.id), specializationId: Number(specializationId) },
    include: { specialization: true },
  });
  res.status(201).json(record);
});

// ── DELETE /api/users/:uid/specializations/:sid ─
router.delete("/:uid/specializations/:sid", async (req: Request, res: Response) => {
  await prisma.userSpecialization.delete({
    where: { userId_specializationId: { userId: Number(req.params.uid), specializationId: Number(req.params.sid) } },
  });
  res.status(204).end();
});

export default router;
