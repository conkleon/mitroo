# Mobile Filter UX Improvements

**Date:** 2026-05-17  
**Status:** Approved

## Problem

On mobile, each main screen wastes vertical space with a redundant page title (the bottom nav already communicates context) and always-visible filter controls that most users don't need on every visit. This is especially painful on the Services screen which stacks a branded title, action bar, specialization chips, and tab bar before any content appears.

## Goal

Remove page titles and make secondary filters collapsible (hidden by default, revealed on tap) across all main screens, while keeping primary actions (search, action buttons) always visible.

## Scope

Five main screens accessed via bottom navigation:
1. **ServicesScreen** — `screens/services_screen.dart`
2. **VictimsScreen** — `screens/victims_screen.dart`
3. **ItemsScreen** — `screens/items_screen.dart`
4. **VehiclesScreen** — `screens/vehicles_screen.dart`
5. **DepartmentsScreen** — `screens/departments_screen.dart`

## Design

### 1. Remove page titles (all screens)

- **ServicesScreen**: Remove the `SliverToBoxAdapter` containing the branded "Υπηρεσίες" title row (red bar + text).
- **VictimsScreen**: Remove the `AppBar` (currently `appBar: AppBar(title: Text('Περιστατικά'))`). The screen becomes a plain `Scaffold` with no `appBar`.
- **VehiclesScreen**: Remove the `AppBar` title if present.
- **DepartmentsScreen**: Remove the `AppBar` title if present.
- **ItemsScreen**: Remove any title header row if present.

### 2. Collapsible filter panel

**Collapse behavior:**
- A "Φίλτρα" toggle button controls a `bool _filtersExpanded` state variable (default `false`).
- Filter panel uses `AnimatedContainer` with `height` animated between `0` and its natural height, with `ClipRect` to prevent overflow during animation. Duration: 200ms, curve: `Curves.easeInOut`.
- Panel state is kept in screen `State` (resets on navigation, no persistence needed).

**Filter button style:**
- Compact `OutlinedButton.icon` or `TextButton.icon` with `Icons.tune_rounded` and label "Φίλτρα".
- When any secondary filter is active: button changes to filled/colored style and shows an active count badge (e.g. `"Φίλτρα (2)"`).
- Positioned to the right of the search bar (Victims, Items) or as a standalone row above the tab bar (Services).

### 3. Per-screen changes

#### ServicesScreen
- **Remove**: branded title row (`SliverToBoxAdapter` with "Υπηρεσίες").
- **Keep**: top action bar (my-services button, equipment badge, profile avatar) — these are actions.
- **Collapse**: specialization filter chips behind a "Φίλτρα" button placed between the action bar and the tab bar.
- **Keep**: tab bar (List / Ημερολόγιο) always visible — it's primary navigation.
- Active indicator: button shows filled style when `_selectedSpecId != null`.

#### VictimsScreen
- **Remove**: `AppBar` entirely.
- **Keep**: search `TextField` always visible.
- **Collapse**: date range row + status `_FilterRow` chips into expandable panel.
- **Filter button**: sits to the right of the search bar as an icon button (`Icons.tune_rounded`), badge shows count of active secondary filters (date from, date to, status ≠ 'all').

#### ItemsScreen
- **Remove**: any title header row.
- **Keep**: search `TextField` always visible.
- **Collapse**: department dropdown + category filter into expandable panel.
- Same filter button pattern as Victims.

#### VehiclesScreen
- **Remove**: `AppBar` title / any header. No filters to collapse.

#### DepartmentsScreen
- **Remove**: `AppBar` title / any header. Search (if present) stays visible.

### 4. Active filter badge

Helper: count active secondary filters → show as `"Φίλτρα (N)"` or just a colored dot on the icon button. Use a simple integer count per screen, no shared widget needed.

## What is NOT changing

- Bottom navigation bar
- Top action bar in ServicesScreen (my-services, equipment, profile)
- Tab bar (List/Calendar) in ServicesScreen
- Search bar in any screen — always visible
- Pagination bar in VictimsScreen
- All desktop layout (≥900px breakpoint in ShellScreen) — these changes are safe on all widths since the collapsible panel just gives back space; no breakpoint-specific code needed

## Implementation notes

- `AnimatedContainer` wrapping the filter panel with `ClipRect` child to avoid content bleeding during animation.
- Filter state (`_filtersExpanded`) added as a `bool` field on each screen's `State`.
- No new shared widgets needed — each screen implements its own collapse inline (they differ enough that abstraction would be premature).
