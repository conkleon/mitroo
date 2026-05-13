# My Equipment Sheet Refactor — Design

## Scope

Refactor `MyEquipmentSheet` (the bottom sheet at `frontend/lib/screens/my_equipment_sheet.dart`) to be more polished and professional. The primary UX change: replace the single generic scan button (which opens a QR-vs-barcode choice dialog) with two separate, prominent scan entry points that live alongside the search bar.

## Overall Sheet Structure

- Drag handle (centered, 5px thick)
- Tab bar: Equipment (count badge) / Vehicles (unchanged)
- Content area: constrained height, shrinkWrap list

## Equipment Tab — "My Equipment" Mode (default)

Refined item cards:
- White background, subtle grey border, 12px radius
- Left: icon container with item accent color at 20% opacity
- Middle: name (bold), barcode/location subtitle
- Right: "open detail" icon (muted) + "return" icon (red)
- Expired items: red-tinted background + "Έληξε" badge
- Empty state: outlined check icon + text

## Equipment Tab — "Take Equipment" Mode (search)

Toggled via the "Λήψη" button. Contains:

### Header row
- "Αναζήτηση Εξοπλισμού" title + back button to return to "My Equipment"

### Search bar
- Unchanged: outlined text field, filters available items by name/barcode

### Two scan panels (new — vertical stack, 12px gap)

Each panel: 64px-tall outlined container.

| Property | QR Code panel | Barcode panel |
|---|---|---|
| Icon | `Icons.qr_code` | `Icons.barcode_reader` |
| Icon color | Indigo (`#6366F1`) | Teal (`#0D9488`) |
| Title | "Σάρωση QR Code" | "Σάρωση Barcode" |
| Subtitle | "Σάρωση κωδικού QR με κάμερα" | "Σάρωση barcode με κάμερα" |
| Border | Indigo at 30% opacity | Teal at 30% opacity |
| Background | White with indigo tint (6%) | White with teal tint (6%) |

Layout of each panel: `[44px filled icon circle] — [title + subtitle] — [chevron]`

On tap: opens camera scanner directly (no intermediate dialog), with the appropriate mode pre-selected.

### Results list
- Unchanged: available items with "Λήψη" button

## Vehicles Tab

Unchanged from current implementation.

## Files Changed

- `frontend/lib/screens/my_equipment_sheet.dart` — main refactor target
- `frontend/lib/screens/scanner_screen.dart` — may need minor changes to accept initial scan mode

## What Stays the Same

- `ItemProvider` and API client calls — no backend changes
- Vehicle tab entirely
- The `_selfAssignItem`, `_returnItem`, `_fetchAvailableItems` methods (cosmetic cleanup only)
- `showScanChoiceDialog` — kept for the `items_screen.dart` FAB flow, not used in this sheet anymore
