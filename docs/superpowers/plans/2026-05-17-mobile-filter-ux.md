# Mobile Filter UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove redundant page title headers and make secondary filters collapsible (hidden by default, toggled by a "Φίλτρα" button) across all five main screens.

**Architecture:** Each screen adds a `bool _filtersExpanded` state field. A compact `AnimatedContainer`-style toggle button sits inline with the search bar (or after the action bar). The filter panel is wrapped in `AnimatedSize` which animates height between 0 and natural size. No shared widgets — each screen handles its own panel since the contents differ.

**Tech Stack:** Flutter (Dart), `AnimatedSize`, `AnimatedContainer`, Provider

---

## Files Modified

| File | Change |
|------|--------|
| `frontend/lib/screens/services_screen.dart` | Remove title row; add `_filtersExpanded`; wrap spec chips in `AnimatedSize` |
| `frontend/lib/screens/victims_screen.dart` | Remove `AppBar`; add `SafeArea`; inline filter button next to search; wrap date+status in `AnimatedSize` |
| `frontend/lib/screens/items_screen.dart` | Remove dept filter from top bar; add filter button next to search; wrap dept+category in `AnimatedSize` |
| `frontend/lib/screens/vehicles_screen.dart` | Remove "Οχήματα" section header `SliverToBoxAdapter` |
| `frontend/lib/screens/departments_screen.dart` | Remove "Τμήματα" section header `SliverToBoxAdapter` |

---

## Task 1: ServicesScreen — remove title, collapsible spec filters

**File:** `frontend/lib/screens/services_screen.dart`

- [ ] **Step 1: Add `_filtersExpanded` state field**

  In `_ServicesScreenState`, after `bool _fabOpen = false;` (around line 78), add:

  ```dart
  bool _filtersExpanded = false;
  ```

- [ ] **Step 2: Delete the "Brand page title" SliverToBoxAdapter**

  Remove this entire block from the `slivers` list (currently the first `SliverToBoxAdapter` in the `CustomScrollView`):

  ```dart
  // ── Brand page title ──
  SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(
        children: [
          Container(
            width: 4, height: 22,
            decoration: BoxDecoration(
              color: const Color(0xFFC62828),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Υπηρεσίες',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1C1E),
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    ),
  ),
  const SliverToBoxAdapter(child: SizedBox(height: 12)),
  ```

- [ ] **Step 3: Add the filter toggle button between the top bar and the spec chips**

  After the top bar `SliverToBoxAdapter` (the one containing "Οι υπηρεσίες μου" button), and before the spec filter chips `SliverToBoxAdapter`, insert:

  ```dart
  // ── Filter toggle ───────────────────────────
  SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: (_filtersExpanded || _selectedSpecId != null)
                  ? cs.primary.withAlpha(15)
                  : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (_filtersExpanded || _selectedSpecId != null)
                    ? cs.primary.withAlpha(60)
                    : const Color(0xFFE5E7EB),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 16,
                  color: (_filtersExpanded || _selectedSpecId != null)
                      ? cs.primary
                      : const Color(0xFF6B7280),
                ),
                const SizedBox(width: 6),
                Text(
                  _selectedSpecId != null ? 'Φίλτρα (1)' : 'Φίλτρα',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: (_filtersExpanded || _selectedSpecId != null)
                        ? cs.primary
                        : const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
  ```

- [ ] **Step 4: Wrap the spec filter chips in `AnimatedSize`**

  Replace the existing spec filter chips `SliverToBoxAdapter`:

  ```dart
  // ── Specialization filter bubbles ────────
  SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: SizedBox(
        height: 40,
        child: dynamicSpecs.isEmpty
            ? const SizedBox.shrink()
            : ListView.separated(
          // ... existing chip list builder ...
        ),
      ),
    ),
  ),
  ```

  With:

  ```dart
  // ── Specialization filter bubbles (collapsible) ────────
  SliverToBoxAdapter(
    child: AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: (_filtersExpanded && dynamicSpecs.isNotEmpty)
          ? Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemCount: dynamicSpecs.length,
                  itemBuilder: (context, i) {
                    final specId = dynamicSpecs[i].key;
                    final specName = dynamicSpecs[i].value;
                    final count = _countForSpec(specId);
                    final selected = _selectedSpecId == specId;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedSpecId = selected ? null : specId;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? cs.primary : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected ? cs.primary : const Color(0xFFD1D5DB),
                          ),
                        ),
                        child: Text(
                          '$specName ($count)',
                          style: tt.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : const Color(0xFF374151),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            )
          : const SizedBox.shrink(),
    ),
  ),
  ```

