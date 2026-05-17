# Vehicle Permissions & Personal Vehicles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce role-based permissions on department vehicles and add personal vehicle ownership with private logs.

**Architecture:** Add `ownerId` FK to `Vehicle` — personal vehicles are those with `ownerId` set. Backend enforces all permissions via a shared `canManageVehicle` helper that checks system admin, vehicle owner, or dept admin (missionAdmin/itemAdmin). Frontend uses existing `AuthProvider` department data to show/hide controls.

**Tech Stack:** TypeScript/Express/Prisma (backend), Dart/Flutter/Provider (frontend)

---

## File Map

| File | Change |
|---|---|
| `backend/prisma/schema.prisma` | Add `ownerId` to `Vehicle`, back-relation on `User` |
| `backend/src/routes/vehicle.routes.ts` | Add `canManageVehicle` helper, update all routes |
| `frontend/lib/providers/auth_provider.dart` | Add `isDeptAdminOf(int?)` + `isDeptAdmin` helpers |
| `frontend/lib/screens/vehicle_detail_screen.dart` | Permission-aware edit/delete/take/return buttons |
| `frontend/lib/screens/vehicles_screen.dart` | Personal/dept toggle in create dialog |

---

## Task 1: Add ownerId to Vehicle schema

**Files:**
- Modify: `backend/prisma/schema.prisma`

- [ ] **Step 1: Add ownerId to Vehicle model**

In `backend/prisma/schema.prisma`, find the `Vehicle` model and add after the `department` relation line:

```prisma
  ownerId    Int?    @map("owner_id")
  owner      User?   @relation("OwnedVehicles", fields: [ownerId], references: [id], onDelete: SetNull)
```

The `Vehicle` model's relation block should look like:

```prisma
  department  Department?      @relation(fields: [departmentId], references: [id], onDelete: SetNull)
  owner       User?            @relation("OwnedVehicles", fields: [ownerId], references: [id], onDelete: SetNull)
  logs        VehicleLog[]
  attachments FileAttachment[]
```

- [ ] **Step 2: Add back-relation on User model**

In `backend/prisma/schema.prisma`, find the `User` model's relation block (near `vehicleLogs`, `vehicleComments`) and add:

```prisma
  ownedVehicles                Vehicle[]             @relation("OwnedVehicles")
```

- [ ] **Step 3: Run migration**

```bash
cd backend
npm run prisma:migrate
```

Expected: Prisma prompts for a migration name — enter `add_vehicle_owner`. A new migration file is created and applied. Output ends with `Your database is now in sync with your schema.`

- [ ] **Step 4: Regenerate Prisma client**

```bash
npm run prisma:generate
```

Expected: `Generated Prisma Client` message with no errors.

- [ ] **Step 5: Verify TypeScript compiles**

```bash
npm run build
```

Expected: no TypeScript errors.

- [ ] **Step 6: Commit**

```bash
cd backend
git add prisma/schema.prisma prisma/migrations/
git commit -m "feat: add ownerId to Vehicle for personal vehicle ownership"
```

---

## Task 2: Backend — canManageVehicle helper + updated GET /

**Files:**
- Modify: `backend/src/routes/vehicle.routes.ts`

- [ ] **Step 1: Add canManageVehicle helper**

In `backend/src/routes/vehicle.routes.ts`, add this function after the `logSchema` declaration (before the first route):

```ts
async function canManageVehicle(
  userId: number,
  isAdmin: boolean,
  vehicle: { ownerId: number | null; departmentId: number | null },
): Promise<boolean> {
  if (isAdmin) return true;
  if (vehicle.ownerId !== null && vehicle.ownerId === userId) return true;
  if (vehicle.departmentId !== null) {
    const count = await prisma.userDepartment.count({
      where: {
        userId,
        departmentId: vehicle.departmentId,
        role: { in: ["missionAdmin", "itemAdmin"] },
      },
    });
    return count > 0;
  }
  return false;
}
```

- [ ] **Step 2: Replace GET / handler**

Replace the entire `router.get("/", ...)` handler with:

```ts
router.get("/", async (req: Request, res: Response) => {
  const { departmentId } = req.query;
  const userId = req.user!.userId;
  const isAdmin = req.user!.isAdmin;

  let where: any = {};
  if (departmentId) {
    where.departmentId = Number(departmentId);
  } else if (!isAdmin) {
    where.OR = [
      { departmentId: { not: null } },
      { ownerId: userId },
    ];
  }

  const vehicles = await prisma.vehicle.findMany({
    where,
    include: {
      department: { select: { id: true, name: true } },
      attachments: {
        where: { isImage: true },
        select: { id: true, thumbnailPath: true },
        take: 1,
        orderBy: { uploadedAt: "asc" as const },
      },
    },
    orderBy: { name: "asc" },
  });
  res.json(vehicles);
});
```

- [ ] **Step 3: Build to verify no TS errors**

```bash
cd backend
npm run build
```

Expected: compiles with no errors.

- [ ] **Step 4: Commit**

```bash
git add backend/src/routes/vehicle.routes.ts
git commit -m "feat: add canManageVehicle helper and filter personal vehicles in GET /"
```

---

## Task 3: Backend — POST / permission enforcement

**Files:**
- Modify: `backend/src/routes/vehicle.routes.ts`

- [ ] **Step 1: Replace POST / handler**

Replace the entire `router.post("/", ...)` handler with:

```ts
router.post("/", async (req: Request, res: Response) => {
  try {
    const data = createSchema.parse(req.body);
    const userId = req.user!.userId;
    const isAdmin = req.user!.isAdmin;

    if (data.departmentId) {
      if (!isAdmin) {
        const count = await prisma.userDepartment.count({
          where: {
            userId,
            departmentId: data.departmentId,
            role: { in: ["missionAdmin", "itemAdmin"] },
          },
        });
        if (count === 0) {
          res.status(403).json({ error: "Not an admin of this department" });
          return;
        }
      }
    }

    const vehicleData: any = { ...data };
    if (!data.departmentId) {
      vehicleData.ownerId = userId;
    }

    const vehicle = await prisma.vehicle.create({
      data: vehicleData,
      include: { department: { select: { id: true, name: true } } },
    });
    res.status(201).json(vehicle);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});
```

- [ ] **Step 2: Build to verify no TS errors**

```bash
cd backend
npm run build
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add backend/src/routes/vehicle.routes.ts
git commit -m "feat: restrict dept vehicle creation to admins, auto-set ownerId for personal"
```

---

## Task 4: Backend — GET /:id, PATCH /:id, DELETE /:id permissions

**Files:**
- Modify: `backend/src/routes/vehicle.routes.ts`

- [ ] **Step 1: Replace GET /:id handler**

Replace the entire `router.get("/:id", ...)` handler with:

```ts
router.get("/:id", async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const isAdmin = req.user!.isAdmin;

  const vehicle = await prisma.vehicle.findUnique({
    where: { id: Number(req.params.id) },
    include: {
      department: true,
      logs: {
        include: {
          user: { select: { id: true, forename: true, surname: true } },
          service: { select: { id: true, name: true } },
        },
        orderBy: { startAt: "desc" },
        take: 50,
      },
      comments: {
        include: { user: { select: { id: true, forename: true, surname: true, eame: true } } },
        orderBy: { createdAt: "desc" },
      },
    },
  });
  if (!vehicle) { res.status(404).json({ error: "Vehicle not found" }); return; }

  if (vehicle.ownerId !== null && !isAdmin && vehicle.ownerId !== userId) {
    res.status(403).json({ error: "Access denied" });
    return;
  }

  res.json(vehicle);
});
```

- [ ] **Step 2: Replace PATCH /:id handler**

Replace the entire `router.patch("/:id", ...)` handler with:

