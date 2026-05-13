# Admin Panel Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the admin panel to a department-centric card layout, give mission admins user and item management access, add an inline user-detail end-drawer, and surface assigned user on item cards.

**Architecture:** Three targeted file changes plus a router tweak. (1) Extract `UserDetailBody` from `UserDetailScreen` so it can render inside a drawer without a double-Scaffold. (2) Add `initialDepartmentId` to `ItemsScreen` and surface the assigned user on each item card. (3) Refactor `AdminPanelScreen` to dept-centric cards with a right-side end-drawer for user management.

**Tech Stack:** Flutter 3.x, Provider, GoRouter, `dart:convert`, `ApiClient` (internal HTTP wrapper)

---

## File Map

| File | Action |
|---|---|
| `frontend/lib/screens/user_detail_screen.dart` | Extract `UserDetailBody` widget; wrap in thin `UserDetailScreen` Scaffold |
| `frontend/lib/screens/items_screen.dart` | Add `initialDepartmentId` constructor param; surface assigned user on item cards |
| `frontend/lib/config/router.dart` | Pass `departmentId` query param to `ItemsScreen` |
| `frontend/lib/screens/admin_panel_screen.dart` | Full refactor: dept cards, remove dead code, add `_UserDrawer` end-drawer |

---

## Task 1: Extract UserDetailBody from UserDetailScreen

**Files:**
- Modify: `frontend/lib/screens/user_detail_screen.dart`

- [ ] **Step 1: Read the file**

Open `frontend/lib/screens/user_detail_screen.dart`. Note:
- The class name of the current `State` (likely `_UserDetailScreenState`)
- What `build` returns — it should be a `Scaffold`. Note the `appBar:` content and the `body:` content separately.

- [ ] **Step 2: Introduce UserDetailBody stateful widget**

Add this class *above* `UserDetailScreen` in the file:

```dart
/// User detail content without a Scaffold — safe to embed in a Drawer.
class UserDetailBody extends StatefulWidget {
  final int userId;
  const UserDetailBody({super.key, required this.userId});

  @override
  State<UserDetailBody> createState() => _UserDetailBodyState();
}
```

- [ ] **Step 3: Rename the existing state class and re-parent it**

Change:
```dart
class _UserDetailScreenState extends State<UserDetailScreen> {
```
To:
```dart
class _UserDetailBodyState extends State<UserDetailBody> {
```

All references to `widget.userId` inside this class remain correct — no other changes needed to field access.

- [ ] **Step 4: Strip Scaffold from _UserDetailBodyState.build**

