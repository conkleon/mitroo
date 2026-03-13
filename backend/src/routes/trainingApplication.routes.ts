import { Router, Request, Response } from "express";
import crypto from "crypto";
import bcrypt from "bcryptjs";
import { z } from "zod";
import { Prisma, TrainingApplicationStatus } from "@prisma/client";
import prisma from "../lib/prisma";
import { authenticate, getMissionAdminDepartmentIds } from "../middleware/auth";
import { formatGeneratedEame, getNextGeneratedEameSequence } from "../lib/eame";
import { sendInviteEmail, sendTrainingApplicationSubmittedEmail } from "../lib/email";

const router = Router();

const submitSchema = z.object({
  email: z.string().email(),
  forename: z.string().min(1),
  surname: z.string().min(1),
  phonePrimary: z.string().min(5).max(30),
  phoneSecondary: z.string().max(30).optional().nullable(),
  address: z.string().optional().nullable(),
  birthDate: z.string().datetime().optional().nullable(),
  extraInfo: z.string().optional().nullable(),
  departmentId: z.number().int(),
  specializationId: z.number().int(),
});

const reviewSchema = z.object({
  reviewNotes: z.string().max(2000).optional().nullable(),
});

function isEameUniqueError(error: unknown): boolean {
  if (!(error instanceof Prisma.PrismaClientKnownRequestError)) {
    return false;
  }
  if (error.code !== "P2002") {
    return false;
  }

  const target = Array.isArray(error.meta?.target) ? error.meta.target : [];
  return target.includes("eame") || target.includes("ename");
}

async function canManageDepartment(req: Request, departmentId: number): Promise<boolean> {
  if (req.user?.isAdmin) return true;
  if (!req.user) return false;

  const deptIds = await getMissionAdminDepartmentIds(req.user.userId);
  return deptIds.includes(departmentId);
}

// Public metadata for applicant flow
router.get("/meta", async (_req: Request, res: Response) => {
  const [departments, rootSpecializations] = await Promise.all([
    prisma.department.findMany({ select: { id: true, name: true }, orderBy: { name: "asc" } }),
    prisma.specialization.findMany({
      where: { rootId: null },
      select: { id: true, name: true, description: true },
      orderBy: { name: "asc" },
    }),
  ]);

  res.json({ departments, rootSpecializations });
});

// Public submit
router.post("/", async (req: Request, res: Response) => {
  try {
    const data = submitSchema.parse(req.body);

    const [department, specialization] = await Promise.all([
      prisma.department.findUnique({ where: { id: data.departmentId }, select: { id: true, name: true } }),
      prisma.specialization.findUnique({ where: { id: data.specializationId }, select: { id: true, name: true, rootId: true } }),
    ]);

    if (!department) {
      res.status(404).json({ error: "Department not found" });
      return;
    }
    if (!specialization) {
      res.status(404).json({ error: "Specialization not found" });
      return;
    }
    if (specialization.rootId !== null) {
      res.status(400).json({ error: "Η ειδίκευση αίτησης πρέπει να είναι ριζική." });
      return;
    }

    const existingUser = await prisma.user.findUnique({ where: { email: data.email }, select: { id: true } });
    if (existingUser) {
      res.status(409).json({ error: "Υπάρχει ήδη ενεργός λογαριασμός με αυτό το email." });
      return;
    }

    const existingApplication = await prisma.trainingApplication.findFirst({
      where: {
        email: data.email,
        status: { in: ["submitted", "training"] },
      },
      select: { id: true },
    });
    if (existingApplication) {
      res.status(409).json({ error: "Υπάρχει ήδη ενεργή αίτηση για αυτό το email." });
      return;
    }

    const application = await prisma.trainingApplication.create({
      data: {
        email: data.email,
        forename: data.forename,
        surname: data.surname,
        phonePrimary: data.phonePrimary,
        phoneSecondary: data.phoneSecondary ?? null,
        address: data.address ?? null,
        birthDate: data.birthDate ? new Date(data.birthDate) : null,
        extraInfo: data.extraInfo ?? null,
        departmentId: data.departmentId,
        specializationId: data.specializationId,
      },
      include: {
        department: { select: { id: true, name: true } },
        specialization: { select: { id: true, name: true } },
      },
    });

    try {
      await sendTrainingApplicationSubmittedEmail(
        data.email,
        data.forename,
        application.department.name,
        application.specialization.name,
      );
    } catch (emailErr) {
      console.error("Failed to send training application email:", emailErr);
    }

    res.status(201).json({
      message: "Η αίτησή σας καταχωρήθηκε. Παρακαλώ περιμένετε επικοινωνία από το τμήμα επιλογής σας.",
      applicationId: application.id,
    });
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Validation failed", details: err.errors });
      return;
    }
    throw err;
  }
});

router.use(authenticate);

// List for admin / missionAdmin
router.get("/", async (req: Request, res: Response) => {
  const status = (req.query.status as TrainingApplicationStatus | undefined) ?? undefined;
  const allowedStatuses: TrainingApplicationStatus[] = ["submitted", "training", "rejected", "enabled"];
  if (status && !allowedStatuses.includes(status)) {
    res.status(400).json({ error: "Invalid status" });
    return;
  }

  let where: any = status ? { status } : undefined;

  if (!req.user!.isAdmin) {
    const deptIds = await getMissionAdminDepartmentIds(req.user!.userId);
    if (deptIds.length === 0) {
      res.status(403).json({ error: "Access denied" });
      return;
    }
    where = { ...(where ?? {}), departmentId: { in: deptIds } };
  }

  const applications = await prisma.trainingApplication.findMany({
    where,
    include: {
      department: { select: { id: true, name: true } },
      specialization: { select: { id: true, name: true } },
      reviewedBy: { select: { id: true, forename: true, surname: true } },
      linkedUser: { select: { id: true, eame: true, email: true } },
    },
    orderBy: { createdAt: "desc" },
  });

  res.json(applications);
});

