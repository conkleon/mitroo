# Admin Screen Visual Refactor — Design Spec

**Date:** 2026-05-16  
**Screens:** `manage_departments_screen.dart`, `manage_specializations_screen.dart`, `past_services_screen.dart`

---

## Goal

1. Make department and specialization list cards more condensed and informative.
2. Refactor past services cards to match the compact left-accent style of `services_screen.dart`, and add a bottom sheet with service info + enrolled members list + edit button.

---

## 1. Department & Specialization Cards

### Pattern

Both `_DeptCard` and `_SpecCard` are replaced with the same left-accent strip layout used by `_CalendarServiceCard` in `services_screen.dart`:

- Remove the 48×48 gradient icon square entirely.
- Use `IntrinsicHeight` + `Row` with a 4px colored left bar.
- Card padding: `horizontal: 12, vertical: 8` (down from `horizontal: 16, vertical: 14`).
- Total card height: ~48px (was ~76px+).

### `_DeptCard` layout

```
┌─┬──────────────────────────────────────┬───┐
│▌│ Τμήμα Αθήνας                   👥3 🔧2│ › │
│▌│ Κεντρική Αθήνα • Περιγραφή...   🚗1  │   │
└─┴──────────────────────────────────────┴───┘
```

- Left strip color: `Color(0xFF7C3AED)` (purple, consistent with manage screens).
- **Line 1:** `dept['name']`, `titleSmall`, `w700`, maxLines 1, overflow ellipsis.
- **Line 2:** Location + description snippet (both optional, separated by ` • ` if both present). `bodySmall`, `Color(0xFF6B7280)`, maxLines 1, overflow ellipsis.
- **Line 3 (Wrap):** `_CountBadge` widgets — members, services, vehicles — unchanged.
- Chevron `Icons.chevron_right` at far right.

### `_SpecCard` layout

```
┌─┬──────────────────────────────────────┬───┐
│▌│ Πυροσβεστική                   👥5 ↳2│ › │
│▌│ [root name or description snippet]   │   │
└─┴──────────────────────────────────────┴───┘
```

- Left strip color: `Color(0xFF7C3AED)` for root specs; `Color(0xFFDC2626)` for sub-specs (`rootId != null`).
- **Line 1:** `spec['name']`, same style as dept.
- **Line 2:** Parent name (if sub-spec) OR description snippet (if root). Gray, maxLines 1.
- **Line 3 (Wrap):** Existing `_MiniLabel` badges (user count, child count, hours, eamePrefix) — unchanged.
- Chevron at far right.

### Grid aspect ratios

- `manage_departments_screen.dart`: `childAspectRatio` adjusted from `3.0` → `3.5` to compensate for shorter cards.
- `manage_specializations_screen.dart`: `childAspectRatio` adjusted from `3.2` → `3.8`.

---

## 2. Past Services Screen

### Card style

Replace `_buildCard` with a new `_PastServiceCard` widget (inline in the file) using the left-accent strip pattern:

```
┌─┬──────────────────────────────────────┬─────┐
│▌│ ΕΚΤΑΚΤΗ ΥΠΗΡΕΣΙΑ ΑΘΗΝΩΝ      👥4 ✓2 │  ›  │
│▌│ 🕐 12/04/25 08:00 → 14/04/25 20:00   │     │
│▌│ 📍 Αθήνα                             │     │
└─┴──────────────────────────────────────┴─────┘
```

- Left strip color: `Color(0xFF059669)` (green — all past services are completed).
- **Line 1:** Service name (`svc['name']`), bold, maxLines 1.
- **Line 2:** Time range — `startAt → endAt` formatted as `dd/MM/yy HH:mm` (reuse existing `_fmtDate`).
- **Line 3:** Location (if non-empty).
- **Right side:** Enrollment count badge (`👥 N`) + accepted count badge (`✓ N`, green) if > 0.
- Chevron at far right.
- `onTap` → opens the bottom sheet (see below).

Grid `childAspectRatio` adjusted from `2.0` → `2.8` for the shorter cards.

### Bottom sheet on tap

Opened via `showModalBottomSheet` with `DraggableScrollableSheet` (initialChildSize: 0.65, max: 0.9). Structure mirrors `_showServiceInfoSheet` in `services_screen.dart`:

**Header section:**
- Drag handle.
- Service name as `titleLarge`, `w800`.
- Info rows (icon + label + value): time range, location, carrier (if set), responsible user (if set), total enrollment count.
- Description box (if set).
- Hours chips section (reuse `_sheetHourChip` pattern).

**Applications section:**
- Section header: `"Αιτήσεις (N)"` with divider.
- `ListView` of `userServices` entries, each row:
  - User full name (`forename surname`).
  - Status chip: green `"Εγκρίθηκε"` / red `"Απορρίφθηκε"` / amber `"Αίτηση"`.
  - Hours if `us['hours'] > 0` — shown as small gray text.
- Empty state if `userServices` is empty: `"Δεν υπάρχουν αιτήσεις"`.

**Edit button (admin only):**
- Shown when `auth.isAdmin || auth.isMissionAdmin` — same guard used in `services_screen.dart` FAB.
- `FilledButton` full-width: `"Επεξεργασία υπηρεσίας"` → navigates to `/admin/services/{id}`.

### Auth access in PastServicesScreen

`PastServicesScreen` currently does not consume `AuthProvider`. Add `context.watch<AuthProvider>()` in `build()` to get the admin flag for the edit button in the sheet.

---

## Files Changed

| File | Change |
|------|--------|
| `frontend/lib/screens/manage_departments_screen.dart` | Replace `_DeptCard` body with left-accent strip layout; adjust grid ratio |
| `frontend/lib/screens/manage_specializations_screen.dart` | Replace `_SpecCard` body with left-accent strip layout; adjust grid ratio |
| `frontend/lib/screens/past_services_screen.dart` | Replace `_buildCard`/`_buildGrid`/`_buildList` with `_PastServiceCard`; add `_showPastServiceSheet`; add `AuthProvider` import |

No new files. No backend changes. No routing changes.
