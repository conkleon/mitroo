# Service Card Simplification & Per-Service Mitroo Sync

**Date:** 2026-06-07

## Problem

The admin service management screen (`ManageServicesScreen`) is visually crowded. Specifically:

- The participant count is shown **twice** on each card — once in the content row (left side) and once in the right-side action column toggle.
- There is no way to sync a single service with the original mitroo system; the only option is a full department-level sync from the app bar.

## Goals

1. Remove the duplicate participant count from the card content row.
2. Add a per-service sync icon (only for mitroo-linked services) that triggers a targeted sync of that specific service.

---

## Design

### 1. Card Simplification — `frontend/lib/widgets/service_card.dart`

**Remove** from `_buildCardContent` (the info row inside the card):
- `Icons.people` + `enrolledCount` text (lines 308–314)
- The pending-requests badge (`requestedCount` container, lines 315–331)

**Keep:**
- Location icon + text
- Calendar icon + date
- Specialization badges
- Responsible-user chip

The participant count and pending-requests badge remain exclusively in `_buildActionColumn` (the right-side toggle), which already shows them clearly.

### 2. Sync Icon — `frontend/lib/widgets/service_card.dart`

Add an optional `onSync` callback to `ServiceCard`:

```dart
final VoidCallback? onSync;
```

In `_buildActionColumn`, after the existing action buttons, render a sync icon button **only when** `service['externalMissionId'] != null`:

- **Icon:** `Icons.cloud_sync` (or `Icons.sync`) with a teal/primary color
- **Loading state:** Replace icon with a `SizedBox(width:14, height:14, child: CircularProgressIndicator(strokeWidth: 1.5))` while syncing
- **Tap:** calls `onSync`
- **Tooltip:** `'Συγχρονισμός με Mitroo'`

Loading state is managed locally in `ServiceCard` (stateful widget change needed, or pass `isSyncing` bool from parent).

### 3. Wire-up in Tab Widgets

All four tab widgets (`active_services_tab.dart`, `closed_services_tab.dart`, `completed_services_tab.dart`, `finalized_services_tab.dart`) pass a new `onSync` handler to `ServiceCard`:

```dart
onSync: () => _syncSingleService(svc['id'] as int),
```

The handler:
1. Calls `POST /api/services/:id/sync`
2. On success, calls `_load()` to refresh the tab list

### 4. Expose `externalMissionId` in Service List API — `backend/src/routes/service.routes.ts`

Add `externalMissionId: true` to the `select` clause of the service list query so the frontend receives the field and can conditionally render the sync icon.

### 5. Backend: Per-Service Sync Function — `backend/src/lib/mitrooSync.ts`

New exported function:

```ts
export async function syncSingleService(serviceId: number): Promise<SyncResult>
```

**Note:** The external mitroo API has no per-mission endpoint. Missions are only available via paginated list endpoints (`fetchMissionPage`). The implementation scans pages until it finds the matching mission.

Implementation:
1. Look up the service: `{ externalMissionId, departmentId, lifecycleStatus }`
2. If `externalMissionId` is null, return `{ errors: ['No external mission ID'] }`
3. Get the mitroo client via `getClient(departmentId)`
4. Map `lifecycleStatus` → external API status string (`active→open`, `closed→closed`, `completed→finished`, `finalized→finalized`)
5. Page-scan `fetchMissionPage(extStatus, skip, 200)` with `$orderby=id+desc` until the matching mission is found (stops on first match or end of pages). Active missions ordered newest-first typically appear on page 1.
6. If not found, return with error (service may have been removed from external system)
7. Call `processMissions(departmentId, [mission], client, result)` (internal helper, same file)
8. Call `syncShiftApplications(departmentId)` to sync enrollment statuses
9. Update sync status via `setSyncStatus`

### 6. Backend: New Endpoint — `backend/src/routes/service.routes.ts`

```
POST /api/services/:id/sync
```

- **Auth:** `authenticate` middleware (already on all service routes)
- **Authorization:** `isMissionAdminInDepartment(userId, service.departmentId)` — same guard as other sync endpoints
- **Handler:** calls `syncSingleService(serviceId)`, returns `{ ok: true, ...result }`
- **Error:** 404 if service not found, 403 if not authorized, 400 if no externalMissionId

---

## Affected Files

| File | Change |
|------|--------|
| `frontend/lib/widgets/service_card.dart` | Remove duplicate count; add `onSync` callback + sync icon |
| `frontend/lib/widgets/active_services_tab.dart` | Wire `onSync` → `_syncSingleService` |
| `frontend/lib/widgets/closed_services_tab.dart` | Same |
| `frontend/lib/widgets/completed_services_tab.dart` | Same |
| `frontend/lib/widgets/finalized_services_tab.dart` | Same |
| `backend/src/routes/service.routes.ts` | Add `externalMissionId` to select; add `POST /:id/sync` endpoint |
| `backend/src/lib/mitrooSync.ts` | Add `syncSingleService(serviceId)` |

---

## Out of Scope

- Syncing services that were created manually (no `externalMissionId`) — icon is hidden for these
- Changing the sync behavior for the app-bar refresh button
- Any changes to the user-facing `ServicesScreen` (calendar/list view)
