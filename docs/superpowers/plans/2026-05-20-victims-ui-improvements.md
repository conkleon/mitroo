# Victims UI Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the DataTable in VictimsScreen with a colour-coded card list, and fix the Delete button being cut off on narrow screens in VictimDetailScreen.

**Architecture:** Two self-contained edits in two existing screen files. VictimsScreen replaces its `DataTable`+horizontal-scroll block with a `ListView.builder` of `Card` widgets that use a 4 px coloured left border to signal status. VictimDetailScreen replaces the `Row` in `bottomNavigationBar` with `Wrap` so buttons reflow instead of overflowing.

**Tech Stack:** Flutter (Dart), `provider` package for state, `go_router` for navigation, `flutter_test` for widget tests, `shared_preferences` (mock) for provider setup.

---

## File Map

| File | Action |
|------|--------|
| `frontend/lib/screens/victims_screen.dart` | Modify — replace `DataTable` block (lines 252-350) with `ListView.builder` of coloured-border cards |
| `frontend/lib/screens/victim_detail_screen.dart` | Modify — replace `Row` in `bottomNavigationBar` (line ~459) with `Wrap(spacing:8, runSpacing:8)`; remove explicit `SizedBox(width:8)` spacers |
| `frontend/test/screens/victim_detail_screen_test.dart` | Create — widget tests for Wrap layout |
| `frontend/test/screens/victims_screen_test.dart` | Create — widget tests for card list |

---

## Task 1: Fix bottom bar overflow in VictimDetailScreen

**Files:**
- Modify: `frontend/lib/screens/victim_detail_screen.dart:455-487`
- Create: `frontend/test/screens/victim_detail_screen_test.dart`

- [ ] **Step 1: Create the test directory and failing test**

Create `frontend/test/screens/victim_detail_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mitroo_frontend/screens/victim_detail_screen.dart';
import 'package:mitroo_frontend/providers/victim_provider.dart';
import 'package:mitroo_frontend/providers/auth_provider.dart';

// Fake VictimProvider — overrides only what the detail screen reads.
class _FakeVictimProvider extends VictimProvider {
  final Map<String, dynamic> _victim;

  _FakeVictimProvider(this._victim);

  @override
  Map<String, dynamic>? get selected => _victim;

  @override
  bool get loading => false;

  @override
  Future<void> fetchVictim(int id) async {}
}

// Fake AuthProvider — admin user so all three buttons are shown.
class _FakeAuthProvider extends AuthProvider {
  @override
  Map<String, dynamic>? get user => {'id': 1, 'isAdmin': true};

  @override
  bool get isAdmin => true;

  @override
  bool get isMissionAdmin => true;
}

Widget _buildSubject({
  required VictimProvider victimProvider,
  required AuthProvider authProvider,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<VictimProvider>.value(value: victimProvider),
      ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
    ],
    child: MaterialApp(
      home: VictimDetailScreen(victimId: 1),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows Edit, Finalize and Delete buttons for admin', (tester) async {
    final victim = {
      'id': 1,
      'name': 'Νικολάου Μαρία',
      'isFinalized': false,
      'createdById': 99,
      'vitalSigns': <dynamic>[],
      'treatments': <dynamic>[],
    };

    await tester.pumpWidget(_buildSubject(
      victimProvider: _FakeVictimProvider(victim),
      authProvider: _FakeAuthProvider(),
    ));
    await tester.pump();

    expect(find.text('Επεξεργασία'), findsOneWidget);
    expect(find.text('Οριστικοποίηση'), findsOneWidget);
    expect(find.text('Διαγραφή'), findsOneWidget);
  });

  testWidgets('bottom bar uses Wrap not Row', (tester) async {
    final victim = {
      'id': 1,
      'name': 'Νικολάου Μαρία',
      'isFinalized': false,
      'createdById': 99,
      'vitalSigns': <dynamic>[],
      'treatments': <dynamic>[],
    };

    await tester.pumpWidget(_buildSubject(
      victimProvider: _FakeVictimProvider(victim),
      authProvider: _FakeAuthProvider(),
    ));
    await tester.pump();

    // Wrap replaces Row in the bottom bar — verify Wrap is present
    expect(find.byType(Wrap), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd frontend && flutter test test/screens/victim_detail_screen_test.dart -v
```

Expected: both tests FAIL (screen uses `Row`, `Wrap` not found; and potentially layout overflow error).

- [ ] **Step 3: Replace Row with Wrap in the bottom bar**

In `frontend/lib/screens/victim_detail_screen.dart`, find the `bottomNavigationBar` block (around line 455). Replace the entire `Row(children: [...])` and its contents with `Wrap(spacing: 8, runSpacing: 8, children: [...])`, removing the two `SizedBox(width: 8)` spacers (spacing is now handled by `Wrap.spacing`).

