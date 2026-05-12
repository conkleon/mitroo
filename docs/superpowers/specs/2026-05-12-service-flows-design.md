# Service Flows: Auth Guards, Enrollment Fix & Notifications

**Date:** 2026-05-12  
**Scope:** Backend authorization on service mutations + self-enrollment fix + frontend stub removal + email & web push notifications

---

## Problem Summary

Four gaps in the service creation / application / acceptance flows:

1. No authorization on any backend mutation — any authenticated user can create, edit, delete services or accept/reject enrollments.
2. `POST /services/:id/enroll` takes `userId` from the request body — a user can enroll anyone.
3. `ServicesScreen` has a stub create dialog (raw dept ID text field) instead of routing to `CreateServiceScreen`.
4. No department membership check on self-enrollment — a user can apply to a service outside their departments.

---

## Design

### 1. Backend: `requireServiceAdmin` helper

**File:** `backend/src/routes/service.routes.ts`

Add an async helper:

```ts
async function requireServiceAdmin(
  req: Request,
  res: Response,
  serviceId: number   // pass 0 for POST /services, use deptId instead
): Promise<{ deptId: number } | null>
```

- If `req.user!.isAdmin` → pass through, return `{ deptId }`.
- Otherwise fetch `service.departmentId` from DB (or accept `departmentId` directly for the create case).
- Query `UserDepartment` for `{ userId, departmentId, role: 'missionAdmin' }`.
- If not found → `res.status(403).json({ error: "Δεν έχετε δικαίωμα" })` and return `null`.

**Applied to:**
| Endpoint | How dept is obtained |
|---|---|
| `POST /services` | from validated `data.departmentId` |
| `PATCH /services/:id` | fetch service by id |
| `DELETE /services/:id` | fetch service by id |
| `PATCH /:sid/users/:uid/status` | fetch service by sid |
| `PATCH /:sid/users/:uid/hours` | fetch service by sid |
| `DELETE /:sid/users/:uid` | fetch service by sid |
| `PATCH /:id/responsible` | fetch service by id |
| `POST /:id/visibility` | fetch service by id |
| `DELETE /:sid/visibility/:specId` | fetch service by sid |

To avoid an extra DB round-trip on update/delete routes, the helper can be called with the already-fetched service's `departmentId`.

---

### 2. Fix `POST /services/:id/enroll`

**For regular users (non-admin, non-missionAdmin of this dept):**
- Ignore `userId` from body; use `req.user!.userId`.
- Force `status = "requested"`.
- Guard: verify the user is a member of the service's department (`UserDepartment` exists for `userId + departmentId`). Return `403` if not.

**For missionAdmin of the service's dept (or global admin):**
- Allow `userId` from body (to directly enroll someone).
- Allow any `status` value.

**Updated `enrollSchema`:**
```ts
const enrollSchema = z.object({
  userId: z.number().int().optional(),   // admin-only; ignored for regular users
  status: z.enum(["requested", "accepted", "rejected"]).optional(),
});
```

No frontend changes needed — `ServiceProvider.enrollSelf` already omits direct status manipulation for end users.

---

### 3. Frontend: remove stub create dialog

**File:** `frontend/lib/screens/services_screen.dart`

- Delete `_showCreateDialog()` method.
- Replace its call site (the create FAB / button visible to `auth.isAdmin || auth.isMissionAdmin`) with:
  ```dart
  context.push('/admin/services/new');
  ```
- `CreateServiceScreen` already reads `auth.missionAdminDepartments` to pre-populate the department picker for non-global admins.

---

### 4. Email notifications (nodemailer — existing infrastructure)

**New functions in `backend/src/lib/email.ts`:**

- `sendServiceEnrollmentEmail(adminEmail, adminName, applicantName, serviceName)` — sent to each `missionAdmin` of the service's dept when a user applies.
- `sendServiceStatusEmail(userEmail, userName, serviceName, status: 'accepted' | 'rejected')` — sent to the enrolled user when their status changes.

**Trigger points** (fire-and-forget, same try/catch pattern as existing email calls):
- `POST /services/:id/enroll` (self-enrollment) → email all missionAdmins of the service's dept.
- `PATCH /:sid/users/:uid/status` → email the user whose status changed.

---

### 5. Web Push notifications

#### 5a. Schema — new `PushSubscription` table

```prisma
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

New Prisma migration required.

#### 5b. Backend

- Install `web-push` npm package + `@types/web-push`.
- Add to `.env`: `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_EMAIL`.
- **`backend/src/lib/webpush.ts`** — configure VAPID, export `sendPushToUser(userId: number, payload: object)`: fetches all subscriptions for the user and calls `webpush.sendNotification`, swallowing `410 Gone` (expired subscription) by deleting those records.
- **`backend/src/routes/push.routes.ts`**:
  - `POST /push/subscribe` — upsert subscription for `req.user.userId`.
  - `DELETE /push/unsubscribe` — delete by endpoint.
  - `GET /push/vapid-public-key` — returns `VAPID_PUBLIC_KEY` (public, no auth needed).

**Trigger points** (same two as email, fire-and-forget):
- `POST /services/:id/enroll` → push to all missionAdmins of the service's dept: `{ title: "Νέα αίτηση", body: "[name] αιτήθηκε για [service name]" }`
- `PATCH /:sid/users/:uid/status` → push to the enrolled user: `{ title: "Ενημέρωση αίτησης", body: "Η αίτησή σας για [service name] εγκρίθηκε / απορρίφθηκε" }`

#### 5c. Frontend (Flutter Web)

- **`frontend/web/push_sw.js`** — standalone service worker that handles `push` events and calls `self.registration.showNotification(...)`.
- Register `push_sw.js` in **`frontend/web/index.html`** via `navigator.serviceWorker.register`.
- **`frontend/lib/services/push_service.dart`** — JS interop (`dart:js_interop`):
  - `init()`: fetches VAPID public key from backend, requests notification permission, subscribes to `PushManager`, POSTs subscription to `/push/subscribe`.
  - Called from `AuthProvider` on successful login.

---

## Files Changed

| File | Change |
|---|---|
| `backend/src/routes/service.routes.ts` | `requireServiceAdmin` helper; auth guards on all mutations; fix enroll endpoint; trigger email+push |
| `backend/src/lib/email.ts` | Add `sendServiceEnrollmentEmail` and `sendServiceStatusEmail` |
| `backend/src/lib/webpush.ts` | New — VAPID config + `sendPushToUser` |
| `backend/src/routes/push.routes.ts` | New — subscribe / unsubscribe / public key endpoints |
| `backend/src/app.ts` | Mount push router |
| `backend/prisma/schema.prisma` | Add `PushSubscription` model + relation on `User` |
| `frontend/web/push_sw.js` | New — service worker push handler |
| `frontend/web/index.html` | Register `push_sw.js` |
| `frontend/lib/services/push_service.dart` | New — JS interop subscribe + permission |
| `frontend/lib/providers/auth_provider.dart` | Call `PushService.init()` on login |
| `frontend/lib/screens/services_screen.dart` | Remove stub dialog; route create button to `/admin/services/new` |

## Out of Scope

- Pagination on enrollment lists
- Mobile/native push (FCM)
- Notification history / inbox UI
