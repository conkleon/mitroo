# Admin Panel Refactor Design

**Date:** 2026-05-13  
**Branch:** `copilot/extend-mitroo-synchronization`  
**Status:** Approved

---

## Overview

Refactor the admin panel to be simpler, more professional, and role-correct. The hub page is kept (mobile-friendly alternative to pure sidebar nav). Layout shifts from role-grouped tile sections to department-centric cards. Mission admins gain access to user management and items within their departments. Item admins see items and vehicles only.

---

## Role Permissions Summary

| Capability | sysAdmin | missionAdmin | itemAdmin |
|---|---|---|---|
| Manage all users (global) | ✓ | — | — |
| Manage departments | ✓ | — | — |
| Manage specializations | ✓ | — | — |
| Training applications | ✓ | ✓ (own depts) | — |
| Services | ✓ | ✓ (own depts) | — |
| Users (dept-scoped) | ✓ | ✓ (own depts) | — |
| Items | ✓ | ✓ (own depts) | ✓ (own depts) |
| Vehicles | ✓ | ✓ (own depts) | ✓ (own depts) |

*missionAdmin inherits itemAdmin (already reflected in `auth_provider.dart`).*

---

## Layout

### Page Structure

```
AdminPanelScreen
├── _HeaderBar (unchanged)
├── [sysAdmin only] System Management section
│   └── 3 tiles: Users · Departments · Specializations
└── [per dept the user admins] _DeptAdminCard × N
    ├── Card header: dept name + role badge chips
    └── Compact action tiles (role-appropriate)
```

### _DeptAdminCard tiles

**missionAdmin in dept:**
- Training Requests (blue) → `/admin/training-applications`
- Services (green) → `/admin/services?departmentId=X`
- Users (red) → opens end-drawer (see below)
- Items (purple) → `/items?departmentId=X` (improved items screen, dept pre-filtered)
- Vehicles (amber) → `/vehicles`

**itemAdmin only in dept:**
- Items (purple) → `/items?departmentId=X` (improved items screen, dept pre-filtered)
- Vehicles (amber) → `/vehicles`

### Visual Style

- Colored icon tiles (kept from current design)
- Tiles inside each dept card: smaller/more compact than current top-level tiles
- Role badge chips in card header: `Αποστολών` (green), `Υλικού` (purple)
- Card: white background, subtle border (`Colors.grey.shade200`), `BorderRadius.circular(16)`
- Page background: `0xFFF5F7FA` (unchanged)
- Remove dead code: `_StatData`, `_StatsRow`, `_StatCard` (never rendered)

---

## User Drawer (Mission Admins)

Triggered by tapping the Users tile. Uses `Scaffold.endDrawer` + `GlobalKey<ScaffoldState>`.

### State machine (local to `_AdminPanelScreenState`)

```
_drawerDeptId      — which dept's users to show
_drawerSelectedUser — null = list view, non-null = detail view
```

### State 1 — User List

- Drawer header: dept name + close button + back button (hidden in list state)
- Search bar (filters by name/eame)
- List of dept members: `CircleAvatar` initials · full name · role badge · volunteer hours
- Tapping a row sets `_drawerSelectedUser` → transitions to State 2
- Data fetched from `/users/stats`, filtered client-side to members of `_drawerDeptId` (same pattern as `ManageUsersScreen._filterableDepts`)

### State 2 — User Detail

- Drawer header shows back arrow (→ returns to list) + user full name
- Renders `UserDetailScreen` content inline as a widget (not navigated to)
- `UserDetailScreen` must expose its body as a composable widget or the drawer renders it via a nested `Navigator` push within the drawer
- Full edit scope: name, roles, specializations, dept assignments

### Implementation note

`UserDetailScreen` currently builds a full `Scaffold`. To avoid double-scaffold nesting, extract its body into a `UserDetailBody(userId)` stateful widget. `UserDetailScreen` wraps it in a `Scaffold`; the drawer uses `UserDetailBody` directly.

---

## Items Screen Improvement

File: `frontend/lib/screens/items_screen.dart`

### Assigned user display

On each item card/row, add an assigned-user element:

- **Assigned:** `CircleAvatar` (initials, size 16) + assignee name in a grey pill row, positioned below the item name
- **Unassigned:** muted `Αδιάθετο` label (already present or add if missing)

No data removed. All existing fields (category, department, barcode, container hierarchy, expiration date) remain visible. Assigned user moves from detail-only to list-visible.

### Dept filter from admin panel

When navigated to from a dept admin card, `/items?departmentId=X` pre-selects the department filter. `ItemsScreen.initState` already reads `departmentId` from query params via GoRouter — confirm this is wired or add it.

---

## Files to Create / Modify

| File | Change |
|---|---|
| `frontend/lib/screens/admin_panel_screen.dart` | Full refactor: dept-centric cards, end-drawer, remove dead code |
| `frontend/lib/screens/user_detail_screen.dart` | Extract body into `UserDetailBody` widget |
| `frontend/lib/screens/items_screen.dart` | Surface assigned user on item cards; accept `departmentId` query param |

No changes to router, providers, backend, or other screens.

---

## Out of Scope

- Vehicles screen improvements
- ManageUsersScreen (sys admin full table view — unchanged)
- ManageServicesScreen (unchanged)
- Backend API changes
