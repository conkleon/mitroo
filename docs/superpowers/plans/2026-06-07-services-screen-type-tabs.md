# Services Screen Service-Type Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the collapsible specialization filter on the Services screen with a dynamic pill-style tab bar where each tab is a service type, hidden when fewer than two types exist.

**Architecture:** Single-file refactor of `frontend/lib/screens/services_screen.dart`. State tracking switches from specialization-id filter to service-type-id selection. The service-type tab bar is built manually (no TabController) so it handles dynamic tab counts without lifecycle complexity.

**Tech Stack:** Flutter, Provider, Dart

---

## File Map

| Action | File |
|---|---|
| Modify | `frontend/lib/screens/services_screen.dart` |
| Create | `frontend/test/screens/services_screen_test.dart` |

---

### Task 1: Remove old filter state and add service-type state

**Files:**
- Modify: `frontend/lib/screens/services_screen.dart`

- [ ] **Step 1: Remove old state fields**

In `_ServicesScreenState`, delete these two fields (around line 67–68):
```dart
// DELETE these two lines:
int? _selectedSpecId;
bool _filtersExpanded = false;
```

- [ ] **Step 2: Add new state field**

In their place, add:
```dart
int? _selectedServiceTypeId;
```

- [ ] **Step 3: Remove `_countForSpec` helper**

Delete the entire `_countForSpec` method (around lines 198–207):
```dart
// DELETE this entire method:
int _countForSpec(int specId) {
  return context.read<ServiceProvider>().services.where((s) {
    final st = s['serviceType'] as Map<String, dynamic>?;
    if (st == null) return false;
    final specs2 = st['specializations'] as List<dynamic>? ?? [];
    return specs2.any((row) => row['specializationId'] == specId ||
        row['specialization']?['id'] == specId);
  }).length;
}
```

- [ ] **Step 4: Replace `_filteredServices` getter with `_getFilteredServices` method**

Delete the old getter (around lines 186–196):
```dart
// DELETE:
List<dynamic> get _filteredServices {
  final all = context.read<ServiceProvider>().services;
  if (_selectedSpecId == null) return all;
  return all.where((s) {
    final st = s['serviceType'] as Map<String, dynamic>?;
    if (st == null) return false;
    final specs2 = st['specializations'] as List<dynamic>? ?? [];
    return specs2.any((row) => row['specializationId'] == _selectedSpecId ||
        row['specialization']?['id'] == _selectedSpecId);
  }).toList();
}
```

Add the new method in the same location:
```dart
List<dynamic> _getFilteredServices(int? typeId) {
  final all = context.read<ServiceProvider>().services;
  if (typeId == null) return all;
  return all.where((s) {
    final st = s['serviceType'] as Map<String, dynamic>?;
    if (st == null) return false;
    return (st['id'] as int) == typeId;
  }).toList();
}
```

- [ ] **Step 5: Verify the app still compiles (errors expected — `_filteredServices` and filter UI references are still present)**

```bash
cd frontend && flutter analyze --no-fatal-infos 2>&1 | head -40
```

Expected: errors about undefined `_filteredServices`, `_selectedSpecId`, `_filtersExpanded` — that's fine, we fix those in later tasks.

---

### Task 2: Compute service-type data in `build()` and replace filter UI

**Files:**
- Modify: `frontend/lib/screens/services_screen.dart`

- [ ] **Step 1: Replace the spec-filter derived data block in `build()`**

Find this block in `build()` (around lines 279–295 — the `specMap` / `dynamicSpecs` computation):
```dart
// DELETE this block:
final userSpecs = auth.specializations; // [{id, name, description}, ...]

// Build dynamic spec filters from services that actually exist
final allServices = svcProv.services;
final specMap = <int, String>{}; // id -> name
for (final svc in allServices) {
  final st = svc['serviceType'] as Map<String, dynamic>?;
  if (st == null) continue;
  final specs2 = st['specializations'] as List<dynamic>? ?? [];
  for (final row in specs2) {
    final spec = row['specialization'] as Map<String, dynamic>?;
    if (spec != null) {
      specMap[spec['id'] as int] = spec['name'] as String? ?? '';
    }
  }
}
// Sort by name for consistent order
final dynamicSpecs = specMap.entries.toList()
  ..sort((a, b) => a.value.compareTo(b.value));

final filtered = _filteredServices;
```

