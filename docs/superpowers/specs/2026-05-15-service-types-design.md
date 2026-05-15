# Service Types Overhaul — Design Spec

**Date:** 2026-05-15
**Scope:** Replace the `missionCategories` JSON + `ServiceVisibility` denormalized table system with a proper `ServiceType` entity.

## Motivation

The current system maps external Mitroo mission types → string categories stored as JSON on specializations → denormalized `ServiceVisibility` records per service. This is brittle:
- Visibility records get stale when sync re-runs
- `missionCategories` JSON field is hard to query and easy to misconfigure
- No admin UI for managing service types independently
- The frontend PATCH for specializations was silently broken because of TS type issues

## Design

### Data Model

**New: `ServiceType`**

| Column | Type | Notes |
|--------|------|-------|
| `id` | serial PK | |
| `name` | text NOT NULL | Greek label, e.g. "ΝΑΥΑΓΟΣΩΣΤΙΚΗ ΚΑΛΥΨΗ" |
| `externalMissionTypeId` | int UNIQUE nullable | The numeric ID from old Mitroo (71, 56, 57, 36, 86, 33, 83, 60, 85, 16, 81). Null for manually created types. |
| `isDefaultVisible` | boolean NOT NULL DEFAULT false | When true, services of this type are visible to all department members regardless of specialization. |

Seed data: all 11 types from the old Mitroo mission_type_id dropdown.

**New: `SpecializationServiceType`**

| Column | Type |
|--------|------|
| `specializationId` | int FK → specializations |
| `serviceTypeId` | int FK → service_types |

Composite unique on `(specializationId, serviceTypeId)`.

**Changed: `Service`**
- Add `serviceTypeId` int FK → service_types (nullable during migration, required after data fix).

**Changed: `Specialization`**
- Drop `missionCategories` JSON column.

**Dropped: `ServiceVisibility`**

### Query-Time Visibility

Services visible to a user = services where:
- Service is in one of the user's departments **AND**
- (`serviceTypeId` is null **OR** `serviceType.isDefaultVisible = true` **OR** `serviceType.specializations` contains one of the user's specializations)

Null `serviceTypeId` (services without a type set) are treated as visible to all — a safety net. After migration and sync, all services will have a type.

No more denormalized visibility table — all filtering is live via Prisma joins through the FK chain.

### API Changes

**New: `GET /api/service-types`**
Returns all service types with `_count: { specializations: true }`.

**New: `POST /api/service-types`**
Admin creates a service type. Body: `{ name: string, externalMissionTypeId?: number, isDefaultVisible?: boolean }`.

**New: `PATCH /api/service-types/:id`**
Admin updates a service type.

**New: `DELETE /api/service-types/:id`**
Admin deletes a service type.

**New: `GET /api/service-types/:id/specializations`**
Returns specializations linked to this service type.

**New: `PUT /api/service-types/:id/specializations`**
Admin sets specialization assignments. Body: `{ specializationIds: number[] }`.

**Changed: `POST/PATCH /api/services`**
Accept and return `serviceTypeId`. No separate visibility endpoint calls needed.

**Changed: `GET /api/services/my`**
Filter via service_type chain instead of ServiceVisibility:
```
serviceType: {
  OR: [
    { isDefaultVisible: true },
    { specializations: { some: { specializationId: { in: userSpecIds } } } }
  ]
}
```

**Changed: `GET /api/services?specializationId=X`**
Filter via `serviceType: { specializations: { some: { specializationId: X } } }`.

**Dropped: `POST/DELETE /api/services/:id/visibility`**

### Sync Changes

`syncServiceVisibility` function is replaced by setting `serviceTypeId` on the service record during create/update. Look up `ServiceType` by `externalMissionTypeId` matching the mission's `mission_type_id`.

Remove these constants (no longer needed):
- `MISSION_CATEGORY_MAP`
- `TRAINER_MISSION_TYPE_IDS`, `TRAINING_MISSION_TYPE_IDS`, `TEP_MISSION_TYPE_IDS`, `VOLUNTEER_MISSION_TYPE_IDS`, `SANITARY_MISSION_TYPE_IDS`
- `getCategoriesForMissionType` function
- `BASE_CATEGORIES` logic (replaced by `isDefaultVisible` on `ServiceType`)

The `remapDefaultHoursByMissionType` logic is unchanged — hours routing is orthogonal to visibility.

### Frontend Changes

**New: `ManageServiceTypesScreen`**
Admin table showing all service types. Each row: name, specialization count, default-visible toggle. Tap to edit: name, external ID, toggle, and a specialization checkbox list.

**Changed: `CreateServiceScreen`**
Replace the multi-select specialization picker with a dropdown of the 11 service type names. Selecting the type sets `serviceTypeId` — visibility is derived from that alone.

**Changed: `SpecializationDetailScreen` / `ManageSpecializationsScreen`**
Replace the `missionCategories` chips with a "Service Types" checkbox list. Each specialization gets assigned which service types it can see.

**Changed: `ServicesScreen` / `ManageServicesScreen`**
Filter chips unchanged in UX — but backend filtering now goes through the ServiceType chain.

**Removed: `specialization_labels.dart`**
The old category label function is replaced by live service type names from the DB.

## Migration Strategy

1. Run the Prisma migration (add tables, drop column, drop table)
2. Seed the 11 `ServiceType` rows with correct `externalMissionTypeId` values
3. Wipe and re-sync all services — they pick up the correct `serviceTypeId` from the sync
4. Manually re-assign specialization → service type visibility in the admin UI
