import { Router, Request, Response } from "express";
import prisma from "../lib/prisma";
import redis from "../lib/redis";

const router = Router();

router.get("/", async (_req: Request, res: Response) => {
  const checks: Record<string, string> = { api: "ok" };

  try {
    await prisma.$queryRaw`SELECT 1`;
    checks.database = "ok";
  } catch {
    checks.database = "error";
  }

  try {
    await redis.ping();
    checks.redis = "ok";
  } catch {
    checks.redis = "error";
  }

  const healthy = Object.values(checks).every((v) => v === "ok");
  res.status(healthy ? 200 : 503).json({ status: healthy ? "healthy" : "degraded", checks });
});

export default router;
