import { Router, Request, Response } from "express";
import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import crypto from "crypto";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate } from "../middleware/auth";
import { sendPasswordResetEmail } from "../lib/email";
import { autoUpdateSyncConfig, syncUserApplications, syncUserDepartments } from "../lib/mitrooSync";
import { MitrooClient } from "../lib/mitrooClient";

const router = Router();

// ── Validation schemas ──────────────────────────
const loginSchema = z.object({
  email: z.string().email(),
  password: z.string(),
});

const EXTERNAL_BASE_URL =
  process.env.MITROO_EXTERNAL_BASE_URL ?? "https://mitroo.redcross.gr";
const EXTERNAL_DEBUG = process.env.MITROO_EXTERNAL_DEBUG === "1";

const debugExternal = (message: string, context?: Record<string, unknown>) => {
  if (!EXTERNAL_DEBUG) return;
  if (context) console.info(`[auth][external] ${message}`, context);
  else console.info(`[auth][external] ${message}`);
};

type AuthUser = {
  id: number;
  eame: string;
  forename: string;
  surname: string;
  email: string;
  rank: string;
  isAdmin: boolean;
  imagePath: string | null;
  gdprAcceptedAt: Date | null;
};

const selectAuthUser = {
  id: true,
  eame: true,
  forename: true,
  surname: true,
  email: true,
  rank: true,
  isAdmin: true,
  imagePath: true,
  gdprAcceptedAt: true,
};

async function syncProfileSpecializations(
  userId: number,
  specializationNames: string[],
): Promise<void> {
  for (const name of specializationNames) {
    const spec = await prisma.specialization.upsert({
      where: { name },
      update: {},
      create: { name },
      select: { id: true },
    });
    await prisma.userSpecialization.upsert({
      where: { userId_specializationId: { userId, specializationId: spec.id } },
      update: {},
      create: { userId, specializationId: spec.id },
    });
  }
}

async function linkUserToDepartment(userId: number, memberDepartment?: string): Promise<void> {
  if (!memberDepartment) return;
  let dept = await prisma.department.findFirst({
    where: { name: { equals: memberDepartment, mode: "insensitive" } },
    select: { id: true },
  });
  if (!dept) {
    dept = await prisma.department.create({
      data: { name: memberDepartment },
      select: { id: true },
    });
    debugExternal("auto-created department", { name: memberDepartment, id: dept.id });
  }
  await prisma.userDepartment.upsert({
    where: { userId_departmentId: { userId, departmentId: dept.id } },
    update: {},
    create: { userId, departmentId: dept.id, role: "volunteer" },
  });
  debugExternal("linked user to department", { userId, departmentId: dept.id, memberDepartment });
}

async function loginViaExternalMitroo(
  email: string,
  password: string,
): Promise<
  | { user: AuthUser | null; emailConflict: boolean; memberDepartment?: string; isExternalAdmin: boolean }
  | null
