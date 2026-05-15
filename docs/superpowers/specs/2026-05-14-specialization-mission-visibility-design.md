# Specialization Mission Visibility & Seeding

**Date**: 2026-05-14
**Branch**: `refactor-appearance`

## Overview

Replace the 4 English seeded specializations with 6 Greek ones, assign imported services to specializations based on mission type, and allow admins to customize which mission types each specialization can see.

## Database

### Schema change

Add `missionCategories` JSON column to `specializations`:

```prisma
missionCategories  Json     @default("[]") @map("mission_categories")
```

Stores an array of category strings, e.g. `["tep", "training", "volunteer"]`.

No new tables needed. `ServiceVisibility` (existing join table) remains the mechanism for service→specialization gating.

## Category definitions

| Category | Mission Type IDs | Notes |
|---|---|---|
| `trainer` | 71, 36, 86, 33, 83 | TRAINER_MISSION_TYPE_IDS |
| `training` | 81 | TRAINING_MISSION_TYPE_IDS |
| `tep` | 85 | TEP_MISSION_TYPE_IDS |
| `volunteer` | 56, 57 | VOLUNTEER_MISSION_TYPE_IDS |
| `sanitary_general` | 16 | SANITARY_MISSION_TYPE_IDS (general) |
| `sanitary_lifeguard` | 60 | SANITARY_MISSION_TYPE_IDS (lifeguard) |

Mapping function `getCategoriesForMissionType(id)` → `string[]` in `mitrooSync.ts`.

## Seed specializations (replacing old 4)

Base categories (visible to all): `training`, `volunteer`, `sanitary_general`

| # | Name | Categories (base + specific) |
|---|---|---|
| 1 | Δόκιμος Σαμαρείτης | base + `tep` |
| 2 | Δόκιμος Ναυαγοσώστης | base + `tep` |
| 3 | Σαμαρείτης | base only |
| 4 | Ναυαγοσώστης | base + `sanitary_lifeguard` |
| 5 | Εκπαιδευτής Α' Βοηθειών | base + `trainer` |
| 6 | Εκπαιδευτής Ναυαγοσωστικής | base + `trainer`, `sanitary_lifeguard` |

Old seed entries (First Aid, ALS, Lifeguard, BLS/AED Instructor) removed. Old `ServiceVisibility` seed block removed — import handles visibility dynamically. Keep admin + volunteer `UserSpecialization` assignments using new spec IDs.

## Import logic (`mitrooSync.ts`)

New function `syncServiceVisibility(serviceId, missionTypeId)`:

1. Resolve `missionTypeId` → category strings via `getCategoriesForMissionType`
2. Find specializations where `missionCategories` array intersects with resolved categories (Prisma `hasSome`)
3. Delete existing `ServiceVisibility` rows for that service
4. Insert rows for each matching specialization

Called from `syncServices` after both create and update branches (wrapped per-shift so failures don't abort the batch).

Hours logic (`remapDefaultHoursByMissionType`) unchanged — already works correctly.

## Backend API

### `specialization.routes.ts`

- Add `missionCategories` to Zod `createSchema`: `z.array(z.enum([...])).optional()`
- Field flows through POST and PATCH automatically
- GET returns the JSON column without changes

### Migration

Single Prisma migration: `ALTER TABLE specializations ADD COLUMN mission_categories JSON DEFAULT '[]'`.

## Frontend

### `manage_specializations_screen.dart` — Create dialog

Add `FilterChip` toggles with Greek labels below existing fields:

- Εκπαιδευτικές (trainer)
- Εκπαίδευση (training)
- ΤΕΠ (tep)
- Εθελοντικές (volunteer)
- Υγειονομικές Γενικές (sanitary_general)
- Υγειονομικές Ναυαγοσωστικές (sanitary_lifeguard)

Selected categories sent as `missionCategories` array in POST body.

### `specialization_detail_screen.dart`

- **Info card**: Display current `missionCategories` as labeled chips.
- **Edit dialog**: Same `FilterChip` toggles as create, pre-selected from current values. Sent in PATCH body.

## Files changed

| File | Change |
|---|---|
| `backend/prisma/schema.prisma` | Add `missionCategories` column |
| `backend/prisma/seed.ts` | Replace 4 old specs with 6 Greek ones, remove old visibility seeds |
| `backend/src/lib/mitrooSync.ts` | Add category map, `getCategoriesForMissionType`, `syncServiceVisibility`, call from `syncServices` |
| `backend/src/routes/specialization.routes.ts` | Add `missionCategories` to Zod schema |
| `frontend/lib/screens/manage_specializations_screen.dart` | Add category chips to create dialog |
| `frontend/lib/screens/specialization_detail_screen.dart` | Show categories in info card, add chips to edit dialog |
