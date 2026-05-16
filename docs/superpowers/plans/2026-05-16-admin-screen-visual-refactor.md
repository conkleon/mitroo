# Admin Screen Visual Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace tall icon-box cards in the manage departments and manage specializations screens with compact left-accent strip cards, and refactor the past services screen to use the same compact style with a bottom sheet showing service info + enrolled members + admin edit button.

**Architecture:** Three isolated file edits — no new files, no backend changes, no routing changes. Each card widget is replaced in-place. The past services screen gains two new helper methods (`_showPastServiceSheet`, `_sheetInfoRow`, `_sheetHourChip`) and two new imports.

**Tech Stack:** Flutter/Dart, Provider, GoRouter, google_fonts, intl

---

## File Map

| File | Change |
|------|--------|
| `frontend/lib/screens/manage_departments_screen.dart` | Replace `_DeptCard.build` body; adjust grid `childAspectRatio` 3.0 → 3.5 |
| `frontend/lib/screens/manage_specializations_screen.dart` | Replace `_SpecCard.build` body; adjust grid `childAspectRatio` 3.2 → 3.8 |
| `frontend/lib/screens/past_services_screen.dart` | Replace `_buildCard`; add `_PastServiceCard`; add `_showPastServiceSheet` + helpers; add `AuthProvider` + `provider` imports |

---

## Task 1: Refactor `_DeptCard` in `manage_departments_screen.dart`

**Files:**
- Modify: `frontend/lib/screens/manage_departments_screen.dart`

- [ ] **Step 1: Verify the current `_DeptCard` build method starts at line 310**

  Open `frontend/lib/screens/manage_departments_screen.dart`. Confirm `_DeptCard` is around line 304 and its `build` method padding is `const EdgeInsets.symmetric(horizontal: 16, vertical: 14)`.

- [ ] **Step 2: Replace the entire `_DeptCard.build` method body**

  Replace the `build` method of `_DeptCard` (the `return Card(...)` block, lines ~317–381) with:

  ```dart
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final counts = dept['_count'] as Map<String, dynamic>? ?? {};
    final memberCount = counts['userDepartments'] ?? 0;
    final serviceCount = counts['services'] ?? 0;
    final vehicleCount = counts['vehicles'] ?? 0;
    final location = (dept['location'] ?? '').toString();
    final description = (dept['description'] ?? '').toString();
    final subtitle = [location, description]
        .where((s) => s.isNotEmpty)
        .join(' • ');

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 4,
                decoration: const BoxDecoration(
                  color: Color(0xFF7C3AED),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(dept['name'] ?? '',
                          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: GoogleFonts.inter(
                                fontSize: 12, color: const Color(0xFF6B7280)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 10,
                        children: [
                          _CountBadge(
                              icon: Icons.people,
                              count: memberCount,
                              color: const Color(0xFFDC2626)),
                          _CountBadge(
                              icon: Icons.miscellaneous_services,
                              count: serviceCount,
                              color: const Color(0xFF059669)),
                          _CountBadge(
                              icon: Icons.directions_car,
                              count: vehicleCount,
                              color: const Color(0xFFD97706)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.chevron_right, color: Color(0xFF9CA3AF), size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
  ```

- [ ] **Step 3: Adjust grid `childAspectRatio` from `3.0` to `3.5`**

  In `_buildGrid`, find:
  ```dart
  childAspectRatio: 3.0,
  ```
  Replace with:
  ```dart
  childAspectRatio: 3.5,
  ```

- [ ] **Step 4: Hot-reload and verify visually**

  Run `flutter run -d chrome` (or hot-reload if already running).
  Navigate to Admin → Departments.
  Verify: cards are ~48px tall, no icon square, purple left strip, name bold on line 1, location/description gray on line 2, count badges on line 3, chevron at right.

- [ ] **Step 5: Commit**

  ```bash
  git add frontend/lib/screens/manage_departments_screen.dart
  git commit -m "refactor: condense _DeptCard to left-accent strip layout"
  ```

---

## Task 2: Refactor `_SpecCard` in `manage_specializations_screen.dart`