**Before** (lines ~457–486):
```dart
child: Row(
  children: [
    if (canEdit)
      FilledButton.icon(
        onPressed: () => context.push('/victims/create'),
        icon: const Icon(Icons.edit, size: 18),
        label: const Text('Επεξεργασία'),
      ),
    if (canEdit) const SizedBox(width: 8),
    if (canFinalize)
      FilledButton.icon(
        onPressed: _showFinalizeDialog,
        icon: const Icon(Icons.lock_outline, size: 18),
        label: const Text('Οριστικοποίηση'),
      ),
    if (canDelete) ...[
      const SizedBox(width: 8),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
        onPressed: _showDeleteDialog,
        icon: const Icon(Icons.delete_outline, size: 18),
        label: const Text('Διαγραφή'),
      ),
    ],
  ],
),
```

**After:**
```dart
child: Wrap(
  spacing: 8,
  runSpacing: 8,
  children: [
    if (canEdit)
      FilledButton.icon(
        onPressed: () => context.push('/victims/create'),
        icon: const Icon(Icons.edit, size: 18),
        label: const Text('Επεξεργασία'),
      ),
    if (canFinalize)
      FilledButton.icon(
        onPressed: _showFinalizeDialog,
        icon: const Icon(Icons.lock_outline, size: 18),
        label: const Text('Οριστικοποίηση'),
      ),
    if (canDelete)
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
        onPressed: _showDeleteDialog,
        icon: const Icon(Icons.delete_outline, size: 18),
        label: const Text('Διαγραφή'),
      ),
  ],
),
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd frontend && flutter test test/screens/victim_detail_screen_test.dart -v
```

Expected: both tests PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/victim_detail_screen.dart frontend/test/screens/victim_detail_screen_test.dart
git commit -m "fix(victim-detail): replace Row with Wrap in bottom bar so Delete is always visible"
```

---

## Task 2: Replace DataTable with colour-coded card list in VictimsScreen

**Files:**
- Modify: `frontend/lib/screens/victims_screen.dart:252-350`
- Create: `frontend/test/screens/victims_screen_test.dart`

- [ ] **Step 1: Create the failing test**

Create `frontend/test/screens/victims_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mitroo_frontend/screens/victims_screen.dart';
import 'package:mitroo_frontend/providers/victim_provider.dart';

class _FakeVictimProvider extends VictimProvider {
  final List<Map<String, dynamic>> _victims;
  final List<Map<String, dynamic>> _pending;

  _FakeVictimProvider({
    List<Map<String, dynamic>> victims = const [],
    List<Map<String, dynamic>> pending = const [],
  })  : _victims = victims,
        _pending = pending;

  @override
  List<Map<String, dynamic>> get victims => _victims;

  @override
  List<Map<String, dynamic>> get pendingVictims => _pending;

  @override
  bool get loading => false;

  @override
  int get totalPages => 1;

  @override
  int get currentPage => 1;

  @override
  Future<void> fetchVictims({
    int? serviceId,
    String? search,
    String? dateFrom,
    String? dateTo,
    String? status,
    int page = 1,
    int limit = 20,
  }) async {}
}

