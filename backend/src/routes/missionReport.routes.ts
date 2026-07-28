import { Router, Request, Response } from "express";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate, getMissionAdminDepartmentIds } from "../middleware/auth";
import { aggregateMissionReportData, MissionReportData } from "../lib/missionReportData";
import { anonymizeVictimForPrompt } from "../lib/missionReportAnonymize";
import { buildPressReleasePrompt } from "../lib/missionReportPrompt";
import { getAIProvider } from "../lib/ai";
import { renderMissionReportPdf } from "../lib/missionReportPdf";

const router = Router();
router.use(authenticate);

interface ReportScope {
  isAdmin: boolean;
  departmentIds: number[];
}

async function getReportScope(req: Request): Promise<ReportScope> {
  if (req.user!.isAdmin) {
    return { isAdmin: true, departmentIds: [] };
  }
  const departmentIds = await getMissionAdminDepartmentIds(req.user!.userId);
  return { isAdmin: false, departmentIds };
}

/**
 * Re-validates that every supplied serviceId belongs to a department the caller
 * administers. Responds with 403 and returns false when the check fails.
 * Global admins are always allowed.
 */
async function validateServiceScope(
  scope: ReportScope,
  serviceIds: number[],
  res: Response,
): Promise<boolean> {
  if (scope.isAdmin) return true;
  const allowedCount = await prisma.service.count({
    where: { id: { in: serviceIds }, departmentId: { in: scope.departmentIds } },
  });
  if (allowedCount !== serviceIds.length) {
    res.status(403).json({ error: "Δεν έχετε δικαίωμα για μία ή περισσότερες αποστολές" });
    return false;
  }
  return true;
}

// ── GET /api/reports/missions ───────────────────
router.get("/missions", async (req: Request, res: Response) => {
  try {
    const scope = await getReportScope(req);
    if (!scope.isAdmin && scope.departmentIds.length === 0) {
      res.status(403).json({ error: "Δεν έχετε δικαίωμα πρόσβασης σε αναφορές αποστολών" });
      return;
    }

    const departmentIdParam = req.query.departmentId ? Number(req.query.departmentId) : undefined;
    if (
      departmentIdParam !== undefined &&
      !scope.isAdmin &&
      !scope.departmentIds.includes(departmentIdParam)
    ) {
      res.status(403).json({ error: "Δεν έχετε δικαίωμα για αυτό το τμήμα" });
      return;
    }

    const where: any = scope.isAdmin ? {} : { departmentId: { in: scope.departmentIds } };
    if (departmentIdParam !== undefined) {
      where.departmentId = departmentIdParam;
    }

    let from: Date | undefined;
    if (req.query.from) {
      from = new Date(req.query.from as string);
      if (isNaN(from.getTime())) {
        res.status(400).json({ error: "Μη έγκυρη ημερομηνία" });
        return;
      }
    }
    let to: Date | undefined;
    if (req.query.to) {
      to = new Date(req.query.to as string);
      if (isNaN(to.getTime())) {
        res.status(400).json({ error: "Μη έγκυρη ημερομηνία" });
        return;
      }
    }
    if (from) where.OR = [{ endAt: { gte: from } }, { endAt: null }];
    if (to) where.startAt = { lte: to };

    const search = (req.query.search as string | undefined)?.trim();
    if (search) {
      where.name = { contains: search, mode: "insensitive" };
    }

    let take: number | undefined;
    if (req.query.limit) {
      const parsed = Number(req.query.limit);
      if (!Number.isInteger(parsed) || parsed <= 0) {
        res.status(400).json({ error: "Μη έγκυρο όριο αποτελεσμάτων" });
        return;
      }
      take = parsed;
    }

    const missions = await prisma.service.findMany({
      where,
      select: {
        id: true,
        name: true,
        startAt: true,
        endAt: true,
        lifecycleStatus: true,
        department: { select: { id: true, name: true } },
      },
      orderBy: { startAt: "desc" },
      ...(take !== undefined ? { take } : {}),
    });

    res.json(missions);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Validation failed", details: err.errors });
      return;
    }
    throw err;
  }
});

