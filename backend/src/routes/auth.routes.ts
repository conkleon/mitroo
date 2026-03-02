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

export default router;
