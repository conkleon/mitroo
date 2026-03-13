import { Router, Request, Response } from "express";
import crypto from "crypto";
import bcrypt from "bcryptjs";
import { z } from "zod";
import { Prisma } from "@prisma/client";
import prisma from "../lib/prisma";
import { authenticate, getMissionAdminDepartmentIds, requireAdmin } from "../middleware/auth";
import { sendInviteEmail } from "../lib/email";
import { formatGeneratedEame, getNextGeneratedEameSequence } from "../lib/eame";

const router = Router();
router.use(authenticate);

const RANK_VALUES = ["Α", "Β", "Γ"] as const;

const USER_SELECT = {
  id: true, eame: true, forename: true, surname: true, email: true,
  rank: true,
  phonePrimary: true, phoneSecondary: true, address: true,
  birthDate: true, imagePath: true, extraInfo: true, isAdmin: true,
  createdAt: true, updatedAt: true,
};

const updateSchema = z.object({
  eame: z.string().min(2).max(50).optional(),
  forename: z.string().min(1).optional(),
  surname: z.string().min(1).optional(),
  email: z.string().email().optional(),
  phonePrimary: z.string().optional().nullable(),
  phoneSecondary: z.string().optional().nullable(),
  address: z.string().optional().nullable(),
  birthDate: z.string().datetime().optional().nullable(),
  extraInfo: z.string().optional().nullable(),
  rank: z.enum(RANK_VALUES).optional(),
  isAdmin: z.boolean().optional(),
});

const createUserSchema = z.object({
  eame: z.string().min(2).max(50).optional(),
  forename: z.string().min(1),
  surname: z.string().min(1),
  email: z.string().email(),
  rank: z.enum(RANK_VALUES).default("Γ"),
  departmentId: z.number().int(),
  departmentRole: z.enum(["missionAdmin", "itemAdmin", "volunteer"]).default("volunteer"),
  specializationId: z.number().int(),
});

type UserAccessScope =
  | { kind: "admin" }
  | { kind: "missionAdmin"; departmentIds: number[] }
  | { kind: "self" };

function isEameUniqueError(error: unknown): boolean {
  if (!(error instanceof Prisma.PrismaClientKnownRequestError)) {
    return false;
  }
  if (error.code !== "P2002") {
    return false;
  }

  const target = Array.isArray(error.meta?.target) ? error.meta.target : [];
  return target.includes("ename") || target.includes("eame");
}

async function getAccessScope(req: Request): Promise<UserAccessScope> {
  if (req.user!.isAdmin) {
    return { kind: "admin" };
  }

  const departmentIds = await getMissionAdminDepartmentIds(req.user!.userId);
  if (departmentIds.length > 0) {
    return { kind: "missionAdmin", departmentIds };
  }

  return { kind: "self" };
}

async function canReadUserByScope(scope: UserAccessScope, currentUserId: number, targetUserId: number): Promise<boolean> {
  if (scope.kind === "admin") {
    return true;
  }

  if (scope.kind === "self") {
    return currentUserId === targetUserId;
  }

  const count = await prisma.userDepartment.count({
    where: {
      userId: targetUserId,
      departmentId: { in: scope.departmentIds },
    },
  });
  return count > 0;
}

// ── GET /api/users ──────────────────────────────
router.get("/", async (req: Request, res: Response) => {
  const scope = await getAccessScope(req);

  const where =
    scope.kind === "admin"
      ? undefined
      : scope.kind === "self"
        ? { id: req.user!.userId }
        : { departments: { some: { departmentId: { in: scope.departmentIds } } } };

  const users = await prisma.user.findMany({
    where,
    select: { ...USER_SELECT, departments: { include: { department: { select: { id: true, name: true } } } } },
    orderBy: { surname: "asc" },
  });
  res.json(users);
});

