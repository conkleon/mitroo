import { Router, Request, Response } from "express";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate, isMissionAdminInDepartment } from "../middleware/auth";
import { encrypt } from "../lib/encryption";
import {
  syncUsers,
  syncAllServices,
  syncActiveServices,
  syncClosedServices,
  syncCompletedServices,
  syncFinalizedServices,
  syncShiftApplications,
  diagMissionHours,
} from "../lib/mitrooSync";

const router = Router();
router.use(authenticate);

async function requireSyncAdmin(req: Request, res: Response, deptId: number): Promise<boolean> {
  if (req.user!.isAdmin) return true;
  const allowed = await isMissionAdminInDepartment(req.user!.userId, deptId);
  if (!allowed) {
    res.status(403).json({ error: "Δεν έχετε δικαίωμα" });
    return false;
  }
  return true;
}

const configSchema = z.object({
  username: z.string().min(1).max(255),
  password: z.string().min(1),
  syncEnabled: z.boolean(),
});

// ── GET /api/departments/:id/sync/config ────────
router.get("/:id/sync/config", async (req: Request, res: Response) => {
  const deptId = Number(req.params.id);
  if (!await requireSyncAdmin(req, res, deptId)) return;

  const config = await prisma.departmentSyncConfig.findUnique({
    where: { departmentId: deptId },
    select: {
      externalUsername: true,
      syncEnabled: true,
      lastUserSyncAt: true,
      lastServiceSyncAt: true,
      lastFinalizedSyncAt: true,
      lastSyncStatus: true,
      lastSyncError: true,
    },
  });

  if (!config) {
    res.json({ configured: false, syncEnabled: false });
    return;
  }

  res.json({
    configured: true,
    username: config.externalUsername,
    password: "••••••••",
    syncEnabled: config.syncEnabled,
    lastUserSyncAt: config.lastUserSyncAt,
    lastServiceSyncAt: config.lastServiceSyncAt,
    lastFinalizedSyncAt: config.lastFinalizedSyncAt,
    lastSyncStatus: config.lastSyncStatus,
    lastSyncError: config.lastSyncError,
  });
});

// ── POST /api/departments/:id/sync/config ───────
router.post("/:id/sync/config", async (req: Request, res: Response) => {
  try {
    const deptId = Number(req.params.id);
    if (!await requireSyncAdmin(req, res, deptId)) return;

    const data = configSchema.parse(req.body);
    const encryptedPassword = encrypt(data.password);

    await prisma.departmentSyncConfig.upsert({
      where: { departmentId: deptId },
      update: {
        externalUsername: data.username,
        externalPassword: encryptedPassword,
        syncEnabled: data.syncEnabled,
      },
      create: {
        departmentId: deptId,
        externalUsername: data.username,
        externalPassword: encryptedPassword,
        syncEnabled: data.syncEnabled,
      },
    });

    res.json({ ok: true });
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Validation failed", details: err.errors });
      return;
    }
    throw err;
  }
});

// ── POST /api/departments/:id/sync/users ────────
router.post("/:id/sync/users", async (req: Request, res: Response) => {
  const deptId = Number(req.params.id);
  if (!await requireSyncAdmin(req, res, deptId)) return;

  const result = await syncUsers(deptId);
  res.json(result);
});

// ── POST /api/departments/:id/sync/services ─────
router.post("/:id/sync/services", async (req: Request, res: Response) => {
  const deptId = Number(req.params.id);
  if (!await requireSyncAdmin(req, res, deptId)) return;

  const result = await syncAllServices(deptId);
  res.json(result);
});

// ── POST /api/departments/:id/sync/services/active ──
router.post("/:id/sync/services/active", async (req: Request, res: Response) => {
  const deptId = Number(req.params.id);
  if (!await requireSyncAdmin(req, res, deptId)) return;

  const result = await syncActiveServices(deptId);
  res.json(result);
});

// ── POST /api/departments/:id/sync/services/closed ──
router.post("/:id/sync/services/closed", async (req: Request, res: Response) => {
  const deptId = Number(req.params.id);
  if (!await requireSyncAdmin(req, res, deptId)) return;

  const result = await syncClosedServices(deptId);
  res.json(result);
});

// ── POST /api/departments/:id/sync/services/completed ──
router.post("/:id/sync/services/completed", async (req: Request, res: Response) => {
  const deptId = Number(req.params.id);
  if (!await requireSyncAdmin(req, res, deptId)) return;

  const result = await syncCompletedServices(deptId);
  res.json(result);
});

// ── POST /api/departments/:id/sync/finalized ─────
router.post("/:id/sync/finalized", async (req: Request, res: Response) => {
  const deptId = Number(req.params.id);
  if (!await requireSyncAdmin(req, res, deptId)) return;

  const result = await syncFinalizedServices(deptId);
  res.json(result);
});

// ── POST /api/departments/:id/sync/applications ──
router.post("/:id/sync/applications", async (req: Request, res: Response) => {
  const deptId = Number(req.params.id);
  if (!await requireSyncAdmin(req, res, deptId)) return;

  const result = await syncShiftApplications(deptId);
  res.json(result);
});

// ── GET /api/departments/:id/sync/status ────────
router.get("/:id/sync/status", async (req: Request, res: Response) => {
  const deptId = Number(req.params.id);
  if (!await requireSyncAdmin(req, res, deptId)) return;

  const config = await prisma.departmentSyncConfig.findUnique({
    where: { departmentId: deptId },
    select: {
      lastUserSyncAt: true,
      lastServiceSyncAt: true,
      lastFinalizedSyncAt: true,
      lastSyncStatus: true,
      lastSyncError: true,
    },
  });

  res.json(config ?? { lastUserSyncAt: null, lastServiceSyncAt: null, lastFinalizedSyncAt: null, lastSyncStatus: null });
});

// ── GET /api/departments/:id/sync/diag/:missionId ──
router.get("/:id/sync/diag/:missionId", async (req: Request, res: Response) => {
  const deptId = Number(req.params.id);
  if (!await requireSyncAdmin(req, res, deptId)) return;
  const missionId = Number(req.params.missionId);
  const diag = await diagMissionHours(deptId, missionId);
  res.json(diag);
});

export default router;
