# Finalized Missions Sync — Design

## Summary

Add a new "Sync Finalized" button in the department detail screen that syncs missions exclusively from the external `GridGetMissions/finalized/` endpoint. This is a separate data source from the already-supported `finished/` endpoint.

## Motivation

The existing sync fetches from `open`, `closed`, and `finished` endpoints. The external Mitroo system also exposes a `finalized/` endpoint that returns a different set of missions. Department admins need a way to pull these finalized missions into the local system.

## Architecture

A new standalone sync path, parallel to the existing "Sync Services", hitting only the `finalized/` endpoint.

## Changes

### Backend

**`mitrooClient.ts`** — New `fetchFinalizedMissions()` method:
- Paginates over `/index.php/ajaxdptadmin/GridGetMissions/finalized/?$count=true&$skip=X&$top=200`
- Same pattern as `fetchFinishedMissions()` but uses the `finalized` URL
- Returns `ExternalMission[]`

**`mitrooSync.ts`** — New `syncFinalizedServices(departmentId)` function:
- Calls `client.fetchFinalizedMissions()`
- Upserts each mission as a Service (same dedup/upsert logic as existing sync)
- Maps mission status to lifecycle status via `mapMissionStatus`
- Syncs shift applications afterward via `syncShiftApplications`
- Records sync status in `DepartmentSyncConfig`

**`sync.routes.ts`** — New `POST /departments/:id/sync/finalized` route:
- Authenticated, same `requireSyncAdmin` guard (admin or missionAdmin)
- Calls `syncFinalizedServices()` and returns `{ created, updated, errors }`

### Frontend

**`sync_service.dart`** — New `triggerFinalizedSync(deptId)` → `POST /departments/{id}/sync/finalized`

**`sync_provider.dart`** — New `isSyncingFinalized` state, `syncFinalized()` action

**`sync_config_card.dart`** — New `_SyncRow` labeled "Ολοκληρωμένες" below the existing "Υπηρεσίες" row

## Data Flow

```
Button tap → SyncProvider.syncFinalized()
  → SyncService.triggerFinalizedSync(deptId)
    → POST /api/departments/:id/sync/finalized
      → syncFinalizedServices(departmentId)
        → mitrooClient.fetchFinalizedMissions()
        → for each mission: upsert Service via externalMissionId/externalShiftId
        → syncShiftApplications(departmentId)
      → { created, updated, errors }
  → Snackbar with result counts
```

## Error Handling

- Per-mission errors collected in `errors[]`, processing continues
- Fatal errors caught, sync status set to `"failed"` with error message
- Frontend shows red snackbar on failure, green-tinted snackbar with counts on success

## UI

A third `_SyncRow` in the existing `SyncConfigCard`:

```
┌──────────────────────────────────────────┐
│ 🔄 Συγχρονισμός Mitroo            ✓     │
│                                          │
│ [credentials fields...]                  │
│ [auto-sync toggle...]                    │
│ [Save button]                            │
│ ──────────────────────────────────────── │
│ Χρήστες          Τελευταίος: ...  [Sync] │
│ Υπηρεσίες        Τελευταίος: ...  [Sync] │
│ Ολοκληρωμένες    Τελευταίος: ...  [Sync] │  ← NEW
└──────────────────────────────────────────┘
```