// ── GET /api/users/stats ────────────────────────
// Returns all users + aggregated hours (total & this year)
router.get("/stats", async (req: Request, res: Response) => {
  const scope = await getAccessScope(req);

  const where =
    scope.kind === "admin"
      ? undefined
      : scope.kind === "self"
        ? { id: req.user!.userId }
        : { departments: { some: { departmentId: { in: scope.departmentIds } } } };

  const now = new Date();
  const yearStart = new Date(now.getFullYear(), 0, 1);

  const users = await prisma.user.findMany({
    where,
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
  const targetUserId = Number(req.params.id);
  const scope = await getAccessScope(req);
  const allowed = await canReadUserByScope(scope, req.user!.userId, targetUserId);
  if (!allowed) {
    res.status(403).json({ error: "Access denied" });
    return;
  }

  const user = await prisma.user.findUnique({
    where: { id: targetUserId },
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
router.post("/", requireAdmin, async (req: Request, res: Response) => {
  try {
    const data = createUserSchema.parse(req.body);
    const providedEame = data.eame?.trim();

    const existingEmail = await prisma.user.findUnique({ where: { email: data.email } });
    if (existingEmail) {
      res.status(409).json({ error: "Το email χρησιμοποιείται ήδη" });
      return;
    }

    if (providedEame) {
      const existingEame = await prisma.user.findUnique({ where: { eame: providedEame } });
      if (existingEame) {
        res.status(409).json({ error: "Το EAME υπάρχει ήδη" });
        return;
      }
    }

    const department = await prisma.department.findUnique({ where: { id: data.departmentId }, select: { id: true } });
    if (!department) {
      res.status(404).json({ error: "Department not found" });
      return;
    }

    const specialization = await prisma.specialization.findUnique({
      where: { id: data.specializationId },
      select: { id: true, rootId: true, eamePrefix: true },
    });
    if (!specialization) {
      res.status(404).json({ error: "Specialization not found" });
      return;
    }
    if (specialization.rootId !== null) {
      res.status(400).json({ error: "Η αρχική ειδίκευση πρέπει να είναι ριζική." });
      return;
    }

    let eamePrefix = "";
    if (!providedEame) {
      eamePrefix = specialization.eamePrefix?.trim() ?? "";
    }

    const plainPassword = crypto.randomBytes(6).toString("base64url"); // ~8 chars
    const hashed = await bcrypt.hash(plainPassword, 12);

    let user: Pick<Prisma.UserGetPayload<{ select: typeof USER_SELECT }>, keyof typeof USER_SELECT> | null = null;
    const maxAttempts = providedEame ? 1 : 5;

    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        user = await prisma.$transaction(async (tx) => {
          const finalEame = providedEame ?? formatGeneratedEame(eamePrefix, await getNextGeneratedEameSequence(tx));

          const createdUser = await tx.user.create({
            data: {
              eame: finalEame,
              password: hashed,
              forename: data.forename,
              surname: data.surname,
              email: data.email,
              rank: data.rank,
            },
            select: USER_SELECT,
          });

          await tx.userDepartment.create({
            data: {
              userId: createdUser.id,
              departmentId: data.departmentId,
              role: data.departmentRole,
            },
          });

          await tx.userSpecialization.create({
            data: {
              userId: createdUser.id,
              specializationId: data.specializationId,
            },
          });

          return createdUser;
        });
        break;
      } catch (error) {
        if (!providedEame && isEameUniqueError(error) && attempt < maxAttempts - 1) {
          continue;
        }
        throw error;
      }
    }

    if (!user) {
      res.status(500).json({ error: "Failed to create user" });
      return;
    }

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
router.patch("/:id", requireAdmin, async (req: Request, res: Response) => {
  try {
    const targetUserId = Number(req.params.id);
    const data = updateSchema.parse(req.body);

    if (data.eame) {
      const existingEame = await prisma.user.findUnique({ where: { eame: data.eame } });
      if (existingEame && existingEame.id !== targetUserId) {
        res.status(409).json({ error: "Το EAME υπάρχει ήδη" });
        return;
      }
    }

    if (data.email) {
      const existingEmail = await prisma.user.findUnique({ where: { email: data.email } });
      if (existingEmail && existingEmail.id !== targetUserId) {
        res.status(409).json({ error: "Το email χρησιμοποιείται ήδη" });
        return;
      }
    }

    const user = await prisma.user.update({
      where: { id: targetUserId },
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
  const targetUserId = Number(req.params.id);
  const scope = await getAccessScope(req);
  const allowed = await canReadUserByScope(scope, req.user!.userId, targetUserId);
  if (!allowed) {
    res.status(403).json({ error: "Access denied" });
    return;
  }

  const specs = await prisma.userSpecialization.findMany({
    where: { userId: targetUserId },
    include: { specialization: true },
  });
  res.json(specs);
});

// ── GET /api/users/:id/services ─────────────────
// Returns user's service enrolments with service details & hours
router.get("/:id/services", async (req: Request, res: Response) => {
  const userId = Number(req.params.id);
  const scope = await getAccessScope(req);
  const allowed = await canReadUserByScope(scope, req.user!.userId, userId);
  if (!allowed) {
    res.status(403).json({ error: "Access denied" });
    return;
  }

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
router.post("/:id/specializations", requireAdmin, async (req: Request, res: Response) => {
  const { specializationId } = req.body;
  const record = await prisma.userSpecialization.create({
    data: { userId: Number(req.params.id), specializationId: Number(specializationId) },
    include: { specialization: true },
  });
  res.status(201).json(record);
});

// ── DELETE /api/users/:uid/specializations/:sid ─
router.delete("/:uid/specializations/:sid", requireAdmin, async (req: Request, res: Response) => {
  await prisma.userSpecialization.delete({
    where: { userId_specializationId: { userId: Number(req.params.uid), specializationId: Number(req.params.sid) } },
  });
  res.status(204).end();
});

export default router;
