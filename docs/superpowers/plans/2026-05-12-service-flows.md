# Service Flows: Auth Guards, Enrollment Fix & Notifications — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix missing authorization on all service mutation endpoints, correct self-enrollment to use the authenticated user's ID, add email + web push notifications on enrollment events, and remove the stub create dialog from ServicesScreen.

**Architecture:** Backend auth uses the existing `isMissionAdminInDepartment` from `middleware/auth.ts`. A local `requireServiceAdmin(req, res, departmentId)` helper wraps it and sends the 403 automatically. Notifications are fire-and-forget inside a try/catch, matching the existing pattern in `trainingApplication.routes.ts`. Web push uses `web-push` (VAPID); the Flutter Web client subscribes via a JS helper in `index.html`, called from Dart via `dart:js`.

**Tech Stack:** Node.js/Express/TypeScript, Prisma, nodemailer (existing), web-push (new npm package), Flutter Web, dart:js interop

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `backend/prisma/schema.prisma` | Modify | Add `PushSubscription` model + `User` relation |
| `backend/src/lib/webpush.ts` | Create | VAPID config, `sendPushToUser(userId, payload)` |
| `backend/src/routes/push.routes.ts` | Create | `POST /push/subscribe`, `DELETE /push/unsubscribe`, `GET /push/vapid-public-key` |
| `backend/src/app.ts` | Modify | Mount push router at `/api/push` |
| `backend/src/lib/email.ts` | Modify | Add `sendServiceEnrollmentEmail` + `sendServiceStatusEmail` |
| `backend/src/routes/service.routes.ts` | Modify | `requireServiceAdmin` helper; auth guards on all mutations; fix enroll; trigger notifications |
| `frontend/web/push_sw.js` | Create | Service worker — handle `push` events, show notification |
| `frontend/web/index.html` | Modify | Register `push_sw.js`; add `mitrooSubscribePush` JS helper |
| `frontend/lib/services/push_service.dart` | Create | Dart — fetch VAPID key, call JS helper, POST subscription to backend |
| `frontend/lib/providers/auth_provider.dart` | Modify | Call `PushService.init()` after successful login and auto-login |
| `frontend/lib/screens/services_screen.dart` | Modify | Remove `_showCreateDialog()`; replace call site with `context.push('/admin/services/new')` |

---

## Task 1: Prisma — add PushSubscription model

**Files:**
- Modify: `backend/prisma/schema.prisma`

- [ ] **Step 1: Add model to schema**

Open `backend/prisma/schema.prisma`. Add the following block **before** the `Vehicle` model section (anywhere after the `User` model closing brace is fine):

```prisma
// ──────────────────────────────────────────────
// Web Push subscriptions
// ──────────────────────────────────────────────

model PushSubscription {
  id        Int      @id @default(autoincrement())
  userId    Int      @map("user_id")
  endpoint  String   @db.Text
  p256dhKey String   @map("p256dh_key") @db.Text
  authKey   String   @map("auth_key") @db.Text
  createdAt DateTime @default(now()) @map("created_at")

  user User @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@unique([userId, endpoint])
  @@map("push_subscriptions")
}
```

- [ ] **Step 2: Add relation to User model**

In the `User` model, add one line to the relations block (after `reviewedTrainingApplications` and `linkedTrainingApplications`):

```prisma
  pushSubscriptions    PushSubscription[]
```

- [ ] **Step 3: Run migration**

```bash
cd backend
npm run prisma:migrate
```

When prompted for a migration name, enter: `add_push_subscriptions`

Expected: migration applies cleanly, `push_subscriptions` table created.

- [ ] **Step 4: Regenerate Prisma client**

```bash
npm run prisma:generate
```

Expected: client regenerated with `PushSubscription` model available.

- [ ] **Step 5: Commit**

```bash
git add backend/prisma/schema.prisma backend/prisma/migrations/
git commit -m "feat: add push_subscriptions table"
```

---

## Task 2: Backend — install web-push + create webpush.ts

