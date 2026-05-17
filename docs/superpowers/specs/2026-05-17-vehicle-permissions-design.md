# Vehicle Permissions & Personal Vehicles — Design Spec

**Date:** 2026-05-17  
**Status:** Approved

## Overview

Refactor the vehicle flow to enforce role-based permissions on department vehicles and introduce a personal vehicle concept where users can own and privately log their own vehicles.

## Schema Change

Add a nullable `ownerId` FK to the `Vehicle` model:

```prisma
ownerId Int?   @map("owner_id")
owner   User?  @relation("OwnedVehicles", fields: [ownerId], references: [id], onDelete: SetNull)
```

Add the back-relation on `User`:

```prisma
ownedVehicles Vehicle[] @relation("OwnedVehicles")
```

A vehicle is **personal** when `ownerId != null` (and `departmentId` is null).  
Log privacy is derived from the vehicle: personal vehicle logs are always private (owner + system admins only).

Migration: `ALTER TABLE vehicles ADD COLUMN owner_id INT REFERENCES users(id) ON DELETE SET NULL`.

## Permission Matrix

| Action | System Admin | Dept Admin (own dept) | Normal User (vehicle owner) | Normal User (other) |
|---|---|---|---|---|
| Create dept vehicle | ✓ | ✓ | ✗ | ✗ |
| Create personal vehicle | ✓ | ✓ | ✓ | ✓ |
| View dept vehicle | ✓ | ✓ | ✓ | ✓ |
| View own personal vehicle | ✓ | ✗ | ✓ | ✗ |
| Edit dept vehicle | ✓ | ✓ | ✗ | ✗ |
| Edit own personal vehicle | ✓ | ✗ | ✓ | ✗ |
| Delete dept vehicle | ✓ | ✓ | ✗ | ✗ |
| Delete own personal vehicle | ✓ | ✗ | ✓ | ✗ |
| Take/return dept vehicle | ✓ | ✓ | ✓ | ✓ |
| Take/return personal vehicle | ✓ | ✗ | ✓ | ✗ |
| View dept vehicle logs | ✓ | ✓ | ✓ | ✓ |
| View personal vehicle logs | ✓ | ✗ | ✓ | ✗ |
| Add manual log to dept vehicle | ✓ | ✓ | ✗ | ✗ |
| Add manual log to personal vehicle | ✓ | ✗ | ✓ | ✗ |

"Dept Admin" = user with `missionAdmin` or `itemAdmin` role in the vehicle's department (`UserDepartment`).

## Backend Changes (`backend/src/routes/vehicle.routes.ts`)

### Shared helper

```ts
async function canManageVehicle(userId: number, isAdmin: boolean, vehicle: { ownerId: number | null, departmentId: number | null }): Promise<boolean>
```

Returns true if:
- `isAdmin`, OR
- `vehicle.ownerId === userId`, OR
- `vehicle.departmentId != null` and user has `missionAdmin` or `itemAdmin` role in that department (query `UserDepartment`)

### Route-by-route

- **`GET /`** — dept vehicles returned to all; personal vehicles only returned to their owner or system admins.
- **`POST /`** — if `departmentId` in body: require system admin or dept admin of that department. Otherwise: personal vehicle — set `ownerId = req.user.userId`, ignore any submitted `ownerId`.
- **`GET /:id`** — 403 if personal vehicle and requester is not owner or system admin. Logs inside the response filtered the same way.
- **`PATCH /:id`** — require `canManageVehicle`. `ownerId` field is not patchable.
- **`DELETE /:id`** — require `canManageVehicle`.
- **`GET /:id/logs`** — 403 if personal vehicle and not owner or system admin.
- **`POST /:id/logs`** (manual log) — require `canManageVehicle`.
- **`DELETE /logs/:logId`** — require system admin, or vehicle owner (personal), or dept admin (dept vehicle). This route must be registered **before** `/:id` routes in Express to prevent `"logs"` being captured as `:id`.
- **`POST /:id/take`** — personal vehicle: require owner. Dept vehicle: open to all authenticated (unchanged).
- **`POST /:id/return`** — personal vehicle: require owner. Dept vehicle: open (unchanged).

## Frontend Changes

### `AuthProvider`
Expose current user's department memberships with roles. Fetch from existing `/api/auth/me` or user profile response on login. Add helper `isDeptAdminOf(departmentId)` returning true if user has `missionAdmin` or `itemAdmin` in that department.

### `VehiclesScreen`
- FAB visible to everyone.
- Create dialog adds a "Personal / Department" toggle. Department option + dept dropdown only shown when user `isAdmin` or has at least one dept admin role.
- For non-admins with no dept roles, creation always produces a personal vehicle (no toggle shown).

### `VehicleDetailScreen`
- Edit/delete buttons: show when `isAdmin || auth.isDeptAdminOf(vehicle.departmentId) || vehicle.ownerId == currentUserId`.
- Take/return buttons: for personal vehicles only show to the owner; dept vehicles unchanged.
- Logs card: backend filters appropriately; frontend needs no special logic.

### `VehicleProvider`
- `create()`: pass `departmentId` for dept vehicles; omit it for personal (backend sets `ownerId` server-side).
- `fetchVehicles()` unchanged — backend returns only what the user is allowed to see.

## Migration

```sql
ALTER TABLE vehicles ADD COLUMN owner_id INT REFERENCES users(id) ON DELETE SET NULL;
```

Prisma migration file generated via `npm run prisma:migrate` (uses `scripts/run-with-dev-env.js` to inject dev env vars).

## Out of Scope

- Dept admins cannot see personal vehicles of users in their department.
- Ownership cannot be transferred after creation.
- No UI for system admins to reassign vehicle ownership (can be done via Prisma Studio if needed).
