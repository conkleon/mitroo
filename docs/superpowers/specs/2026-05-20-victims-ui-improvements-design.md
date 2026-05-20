# Victims UI Improvements — Design Spec

**Date:** 2026-05-20  
**Scope:** `frontend/lib/screens/victims_screen.dart`, `frontend/lib/screens/victim_detail_screen.dart`

---

## 1. Victims Screen — Card list with colour-coded left border

### Problem
The current `DataTable` requires horizontal scrolling on mobile, making the list hard to scan on narrow screens.

### Solution
Replace the `DataTable` and its `SingleChildScrollView(scrollDirection: Axis.horizontal)` wrapper with a `ListView.builder` of cards. Each card has a 4 px coloured left border communicating status at a glance.

### Card design
- **Container**: white background, `BorderRadius.circular(10)`, subtle box shadow matching the rest of the app
- **Left border**: 4 px wide, colour determined by status:
  - Amber `#D97706` — pending (unsynced, `_isPending == true`)
  - Blue `#2563EB` — open (synced, not finalized)
  - Grey `#9CA3AF` — finalized
- **Content area** (right of border):
  - **Primary line**: victim name in bold (`FontWeight.w700`, `#1F2937`); pending cards prepend a `Icons.cloud_off_outlined` icon in amber
  - **Secondary line**: for pending cards show "Εκκρεμεί" in amber; for synced cards show `DD/MM/YYYY HH:mm · <chiefComplaint>` in `#6B7280`
- **Tap behaviour**: pending cards are non-tappable (same as current); synced cards navigate to `/victims/<id>` via `context.push`

### What stays the same
- Search bar and filter toggle button
- Collapsible date-range + status filter panel
- Pagination bar
- FloatingActionButton
- Loading spinner and empty-state text
- `_formatDate` helper

---

## 2. Victim Details Screen — `Wrap` for bottom action buttons

### Problem
The `bottomNavigationBar` uses a `Row` with up to three `FilledButton.icon` widgets (Edit, Finalize, Delete). On narrow mobile screens all three buttons overflow and the Delete button is clipped or invisible.

### Solution
Replace `Row` with `Wrap(spacing: 8, runSpacing: 8)`. Each button keeps its current style, label, and behaviour.

- On wide screens: all three buttons sit on one line (unchanged appearance).
- On narrow screens: overflow buttons wrap to a second run — Delete is always fully visible.
- The outer `Padding` and `SafeArea` wrappers remain unchanged.
- No other changes to the detail screen.

---

## Files changed

| File | Change |
|------|--------|
| `frontend/lib/screens/victims_screen.dart` | Replace `DataTable` block with `ListView.builder` of coloured-border cards |
| `frontend/lib/screens/victim_detail_screen.dart` | Replace `Row` in `bottomNavigationBar` with `Wrap` |
