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
  if (subscriptions.length === 0) {
    console.log(`[push] user ${userId} has no push subscriptions — cannot send`);
    return;
  }
  console.log(`[push] sending to user ${userId}: ${subscriptions.length} subscription(s)`);
  const results = await Promise.allSettled(
    subscriptions.map(async (sub) => {
      try {
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dhKey, auth: sub.authKey } },
          JSON.stringify(payload)
        );
        return 'ok';
      } catch (err: any) {
        if (err.statusCode === 410) {
          // Subscription expired — delete it
          await prisma.pushSubscription.delete({
            where: { id: sub.id },
          }).catch(() => {});
          return 'expired';
        }
        console.error(`[push] send failed for user ${userId} (status ${err.statusCode}):`, err?.message ?? err);
        return 'failed';
      }
    })
  );
  const ok = results.filter(r => r.status === 'fulfilled' && r.value === 'ok').length;
  const expired = results.filter(r => r.status === 'fulfilled' && r.value === 'expired').length;
  const failed = results.filter(r => r.status === 'rejected' || (r.status === 'fulfilled' && r.value === 'failed')).length;
  console.log(`[push] user ${userId} result: ${ok} sent, ${expired} expired, ${failed} failed`);
}