> {
  const client = new MitrooClient(EXTERNAL_BASE_URL);
  debugExternal("login attempt", { email });
  try {
    await client.login(email, password);
    debugExternal("login success", { email });
  } catch (error) {
    debugExternal("login failed", { email, error: String(error) });
    return null;
  }

  const match = await client.findVolunteerByEmail(email);
  const eame = (match?.registration_code as string | undefined)?.trim();
  let externalId = match ? Number(match.id) : null;
  let memberDepartment = (match?.member_department as string | undefined)?.trim();
  let forename = match ? (match.first_name as string) ?? "" : "";
  let surname = match ? (match.last_name as string) ?? "" : "";
  const normalizedEmail = email.trim().toLowerCase();

  // Always fetch profile for extended data (phones, birthdate, address, specializations)
  // and as a fallback source for eame/name when the volunteer grid lookup misses
  const profileIdentity = await client.fetchProfileIdentity();
  let resolvedEame = eame || profileIdentity.eame;
  if (!forename && profileIdentity.forename) forename = profileIdentity.forename;
  if (!surname && profileIdentity.surname) surname = profileIdentity.surname;

  if (!resolvedEame) {
    debugExternal("unable to resolve eame", { email });
    return null;
  }

  // If the email-based lookup didn't find the volunteer, try by
  // registration_code. The login email may differ from the email stored
  // in the volunteer record.
  if (!match && resolvedEame) {
    const matchByCode = await client.findVolunteerByCode(resolvedEame);
    if (matchByCode) {
      externalId = Number(matchByCode.id);
      memberDepartment = (matchByCode.member_department as string | undefined)?.trim();
      debugExternal("found volunteer by registration_code", {
        eame: resolvedEame,
        externalId: Number.isFinite(externalId) ? externalId : null,
        memberDepartment: memberDepartment || null,
      });
    }
  }

  debugExternal("matched external identity", {
    email: normalizedEmail,
    eame: resolvedEame,
    externalId: Number.isFinite(externalId ?? NaN) ? externalId : null,
  });

  const emailOwner = normalizedEmail
    ? await prisma.user.findUnique({ where: { email: normalizedEmail } })
    : null;

  const existing = await prisma.user.findUnique({ where: { eame: resolvedEame } });

  if (!existing) {
    if (emailOwner && emailOwner.eame !== resolvedEame) {
      await prisma.user.update({
        where: { id: emailOwner.id },
        data: { email: `unused_${Date.now()}_${emailOwner.email}` },
      });
    }

    // Probe admin access once, at account-creation time. After this the role
    // is stored locally and we never need to probe again.
    const isExternalAdmin = await client.testAdminAccess();
    debugExternal("admin access probe (new user)", { email: normalizedEmail, isExternalAdmin });

    const hashed = await bcrypt.hash(password, 12);
    const createData: {
      eame: string;
      email: string;
      password: string;
      forename: string;
      surname: string;
      externalId?: number;
      phonePrimary?: string;
      phoneSecondary?: string;
      birthDate?: Date;
      address?: string;
    } = {
      eame: resolvedEame,
      email: normalizedEmail,
      password: hashed,
      forename: forename || "",
      surname: surname || "",
    };
    if (Number.isFinite(externalId ?? NaN) && (externalId ?? 0) > 0) {
      createData.externalId = externalId as number;
    }
    if (profileIdentity.phonePrimary) createData.phonePrimary = profileIdentity.phonePrimary;
    if (profileIdentity.phoneSecondary) createData.phoneSecondary = profileIdentity.phoneSecondary;
    if (profileIdentity.birthDate) createData.birthDate = profileIdentity.birthDate;
    if (profileIdentity.address) createData.address = profileIdentity.address;
    const created = await prisma.user.create({
      data: createData,
      select: selectAuthUser,
    });
    debugExternal("created local user from external auth", { userId: created.id, eame: resolvedEame });
    linkUserToDepartment(created.id, memberDepartment).catch((e) =>
      console.error("[auth] linkUserToDepartment error:", e),
    );
    if (profileIdentity.specializationNames?.length) {
      syncProfileSpecializations(created.id, profileIdentity.specializationNames).catch((e) =>
        console.error("[auth] syncProfileSpecializations error:", e),
      );
    }
    return { user: created, emailConflict: false, memberDepartment, isExternalAdmin };
  }

  if (emailOwner && emailOwner.id !== existing.id) {
    // Email belongs to a different local user — clear it from the old
    // owner so the external-Mitroo-verified user can claim it.
    debugExternal("reassigning email from conflicting user", {
      email: normalizedEmail,
      eame: resolvedEame,
      existingUserId: existing.id,
      emailOwnerId: emailOwner.id,
    });
    await prisma.user.update({
      where: { id: emailOwner.id },
      data: { email: `unused_${Date.now()}_${emailOwner.email}` },
    });
  }

  const hashed = await bcrypt.hash(password, 12);
  debugExternal("updating local user", { userId: existing.id, eame: resolvedEame });
  const updated = await prisma.user.update({
    where: { id: existing.id },
    data: {
      password: hashed,
      ...(forename ? { forename } : {}),
      ...(surname ? { surname } : {}),
      email: normalizedEmail,
      ...(Number.isFinite(externalId ?? NaN) && (externalId ?? 0) > 0 ? { externalId } : {}),
      ...(profileIdentity.phonePrimary ? { phonePrimary: profileIdentity.phonePrimary } : {}),
      ...(profileIdentity.phoneSecondary ? { phoneSecondary: profileIdentity.phoneSecondary } : {}),
      ...(profileIdentity.birthDate ? { birthDate: profileIdentity.birthDate } : {}),
      ...(profileIdentity.address ? { address: profileIdentity.address } : {}),
    },
    select: selectAuthUser,
  });
  linkUserToDepartment(updated.id, memberDepartment).catch((e) =>
    console.error("[auth] linkUserToDepartment error:", e),
  );
  if (profileIdentity.specializationNames?.length) {
    syncProfileSpecializations(updated.id, profileIdentity.specializationNames).catch((e) =>
      console.error("[auth] syncProfileSpecializations error:", e),
    );
  }
  return { user: updated, emailConflict: false, memberDepartment, isExternalAdmin: false };
}