**Files:**
- Create: `backend/src/lib/webpush.ts`

- [ ] **Step 1: Install web-push**

```bash
cd backend
npm install web-push
npm install --save-dev @types/web-push
```

Expected: `web-push` and `@types/web-push` appear in `package.json`.

- [ ] **Step 2: Generate VAPID keys**

```bash
npx web-push generate-vapid-keys
```

Expected output looks like:
```
Public Key:
BFjNqS...

Private Key:
abc123...
```

Copy both values. Add them to your `.env` file:
```
VAPID_PUBLIC_KEY=BFjNqS...
VAPID_PRIVATE_KEY=abc123...
VAPID_EMAIL=admin@mitroo.local
```

Also add the keys (without values) to `.env.example`:
```
VAPID_PUBLIC_KEY=
VAPID_PRIVATE_KEY=
VAPID_EMAIL=
```

- [ ] **Step 3: Create webpush.ts**

Create `backend/src/lib/webpush.ts`:

```typescript
import webpush from "web-push";
import prisma from "./prisma";

webpush.setVapidDetails(
  `mailto:${process.env.VAPID_EMAIL}`,
  process.env.VAPID_PUBLIC_KEY!,
  process.env.VAPID_PRIVATE_KEY!
);

export async function sendPushToUser(userId: number, payload: { title: string; body: string }): Promise<void> {
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
```

- [ ] **Step 4: Verify TypeScript compiles**

```bash
cd backend
npm run build
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add backend/src/lib/webpush.ts backend/package.json backend/package-lock.json .env.example
git commit -m "feat: add web-push lib with sendPushToUser helper"
```

---

## Task 3: Backend — push.routes.ts

**Files:**
- Create: `backend/src/routes/push.routes.ts`

- [ ] **Step 1: Create push routes**

Create `backend/src/routes/push.routes.ts`:

```typescript
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
  if (!endpoint) { res.status(400).json({ error: "Missing endpoint" }); return; }
  await prisma.pushSubscription.deleteMany({
    where: { userId: req.user!.userId, endpoint },
  });
  res.status(204).end();
});

export default router;
```

- [ ] **Step 2: Verify TypeScript compiles**

```bash
cd backend && npm run build
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add backend/src/routes/push.routes.ts
git commit -m "feat: add push subscribe/unsubscribe endpoints"
```

---

## Task 4: Backend — mount push router in app.ts

**Files:**
- Modify: `backend/src/app.ts`

- [ ] **Step 1: Add import**

In `backend/src/app.ts`, add the following import after the existing route imports:

```typescript
import pushRoutes from "./routes/push.routes";
```

- [ ] **Step 2: Mount the router**

In `backend/src/app.ts`, add the following line in the `// ── Routes ──` section, after the `categoryRoutes` line:

```typescript
app.use("/api/push", pushRoutes);
```

- [ ] **Step 3: Verify and commit**

```bash
cd backend && npm run build
git add backend/src/app.ts
git commit -m "feat: mount push router at /api/push"
```

---

## Task 5: Backend — email notification functions

**Files:**
- Modify: `backend/src/lib/email.ts`

- [ ] **Step 1: Add sendServiceEnrollmentEmail**

Open `backend/src/lib/email.ts`. Add this function at the end of the file (the `transporter`, `FROM`, `APP_NAME`, and `FRONTEND_URL` constants are already defined at the top of that file):