Replace with:
```dart
final allServices = svcProv.services;

// Build service-type tab data
final serviceTypeMap = <int, String>{};
final countPerType = <int, int>{};
for (final svc in allServices) {
  final st = svc['serviceType'] as Map<String, dynamic>?;
  if (st == null) continue;
  final id = st['id'] as int;
  serviceTypeMap.putIfAbsent(id, () => st['name'] as String? ?? '');
  countPerType[id] = (countPerType[id] ?? 0) + 1;
}
final serviceTypes = serviceTypeMap.entries.toList()
  ..sort((a, b) => a.value.compareTo(b.value));
final showTypeTabs = serviceTypes.length >= 2;
final effectiveTypeId = showTypeTabs
    ? (serviceTypes.any((e) => e.key == _selectedServiceTypeId)
        ? _selectedServiceTypeId
        : serviceTypes.first.key)
    : null;

final filtered = _getFilteredServices(effectiveTypeId);
```

- [ ] **Step 2: Replace the filter button row sliver**

Find the sliver that contains the `TabBar` + filter button row (around lines 432–529 — the `SliverToBoxAdapter` with the `Row` containing the `TabBar` + `GestureDetector` filter button):

```dart
// DELETE this entire SliverToBoxAdapter (the one with Row > TabBar + filter GestureDetector):
SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
    child: Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            // ... TabBar ...
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
          // ... filter button ...
        ),
      ],
    ),
  ),
),
```

Replace with two separate slivers — view toggle (clean, no filter button) and service-type tabs:
```dart
// View toggle: Λίστα / Ημερολόγιο
SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
    child: Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: cs.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF6B7280),
        labelStyle: tt.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: tt.labelMedium?.copyWith(fontWeight: FontWeight.w500),
        dividerHeight: 0,
        indicatorPadding: const EdgeInsets.all(3),
        tabs: const [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.list_alt_rounded, size: 16),
                SizedBox(width: 6),
                Text('Λίστα'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calendar_month_rounded, size: 16),
                SizedBox(width: 6),
                Text('Ημερολόγιο'),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
),

// Service-type tab bar (hidden when < 2 types)
if (showTypeTabs)
  SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(3),
          child: Row(
            children: serviceTypes.map((entry) {
              final typeId = entry.key;
              final typeName = entry.value;
              final count = countPerType[typeId] ?? 0;
              final selected = effectiveTypeId == typeId;
              return GestureDetector(
                onTap: () => setState(() => _selectedServiceTypeId = typeId),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? cs.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$typeName ($count)',
                    style: selected
                        ? tt.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          )
                        : tt.labelMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF6B7280),
                          ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    ),
  ),
```

- [ ] **Step 3: Delete the specialization bubbles sliver**

Find and delete the entire `SliverToBoxAdapter` that wraps the `AnimatedSize` / `_filtersExpanded` bubble row (around lines 532–582):
```dart
// DELETE this entire SliverToBoxAdapter:
SliverToBoxAdapter(
  child: AnimatedSize(
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeInOut,
    child: (_filtersExpanded && dynamicSpecs.isNotEmpty)
        ? Padding(
            // ... scrollable spec bubbles ...
          )
        : const SizedBox.shrink(),
  ),
),
```

- [ ] **Step 4: Verify app compiles cleanly**

```bash
cd frontend && flutter analyze --no-fatal-infos 2>&1 | head -40
```

Expected: no errors. If there are remaining references to `_selectedSpecId`, `_filtersExpanded`, `dynamicSpecs`, or `_filteredServices`, fix them now.

---

### Task 3: Write widget tests

**Files:**
- Create: `frontend/test/screens/services_screen_test.dart`

- [ ] **Step 1: Create the test file**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mitroo_frontend/screens/services_screen.dart';
import 'package:mitroo_frontend/providers/service_provider.dart';
import 'package:mitroo_frontend/providers/auth_provider.dart';

class _FakeServiceProvider extends ServiceProvider {
  final List<Map<String, dynamic>> _data;
  _FakeServiceProvider(this._data);

  @override
  List<dynamic> get services => _data;

  @override
  bool get loading => false;

  @override
  bool get isStale => false;

  @override
  Future<void> fetchMyServices() async {}
}

class _FakeAuthProvider extends AuthProvider {
  @override
  bool get isAuthenticated => true;

  @override
  bool get isAdmin => false;

  @override
  bool get isMissionAdmin => false;

  @override
  Map<String, dynamic>? get user => {'id': 1, 'forename': 'Test', 'surname': 'User'};

  @override
  String get displayName => 'Test User';

  @override
  List<dynamic> get specializations => [];
}