// ── POST /api/auth/login ────────────────────────
router.post("/login", async (req: Request, res: Response) => {
  try {
    const data = loginSchema.parse(req.body);

    const identifier = data.email.trim().toLowerCase();
    const user = await prisma.user.findUnique({ where: { email: identifier } });

    if (!user || !(await bcrypt.compare(data.password, user.password))) {
      const externalResult = await loginViaExternalMitroo(identifier, data.password);
      if (!externalResult) {
        res.status(401).json({ error: "Invalid credentials" });
        return;
      }
      if (externalResult.emailConflict) {
        res.status(409).json({ error: "Email already registered" });
        return;
      }

      const token = jwt.sign(
        { userId: externalResult.user!.id, isAdmin: externalResult.user!.isAdmin },
        process.env.JWT_SECRET!,
        { expiresIn: process.env.JWT_EXPIRES_IN || "7d" } as jwt.SignOptions,
      );

      // Await credential save + missionAdmin assignment before responding so the
      // frontend sees the correct role when it calls /me. syncServices inside
      // autoUpdateSyncConfig is still fire-and-forget, so response isn't blocked by sync.
      if (externalResult.memberDepartment && externalResult.isExternalAdmin) {
        try {
          await autoUpdateSyncConfig(
            externalResult.memberDepartment,
            identifier,
            data.password,
            externalResult.user!.id,
          );
        } catch (e) {
          console.error("[auth] autoUpdateSyncConfig error:", e);
        }
      }

      res.json({
        user: externalResult.user,
        token,
        gdprConsentRequired: !externalResult.user!.gdprAcceptedAt,
      });
      syncUserApplications(externalResult.user!.id).catch((e) =>
        console.error("[auth] syncUserApplications error:", e),
      );
      syncUserDepartments(externalResult.user!.id).catch((e) =>
        console.error("[auth] syncUserDepartments error:", e),
      );
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
        eame: user.eame,
        forename: user.forename,
        surname: user.surname,
        email: user.email,
        rank: user.rank,
        isAdmin: user.isAdmin,
        imagePath: user.imagePath,
      },
      token,
      gdprConsentRequired: !user.gdprAcceptedAt,
    });

    // Fire-and-forget: sync profile data (externalId, department, phones, birthdate,
    // address, specializations) from external Mitroo on every successful local login.
    (async () => {
      try {
        const client = new MitrooClient(EXTERNAL_BASE_URL);
        await client.login(data.email, data.password);
        let match = await client.findVolunteerByEmail(identifier);

        const profile = await client.fetchProfileIdentity();

        if (!match && profile.eame) {
          match = await client.findVolunteerByCode(profile.eame);
        }

        if (match) {
          const extId = Number(match.id);
          const memberDepartment = (match.member_department as string | undefined)?.trim();

          if (Number.isFinite(extId) && extId > 0 && !user.externalId) {
            await prisma.user.update({
              where: { id: user.id },
              data: { externalId: extId },
            });
            debugExternal("populated missing externalId", { userId: user.id, externalId: extId });
          }

          if (memberDepartment) {
            await linkUserToDepartment(user.id, memberDepartment);
            // No probe needed — role is already in the DB from first login.
            // Refresh credentials if the user is a known admin or missionAdmin.
            if (user.isAdmin) {
              autoUpdateSyncConfig(memberDepartment, data.email, data.password, user.id).catch((e) =>
                console.error("[auth] autoUpdateSyncConfig error:", e),
              );
            } else {
              const dept = await prisma.department.findFirst({
                where: { name: { equals: memberDepartment, mode: "insensitive" } },
                select: { id: true },
              });
              if (dept) {
                const membership = await prisma.userDepartment.findUnique({
                  where: { userId_departmentId: { userId: user.id, departmentId: dept.id } },
                  select: { role: true },
                });
                if (membership?.role === "missionAdmin") {
                  autoUpdateSyncConfig(memberDepartment, data.email, data.password, user.id).catch((e) =>
                    console.error("[auth] autoUpdateSyncConfig error:", e),
                  );
                }
              }
            }
          }
        }

        // Sync extended profile fields regardless of whether volunteer grid matched
        const profileUpdateData: {
          phonePrimary?: string;
          phoneSecondary?: string;
          birthDate?: Date;
          address?: string;
        } = {};
        if (profile.phonePrimary) profileUpdateData.phonePrimary = profile.phonePrimary;
        if (profile.phoneSecondary) profileUpdateData.phoneSecondary = profile.phoneSecondary;
        if (profile.birthDate) profileUpdateData.birthDate = profile.birthDate;
        if (profile.address) profileUpdateData.address = profile.address;
        if (Object.keys(profileUpdateData).length > 0) {
          await prisma.user.update({ where: { id: user.id }, data: profileUpdateData });
        }
        if (profile.specializationNames?.length) {
          await syncProfileSpecializations(user.id, profile.specializationNames);
        }
      } catch (e) {
        console.error("[auth] external department sync after login error:", e);
      }
    })();

    // Fire-and-forget: sync user applications on login
    // (autoUpdateSyncConfig above handles service sync for the user's department)
    syncUserApplications(user.id).catch((e) =>
      console.error("[auth] syncUserApplications error:", e),
    );
    syncUserDepartments(user.id).catch((e) =>
      console.error("[auth] syncUserDepartments error:", e),
    );
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
      id: true, eame: true, forename: true, surname: true, email: true,
      rank: true,
      isAdmin: true, imagePath: true, phonePrimary: true, phoneSecondary: true,
      birthDate: true, address: true, extraInfo: true,
      gdprAcceptedAt: true,
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

// ── POST /api/auth/gdpr-consent ─────────────────
router.post("/gdpr-consent", authenticate, async (req: Request, res: Response) => {
  await prisma.user.update({
    where: { id: req.user!.userId },
    data: { gdprAcceptedAt: new Date() },
  });
  res.json({ ok: true });
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

// ── POST /api/auth/forgot-password ──────────────
const forgotPasswordSchema = z.object({
  email: z.string().email(),
});

router.post("/forgot-password", async (req: Request, res: Response) => {
  try {
    const { email } = forgotPasswordSchema.parse(req.body);
    const normalizedEmail = email.trim().toLowerCase();

    const user = await prisma.user.findUnique({ where: { email: normalizedEmail } });
    if (user) {
      const token = crypto.randomBytes(32).toString("hex");
      const expires = new Date(Date.now() + 60 * 60 * 1000); // 1 hour

      await prisma.user.update({
        where: { id: user.id },
        data: { passwordResetToken: token, passwordResetExpires: expires },
      });

      try {
        await sendPasswordResetEmail(email, token, user.forename);
      } catch (emailErr) {
        console.error("Failed to send password reset email:", emailErr);
      }
    } else {
      // No local user — forward to original Mitroo's forgot-password flow
      try {
        const client = new MitrooClient(EXTERNAL_BASE_URL);
        await client.forgotPassword(email);
        debugExternal("forgot-password proxied to external", { email: normalizedEmail });
      } catch (extErr) {
        console.error("Failed to proxy forgot-password to external Mitroo:", extErr);
      }
    }

    // Always return the same message to avoid leaking whether an email exists
    res.json({ message: "Αν υπάρχει λογαριασμός με αυτό το email, θα λάβεις οδηγίες επαναφοράς." });
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Validation failed", details: err.errors });
      return;
    }
    throw err;
  }
});

// ── POST /api/auth/reset-password ───────────────
const resetPasswordSchema = z.object({
  token: z.string().min(1),
  password: z.string().min(8),
});

router.post("/reset-password", async (req: Request, res: Response) => {
  try {
    const data = resetPasswordSchema.parse(req.body);

    const user = await prisma.user.findFirst({
      where: {
        passwordResetToken: data.token,
        passwordResetExpires: { gt: new Date() },
      },
    });

    if (!user) {
      res.status(400).json({ error: "Μη έγκυρος ή ληγμένος σύνδεσμος επαναφοράς." });
      return;
    }

    const hashed = await bcrypt.hash(data.password, 12);
    await prisma.user.update({
      where: { id: user.id },
      data: { password: hashed, passwordResetToken: null, passwordResetExpires: null },
    });

    res.json({ message: "Ο κωδικός άλλαξε επιτυχώς. Μπορείς να συνδεθείς." });
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Validation failed", details: err.errors });
      return;
    }
    throw err;
  }
});

export default router;