```ts
router.patch("/:id", async (req: Request, res: Response) => {
  try {
    const userId = req.user!.userId;
    const isAdmin = req.user!.isAdmin;

    const existing = await prisma.vehicle.findUnique({
      where: { id: Number(req.params.id) },
      select: { ownerId: true, departmentId: true },
    });
    if (!existing) { res.status(404).json({ error: "Vehicle not found" }); return; }

    const allowed = await canManageVehicle(userId, isAdmin, existing);
    if (!allowed) { res.status(403).json({ error: "Forbidden" }); return; }

    const data = createSchema.partial().parse(req.body);
    const vehicle = await prisma.vehicle.update({
      where: { id: Number(req.params.id) },
      data,
      include: { department: { select: { id: true, name: true } } },
    });
    res.json(vehicle);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});
```

- [ ] **Step 3: Replace DELETE /:id handler**

Replace the entire `router.delete("/:id", ...)` handler with:

```ts
router.delete("/:id", async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const isAdmin = req.user!.isAdmin;

  const existing = await prisma.vehicle.findUnique({
    where: { id: Number(req.params.id) },
    select: { ownerId: true, departmentId: true },
  });
  if (!existing) { res.status(404).json({ error: "Vehicle not found" }); return; }

  const allowed = await canManageVehicle(userId, isAdmin, existing);
  if (!allowed) { res.status(403).json({ error: "Forbidden" }); return; }

  await prisma.vehicle.delete({ where: { id: Number(req.params.id) } });
  res.status(204).end();
});
```

- [ ] **Step 4: Build to verify no TS errors**

```bash
cd backend
npm run build
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add backend/src/routes/vehicle.routes.ts
git commit -m "feat: enforce canManageVehicle on PATCH and DELETE vehicle routes"
```

---

## Task 5: Backend — logs routes permissions

**Files:**
- Modify: `backend/src/routes/vehicle.routes.ts`

- [ ] **Step 1: Replace GET /:id/logs handler**

Replace the entire `router.get("/:id/logs", ...)` handler with:

```ts
router.get("/:id/logs", async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const isAdmin = req.user!.isAdmin;

  const vehicle = await prisma.vehicle.findUnique({
    where: { id: Number(req.params.id) },
    select: { ownerId: true },
  });
  if (!vehicle) { res.status(404).json({ error: "Vehicle not found" }); return; }

  if (vehicle.ownerId !== null && !isAdmin && vehicle.ownerId !== userId) {
    res.status(403).json({ error: "Access denied" });
    return;
  }

  const logs = await prisma.vehicleLog.findMany({
    where: { vehicleId: Number(req.params.id) },
    include: {
      user: { select: { id: true, forename: true, surname: true } },
      service: { select: { id: true, name: true } },
    },
    orderBy: { startAt: "desc" },
  });
  res.json(logs);
});
```

- [ ] **Step 2: Replace POST /:id/logs handler**

Replace the entire `router.post("/:id/logs", ...)` handler with:

```ts
router.post("/:id/logs", async (req: Request, res: Response) => {
  try {
    const userId = req.user!.userId;
    const isAdmin = req.user!.isAdmin;

    const vehicle = await prisma.vehicle.findUnique({
      where: { id: Number(req.params.id) },
      select: { ownerId: true, departmentId: true },
    });
    if (!vehicle) { res.status(404).json({ error: "Vehicle not found" }); return; }

    const allowed = await canManageVehicle(userId, isAdmin, vehicle);
    if (!allowed) { res.status(403).json({ error: "Forbidden" }); return; }

    const data = logSchema.parse(req.body);

    if (data.meterEnd < data.meterStart) {
      res.status(400).json({ error: "meter_end must be >= meter_start" });
      return;
    }
    if (new Date(data.endAt) <= new Date(data.startAt)) {
      res.status(400).json({ error: "end_at must be after start_at" });
      return;
    }

    const log = await prisma.vehicleLog.create({
      data: {
        vehicleId: Number(req.params.id),
        userId: data.userId,
        serviceId: data.serviceId,
        startAt: new Date(data.startAt),
        endAt: new Date(data.endAt),
        meterStart: data.meterStart,
        meterEnd: data.meterEnd,
        destination: data.destination,
        comment: data.comment,
      },
    });

    await prisma.vehicle.update({
      where: { id: Number(req.params.id) },
      data: { currentMeter: data.meterEnd },
    });

    res.status(201).json(log);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});
```

- [ ] **Step 3: Replace DELETE /logs/:logId handler**

