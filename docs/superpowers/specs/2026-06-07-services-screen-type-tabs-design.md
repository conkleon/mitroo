# Services Screen — Service-Type Tab Refactor

**Date:** 2026-06-07  
**File:** `frontend/lib/screens/services_screen.dart`

## Summary

Replace the collapsible specialization filter (filter button + bubble row) with a dynamic pill-style tab bar where each tab corresponds to a `serviceType`. Tab bar is hidden when fewer than two distinct service types are present in the loaded data.

## State Changes

**Remove:**
- `int? _selectedSpecId`
- `bool _filtersExpanded`
- `int _countForSpec(int specId)` helper method
- `List<dynamic> get _filteredServices` (replaced)

**Add:**
- `int? _selectedServiceTypeId` — the currently selected service type ID; `null` means no explicit selection (falls back to first available type when tabs are shown)

## Data Derived in `build()`

```dart
// 1. Build ordered map: serviceTypeId → name
final serviceTypeMap = <int, String>{};
for (final svc in allServices) {
  final st = svc['serviceType'] as Map<String, dynamic>?;
  if (st == null) continue;
  serviceTypeMap[st['id'] as int] = st['name'] as String? ?? '';
}
final serviceTypes = serviceTypeMap.entries.toList()
  ..sort((a, b) => a.value.compareTo(b.value)); // stable alphabetical order

// 2. Count services per type
final countPerType = <int, int>{};
for (final svc in allServices) {
  final st = svc['serviceType'] as Map<String, dynamic>?;
  if (st == null) continue;
  final id = st['id'] as int;
  countPerType[id] = (countPerType[id] ?? 0) + 1;
}

// 3. Visibility + effective selection
final showTypeTabs = serviceTypes.length >= 2;
final effectiveTypeId = showTypeTabs
    ? (serviceTypes.any((e) => e.key == _selectedServiceTypeId)
        ? _selectedServiceTypeId
        : serviceTypes.first.key)
    : null;
```

`effectiveTypeId` is computed on-the-fly in `build()` — no `setState` needed to handle a stale selection after a refresh.

## Filtering

Replace the old getter with a method:

```dart
List<dynamic> _getFilteredServices(int? typeId) {
  final all = context.read<ServiceProvider>().services;
  if (typeId == null) return all;
  return all.where((s) {
    final st = s['serviceType'] as Map<String, dynamic>?;
    if (st == null) return false;
    return (st['id'] as int) == typeId;
  }).toList();
}
```

Called as `_getFilteredServices(effectiveTypeId)` wherever `_filteredServices` was previously used (list view, calendar view).

## UI Structure

```
┌─────────────────────────────────────────────┐
│  [Οι υπηρεσίες μου]           [📦] [Avatar] │  ← unchanged top bar
├─────────────────────────────────────────────┤
│  [ Λίστα          │       Ημερολόγιο ]      │  ← unchanged view toggle
├─────────────────────────────────────────────┤
│  [ Κάλυψη (3)   Εκπαίδευση (1)   ΤΕΠ (2) ] │  ← NEW (hidden if < 2 types)
├─────────────────────────────────────────────┤
│  Service list / calendar (filtered)         │
└─────────────────────────────────────────────┘
```

### Tab Bar Widget

- Container: `height: 44`, white background, `border-radius: 12`, `Border.all(Color(0xFFE5E7EB))`
- `SingleChildScrollView(scrollDirection: Axis.horizontal)` with `padding: EdgeInsets.all(3)`
- Each tab: `AnimatedContainer` with `duration: 200ms`
  - Selected: `color: cs.primary`, `borderRadius: 10`, white bold text
  - Unselected: transparent background, `Color(0xFF6B7280)` medium-weight text
- Tab label: `'$typeName ($count)'`
- `onTap`: `setState(() => _selectedServiceTypeId = typeId)`

### Visibility

```dart
if (showTypeTabs)
  SliverToBoxAdapter(child: /* tab bar widget */)
```

Placed between the view toggle sliver and the list/calendar sliver. Hidden entirely (no `SizedBox`) when `showTypeTabs` is false.

## Edge Cases

| Scenario | Behaviour |
|---|---|
| All services share one type | Tab bar hidden; all services shown |
| No service has a `serviceType` | Tab bar hidden; all services shown |
| Selected type absent after refresh | `effectiveTypeId` resets to first type silently |
| Many types (> fits on screen) | Tab bar scrolls horizontally |

## Out of Scope

- No "All" tab — tabs always show a single type's services
- No persistence of selected service type between sessions
- No changes to the List/Calendar view toggle (`_tabController`)
- No changes to the calendar view internals or the "My Services" bottom sheet
