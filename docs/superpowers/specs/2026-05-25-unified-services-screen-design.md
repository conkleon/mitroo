# Unified Services Screen — Design Spec

**Date:** 2026-05-25  
**Status:** Approved

## Summary

Replace the two-screen setup (`ManageServicesScreen` + `PastServicesScreen`) with a single tabbed screen at `/admin/services` containing four lifecycle tabs: Active, Closed, Completed, Finalized. Each tab renders the same card component, has its own data/sync state, and exposes admin actions appropriate to that lifecycle stage.

---

## 1. Architecture

### Host screen

`ManageServicesScreen` becomes a thin `StatefulWidget` that owns:
- A `TabController` (4 tabs)
- A `TabBar` (rendered in the AppBar bottom slot)
- A `TabBarView` with four child tab widgets
- The AppBar sync icon button (delegates to the active tab's `sync()` method via a per-tab `GlobalKey` or a shared `TabSyncController`)
- The FAB ("Νέα Υπηρεσία") — visible only when Active tab is selected

### Tab widgets

Each tab is a separate `StatefulWidget` with `AutomaticKeepAliveClientMixin` to preserve scroll position and loaded data when the user switches tabs:

| File | Class | Lifecycle |
|------|-------|-----------|
| `widgets/active_services_tab.dart` | `ActiveServicesTab` | `active` |
| `widgets/closed_services_tab.dart` | `ClosedServicesTab` | `closed` |
| `widgets/completed_services_tab.dart` | `CompletedServicesTab` | `completed` |
| `widgets/finalized_services_tab.dart` | `FinalizedServicesTab` | `finalized` |

### Shared card

`widgets/service_card.dart` extracts the full card builder, enrollment panel, and all small reusable widgets (`_EnrollBadge`, `_CompactIconBtn`, `_HoursField`) currently duplicated across the two screens. Each tab passes tab-specific action callbacks into the card so the card itself stays stateless with respect to lifecycle logic.

---

## 2. Navigation changes

- `/admin/services/past` GoRoute is **removed**.
- The "Προηγούμενες" `TextButton` in the `ManageServicesScreen` AppBar is **removed**.
- `PastServicesScreen` file is **deleted**.
- `router.dart` import of `PastServicesScreen` is removed.

---

## 3. Backend changes

### 3a. Prisma schema — new enum value

Add `not_participated` to the `UserServiceStatus` enum (Prisma uses snake_case for enum values by default; the API and Dart client will surface it as `"not-participated"`).

```prisma
enum UserServiceStatus {
  requested
  accepted
  rejected
  participated
  not_participated  // ← new
}
```

Generate and apply a migration: `20260525_add_not_participated_status`.

### 3b. Prisma enum wire format note

Prisma enum value `not_participated` (underscore) serializes to the string `"not-participated"` (hyphen) over the API wire format by convention in this codebase (matching `lifecycleStatus` values like `"not-participated"`). All Dart and TypeScript code uses `"not-participated"`.

### 3c. New endpoint

```
PATCH /api/services/:sid/users/:uid/participation
```

**Auth:** `authenticate` + `requireServiceAdmin`  
**Guard:** service `lifecycleStatus` must be `closed` or `completed` (409 otherwise)  
**Body schema (Zod):**
```ts
z.object({ status: z.enum(["participated", "not-participated"]) })
```
**Action:** `prisma.userService.update` setting `status` on the `userId_serviceId` record.  
**Response:** the updated `UserService` record.  
**No write-back** to Mitroo for this action (participation corrections are local-only).

### 3d. Existing status endpoint unchanged

`PATCH /api/services/:sid/users/:uid/status` keeps its schema (`requested | accepted | rejected`) and is still used for normal enrollment management on Active and Closed tabs.

---

## 4. Per-tab behavior

### Active tab

- **Loads:** `GET /services?departmentId=X&lifecycleStatus=active&includeEnrollments=true`
- **Filters:** search bar, service-type filter chips (same as current screen)
- **Card additions vs current:** amber "Κλείσιμο" button in the card header action column → `POST /services/:id/close` → removes card from list on success
- **Enrollment panel:** identical to current (accept/reject/hours/remove/direct-enroll)
- **Sync:** AppBar button triggers `SyncProvider.syncActive(deptId)` → reload
- **FAB:** "Νέα Υπηρεσία" (only tab with FAB)

### Closed tab

- **Loads:** `GET /services?departmentId=X&lifecycleStatus=closed&includeEnrollments=true&includeExpired=true`
- **Filters:** search bar only
- **Card additions:** green "Ολοκλήρωση" button in the card header action column → `AlertDialog` ("Ολοκλήρωση «name»; Όλοι οι αποδεκτοί εθελοντές θα σημανθούν ως παρόντες.") → on confirm: `POST /services/:id/complete` → removes card from list on success
- **Enrollment panel additions:**
  - Each user with `status == "accepted"` gets a "Μη συμμετοχή" icon button (`Icons.person_off_outlined`, grey) → calls `PATCH /participation` with `{ status: "not-participated" }` → local state update
  - Each user with `status == "not-participated"` gets a "Επαναφορά" icon button (`Icons.undo`, amber) → calls the existing `PATCH /status` with `{ status: "accepted" }` (reverts to accepted since the service is still `closed`, not yet completed)
  - `not-participated` users display status badge "Δεν παρ." in red
- **Sync:** `SyncProvider.syncClosed(deptId)`

### Completed tab

- **Loads:** `GET /services?departmentId=X&lifecycleStatus=completed&includeEnrollments=true&includeExpired=true` with server-side pagination (`page` / `limit=20`)
- **Pagination:** infinite scroll — when user reaches bottom of list, appends next page; or a "Φόρτωση περισσότερων" button
- **Card:** same expandable card; enrollment panel shows `participated` / `not-participated` / `rejected` / `accepted` status badges. Hours edit button still available (`PATCH /hours`). Per-user `PATCH /participation` toggle available for `participated` ↔ `not-participated`.
- **No lifecycle action buttons** (Complete/Close) — service is already completed
- **Sync:** `SyncProvider.syncCompleted(deptId)`

### Finalized tab

- **Loads:** `GET /services?departmentId=X&lifecycleStatus=finalized&includeEnrollments=true&includeExpired=true` with pagination (`limit=20`)
- **Card:** fully read-only. Enrollment panel shows status badges only — no action buttons, no hours edit, no direct-enroll field
- **Sync:** `SyncProvider.syncFinalized(deptId)`

---

## 5. Sync behavior (all tabs)

- **No automatic sync on tab switch.** Each tab loads from local DB on mount (`_load()` in `initState`).
- The AppBar sync button is the sole trigger. It shows a `CircularProgressIndicator` (20×20, strokeWidth 2) while syncing and is disabled during sync.
- The sync button is scoped: pressing it while on the Closed tab calls `syncClosed`, etc.
- After sync completes, the active tab calls `_load()` to refresh from DB.

---

## 6. Status display mapping

| DB status | Display label (Greek) | Color |
|-----------|----------------------|-------|
| `requested` | Εκκρεμής | amber `0xFFF59E0B` |
| `accepted` | Εγκρίθηκε | green `0xFF059669` |
| `rejected` | Απορρίφθηκε | red `0xFFDC2626` |
| `participated` | Παρουσιάστηκε | cyan `0xFF0891B2` |
| `not-participated` | Δεν παρ. | grey `0xFF6B7280` |

---

### 3e. Backend pagination (also referenced in §7)

The `GET /services` endpoint gains optional `page` (1-based integer, default 1) and `limit` (integer, default no-limit) query params. When both are provided, the Prisma query adds `skip: (page-1)*limit` and `take: limit`. This is only used by the Completed and Finalized tabs.

---

## 7. Frontend pagination

Completed and Finalized tabs load with `page=1&limit=20`. When the user scrolls to the bottom (or taps "Φόρτωση περισσότερων"), the tab appends the next page. End-of-list is detected when the returned array length is less than the requested `limit`. The list is not reset on sync — sync fetches page 1 fresh and replaces the entire list.

---

## 8. Out of scope

- Responsible-user picker: kept as-is on Active and Closed tabs, hidden on Completed/Finalized
- Service edit/delete: kept on Active tab only; hidden on Closed/Completed/Finalized
- Specialization filter: not included in this refactor (can be added later)
- Date range filter: not included (can be added later per tab)