The current `build` method returns `Scaffold(appBar: ..., body: <content>)`.
Change it to return only `<content>` (the `Scaffold`'s `body:` child — typically a `SafeArea` or `SingleChildScrollView`). Delete the `Scaffold(...)` wrapper and its `appBar:` from this method.

```dart
@override
Widget build(BuildContext context) {
  // Before: return Scaffold(appBar: AppBar(...), body: SafeArea(...));
  // After:
  return SafeArea(
    child: /* exactly what was previously body: */,
  );
}
```

- [ ] **Step 5: Make UserDetailScreen a thin Scaffold wrapper**

Replace the old `UserDetailScreen` state class with a `StatelessWidget`:

```dart
class UserDetailScreen extends StatelessWidget {
  final int userId;
  const UserDetailScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Στοιχεία Χρήστη'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: UserDetailBody(userId: userId),
    );
  }
}
```

**Note:** If the original `AppBar` displayed dynamic data loaded from the API (e.g. the user's name), keep `UserDetailScreen` as a `StatefulWidget` that watches the same data. Move only the non-AppBar `body:` content into `UserDetailBody`.

- [ ] **Step 6: Verify navigation still works**

```bash
cd frontend && flutter run -d chrome
```

Log in as a system admin. Navigate Admin → Users → tap any row. The user detail screen must load identically to before. No visual change expected.

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/screens/user_detail_screen.dart
git commit -m "refactor: extract UserDetailBody for inline drawer rendering"
```

---

## Task 2: Improve ItemsScreen — dept pre-filter + assigned user display

**Files:**
- Modify: `frontend/lib/screens/items_screen.dart`
- Modify: `frontend/lib/config/router.dart`

- [ ] **Step 1: Identify the assigned-user field name**

Add a temporary debug print in `_ItemsScreenState.initState` right after `fetchItems` resolves:

```dart
// Add inside the Future.microtask callback, after fetchItems:
WidgetsBinding.instance.addPostFrameCallback((_) {
  final items = context.read<ItemProvider>().items;
  if (items.isNotEmpty) {
    debugPrint('item fields: ${(items.first as Map).keys.toList()}');
    debugPrint('sample item: ${items.first}');
  }
});
```

Run the app, open the Items screen, check the debug console for the field that holds the assigned user object (e.g. `assignedUser`, `holder`, `currentUser`). Note the exact key name. **Remove the debug print after noting the field name.**

- [ ] **Step 2: Add initialDepartmentId constructor param**

Change:
```dart
class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key});
```
To:
```dart
class ItemsScreen extends StatefulWidget {
  final int? initialDepartmentId;
  const ItemsScreen({super.key, this.initialDepartmentId});
```

- [ ] **Step 3: Apply initialDepartmentId in initState**

In `_ItemsScreenState.initState`, inside the `Future.microtask` callback, before `_loadMyEquipment()`, add:

```dart
if (widget.initialDepartmentId != null) {
  _selectedDepartmentId = widget.initialDepartmentId;
}
```

- [ ] **Step 4: Surface assigned user on item cards**

Find the widget that renders each item in the list (a `Card`, `ListTile`, or custom row builder). Inside it, locate where the item name `Text` is rendered. Below it, add the assigned-user row using the field name from Step 1. Replace `'assignedUser'` below with the actual field key you found:

```dart
// After the item title Text widget:
Builder(builder: (context) {
  final assignedUser = item['assignedUser'] as Map<String, dynamic>?;
  if (assignedUser != null) {
    final name = '${assignedUser['forename'] ?? ''} ${assignedUser['surname'] ?? ''}'.trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 8,
            backgroundColor: const Color(0xFFE5E7EB),
            child: Text(initial,
                style: const TextStyle(fontSize: 9, color: Color(0xFF374151))),
          ),
          const SizedBox(width: 6),
          Text(name,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        ],
      ),
    );
  }
  return const Padding(
    padding: EdgeInsets.only(top: 4),
    child: Text('Unassigned',
        style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
  );
}),
```

- [ ] **Step 5: Update router to forward departmentId query param**

In `frontend/lib/config/router.dart`, find the `/items` route:

```dart
GoRoute(
  path: '/items',
  builder: (context, state) => const ItemsScreen(),
),
```

Replace with:

```dart
GoRoute(
  path: '/items',
  builder: (context, state) {
    final deptId =
        int.tryParse(state.uri.queryParameters['departmentId'] ?? '');
    return ItemsScreen(initialDepartmentId: deptId);
  },
),
```

- [ ] **Step 6: Verify**

```bash
cd frontend && flutter run -d chrome
```

1. Open Items screen — confirm each card shows either the assigned user name or "Unassigned".
2. Navigate to `http://localhost:PORT/items?departmentId=1` (use a real dept id from your DB) — confirm the department filter dropdown is pre-selected to that department.

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/screens/items_screen.dart frontend/lib/config/router.dart
git commit -m "feat: surface assigned user on item cards; support dept pre-filter param"
```

---

## Task 3: Refactor AdminPanelScreen — dept-centric cards + user drawer

**Files:**
- Modify: `frontend/lib/screens/admin_panel_screen.dart`

**Prerequisite:** Task 1 must be complete (`UserDetailBody` must exist and be importable).

- [ ] **Step 1: Add missing imports**

At the top of `admin_panel_screen.dart`, ensure these imports are present:

```dart
import 'dart:convert';
import '../services/api_client.dart';
import 'user_detail_screen.dart';
```

- [ ] **Step 2: Remove dead code**

Delete these three class definitions entirely — they are never instantiated in the current file:
- `_StatData`
- `_StatsRow`
- `_StatCard`

Also remove unused provider watches. In `initState` and `_refresh`, remove `ServiceProvider` and `VehicleProvider` fetches if no tile in the new layout needs their count data. Remove those provider imports too if unused.

Check: `dart:math` is still needed by `_ResponsiveTileGrid` (for `math.min`) — keep it.

- [ ] **Step 3: Add drawer state to _AdminPanelScreenState**

Add these four fields at the top of `_AdminPanelScreenState`:

```dart
final _scaffoldKey = GlobalKey<ScaffoldState>();
int? _drawerDeptId;
String _drawerDeptName = '';
int? _drawerUserId;
```

- [ ] **Step 4: Add _adminDepts and _rolesInDept helpers**

Add these two methods to `_AdminPanelScreenState`:

```dart
/// All depts this user admins — deduped union of mission + item depts.
List<Map<String, dynamic>> _adminDepts(
    AuthProvider auth, DepartmentProvider deptProv) {
  if (auth.isAdmin) return deptProv.departments.cast<Map<String, dynamic>>();
  final seen = <int>{};
  final result = <Map<String, dynamic>>[];
  for (final dept in [
    ...auth.missionAdminDepartments,
    ...auth.itemAdminDepartments,
  ]) {
    final id = dept['id'] as int;
    if (seen.add(id)) result.add(dept);
  }
  return result;
}