Widget _buildSubject(ServiceProvider svcProv) {
  SharedPreferences.setMockInitialValues({});
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const ServicesScreen()),
    GoRoute(path: '/profile', builder: (_, __) => const Scaffold()),
    GoRoute(path: '/victims/create', builder: (_, __) => const Scaffold()),
    GoRoute(path: '/admin/services/create', builder: (_, __) => const Scaffold()),
  ]);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ServiceProvider>.value(value: svcProv),
      ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuthProvider()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Map<String, dynamic> _makeService(int id, String name, int typeId, String typeName) => {
  'id': id,
  'name': name,
  'carrier': '',
  'startAt': '2026-06-10T09:00:00.000Z',
  'endAt': '2026-06-10T17:00:00.000Z',
  'location': '',
  'description': '',
  'defaultHours': 0,
  'defaultHoursVol': 0,
  'defaultHoursTraining': 0,
  'defaultHoursTrainers': 0,
  'defaultHoursTEP': 0,
  'userServices': [],
  '_count': {'userServices': 0},
  'serviceType': {'id': typeId, 'name': typeName},
};

void main() {
  group('ServicesScreen — service-type tabs', () {
    testWidgets('hides tab bar when all services share one type', (tester) async {
      final svcProv = _FakeServiceProvider([
        _makeService(1, 'Svc A', 10, 'Κάλυψη'),
        _makeService(2, 'Svc B', 10, 'Κάλυψη'),
      ]);
      await tester.pumpWidget(_buildSubject(svcProv));
      await tester.pumpAndSettle();

      // Only one type — tab bar should not be rendered
      expect(find.text('Κάλυψη (2)'), findsNothing);
    });

    testWidgets('hides tab bar when no service has a serviceType', (tester) async {
      final svcProv = _FakeServiceProvider([
        {
          'id': 1, 'name': 'Svc A', 'carrier': '', 'startAt': '2026-06-10T09:00:00.000Z',
          'endAt': '2026-06-10T17:00:00.000Z', 'location': '', 'description': '',
          'defaultHours': 0, 'defaultHoursVol': 0, 'defaultHoursTraining': 0,
          'defaultHoursTrainers': 0, 'defaultHoursTEP': 0, 'userServices': [],
          '_count': {'userServices': 0}, 'serviceType': null,
        },
      ]);
      await tester.pumpWidget(_buildSubject(svcProv));
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsNothing);
    });

    testWidgets('shows tab bar with counts when 2+ types exist', (tester) async {
      final svcProv = _FakeServiceProvider([
        _makeService(1, 'Svc A', 10, 'Κάλυψη'),
        _makeService(2, 'Svc B', 10, 'Κάλυψη'),
        _makeService(3, 'Svc C', 20, 'Εκπαίδευση'),
      ]);
      await tester.pumpWidget(_buildSubject(svcProv));
      await tester.pumpAndSettle();

      expect(find.text('Εκπαίδευση (1)'), findsOneWidget);
      expect(find.text('Κάλυψη (2)'), findsOneWidget);
    });

    testWidgets('tapping a tab switches the visible services', (tester) async {
      final svcProv = _FakeServiceProvider([
        _makeService(1, 'Coverage Service', 10, 'Κάλυψη'),
        _makeService(2, 'Training Service', 20, 'Εκπαίδευση'),
      ]);
      await tester.pumpWidget(_buildSubject(svcProv));
      await tester.pumpAndSettle();

      // Switch to list view first (tab index 0)
      await tester.tap(find.text('Λίστα'));
      await tester.pumpAndSettle();

      // Default selects first type alphabetically — tap the other type
      await tester.tap(find.text('Κάλυψη (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Coverage Service'), findsOneWidget);
      expect(find.text('Training Service'), findsNothing);
    });
  });
}
```

- [ ] **Step 2: Run tests**

```bash
cd frontend && flutter test test/screens/services_screen_test.dart --reporter expanded
```

Expected: all 4 tests pass. If any fail, fix the test setup (mock data shape) rather than the production code — the production code was already verified by `flutter analyze` in Task 2.

- [ ] **Step 3: Commit**

```bash
cd frontend && git add lib/screens/services_screen.dart test/screens/services_screen_test.dart
git commit -m "feat: replace specialization filter with service-type pill tabs on services screen"
```

---

## Verification Checklist

After all tasks complete, manually confirm in the running app:

- [ ] With 2+ service types: tab bar appears between the view toggle and the service list
- [ ] Tab label shows `TypeName (n)` with correct count
- [ ] Tapping a tab filters the list/calendar to only that type's services
- [ ] With 1 service type or no types: no tab bar visible, all services shown
- [ ] After pull-to-refresh: if selected type disappears, app doesn't crash and silently shows first available type
- [ ] Horizontal scroll works when many types exist
- [ ] Existing List/Calendar toggle still works normally
