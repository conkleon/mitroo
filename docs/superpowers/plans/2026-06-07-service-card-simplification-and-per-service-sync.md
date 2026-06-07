# Service Card Simplification & Per-Service Mitroo Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the duplicate participant count from admin service cards and add a per-service sync icon that re-fetches a mitroo-linked service from the external system.

**Architecture:** Backend gets a new `syncSingleService(serviceId)` function in `mitrooSync.ts` (pages through the external API to find the specific mission) plus a `POST /api/services/:id/sync` endpoint. Frontend removes the redundant people-count from the card content row, adds `onSync`/`isSyncing` props to `ServiceCard`, and each tab widget wires those up.

**Tech Stack:** Flutter (Dart), Node.js/Express/TypeScript, Prisma, existing `MitrooClient`, existing `processMissions`/`syncShiftApplications` helpers.

---

## File Map

| File | Change |
|------|--------|
| `backend/src/lib/mitrooSync.ts` | Add `syncSingleService(serviceId)` export |
| `backend/src/routes/service.routes.ts` | Add `POST /:id/sync` endpoint; add `syncSingleService` to import |
| `frontend/lib/widgets/service_card.dart` | Remove duplicate count from content row; add `onSync`/`isSyncing` props + sync icon in action column |
| `frontend/lib/widgets/active_services_tab.dart` | Add `_syncingServiceIds` set + `_syncSingleService` method; pass `onSync`/`isSyncing` to `ServiceCard` |
| `frontend/lib/widgets/closed_services_tab.dart` | Same as above |
| `frontend/lib/widgets/completed_services_tab.dart` | Same as above |
| `frontend/lib/widgets/finalized_services_tab.dart` | Same as above |

---

## Task 1: Add `syncSingleService` to `mitrooSync.ts`

**Files:**
- Modify: `backend/src/lib/mitrooSync.ts` (append near bottom, before end of file)

- [ ] **Step 1: Add the function**

Open `backend/src/lib/mitrooSync.ts` and append this function before the closing of the file (after `syncShiftApplications` and its helpers, before `diagMissionHours` if present).

`processMissions`, `syncShiftApplications`, `getClient`, `setSyncStatus` are all defined in the same file — no extra imports needed. Declare `service` outside the `try` block so it's accessible in `catch`:

```typescript
export async function syncSingleService(serviceId: number): Promise<SyncResult> {
  const result: SyncResult = { created: 0, updated: 0, errors: [] };
  let service: { externalMissionId: number | null; departmentId: number; lifecycleStatus: string } | null = null;
  try {
    service = await prisma.service.findUnique({
      where: { id: serviceId },
      select: { externalMissionId: true, departmentId: true, lifecycleStatus: true },
    });

    if (!service?.externalMissionId) {
      result.errors.push("No external mission ID on this service");
      return result;
    }

    const { externalMissionId, departmentId, lifecycleStatus } = service;

    const client = await getClient(departmentId);

    const statusMap: Record<string, string> = {
      active: "open",
      closed: "closed",
      completed: "finished",
      finalized: "finalized",
    };
    const extStatus = statusMap[lifecycleStatus] ?? "open";

    const PAGE_SIZE = 200;
    let mission: import("./mitrooClient").ExternalMission | undefined;
    for (let page = 0; page < 500 && !mission; page++) {
      const rows = await client.fetchMissionPage(extStatus, page * PAGE_SIZE, PAGE_SIZE);
      if (rows.length === 0) break;
      mission = rows.find((r) => Number(r.id) === externalMissionId);
      if (rows.length < PAGE_SIZE) break;
    }

    if (!mission) {
      result.errors.push(`Mission ${externalMissionId} not found in external system (status=${extStatus})`);
      return result;
    }

    await processMissions(departmentId, [mission], client, result);

    const appResult = await syncShiftApplications(departmentId);
    result.created += appResult.created;
    result.updated += appResult.updated;
    result.errors.push(...appResult.errors);

    await setSyncStatus(departmentId, "service", "success");
  } catch (e: unknown) {
    const msg = String(e);
    result.errors.push(msg);
    console.error("[mitrooSync] syncSingleService: FATAL error:", e);
    await setSyncStatus(service?.departmentId ?? 0, "service", "failed", msg).catch(() => {});
  }
  return result;
}
```