- [ ] **Step 5: Reduce top bar top padding**

  The top bar's `SliverToBoxAdapter` currently has `padding: const EdgeInsets.fromLTRB(20, 16, 20, 0)`. Change the top from `16` to `20` to compensate for removing the title row above it:

  ```dart
  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
  ```

- [ ] **Step 6: Manually verify**

  Run `flutter run -d chrome`, navigate to the Services screen. Confirm:
  - No "Υπηρεσίες" title visible
  - Spec chips hidden by default
  - Tapping "Φίλτρα" reveals chips with animation
  - Button shows "Φίλτρα (1)" when a spec is selected
  - Button stays highlighted while filters panel is open or a filter is active

- [ ] **Step 7: Commit**

  ```bash
  git add frontend/lib/screens/services_screen.dart
  git commit -m "feat(mobile): remove title, collapsible spec filters on ServicesScreen"
  ```

---

## Task 2: VictimsScreen — remove AppBar, collapsible date/status filters

**File:** `frontend/lib/screens/victims_screen.dart`

- [ ] **Step 1: Add state fields**

  In `_VictimsScreenState`, after `Timer? _searchDebounce;`, add:

  ```dart
  bool _filtersExpanded = false;
  ```

  Also add a getter for the active secondary filter count (add this method to the class body):

  ```dart
  int get _activeFilterCount {
    int count = 0;
    if (_dateFrom != null) count++;
    if (_dateTo != null) count++;
    if (_status != 'all') count++;
    return count;
  }
  ```

- [ ] **Step 2: Remove the `AppBar` and add `SafeArea`**

  In `build`, replace:

  ```dart
  return Scaffold(
    appBar: AppBar(
      title: const Text('Περιστατικά'),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () => context.push('/victims/create'),
      child: const Icon(Icons.add),
    ),
    body: RefreshIndicator(
  ```

  With:

  ```dart
  return Scaffold(
    floatingActionButton: FloatingActionButton(
      onPressed: () => context.push('/victims/create'),
      child: const Icon(Icons.add),
    ),
    body: SafeArea(
      child: RefreshIndicator(
  ```

  And close the extra `SafeArea` at the end (find the closing `),` of `body: RefreshIndicator(...)` and wrap it):

  The full body becomes:
  ```dart
  body: SafeArea(
    child: RefreshIndicator(
      onRefresh: () async => _fetch(),
      child: Column(
        children: [
          // ... all existing children ...
        ],
      ),
    ),
  ),
  ```

- [ ] **Step 3: Replace the search bar with a search + filter toggle row**

  Replace the current search bar `Padding` widget:

  ```dart
  // ── Search bar ──────────────────────
  Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: TextField(
      controller: _searchCtrl,
      decoration: InputDecoration(
        hintText: 'Αναζήτηση...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchCtrl.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchDebounce?.cancel();
                  _searchCtrl.clear();
                  _fetch();
                },
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onChanged: _onSearchChanged,
    ),
  ),
  ```

  With:

  ```dart
  // ── Search bar + filter toggle ──────
  Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Αναζήτηση...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchDebounce?.cancel();
                        _searchCtrl.clear();
                        setState(() {});
                        _fetch();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onChanged: (v) {
              setState(() {});
              _onSearchChanged(v);
            },
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (_filtersExpanded || _activeFilterCount > 0)
                  ? Theme.of(context).colorScheme.primary.withAlpha(15)
                  : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (_filtersExpanded || _activeFilterCount > 0)
                    ? Theme.of(context).colorScheme.primary.withAlpha(60)
                    : const Color(0xFFE5E7EB),
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: (_filtersExpanded || _activeFilterCount > 0)
                      ? Theme.of(context).colorScheme.primary
                      : const Color(0xFF6B7280),
                ),
                if (_activeFilterCount > 0)
                  Positioned(
                    right: -4, top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Color(0xFFC62828),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$_activeFilterCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  ),
  ```