// ── POST /api/reports/generate ──────────────────
const generateSchema = z.union([
  z.object({ serviceIds: z.array(z.number().int()).min(1) }),
  z.object({
    departmentId: z.number().int().optional(),
    from: z.string().datetime(),
    to: z.string().datetime(),
  }),
]);

router.post("/generate", async (req: Request, res: Response) => {
  try {
    const scope = await getReportScope(req);
    if (!scope.isAdmin && scope.departmentIds.length === 0) {
      res.status(403).json({ error: "Δεν έχετε δικαίωμα πρόσβασης σε αναφορές αποστολών" });
      return;
    }

    const input = generateSchema.parse(req.body);

    let serviceIds: number[];
    if ("serviceIds" in input) {
      serviceIds = input.serviceIds;
    } else {
      if (
        input.departmentId !== undefined &&
        !scope.isAdmin &&
        !scope.departmentIds.includes(input.departmentId)
      ) {
        res.status(403).json({ error: "Δεν έχετε δικαίωμα για αυτό το τμήμα" });
        return;
      }

      const where: any = {
        startAt: { lte: new Date(input.to) },
        OR: [{ endAt: { gte: new Date(input.from) } }, { endAt: null }],
      };
      if (input.departmentId !== undefined) {
        where.departmentId = input.departmentId;
      } else if (!scope.isAdmin) {
        where.departmentId = { in: scope.departmentIds };
      }

      const resolved = await prisma.service.findMany({ where, select: { id: true } });
      serviceIds = resolved.map((s) => s.id);
    }

    if (serviceIds.length === 0) {
      res.status(400).json({ error: "Δεν βρέθηκαν αποστολές για τα επιλεγμένα κριτήρια" });
      return;
    }

    if (!(await validateServiceScope(scope, serviceIds, res))) return;

    const structuredData: MissionReportData = await aggregateMissionReportData(serviceIds);

    let narrativeDraft: string | null = null;
    let narrativeError: string | undefined;
    try {
      const provider = getAIProvider();
      const anonymizedVictims = structuredData.victims.map(anonymizeVictimForPrompt);
      const prompt = buildPressReleasePrompt(structuredData, anonymizedVictims);
      narrativeDraft = await provider.generatePressRelease(prompt);
    } catch (err: any) {
      narrativeError = err.message || "Η δημιουργία του κειμένου απέτυχε";
    }

    res.json({ structuredData, narrativeDraft, narrativeError });
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Validation failed", details: err.errors });
      return;
    }
    throw err;
  }
});

// ── POST /api/reports/pdf ────────────────────────
// The client only supplies the mission ids + the (possibly hand-edited) narrative.
// The structured data is always re-aggregated server-side so the renderer can never
// be fed an untrusted / malformed blob, and so the request body stays tiny.
const pdfSchema = z.object({
  serviceIds: z.array(z.number().int()).min(1),
  narrativeText: z.string(),
});

router.post("/pdf", async (req: Request, res: Response) => {
  try {
    const scope = await getReportScope(req);
    if (!scope.isAdmin && scope.departmentIds.length === 0) {
      res.status(403).json({ error: "Δεν έχετε δικαίωμα πρόσβασης σε αναφορές αποστολών" });
      return;
    }

    const { serviceIds, narrativeText } = pdfSchema.parse(req.body);

    if (!(await validateServiceScope(scope, serviceIds, res))) return;

    const structuredData: MissionReportData = await aggregateMissionReportData(serviceIds);
    const buffer = await renderMissionReportPdf(structuredData, narrativeText);
    res.setHeader("Content-Type", "application/pdf");
    res.setHeader("Content-Disposition", 'attachment; filename="mission-report.pdf"');
    res.send(buffer);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Validation failed", details: err.errors });
      return;
    }
    throw err;
  }
});

export default router;
