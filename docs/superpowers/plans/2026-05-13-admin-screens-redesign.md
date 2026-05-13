# Admin Screens Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve the admin service management, past services, and users screens with better visual hierarchy, direct enrollment, and multi-select bulk actions.

**Architecture:** All changes are self-contained within three existing Flutter screen files. No new routes, no new backend endpoints. State is managed with existing `setState` patterns already used in each screen.

**Tech Stack:** Flutter (web), `provider`, `go_router`, `ApiClient` wrapper (custom HTTP), `intl` for date formatting.

---

## File Map

| File | What changes |
|------|-------------|
| `frontend/lib/screens/manage_services_screen.dart` | Add `_deptMembers` state + load in `_load()`; add direct-enroll `Autocomplete`; restyle enrollment rows; update pending badge text |
| `frontend/lib/screens/past_services_screen.dart` | Add stats row to cards; date range display; badge color update; spec chips to horizontal scroll; filter strip unification |
| `frontend/lib/screens/manage_users_screen.dart` | Add `_selectionMode` + `_selectedIds` state; checkbox rows; animated bulk action bar; four bulk action dialogs |

---

## API Reference

All calls use the existing `_api` (`ApiClient`) instance. Base: `http://localhost:4000/api`.

| Endpoint | Method | Body | Used in |
|----------|--------|------|---------|
| `/departments/:id/members` | GET | — | Task 1 — fetch dept members for search |
| `/services/:id/enroll` | POST | `{ userId, status: 'accepted' }` | Task 1 — direct enroll; Task 8 — bulk assign to service |
| `/users/:id/specializations` | POST | `{ specializationId }` | Task 8 — bulk assign specialization |
| `/departments/:deptId/members/:userId` | PATCH | `{ role }` | Task 8 — bulk role change |
| `/users/:id` | DELETE | — | Task 8 — bulk delete |
| `/services?departmentId=N&includeEnrollments=false` | GET | — | Task 8 — list active services for service dialog |

---

## Task 1: ManageServicesScreen — Load department members + direct enroll field

**Files:**
- Modify: `frontend/lib/screens/manage_services_screen.dart`

### Changes overview
Add `_deptMembers` to screen state, fetch it in `_load()` in parallel with services, then add an `Autocomplete` search field at the bottom of `_buildEnrollmentPanel`.

- [ ] **Step 1: Add `_deptMembers` field and update `_load()`**

In `_ManageServicesScreenState`, add the field below the existing `_expandedCards` line:

```dart
final Set<int> _expandedCards = {};
List<dynamic> _deptMembers = []; // ← add this
```

Replace the entire `_load()` method:

```dart
Future<void> _load() async {
  setState(() => _loading = true);
  try {
    final results = await Future.wait([
      _api.get('/services?departmentId=${widget.departmentId}&includeEnrollments=true'),
      _api.get('/departments/${widget.departmentId}/members'),
    ]);
    if (results[0].statusCode == 200 && mounted) {
      _services = jsonDecode(results[0].body);
    }
    if (results[1].statusCode == 200 && mounted) {
      _deptMembers = jsonDecode(results[1].body);
    }
  } catch (_) {}
  if (mounted) setState(() => _loading = false);
}
```

- [ ] **Step 2: Add `_directEnroll()` method**

Add this method to `_ManageServicesScreenState` (place after `_removeEnrollment`):

```dart
Future<void> _directEnroll(int serviceId, int userId) async {
  try {
    final res = await _api.post(
      '/services/$serviceId/enroll',
      body: {'userId': userId, 'status': 'accepted'},
    );
    if (res.statusCode == 201) {
      _load();
    } else if (mounted) {
      final err = jsonDecode(res.body)['error'] ?? 'Αποτυχία εγγραφής';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  } catch (_) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Σφάλμα εγγραφής')));
    }
  }
}
```

- [ ] **Step 3: Add `_buildDirectEnrollField()` method**

Add this method after `_directEnroll`:

```dart
Widget _buildDirectEnrollField(Map<String, dynamic> svc, List<dynamic> userServices) {
  final serviceId = svc['id'] as int;
  final enrolledIds = userServices
      .map((us) => (us['userId'] ?? us['user']?['id']) as int? ?? 0)
      .toSet();
  final available = _deptMembers.where((m) {
    final uid = m['user']?['id'] as int? ?? 0;
    return uid != 0 && !enrolledIds.contains(uid);
  }).toList();

  return Autocomplete<Map<String, dynamic>>(
    displayStringForOption: (m) {
      final u = m['user'] as Map<String, dynamic>;
      return '${u['forename'] ?? ''} ${u['surname'] ?? ''}'.trim();
    },
    optionsBuilder: (TextEditingValue value) {
      if (available.isEmpty) return const [];
      if (value.text.isEmpty) return available.cast<Map<String, dynamic>>();
      final q = value.text.toLowerCase();
      return available.where((m) {
        final u = m['user'] as Map<String, dynamic>;
        final name =
            '${u['forename'] ?? ''} ${u['surname'] ?? ''}'.trim().toLowerCase();
        final eame = (u['eame'] ?? '').toString().toLowerCase();
        return name.contains(q) || eame.contains(q);
      }).cast<Map<String, dynamic>>();
    },
    onSelected: (m) {
      final uid = m['user']['id'] as int;
      _directEnroll(serviceId, uid);
    },
    fieldViewBuilder: (context, controller, focusNode, _) => TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: InputDecoration(
        hintText: 'Προσθήκη μέλους...',
        prefixIcon: const Icon(Icons.person_add_outlined, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        isDense: true,
      ),
    ),
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 320),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, i) {
              final m = options.elementAt(i);
              final u = m['user'] as Map<String, dynamic>;
              final name =
                  '${u['forename'] ?? ''} ${u['surname'] ?? ''}'.trim();
              final eame = (u['eame'] ?? '').toString();
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: const Color(0xFFF5F3FF),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6D28D9),
                        fontWeight: FontWeight.w700),
                  ),
                ),
                title: Text(name, style: const TextStyle(fontSize: 13)),
                subtitle: eame.isNotEmpty
                    ? Text('@$eame',
                        style: const TextStyle(fontSize: 11))
                    : null,
                onTap: () => onSelected(m),
              );
            },
          ),
        ),
      ),
    ),
  );
}
```

- [ ] **Step 4: Add the enroll field to `_buildEnrollmentPanel`**

In `_buildEnrollmentPanel`, after the closing `...sorted.map((us) { ... })` spread (i.e. after all user rows), add:

```dart
// ── Direct enroll field ──
const SizedBox(height: 10),
Divider(color: Colors.grey.shade200, height: 1),
const SizedBox(height: 10),
_buildDirectEnrollField(svc, userServices),
```

The `child: Column(...)` in `_buildEnrollmentPanel` should end like:

```dart
child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    // Header row (existing)
    ...
    const SizedBox(height: 8),
    // User rows (existing)
    ...sorted.map((us) { ... }),
    // ── Direct enroll field (new) ──
    const SizedBox(height: 10),
    Divider(color: Colors.grey.shade200, height: 1),
    const SizedBox(height: 10),
    _buildDirectEnrollField(svc, userServices),
  ],
),
```

- [ ] **Step 5: Verify**

Start the frontend:
```bash
cd frontend && flutter run -d chrome
```