Replace the entire `router.delete("/logs/:logId", ...)` handler with:

```ts
router.delete("/logs/:logId", async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const isAdmin = req.user!.isAdmin;

  const log = await prisma.vehicleLog.findUnique({
    where: { id: Number(req.params.logId) },
    include: { vehicle: { select: { ownerId: true, departmentId: true } } },
  });
  if (!log) { res.status(404).json({ error: "Log not found" }); return; }

  const allowed = await canManageVehicle(userId, isAdmin, log.vehicle);
  if (!allowed) { res.status(403).json({ error: "Forbidden" }); return; }

  await prisma.vehicleLog.delete({ where: { id: Number(req.params.logId) } });
  res.status(204).end();
});
```

- [ ] **Step 4: Build to verify no TS errors**

```bash
cd backend
npm run build
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add backend/src/routes/vehicle.routes.ts
git commit -m "feat: enforce permissions on vehicle log routes"
```

---

## Task 6: Backend — take/return permission for personal vehicles

**Files:**
- Modify: `backend/src/routes/vehicle.routes.ts`

- [ ] **Step 1: Add personal vehicle guard to POST /:id/take**

In the `router.post("/:id/take", ...)` handler, the existing code fetches `vehicle` from the DB. After the `if (!vehicle)` check, add this block:

```ts
  // Personal vehicles: only owner or system admin may take
  if (vehicle.ownerId !== null && !isAdmin && vehicle.ownerId !== userId) {
    res.status(403).json({ error: "Access denied" });
    return;
  }
```

The handler should look like this after the change:

```ts
router.post("/:id/take", async (req: Request, res: Response) => {
  const vehicleId = Number(req.params.id);
  const userId = req.user!.userId;
  const isAdmin = req.user!.isAdmin;

  const vehicle = await prisma.vehicle.findUnique({ where: { id: vehicleId } });
  if (!vehicle) { res.status(404).json({ error: "Vehicle not found" }); return; }

  if (vehicle.ownerId !== null && !isAdmin && vehicle.ownerId !== userId) {
    res.status(403).json({ error: "Access denied" });
    return;
  }

  const openLog = await prisma.vehicleLog.findFirst({
    where: { vehicleId, endAt: null },
  });
  if (openLog) {
    res.status(400).json({ error: "Το όχημα χρησιμοποιείται ήδη" });
    return;
  }

  const meterStart = req.body.meterStart != null ? Number(req.body.meterStart) : Number(vehicle.currentMeter);
  if (isNaN(meterStart) || meterStart < 0) {
    res.status(400).json({ error: "Invalid meterStart" });
    return;
  }

  const log = await prisma.vehicleLog.create({
    data: {
      vehicleId,
      userId,
      serviceId: req.body.serviceId ? Number(req.body.serviceId) : null,
      startAt: new Date(),
      meterStart,
      destination: req.body.destination || null,
      comment: req.body.comment,
    },
    include: {
      vehicle: { select: { id: true, name: true, type: true, meterType: true, registrationNumber: true } },
    },
  });

  res.json(log);
});
```

- [ ] **Step 2: Add personal vehicle guard to POST /:id/return**

Replace the entire `router.post("/:id/return", ...)` handler with:

```ts
router.post("/:id/return", async (req: Request, res: Response) => {
  const vehicleId = Number(req.params.id);
  const userId = req.user!.userId;
  const isAdmin = req.user!.isAdmin;

  const vehicle = await prisma.vehicle.findUnique({
    where: { id: vehicleId },
    select: { ownerId: true },
  });
  if (!vehicle) { res.status(404).json({ error: "Vehicle not found" }); return; }

  if (vehicle.ownerId !== null && !isAdmin && vehicle.ownerId !== userId) {
    res.status(403).json({ error: "Access denied" });
    return;
  }

  const openLog = await prisma.vehicleLog.findFirst({
    where: { vehicleId, userId, endAt: null },
  });
  if (!openLog) {
    res.status(400).json({ error: "Δεν έχετε ανοιχτό αρχείο για αυτό το όχημα" });
    return;
  }

  const meterEnd = Number(req.body.meterEnd);
  if (isNaN(meterEnd) || meterEnd < 0) {
    res.status(400).json({ error: "Invalid meterEnd" });
    return;
  }
  if (meterEnd < Number(openLog.meterStart)) {
    res.status(400).json({ error: "Τα τελικά πρέπει να είναι >= αρχικά" });
    return;
  }

  const log = await prisma.vehicleLog.update({
    where: { id: openLog.id },
    data: {
      endAt: new Date(),
      meterEnd,
      destination: req.body.destination ?? openLog.destination,
      comment: req.body.comment ?? openLog.comment,
    },
    include: {
      vehicle: { select: { id: true, name: true, type: true, meterType: true, registrationNumber: true } },
    },
  });

  await prisma.vehicle.update({
    where: { id: vehicleId },
    data: { currentMeter: meterEnd },
  });

  res.json(log);
});
```

- [ ] **Step 3: Build to verify no TS errors**

```bash
cd backend
npm run build
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add backend/src/routes/vehicle.routes.ts
git commit -m "feat: restrict take/return of personal vehicles to owner"
```

---

## Task 7: Frontend — AuthProvider helpers

**Files:**
- Modify: `frontend/lib/providers/auth_provider.dart`

- [ ] **Step 1: Add isDeptAdminOf and isDeptAdmin**

In `frontend/lib/providers/auth_provider.dart`, add these two methods after the existing `canManageUsersInDepartment` method (around line 57):

```dart
  /// True when user is missionAdmin or itemAdmin in the given department (or is global admin).
  bool isDeptAdminOf(int? deptId) {
    if (deptId == null) return false;
    if (isAdmin) return true;
    final depts = _user?['departments'] as List<dynamic>? ?? [];
    return depts.any((d) =>
      (d['role'] == 'missionAdmin' || d['role'] == 'itemAdmin') &&
      d['department']?['id'] == deptId,
    );
  }

  /// True when user is missionAdmin or itemAdmin in at least one department (or global admin).
  bool get isDeptAdmin {
    if (isAdmin) return true;
    final depts = _user?['departments'] as List<dynamic>?;
    if (depts == null) return false;
    return depts.any((d) => d['role'] == 'missionAdmin' || d['role'] == 'itemAdmin');
  }
```

- [ ] **Step 2: Verify Flutter analyzes cleanly**

```bash
cd frontend
flutter analyze lib/providers/auth_provider.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/providers/auth_provider.dart
git commit -m "feat: add isDeptAdminOf and isDeptAdmin helpers to AuthProvider"
```

---

## Task 8: Frontend — VehicleDetailScreen permission-aware controls

**Files:**
- Modify: `frontend/lib/screens/vehicle_detail_screen.dart`

- [ ] **Step 1: Update _buildSheetHeader signature**

Change the `_buildSheetHeader` method signature from:

```dart
Widget _buildSheetHeader(TextTheme tt, ColorScheme cs, bool isAdmin) {
```

to:

```dart
Widget _buildSheetHeader(TextTheme tt, ColorScheme cs, bool canManage) {
```

And inside it, change:

```dart
if (isAdmin && _vehicle != null) ...[
```

to:

```dart
if (canManage && _vehicle != null) ...[
```

- [ ] **Step 2: Update _buildBody to compute canManage and use it**

In `_buildBody`, after the existing variable declarations (`vehicleType`, `meterType`, etc.), add:

```dart
    final ownerId = v['ownerId'] as int?;
    final currentUserId = auth.user?['id'] as int?;
    final isOwner = ownerId != null && ownerId == currentUserId;
    final deptId = dept?['id'] as int?;
    final canManage = isAdmin || auth.isDeptAdminOf(deptId) || isOwner;
    final isPersonal = ownerId != null;
```

- [ ] **Step 3: Pass canManage to _buildSheetHeader**

In the `build` method, update the call to `_buildSheetHeader`. Currently:

```dart
_buildSheetHeader(tt, cs, isAdmin),
```

Change to:

```dart
_buildSheetHeader(tt, cs, _computeCanManage(auth)),
```