Widget _buildSubject(VictimProvider provider) {
  return ChangeNotifierProvider<VictimProvider>.value(
    value: provider,
    child: const MaterialApp(home: VictimsScreen()),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders Card widgets instead of DataTable', (tester) async {
    final provider = _FakeVictimProvider(
      victims: [
        {
          'id': 1,
          'name': 'Νικολάου Μαρία',
          'createdAt': '2026-05-20T10:00:00.000Z',
          'chiefComplaint': 'Δύσπνοια',
          'isFinalized': false,
        },
      ],
    );

    await tester.pumpWidget(_buildSubject(provider));
    await tester.pump();

    expect(find.byType(DataTable), findsNothing);
    expect(find.byType(Card), findsWidgets);
    expect(find.text('Νικολάου Μαρία'), findsOneWidget);
  });

  testWidgets('shows pending icon for unsynced victims', (tester) async {
    final provider = _FakeVictimProvider(
      pending: [
        {
          'id': -1,
          'name': 'Παπαδόπουλος Γεώργιος',
          '_isPending': true,
        },
      ],
    );

    await tester.pumpWidget(_buildSubject(provider));
    await tester.pump();

    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.text('Παπαδόπουλος Γεώργιος'), findsOneWidget);
  });

  testWidgets('shows empty state when no victims', (tester) async {
    final provider = _FakeVictimProvider();

    await tester.pumpWidget(_buildSubject(provider));
    await tester.pump();

    expect(find.text('Δεν υπάρχουν περιστατικά'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd frontend && flutter test test/screens/victims_screen_test.dart -v
```

Expected: first test FAILS (DataTable still present, no coloured-border Cards); others may pass or fail.

- [ ] **Step 3: Replace the DataTable block with ListView.builder**

In `frontend/lib/screens/victims_screen.dart`, find the `Expanded(child: provider.loading ? ... : allRows.isEmpty ? ... : SingleChildScrollView(...DataTable...))` block (lines ~239–351).

Replace only the `SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(...DataTable...))` branch with the card list below. Keep the loading spinner and empty-state branches unchanged.

**Remove** (the horizontal-scroll DataTable branch):
```dart
: SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: MediaQuery.of(context).size.width,
      ),
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(
          const Color(0xFFF9FAFB),
        ),
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return cs.primary.withAlpha(15);
          }
          return null;
        }),
        columnSpacing: 24,
        horizontalMargin: 16,
        columns: [
          DataColumn(
            label: Text('Όνομα',
                style: tt.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF374151))),
          ),
          DataColumn(
            label: Text('Ημ/νία Καταγραφής',
                style: tt.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF374151))),
          ),
          DataColumn(
            label: Text('Κύριο Σύμπτωμα',
                style: tt.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF374151))),
          ),
        ],
        rows: allRows.asMap().entries.map((entry) {
          final i = entry.key;
          final v = entry.value;
          final name = v['name'] as String? ?? 'Άγνωστο';
          final chiefComplaint = v['chiefComplaint'] as String? ?? '';
          final isPending = v['_isPending'] == true;
          return DataRow(
            color: WidgetStateProperty.all(
              isPending
                  ? const Color(0xFFFEFCE8)
                  : i.isEven
                      ? const Color(0xFFF9FAFB)
                      : null,
            ),
            onSelectChanged: isPending
                ? null
                : (_) => context.push('/victims/${v['id']}'),
            cells: [
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isPending) ...[
                      const Icon(Icons.cloud_off_outlined, size: 16, color: Color(0xFFD97706)),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(name,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isPending ? const Color(0xFF92400E) : const Color(0xFF1F2937)),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
              DataCell(
                isPending
                    ? const Text('Εκκρεμεί',
                        style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.w500, fontSize: 13))
                    : Text(_formatDate(v['createdAt'] as String?),
                        style: const TextStyle(color: Color(0xFF6B7280))),
              ),
              DataCell(
                Text(
                  chiefComplaint.isNotEmpty ? chiefComplaint : '—',
                  style: TextStyle(
                    color: chiefComplaint.isNotEmpty
                        ? const Color(0xFF374151)
                        : const Color(0xFF9CA3AF),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    ),
  ),
```

**Replace with:**
```dart
: ListView.builder(
    itemCount: allRows.length,
    itemBuilder: (context, i) {
      final v = allRows[i];
      final name = v['name'] as String? ?? 'Άγνωστο';
      final chiefComplaint = v['chiefComplaint'] as String? ?? '';
      final isPending = v['_isPending'] == true;
      final isFinalized = v['isFinalized'] == true;

      final borderColor = isPending
          ? const Color(0xFFD97706)
          : isFinalized
              ? const Color(0xFF9CA3AF)
              : const Color(0xFF2563EB);

      return Card(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isPending ? null : () => context.push('/victims/${v['id']}'),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: borderColor),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (isPending) ...[
                            const Icon(Icons.cloud_off_outlined,
                                size: 14, color: Color(0xFFD97706)),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: isPending
                                    ? const Color(0xFF92400E)
                                    : const Color(0xFF1F2937),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isPending
                            ? 'Εκκρεμεί'
                            : [
                                _formatDate(v['createdAt'] as String?),
                                if (chiefComplaint.isNotEmpty) chiefComplaint,
                              ].join(' · '),
                        style: TextStyle(
                          fontSize: 12,
                          color: isPending
                              ? const Color(0xFFD97706)
                              : const Color(0xFF6B7280),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.chevron_right,
                    size: 18, color: Color(0xFF9CA3AF)),
              ),
            ],
          ),
        ),
      );
    },
  ),
```

Also remove the unused `cs` and `tt` variables from the `build` method — they were only referenced in the DataTable headers. Delete these two lines near the top of `build`:

```dart
final cs = Theme.of(context).colorScheme;
final tt = Theme.of(context).textTheme;
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd frontend && flutter test test/screens/victims_screen_test.dart -v
```

Expected: all three tests PASS.

- [ ] **Step 5: Run all tests to check for regressions**

```bash
cd frontend && flutter test -v
```

Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/screens/victims_screen.dart frontend/test/screens/victims_screen_test.dart
git commit -m "feat(victims): replace DataTable with colour-coded card list"
```