- [ ] **Step 2: Verify TypeScript compiles**

```bash
cd backend && npm run build
```

Expected: no TypeScript errors. If you see `processMissions is not exported`, that's fine — it's in the same file, accessible without exporting.

- [ ] **Step 3: Commit**

```bash
cd backend
git add src/lib/mitrooSync.ts
git commit -m "feat(sync): add syncSingleService for targeted per-service mitroo sync"
```

---

## Task 2: Add `POST /services/:id/sync` endpoint

**Files:**
- Modify: `backend/src/routes/service.routes.ts`

- [ ] **Step 1: Add `syncSingleService` to the mitrooSync import**

The file already imports from `../lib/mitrooSync` (line ~10). Add `syncSingleService` to that import:

```typescript
import {
  writeBackNewService,
  writeBackAssignment,
  writeBackRejection,
  writeBackParticipation,
  writeBackHoursUpdate,
  writeBackServiceDelete,
  writeBackEnrollmentRequest,
  writeBackUnenroll,
  writeBackServiceClose,
  writeBackServiceComplete,
  syncSingleService,
} from "../lib/mitrooSync";
```

- [ ] **Step 2: Add the endpoint**

Find the end of the file (or just before `export default router`) and add:

```typescript
// ── POST /api/services/:id/sync ─────────────────
// Re-syncs a single service from the external mitroo system.
// Requires missionAdmin role for the service's department.
router.post("/:id/sync", async (req: Request, res: Response) => {
  const sid = Number(req.params.id);
  if (!Number.isFinite(sid)) {
    res.status(400).json({ error: "Invalid service ID" });
    return;
  }

  const svc = await prisma.service.findUnique({
    where: { id: sid },
    select: { departmentId: true, externalMissionId: true },
  });
  if (!svc) {
    res.status(404).json({ error: "Service not found" });
    return;
  }
  if (!svc.externalMissionId) {
    res.status(400).json({ error: "Service has no external mission ID" });
    return;
  }

  const userId = req.user!.userId;
  const isAdmin = req.user!.isAdmin;
  if (!isAdmin) {
    const allowed = await isMissionAdminInDepartment(userId, svc.departmentId);
    if (!allowed) {
      res.status(403).json({ error: "Δεν έχετε δικαίωμα" });
      return;
    }
  }

  const result = await syncSingleService(sid);
  res.json({ ok: true, ...result });
});
```

- [ ] **Step 3: Verify TypeScript compiles**

```bash
cd backend && npm run build
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
cd backend
git add src/routes/service.routes.ts
git commit -m "feat(api): add POST /services/:id/sync endpoint for per-service mitroo sync"
```

---

## Task 3: Simplify `ServiceCard` — remove duplicate count, add sync icon

**Files:**
- Modify: `frontend/lib/widgets/service_card.dart`

- [ ] **Step 1: Add `onSync` and `isSyncing` fields to `ServiceCard`**

In the field declarations section of `ServiceCard` (after `onAssignResponsible`):

```dart
final VoidCallback? onSync;
final bool isSyncing;
```

In the constructor (after `this.onAssignResponsible,`):

```dart
this.onSync,
this.isSyncing = false,
```

Full updated field list and constructor:

```dart
class ServiceCard extends StatelessWidget {
  final Map<String, dynamic> service;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final List<dynamic>? deptMembers;

  final VoidCallback? onClose;
  final VoidCallback? onComplete;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onOpenDetail;
  final void Function(int userId, String status)? onUpdateStatus;
  final void Function(int serviceId, int userId, Map<String, dynamic> us)? onUpdateHours;
  final void Function(int userId, String name)? onRemoveEnrollment;
  final void Function(Map<String, dynamic> member)? onDirectEnroll;
  final void Function(int userId, String newStatus)? onUpdateParticipation;
  final VoidCallback? onAssignResponsible;
  final VoidCallback? onSync;
  final bool isSyncing;

  const ServiceCard({
    super.key,
    required this.service,
    required this.isExpanded,
    required this.onToggleExpand,
    this.deptMembers,
    this.onClose,
    this.onComplete,
    this.onEdit,
    this.onDelete,
    this.onOpenDetail,
    this.onUpdateStatus,
    this.onUpdateHours,
    this.onRemoveEnrollment,
    this.onDirectEnroll,
    this.onUpdateParticipation,
    this.onAssignResponsible,
    this.onSync,
    this.isSyncing = false,
  });
```