**Files:**
- Modify: `frontend/lib/screens/manage_specializations_screen.dart`

- [ ] **Step 1: Verify the current `_SpecCard` structure**

  Open `frontend/lib/screens/manage_specializations_screen.dart`. Confirm `_SpecCard` starts around line 452 and has a 48×48 gradient Container icon.

- [ ] **Step 2: Replace the entire `_SpecCard.build` method body**

  Replace the `build` method of `_SpecCard` (the `return Card(...)` block) with:

  ```dart
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final counts = (spec['_count'] as Map<String, dynamic>?) ?? {};
    final userCount = counts['users'] ?? 0;
    final childCount = counts['children'] ?? 0;
    final root = spec['root'] as Map<String, dynamic>?;
    final yearlyHours = spec['yearlyHours'] ?? 0;
    final yearlyHoursTraining = spec['yearlyHoursTraining'] ?? 0;
    final hours = spec['hoursTraining'] ?? 0;
    final hoursTep = spec['hoursTEP'] ?? 0;
    final eamePrefix = (spec['eamePrefix'] ?? '').toString();
    final isRoot = spec['rootId'] == null;
    final description = (spec['description'] ?? '').toString();
    final subtitle = isRoot
        ? description
        : (root?['name'] ?? '').toString();
    final accentColor =
        isRoot ? const Color(0xFF7C3AED) : const Color(0xFFDC2626);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(spec['name'] ?? '',
                          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: GoogleFonts.inter(
                                fontSize: 12, color: const Color(0xFF6B7280)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 4),
                      Wrap(spacing: 10, children: [
                        _MiniLabel(
                            icon: Icons.people,
                            text: '$userCount',
                            color: const Color(0xFFDC2626)),
                        if (isRoot && childCount > 0)
                          _MiniLabel(
                              icon: Icons.subdirectory_arrow_right,
                              text: '$childCount',
                              color: const Color(0xFF7C3AED)),
                        if (hours > 0)
                          _MiniLabel(
                              icon: Icons.schedule,
                              text: '${hours}h',
                              color: const Color(0xFFD97706)),
                        if (yearlyHours > 0)
                          _MiniLabel(
                              icon: Icons.calendar_month,
                              text: 'Ετήσιες ${yearlyHours}h',
                              color: const Color(0xFF2563EB)),
                        if (yearlyHoursTraining > 0)
                          _MiniLabel(
                              icon: Icons.school_outlined,
                              text: 'Εκπ. ${yearlyHoursTraining}h',
                              color: const Color(0xFF0F766E)),
                        if (hoursTep > 0)
                          _MiniLabel(
                              icon: Icons.timer,
                              text: 'TEP ${hoursTep}h',
                              color: const Color(0xFF0EA5E9)),
                        if (eamePrefix.isNotEmpty)
                          _MiniLabel(
                              icon: Icons.badge_outlined,
                              text: 'EAME $eamePrefix',
                              color: const Color(0xFF111827)),
                      ]),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.chevron_right, color: Color(0xFF9CA3AF), size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
  ```

- [ ] **Step 3: Adjust grid `childAspectRatio` from `3.2` to `3.8`**

  In `_buildGrid`, find:
  ```dart
  childAspectRatio: 3.2,
  ```
  Replace with:
  ```dart
  childAspectRatio: 3.8,
  ```

- [ ] **Step 4: Hot-reload and verify visually**

  Navigate to Admin → Specializations.
  Verify: root specs have purple left strip, sub-specs have red left strip, parent name shown as subtitle for sub-specs, description shown for root specs, badges intact, no icon square.

- [ ] **Step 5: Commit**

  ```bash
  git add frontend/lib/screens/manage_specializations_screen.dart
  git commit -m "refactor: condense _SpecCard to left-accent strip layout"
  ```

---

## Task 3: Add compact `_PastServiceCard` to `past_services_screen.dart`

**Files:**
- Modify: `frontend/lib/screens/past_services_screen.dart`

