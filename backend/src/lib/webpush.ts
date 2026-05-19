import webpush from "web-push";
import prisma from "./prisma";

webpush.setVapidDetails(
  `mailto:${process.env.VAPID_EMAIL}`,
  process.env.VAPID_PUBLIC_KEY!,
  process.env.VAPID_PRIVATE_KEY!
);

export async function sendPushToUser(
  userId: number,
  payload: { title: string; body: string; tag?: string; route?: string; data?: Record<string, unknown> }
): Promise<void> {
  const subscriptions = await prisma.pushSubscription.findMany({ where: { userId } });
  await Promise.all(
    subscriptions.map(async (sub) => {
      try {
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dhKey, auth: sub.authKey } },
          JSON.stringify(payload)
        );
      } catch (err: any) {
        if (err.statusCode === 410) {
          // Subscription expired — delete it
          await prisma.pushSubscription.delete({
            where: { id: sub.id },
          }).catch(() => {});
        }
      }
    })
  );
}
