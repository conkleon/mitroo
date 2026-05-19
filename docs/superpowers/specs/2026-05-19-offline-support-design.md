# Offline Support Design

**Date:** 2026-05-19
**Status:** Approved

## Goal

Allow users to log in, view data, and submit victim reports regardless of network status. When connectivity is restored, queued reports sync automatically on user request.

## Scope

- Offline app load (service worker app-shell cache)
- Offline login (cached user profile)
- Offline victim report creation (local outbox queue, explicit sync UX)
- Stale read data for items, vehicles, and services (last-fetch snapshot)

Out of scope: offline creation of items/vehicles/services, background sync without user action, IndexedDB.

---

## Architecture

### Storage Layer

All persistent offline state lives in **`SharedPreferences`** (`localStorage` in the browser). No new dependencies.

| Key | Content | Written by | Read by |
|-----|---------|-----------|---------|
| `jwt_token` | JWT string | `ApiClient` | `ApiClient` |
| `cached_user` | JSON string — full `/auth/me` response | `AuthProvider` | `AuthProvider` |
| `offline_victim_outbox` | JSON string — `List<Map>` of pending report payloads | `OfflineStore` | `OfflineStore` / `VictimProvider` |
| `cached_services` | JSON string — last `/services/my` response body | `ServiceProvider` | `ServiceProvider` |
| `cached_items` | JSON string — last `/items` response body | `ItemProvider` | `ItemProvider` |
| `cached_vehicles` | JSON string — last `/vehicles` response body | `VehicleProvider` | `VehicleProvider` |

---

## Section 1: Service Worker — App Shell Caching

**File:** `frontend/web/sw.js`

On `install`, the SW fetches and caches a fixed list of shell assets into a versioned cache (`mitroo-shell-v1`):

```
/, /index.html, /main.dart.js, /flutter.js,
/manifest.json, /icons/Icon-192.png, /icons/Icon-512.png
```

> **Implementation note:** Exact filenames must be verified against `flutter build web` output — Flutter may split `main.dart.js` into deferred chunks in release mode. The implementation plan should run a build and adjust the list accordingly.

On `fetch`:
- Navigation requests (HTML) → cache-first, fall back to network
- All other requests → network passthrough (unchanged from today)

The `activate` event deletes any old cache versions to avoid stale shell assets after deploys.

API calls (`/api/*`) are never intercepted by the SW — offline API handling is done entirely in Dart.

---

## Section 2: Offline Detection

**New file:** `frontend/lib/services/connectivity_service.dart`

Static service using `dart:js_interop`:
- `static bool get isOnline` — reads `window.navigator.onLine`
- `static Stream<bool> onConnectivityChanged` — listens to `window` `online`/`offline` events via a `StreamController.broadcast()`

**New file:** `frontend/lib/providers/connectivity_provider.dart`

`ChangeNotifier` that:
- Subscribes to `ConnectivityService.onConnectivityChanged` in its constructor
- Exposes `bool isOnline` getter
- Calls `notifyListeners()` on every change

Added to `MultiProvider` in `main.dart` before domain providers.

No polling. No extra dependency.

---

## Section 3: Offline Login

**Modified file:** `frontend/lib/providers/auth_provider.dart`

Three changes only:

1. **Cache write** — after every successful `_loadCurrentUser()`, write `jsonEncode(_user)` to SharedPreferences under `cached_user`.

2. **Cache read** — in `_tryAutoLogin`, the catch block becomes:
   - If JWT is present and `cached_user` exists in SharedPreferences, decode and set `_user` from it.
   - If no cached blob, `_user` stays null — login screen shows normally.

3. **Cache clear** — `logout()` removes `cached_user` alongside the JWT.

No new files. No UI change. The router guard (`auth.loading` check) already handles the async resolution.

**Edge case:** If the JWT has expired server-side, the next online request will return 401. Providers already handle non-200 responses gracefully; no special handling needed here.

---

## Section 4: Victim Report Outbox

**New file:** `frontend/lib/services/offline_store.dart`

Static service with three methods:
- `static Future<void> saveVictimReport(Map<String, dynamic> payload)` — loads the list, appends, writes back
- `static Future<List<Map<String, dynamic>>> getPendingVictimReports()` — reads and decodes the list
- `static Future<void> removePendingVictimReport(int index)` — removes one entry by index, writes back

**Modified file:** `frontend/lib/providers/victim_provider.dart`