- [ ] **Step 1: Add `_PastServiceCard` widget class at the bottom of the file**

  After the closing `}` of `_StatPill` (the last class in the file, around line 550), add:

  ```dart
  class _PastServiceCard extends StatelessWidget {
    final Map<String, dynamic> svc;
    final VoidCallback onTap;
    const _PastServiceCard({required this.svc, required this.onTap});

    String _fmt(String? iso) {
      if (iso == null) return '—';
      final dt = DateTime.tryParse(iso);
      if (dt == null) return '—';
      final l = dt.toLocal();
      return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${(l.year % 100).toString().padLeft(2, '0')} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
    }

    @override
    Widget build(BuildContext context) {
      final tt = Theme.of(context).textTheme;
      final name = (svc['name'] ?? '').toString();
      final location = (svc['location'] ?? '').toString();
      final userServices = svc['userServices'] as List<dynamic>? ?? [];
      final enrolledCount = (svc['_count']?['userServices'] ?? 0) as int;
      final acceptedCount =
          userServices.where((us) => us['status'] == 'accepted').length;

      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          elevation: 0,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      decoration: const BoxDecoration(
                        color: Color(0xFF059669),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(12),
                          bottomLeft: Radius.circular(12),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(name,
                                style: tt.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Row(children: [
                              const Icon(Icons.schedule,
                                  size: 12, color: Color(0xFF6B7280)),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  '${_fmt(svc['startAt'] as String?)} → ${_fmt(svc['endAt'] as String?)}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Color(0xFF6B7280)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ]),
                            if (location.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Row(children: [
                                const Icon(Icons.location_on_outlined,
                                    size: 12, color: Color(0xFF6B7280)),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(location,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF6B7280)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ]),
                            ],
                            const SizedBox(height: 4),
                            Row(children: [
                              _StatPill(Icons.people, '$enrolledCount εγγ.',
                                  const Color(0xFF6B7280)),
                              if (acceptedCount > 0) ...[
                                const SizedBox(width: 6),
                                _StatPill(
                                    Icons.check_circle_outline,
                                    '$acceptedCount εγκ.',
                                    const Color(0xFF059669)),
                              ],
                            ]),
                          ],
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.chevron_right,
                          color: Color(0xFF9CA3AF), size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
  }
  ```

- [ ] **Step 2: Replace `_buildList` and `_buildGrid` to use `_PastServiceCard`**

  Find `_buildList` (around line 366):
  ```dart
  Widget _buildList(List<dynamic> services) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: services.length,
      itemBuilder: (ctx, i) => _buildCard(services[i]),
    );
  }
  ```
  Replace with:
  ```dart
  Widget _buildList(List<dynamic> services) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: services.length,
      itemBuilder: (ctx, i) => _PastServiceCard(
        svc: services[i] as Map<String, dynamic>,
        onTap: () => _showPastServiceSheet(services[i] as Map<String, dynamic>),
      ),
    );
  }
  ```

  Find `_buildGrid` (around line 374):
  ```dart
  Widget _buildGrid(List<dynamic> services) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2.0,
      ),
      itemCount: services.length,
      itemBuilder: (ctx, i) => _buildCard(services[i]),
    );
  }
  ```
  Replace with:
  ```dart
  Widget _buildGrid(List<dynamic> services) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 12,
        childAspectRatio: 2.8,
      ),
      itemCount: services.length,
      itemBuilder: (ctx, i) => _PastServiceCard(
        svc: services[i] as Map<String, dynamic>,
        onTap: () => _showPastServiceSheet(services[i] as Map<String, dynamic>),
      ),
    );
  }
  ```

- [ ] **Step 3: Delete the old `_buildCard` method and its helper classes**

  Delete the entire `_buildCard` method (lines ~388–505).
  Delete the `_PastInfoChip` class (it is no longer used).
  Keep `_StatPill` — it is used by `_PastServiceCard`.

- [ ] **Step 4: Add a stub `_showPastServiceSheet` so the file compiles**

  Temporarily add this method to `_PastServicesScreenState` (will be replaced in Task 4):

  ```dart
  void _showPastServiceSheet(Map<String, dynamic> svc) {}
  ```

- [ ] **Step 5: Verify the file compiles**

  ```bash
  cd frontend && flutter analyze lib/screens/past_services_screen.dart
  ```
  Expected: no errors. Fix any unused-import warnings if present.