And add this private helper method to the class (above `build`):

```dart
  bool _computeCanManage(AuthProvider auth) {
    if (_vehicle == null) return auth.isAdmin;
    final ownerId = _vehicle!['ownerId'] as int?;
    final currentUserId = auth.user?['id'] as int?;
    final dept = _vehicle!['department'] as Map<String, dynamic>?;
    final deptId = dept?['id'] as int?;
    return auth.isAdmin ||
        auth.isDeptAdminOf(deptId) ||
        (ownerId != null && ownerId == currentUserId);
  }
```

- [ ] **Step 4: Update ImageGalleryCard canManage**

In `_buildBody`, find:

```dart
          ImageGalleryCard(
            entityParam: 'vehicleId',
            entityId: widget.vehicleId,
            canManage: isAdmin,
          ),
```

Change to:

```dart
          ImageGalleryCard(
            entityParam: 'vehicleId',
            entityId: widget.vehicleId,
            canManage: canManage,
          ),
```

- [ ] **Step 5: Restrict Take/Return buttons for personal vehicles**

In `_buildBody`, the take/return buttons section currently reads:

```dart
          if (!hasOpenLog && !isInUse)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _takeVehicle,
                ...
              ),
            ),
          if (hasOpenLog)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _returnVehicle,
                ...
              ),
            ),
```

Change to:

```dart
          if (!hasOpenLog && !isInUse && (!isPersonal || isOwner || isAdmin))
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _takeVehicle,
                icon: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.key),
                label: Text(_busy ? 'Παρακαλώ περιμένετε...' : 'Λήψη Οχήματος'),
              ),
            ),
          if (hasOpenLog && (!isPersonal || isOwner || isAdmin))
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _returnVehicle,
                icon: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.assignment_return),
                label: Text(_busy ? 'Παρακαλώ περιμένετε...' : 'Επιστροφή Οχήματος'),
                style: FilledButton.styleFrom(backgroundColor: Color(0xFFDC2626)),
              ),
            ),
```

- [ ] **Step 6: Verify Flutter analyzes cleanly**