- [ ] **Step 2: Remove `enrolledCount` and `requestedCount` from `_buildCardContent`**

In `build()`, the call to `_buildCardContent` currently passes `enrolledCount` and `requestedCount`. Remove those two arguments:

Before:
```dart
_buildCardContent(
    tt, name, description, location, enrolledCount,
    requestedCount, visSpecs),
```

After:
```dart
_buildCardContent(tt, name, description, location, visSpecs),
```

Update the `_buildCardContent` method signature — remove `int enrolledCount` and `int requestedCount` parameters:

Before:
```dart
Widget _buildCardContent(
  TextTheme tt,
  String name,
  String description,
  String location,
  int enrolledCount,
  int requestedCount,
  List<dynamic> visSpecs,
) {
```

After:
```dart
Widget _buildCardContent(
  TextTheme tt,
  String name,
  String description,
  String location,
  List<dynamic> visSpecs,
) {
```

Inside `_buildCardContent`, remove the people icon + count block and the requested badge. The info `Row` currently looks like:

```dart
Row(
  children: [
    if (location.isNotEmpty) ...[
      const Icon(Icons.location_on, size: 11, color: Color(0xFF6B7280)),
      const SizedBox(width: 2),
      Flexible(
        child: Text(location, ...),
      ),
      const SizedBox(width: 8),
    ],
    const Icon(Icons.calendar_today, size: 11, color: Color(0xFF6B7280)),
    const SizedBox(width: 2),
    Text(fmtServiceDate(service['startAt']), ...),
    const SizedBox(width: 8),
    const Icon(Icons.people, size: 11, color: Color(0xFFDC2626)),       // REMOVE
    const SizedBox(width: 2),                                            // REMOVE
    Text('$enrolledCount', ...),                                         // REMOVE
    if (requestedCount > 0) ...[                                         // REMOVE
      const SizedBox(width: 6),                                          // REMOVE
      Container(...),                                                    // REMOVE
    ],                                                                   // REMOVE
    if (visSpecs.isNotEmpty) ...[...],
  ],
),
```

Replace the entire info Row with:

```dart
Row(
  children: [
    if (location.isNotEmpty) ...[
      const Icon(Icons.location_on, size: 11, color: Color(0xFF6B7280)),
      const SizedBox(width: 2),
      Flexible(
        child: Text(location,
            style: const TextStyle(
                fontSize: 10, color: Color(0xFF4B5563)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ),
      const SizedBox(width: 8),
    ],
    const Icon(Icons.calendar_today, size: 11, color: Color(0xFF6B7280)),
    const SizedBox(width: 2),
    Text(fmtServiceDate(service['startAt']),
        style: const TextStyle(fontSize: 10, color: Color(0xFF4B5563))),
    const SizedBox(width: 8),
    if (visSpecs.isNotEmpty) ...[
      ...visSpecs.take(2).map((v) => Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFDDD6FE)),
              ),
              child: Text(v['specialization']?['name'] ?? '',
                  style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6D28D9))),
            ),
          )),
      if (visSpecs.length > 2)
        Text('+${visSpecs.length - 2}',
            style: const TextStyle(
                fontSize: 9, color: Color(0xFF6D28D9))),
    ],
  ],
),
```

- [ ] **Step 3: Add sync icon to `_buildActionColumn`**

