# Victims Table View Refactor

## Goal

Replace the card-based victims list with a paginated table view showing name, date added, and chief complaint. Add server-side search and date-range filtering. Preserve the existing status filter chips.

## Backend Changes

### `GET /api/victims` — new query params

| Param | Type | Default | Description |
|---|---|---|---|
| `search` | string | — | Filters by `name` (case-insensitive contains) |
| `dateFrom` | ISO date | — | Filters `createdAt >= dateFrom` |
| `dateTo` | ISO date | — | Filters `createdAt <= dateTo` (end of day) |
| `status` | `open` \| `finalized` | — | Filters by `isFinalized` |
| `page` | int | 1 | Page number |
| `limit` | int | 20 | Rows per page |
| `serviceId` | int | — | Existing param, preserved |

### Response shape change

From a flat array to:

```json
{
  "data": [ ... ],
  "total": 57,
  "page": 1,
  "limit": 20
}
```

### Select change

Add `chiefComplaint` to the list query's `select`. Keep all existing fields.

### Implementation notes

- Counting uses a separate `prisma.victim.count()` with the same `where` for accurate pagination totals.
- `dateTo` is interpreted as end-of-day (23:59:59.999) inclusive.
- Status filter wire-up: `status=open` → `isFinalized: false`, `status=finalized` → `isFinalized: true`.

## Frontend Changes

### VictimProvider

Add optional filter params to `fetchVictims`:

```dart
Future<void> fetchVictims({
  String? search,
  String? dateFrom,
  String? dateTo,
  String? status,
  int page = 1,
  int limit = 20,
});
```

Build query string from provided params. Store `_total` and `_currentPage` fields with getters.

### VictimsScreen

#### Layout (top to bottom)

1. **Search bar** — `TextField` with search icon, debounced ~300ms before firing API call
2. **Date range row** — two inline date pickers ("Από" / "Έως") using `showDatePicker`
3. **Status filter chips** — existing All / Open / Finalized chips, preserved as-is
4. **Table** — `DataTable` with columns: Name, Date Added, Chief Complaint
   - Alternating row colors (white / light gray)
   - Tappable rows → navigate to victim detail
   - "Δεν υπάρχουν περιστατικά" empty state when no results
   - Loading indicator while fetching
5. **Pagination** — row of page buttons below the table: `< 1 2 3 ... >`
6. **FAB** — preserved for creating new victims

#### State management

- All filter changes reset to page 1
- Debounce on search input (300ms Timer)
- Date pickers use `showDatePicker` with Greek locale; cleared via a reset icon

#### API call trigger

Any filter/page change calls `provider.fetchVictims(...)` with the full current parameter set.

### Table columns detail

| Column | Source field | Format |
|---|---|---|
| Name | `name` | Text, bold, overflow ellipsis |
| Date Added | `createdAt` | `dd/MM/yyyy HH:mm` localized |
| Chief Complaint | `chiefComplaint` | Text, max 2 lines, overflow ellipsis; "—" if empty |

## Preserved behavior

- FAB to create new victim
- Status filter chips
- Pull-to-refresh (RefreshIndicator wrapping the entire Column)
- Tapping a row navigates to `/victims/:id`