Open a service card, expand the enrollment panel, type a name in the "Προσθήκη μέλους..." field. Selecting a user should add them as accepted and reload the panel.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/screens/manage_services_screen.dart
git commit -m "feat: add direct enrollment search to service enrollment panel"
```

---

## Task 2: ManageServicesScreen — Restyle enrollment rows + action row

**Files:**
- Modify: `frontend/lib/screens/manage_services_screen.dart`

### Changes overview
- `requested` rows: amber left accent bar; action row shows Accept (filled) + Reject + Remove.
- `accepted` rows: Accept hidden; show Reject + Hours + Remove.
- `rejected` rows: Reject hidden; show Accept + Hours + Remove.
- Hours button hidden for `requested` status (no hours to log yet).
- Remove button becomes a plain `IconButton` (no `_ActionButton` wrapper).

- [ ] **Step 1: Replace the user row `Container` in `_buildEnrollmentPanel`**

Inside the `...sorted.map((us) { ... })` lambda, replace the entire returned `Container(...)` widget with:

```dart
return ClipRRect(
  borderRadius: BorderRadius.circular(10),
  child: Container(
    margin: const EdgeInsets.only(bottom: 6),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: st == 'requested'
            ? const Color(0xFFFDE68A)
            : Colors.grey.shade200,
        width: st == 'requested' ? 1.5 : 1,
      ),
    ),
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Amber accent bar for pending
          if (st == 'requested')
            Container(width: 4, color: const Color(0xFFF59E0B)),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              color: st == 'requested'
                  ? const Color(0xFFFFFBEB)
                  : Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Top: user info + status ──
                  Row(children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: stColor.withAlpha(30),
                      child: Text(
                        uName.isNotEmpty ? uName[0].toUpperCase() : '?',
                        style: TextStyle(
                            color: stColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(uName,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          if (eame.isNotEmpty)
                            Text('@$eame',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: stColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: stColor.withAlpha(60)),
                      ),
                      child: Text(
                        st.substring(0, 1).toUpperCase() +
                            st.substring(1),
                        style: TextStyle(
                            color: stColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  // ── Action row ──
                  Row(children: [
                    if (st != 'accepted') ...[
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.check_circle_outline,
                          label: 'Αποδοχή',
                          color: const Color(0xFF059669),
                          filled: true,
                          onTap: () => _updateEnrollmentStatus(
                              serviceId, userId, 'accepted'),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (st != 'rejected') ...[
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.cancel_outlined,
                          label: 'Απόρριψη',
                          color: const Color(0xFFDC2626),
                          filled: false,
                          onTap: () => _updateEnrollmentStatus(
                              serviceId, userId, 'rejected'),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (st != 'requested') ...[
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.schedule,
                          label: 'Ώρες',
                          color: const Color(0xFF6B7280),
                          filled: false,
                          onTap: () =>
                              _updateEnrollmentHours(serviceId, userId, us),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    IconButton(
                      icon: Icon(Icons.person_remove_outlined,
                          size: 18, color: Colors.grey.shade400),
                      onPressed: () =>
                          _removeEnrollment(serviceId, userId, uName),
                      tooltip: 'Αφαίρεση',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 32, minHeight: 32),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);
```

- [ ] **Step 2: Verify**

In the app, expand a service with both `requested` and `accepted` enrollments:
- `requested` rows show an amber left bar + amber background + Accept (green filled) + Reject + Remove icon
- `accepted` rows show white background + Reject + Hours + Remove icon
- `rejected` rows show white background + Accept + Hours + Remove icon

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/screens/manage_services_screen.dart
git commit -m "feat: restyle enrollment rows with amber accent and cleaner action row"
```

---

## Task 3: ManageServicesScreen — Update pending badge on card header

**Files:**
- Modify: `frontend/lib/screens/manage_services_screen.dart`

- [ ] **Step 1: Replace the amber badge in `_buildCard`**

Find this block inside `_buildCard` (inside the Members badge section):

```dart
if (requestedCount > 0) ...[
  const SizedBox(width: 4),
  Container(
    padding: const EdgeInsets.symmetric(
        horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: const Color(0xFFF59E0B),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text('+$requestedCount',
        style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w700)),
  ),
],
```

Replace with:

```dart
if (requestedCount > 0) ...[
  const SizedBox(width: 6),
  Container(
    padding: const EdgeInsets.symmetric(
        horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xFFFEF3C7),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFF59E0B)),
    ),
    child: Text('$requestedCount εκκρεμείς',
        style: const TextStyle(
            color: Color(0xFFB45309),
            fontSize: 10,
            fontWeight: FontWeight.w700)),
  ),
],
```

- [ ] **Step 2: Verify**

A service card with pending enrollments should show e.g. `2 εκκρεμείς` in an amber outlined pill next to the member count.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/screens/manage_services_screen.dart
git commit -m "feat: update pending badge to show count with label"
```

---

## Task 4: PastServicesScreen — Richer card stats + date range

**Files:**
- Modify: `frontend/lib/screens/past_services_screen.dart`

- [ ] **Step 1: Replace `_buildCard` in `past_services_screen.dart`**

Replace the entire `_buildCard` method with:

```dart
Widget _buildCard(Map<String, dynamic> svc) {
  final tt = Theme.of(context).textTheme;
  final name = svc['name'] ?? '';
  final location = svc['location'] ?? '';
  final carrier = svc['carrier'] ?? '';
  final visSpecs = svc['visibility'] as List<dynamic>? ?? [];
  final userServices = svc['userServices'] as List<dynamic>? ?? [];
  final enrolledCount = (svc['_count']?['userServices'] ?? 0) as int;
  final acceptedCount =
      userServices.where((us) => us['status'] == 'accepted').length;
  final totalHours = userServices.fold<int>(
      0, (sum, us) => sum + ((us['hours'] as int?) ?? 0));

  return Card(
    margin: const EdgeInsets.only(bottom: 10),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: Colors.grey.shade200),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.push('/admin/services/${svc['id']}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: name + completed badge ──
            Row(children: [
              Expanded(
                child: Text(name,
                    style: tt.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
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
                        color: Color(0xFF4B5563),
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 8),

            // ── Info row: location, carrier, date range ──
            Wrap(spacing: 12, runSpacing: 4, children: [
              if (location.isNotEmpty)
                _PastInfoChip(Icons.location_on, location),
              if (carrier.isNotEmpty)
                _PastInfoChip(Icons.groups, carrier),
              _PastInfoChip(Icons.calendar_today,
                  '${_fmtDate(svc['startAt'])} → ${_fmtDate(svc['endAt'])}'),
            ]),

            // ── Specialization chips (horizontal scroll) ──
            if (visSpecs.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 26,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: visSpecs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 4),
                  itemBuilder: (context, i) {
                    final specName =
                        visSpecs[i]['specialization']?['name'] ?? '';
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F3FF),
                        borderRadius: BorderRadius.circular(6),
                        border:
                            Border.all(color: const Color(0xFFDDD6FE)),
                      ),
                      child: Text(specName,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6D28D9))),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 10),

            // ── Stats row ──
            Row(children: [
              _StatPill(Icons.people, '$enrolledCount εγγ.',
                  const Color(0xFF6B7280)),
              const SizedBox(width: 8),
              if (acceptedCount > 0)
                _StatPill(Icons.check_circle_outline,
                    '$acceptedCount εγκ.', const Color(0xFF059669)),
              if (acceptedCount > 0) const SizedBox(width: 8),
              if (totalHours > 0)
                _StatPill(Icons.schedule, '${totalHours}h',
                    const Color(0xFF2563EB)),
              const Spacer(),
              Icon(Icons.chevron_right,
                  size: 18, color: Colors.grey.shade400),
            ]),
          ],
        ),
      ),
    ),
  );
}
```

- [ ] **Step 2: Add `_StatPill` widget at the bottom of the file**

After the `_PastInfoChip` class at the end of the file, add:

```dart
class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatPill(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
```

- [ ] **Step 3: Verify**

Past services cards now show:
- `Ολοκληρωμένη` badge in green-grey (not flat grey)
- Start → End date range on the info row
- Specialization chips in a horizontal scrollable row
- Stats pills at the bottom: `👥 N εγγ.` · `✓ N εγκ.` · `⏱ Nh`

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/screens/past_services_screen.dart
git commit -m "feat: add stats row and date range to past service cards"
```

---

## Task 5: PastServicesScreen — Unify filter strip

**Files:**
- Modify: `frontend/lib/screens/past_services_screen.dart`

### Changes overview
Replace the `_buildSpecDropdown` + `_buildDateChip` widgets in the filter row with a single horizontal `ListView` of `FilterChip`-style containers, matching the style used in `manage_services_screen.dart`.

- [ ] **Step 1: Replace the filter row in `build()`**

Find the `// ── Filters row ──` section in `build()` and replace the entire `Padding(...)` block containing `Wrap(...)` with:

```dart
// ── Filter strip ──
SizedBox(
  height: 38,
  child: ListView(
    scrollDirection: Axis.horizontal,
    padding: EdgeInsets.symmetric(horizontal: hPad),
    children: [
      // Specialization chips
      ..._specializations.map((s) {
        final specId = s['id'] as int;
        final selected = _selectedSpecId == specId;
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: FilterChip(
            avatar: Icon(Icons.workspace_premium,
                size: 14,
                color: selected
                    ? const Color(0xFF7C3AED)
                    : const Color(0xFF6B7280)),
            label: Text(s['name'] ?? ''),
            selected: selected,
            onSelected: (_) {
              setState(
                  () => _selectedSpecId = selected ? null : specId);
              _load();
            },
            selectedColor: const Color(0xFFF5F3FF),
            checkmarkColor: const Color(0xFF7C3AED),
            side: BorderSide(
                color: selected
                    ? const Color(0xFFDDD6FE)
                    : Colors.grey.shade300),
            visualDensity: VisualDensity.compact,
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight:
                  selected ? FontWeight.w600 : FontWeight.w400,
              color: selected
                  ? const Color(0xFF6D28D9)
                  : const Color(0xFF6B7280),
            ),
            padding: EdgeInsets.zero,
          ),
        );
      }),

      // From date chip
      Padding(
        padding: const EdgeInsets.only(right: 6),
        child: _buildDateChip(
          label: _fromDate != null
              ? 'Από: ${_fmtDay(_fromDate!)}'
              : 'Από ημ/νία',
          isSet: _fromDate != null,
          onTap: () => _pickDate(isFrom: true),
          onClear: _fromDate != null
              ? () {
                  setState(() => _fromDate = null);
                  _load();
                }
              : null,
        ),
      ),

      // To date chip
      Padding(
        padding: const EdgeInsets.only(right: 6),
        child: _buildDateChip(
          label: _toDate != null
              ? 'Έως: ${_fmtDay(_toDate!)}'
              : 'Έως ημ/νία',
          isSet: _toDate != null,
          onTap: () => _pickDate(isFrom: false),
          onClear: _toDate != null
              ? () {
                  setState(() => _toDate = null);
                  _load();
                }
              : null,
        ),
      ),

      // Clear all
      if (_selectedSpecId != null || _fromDate != null || _toDate != null)
        TextButton.icon(
          onPressed: () {
            setState(() {
              _selectedSpecId = null;
              _fromDate = null;
              _toDate = null;
            });
            _load();
          },
          icon: const Icon(Icons.clear_all, size: 16),
          label: const Text('Καθαρισμός', style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
            foregroundColor: Colors.grey.shade600,
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            visualDensity: VisualDensity.compact,
          ),
        ),
    ],
  ),
),
const SizedBox(height: 4),
```

Also remove the `// ── Results count ──` padding block from build — merge it into a single line below the filter strip:

```dart
Padding(
  padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 2),
  child: Text(
    _loading
        ? 'Φόρτωση...'
        : 'Βρέθηκαν ${_filtered.length} υπηρεσίες',
    style: Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Colors.grey.shade500),
  ),
),
```

- [ ] **Step 2: Remove `_buildSpecDropdown`**

Delete the entire `Widget _buildSpecDropdown(TextTheme tt) { ... }` method — it is no longer called.

- [ ] **Step 3: Verify**

The past services filter area shows a horizontal scrollable strip of specialization chips + date chips, styled consistently with the manage-services screen. Tapping a spec chip filters results immediately.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/screens/past_services_screen.dart
git commit -m "feat: unify past services filter strip with FilterChip style"
```

---

## Task 6: ManageUsersScreen — Multi-select state + checkbox rows

**Files:**
- Modify: `frontend/lib/screens/manage_users_screen.dart`

- [ ] **Step 1: Add selection state fields**

In `_ManageUsersScreenState`, after the `_page` and `_rowsPerPage` fields, add:

```dart
// Selection
bool _selectionMode = false;
final Set<int> _selectedIds = {};
```

- [ ] **Step 2: Add selection helper methods**

Add these methods after `_setSort`:

```dart
void _enterSelectionMode(int userId) {
  setState(() {
    _selectionMode = true;
    _selectedIds.add(userId);
  });
}

void _exitSelectionMode() {
  setState(() {
    _selectionMode = false;
    _selectedIds.clear();
  });
}

void _toggleSelect(int userId) {
  setState(() {
    if (_selectedIds.contains(userId)) {
      _selectedIds.remove(userId);
      if (_selectedIds.isEmpty) _selectionMode = false;
    } else {
      _selectedIds.add(userId);
    }
  });
}

void _toggleSelectAll(List<Map<String, dynamic>> pageUsers) {
  setState(() {
    final pageIds = pageUsers.map((u) => u['id'] as int).toSet();
    if (pageIds.every((id) => _selectedIds.contains(id))) {
      _selectedIds.removeAll(pageIds);
      if (_selectedIds.isEmpty) _selectionMode = false;
    } else {
      _selectedIds.addAll(pageIds);
    }
  });
}
```

- [ ] **Step 3: Update `_buildRow` to support selection mode**

Replace the entire `_buildRow` method:

```dart
Widget _buildRow(Map<String, dynamic> user, TextTheme tt, bool even) {
  final name = '${user['forename'] ?? ''} ${user['surname'] ?? ''}'.trim();
  final isAdmin = user['isAdmin'] == true;
  final userId = user['id'] as int;
  final isSelected = _selectedIds.contains(userId);

  return GestureDetector(
    onLongPress: () => _enterSelectionMode(userId),
    child: InkWell(
      onTap: () {
        if (_selectionMode) {
          _toggleSelect(userId);
        } else {
          context.push('/admin/users/$userId').then((_) {
            if (mounted) _fetch();
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: isSelected
            ? const Color(0xFFEEF2FF)
            : even
                ? Colors.white
                : const Color(0xFFF9FAFB),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          // Leading: checkbox in selection mode, avatar otherwise
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: _selectionMode
                ? Checkbox(
                    key: ValueKey(userId),
                    value: isSelected,
                    onChanged: (_) => _toggleSelect(userId),
                    visualDensity: VisualDensity.compact,
                    activeColor: const Color(0xFF7C3AED),
                  )
                : CircleAvatar(
                    key: ValueKey('avatar_$userId'),
                    radius: 15,
                    backgroundColor: isAdmin
                        ? Colors.amber.shade100
                        : const Color(0xFFFEE2E2),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'U',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isAdmin
                              ? Colors.amber.shade800
                              : const Color(0xFFDC2626)),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          // Name cell
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(name.isNotEmpty ? name : user['eame'] ?? '',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (isAdmin) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                          color: Colors.amber.withAlpha(30),
                          borderRadius: BorderRadius.circular(3)),
                      child: Text('A',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.amber.shade800)),
                    ),
                  ],
                ]),
                Text(user['eame'] ?? '',
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF9CA3AF)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          // Hours cells
          _hoursCell(user['totalHours']),
          _hoursCell(user['yearHours']),
          _hoursCell(user['yearVolHours']),
          _hoursCell(user['yearTrainingHours']),
          _hoursCell(user['yearTrainerHours']),
          _selectionMode
              ? const SizedBox(width: 16)
              : const Icon(Icons.chevron_right,
                  size: 16, color: Color(0xFFD1D5DB)),
        ]),
      ),
    ),
  );
}
```

- [ ] **Step 4: Update the table header to show select-all checkbox in selection mode**

Replace `_headerCell` call for 'Name' inside `build()` header row with:

```dart
// ── Header ──
Container(
  color: const Color(0xFFEEF0F4),
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
  child: Row(children: [
    if (_selectionMode)
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Checkbox(
          value: pageUsers.isNotEmpty &&
              pageUsers.every((u) =>
                  _selectedIds.contains(u['id'] as int)),
          tristate: false,
          onChanged: (_) => _toggleSelectAll(pageUsers),
          visualDensity: VisualDensity.compact,
          activeColor: const Color(0xFF7C3AED),
        ),
      )
    else
      const SizedBox(width: 8),
    _headerCell('Name', 'name', flex: 3),
    _headerCell('Total', 'totalHours'),
    _headerCell('Year', 'yearHours'),
    _headerCell('Vol', 'yearVolHours'),
    _headerCell('Train', 'yearTrainingHours'),
    _headerCell('Trainer', 'yearTrainerHours'),
    const SizedBox(width: 32),
  ]),
),
```

- [ ] **Step 5: Verify**

Long-press a user row → selection mode activates, checkbox appears. Tapping other rows toggles their checkbox. Tapping the header checkbox selects/deselects all visible rows.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/screens/manage_users_screen.dart
git commit -m "feat: add multi-select mode with checkboxes to users screen"
```