```typescript
export async function sendServiceEnrollmentEmail(
  to: string,
  adminName: string,
  applicantName: string,
  serviceName: string
) {
  await transporter.sendMail({
    from: FROM,
    to,
    subject: `${APP_NAME} – Νέα αίτηση για "${serviceName}"`,
    html: `
      <div style="font-family:sans-serif;max-width:560px;margin:auto;padding:24px">
        <h2 style="color:#DC2626">Νέα αίτηση συμμετοχής</h2>
        <p>Γεια σου <strong>${adminName}</strong>,</p>
        <p>Ο/Η <strong>${applicantName}</strong> αιτήθηκε συμμετοχή στην υπηρεσία <strong>"${serviceName}"</strong>.</p>
        <p>Συνδέσου στην πλατφόρμα για να αποδεχθείς ή να απορρίψεις την αίτηση.</p>
        <p style="text-align:center;margin:24px 0">
          <a href="${FRONTEND_URL}"
             style="background:#DC2626;color:#fff;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:600">
            Διαχείριση αιτήσεων
          </a>
        </p>
      </div>
    `,
  });
}

export async function sendServiceStatusEmail(
  to: string,
  userName: string,
  serviceName: string,
  status: "accepted" | "rejected"
) {
  const accepted = status === "accepted";
  await transporter.sendMail({
    from: FROM,
    to,
    subject: `${APP_NAME} – Ενημέρωση αίτησης για "${serviceName}"`,
    html: `
      <div style="font-family:sans-serif;max-width:560px;margin:auto;padding:24px">
        <h2 style="color:${accepted ? "#059669" : "#DC2626"}">
          ${accepted ? "Η αίτησή σας εγκρίθηκε" : "Η αίτησή σας απορρίφθηκε"}
        </h2>
        <p>Γεια σου <strong>${userName}</strong>,</p>
        <p>Η αίτησή σας για συμμετοχή στην υπηρεσία <strong>"${serviceName}"</strong>
           ${accepted ? "εγκρίθηκε" : "απορρίφθηκε"}.</p>
        <p style="text-align:center;margin:24px 0">
          <a href="${FRONTEND_URL}"
             style="background:#DC2626;color:#fff;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:600">
            Άνοιγμα εφαρμογής
          </a>
        </p>
      </div>
    `,
  });
}
```

- [ ] **Step 2: Verify and commit**

```bash
cd backend && npm run build
git add backend/src/lib/email.ts
git commit -m "feat: add service enrollment email notification functions"
```

---

## Task 6: Backend — requireServiceAdmin helper + auth guards on all mutations

**Files:**
- Modify: `backend/src/routes/service.routes.ts`

- [ ] **Step 1: Add import for isMissionAdminInDepartment**

At the top of `backend/src/routes/service.routes.ts`, change the auth import line from:

```typescript
import { authenticate } from "../middleware/auth";
```

to:

```typescript
import { authenticate, isMissionAdminInDepartment } from "../middleware/auth";
```

- [ ] **Step 2: Add requireServiceAdmin helper**

Add this helper function immediately after the `statusSchema` declaration (around line 32, before the first `router.get` call):

```typescript
/** Returns true and continues if caller is global admin or missionAdmin of the given department.
 *  Returns false after sending 403 if not authorised. */
async function requireServiceAdmin(req: Request, res: Response, departmentId: number): Promise<boolean> {
  if (req.user!.isAdmin) return true;
  const allowed = await isMissionAdminInDepartment(req.user!.userId, departmentId);
  if (!allowed) {
    res.status(403).json({ error: "Δεν έχετε δικαίωμα" });
    return false;
  }
  return true;
}
```

- [ ] **Step 3: Guard POST /api/services (create)**

Find the `router.post("/", ...)` handler. Replace the body with:

```typescript
router.post("/", async (req: Request, res: Response) => {
  try {
    const data = createSchema.parse(req.body);
    if (!await requireServiceAdmin(req, res, data.departmentId)) return;
    const service = await prisma.service.create({
      data: {
        ...data,
        startAt: data.startAt ? new Date(data.startAt) : undefined,
        endAt: data.endAt ? new Date(data.endAt) : undefined,
      },
      include: { department: { select: { id: true, name: true } } },
    });
    res.status(201).json(service);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});
```

- [ ] **Step 4: Guard PATCH /api/services/:id (update)**

Find `router.patch("/:id", ...)`. Replace with:

