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

// ── GET /api/reports/missions ───────────────────
router.get("/missions", async (req: Request, res: Response) => {
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

  const from = req.query.from ? new Date(req.query.from as string) : undefined;
  const to = req.query.to ? new Date(req.query.to as string) : undefined;
  if (from) where.OR = [{ endAt: { gte: from } }, { endAt: null }];
  if (to) where.startAt = { lte: to };

  const search = (req.query.search as string | undefined)?.trim();
  if (search) {
    where.name = { contains: search, mode: "insensitive" };
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
  });

  res.json(missions);
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

    if (!scope.isAdmin) {
      const allowedCount = await prisma.service.count({
        where: { id: { in: serviceIds }, departmentId: { in: scope.departmentIds } },
      });
      if (allowedCount !== serviceIds.length) {
        res.status(403).json({ error: "Δεν έχετε δικαίωμα για μία ή περισσότερες αποστολές" });
        return;
      }
    }

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
const pdfSchema = z.object({
  structuredData: z.custom<MissionReportData>((val) => typeof val === "object" && val !== null),
  narrativeText: z.string(),
});

router.post("/pdf", async (req: Request, res: Response) => {
  try {
    const scope = await getReportScope(req);
    if (!scope.isAdmin && scope.departmentIds.length === 0) {
      res.status(403).json({ error: "Δεν έχετε δικαίωμα πρόσβασης σε αναφορές αποστολών" });
      return;
    }

    const { structuredData, narrativeText } = pdfSchema.parse(req.body);
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
