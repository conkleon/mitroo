import { Router, Request, Response } from "express";
import prisma from "../lib/prisma";
import { authenticate } from "../middleware/auth";

const router = Router();

// Public: client fetches this to configure PushManager
router.get("/vapid-public-key", (_req: Request, res: Response) => {
  res.json({ publicKey: process.env.VAPID_PUBLIC_KEY });
});

router.use(authenticate);

// POST /api/push/subscribe — store or update push subscription for current user
router.post("/subscribe", async (req: Request, res: Response) => {
  const { endpoint, p256dhKey, authKey } = req.body;
  if (!endpoint || !p256dhKey || !authKey) {
    res.status(400).json({ error: "Missing subscription fields" });
    return;
  }
  await prisma.pushSubscription.upsert({
    where: { userId_endpoint: { userId: req.user!.userId, endpoint } },
    update: { p256dhKey, authKey },
    create: { userId: req.user!.userId, endpoint, p256dhKey, authKey },
  });
  res.status(201).json({ ok: true });
});

// DELETE /api/push/unsubscribe — remove subscription by endpoint
router.delete("/unsubscribe", async (req: Request, res: Response) => {
  const { endpoint } = req.body;
  if (!endpoint) {
    res.status(400).json({ error: "Missing endpoint" });
    return;
  }
  await prisma.pushSubscription.deleteMany({
    where: { userId: req.user!.userId, endpoint },
  });
  res.status(204).end();
});

export default router;
