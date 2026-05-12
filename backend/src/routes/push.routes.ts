import { Router, Request, Response } from "express";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate } from "../middleware/auth";

const router = Router();

const subscribeSchema = z.object({
  endpoint: z.string().url(),
  p256dhKey: z.string().min(1),
  authKey: z.string().min(1),
});

const VAPID_PUBLIC_KEY = process.env.VAPID_PUBLIC_KEY;

// Public: client fetches this to configure PushManager
router.get("/vapid-public-key", (_req: Request, res: Response) => {
  if (!VAPID_PUBLIC_KEY) { res.status(500).json({ error: "VAPID not configured" }); return; }
  res.json({ publicKey: VAPID_PUBLIC_KEY });
});

router.use(authenticate);

// POST /api/push/subscribe — store or update push subscription for current user
router.post("/subscribe", async (req: Request, res: Response) => {
  try {
    const { endpoint, p256dhKey, authKey } = subscribeSchema.parse(req.body);
    await prisma.pushSubscription.upsert({
      where: { userId_endpoint: { userId: req.user!.userId, endpoint } },
      update: { p256dhKey, authKey },
      create: { userId: req.user!.userId, endpoint, p256dhKey, authKey },
    });
    res.status(201).json({ ok: true });
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// DELETE /api/push/unsubscribe?endpoint=... — remove subscription
router.delete("/unsubscribe", async (req: Request, res: Response) => {
  try {
    const { endpoint } = z.object({ endpoint: z.string().url() }).parse({ endpoint: req.query.endpoint });
    const result = await prisma.pushSubscription.deleteMany({
      where: { userId: req.user!.userId, endpoint },
    });
    res.json({ removed: result.count });
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

export default router;