---

## Task 7: ManageUsersScreen — Bulk action bar + dialogs

**Files:**
- Modify: `frontend/lib/screens/manage_users_screen.dart`

- [ ] **Step 1: Wrap the `Scaffold` body in a `Stack` for the bulk action bar**

In `build()`, the `body: SafeArea(child: Column(...))` currently sits directly on `Scaffold`. Wrap the `SafeArea` in a `Stack`:

```dart
body: Stack(
  children: [
    SafeArea(
      child: Column(
        children: [
          // ... all existing filter + table content ...
        ],
      ),
    ),
    // Bulk action bar (overlays bottom)
    _buildBulkBar(),
  ],
),
```

- [ ] **Step 2: Add `_buildBulkBar()` method**

Add this method after `_buildDeptFilter`:

```dart
Widget _buildBulkBar() {
  return AnimatedSlide(
    offset: _selectionMode ? Offset.zero : const Offset(0, 1),
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOut,
    child: AnimatedOpacity(
      opacity: _selectionMode ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1B4B),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withAlpha(60),
                  blurRadius: 16,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Row(children: [
            // Count + close
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              onPressed: _exitSelectionMode,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            const SizedBox(width: 6),
            Text(
              '${_selectedIds.length} επιλεγμένοι',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
            const Spacer(),
            // Specialization
            _BulkAction(
              icon: Icons.school_outlined,
              label: 'Ειδίκευση',
              onTap: _showSpecializationDialog,
            ),
            // Service
            _BulkAction(
              icon: Icons.assignment_outlined,
              label: 'Υπηρεσία',
              onTap: _showServiceDialog,
            ),
            // Role (only when dept is selected)
            if (_deptFilter != null)
              _BulkAction(
                icon: Icons.manage_accounts_outlined,
                label: 'Ρόλος',
                onTap: _showRoleDialog,
              ),
            // Delete
            _BulkAction(
              icon: Icons.delete_outline,
              label: 'Διαγραφή',
              color: const Color(0xFFEF4444),
              onTap: _showDeleteDialog,
            ),
          ]),
        ),
      ),
    ),
  );
}
```