- [ ] **Step 4: Wrap the date range row and status chips in `AnimatedSize`**

  Replace the current date range row and `_FilterRow` with:

  ```dart
  // ── Collapsible filters ─────────────
  AnimatedSize(
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeInOut,
    child: _filtersExpanded
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Date range row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: _DatePickerButton(
                        label: 'Από',
                        date: _dateFrom,
                        onPicked: (d) {
                          setState(() => _dateFrom = d);
                          _fetch();
                        },
                        onClear: () {
                          setState(() => _dateFrom = null);
                          _fetch();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DatePickerButton(
                        label: 'Έως',
                        date: _dateTo,
                        onPicked: (d) {
                          setState(() => _dateTo = d);
                          _fetch();
                        },
                        onClear: () {
                          setState(() => _dateTo = null);
                          _fetch();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              // Status chips
              _FilterRow(
                selected: _status,
                onChanged: (v) {
                  setState(() => _status = v);
                  _fetch();
                },
              ),
            ],
          )
        : const SizedBox.shrink(),
  ),
  const SizedBox(height: 4),
  ```

  Remove the original date range and `_FilterRow` and `const SizedBox(height: 4)` that were previously unconditional.

- [ ] **Step 5: Manually verify**

  Navigate to Victims screen. Confirm:
  - No AppBar title "Περιστατικά"
  - Content starts below status bar (SafeArea correct)
  - Date range and status chips are hidden by default
  - Tune icon button appears to the right of the search bar
  - Tapping it reveals filters with animation
  - Badge shows count of active secondary filters
  - Selecting a status or date shows badge on button even after closing the panel

- [ ] **Step 6: Commit**

  ```bash
  git add frontend/lib/screens/victims_screen.dart
  git commit -m "feat(mobile): remove AppBar, collapsible secondary filters on VictimsScreen"
  ```

---

## Task 3: ItemsScreen — move dept filter into collapsible panel

**File:** `frontend/lib/screens/items_screen.dart`

- [ ] **Step 1: Add state field and active filter count getter**

  In `_ItemsScreenState`, after `final Set<int> _selectedIds = {};`, add:

  ```dart
  bool _filtersExpanded = false;
  ```

  Add this getter to the class body (after `_exitSelectionMode`):

  ```dart
  int get _activeFilterCount {
    int count = 0;
    if (_deptFilter != null) count++;
    if (_selectedCategoryId != null) count++;
    return count;
  }
  ```

- [ ] **Step 2: Remove the dept filter dropdown from the top bar**

  In the top bar `Row` in `build`, remove these two lines:

  ```dart
  const SizedBox(width: 8),
  Expanded(child: _buildDeptFilter()),
  ```

  The top bar row now contains: `[my equipment button]`, `[spacer]`, `[csv icon (admin)]`, `[profile avatar]`.

  Add a `const Spacer()` between the equipment button and the CSV icon so they spread properly:

  ```dart
  Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Row(children: [
      // my equipment button (unchanged)
      Material(
        // ... unchanged ...
      ),
      const Spacer(),
      if (canManage) ...[
        IconButton(
          onPressed: () => context.push('/items/csv'),
          icon: Icon(Icons.settings, size: 22, color: cs.primary),
          tooltip: 'Εισαγωγή / Εξαγωγή CSV',
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 4),
      ],
      GestureDetector(
        onTap: () => context.push('/profile'),
        child: CircleAvatar(
          radius: 18,
          backgroundColor: cs.primary,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : 'U',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
      ),
    ]),
  ),
  ```

- [ ] **Step 3: Add filter toggle button next to the search bar**

  Replace the search bar `Padding` widget:

  ```dart
  // ── Search ──
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: TextField(
      controller: _searchCtrl,
      // ...
    ),
  ),
  ```

  With:

  ```dart
  // ── Search + filter toggle ──
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: canManage
                  ? 'Αναζήτηση αντικειμένων...'
                  : 'Αναζήτηση διαθέσιμου εξοπλισμού...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() { _search = ''; _page = 0; });
                      },
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            onChanged: (v) => setState(() { _search = v; _page = 0; }),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (_filtersExpanded || _activeFilterCount > 0)
                  ? cs.primary.withAlpha(15)
                  : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (_filtersExpanded || _activeFilterCount > 0)
                    ? cs.primary.withAlpha(60)
                    : const Color(0xFFE5E7EB),
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: (_filtersExpanded || _activeFilterCount > 0)
                      ? cs.primary
                      : const Color(0xFF6B7280),
                ),
                if (_activeFilterCount > 0)
                  Positioned(
                    right: -4, top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Color(0xFFC62828),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$_activeFilterCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  ),
  ```

