---
name: past-services-lifecycle-filter
description: Add server-side lifecycle status filter chips to PastServicesScreen — default fetches only closed services, chips let admin toggle closed/completed/both
metadata:
  type: project
---

# Past Services Lifecycle Status Filter

## Overview

Add `FilterChip` widgets for "Κλειστές" and "Ολοκληρωμένες" to `PastServicesScreen`, backed by a new `lifecycleStatus` query param on `GET /services`. Default state fetches only `closed` services. Toggling chips re-fetches from the server.

## Backend

**File:** `backend/src/routes/service.routes.ts`

Add `lifecycleStatus` to the destructured query params on `GET /services`:

```ts
const { departmentId, includeEnrollments, fromDate, toDate, specializationId, pastOnly, includeExpired, lifecycleStatus } = req.query;
```

After the existing `pastOnly` block, add a lifecycle status filter:

```ts
if (lifecycleStatus) {
  const statuses = Array.isArray(lifecycleStatus) ? lifecycleStatus : [lifecycleStatus];
  where.lifecycleStatus = { in: statuses };
}
```

This is additive — no existing behaviour changes when `lifecycleStatus` is absent.

## Frontend

**File:** `frontend/lib/screens/past_services_screen.dart`

### State

Add one field to `_PastServicesScreenState`:

```dart
Set<String> _selectedLifecycleStatuses = {'closed'};
```

### `_load()` — query params

For each status in `_selectedLifecycleStatuses`, append `lifecycleStatus=<value>` to the query string. Since `Uri` / manual string building is already used, append them as repeated params:

```dart
for (final s in _selectedLifecycleStatuses) {
  params['lifecycleStatus'] = s; // last wins if using Map — use list instead
}
```

Use a `List<String>` of `key=value` pairs (or build the query manually) to support repeated params:

```dart
final parts = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').toList();
for (final s in _selectedLifecycleStatuses) {
  parts.add('lifecycleStatus=${Uri.encodeQueryComponent(s)}');
}
final query = parts.join('&');
```

### Filter chips UI

In the existing spec filter strip (after the search bar, before or alongside the specialization chips), add two `FilterChip` widgets:

- Label "Κλειστές" → value `'closed'`
- Label "Ολοκληρωμένες" → value `'completed'`

Toggle logic:
- On tap: add or remove the status from `_selectedLifecycleStatuses`
- **Constraint:** if toggling off would empty the set, ignore the tap (always at least one selected)
- After state change: call `_load()`

Visual: use the same `FilterChip` style already used for specialization chips. Selected chips use the theme's filled style; unselected are outlined.

## Data Flow

```
User taps chip
  → setState: toggle status in _selectedLifecycleStatuses (min 1)
  → _load(): builds query with lifecycleStatus= params + existing filters
  → GET /services?departmentId=X&pastOnly=true&lifecycleStatus=closed[&lifecycleStatus=completed]&...
  → Backend: where.lifecycleStatus = { in: ['closed'] } (or both)
  → Response: filtered list
  → setState: _services = result
  → _filtered getter: applies search on top
  → UI rebuilds
```

## Error Handling

No new error paths — follows existing `_load()` try/catch which silently handles failures and sets `_loading = false`.

## Out of Scope

- No change to `_filtered` getter (search still applies client-side on whatever server returned)
- No change to any other screen
- No migration — `lifecycleStatus` column already exists