- `createVictim()` wraps its POST in try/catch. On network error, calls `OfflineStore.saveVictimReport(data)` and returns `null` (success path) with `_pendingCount` incremented. The caller (screen) receives `null` and navigates normally — the difference is surfaced by the banner, not the form.
- New `int _pendingCount` field loaded from `OfflineStore` in `initState`-equivalent (`_loadPendingCount()`).
- `int get pendingCount` getter.
- `syncOutbox()` — iterates pending reports, POSTs each, removes on success, stops on first failure. Calls `fetchVictims()` if any synced. Updates `_pendingCount`. Notifies listeners throughout.

**New file:** `frontend/lib/widgets/offline_banner.dart`

Slim `Material` banner rendered at the top of `ShellScreen`. Consumes `ConnectivityProvider` and `VictimProvider`:

| State | Text | Button |
|-------|------|--------|
| Offline, 0 pending | "Χωρίς σύνδεση" | — |
| Offline, N pending | "Χωρίς σύνδεση — N αναφορές εκκρεμούν" | "Συγχρονισμός" (disabled) |
| Online, N pending | "N αναφορές εκκρεμούν" | "Συγχρονισμός" (active) |
| Online, 0 pending | (hidden) | — |

Tapping "Συγχρονισμός" calls `VictimProvider.syncOutbox()`.

**Modified file:** `frontend/lib/screens/shell_screen.dart`

Adds `OfflineBanner` above the main content area (below the AppBar if any, before the page body).

---

## Section 5: Read Data Cache

Same pattern applied to three providers.

**`ServiceProvider`** (`fetchMyServices`):
- On success: `prefs.setString('cached_services', res.body)`
- On catch: if `prefs.getString('cached_services')` exists, decode and set `_services`; set `_isStale = true`
- `_isStale = false` on every successful fetch

**`ItemProvider`** (`fetchItems`):
- On success: `prefs.setString('cached_items', jsonEncode({'data': _items, 'page': ..., 'totalPages': ..., 'total': ..., 'limit': ...}))`
- On catch: load from `cached_items`, set `_isStale = true`
- Only the last-fetched page is cached (not all pages)

**`VehicleProvider`** (`fetchVehicles`):
- On success: `prefs.setString('cached_vehicles', res.body)`
- On catch: load from `cached_vehicles`, set `_isStale = true`

Each provider exposes `bool get isStale`.

**New file:** `frontend/lib/widgets/stale_banner.dart`

Single reusable widget:
```dart
StaleBanner(isStale: provider.isStale)
```
Renders a slim amber bar: "Εμφάνιση αποθηκευμένων δεδομένων" when `isStale == true`, otherwise `SizedBox.shrink()`.

Placed at the top of `ServicesScreen`, `ItemsScreen`, and `VehiclesScreen`.

---

## File Map

| Action | Path |
|--------|------|
| Modify | `frontend/web/sw.js` |
| Create | `frontend/lib/services/connectivity_service.dart` |
| Create | `frontend/lib/providers/connectivity_provider.dart` |
| Modify | `frontend/lib/providers/auth_provider.dart` |
| Create | `frontend/lib/services/offline_store.dart` |
| Modify | `frontend/lib/providers/victim_provider.dart` |
| Create | `frontend/lib/widgets/offline_banner.dart` |
| Modify | `frontend/lib/screens/shell_screen.dart` |
| Create | `frontend/lib/widgets/stale_banner.dart` |
| Modify | `frontend/lib/providers/service_provider.dart` |
| Modify | `frontend/lib/providers/item_provider.dart` |
| Modify | `frontend/lib/providers/vehicle_provider.dart` |
| Modify | `frontend/lib/screens/services_screen.dart` |
| Modify | `frontend/lib/screens/items_screen.dart` |
| Modify | `frontend/lib/screens/vehicles_screen.dart` |
| Modify | `frontend/lib/main.dart` |

---

## Error Handling

- Network errors are identified by catching `Exception` in provider fetch methods (the `http` package throws on connection failure, not on non-2xx status). Status code checks remain as-is.
- If `syncOutbox()` fails mid-way, successfully synced entries are removed and the remainder stays. The banner count updates accordingly.
- Stale data is always shown read-only; write operations (create/update/delete) that fail offline show the standard error snackbar — no offline queueing for writes other than victim reports.

---

## Out of Scope

- Offline creation/editing of items, vehicles, or services
- Background sync without the app open (Background Sync API)
- Conflict resolution for stale-then-edited data
- Outbox for vital signs or treatments (only the initial victim report is queued)