- [ ] **Step 4: Wrap dept dropdown + category chips in `AnimatedSize`**

  After the search row, replace the existing `if (cats.isNotEmpty) Padding(...)` category chips block with:

  ```dart
  // ── Collapsible filters ─────────────
  AnimatedSize(
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeInOut,
    child: _filtersExpanded
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dept dropdown
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: _buildDeptFilter(),
              ),
              // Category chips
              if (cats.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _chip('Όλα (${_processed.length})', null),
                        const SizedBox(width: 6),
                        ...cats.map((c) {
                          final catId = c['id'] as int;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _chip(
                              '${c['name']} (${_countCat(catId)})',
                              catId,
                              color: const Color(0xFF7C3AED),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
            ],
          )
        : const SizedBox.shrink(),
  ),
  ```

- [ ] **Step 5: Manually verify**

  Navigate to Items screen. Confirm:
  - Top bar no longer has the dept dropdown inline
  - Filter button appears right of search
  - Tapping reveals dept dropdown + category chips
  - Badge shows active filter count
  - Dept filter selected state still resets page to 0 when changed

- [ ] **Step 6: Commit**

  ```bash
  git add frontend/lib/screens/items_screen.dart
  git commit -m "feat(mobile): move dept filter, collapsible panel on ItemsScreen"
  ```

---

## Task 4: VehiclesScreen + DepartmentsScreen — remove section title headers

**Files:** `frontend/lib/screens/vehicles_screen.dart`, `frontend/lib/screens/departments_screen.dart`

- [ ] **Step 1: Remove "Οχήματα" section header from VehiclesScreen**

  In `vehicles_screen.dart`, inside the `CustomScrollView` slivers list, find and delete the `SliverToBoxAdapter` that contains the "Οχήματα" title row. It looks like:

  ```dart
  // ── Section header ──
  SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        children: [
          Container(
            width: 4, height: 22,
            decoration: BoxDecoration(
              color: const Color(0xFFC62828),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Οχήματα',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1C1E),
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFD97706).withAlpha(15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${prov.vehicles.length} σύνολο',
              style: GoogleFonts.inter(
                fontSize: 12, color: const Color(0xFFD97706), fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  ),
  ```

  Delete this entire `SliverToBoxAdapter` block.

- [ ] **Step 2: Remove "Τμήματα" section header from DepartmentsScreen**

  In `departments_screen.dart`, inside the `CustomScrollView` slivers list, find and delete the `SliverToBoxAdapter` that contains the "Τμήματα" title row. It starts with the comment `// ── Section header ──` and includes the count chip. Delete the entire block:

  ```dart
  // ── Section header ──
  SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        children: [
          Container(
            width: 4, height: 22,
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Τμήματα',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1C1E),
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withAlpha(15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${depts.length} σύνολο',
              style: GoogleFonts.inter(
                fontSize: 12, color: const Color(0xFF7C3AED), fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  ),
  ```

- [ ] **Step 3: Manually verify both screens**

  Navigate to Vehicles screen: no "Οχήματα" title, top bar and vehicle cards intact.
  Navigate to Departments screen: no "Τμήματα" title, search bar and department cards intact.

- [ ] **Step 4: Commit**

  ```bash
  git add frontend/lib/screens/vehicles_screen.dart frontend/lib/screens/departments_screen.dart
  git commit -m "feat(mobile): remove section title headers from Vehicles and Departments screens"
  ```

---

## Final Check

After all tasks are done, do a quick pass across all five screens on mobile viewport (Chrome DevTools at 390×844):
- No redundant page titles anywhere
- Filters hidden by default on Services, Victims, Items
- Filter button badge correctly reflects active filter state
- Animations feel smooth (200ms easeInOut)
- Desktop layout (≥900px) unaffected
