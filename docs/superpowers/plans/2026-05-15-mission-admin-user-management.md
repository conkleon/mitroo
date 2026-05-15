# Mission Admin User Management — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow mission admins to create, edit, and delete users, manage department memberships, and manage specializations — scoped to the departments they administer.

**Architecture:** New `requireAdminOrMissionAdminForDept` middleware factory on the backend gates write endpoints by department scope. For user-targeting endpoints (where no single dept ID is in the params), inline scope checks verify department overlap. Frontend: `AuthProvider` gains `canManageUsersInDepartment` and `isDepartmentMissionAdmin`; UI widgets replace bare `isAdmin` checks with scoped variants.

**Tech Stack:** Node.js/Express/TypeScript backend, Flutter/Dart frontend, Prisma ORM, PostgreSQL

---

### Task 1: Add `requireAdminOrMissionAdminForDept` middleware

**Files:**
- Modify: `backend/src/middleware/auth.ts`

- [ ] **Step 1: Add the middleware function after `isMissionAdminInDepartment`**

Add this code after line 71 (after `isMissionAdminInDepartment`):

```ts
/** Require system-admin OR mission-admin over the department returned by getDeptId. */
export function requireAdminOrMissionAdminForDept(
  getDeptId: (req: Request) => number,
): (req: Request, res: Response, next: NextFunction) => Promise<void> {
  return async (req: Request, res: Response, next: NextFunction) => {
    if (!req.user) {
      res.status(401).json({ error: "Authentication required" });
      return;
    }
    if (req.user.isAdmin) {
      next();
      return;
    }
    const deptId = getDeptId(req);
    if (Number.isNaN(deptId)) {
      res.status(400).json({ error: "Invalid department id" });
      return;
    }
    const allowed = await isMissionAdminInDepartment(req.user.userId, deptId);
    if (!allowed) {
      res.status(403).json({ error: "Admin access required for this department" });
      return;
    }
    next();
  };
}
```

- [ ] **Step 2: Verify the file compiles**

Run: `cd backend && npx tsc --noEmit`
Expected: no new errors.

- [ ] **Step 3: Commit**

```bash
git add backend/src/middleware/auth.ts
git commit -m "feat: add requireAdminOrMissionAdminForDept middleware factory
"
```

---

### Task 2: Replace `requireAdmin` on user-targeting write endpoints

**Files:**
- Modify: `backend/src/routes/user.routes.ts`

For `PATCH /api/users/:id`, `DELETE /api/users/:id`, `POST /api/users/:id/specializations`, `DELETE /api/users/:uid/specializations/:sid`, replace `requireAdmin` with an inline scope check that verifies the target user shares at least one department with a mission-admin caller.

- [ ] **Step 1: Update imports in user.routes.ts (line 7)**

Change:
```ts
import { authenticate, getMissionAdminDepartmentIds, requireAdmin } from "../middleware/auth";
```
To:
```ts
import { authenticate, getMissionAdminDepartmentIds, requireAdminOrMissionAdminForDept } from "../middleware/auth";
```

- [ ] **Step 2: Add a `canWriteUserByScope` helper after `canReadUserByScope` (after line 95)**

```ts
async function canWriteUserByScope(scope: UserAccessScope, targetUserId: number): Promise<boolean> {
  if (scope.kind === "admin") {
    return true;
  }
  if (scope.kind === "self") {
    return false; // self cannot write other users
  }
  const targetDepts = await prisma.userDepartment.findMany({
    where: { userId: targetUserId },
    select: { departmentId: true },
  });
  const targetDeptIds = targetDepts.map((d) => d.departmentId);
  return targetDeptIds.some((id) => scope.departmentIds.includes(id));
}
```

- [ ] **Step 3: Replace `requireAdmin` on `PATCH /api/users/:id` (line 341)**

Change:
```ts
router.patch("/:id", requireAdmin, async (req: Request, res: Response) => {
```
To:
```ts
router.patch("/:id", async (req: Request, res: Response) => {
```

And add a scope check after `targetUserId` is computed and before the update logic (after line 344). Add after `const data = updateSchema.parse(req.body);`:

```ts
    const scope = await getAccessScope(req);
    const writeAllowed = await canWriteUserByScope(scope, targetUserId);
    if (!writeAllowed) {
      res.status(403).json({ error: "Access denied" });
      return;
    }

    // Strip isAdmin from body for non-system-admin callers
    const cleanData = req.user!.isAdmin ? data : { ...data, isAdmin: undefined };
```

Then change the `prisma.user.update` data from `data` to `cleanData`:

Change:
```ts
      data: {
        ...data,
        birthDate: data.birthDate ? new Date(data.birthDate) : data.birthDate === null ? null : undefined,
      },
```
To:
```ts
      data: {
        ...cleanData,
        birthDate: cleanData.birthDate ? new Date(cleanData.birthDate) : cleanData.birthDate === null ? null : undefined,
      },
```

- [ ] **Step 4: Replace `requireAdmin` on `DELETE /api/users/:id` (line 378)**

Change:
```ts
router.delete("/:id", requireAdmin, async (req: Request, res: Response) => {
  await prisma.user.delete({ where: { id: Number(req.params.id) } });
  res.status(204).end();
});
```
To:
```ts
router.delete("/:id", async (req: Request, res: Response) => {
  const targetUserId = Number(req.params.id);
  const scope = await getAccessScope(req);
  const writeAllowed = await canWriteUserByScope(scope, targetUserId);
  if (!writeAllowed) {
    res.status(403).json({ error: "Access denied" });
    return;
  }
  await prisma.user.delete({ where: { id: targetUserId } });
  res.status(204).end();
});
```

- [ ] **Step 5: Replace `requireAdmin` on `POST /api/users/:id/specializations` (line 444)**

Change:
```ts
router.post("/:id/specializations", requireAdmin, async (req: Request, res: Response) => {
  const { specializationId } = req.body;
  const record = await prisma.userSpecialization.create({
    data: { userId: Number(req.params.id), specializationId: Number(specializationId) },
    include: { specialization: true },
  });
  res.status(201).json(record);
});
```
To:
```ts
router.post("/:id/specializations", async (req: Request, res: Response) => {
  const targetUserId = Number(req.params.id);
  const scope = await getAccessScope(req);
  const writeAllowed = await canWriteUserByScope(scope, targetUserId);
  if (!writeAllowed) {
    res.status(403).json({ error: "Access denied" });
    return;
  }
  const { specializationId } = req.body;
  const record = await prisma.userSpecialization.create({
    data: { userId: targetUserId, specializationId: Number(specializationId) },
    include: { specialization: true },
  });
  res.status(201).json(record);
});
```

- [ ] **Step 6: Replace `requireAdmin` on `DELETE /api/users/:uid/specializations/:sid` (line 454)**

Change:
```ts
router.delete("/:uid/specializations/:sid", requireAdmin, async (req: Request, res: Response) => {
  await prisma.userSpecialization.delete({
    where: { userId_specializationId: { userId: Number(req.params.uid), specializationId: Number(req.params.sid) } },
  });
  res.status(204).end();
});
```
To:
```ts
router.delete("/:uid/specializations/:sid", async (req: Request, res: Response) => {
  const targetUserId = Number(req.params.uid);
  const scope = await getAccessScope(req);
  const writeAllowed = await canWriteUserByScope(scope, targetUserId);
  if (!writeAllowed) {
    res.status(403).json({ error: "Access denied" });
    return;
  }
  await prisma.userSpecialization.delete({
    where: { userId_specializationId: { userId: targetUserId, specializationId: Number(req.params.sid) } },
  });
  res.status(204).end();
});
```

- [ ] **Step 7: Verify compilation**