```typescript
router.patch("/:id", async (req: Request, res: Response) => {
  try {
    const service = await prisma.service.findUnique({ where: { id: Number(req.params.id) }, select: { departmentId: true } });
    if (!service) { res.status(404).json({ error: "Service not found" }); return; }
    if (!await requireServiceAdmin(req, res, service.departmentId)) return;
    const data = createSchema.partial().parse(req.body);
    const updated = await prisma.service.update({
      where: { id: Number(req.params.id) },
      data: {
        ...data,
        startAt: data.startAt ? new Date(data.startAt) : undefined,
        endAt: data.endAt ? new Date(data.endAt) : undefined,
      },
    });
    res.json(updated);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});
```

- [ ] **Step 5: Guard DELETE /api/services/:id**

Find `router.delete("/:id", ...)`. Replace with:

```typescript
router.delete("/:id", async (req: Request, res: Response) => {
  const service = await prisma.service.findUnique({ where: { id: Number(req.params.id) }, select: { departmentId: true } });
  if (!service) { res.status(404).json({ error: "Service not found" }); return; }
  if (!await requireServiceAdmin(req, res, service.departmentId)) return;
  await prisma.service.delete({ where: { id: Number(req.params.id) } });
  res.status(204).end();
});
```

- [ ] **Step 6: Guard PATCH /:sid/users/:uid/status**

Find `router.patch("/:sid/users/:uid/status", ...)`. Replace with:

```typescript
router.patch("/:sid/users/:uid/status", async (req: Request, res: Response) => {
  try {
    const service = await prisma.service.findUnique({ where: { id: Number(req.params.sid) }, select: { departmentId: true } });
    if (!service) { res.status(404).json({ error: "Service not found" }); return; }
    if (!await requireServiceAdmin(req, res, service.departmentId)) return;
    const { status } = statusSchema.parse(req.body);
    const record = await prisma.userService.update({
      where: { userId_serviceId: { userId: Number(req.params.uid), serviceId: Number(req.params.sid) } },
      data: { status },
    });
    res.json(record);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});
```

- [ ] **Step 7: Guard PATCH /:sid/users/:uid/hours**

Find `router.patch("/:sid/users/:uid/hours", ...)`. Replace with:

```typescript
router.patch("/:sid/users/:uid/hours", async (req: Request, res: Response) => {
  const service = await prisma.service.findUnique({ where: { id: Number(req.params.sid) }, select: { departmentId: true } });
  if (!service) { res.status(404).json({ error: "Service not found" }); return; }
  if (!await requireServiceAdmin(req, res, service.departmentId)) return;
  const { hours, hoursVol, hoursTraining, hoursTrainers, hoursTEP } = req.body;
  const record = await prisma.userService.update({
    where: { userId_serviceId: { userId: Number(req.params.uid), serviceId: Number(req.params.sid) } },
    data: {
      ...(typeof hours === "number" && { hours }),
      ...(typeof hoursVol === "number" && { hoursVol }),
      ...(typeof hoursTraining === "number" && { hoursTraining }),
      ...(typeof hoursTrainers === "number" && { hoursTrainers }),
      ...(typeof hoursTEP === "number" && { hoursTEP }),
    },
  });
  res.json(record);
});
```

- [ ] **Step 8: Guard DELETE /:sid/users/:uid**

Find `router.delete("/:sid/users/:uid", ...)`. Replace with:

```typescript
router.delete("/:sid/users/:uid", async (req: Request, res: Response) => {
  const service = await prisma.service.findUnique({ where: { id: Number(req.params.sid) }, select: { departmentId: true } });
  if (!service) { res.status(404).json({ error: "Service not found" }); return; }
  if (!await requireServiceAdmin(req, res, service.departmentId)) return;
  await prisma.userService.delete({
    where: { userId_serviceId: { userId: Number(req.params.uid), serviceId: Number(req.params.sid) } },
  });
  res.status(204).end();
});
```

- [ ] **Step 9: Guard PATCH /:id/responsible**

Find `router.patch("/:id/responsible", ...)`. Replace with:

```typescript
router.patch("/:id/responsible", async (req: Request, res: Response) => {
  const serviceId = Number(req.params.id);
  const service = await prisma.service.findUnique({ where: { id: serviceId }, select: { departmentId: true } });
  if (!service) { res.status(404).json({ error: "Service not found" }); return; }
  if (!await requireServiceAdmin(req, res, service.departmentId)) return;
  const { responsibleUserId } = req.body;
  const updated = await prisma.service.update({
    where: { id: serviceId },
    data: { responsibleUserId: responsibleUserId ?? null },
    include: { responsibleUser: { select: { id: true, eame: true, forename: true, surname: true, imagePath: true } } },
  });
  res.json(updated);
});
```

- [ ] **Step 10: Guard POST /:id/visibility**

Find `router.post("/:id/visibility", ...)`. Replace with:

```typescript
router.post("/:id/visibility", async (req: Request, res: Response) => {
  const serviceId = Number(req.params.id);
  const service = await prisma.service.findUnique({ where: { id: serviceId }, select: { departmentId: true } });
  if (!service) { res.status(404).json({ error: "Service not found" }); return; }
  if (!await requireServiceAdmin(req, res, service.departmentId)) return;
  const specId = Number(req.body.specializationId);
  const record = await prisma.serviceVisibility.upsert({
    where: { serviceId_specializationId: { serviceId, specializationId: specId } },
    update: {},
    create: { serviceId, specializationId: specId },
    include: { specialization: true },
  });
  res.status(201).json(record);
});
```

- [ ] **Step 11: Guard DELETE /:sid/visibility/:specId**

Find `router.delete("/:sid/visibility/:specId", ...)`. Replace with:

```typescript
router.delete("/:sid/visibility/:specId", async (req: Request, res: Response) => {
  const serviceId = Number(req.params.sid);
  const service = await prisma.service.findUnique({ where: { id: serviceId }, select: { departmentId: true } });
  if (!service) { res.status(404).json({ error: "Service not found" }); return; }
  if (!await requireServiceAdmin(req, res, service.departmentId)) return;
  await prisma.serviceVisibility.delete({
    where: { serviceId_specializationId: { serviceId, specializationId: Number(req.params.specId) } },
  });
  res.status(204).end();
});
```

- [ ] **Step 12: Verify and commit**

```bash
cd backend && npm run build
git add backend/src/routes/service.routes.ts
git commit -m "feat: add requireServiceAdmin guard to all service mutation endpoints"
```

---

## Task 7: Backend — fix enroll endpoint + enrollment notifications

**Files:**
- Modify: `backend/src/routes/service.routes.ts`

- [ ] **Step 1: Add notification imports**

At the top of `backend/src/routes/service.routes.ts`, add imports for the notification helpers:

```typescript
import { sendServiceEnrollmentEmail, sendServiceStatusEmail } from "../lib/email";
import { sendPushToUser } from "../lib/webpush";
```

- [ ] **Step 2: Replace POST /:id/enroll**

Find the existing `router.post("/:id/enroll", ...)` handler and replace it entirely with:

```typescript
router.post("/:id/enroll", async (req: Request, res: Response) => {
  try {
    const requesterId = req.user!.userId;
    const serviceId = Number(req.params.id);

    const service = await prisma.service.findUnique({
      where: { id: serviceId },
      include: { department: { select: { id: true, name: true } } },
    });
    if (!service) { res.status(404).json({ error: "Service not found" }); return; }

    const isServiceAdmin = req.user!.isAdmin || await isMissionAdminInDepartment(requesterId, service.departmentId);

    let targetUserId: number;
    let status: "requested" | "accepted" | "rejected";

    if (isServiceAdmin) {
      const data = enrollSchema.parse(req.body);
      targetUserId = data.userId ?? requesterId;
      status = data.status ?? "requested";
    } else {
      // Self-enroll: must belong to the service's department
      targetUserId = requesterId;
      status = "requested";
      const membership = await prisma.userDepartment.count({
        where: { userId: requesterId, departmentId: service.departmentId },
      });
      if (!membership) {
        res.status(403).json({ error: "Δεν ανήκετε σε αυτό το τμήμα" });
        return;
      }
    }

    const record = await prisma.userService.create({
      data: {
        userId: targetUserId,
        serviceId,
        status,
        hours: service.defaultHours,
        hoursVol: service.defaultHoursVol,
        hoursTraining: service.defaultHoursTraining,
        hoursTrainers: service.defaultHoursTrainers,
        hoursTEP: service.defaultHoursTEP,
      },
      include: {
        user: { select: { id: true, eame: true, forename: true, surname: true, email: true } },
      },
    });

    // Notify missionAdmins of this department when a regular user self-enrolls
    if (status === "requested") {
      const applicantName = `${record.user.forename} ${record.user.surname}`.trim();
      const admins = await prisma.userDepartment.findMany({
        where: { departmentId: service.departmentId, role: "missionAdmin" },
        include: { user: { select: { id: true, email: true, forename: true, surname: true } } },
      });
      for (const admin of admins) {
        const adminName = `${admin.user.forename} ${admin.user.surname}`.trim();
        try {
          await sendServiceEnrollmentEmail(admin.user.email, adminName, applicantName, service.name);
        } catch { /* non-fatal */ }
        try {
          await sendPushToUser(admin.user.id, {
            title: "Νέα αίτηση",
            body: `${applicantName} αιτήθηκε για "${service.name}"`,
          });
        } catch { /* non-fatal */ }
      }
    }

    res.status(201).json(record);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    if (err?.code === "P2002") { res.status(409).json({ error: "Ήδη εγγεγραμμένος σε αυτή την υπηρεσία" }); return; }
    throw err;
  }
});
```

- [ ] **Step 3: Verify and commit**

```bash
cd backend && npm run build
git add backend/src/routes/service.routes.ts
git commit -m "feat: fix enroll endpoint — self-enroll uses requester id, dept check, notify admins"
```

---

## Task 8: Backend — status change notifications

**Files:**
- Modify: `backend/src/routes/service.routes.ts`

- [ ] **Step 1: Extend PATCH /:sid/users/:uid/status to send notifications**

Find the `router.patch("/:sid/users/:uid/status", ...)` handler you wrote in Task 6 Step 6 and replace it with this version that adds notifications after updating the status:

```typescript
router.patch("/:sid/users/:uid/status", async (req: Request, res: Response) => {
  try {
    const sid = Number(req.params.sid);
    const uid = Number(req.params.uid);
    const service = await prisma.service.findUnique({ where: { id: sid }, select: { departmentId: true, name: true } });
    if (!service) { res.status(404).json({ error: "Service not found" }); return; }
    if (!await requireServiceAdmin(req, res, service.departmentId)) return;
    const { status } = statusSchema.parse(req.body);
    const record = await prisma.userService.update({
      where: { userId_serviceId: { userId: uid, serviceId: sid } },
      data: { status },
      include: { user: { select: { id: true, email: true, forename: true, surname: true } } },
    });

    if (status === "accepted" || status === "rejected") {
      const userName = `${record.user.forename} ${record.user.surname}`.trim();
      try {
        await sendServiceStatusEmail(record.user.email, userName, service.name, status);
      } catch { /* non-fatal */ }
      try {
        await sendPushToUser(record.user.id, {
          title: "Ενημέρωση αίτησης",
          body: `Η αίτησή σας για "${service.name}" ${status === "accepted" ? "εγκρίθηκε" : "απορρίφθηκε"}`,
        });
      } catch { /* non-fatal */ }
    }

    res.json(record);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});
```

- [ ] **Step 2: Verify and commit**

```bash
cd backend && npm run build
git add backend/src/routes/service.routes.ts
git commit -m "feat: notify user via email+push on enrollment status change"
```

---

## Task 9: Frontend — push_sw.js service worker

**Files:**
- Create: `frontend/web/push_sw.js`

- [ ] **Step 1: Create the service worker**

Create `frontend/web/push_sw.js`:

```javascript
self.addEventListener('push', function (event) {
  const data = event.data ? event.data.json() : {};
  const title = data.title || 'Mitroo';
  const options = {
    body: data.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  event.waitUntil(clients.openWindow('/'));
});
```

- [ ] **Step 2: Commit**

```bash
git add frontend/web/push_sw.js
git commit -m "feat: add push service worker"
```

---

## Task 10: Frontend — register service worker + JS helper in index.html

**Files:**
- Modify: `frontend/web/index.html`

- [ ] **Step 1: Add service worker registration and push subscription helper**

Open `frontend/web/index.html`. Add the following `<script>` block just before the closing `</body>` tag:

```html
<script>
  // Register push service worker
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/push_sw.js');
  }

  // Helper called from Dart via dart:js
  function urlBase64ToUint8Array(base64String) {
    var padding = '='.repeat((4 - base64String.length % 4) % 4);
    var base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
    var rawData = window.atob(base64);
    var outputArray = new Uint8Array(rawData.length);
    for (var i = 0; i < rawData.length; ++i) {
      outputArray[i] = rawData.charCodeAt(i);
    }
    return outputArray;
  }

  window.mitrooSubscribePush = function(vapidPublicKey, callback) {
    if (!('Notification' in window) || !('serviceWorker' in navigator)) {
      callback(null);
      return;
    }
    Notification.requestPermission().then(function(permission) {
      if (permission !== 'granted') { callback(null); return; }
      navigator.serviceWorker.ready.then(function(reg) {
        reg.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: urlBase64ToUint8Array(vapidPublicKey),
        }).then(function(sub) {
          var json = sub.toJSON();
          callback(JSON.stringify({
            endpoint: json.endpoint,
            p256dhKey: json.keys.p256dh,
            authKey: json.keys.auth,
          }));
        }).catch(function() { callback(null); });
      });
    });
  };
</script>
```

- [ ] **Step 2: Commit**

```bash
git add frontend/web/index.html
git commit -m "feat: register push service worker and add mitrooSubscribePush JS helper"
```

---

## Task 11: Frontend — push_service.dart

**Files:**
- Create: `frontend/lib/services/push_service.dart`

- [ ] **Step 1: Create push_service.dart**

Create `frontend/lib/services/push_service.dart`:

```dart
import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'api_client.dart';

class PushService {
  static final _api = ApiClient();

  static Future<void> init() async {
    // Only supported on web
    try {
      await _subscribeAndRegister();
    } catch (_) {
      // Non-fatal: push is best-effort
    }
  }

  static Future<void> _subscribeAndRegister() async {
    // 1. Fetch VAPID public key from backend
    final keyRes = await _api.get('/push/vapid-public-key');
    if (keyRes.statusCode != 200) return;
    final vapidPublicKey = (jsonDecode(keyRes.body) as Map<String, dynamic>)['publicKey'] as String?;
    if (vapidPublicKey == null) return;

    // 2. Call JS helper (defined in index.html) — uses a Completer to bridge the callback
    final completer = Completer<String?>();
    js.context.callMethod('mitrooSubscribePush', [
      vapidPublicKey,
      js.allowInterop((dynamic result) {
        completer.complete(result as String?);
      }),
    ]);
    final subJson = await completer.future;
    if (subJson == null) return;

    // 3. POST subscription to backend
    final sub = jsonDecode(subJson) as Map<String, dynamic>;
    await _api.post('/push/subscribe', body: {
      'endpoint': sub['endpoint'],
      'p256dhKey': sub['p256dhKey'],
      'authKey': sub['authKey'],
    });
  }
}
```

- [ ] **Step 2: Verify Flutter analyses cleanly**

```bash
cd frontend && flutter analyze lib/services/push_service.dart
```

Expected: no errors (there may be a deprecation info about `dart:js`; that is acceptable).

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/services/push_service.dart
git commit -m "feat: add PushService dart — subscribes and registers web push"
```

---

## Task 12: Frontend — call PushService.init() from AuthProvider

**Files:**
- Modify: `frontend/lib/providers/auth_provider.dart`

- [ ] **Step 1: Add import**

At the top of `frontend/lib/providers/auth_provider.dart`, add:

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'services/push_service.dart';
```

