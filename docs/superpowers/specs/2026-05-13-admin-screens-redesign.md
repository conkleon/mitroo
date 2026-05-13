# Admin Screens Redesign — Visual & Flow Improvements

**Date:** 2026-05-13  
**Scope:** ManageServicesScreen, PastServicesScreen, ManageUsersScreen  
**Approach:** Inline-first — all changes within existing screens, no new navigation layers

---

## 1. ManageServicesScreen (`manage_services_screen.dart`)

### 1.1 Direct Enrollment (new)
- Bottom of the expanded enrollment panel gets a search-as-you-type `Autocomplete` field.
- Label: "Προσθήκη μέλους..." with a leading `+` / `person_add` icon.
- Options source: `GET /departments/{departmentId}/users` filtered to users not already in `userServices` for this service.
- Selecting a user calls `POST /services/{serviceId}/users` with `{ userId, status: 'accepted' }` (direct enrollment, no application step), then reloads.

### 1.2 Pending Request Visibility
- Rows with `status == 'requested'` get an amber left-border accent (1.5px) inside the enrollment panel.
- The Accept ✓ and Reject ✗ buttons are the first two items in the action row — full-width, clearly labeled — so they require no scrolling or hunting.

### 1.3 Action Row Simplification
- Per-enrollment row: `[Αποδοχή] [Απόρριψη] [Ώρες] [🗑]`
- Remove button is icon-only (trash) with tooltip "Αφαίρεση".
- Buttons that don't apply to current status are hidden (not just disabled), keeping the row uncluttered.

### 1.4 Card Pending Badge
- The amber `+N` pill on the card header changes to `N εκκρεμείς` text — more readable at a glance.

---

## 2. PastServicesScreen (`past_services_screen.dart`)

### 2.1 Richer Card Stats Row
- Each card gains a bottom stats row with three compact pills:
  - `👥 N εγγ.` — total enrolled (`_count.userServices`)
  - `✓ N εγκ.` — accepted count (from `userServices` where `status == 'accepted'`)
  - `⏱ Nh` — sum of `hours` across all `userServices`
- Stats pills use icon + number layout, small font (11px), colored subtly (grey for enrolled, green for accepted, blue-grey for hours).

### 2.2 Date Range Display
- Cards show start → end range: `dd/MM/yy – dd/MM/yy` instead of start date only.

### 2.3 "Ολοκληρωμένη" Badge
- Changed from flat grey to a grey-green tint (`Color(0xFF4B5563)` text on `Color(0xFFF0FDF4)` bg) to distinguish from "Χωρίς ημ/νία" (which stays neutral grey).

### 2.4 Specialization Chips
- Move from `Wrap` to a single horizontal `ListView` (scrollable row) below the info line — prevents overflow on narrow screens.

### 2.5 Filter Strip Unification
- Spec dropdown and date chips are replaced with a single horizontal scrollable strip of `FilterChip`-style widgets — same visual style as the spec filter chips in ManageServicesScreen for consistency.

### 2.6 Wide Screen Grid
- Grid cards (`crossAxisCount: 2`) get `mainAxisExtent` fixed height so the stats row is always visible regardless of content length.

---

## 3. ManageUsersScreen (`manage_users_screen.dart`)

### 3.1 Multi-Select Mode
- **Entry:** Long-press any row → enters selection mode. The pressed row is automatically selected.
- **Visual:** Each row's leading area shows a `Checkbox` (replacing the `CircleAvatar`, which shifts right). A `_selectionMode` bool drives this.
- **Header:** When in selection mode, the header's first cell shows a "select all" `Checkbox`.
- **Exit:** Tap the X in the action bar, or tap outside the list (via `GestureDetector` wrapping the scaffold body), or programmatically after a bulk action completes.

### 3.2 Bottom Bulk Action Bar
- Slides up with `AnimatedContainer` / `AnimatedSlide` when `_selectedUsers.isNotEmpty`.
- Left side: `"{N} επιλεγμένοι"` count.
- Right side: action icon buttons with labels:
  - `Ειδίκευση` (school icon) — dialog to pick a specialization → `POST /users/{id}/specializations` for each selected user.
  - `Υπηρεσία` (assignment icon) — searchable dialog listing active services filtered by current dept → `POST /services/{id}/users` with `status: accepted` for each.
  - `Ρόλος` (manage_accounts icon) — dropdown to pick dept role → `PATCH /departments/{deptId}/users/{id}/role` for each. The `deptId` comes from `_deptFilter`; this action is only available when a specific department is selected (greyed out / hidden when filter is "all departments").
  - `Διαγραφή` (delete icon, red) — confirmation dialog → `DELETE /users/{id}` for each.
- All bulk ops run with `Future.wait` and show a snackbar summary: `"N ενημερώθηκαν, M αποτυχίες"`.

### 3.3 Row Specialization Chip
- Each user row shows the first specialization as a small pill next to the name (from `user['specializations']` if present in the `/users/stats` response — backend may need to include this field).
- If not available from the existing endpoint, skip this visual for now and note it as a backend dependency.

### 3.4 API Endpoint Verification
- `POST /services/{serviceId}/users` — verify it accepts `{ userId, status }` for direct admin enrollment.
- `POST /users/{id}/specializations` — verify endpoint exists or needs creation.
- `PATCH /departments/{deptId}/users/{id}/role` — verify endpoint shape.
- These should be confirmed before implementing the bulk action dialogs.

---

## Out of Scope
- New screens or navigation routes
- Backend changes (except where noted as dependencies)
- Mobile layout changes (existing responsive breakpoints remain)
- ManageSpecializationsScreen, CreateServiceScreen — not touched

---

## Files to Modify
| File | Changes |
|------|---------|
| `frontend/lib/screens/manage_services_screen.dart` | Sections 1.1–1.4 |
| `frontend/lib/screens/past_services_screen.dart` | Sections 2.1–2.6 |
| `frontend/lib/screens/manage_users_screen.dart` | Sections 3.1–3.4 |