router.patch("/:id/accept-training", async (req: Request, res: Response) => {
  const id = Number(req.params.id);
  const data = reviewSchema.parse(req.body ?? {});

  const app = await prisma.trainingApplication.findUnique({ where: { id } });
  if (!app) {
    res.status(404).json({ error: "Application not found" });
    return;
  }

  if (!(await canManageDepartment(req, app.departmentId))) {
    res.status(403).json({ error: "Access denied" });
    return;
  }

  if (app.status !== "submitted") {
    res.status(400).json({ error: "Only submitted applications can be accepted for training" });
    return;
  }

  const updated = await prisma.trainingApplication.update({
    where: { id },
    data: {
      status: "training",
      reviewedAt: new Date(),
      reviewedById: req.user!.userId,
      reviewNotes: data.reviewNotes ?? null,
    },
    include: {
      department: { select: { id: true, name: true } },
      specialization: { select: { id: true, name: true } },
    },
  });

  res.json(updated);
});

router.patch("/:id/reject", async (req: Request, res: Response) => {
  const id = Number(req.params.id);
  const data = reviewSchema.parse(req.body ?? {});

  const app = await prisma.trainingApplication.findUnique({ where: { id } });
  if (!app) {
    res.status(404).json({ error: "Application not found" });
    return;
  }

  if (!(await canManageDepartment(req, app.departmentId))) {
    res.status(403).json({ error: "Access denied" });
    return;
  }

  if (app.status !== "submitted" && app.status !== "training") {
    res.status(400).json({ error: "Application cannot be rejected in the current status" });
    return;
  }

  const updated = await prisma.trainingApplication.update({
    where: { id },
    data: {
      status: "rejected",
      reviewedAt: new Date(),
      reviewedById: req.user!.userId,
      reviewNotes: data.reviewNotes ?? null,
    },
    include: {
      department: { select: { id: true, name: true } },
      specialization: { select: { id: true, name: true } },
    },
  });

  res.json(updated);
});

router.patch("/:id/enable-services", async (req: Request, res: Response) => {
  const id = Number(req.params.id);
  const app = await prisma.trainingApplication.findUnique({
    where: { id },
    include: {
      specialization: { select: { id: true, eamePrefix: true } },
    },
  });

  if (!app) {
    res.status(404).json({ error: "Application not found" });
    return;
  }

  if (!(await canManageDepartment(req, app.departmentId))) {
    res.status(403).json({ error: "Access denied" });
    return;
  }

  if (app.status !== "training") {
    res.status(400).json({ error: "Only users under training can be enabled" });
    return;
  }

  const existingUser = await prisma.user.findUnique({ where: { email: app.email }, select: { id: true } });
  if (existingUser) {
    res.status(409).json({ error: "Υπάρχει ήδη λογαριασμός με αυτό το email." });
    return;
  }

  const plainPassword = crypto.randomBytes(6).toString("base64url");
  const hashed = await bcrypt.hash(plainPassword, 12);

  const prefix = app.specialization.eamePrefix?.trim() ?? "";
  let createdUser: { id: number; eame: string; email: string; forename: string; surname: string } | null = null;
  const maxAttempts = 5;

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      createdUser = await prisma.$transaction(async (tx) => {
        const eame = formatGeneratedEame(prefix, await getNextGeneratedEameSequence(tx));

        const user = await tx.user.create({
          data: {
            eame,
            password: hashed,
            forename: app.forename,
            surname: app.surname,
            email: app.email,
            phonePrimary: app.phonePrimary,
            phoneSecondary: app.phoneSecondary,
            address: app.address,
            birthDate: app.birthDate,
            extraInfo: app.extraInfo,
          },
          select: { id: true, eame: true, email: true, forename: true, surname: true },
        });

        await tx.userDepartment.create({
          data: {
            userId: user.id,
            departmentId: app.departmentId,
            role: "volunteer",
          },
        });

        await tx.userSpecialization.create({
          data: {
            userId: user.id,
            specializationId: app.specializationId,
          },
        });

        await tx.trainingApplication.update({
          where: { id: app.id },
          data: {
            status: "enabled",
            enabledAt: new Date(),
            reviewedAt: new Date(),
            reviewedById: req.user!.userId,
            linkedUserId: user.id,
          },
        });

        return user;
      });
      break;
    } catch (error) {
      if (isEameUniqueError(error) && attempt < maxAttempts - 1) {
        continue;
      }
      throw error;
    }
  }

  if (!createdUser) {
    res.status(500).json({ error: "Failed to enable services for applicant" });
    return;
  }

  try {
    await sendInviteEmail(createdUser.email, createdUser.forename, plainPassword);
  } catch (emailErr) {
    console.error("Failed to send invite email after enable-services:", emailErr);
  }

  res.json({ message: "User enabled successfully", user: createdUser });
});

export default router;
