# Delete Non-Synchronized Services from Inactive Tabs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a delete button to closed, completed, and finalized service tabs, shown only for non-synchronized services (`externalMissionId == null`).

**Architecture:** `ServiceCard` already has an `onDelete: VoidCallback?` prop — it renders a delete button when the callback is non-null. Each of the three inactive tabs gets a `_deleteService` method (confirmation dialog → `ServiceProvider.deleteService` → reload + snackbar) and passes `onDelete` conditionally based on `externalMissionId`. No backend or `ServiceCard` changes needed.

**Tech Stack:** Flutter/Dart, `provider` package (`context.read<ServiceProvider>()`), `GoRouter` (`context.push`)

---

## File Map

| File | Change |
|------|--------|
| `frontend/lib/widgets/closed_services_tab.dart` | Add `_deleteService` method; wire `onDelete` in `ServiceCard` call |
| `frontend/lib/widgets/completed_services_tab.dart` | Same; success path uses `_load(silent: true)` |
| `frontend/lib/widgets/finalized_services_tab.dart` | Same; success path uses `_load(silent: true)` |

---

## Task 1: Wire delete in `closed_services_tab.dart`

**Files:**
- Modify: `frontend/lib/widgets/closed_services_tab.dart`

### Background

- `_syncSingleService` is at line 512; `_assignResponsible` follows at line 528. Add `_deleteService` between them.
- The `ServiceCard` call is at line 883. `onSync`/`isSyncing` are the last two params (lines 907–908). Add `onDelete` after them.
- A `name` variable is already extracted on line 882: `final name = svc['name'] ?? '';`
- `_load()` takes no arguments in this file.

### Steps

- [ ] **Step 1: Add `_deleteService` method**

  Insert after `_syncSingleService` (after line 526), before `_assignResponsible`:

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
      _load();
    }
  }
  ```

- [ ] **Step 2: Wire `onDelete` in the `ServiceCard` call**

  Find the `ServiceCard(...)` call (line 883). Add `onDelete` as the last parameter, after `isSyncing`:

  ```dart
  isSyncing: _syncingServiceIds.contains(id),
  onDelete: svc['externalMissionId'] == null
      ? () => _deleteService(id, name)
      : null,
  ```

- [ ] **Step 3: Verify analyze is clean**

  ```
  cd frontend
  flutter analyze lib/widgets/closed_services_tab.dart
  ```

  Expected: no new errors or warnings in this file.

- [ ] **Step 4: Commit**

  ```bash
  git add frontend/lib/widgets/closed_services_tab.dart
  git commit -m "feat(ui): add delete for non-synced services in closed tab"
  ```

---

## Task 2: Wire delete in `completed_services_tab.dart`

**Files:**
- Modify: `frontend/lib/widgets/completed_services_tab.dart`

### Background

- `_syncSingleService` is at line 257. Add `_deleteService` immediately after it (after its closing `}`).
- The `ServiceCard` call is at line 604. `onSync`/`isSyncing` are the last two params (lines 617–618).
- No `name` variable is extracted in the `itemBuilder` — add it after `final id`.
- This file uses `_load(silent: true)` for background refreshes; use that in the success path.

### Steps

- [ ] **Step 1: Add `_deleteService` method**

  Insert after `_syncSingleService` (after its closing `}`, approximately line 270):

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
      _load(silent: true);
    }
  }
  ```

- [ ] **Step 2: Extract `name` variable in the `itemBuilder`**

  Find the block around line 603:
  ```dart
  final id = svc['id'] as int;
  return ServiceCard(
  ```

  Change to:
  ```dart
  final id = svc['id'] as int;
  final name = svc['name'] as String? ?? '';
  return ServiceCard(
  ```

- [ ] **Step 3: Wire `onDelete` in the `ServiceCard` call**

  Add `onDelete` after `isSyncing` (line 618):

  ```dart
  isSyncing: _syncingServiceIds.contains(id),
  onDelete: svc['externalMissionId'] == null
      ? () => _deleteService(id, name)
      : null,
  ```

- [ ] **Step 4: Verify analyze is clean**

  ```
  cd frontend
  flutter analyze lib/widgets/completed_services_tab.dart
  ```

  Expected: no new errors or warnings in this file.

- [ ] **Step 5: Commit**

  ```bash
  git add frontend/lib/widgets/completed_services_tab.dart
  git commit -m "feat(ui): add delete for non-synced services in completed tab"
  ```

---

## Task 3: Wire delete in `finalized_services_tab.dart`

**Files:**
- Modify: `frontend/lib/widgets/finalized_services_tab.dart`

### Background

- `_syncSingleService` is at line 239. Add `_deleteService` immediately after it (after its closing `}`).
- The `ServiceCard` call is at line 483. `onSync`/`isSyncing` are the last two params (lines 492–493).
- No `name` variable is extracted in the `itemBuilder` — add it after `final id`.
- This file uses `_load(silent: true)` for background refreshes; use that in the success path.

### Steps

- [ ] **Step 1: Add `_deleteService` method**

  Insert after `_syncSingleService` (after its closing `}`, approximately line 257):

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
      _load(silent: true);
    }
  }
  ```

- [ ] **Step 2: Extract `name` variable in the `itemBuilder`**

  Find the block around line 482:
  ```dart
  final id = svc['id'] as int;
  return ServiceCard(
  ```

  Change to:
  ```dart
  final id = svc['id'] as int;
  final name = svc['name'] as String? ?? '';
  return ServiceCard(
  ```

- [ ] **Step 3: Wire `onDelete` in the `ServiceCard` call**

  Add `onDelete` after `isSyncing` (line 493):

  ```dart
  isSyncing: _syncingServiceIds.contains(id),
  onDelete: svc['externalMissionId'] == null
      ? () => _deleteService(id, name)
      : null,
  ```

- [ ] **Step 4: Verify analyze is clean**

  ```
  cd frontend
  flutter analyze lib/widgets/finalized_services_tab.dart
  ```

  Expected: no new errors or warnings in this file.

- [ ] **Step 5: Commit**

  ```bash
  git add frontend/lib/widgets/finalized_services_tab.dart
  git commit -m "feat(ui): add delete for non-synced services in finalized tab"
  ```

---

## Manual Verification (after all tasks)

Start the dev environment and open the admin service management screen.

- [ ] In a **closed** tab: a non-synced service shows a red delete icon; tapping it shows the confirmation dialog; confirming deletes the service and reloads the list.
- [ ] In a **closed** tab: a synced service (has `externalMissionId`) shows **no** delete icon.
- [ ] Same checks for **completed** and **finalized** tabs.
- [ ] The **active** tab is unchanged — delete icon visible for all services regardless of sync status.
- [ ] Cancelling the confirmation dialog leaves the service in place.