```bash
cd frontend
flutter analyze lib/screens/vehicle_detail_screen.dart
```

Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/screens/vehicle_detail_screen.dart
git commit -m "feat: show edit/delete/take/return controls based on ownership and dept admin role"
```

---

## Task 9: Frontend — VehiclesScreen personal/dept create dialog

**Files:**
- Modify: `frontend/lib/screens/vehicles_screen.dart`

- [ ] **Step 1: Update _showCreateDialog to support personal/dept toggle**

In `frontend/lib/screens/vehicles_screen.dart`, replace the entire `_showCreateDialog` method with:

```dart
  void _showCreateDialog() {
    final auth = context.read<AuthProvider>();
    final canCreateDept = auth.isAdmin || auth.isDeptAdmin;

    final nameCtrl = TextEditingController();
    final typeCtrl = TextEditingController();
    final regCtrl = TextEditingController();
    String meterType = 'km';
    String? nameError;
    bool isPersonal = !canCreateDept;
    int? selectedDeptId;
    List<Map<String, dynamic>> deptOptions = [];

    if (canCreateDept) {
      if (auth.isAdmin) {
        final deptProv = context.read<DepartmentProvider>();
        deptOptions = deptProv.departments
            .map((d) => {'id': d['id'] as int, 'name': d['name'] as String})
            .toList();
      } else {
        deptOptions = [
          ...auth.missionAdminDepartments,
          ...auth.itemAdminDepartments,
        ].fold<List<Map<String, dynamic>>>([], (acc, d) {
          if (!acc.any((x) => x['id'] == d['id'])) acc.add(d);
          return acc;
        });
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Νέο Όχημα'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canCreateDept) ...[
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Προσωπικό')),
                      ButtonSegment(value: false, label: Text('Τμήματος')),
                    ],
                    selected: {isPersonal},
                    onSelectionChanged: (v) => setSt(() {
                      isPersonal = v.first;
                      if (isPersonal) selectedDeptId = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Όνομα',
                    errorText: nameError,
                  ),
                  onChanged: (_) => setSt(() => nameError = null),
                ),
                const SizedBox(height: 12),
                TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: 'Τύπος (αυτοκίνητο, σκάφος, κλπ)')),
                const SizedBox(height: 12),
                TextField(controller: regCtrl, decoration: const InputDecoration(labelText: 'Αρ. Κυκλοφορίας')),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'km', label: Text('Χιλιόμετρα')),
                    ButtonSegment(value: 'hours', label: Text('Ώρες')),
                  ],
                  selected: {meterType},
                  onSelectionChanged: (v) => setSt(() => meterType = v.first),
                ),
                if (!isPersonal && deptOptions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: selectedDeptId,
                    decoration: const InputDecoration(labelText: 'Τμήμα'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Κανένα')),
                      ...deptOptions.map((d) => DropdownMenuItem(
                        value: d['id'] as int,
                        child: Text(d['name'] as String),
                      )),
                    ],
                    onChanged: (v) => setSt(() => selectedDeptId = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
            FilledButton(
              onPressed: _creating
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty) {
                        setSt(() => nameError = 'Το όνομα είναι υποχρεωτικό');
                        return;
                      }
                      setSt(() => _creating = true);
                      final data = <String, dynamic>{
                        'name': nameCtrl.text.trim(),
                        'type': typeCtrl.text.trim(),
                        'meterType': meterType,
                      };
                      if (regCtrl.text.isNotEmpty) data['registrationNumber'] = regCtrl.text.trim();
                      if (!isPersonal && selectedDeptId != null) data['departmentId'] = selectedDeptId;
                      final err = await context.read<VehicleProvider>().create(data);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (err != null && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                      }
                      setSt(() => _creating = false);
                    },
              child: _creating
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Δημιουργία'),
            ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 2: Add DepartmentProvider import if not present**

Check the top of `vehicles_screen.dart` for the import:

```dart
import '../providers/department_provider.dart';
```

If missing, add it after the existing imports.

- [ ] **Step 3: Ensure DepartmentProvider is fetched before dialog**

In `_showCreateDialog`, when `auth.isAdmin` is true we read `deptProv.departments`. Ensure the department list is loaded by triggering a fetch in `initState` if the user is an admin. Add to `initState` in `_VehiclesScreenState`:

```dart
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      context.read<VehicleProvider>().fetchVehicles();
      final auth = context.read<AuthProvider>();
      if (auth.isAdmin || auth.isDeptAdmin) {
        context.read<DepartmentProvider>().fetchDepartments();
      }
    });
  }
```

- [ ] **Step 4: Verify Flutter analyzes cleanly**

```bash
cd frontend
flutter analyze lib/screens/vehicles_screen.dart
```

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/vehicles_screen.dart
git commit -m "feat: add personal/dept toggle to vehicle create dialog"
```

---

## Task 10: Final integration check

- [ ] **Step 1: Full Flutter analyze**

```bash
cd frontend
flutter analyze
```

Expected: `No issues found!` or only pre-existing warnings unrelated to vehicle files.

- [ ] **Step 2: Backend build**

```bash
cd backend
npm run build
```

Expected: no errors.

- [ ] **Step 3: Start dev environment and smoke-test**

Start backend:
```bash
cd backend
npm run dev
```

Start frontend:
```bash
cd frontend
flutter run -d chrome
```

Manual checks:
1. Log in as a normal user (volunteer). Navigate to Vehicles. The create FAB opens a dialog with no dept toggle — creating a vehicle produces a personal vehicle visible only to this user.
2. Log in as a dept admin. The create dialog shows the toggle; selecting "Τμήματος" reveals a dept dropdown. Creating a dept vehicle assigns it to the department.
3. Log in as a normal user (non-owner). Open a personal vehicle owned by another user — should get 403/not visible in list.
4. Log in as a dept admin. The edit/delete icons appear on dept vehicles for their department, not for other departments' vehicles.
5. Log in as a normal user. Open a dept vehicle — no edit/delete icons visible.

- [ ] **Step 4: Final commit if any tweaks made**

```bash
git add -p
git commit -m "fix: vehicle permissions integration tweaks"
```