- [ ] **Step 6: Hot-reload and verify visually**

  Navigate to a department's past services.
  Verify: compact green-strip cards, name + date range + location + enrollment pills, no old tall cards.

- [ ] **Step 7: Commit**

  ```bash
  git add frontend/lib/screens/past_services_screen.dart
  git commit -m "refactor: replace past service cards with compact left-accent strip"
  ```

---

## Task 4: Add bottom sheet with applications to `past_services_screen.dart`

**Files:**
- Modify: `frontend/lib/screens/past_services_screen.dart`

- [ ] **Step 1: Add `provider` and `AuthProvider` imports**

  At the top of `past_services_screen.dart`, after the existing imports, add:

  ```dart
  import 'package:provider/provider.dart';
  import '../providers/auth_provider.dart';
  ```

- [ ] **Step 2: Replace the stub `_showPastServiceSheet` with the full implementation**

  Replace `void _showPastServiceSheet(Map<String, dynamic> svc) {}` with:

  ```dart
  void _showPastServiceSheet(Map<String, dynamic> svc) {
    final auth = context.read<AuthProvider>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final isAdmin = auth.isAdmin || auth.isMissionAdmin;

    final name = (svc['name'] ?? '').toString();
    final location = (svc['location'] ?? '').toString();
    final carrier = (svc['carrier'] ?? '').toString();
    final description = (svc['description'] ?? '').toString();
    final userServices = svc['userServices'] as List<dynamic>? ?? [];
    final enrolledCount = userServices.length;

    final responsible = svc['responsibleUser'] as Map<String, dynamic>?;
    final rName = responsible != null
        ? '${responsible['forename'] ?? ''} ${responsible['surname'] ?? ''}'.trim()
        : '';

    final defaultHours = svc['defaultHours'] ?? 0;
    final defaultHoursVol = svc['defaultHoursVol'] ?? 0;
    final defaultHoursTraining = svc['defaultHoursTraining'] ?? 0;
    final defaultHoursTrainers = svc['defaultHoursTrainers'] ?? 0;
    final defaultHoursTEP = svc['defaultHoursTEP'] ?? 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Title + completed badge
              Row(children: [
                Expanded(
                  child: Text(name,
                      style: tt.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1F2937))),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Ολοκληρωμένη',
                      style: TextStyle(
                          color: Color(0xFF059669),
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 16),
              // Info rows
              _sheetInfoRow(Icons.schedule, 'Ώρα',
                  '${_fmtDate(svc['startAt'] as String?)} → ${_fmtDate(svc['endAt'] as String?)}',
                  cs),
              if (location.isNotEmpty)
                _sheetInfoRow(
                    Icons.location_on_outlined, 'Τοποθεσία', location, cs),
              if (carrier.isNotEmpty)
                _sheetInfoRow(Icons.groups, 'Φορέας', carrier, cs),
              if (rName.isNotEmpty)
                _sheetInfoRow(Icons.star_rounded, 'Υπεύθυνος', rName, cs),
              _sheetInfoRow(Icons.people_outline, 'Αιτήσεις',
                  '$enrolledCount μέλη', cs),
              // Description
              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Επιπλέον πληροφορίες',
                    style: tt.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF374151))),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Text(description,
                      style: tt.bodySmall
                          ?.copyWith(color: const Color(0xFF4B5563))),
                ),
              ],
              // Hours
              const SizedBox(height: 16),
              Text('Ώρες υπηρεσίας',
                  style: tt.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF374151))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (defaultHours > 0)
                    _sheetHourChip('Κάλυψη', defaultHours, cs.primary),
                  if (defaultHoursVol > 0)
                    _sheetHourChip('Εθελοντικές', defaultHoursVol,
                        const Color(0xFF7C3AED)),
                  if (defaultHoursTraining > 0)
                    _sheetHourChip('Επανεκπ.', defaultHoursTraining,
                        const Color(0xFFD97706)),
                  if (defaultHoursTrainers > 0)
                    _sheetHourChip('Εκπαιδευτών', defaultHoursTrainers,
                        const Color(0xFF059669)),
                  if (defaultHoursTEP > 0)
                    _sheetHourChip(
                        'ΤΕΠ', defaultHoursTEP, const Color(0xFF0891B2)),
                  if (defaultHours == 0 &&
                      defaultHoursVol == 0 &&
                      defaultHoursTraining == 0 &&
                      defaultHoursTrainers == 0 &&
                      defaultHoursTEP == 0)
                    _sheetHourChip(
                        'Κάλυψη', 0, const Color(0xFF6B7280)),
                ],
              ),
              // Applications section
              const SizedBox(height: 20),
              Row(children: [
                Text('Αιτήσεις',
                    style:
                        tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6B7280).withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$enrolledCount',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6B7280))),
                ),
              ]),
              const SizedBox(height: 8),
              if (userServices.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Δεν υπάρχουν αιτήσεις',
                      style: tt.bodySmall
                          ?.copyWith(color: const Color(0xFF9CA3AF))),
                )
              else
                ...userServices.map((us) {
                  final user =
                      (us as Map<String, dynamic>)['user'] as Map<String, dynamic>? ?? {};
                  final fullName =
                      '${user['forename'] ?? ''} ${user['surname'] ?? ''}'
                          .trim();
                  final eame = (user['eame'] ?? '').toString();
                  final displayName =
                      fullName.isNotEmpty ? fullName : eame;
                  final status = (us['status'] ?? '').toString();
                  final hours = (us['hours'] as int?) ?? 0;

                  final Color statusColor;
                  final String statusLabel;
                  switch (status) {
                    case 'accepted':
                      statusColor = const Color(0xFF059669);
                      statusLabel = 'Εγκρίθηκε';
                    break;
                    case 'rejected':
                      statusColor = const Color(0xFFDC2626);
                      statusLabel = 'Απορρίφθηκε';
                    break;
                    default:
                      statusColor = const Color(0xFFD97706);
                      statusLabel = 'Αίτηση';
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Expanded(
                        child: Text(displayName,
                            style: tt.bodySmall?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF1F2937)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (hours > 0) ...[
                        Text('${hours}h',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF6B7280))),
                        const SizedBox(width: 8),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                          border:
                              Border.all(color: statusColor.withAlpha(60)),
                        ),
                        child: Text(statusLabel,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: statusColor)),
                      ),
                    ]),
                  );
                }),
              // Edit button — admin only
              if (isAdmin) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.push('/admin/services/${svc['id']}');
                    },
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Επεξεργασία υπηρεσίας',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
  ```