Run: `cd backend && npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 8: Commit**

```bash
git add backend/src/routes/user.routes.ts
git commit -m "feat: allow mission admins to write users in their departments
"
```

---

### Task 3: Replace `requireAdmin` on `POST /api/users` and strip `isAdmin` for non-system-admins

**Files:**
- Modify: `backend/src/routes/user.routes.ts:227-338`

- [ ] **Step 1: Replace `requireAdmin` on `POST /api/users` (line 227)**

Change:
```ts
router.post("/", requireAdmin, async (req: Request, res: Response) => {
```
To:
```ts
router.post("/", requireAdminOrMissionAdminForDept((req) => Number(req.body?.departmentId)), async (req: Request, res: Response) => {
```

- [ ] **Step 2: Strip `isAdmin` from body for non-system-admin callers**

After the Zod parse line (`const data = createUserSchema.parse(req.body);`), add:

```ts
    if (!req.user!.isAdmin) {
      // Mission admins cannot set isAdmin on new users
      (data as any).isAdmin = false;
    }
```

Note: `createUserSchema` doesn't include `isAdmin` field by default, but add this guard in case it's added to the body.

- [ ] **Step 3: Verify compilation**

Run: `cd backend && npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add backend/src/routes/user.routes.ts
git commit -m "feat: allow mission admins to create users in their departments
"
```

---

### Task 4: Replace `requireAdmin` on department member management and fix `PATCH /api/departments/:id`

**Files:**
- Modify: `backend/src/routes/department.routes.ts`

- [ ] **Step 1: Update imports in department.routes.ts (line 4)**

Change:
```ts
import { authenticate, isMissionAdminInDepartment, requireAdmin } from "../middleware/auth";
```
To:
```ts
import { authenticate, isMissionAdminInDepartment, requireAdmin, requireAdminOrMissionAdminForDept } from "../middleware/auth";
```

- [ ] **Step 2: Replace `requireAdmin` on `POST /api/departments/:id/members` (line 96)**

Change:
```ts
router.post("/:id/members", requireAdmin, async (req: Request, res: Response) => {
```
To:
```ts
router.post("/:id/members", requireAdminOrMissionAdminForDept((req) => Number(req.params.id)), async (req: Request, res: Response) => {
```

- [ ] **Step 3: Replace `requireAdmin` on `PATCH /api/departments/:deptId/members/:userId` (line 111)**

Change:
```ts
router.patch("/:deptId/members/:userId", requireAdmin, async (req: Request, res: Response) => {
```
To:
```ts
router.patch("/:deptId/members/:userId", requireAdminOrMissionAdminForDept((req) => Number(req.params.deptId)), async (req: Request, res: Response) => {
```

- [ ] **Step 4: Replace `requireAdmin` on `DELETE /api/departments/:deptId/members/:userId` (line 123)**

Change:
```ts
router.delete("/:deptId/members/:userId", requireAdmin, async (req: Request, res: Response) => {
```
To:
```ts
router.delete("/:deptId/members/:userId", requireAdminOrMissionAdminForDept((req) => Number(req.params.deptId)), async (req: Request, res: Response) => {
```

- [ ] **Step 5: Fix `PATCH /api/departments/:id` — add guard and lock `name` for non-system-admins (line 60)**

Change:
```ts
router.patch("/:id", async (req: Request, res: Response) => {
  try {
    const data = createSchema.partial().parse(req.body);
    const dept = await prisma.department.update({ where: { id: Number(req.params.id) }, data });
    res.json(dept);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});
```
To:
```ts
router.patch("/:id", requireAdminOrMissionAdminForDept((req) => Number(req.params.id)), async (req: Request, res: Response) => {
  try {
    const rawData = createSchema.partial().parse(req.body);

    // Mission admins cannot change department name — silently drop it
    const data = req.user!.isAdmin ? rawData : { ...rawData, name: undefined };

    const dept = await prisma.department.update({ where: { id: Number(req.params.id) }, data });
    res.json(dept);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});
```

- [ ] **Step 6: Verify compilation**

Run: `cd backend && npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add backend/src/routes/department.routes.ts
git commit -m "feat: allow mission admins to manage department members and edit their departments
"
```

---

### Task 5: Add `canManageUsersInDepartment` and `isDepartmentMissionAdmin` to AuthProvider

**Files:**
- Modify: `frontend/lib/providers/auth_provider.dart`

- [ ] **Step 1: Add `isDepartmentMissionAdmin` getter after `isItemAdmin` (after line 40)**

```dart
  /// True when user is missionAdmin in at least one dept (excluding sys admin).
  bool get isDepartmentMissionAdmin {
    if (isAdmin) return false;
    final depts = _user?['departments'] as List<dynamic>?;
    if (depts == null) return false;
    return depts.any((d) => d['role'] == 'missionAdmin');
  }
```

- [ ] **Step 2: Add `canManageUsersInDepartment` method after `isDepartmentMissionAdmin`**

```dart
  /// Whether the user can manage (create/edit/delete) users in a specific department.
  bool canManageUsersInDepartment(int deptId) {
    if (isAdmin) return true;
    final depts = _user?['departments'] as List<dynamic>? ?? [];
    return depts.any((d) =>
      d['role'] == 'missionAdmin' && d['department']?['id'] == deptId
    );
  }
```

- [ ] **Step 3: Verify analysis**

Run: `cd frontend && flutter analyze lib/providers/auth_provider.dart`
Expected: no new issues.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/providers/auth_provider.dart
git commit -m "feat: add canManageUsersInDepartment and isDepartmentMissionAdmin to AuthProvider
"
```

---

### Task 6: Show Users and Departments tiles for mission admins in Admin Panel

**Files:**
- Modify: `frontend/lib/screens/admin_panel_screen.dart`

- [ ] **Step 1: Read current state around lines 131-181**

The System Management section (lines 131-181) wraps all tiles in `if (isSysAdmin)`. Split it so Users and Departments show for mission admins too.

- [ ] **Step 2: Replace the System Management block (lines 131-181)**

Change:
```dart
                        if (isSysAdmin) ...[
                          _SectionHeader(
                              icon: Icons.settings,
                              label: 'Διαχείρηση Συστήματος'),
                          _ResponsiveTileGrid(
                            isWide: isWide,
                            isCompact: isCompact,
                            tiles: [
                              _AdminTileData(
                                icon: Icons.people,
                                iconColor: const Color(0xFFDC2626),
                                bgColor: const Color(0xFFFEE2E2),
                                title: 'Διαχείρηση Χρηστών',
                                subtitle:
                                    'Δημιουργία, επεξεργασία & ανάθεση ρόλων',
                                onTap: () => context.push('/admin/users'),
                              ),
                              _AdminTileData(
                                icon: Icons.business,
                                iconColor: const Color(0xFF7C3AED),
                                bgColor: const Color(0xFFEDE9FE),
                                title: 'Διαχείρηση Τμημάτων',
                                subtitle: 'Δημιουργία & ρύθμιση τμημάτων',
                                onTap: () =>
                                    context.push('/admin/departments'),
                              ),
                              _AdminTileData(
                                icon: Icons.school,
                                iconColor: const Color(0xFFD97706),
                                bgColor: const Color(0xFFFEF3C7),
                                title: 'Διαχείρηση Ειδικεύσεων',
                                subtitle:
                                    'Δημιουργία & ανάθεση ειδικεύσεων',
                                onTap: () =>
                                    context.push('/admin/specializations'),
                              ),
                              _AdminTileData(
                                icon: Icons.category,
                                iconColor: const Color(0xFF0891B2),
                                bgColor: const Color(0xFFECFEFF),
                                title: 'Τύποι Υπηρεσιών',
                                subtitle:
                                    'Διαχείριση τύπων υπηρεσιών & ορατότητας',
                                onTap: () =>
                                    context.push('/admin/service-types'),
                              ),
                            ],
                          ),
                          SizedBox(height: isCompact ? 20 : 28),
                        ],
```

To:
```dart
                        if (isSysAdmin || auth.isDepartmentMissionAdmin) ...[
                          _SectionHeader(
                              icon: Icons.settings,
                              label: 'Διαχείρηση Συστήματος'),
                          _ResponsiveTileGrid(
                            isWide: isWide,
                            isCompact: isCompact,
                            tiles: [
                              _AdminTileData(
                                icon: Icons.people,
                                iconColor: const Color(0xFFDC2626),
                                bgColor: const Color(0xFFFEE2E2),
                                title: 'Διαχείρηση Χρηστών',
                                subtitle:
                                    'Δημιουργία, επεξεργασία & ανάθεση ρόλων',
                                onTap: () => context.push('/admin/users'),
                              ),
                              _AdminTileData(
                                icon: Icons.business,
                                iconColor: const Color(0xFF7C3AED),
                                bgColor: const Color(0xFFEDE9FE),
                                title: 'Διαχείρηση Τμημάτων',
                                subtitle: 'Δημιουργία & ρύθμιση τμημάτων',
                                onTap: () =>
                                    context.push('/admin/departments'),
                              ),
                              if (isSysAdmin) ...[
                                _AdminTileData(
                                  icon: Icons.school,
                                  iconColor: const Color(0xFFD97706),
                                  bgColor: const Color(0xFFFEF3C7),
                                  title: 'Διαχείρηση Ειδικεύσεων',
                                  subtitle:
                                      'Δημιουργία & ανάθεση ειδικεύσεων',
                                  onTap: () =>
                                      context.push('/admin/specializations'),
                                ),
                                _AdminTileData(
                                  icon: Icons.category,
                                  iconColor: const Color(0xFF0891B2),
                                  bgColor: const Color(0xFFECFEFF),
                                  title: 'Τύποι Υπηρεσιών',
                                  subtitle:
                                      'Διαχείριση τύπων υπηρεσιών & ορατότητας',
                                  onTap: () =>
                                      context.push('/admin/service-types'),
                                ),
                              ],
                            ],
                          ),
                          SizedBox(height: isCompact ? 20 : 28),
                        ],
```

- [ ] **Step 3: Verify analysis**

Run: `cd frontend && flutter analyze lib/screens/admin_panel_screen.dart`
Expected: no issues.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/screens/admin_panel_screen.dart
git commit -m "feat: show Users and Departments tiles for mission admins in admin panel
"
```

---

### Task 7: Show Users and Departments sidebar links for mission admins

**Files:**
- Modify: `frontend/lib/screens/shell_screen.dart`

- [ ] **Step 1: Replace the system-admin-only condition for Users/Departments/Specializations sidebar children (lines 221-246)**

Change:
```dart
                      if (isSysAdmin) ...[
                        _BrandSidebarItem(
                          icon: Icons.people_outline,
                          selectedIcon: Icons.people,
                          label: 'Χρήστες',
                          selected: currentPath.startsWith('/admin/users'),
                          onTap: () => context.push('/admin/users'),
                          indent: true,
                        ),
                        _BrandSidebarItem(
                          icon: Icons.business_outlined,
                          selectedIcon: Icons.business,
                          label: 'Τμήματα',
                          selected: currentPath.startsWith('/admin/departments'),
                          onTap: () => context.push('/admin/departments'),
                          indent: true,
                        ),
                        _BrandSidebarItem(
                          icon: Icons.school_outlined,
                          selectedIcon: Icons.school,
                          label: 'Ειδικότητες',
                          selected: currentPath.startsWith('/admin/specializations'),
                          onTap: () => context.push('/admin/specializations'),
                          indent: true,
                        ),
                      ],
```

To:
```dart
                      if (isSysAdmin || auth.isDepartmentMissionAdmin) ...[
                        _BrandSidebarItem(
                          icon: Icons.people_outline,
                          selectedIcon: Icons.people,
                          label: 'Χρήστες',
                          selected: currentPath.startsWith('/admin/users'),
                          onTap: () => context.push('/admin/users'),
                          indent: true,
                        ),
                        _BrandSidebarItem(
                          icon: Icons.business_outlined,
                          selectedIcon: Icons.business,
                          label: 'Τμήματα',
                          selected: currentPath.startsWith('/admin/departments'),
                          onTap: () => context.push('/admin/departments'),
                          indent: true,
                        ),
                        if (isSysAdmin)
                          _BrandSidebarItem(
                            icon: Icons.school_outlined,
                            selectedIcon: Icons.school,
                            label: 'Ειδικότητες',
                            selected: currentPath.startsWith('/admin/specializations'),
                            onTap: () => context.push('/admin/specializations'),
                            indent: true,
                          ),
                      ],
```

- [ ] **Step 2: Verify analysis**

Run: `cd frontend && flutter analyze lib/screens/shell_screen.dart`
Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/screens/shell_screen.dart
git commit -m "feat: show Users and Departments sidebar links for mission admins
"
```

---

### Task 8: Show FAB for mission admins in Manage Users screen

**Files:**
- Modify: `frontend/lib/screens/manage_users_screen.dart`

- [ ] **Step 1: Replace the `isAdmin` check for the FAB (line 441)**

Change:
```dart
      floatingActionButton: auth.isAdmin && !_selectionMode
          ? FloatingActionButton.extended(
              onPressed: _showCreateDialog,
              icon: const Icon(Icons.person_add),
              label: const Text('Νέος Χρήστης'),
            )
          : null,
```

To:
```dart
      floatingActionButton: (auth.isAdmin || auth.isDepartmentMissionAdmin) && !_selectionMode
          ? FloatingActionButton.extended(
              onPressed: _showCreateDialog,
              icon: const Icon(Icons.person_add),
              label: const Text('Νέος Χρήστης'),
            )
          : null,
```

- [ ] **Step 2: Verify analysis**

Run: `cd frontend && flutter analyze lib/screens/manage_users_screen.dart`
Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/screens/manage_users_screen.dart
git commit -m "feat: show New User FAB for mission admins in user management
"
```

---

### Task 9: Replace `isAdmin` with scoped check in User Detail screen

**Files:**
- Modify: `frontend/lib/screens/user_detail_screen.dart`

- [ ] **Step 1: Add a `_canManage` getter to `_UserDetailBodyState` (after line 45)**

Add after the existing state fields:

```dart
  /// True when the current user can manage (edit/delete/manage depts/specs)
  /// this target user. System admins can manage anyone. Mission admins can
  /// manage users who share at least one department with them.
  bool get _canManage {
    final auth = context.read<AuthProvider>();
    if (auth.isAdmin) return true;
    if (!auth.isDepartmentMissionAdmin) return false;

    final depts = _user?['departments'] as List<dynamic>? ?? [];
    final userDeptIds = depts
        .map((d) => (d['department']?['id'] ?? d['departmentId']) as int)
        .toSet();
    final myDeptIds = auth.missionAdminDepartments
        .map((d) => d['id'] as int)
        .toSet();
    return userDeptIds.intersection(myDeptIds).isNotEmpty;
  }
```

- [ ] **Step 2: Replace `canManage = context.watch<AuthProvider>().isAdmin` in build() (line 438)**

Change:
```dart
    final canManage = context.watch<AuthProvider>().isAdmin;
```
To:
```dart
    final canManage = _canManage;
```

- [ ] **Step 3: Hide system admin toggle for non-system-admin callers in `_editProfile` (line 133)**

Change the SwitchListTile block (lines 133-139):
```dart
                  SwitchListTile(
                    title: const Text('Διαχειριστής Συστήματος'),
                    value: isAdmin,
                    onChanged: (v) => setDlgState(() => isAdmin = v),
                    contentPadding: EdgeInsets.zero,
                  ),
```
To:
```dart
                  if (canManage && context.read<AuthProvider>().isAdmin)
                    SwitchListTile(
                      title: const Text('Διαχειριστής Συστήματος'),
                      value: isAdmin,
                      onChanged: (v) => setDlgState(() => isAdmin = v),
                      contentPadding: EdgeInsets.zero,
                    ),
```

Add `canManage` capture in `_editProfile` — change line 83:
```dart
    final canManage = context.read<AuthProvider>().isAdmin;
```
To:
```dart
    final auth = context.read<AuthProvider>();
    final canManage = auth.isAdmin || auth.isDepartmentMissionAdmin;
```

- [ ] **Step 4: Verify analysis**

Run: `cd frontend && flutter analyze lib/screens/user_detail_screen.dart`
Expected: no issues.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/user_detail_screen.dart
git commit -m "feat: scope user detail edit controls to mission admin departments
"
```

---

### Task 10: Lock department name field for non-system-admins in Department Detail

**Files:**
- Modify: `frontend/lib/screens/department_detail_screen.dart`

- [ ] **Step 1: Update `_editDepartment` to lock name field for non-system-admins (lines 57-120)**

Add auth reading at the top of `_editDepartment` and conditionally disable the name field:

Change the `_editDepartment` method (starting at line 57):

Before the dialog builder, after the controller lines, add:
```dart
    final auth = context.read<AuthProvider>();
    final canEditName = auth.isAdmin;
```

Then change the name TextField (lines 74-77):
```dart
                TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Όνομα', border: OutlineInputBorder())),
```
To:
```dart
                TextField(
                    controller: nameCtrl,
                    enabled: canEditName,
                    decoration: InputDecoration(
                        labelText: canEditName ? 'Όνομα' : 'Όνομα (Μόνο διαχειριστής)',
                        border: const OutlineInputBorder())),
```

And on save (line 101), conditionally include `name`:
Change:
```dart
              final body = <String, dynamic>{
                'name': nameCtrl.text.trim(),
              };
```
To:
```dart
              final body = <String, dynamic>{};
              if (canEditName) {
                body['name'] = nameCtrl.text.trim();
              }
```

- [ ] **Step 2: Hide delete button for non-system-admins (line 355-358)**

Change:
```dart
          IconButton(
              icon: const Icon(Icons.delete, color: Color(0xFFDC2626)),
              onPressed: _deleteDepartment,
              tooltip: 'Διαγραφή'),
```
To:
```dart
          if (auth.isAdmin)
            IconButton(
                icon: const Icon(Icons.delete, color: Color(0xFFDC2626)),
                onPressed: _deleteDepartment,
                tooltip: 'Διαγραφή'),
```

The `auth` variable needs to be extracted in the build method. After line 368 where `final auth = context.read<AuthProvider>();` is already declared — yes, it's already there for the `canSync` check.

- [ ] **Step 3: Hide the edit button for non-admin users (lines 350-353)**

Only mission admins and system admins should see the edit button:

```dart
          if (auth.isAdmin || auth.isDepartmentMissionAdmin)
            IconButton(
                icon: const Icon(Icons.edit),
                onPressed: _editDepartment,
                tooltip: 'Επεξεργασία'),
```

Wait — this changes the existing behavior where any authenticated user could edit. Since the backend now guards with `requireAdminOrMissionAdminForDept`, any unauthorized edit will be rejected server-side. But hiding the button is cleaner. Update the app bar actions block (lines 349-358):

Change:
```dart
        actions: [
          IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _editDepartment,
              tooltip: 'Επεξεργασία'),
          IconButton(
              icon: const Icon(Icons.delete, color: Color(0xFFDC2626)),
              onPressed: _deleteDepartment,
              tooltip: 'Διαγραφή'),
        ],
```
To:
```dart
        actions: [
          if (auth.isAdmin || auth.isDepartmentMissionAdmin)
            IconButton(
                icon: const Icon(Icons.edit),
                onPressed: _editDepartment,
                tooltip: 'Επεξεργασία'),
          if (auth.isAdmin)
            IconButton(
                icon: const Icon(Icons.delete, color: Color(0xFFDC2626)),
                onPressed: _deleteDepartment,
                tooltip: 'Διαγραφή'),
        ],
```

- [ ] **Step 4: Verify analysis**

Run: `cd frontend && flutter analyze lib/screens/department_detail_screen.dart`
Expected: no issues.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/department_detail_screen.dart
git commit -m "feat: lock department name for non-system admins, hide edit/delete from unauthorized users
"
```

---

### Task 11: Full-stack smoke test

- [ ] **Step 1: Start backend**

Run: `cd backend && npm run dev`

- [ ] **Step 2: Start frontend**

Run: `cd frontend && flutter run -d chrome`

- [ ] **Step 3: Verify mission admin can create a user in their department**

Log in as mission admin → Admin Panel → Users → New User, select an administered department → create.

Expected: user created successfully, invite email sent.

- [ ] **Step 4: Verify mission admin cannot create user in non-administered department**

Via API: `POST /api/users` with `departmentId` outside mission admin's scope.

Expected: 403.

- [ ] **Step 5: Verify mission admin can edit/delete users in their departments**

Edit user profile, change department role, add/remove specializations.

Expected: all operations succeed.

- [ ] **Step 6: Verify mission admin cannot toggle system admin**

Edit user → no system admin switch visible.

Expected: isAdmin not settable.

- [ ] **Step 7: Verify mission admin can edit department description/location**

Department detail → edit → change description/location → save.

Expected: changes persisted, name unchanged.

- [ ] **Step 8: Verify mission admin cannot change department name**

Department detail → name field disabled.

Expected: name read-only.

- [ ] **Step 9: Verify system admin retains all capabilities**

Log in as system admin → verify all admin functions work as before.

Expected: no regressions.
```