- [ ] **Step 3: Add `_BulkAction` widget at the bottom of the file**

After the last existing private widget class (e.g. `_buildDeptFilter`), add:

```dart
class _BulkAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _BulkAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 4: Add `_showSpecializationDialog()` method**

Add after `_buildDeptFilter`:

```dart
Future<void> _showSpecializationDialog() async {
  int? selectedSpecId;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) => AlertDialog(
        title: Text('Ανάθεση ειδίκευσης σε ${_selectedIds.length} χρήστες'),
        content: SizedBox(
          width: 320,
          child: DropdownButtonFormField<int>(
            decoration: const InputDecoration(
                labelText: 'Ειδίκευση', border: OutlineInputBorder()),
            items: _allSpecs
                .map((s) => DropdownMenuItem<int>(
                      value: s['id'] as int,
                      child: Text(s['name']?.toString() ?? ''),
                    ))
                .toList(),
            onChanged: (v) => setDlg(() => selectedSpecId = v),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Άκυρο')),
          FilledButton(
              onPressed: selectedSpecId != null
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Ανάθεση')),
        ],
      ),
    ),
  );
  if (confirmed != true || selectedSpecId == null || !mounted) return;

  int ok = 0;
  int fail = 0;
  await Future.wait(_selectedIds.map((uid) async {
    try {
      final res = await _api.post('/users/$uid/specializations',
          body: {'specializationId': selectedSpecId});
      res.statusCode == 201 ? ok++ : fail++;
    } catch (_) {
      fail++;
    }
  }));
  if (!mounted) return;
  _exitSelectionMode();
  _fetch();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(fail == 0
        ? '$ok χρήστες ενημερώθηκαν'
        : '$ok ενημερώθηκαν, $fail αποτυχίες'),
  ));
}
```

- [ ] **Step 5: Add `_showServiceDialog()` method**

```dart
Future<void> _showServiceDialog() async {
  if (_deptFilter == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text(
              'Επιλέξτε τμήμα για να αναθέσετε χρήστες σε υπηρεσία')),
    );
    return;
  }

  List<dynamic> services = [];
  try {
    final res = await _api
        .get('/services?departmentId=$_deptFilter&includeEnrollments=false');
    if (res.statusCode == 200) services = jsonDecode(res.body);
  } catch (_) {}

  // Filter to active/upcoming only
  final now = DateTime.now();
  final active = services.where((s) {
    final end = DateTime.tryParse(s['endAt'] ?? '');
    return end == null || end.isAfter(now);
  }).toList();

  if (!mounted) return;
  if (active.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Δεν υπάρχουν ενεργές υπηρεσίες')),
    );
    return;
  }

  int? selectedServiceId;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) => AlertDialog(
        title: Text('Ανάθεση ${_selectedIds.length} χρηστών σε υπηρεσία'),
        content: SizedBox(
          width: 360,
          child: DropdownButtonFormField<int>(
            decoration: const InputDecoration(
                labelText: 'Υπηρεσία', border: OutlineInputBorder()),
            isExpanded: true,
            items: active
                .map((s) => DropdownMenuItem<int>(
                      value: s['id'] as int,
                      child: Text(s['name']?.toString() ?? '',
                          overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setDlg(() => selectedServiceId = v),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Άκυρο')),
          FilledButton(
              onPressed: selectedServiceId != null
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Ανάθεση')),
        ],
      ),
    ),
  );
  if (confirmed != true || selectedServiceId == null || !mounted) return;

  int ok = 0;
  int fail = 0;
  await Future.wait(_selectedIds.map((uid) async {
    try {
      final res = await _api.post('/services/$selectedServiceId/enroll',
          body: {'userId': uid, 'status': 'accepted'});
      (res.statusCode == 201 || res.statusCode == 409) ? ok++ : fail++;
    } catch (_) {
      fail++;
    }
  }));
  if (!mounted) return;
  _exitSelectionMode();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(fail == 0
        ? '$ok χρήστες εγγράφηκαν'
        : '$ok εγγράφηκαν, $fail αποτυχίες'),
  ));
}
```

- [ ] **Step 6: Add `_showRoleDialog()` method**

```dart
Future<void> _showRoleDialog() async {
  if (_deptFilter == null) return;
  String selectedRole = 'volunteer';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) => AlertDialog(
        title: Text('Αλλαγή ρόλου για ${_selectedIds.length} χρήστες'),
        content: SizedBox(
          width: 320,
          child: DropdownButtonFormField<String>(
            value: selectedRole,
            decoration: const InputDecoration(
                labelText: 'Ρόλος', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(
                  value: 'volunteer', child: Text('Εθελοντής')),
              DropdownMenuItem(
                  value: 'missionAdmin',
                  child: Text('Δ. Αποστολών')),
              DropdownMenuItem(
                  value: 'itemAdmin', child: Text('Δ. Υλικού')),
            ],
            onChanged: (v) =>
                setDlg(() => selectedRole = v ?? 'volunteer'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Άκυρο')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Εφαρμογή')),
        ],
      ),
    ),
  );
  if (confirmed != true || !mounted) return;

  int ok = 0;
  int fail = 0;
  await Future.wait(_selectedIds.map((uid) async {
    try {
      final res = await _api.patch(
          '/departments/$_deptFilter/members/$uid',
          body: {'role': selectedRole});
      res.statusCode == 200 ? ok++ : fail++;
    } catch (_) {
      fail++;
    }
  }));
  if (!mounted) return;
  _exitSelectionMode();
  _fetch();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(fail == 0
        ? '$ok χρήστες ενημερώθηκαν'
        : '$ok ενημερώθηκαν, $fail αποτυχίες'),
  ));
}
```

- [ ] **Step 7: Add `_showDeleteDialog()` method**

```dart
Future<void> _showDeleteDialog() async {
  final count = _selectedIds.length;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Διαγραφή Χρηστών'),
      content: Text(
          'Διαγραφή $count χρηστών; Αυτή η ενέργεια δεν μπορεί να αναιρεθεί.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Άκυρο')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Διαγραφή'),
        ),
      ],
    ),
  );
  if (confirmed != true || !mounted) return;

  int ok = 0;
  int fail = 0;
  await Future.wait(_selectedIds.map((uid) async {
    try {
      final res = await _api.delete('/users/$uid');
      res.statusCode == 204 ? ok++ : fail++;
    } catch (_) {
      fail++;
    }
  }));
  if (!mounted) return;
  _exitSelectionMode();
  _fetch();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(fail == 0
        ? '$ok χρήστες διαγράφηκαν'
        : '$ok διαγράφηκαν, $fail αποτυχίες'),
  ));
}
```

- [ ] **Step 8: Verify**

1. Long-press a user row → bulk bar slides up from bottom.
2. Select multiple users → count updates in bar.
3. Tap "Ειδίκευση" → dialog to pick a spec → confirm → snackbar reports results.
4. Tap "Υπηρεσία" (with dept filter set) → dialog lists active services → confirm → snackbar.
5. Tap "Ρόλος" (with dept filter set) → role dropdown → confirm → snackbar.
6. Tap "Διαγραφή" → confirmation → users removed → snackbar.
7. Tap X → selection mode exits, bar slides away.

- [ ] **Step 9: Commit**

```bash
git add frontend/lib/screens/manage_users_screen.dart
git commit -m "feat: add bulk action bar with specialization, service, role, and delete actions"
```

---

## Self-Review Checklist

- [x] **Spec § 1.1 Direct enrollment** → Task 1 (Autocomplete + `POST /services/:id/enroll`)
- [x] **Spec § 1.2 Pending row visual** → Task 2 (amber left bar + action row reorder)
- [x] **Spec § 1.3 Action row simplification** → Task 2 (Hours hidden for `requested`; trash icon-only remove)
- [x] **Spec § 1.4 Card pending badge** → Task 3 (`N εκκρεμείς`)
- [x] **Spec § 2.1 Stats row** → Task 4 (`_StatPill` widgets)
- [x] **Spec § 2.2 Date range** → Task 4 (start → end in info row)
- [x] **Spec § 2.3 Badge color** → Task 4 (`Color(0xFFECFDF5)` bg / `Color(0xFF4B5563)` text)
- [x] **Spec § 2.4 Spec chips horizontal** → Task 4 (`ListView` scroll)
- [x] **Spec § 2.5 Filter strip** → Task 5 (unified `FilterChip` horizontal strip)
- [x] **Spec § 2.6 Grid min height** → covered by fixed `childAspectRatio` in existing grid; stat row always has content so no layout change needed
- [x] **Spec § 3.1 Multi-select** → Task 6 (long-press, checkbox, select-all header)
- [x] **Spec § 3.2 Bulk bar** → Task 7 (`AnimatedSlide` + 4 actions)
- [x] **Spec § 3.3 Row spec chip** → deferred (backend `/users/stats` doesn't include specializations; noted in spec as optional)
- [x] **Spec § 3.4 API verification** → all endpoints confirmed present before writing plan