/// Admin roles this user holds in a specific department.
Set<String> _rolesInDept(AuthProvider auth, int deptId) {
  if (auth.isAdmin) return {'missionAdmin', 'itemAdmin'};
  final depts = auth.user?['departments'] as List<dynamic>? ?? [];
  return depts
      .where((d) => d['department']?['id'] == deptId)
      .map((d) => d['role'] as String)
      .toSet();
}
```

- [ ] **Step 5: Rewrite AdminPanelScreen.build**

Replace the entire `build` method body of `_AdminPanelScreenState` with:

```dart
@override
Widget build(BuildContext context) {
  final auth = context.watch<AuthProvider>();
  final deptProv = context.watch<DepartmentProvider>();

  final isSysAdmin = auth.isAdmin;
  final depts = _adminDepts(auth, deptProv);

  String subtitle;
  if (isSysAdmin) {
    subtitle = 'Διαχειριστής Συστήματος';
  } else {
    final roles = <String>[];
    if (auth.isMissionAdmin) roles.add('Διαχειριστής Αποστολών');
    if (auth.isItemAdmin) roles.add('Διαχειριστής Υλικού');
    subtitle = roles.join(' · ');
  }

  return Scaffold(
    key: _scaffoldKey,
    backgroundColor: const Color(0xFFF5F7FA),
    endDrawer: _UserDrawer(
      deptId: _drawerDeptId,
      deptName: _drawerDeptName,
      selectedUserId: _drawerUserId,
      onUserSelected: (id) => setState(() => _drawerUserId = id),
      onBack: () => setState(() => _drawerUserId = null),
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isCompact = width < _kCompactWidth;
          final isWide = width >= _kMediumWidth;
          final hPad = isCompact ? 16.0 : (isWide ? 40.0 : 24.0);
          final contentWidth = math.min(width, 1200.0);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                  hPad, isCompact ? 12 : 20, hPad, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HeaderBar(
                          subtitle: subtitle,
                          auth: auth,
                          isCompact: isCompact),
                      SizedBox(height: isCompact ? 16 : 28),

                      // ── System Management (sysAdmin only) ──
                      if (isSysAdmin) ...[
                        _SectionHeader(
                            icon: Icons.settings,
                            label: 'Διαχείρηση Συστήματος'),
                        const SizedBox(height: 12),
                        _ResponsiveTileGrid(
                          isWide: isWide,
                          isCompact: isCompact,
                          tiles: [
                            _AdminTileData(
                              icon: Icons.people,
                              iconColor: const Color(0xFFDC2626),
                              bgColor: const Color(0xFFFEE2E2),
                              title: 'Διαχείριση Χρηστών',
                              subtitle:
                                  'Δημιουργία, επεξεργασία & ανάθεση ρόλων',
                              onTap: () => context.push('/admin/users'),
                            ),
                            _AdminTileData(
                              icon: Icons.business,
                              iconColor: const Color(0xFF7C3AED),
                              bgColor: const Color(0xFFEDE9FE),
                              title: 'Διαχείριση Τμημάτων',
                              subtitle: 'Δημιουργία & ρύθμιση τμημάτων',
                              onTap: () =>
                                  context.push('/admin/departments'),
                            ),
                            _AdminTileData(
                              icon: Icons.school,
                              iconColor: const Color(0xFFD97706),
                              bgColor: const Color(0xFFFEF3C7),
                              title: 'Διαχείριση Ειδικεύσεων',
                              subtitle:
                                  'Δημιουργία & ανάθεση ειδικεύσεων',
                              onTap: () =>
                                  context.push('/admin/specializations'),
                            ),
                          ],
                        ),
                        SizedBox(height: isCompact ? 20 : 28),
                      ],

                      // ── Department cards ──
                      if (depts.isEmpty && !isSysAdmin)
                        const _EmptyCard(
                            message: 'Κανένα τμήμα ανατεθειμένο')
                      else if (depts.isNotEmpty) ...[
                        _SectionHeader(
                            icon: Icons.domain, label: 'Τμήματα'),
                        const SizedBox(height: 12),
                        ...depts.map((dept) {
                          final deptId = dept['id'] as int;
                          final roles = _rolesInDept(auth, deptId);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _DeptAdminCard(
                              dept: dept,
                              roles: roles,
                              isCompact: isCompact,
                              onUsersTap: roles.contains('missionAdmin')
                                  ? () {
                                      setState(() {
                                        _drawerDeptId = deptId;
                                        _drawerDeptName =
                                            dept['name'] as String? ??
                                                'Τμήμα';
                                        _drawerUserId = null;
                                      });
                                      _scaffoldKey.currentState
                                          ?.openEndDrawer();
                                    }
                                  : null,
                            ),
                          );
                        }),
                      ],

                      const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
```

- [ ] **Step 6: Add _DeptAdminCard, _RoleBadge, _CompactTileRow widgets**

Add these three classes at the bottom of `admin_panel_screen.dart`, before the closing of the file:

```dart
// ─── Dept admin card ──────────────────────────────────────

class _DeptAdminCard extends StatelessWidget {
  final Map<String, dynamic> dept;
  final Set<String> roles;
  final bool isCompact;
  final VoidCallback? onUsersTap;

  const _DeptAdminCard({
    required this.dept,
    required this.roles,
    required this.isCompact,
    this.onUsersTap,
  });

  @override
  Widget build(BuildContext context) {
    final deptName = dept['name'] as String? ?? 'Τμήμα';
    final deptId = dept['id'] as int;
    final isMission = roles.contains('missionAdmin');

    final tiles = <_AdminTileData>[
      if (isMission)
        _AdminTileData(
          icon: Icons.assignment_turned_in,
          iconColor: const Color(0xFF1D4ED8),
          bgColor: const Color(0xFFDBEAFE),
          title: 'Αιτήσεις Εκπαίδευσης',
          subtitle: 'Αποδοχή & ενεργοποίηση εκπαιδευόμενων',
          onTap: () => context.push('/admin/training-applications'),
        ),
      if (isMission)
        _AdminTileData(
          icon: Icons.miscellaneous_services,
          iconColor: const Color(0xFF059669),
          bgColor: const Color(0xFFD1FAE5),
          title: 'Υπηρεσίες',
          subtitle: 'Δημιουργία & διαχείριση υπηρεσιών',
          onTap: () => context.push(
              '/admin/services?departmentId=$deptId&departmentName=${Uri.encodeComponent(deptName)}'),
        ),
      if (isMission && onUsersTap != null)
        _AdminTileData(
          icon: Icons.people,
          iconColor: const Color(0xFFDC2626),
          bgColor: const Color(0xFFFEE2E2),
          title: 'Χρήστες',
          subtitle: 'Προβολή & επεξεργασία μελών τμήματος',
          onTap: onUsersTap!,
        ),
      _AdminTileData(
        icon: Icons.inventory_2,
        iconColor: const Color(0xFF7C3AED),
        bgColor: const Color(0xFFEDE9FE),
        title: 'Αντικείμενα',
        subtitle: 'Διαχείριση εξοπλισμού & κουτιών',
        onTap: () => context.go('/items?departmentId=$deptId'),
      ),
      _AdminTileData(
        icon: Icons.directions_car,
        iconColor: const Color(0xFFD97706),
        bgColor: const Color(0xFFFEF3C7),
        title: 'Οχήματα',
        subtitle: 'Διαχείριση στόλου & χιλιομέτρων',
        onTap: () => context.go('/vehicles'),
      ),
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    deptName,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (isMission)
                  _RoleBadge(
                      label: 'Αποστολών',
                      color: const Color(0xFF059669)),
                if (roles.contains('itemAdmin') && !isMission)
                  _RoleBadge(
                      label: 'Υλικού',
                      color: const Color(0xFF7C3AED)),
              ],
            ),
          ),
          const Divider(height: 1),
          ...tiles.map((t) =>
              _CompactTileRow(data: t, isCompact: isCompact)),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _RoleBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _CompactTileRow extends StatefulWidget {
  final _AdminTileData data;
  final bool isCompact;
  const _CompactTileRow({required this.data, required this.isCompact});

  @override
  State<_CompactTileRow> createState() => _CompactTileRowState();
}

class _CompactTileRowState extends State<_CompactTileRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final tt = Theme.of(context).textTheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: d.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: _hovering
              ? const Color(0xFFF9FAFB)
              : Colors.transparent,
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: widget.isCompact ? 10 : 12,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: d.bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    Icon(d.icon, color: d.iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.title,
                        style: tt.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(d.subtitle,
                        style: tt.bodySmall?.copyWith(
                            color: const Color(0xFF6B7280))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: Colors.grey.shade400, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Add _UserDrawer widget**

Add this class at the bottom of `admin_panel_screen.dart`:

```dart
// ─── User drawer ──────────────────────────────────────────

class _UserDrawer extends StatefulWidget {
  final int? deptId;
  final String deptName;
  final int? selectedUserId;
  final ValueChanged<int> onUserSelected;
  final VoidCallback onBack;

  const _UserDrawer({
    required this.deptId,
    required this.deptName,
    required this.selectedUserId,
    required this.onUserSelected,
    required this.onBack,
  });

  @override
  State<_UserDrawer> createState() => _UserDrawerState();
}

class _UserDrawerState extends State<_UserDrawer> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _users = [];
  bool _loading = false;
  String _search = '';
  int? _loadedDeptId;

  @override
  void initState() {
    super.initState();
    if (widget.deptId != null) _loadUsers();
  }

  @override
  void didUpdateWidget(covariant _UserDrawer old) {
    super.didUpdateWidget(old);
    if (widget.deptId != null && widget.deptId != _loadedDeptId) {
      _loadUsers();
    }
  }

  Future<void> _loadUsers() async {
    final deptId = widget.deptId;
    if (deptId == null) return;
    setState(() => _loading = true);
    try {
      final res = await _api.get('/users/stats');
      if (res.statusCode == 200 && mounted) {
        final all = (jsonDecode(res.body) as List)
            .cast<Map<String, dynamic>>();
        _users = all.where((u) {
          final depts = u['departments'] as List<dynamic>? ?? [];
          return depts
              .any((d) => d['department']?['id'] == deptId);
        }).toList();
        _loadedDeptId = deptId;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _users;
    final q = _search.toLowerCase();
    return _users.where((u) {
      final name =
          '${u['forename'] ?? ''} ${u['surname'] ?? ''}'.toLowerCase();
      final eame = (u['eame'] ?? '').toString().toLowerCase();
      return name.contains(q) || eame.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final inDetail = widget.selectedUserId != null;
    final screenWidth = MediaQuery.of(context).size.width;

    return Drawer(
      width: screenWidth < 600 ? screenWidth : 420,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(inDetail
                        ? Icons.arrow_back
                        : Icons.close),
                    onPressed: inDetail
                        ? widget.onBack
                        : () => Navigator.of(context).pop(),
                    tooltip: inDetail ? 'Πίσω' : 'Κλείσιμο',
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      inDetail
                          ? 'Στοιχεία Χρήστη'
                          : 'Χρήστες – ${widget.deptName}',
                      style: tt.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content: user detail or user list
            Expanded(
              child: inDetail
                  ? UserDetailBody(userId: widget.selectedUserId!)
                  : _buildList(tt, cs),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(TextTheme tt, ColorScheme cs) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Αναζήτηση...',
              prefixIcon: Icon(Icons.search, size: 20),
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                  ? Center(
                      child: Text('Κανένα αποτέλεσμα',
                          style: tt.bodyMedium
                              ?.copyWith(color: Colors.grey)),
                    )
                  : ListView.separated(
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 16),
                      itemBuilder: (ctx, i) {
                        final u = _filtered[i];
                        final name =
                            '${u['forename'] ?? ''} ${u['surname'] ?? ''}'
                                .trim();
                        final initial = name.isNotEmpty
                            ? name[0].toUpperCase()
                            : '?';
                        final depts = u['departments']
                                as List<dynamic>? ??
                            [];
                        final roleDept = depts.firstWhere(
                          (d) =>
                              d['department']?['id'] ==
                              widget.deptId,
                          orElse: () => <String, dynamic>{},
                        );
                        final role =
                            roleDept['role'] as String?;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: cs.primary,
                            child: Text(initial,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                          ),
                          title: Text(name,
                              style: tt.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500)),
                          subtitle: role != null
                              ? Text(_roleLabel(role),
                                  style: tt.bodySmall?.copyWith(
                                      color:
                                          const Color(0xFF6B7280)))
                              : null,
                          trailing: const Icon(
                              Icons.chevron_right,
                              size: 18),
                          onTap: () =>
                              widget.onUserSelected(u['id'] as int),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  String _roleLabel(String role) => switch (role) {
        'missionAdmin' => 'Διαχ. Αποστολών',
        'itemAdmin' => 'Διαχ. Υλικού',
        _ => 'Εθελοντής',
      };
}
```

- [ ] **Step 8: Run app and verify the full flow**

```bash
cd frontend && flutter run -d chrome
```

Check each scenario:

1. **System admin:** Sees "Διαχείριση Συστήματος" tiles + dept cards for all depts. Tiles navigate correctly.
2. **Mission admin:** Sees only dept cards. Each card has Training, Services, Users, Items, Vehicles tiles. Tapping Users opens the right-side drawer with the user list filtered to that dept. Tapping a user shows their detail inline in the drawer. Back arrow returns to the list. Close button closes the drawer.
3. **Item admin only:** Sees only dept cards with Items + Vehicles tiles. No Users tile.
4. **Items tile:** Navigates to `/items?departmentId=X` with dept pre-selected.

- [ ] **Step 9: Commit**

```bash
git add frontend/lib/screens/admin_panel_screen.dart
git commit -m "feat: dept-centric admin panel with user drawer and role-correct tiles"
```