In `_buildActionColumn`, after the `if (hasActions)` block (after the closing `],` of that block, before the final `],` of the `Column`'s children), add:

```dart
if (onSync != null) ...[
  const SizedBox(height: 4),
  Tooltip(
    message: 'Συγχρονισμός με Mitroo',
    child: GestureDetector(
      onTap: isSyncing ? null : onSync,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF0891B2).withAlpha(15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF0891B2).withAlpha(40)),
        ),
        child: isSyncing
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Color(0xFF0891B2),
                ),
              )
            : const Icon(Icons.sync, size: 14, color: Color(0xFF0891B2)),
      ),
    ),
  ),
],
```

The final `_buildActionColumn` children list becomes:

```dart
return Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    // people-count toggle (unchanged)
    InkWell(...),
    if (hasActions) ...[
      const SizedBox(height: 2),
      Row(children: [...]),
    ],
    // NEW: sync icon (only when onSync != null)
    if (onSync != null) ...[
      const SizedBox(height: 4),
      Tooltip(
        message: 'Συγχρονισμός με Mitroo',
        child: GestureDetector(
          onTap: isSyncing ? null : onSync,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF0891B2).withAlpha(15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF0891B2).withAlpha(40)),
            ),
            child: isSyncing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Color(0xFF0891B2),
                    ),
                  )
                : const Icon(Icons.sync, size: 14, color: Color(0xFF0891B2)),
          ),
        ),
      ),
    ],
  ],
);
```

- [ ] **Step 4: Verify Flutter analyzes cleanly**

```bash
cd frontend && flutter analyze lib/widgets/service_card.dart
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
cd frontend
git add lib/widgets/service_card.dart
git commit -m "feat(ui): simplify service card — remove duplicate count, add per-service sync icon"
```

---

## Task 4: Wire sync in `active_services_tab.dart`

**Files:**
- Modify: `frontend/lib/widgets/active_services_tab.dart`

- [ ] **Step 1: Add `_syncingServiceIds` set**

In the state class (`ActiveServicesTabState`), add a field after the existing `_expandedCards`:

```dart
final Set<int> _syncingServiceIds = {};
```

- [ ] **Step 2: Add `_syncSingleService` method**

Add this method to `ActiveServicesTabState` (after `_load()` or near the other async methods):

```dart
Future<void> _syncSingleService(int serviceId) async {
  if (_syncingServiceIds.contains(serviceId)) return;
  setState(() => _syncingServiceIds.add(serviceId));
  try {
    await _api.post('/services/$serviceId/sync', body: {});
  } catch (_) {}
  if (mounted) {
    setState(() => _syncingServiceIds.remove(serviceId));
    _load();
  }
}
```

- [ ] **Step 3: Pass `onSync` and `isSyncing` to `ServiceCard`**

Find the `ServiceCard(` call (around line 746 in the `itemBuilder`). Add two new named parameters after `onAssignResponsible`:

```dart
return ServiceCard(
  service: svc,
  isExpanded: _expandedCards.contains(id),
  onToggleExpand: () => setState(() {
    _expandedCards.contains(id)
        ? _expandedCards.remove(id)
        : _expandedCards.add(id);
  }),
  deptMembers: _deptMembers,
  onClose: () => _closeService(id, name),
  onEdit: () => context.push(
      '/admin/services/$id/edit?departmentId=${widget.departmentId}&departmentName=${Uri.encodeComponent(widget.departmentName)}'),
  onDelete: () => _deleteService(id, name),
  onOpenDetail: () => context.push('/admin/services/$id'),
  onUpdateStatus: (userId, status) =>
      _updateEnrollmentStatus(id, userId, status),
  onUpdateHours: (svcId, userId, us) =>
      _updateEnrollmentHours(svcId, userId, us),
  onRemoveEnrollment: (userId, uName) =>
      _removeEnrollment(id, userId, uName),
  onDirectEnroll: (member) => _directEnroll(id, member),
  onAssignResponsible: () => _showResponsiblePicker(svc),
  onSync: svc['externalMissionId'] != null
      ? () => _syncSingleService(id)
      : null,
  isSyncing: _syncingServiceIds.contains(id),
);
```

- [ ] **Step 4: Verify Flutter analyzes cleanly**

```bash
cd frontend && flutter analyze lib/widgets/active_services_tab.dart
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
cd frontend
git add lib/widgets/active_services_tab.dart
git commit -m "feat(ui): wire per-service sync in active services tab"
```

---

## Task 5: Wire sync in `closed_services_tab.dart`

**Files:**
- Modify: `frontend/lib/widgets/closed_services_tab.dart`

- [ ] **Step 1: Add `_syncingServiceIds` set**

In the state class, add after `_expandedCards`:

```dart
final Set<int> _syncingServiceIds = {};
```

- [ ] **Step 2: Add `_syncSingleService` method**

```dart
Future<void> _syncSingleService(int serviceId) async {
  if (_syncingServiceIds.contains(serviceId)) return;
  setState(() => _syncingServiceIds.add(serviceId));
  try {
    await _api.post('/services/$serviceId/sync', body: {});
  } catch (_) {}
  if (mounted) {
    setState(() => _syncingServiceIds.remove(serviceId));
    _load();
  }
}
```

- [ ] **Step 3: Pass `onSync` and `isSyncing` to `ServiceCard`**

Find the `ServiceCard(` call (around line 866). Add after `onAssignResponsible`:

```dart
return ServiceCard(
  service: svc,
  isExpanded: _expandedCards.contains(id),
  onToggleExpand: () => setState(() {
    _expandedCards.contains(id)
        ? _expandedCards.remove(id)
        : _expandedCards.add(id);
  }),
  deptMembers: _deptMembers,
  onComplete: () => _completeService(id, name),
  onOpenDetail: () => context.push('/admin/services/$id'),
  onUpdateStatus: (userId, status) =>
      _updateEnrollmentStatus(id, userId, status),
  onUpdateParticipation: (userId, status) =>
      _updateParticipation(id, userId, status),
  onUpdateHours: (svcId, userId, us) =>
      _updateEnrollmentHours(svcId, userId, us),
  onRemoveEnrollment: (userId, uName) =>
      _removeEnrollment(id, userId, uName),
  onDirectEnroll: (member) => _directEnroll(id, member),
  onAssignResponsible: () => _showResponsiblePicker(svc),
  onSync: svc['externalMissionId'] != null
      ? () => _syncSingleService(id)
      : null,
  isSyncing: _syncingServiceIds.contains(id),
);
```

- [ ] **Step 4: Verify and commit**

```bash
cd frontend && flutter analyze lib/widgets/closed_services_tab.dart
git add lib/widgets/closed_services_tab.dart
git commit -m "feat(ui): wire per-service sync in closed services tab"
```

---

## Task 6: Wire sync in `completed_services_tab.dart`

**Files:**
- Modify: `frontend/lib/widgets/completed_services_tab.dart`

- [ ] **Step 1: Add `_syncingServiceIds` set**

```dart
final Set<int> _syncingServiceIds = {};
```

- [ ] **Step 2: Add `_syncSingleService` method**

```dart
Future<void> _syncSingleService(int serviceId) async {
  if (_syncingServiceIds.contains(serviceId)) return;
  setState(() => _syncingServiceIds.add(serviceId));
  try {
    await _api.post('/services/$serviceId/sync', body: {});
  } catch (_) {}
  if (mounted) {
    setState(() => _syncingServiceIds.remove(serviceId));
    _load(silent: true);
  }
}
```

Note: `completed_services_tab` uses `_load(silent: true)` for refreshes — use that here.

- [ ] **Step 3: Pass `onSync` and `isSyncing` to `ServiceCard`**

Find the `ServiceCard(` call (around line 587). The current call looks like:

```dart
return ServiceCard(
  service: svc,
  isExpanded: _expandedCards.contains(id),
  onToggleExpand: () => setState(() {
    _expandedCards.contains(id)
        ? _expandedCards.remove(id)
        : _expandedCards.add(id);
  }),
  onOpenDetail: () => context.push('/admin/services/$id'),
  onUpdateParticipation: (userId, status) =>
      _updateParticipation(id, userId, status),
  onUpdateHours: (svcId, userId, us) =>
      _updateHours(svcId, userId, us),
);
```

Add `onSync` and `isSyncing` before the closing `)`:

```dart
return ServiceCard(
  service: svc,
  isExpanded: _expandedCards.contains(id),
  onToggleExpand: () => setState(() {
    _expandedCards.contains(id)
        ? _expandedCards.remove(id)
        : _expandedCards.add(id);
  }),
  onOpenDetail: () => context.push('/admin/services/$id'),
  onUpdateParticipation: (userId, status) =>
      _updateParticipation(id, userId, status),
  onUpdateHours: (svcId, userId, us) =>
      _updateHours(svcId, userId, us),
  onSync: svc['externalMissionId'] != null
      ? () => _syncSingleService(id)
      : null,
  isSyncing: _syncingServiceIds.contains(id),
);
```

- [ ] **Step 4: Verify and commit**

```bash
cd frontend && flutter analyze lib/widgets/completed_services_tab.dart
git add lib/widgets/completed_services_tab.dart
git commit -m "feat(ui): wire per-service sync in completed services tab"
```

---

## Task 7: Wire sync in `finalized_services_tab.dart`

**Files:**
- Modify: `frontend/lib/widgets/finalized_services_tab.dart`

- [ ] **Step 1: Add `_syncingServiceIds` set**

```dart
final Set<int> _syncingServiceIds = {};
```

- [ ] **Step 2: Add `_syncSingleService` method**

```dart
Future<void> _syncSingleService(int serviceId) async {
  if (_syncingServiceIds.contains(serviceId)) return;
  setState(() => _syncingServiceIds.add(serviceId));
  try {
    await _api.post('/services/$serviceId/sync', body: {});
  } catch (_) {}
  if (mounted) {
    setState(() => _syncingServiceIds.remove(serviceId));
    _load(silent: true);
  }
}
```

- [ ] **Step 3: Pass `onSync` and `isSyncing` to `ServiceCard`**

Find the `ServiceCard(` call (around line 466). The current call looks like:

```dart
return ServiceCard(
  service: svc,
  isExpanded: _expandedCards.contains(id),
  onToggleExpand: () => setState(() {
    _expandedCards.contains(id)
        ? _expandedCards.remove(id)
        : _expandedCards.add(id);
  }),
  onOpenDetail: () => context.push('/admin/services/$id'),
);
```

Add `onSync` and `isSyncing` before the closing `)`:

```dart
return ServiceCard(
  service: svc,
  isExpanded: _expandedCards.contains(id),
  onToggleExpand: () => setState(() {
    _expandedCards.contains(id)
        ? _expandedCards.remove(id)
        : _expandedCards.add(id);
  }),
  onOpenDetail: () => context.push('/admin/services/$id'),
  onSync: svc['externalMissionId'] != null
      ? () => _syncSingleService(id)
      : null,
  isSyncing: _syncingServiceIds.contains(id),
);
```

- [ ] **Step 4: Verify and commit**

```bash
cd frontend && flutter analyze lib/widgets/finalized_services_tab.dart
git add lib/widgets/finalized_services_tab.dart
git commit -m "feat(ui): wire per-service sync in finalized services tab"
```

---

## Task 8: Manual Verification

- [ ] **Step 1: Start the dev environment**

```bash
# Terminal 1 — databases
docker compose -f docker-compose.dev.yml up -d

# Terminal 2 — backend
cd backend && npm run dev

# Terminal 3 — frontend
cd frontend && flutter run -d chrome
```

- [ ] **Step 2: Verify card simplification**

Navigate to the admin Manage Services screen for any department with active services.
- Each card should show the participant count **only once** (right-side toggle button).
- The left content area should show: service name, description (if any), location + date + specialization badges + responsible-user chip. No people icon/count in that area.

- [ ] **Step 3: Verify sync icon visibility**

- Services with `externalMissionId` set should show a small teal sync icon (`sync`) in the action column, below the action buttons.
- Services created manually (no `externalMissionId`) should have no sync icon.

If all your test services lack `externalMissionId`, temporarily run a department sync from the app bar to import some mitroo-linked services.

- [ ] **Step 4: Verify sync icon behavior**

Tap the sync icon on a mitroo-linked service:
- Icon should change to a small spinning `CircularProgressIndicator` while syncing.
- On completion, the card should reload with fresh data.
- No crash, no error snackbar for a successful sync.

- [ ] **Step 5: Verify backend returns 400 for manual services**

From the browser dev tools network tab or a REST client, call:

```
POST /api/services/{id-of-manual-service}/sync
Authorization: Bearer <your-token>
```

Expected response: `400 { "error": "Service has no external mission ID" }`

- [ ] **Step 6: Final commit if all checks pass**

```bash
git add .
git commit -m "chore: verify service card simplification and per-service sync complete"
```
