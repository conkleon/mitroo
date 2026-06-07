# Delete Non-Synchronized Services from Inactive Tabs

**Date:** 2026-06-07

## Problem

Admins can delete services from the **active** tab, but not from the closed, completed, or finalized tabs. Manually-created services (no `externalMissionId`) that have moved through the lifecycle have no deletion path once they leave the active state.

## Goal

Allow admins to delete non-synchronized services (those where `externalMissionId` is null) from the closed, completed, and finalized tabs. Synchronized services keep no delete button in these tabs to prevent accidental removal of externally-managed records.

---

## Design

### Backend

No changes. `DELETE /api/services/:id` already:
- Has no lifecycle status guard — allows deletion of services in any state
- Requires `authenticate` middleware + `requireServiceAdmin` authorization
- Calls `writeBackServiceDelete()` (fire-and-forget; no-op for non-synchronized services)
- Cascades to `UserService`, `ItemService`, `FileAttachment`, `Chat`; nullifies `VehicleLog.serviceId` and `Victim.serviceId`

### Frontend

Three files receive identical changes: `closed_services_tab.dart`, `completed_services_tab.dart`, `finalized_services_tab.dart`.

#### 1. Add `_deleteService` method to each tab's State class

Copied verbatim from `active_services_tab.dart`:

```dart
Future<void> _deleteService(int id, String name) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Διαγραφή Υπηρεσίας'),
      content: Text(
          'Είστε σίγουροι ότι θέλετε να διαγράψετε "$name";\nΔεν μπορεί να αναιρεθεί.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Άκυρο')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
          child: const Text('Διαγραφή'),
        ),
      ],
    ),
  );
  if (confirmed != true || !mounted) return;

  final err = await context.read<ServiceProvider>().deleteService(id);
  if (!mounted) return;
  if (err != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  } else {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Η υπηρεσία διαγράφηκε')));
    _load(); // use _load(silent: true) for completed/finalized tabs
  }
}
```

> **Note:** `completed_services_tab.dart` and `finalized_services_tab.dart` use `_load(silent: true)` for background refreshes; use that variant in those two files.

#### 2. Wire `onDelete` in each tab's `ServiceCard(...)` call

```dart
onDelete: svc['externalMissionId'] == null
    ? () => _deleteService(id, svc['name'] as String)
    : null,
```

`ServiceCard` already renders its delete button only when `onDelete != null`, so this single condition gates the button on non-synchronized services.

---

## Affected Files

| File | Change |
|------|--------|
| `frontend/lib/widgets/closed_services_tab.dart` | Add `_deleteService` method; wire `onDelete` in `ServiceCard` call |
| `frontend/lib/widgets/completed_services_tab.dart` | Same; use `_load(silent: true)` in success path |
| `frontend/lib/widgets/finalized_services_tab.dart` | Same; use `_load(silent: true)` in success path |

---

## Out of Scope

- Active tab — behaviour unchanged (delete shown for all services regardless of sync status)
- Backend — no changes required
- `ServiceCard` — no changes required
- Adding delete to the user-facing `ServicesScreen`
