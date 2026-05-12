# Service Flows: Auth Guards & Enrollment Fix

**Date:** 2026-05-12  
**Scope:** Backend authorization on service mutations + self-enrollment fix + frontend stub removal

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

## Files Changed

| File | Change |
|---|---|
| `backend/src/routes/service.routes.ts` | Add `requireServiceAdmin` helper; apply to all mutation routes; fix enroll endpoint |
| `frontend/lib/screens/services_screen.dart` | Remove stub dialog; route create button to `/admin/services/new` |

## Out of Scope

- Push notifications on enrollment status change
- Email notifications
- Pagination on enrollment lists
- Any schema/migration changes (all data already present)
