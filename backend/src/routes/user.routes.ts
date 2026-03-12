import { Router, Request, Response } from "express";
import crypto from "crypto";
import bcrypt from "bcryptjs";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate, requireAdmin } from "../middleware/auth";
import { sendInviteEmail } from "../lib/email";

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

// ── GET /api/users/stats ────────────────────────
// Returns all users + aggregated hours (total & this year)
router.get("/stats", async (_req: Request, res: Response) => {
  const now = new Date();
  const yearStart = new Date(now.getFullYear(), 0, 1);

  const users = await prisma.user.findMany({
    select: {
      ...USER_SELECT,
      departments: { include: { department: { select: { id: true, name: true } } } },
      services: {
        where: { status: "accepted" },
        select: {
          hours: true,
          hoursVol: true,
          hoursTraining: true,
          hoursTrainers: true,
          service: { select: { startAt: true } },
        },
      },
    },
    orderBy: { surname: "asc" },
  });

  const result = users.map((u) => {
    let totalHours = 0;
    let yearHours = 0;
    let yearVolHours = 0;
    let yearTrainingHours = 0;
    let yearTrainerHours = 0;

    for (const us of u.services) {
      const h = us.hours ?? 0;
      const hv = us.hoursVol ?? 0;
      const ht = us.hoursTraining ?? 0;
      const htr = us.hoursTrainers ?? 0;
      totalHours += h + hv + ht + htr;

      const serviceStart = us.service?.startAt;
      if (serviceStart && serviceStart >= yearStart) {
        yearHours += h + hv + ht + htr;
        yearVolHours += hv;
        yearTrainingHours += ht;
        yearTrainerHours += htr;
      }
    }

    const { services, ...rest } = u;
    return { ...rest, totalHours, yearHours, yearVolHours, yearTrainingHours, yearTrainerHours };
  });

  res.json(result);
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

// ── POST /api/users ─────────────────────────────
// Admin creates a user: random password generated, invite email sent
const createUserSchema = z.object({
  ename: z.string().min(2).max(50),
  forename: z.string().min(1),
  surname: z.string().min(1),
  email: z.string().email(),
});

router.post("/", requireAdmin, async (req: Request, res: Response) => {
  try {
    const data = createUserSchema.parse(req.body);

    const existing = await prisma.user.findFirst({
      where: { OR: [{ email: data.email }, { ename: data.ename }] },
    });
    if (existing) {
      res.status(409).json({ error: existing.email === data.email ? "Το email χρησιμοποιείται ήδη" : "Ο κωδ. μέλους υπάρχει ήδη" });
      return;
    }

    const plainPassword = crypto.randomBytes(6).toString("base64url"); // ~8 chars
    const hashed = await bcrypt.hash(plainPassword, 12);

    const user = await prisma.user.create({
      data: {
        ename: data.ename,
        password: hashed,
        forename: data.forename,
        surname: data.surname,
        email: data.email,
      },
      select: USER_SELECT,
    });

    try {
      await sendInviteEmail(data.email, data.forename, plainPassword);
    } catch (emailErr) {
      console.error("Failed to send invite email:", emailErr);
    }

    res.status(201).json(user);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Validation failed", details: err.errors });
      return;
    }
    throw err;
  }
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

// ── GET /api/users/:id/services ─────────────────
// Returns user's service enrolments with service details & hours
router.get("/:id/services", async (req: Request, res: Response) => {
  const userId = Number(req.params.id);
  const enrolments = await prisma.userService.findMany({
    where: { userId },
    include: {
      service: {
        select: {
          id: true,
          name: true,
          location: true,
          carrier: true,
          startAt: true,
          endAt: true,
          department: { select: { id: true, name: true } },
        },
      },
    },
    orderBy: { service: { startAt: "desc" } },
  });

  const result = enrolments.map((e) => ({
    serviceId: e.serviceId,
    status: e.status,
    hours: e.hours,
    hoursVol: e.hoursVol,
    hoursTraining: e.hoursTraining,
    hoursTrainers: e.hoursTrainers,
    totalHours: (e.hours ?? 0) + (e.hoursVol ?? 0) + (e.hoursTraining ?? 0) + (e.hoursTrainers ?? 0),
    service: e.service,
  }));

  res.json(result);
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