- [ ] **Step 3: Add `_sheetInfoRow` and `_sheetHourChip` helper methods to `_PastServicesScreenState`**

  Add these two methods inside `_PastServicesScreenState` (below `_showPastServiceSheet`):

  ```dart
  Widget _sheetInfoRow(IconData icon, String label, String value, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 10),
        SizedBox(
          width: 90,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1F2937))),
        ),
      ]),
    );
  }

  Widget _sheetHourChip(String label, int hours, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 13, color: color),
          const SizedBox(width: 4),
          Text('$label: ${hours}ω',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
  ```

- [ ] **Step 4: Verify the file compiles with no errors**

  ```bash
  cd frontend && flutter analyze lib/screens/past_services_screen.dart
  ```
  Expected: no errors, no unused-import warnings.

- [ ] **Step 5: Hot-reload and verify bottom sheet**

  Navigate to past services. Tap a card.
  Verify:
  - Sheet opens with drag handle, service name + "Ολοκληρωμένη" badge.
  - Info rows: time range, location (if set), carrier (if set), responsible (if set), enrollment count.
  - Description box appears if service has description.
  - Hours chips section present.
  - "Αιτήσεις (N)" section with list of names + colored status chips.
  - If logged in as admin/missionAdmin: green "Επεξεργασία υπηρεσίας" button at bottom.
  - If not admin: no edit button.

- [ ] **Step 6: Commit**

  ```bash
  git add frontend/lib/screens/past_services_screen.dart
  git commit -m "feat: add past service bottom sheet with applications list and admin edit button"
  ```