Note: the existing import is `import 'package:flutter/foundation.dart';` — replace it with:

```dart
import 'package:flutter/foundation.dart';
import '../services/push_service.dart';
```

- [ ] **Step 2: Call PushService.init() on successful login**

In the `login()` method, after the line `_user = data['user'];` (inside the `if (res.statusCode == 200)` block), add:

```dart
if (kIsWeb) PushService.init();
```

The block should look like:

```dart
if (res.statusCode == 200) {
  await _api.setToken(data['token']);
  _user = data['user'];
  if (kIsWeb) PushService.init();
  _loading = false;
  notifyListeners();
  return null;
}
```

- [ ] **Step 3: Call PushService.init() on auto-login**

In `_tryAutoLogin()`, after the line `_user = jsonDecode(res.body);`, add:

```dart
if (kIsWeb) PushService.init();
```

The block should look like:

```dart
if (res.statusCode == 200) {
  _user = jsonDecode(res.body);
  if (kIsWeb) PushService.init();
}
```

- [ ] **Step 4: Verify and commit**

```bash
cd frontend && flutter analyze lib/providers/auth_provider.dart
git add frontend/lib/providers/auth_provider.dart
git commit -m "feat: call PushService.init() on login and auto-login (web only)"
```

---

## Task 13: Frontend — remove stub create dialog from ServicesScreen

**Files:**
- Modify: `frontend/lib/screens/services_screen.dart`

- [ ] **Step 1: Find and delete _showCreateDialog()**

Open `frontend/lib/screens/services_screen.dart`. Search for `_showCreateDialog`. Delete the entire method body — it starts with:

```dart
// ── Create dialog (admin) ───────────────────────
void _showCreateDialog() {
```

and ends with the closing `);` and `}` of the `showDialog` call.

- [ ] **Step 2: Replace the call site**

In the same file, find where `_showCreateDialog()` is called (it will be `onTap: () => _showCreateDialog()` or `onPressed: () => _showCreateDialog()`). Replace that entire callback with:

```dart
onTap: () => context.push('/admin/services/new'),
```

or if it uses `onPressed`:

```dart
onPressed: () => context.push('/admin/services/new'),
```

- [ ] **Step 3: Verify the /admin/services/new route exists**

Open `frontend/lib/config/router.dart`. Search for `admin/services/new`. If it does not exist, add the following route inside the `ShellRoute` routes list, after the existing `/admin` routes:

```dart
GoRoute(
  path: '/admin/services/new',
  builder: (context, state) {
    final deptId = int.tryParse(state.uri.queryParameters['departmentId'] ?? '');
    final deptName = state.uri.queryParameters['departmentName'];
    return CreateServiceScreen(
      initialDepartmentId: deptId,
      initialDepartmentName: deptName,
    );
  },
),
```

- [ ] **Step 4: Verify and commit**

```bash
cd frontend && flutter analyze lib/screens/services_screen.dart lib/config/router.dart
git add frontend/lib/screens/services_screen.dart frontend/lib/config/router.dart
git commit -m "feat: replace stub create dialog with CreateServiceScreen navigation"
```

---

## Final Verification

- [ ] Start the backend and confirm `npm run dev` starts with no errors.
- [ ] Run `flutter run -d chrome` and verify:
  - Browser prompts for notification permission on login.
  - The "Create service" button on ServicesScreen navigates to the full CreateServiceScreen form.
- [ ] As a non-admin/non-missionAdmin user, attempt `POST /api/services` directly — expect 403.
- [ ] As a missionAdmin of dept A, attempt to create a service for dept B — expect 403.
- [ ] As a regular dept member, apply to a service — verify missionAdmins receive a browser notification.
- [ ] As a missionAdmin, accept the enrollment — verify the user receives a browser notification.
