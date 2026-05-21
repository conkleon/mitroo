# Past Services Lifecycle Status Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add "Κλειστές" / "Ολοκληρωμένες" filter chips to `PastServicesScreen` that re-fetch from the server, defaulting to `closed` only.

**Architecture:** New `lifecycleStatus` query param on `GET /services` filters by `where.lifecycleStatus = { in: [...] }` in Prisma. The Flutter screen adds a `Set<String>` state field, updates `_load()` to send repeated `lifecycleStatus=` params, and renders two always-visible `FilterChip` widgets above the existing specialization strip.

**Tech Stack:** TypeScript / Express / Prisma (backend); Flutter / Dart (frontend)

---

## File Map

| File | Change |
|------|--------|
| `backend/src/routes/service.routes.ts` | Add `lifecycleStatus` to query destructure + Prisma where filter |
| `frontend/lib/screens/past_services_screen.dart` | Add state field, update `_load()`, add chip strip + helper method |

---

### Task 1: Add `lifecycleStatus` filter to `GET /services`

**Files:**
- Modify: `backend/src/routes/service.routes.ts` (line 97 and ~line 125)

- [ ] **Step 1: Update the query param destructure**

Find this line (line 97):
```ts
const { departmentId, includeEnrollments, fromDate, toDate, specializationId, pastOnly, includeExpired } = req.query;
```

Replace with:
```ts
const { departmentId, includeEnrollments, fromDate, toDate, specializationId, pastOnly, includeExpired, lifecycleStatus } = req.query;
```

- [ ] **Step 2: Add the Prisma where filter**

Find the `specializationId` block (it ends around line 125):
```ts
  if (specializationId) {
    where.serviceType = {
      specializations: {
        some: { specializationId: Number(specializationId) },
      },
    };
  }
```

Add the lifecycle filter immediately after it:
```ts
  if (lifecycleStatus) {
    const statuses = Array.isArray(lifecycleStatus) ? lifecycleStatus : [lifecycleStatus];
    where.lifecycleStatus = { in: statuses };
  }
```

- [ ] **Step 3: Manual verification**

Start the backend:
```bash
cd backend && npm run dev
```

Test with curl (replace `<token>` and `<deptId>`):
```bash
# Should return only closed services
curl -s -H "Authorization: Bearer <token>" \
  "http://localhost:4000/api/services?departmentId=<deptId>&pastOnly=true&lifecycleStatus=closed" \
  | jq '.[].lifecycleStatus' | sort | uniq

# Expected output:
"closed"

# Both statuses
curl -s -H "Authorization: Bearer <token>" \
  "http://localhost:4000/api/services?departmentId=<deptId>&pastOnly=true&lifecycleStatus=closed&lifecycleStatus=completed" \
  | jq '.[].lifecycleStatus' | sort | uniq

# Expected output (one or both, depending on data):
"closed"
"completed"
```

- [ ] **Step 4: Commit**

```bash
git add backend/src/routes/service.routes.ts
git commit -m "feat(api): add lifecycleStatus filter param to GET /services"
```

---

### Task 2: Add state + update `_load()` in `PastServicesScreen`

**Files:**
- Modify: `frontend/lib/screens/past_services_screen.dart`

- [ ] **Step 1: Add the lifecycle state field**

Find the existing state fields block (around line 25–33):
```dart
  String _search = '';
  int? _selectedSpecId;
  DateTime? _fromDate;
  DateTime? _toDate;
```

Add `_selectedLifecycleStatuses` after `_toDate`:
```dart
  String _search = '';
  int? _selectedSpecId;
  DateTime? _fromDate;
  DateTime? _toDate;
  Set<String> _selectedLifecycleStatuses = {'closed'};
```

- [ ] **Step 2: Update `_load()` to send repeated lifecycle params**

Find the current query-building lines inside `_load()`:
```dart
      final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
      final res = await _api.get('/services?$query');
```

Replace with:
```dart
      final parts = params.entries.map((e) => '${e.key}=${e.value}').toList();
      for (final s in _selectedLifecycleStatuses) {
        parts.add('lifecycleStatus=$s');
      }
      final query = parts.join('&');
      final res = await _api.get('/services?$query');
```

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/screens/past_services_screen.dart
git commit -m "feat(ui): wire lifecycle status filter state into PastServicesScreen _load"
```

---

### Task 3: Add lifecycle filter chip strip to the UI

**Files:**
- Modify: `frontend/lib/screens/past_services_screen.dart`

- [ ] **Step 1: Add the `_lifecycleChip` helper method**

Find any existing helper method in the file (e.g. `_buildDateButton`) and add `_lifecycleChip` alongside it (outside the `build` method, inside the State class):

```dart
  Widget _lifecycleChip(String value, String label) {
    final selected = _selectedLifecycleStatuses.contains(value);
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        if (selected && _selectedLifecycleStatuses.length == 1) return;
        setState(() {
          if (selected) {
            _selectedLifecycleStatuses.remove(value);
          } else {
            _selectedLifecycleStatuses.add(value);
          }
        });
        _load();
      },
      selectedColor: const Color(0xFFF5F3FF),
      checkmarkColor: const Color(0xFF7C3AED),
      side: BorderSide(
        color: selected ? const Color(0xFF6D28D9) : const Color(0xFF6B7280),
      ),
      padding: EdgeInsets.zero,
    );
  }
```

- [ ] **Step 2: Add the chip strip to the build tree**

In the `build` method, find the `// ── Spec filter strip ──` comment. Insert the lifecycle strip directly **before** it:

```dart
              // ── Lifecycle status filter strip ──
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  children: [
                    _lifecycleChip('closed', 'Κλειστές'),
                    const SizedBox(width: 6),
                    _lifecycleChip('completed', 'Ολοκληρωμένες'),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              // ── Spec filter strip ──
```

- [ ] **Step 3: Manual verification**

Run the Flutter app:
```bash
cd frontend && flutter run -d chrome
```

Open the Past Services screen for any department and verify:
1. Both chips are always visible; "Κλειστές" starts selected, "Ολοκληρωμένες" is not
2. The initial list shows only `closed` services
3. Tapping "Ολοκληρωμένες" selects it and re-fetches — list now includes both statuses
4. Tapping "Κλειστές" while both are selected deselects it — list shows only `completed`
5. Tapping the sole selected chip does nothing (can't deselect last chip)
6. The existing search, specialization, and date filters continue working alongside the lifecycle chips

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/screens/past_services_screen.dart
git commit -m "feat(ui): add lifecycle status filter chips to PastServicesScreen"
```
