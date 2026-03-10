import { Router, Request, Response } from "express";
import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate } from "../middleware/auth";

const router = Router();

// ── Validation schemas ──────────────────────────
const registerSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  forename: z.string().min(1),
  surname: z.string().min(1),
  ename: z.string().min(2).max(50),
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string(),
});

// ── POST /api/auth/register ─────────────────────
router.post("/register", async (req: Request, res: Response) => {
  try {
    const data = registerSchema.parse(req.body);

    const existing = await prisma.user.findUnique({ where: { email: data.email } });
    if (existing) {
      res.status(409).json({ error: "Email already registered" });
      return;
    }

    const hashed = await bcrypt.hash(data.password, 12);
    const user = await prisma.user.create({
      data: {
        ename: data.ename,
        password: hashed,
        forename: data.forename,
        surname: data.surname,
        email: data.email,
      },
      select: { id: true, ename: true, forename: true, surname: true, email: true, isAdmin: true },
    });

    const token = jwt.sign(
      { userId: user.id, isAdmin: user.isAdmin },
      process.env.JWT_SECRET!,
      { expiresIn: process.env.JWT_EXPIRES_IN || "7d" } as jwt.SignOptions,
    );

    res.status(201).json({ user, token });
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Validation failed", details: err.errors });
      return;
    }
    throw err;
  }
});

// ── POST /api/auth/login ────────────────────────
router.post("/login", async (req: Request, res: Response) => {
  try {
    const data = loginSchema.parse(req.body);

    const user = await prisma.user.findUnique({ where: { email: data.email } });
    if (!user || !(await bcrypt.compare(data.password, user.password))) {
      res.status(401).json({ error: "Invalid credentials" });
      return;
    }

    const token = jwt.sign(
      { userId: user.id, isAdmin: user.isAdmin },
      process.env.JWT_SECRET!,
      { expiresIn: process.env.JWT_EXPIRES_IN || "7d" } as jwt.SignOptions,
    );

    res.json({
      user: {
        id: user.id,
        ename: user.ename,
        forename: user.forename,
        surname: user.surname,
        email: user.email,
        isAdmin: user.isAdmin,
        imagePath: user.imagePath,
      },
      token,
    });
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Validation failed", details: err.errors });
      return;
    }
    throw err;
  }
});

// ── GET /api/auth/me ────────────────────────────
router.get("/me", authenticate, async (req: Request, res: Response) => {
  const user = await prisma.user.findUnique({
    where: { id: req.user!.userId },
    select: {
      id: true, ename: true, forename: true, surname: true, email: true,
      isAdmin: true, imagePath: true, phonePrimary: true, phoneSecondary: true,
      birthDate: true, address: true, extraInfo: true,
      departments: { include: { department: { select: { id: true, name: true } } } },
      specializations: {
        include: { specialization: { select: { id: true, name: true, description: true } } },
      },
    },
  });
  if (!user) {
    res.status(404).json({ error: "User not found" });
    return;
  }
  res.json(user);
});

// ── GET /api/auth/me/profile ────────────────────
// Returns the current user's aggregated hours (all-time & last year by type)
// plus their assigned equipment (items).
router.get("/me/profile", authenticate, async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const now = new Date();
  const yearStart = new Date(now.getFullYear(), 0, 1);

  // Fetch accepted service enrolments with service dates
  const enrolments = await prisma.userService.findMany({
    where: { userId, status: "accepted" },
    select: {
      hours: true,
      hoursVol: true,
      hoursTraining: true,
      hoursTrainers: true,
      service: { select: { startAt: true } },
    },
  });

  let totalHours = 0;
  let yearHours = 0;
  let yearServiceHours = 0;
  let yearVolHours = 0;
  let yearTrainingHours = 0;
  let yearTrainerHours = 0;

  for (const e of enrolments) {
    const h = e.hours ?? 0;
    const hv = e.hoursVol ?? 0;
    const ht = e.hoursTraining ?? 0;
    const htr = e.hoursTrainers ?? 0;
    const sum = h + hv + ht + htr;
    totalHours += sum;

    if (e.service?.startAt && e.service.startAt >= yearStart) {
      yearHours += sum;
      yearServiceHours += h;
      yearVolHours += hv;
      yearTrainingHours += ht;
      yearTrainerHours += htr;
    }
  }

  // Fetch items assigned to this user (equipment list)
  const equipment = await prisma.item.findMany({
    where: { assignedToId: userId },
    select: {
      id: true,
      name: true,
      barCode: true,
      imagePath: true,
      isContainer: true,
      location: true,
      expirationDate: true,
    },
    orderBy: { name: "asc" },
  });

  res.json({
    totalHours,
    yearHours,
    yearServiceHours,
    yearVolHours,
    yearTrainingHours,
    yearTrainerHours,
    equipment,
  });
});

// ── POST /api/auth/change-password ──────────────
const changePasswordSchema = z.object({
  currentPassword: z.string().min(1),
  newPassword: z.string().min(8),
});

router.post("/change-password", authenticate, async (req: Request, res: Response) => {
  try {
    const data = changePasswordSchema.parse(req.body);
    const user = await prisma.user.findUnique({ where: { id: req.user!.userId } });
    if (!user) { res.status(404).json({ error: "User not found" }); return; }

    const valid = await bcrypt.compare(data.currentPassword, user.password);
    if (!valid) { res.status(401).json({ error: "Current password is incorrect" }); return; }

    const hashed = await bcrypt.hash(data.newPassword, 12);
    await prisma.user.update({ where: { id: user.id }, data: { password: hashed } });

    res.json({ message: "Password changed successfully" });
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Validation failed", details: err.errors });
      return;
    }
    throw err;
  }
});

export default router;
