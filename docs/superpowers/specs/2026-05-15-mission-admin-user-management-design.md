# Mission Admin User Management — Design Spec

**Date**: 2026-05-15
**Status**: Approved

## Summary

Currently only system-wide admins (`isAdmin: true`) can create, edit, and delete users, manage department memberships, and manage specializations. Mission admins can *see* users in their departments (the READ paths already support scope-based access) but cannot perform any write operations. This spec gives mission admins full user-management capabilities scoped to their administered departments.

## Backend

### New Middleware

Add `requireAdminOrMissionAdminForDept` — a middleware factory that takes a function extracting the relevant department ID from the request:

```ts
function requireAdminOrMissionAdminForDept(
  getDeptId: (req: Request) => number
): (req: Request, res: Response, next: NextFunction) => Promise<void>
```

Logic:
1. If `req.user.isAdmin` → next()
2. Else, extract target department ID via `getDeptId(req)`
3. Call `getMissionAdminDepartmentIds(req.user.userId)` — if the target department is in the set → next()
4. Else → 403

If `getDeptId` returns `NaN` (e.g., missing parameter), respond 400.

### Endpoint Changes

| Endpoint | Current Guard | New Guard | Dept Source |
|---|---|---|---|
| `POST /api/users` | `requireAdmin` | `requireAdminOrMissionAdminForDept` | `req.body.departmentId` |
| `PATCH /api/users/:id` | `requireAdmin` | scoped check inline | user's departments ∩ admin's departments |
| `DELETE /api/users/:id` | `requireAdmin` | scoped check inline | user's departments ∩ admin's departments |
| `POST /api/users/:id/specializations` | `requireAdmin` | scoped check inline | user's departments ∩ admin's departments |
| `DELETE /api/users/:uid/specializations/:sid` | `requireAdmin` | scoped check inline | user's departments ∩ admin's departments |
| `POST /api/departments/:id/members` | `requireAdmin` | `requireAdminOrMissionAdminForDept` | `req.params.id` |
| `PATCH /api/departments/:deptId/members/:userId` | `requireAdmin` | `requireAdminOrMissionAdminForDept` | `req.params.deptId` |
| `DELETE /api/departments/:deptId/members/:userId` | `requireAdmin` | `requireAdminOrMissionAdminForDept` | `req.params.deptId` |
| `PATCH /api/departments/:id` | *(none — bug)* | `requireAdminOrMissionAdminForDept` | `req.params.id` |

For user-targeting endpoints (PATCH, DELETE user, specialization add/remove), the middleware is not a direct fit because there's no single department ID in the request params. Instead, reuse the existing `getAccessScope()` / `canReadUserByScope()` pattern with an added write check: fetch the target user's departments, compute the intersection with the caller's mission-admin departments, and allow if non-empty.

```ts
const targetDepts = await prisma.userDepartment.findMany({
  where: { userId: targetUserId },
  select: { departmentId: true },
});
const targetDeptIds = targetDepts.map((d) => d.departmentId);
const allowed = targetDeptIds.some((id) => scope.departmentIds.includes(id));
```

### Special Rules

- **User create/edit**: The `isAdmin` field is stripped from the request body when the caller is not a system admin. Mission admins cannot elevate users to system admin.
- **Department edit**: Mission admins can update `description` and `location` but NOT `name`. System admins can edit all fields. If a mission admin sends `name`, it is silently dropped from the update payload.
- **Department create/delete**: Remain `requireAdmin` — only system admins create or delete departments.

### Existing Scope Machinery

The user routes already have `getAccessScope()` and `canReadUserByScope()` in `user.routes.ts`. These handle READ authorization and return a `UserAccessScope` union type. The new middleware will complement this by handling WRITE authorization. The scope helpers remain unchanged.

## Frontend

### AuthProvider (`auth_provider.dart`)

Add two helpers:

```dart
/// Whether the user can manage users in a specific department.
bool canManageUsersInDepartment(int deptId) {
  if (isAdmin) return true;
  final depts = _user?['departments'] as List<dynamic>? ?? [];
  return depts.any((d) =>
    d['role'] == 'missionAdmin' && d['department']?['id'] == deptId
  );
}

/// True when user is missionAdmin in at least one dept (excluding sys admin).
bool get isDepartmentMissionAdmin {
  if (isAdmin) return false;
  final depts = _user?['departments'] as List<dynamic>?;
  if (depts == null) return false;
  return depts.any((d) => d['role'] == 'missionAdmin');
}
```

### Admin Panel Screen

Show "Users" and "Departments" tiles for mission admins (not just system admins). Specializations and Service Types remain system-admin-only.

### Shell Screen / Sidebar

Show "Users" and "Departments" sidebar links for mission admins. Specializations remain system-admin-only.

### Manage Users Screen

- FAB for "New User" visible when `isAdmin` OR `isDepartmentMissionAdmin`
- Department filter already scoped to user's departments (no change needed)

### User Detail Screen

Replace the bare `canManage = auth.isAdmin` with a check that considers the target user's department overlap with the current user's mission-admin scope. Hide the system admin toggle in the edit dialog for non-system-admin callers.

### Department Detail Screen

Lock the `name` field for non-system-admin editors. Mission admins can edit description and location only.

## What Does NOT Change

- Department create/delete: system admin only
- Specialization CRUD: system admin only
- Service Type management: system admin only
- READ operations (user list, stats, detail): already support mission admin scope

## Testing Notes

- Verify mission admin can create a user and assign them to an administered department
- Verify mission admin cannot create a user in a non-administered department
- Verify mission admin cannot toggle system admin flag
- Verify mission admin cannot change a department's name
- Verify mission admin can edit department description/location
- Verify system admin retains all existing capabilities
