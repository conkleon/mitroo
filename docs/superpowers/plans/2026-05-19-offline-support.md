# Offline Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to log in, view last-fetched data, and submit victim reports while offline, with an explicit sync banner that flushes queued reports when connectivity returns.

**Architecture:** Five layered pieces — (1) service worker caches the Flutter app shell for offline load; (2) a `ConnectivityService`/`ConnectivityProvider` pair tracks `window.online`/`offline` events; (3) `AuthProvider` caches the user profile in SharedPreferences so auto-login survives network loss; (4) `VictimProvider` queues failed POSTs via `OfflineStore` and flushes them via `syncOutbox()`; (5) `ServiceProvider`, `ItemProvider`, and `VehicleProvider` cache their last fetch and expose `isStale` for UI banners.

**Tech Stack:** Flutter Web, `dart:js_interop`, `dart:js_interop_unsafe`, `shared_preferences` (already a dep), Service Worker Cache API

> **Testing note:** This codebase has no test suite. Each task uses `flutter analyze` as the verification gate instead of unit tests. js_interop code cannot be tested outside the browser — manual smoke testing is the final gate (see Task 12).

---

## File Map

| Action | Path |
|--------|------|
| Modify | `frontend/web/sw.js` |
| Create | `frontend/lib/services/connectivity_service.dart` |
| Create | `frontend/lib/providers/connectivity_provider.dart` |
| Modify | `frontend/lib/main.dart` |
| Create | `frontend/lib/services/offline_store.dart` |
| Modify | `frontend/lib/providers/auth_provider.dart` |
| Modify | `frontend/lib/providers/victim_provider.dart` |
| Create | `frontend/lib/widgets/offline_banner.dart` |
| Modify | `frontend/lib/screens/shell_screen.dart` |
| Create | `frontend/lib/widgets/stale_banner.dart` |
| Modify | `frontend/lib/providers/service_provider.dart` |
| Modify | `frontend/lib/screens/services_screen.dart` |
| Modify | `frontend/lib/providers/item_provider.dart` |
| Modify | `frontend/lib/screens/items_screen.dart` |
| Modify | `frontend/lib/providers/vehicle_provider.dart` |
| Modify | `frontend/lib/screens/vehicles_screen.dart` |

---

## Task 1: Service Worker — App Shell Caching

**Files:**
- Modify: `frontend/web/sw.js`

- [ ] **Step 1: Replace the fetch no-op and add install/activate handlers**

Replace the entire contents of `frontend/web/sw.js` with:

```javascript
var CACHE_NAME = 'mitroo-shell-v1';

// Shell assets to cache on install.
// If flutter build web splits main.dart.js into chunks, add them here.
var SHELL_ASSETS = [
  '/',
  '/index.html',
  '/main.dart.js',
  '/flutter.js',
  '/manifest.json',
  '/icons/Icon-192.png',
  '/icons/Icon-512.png',
];

self.addEventListener('install', function(event) {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then(function(cache) {
      return cache.addAll(SHELL_ASSETS);
    })
  );
});

self.addEventListener('activate', function(event) {
  event.waitUntil(
    caches.keys().then(function(keys) {
      return Promise.all(
        keys.filter(function(k) { return k !== CACHE_NAME; })
            .map(function(k) { return caches.delete(k); })
      );
    }).then(function() { return self.clients.claim(); })
  );
});

// Push notification → show to user
self.addEventListener('push', function(event) {
  var data = event.data ? event.data.json() : {};
  event.waitUntil(
    self.registration.showNotification(data.title || 'Mitroo', {
      body: data.body || '',
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      tag: data.tag || 'default',
      data: { route: data.route || '/' },
    })
  );
});

// Notification click → focus existing tab or open new window
self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  var route = (event.notification.data && event.notification.data.route) || '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(list) {
      var existing = list.find(function(c) {
        return c.url.includes(self.location.origin);
      });
      if (existing) {
        existing.focus();
        existing.postMessage({ type: 'navigate', route: route });
      } else {
        clients.openWindow(route);
      }
    })
  );
});

// Navigation requests (HTML) → cache-first with network fallback.
// All other requests pass through unchanged.
self.addEventListener('fetch', function(event) {
  if (event.request.mode === 'navigate') {
    event.respondWith(
      caches.match(event.request).then(function(cached) {
        return cached || fetch(event.request);
      })
    );
  }
});
```

- [ ] **Step 2: Verify analysis passes**

```bash
cd frontend && flutter analyze
```

Expected: no errors (sw.js is not analyzed by Flutter, but run to confirm no dart regressions from the repo state).

- [ ] **Step 3: Commit**

```bash
git add frontend/web/sw.js
git commit -m "feat(sw): cache app shell on install, serve navigation requests cache-first"
```

---

## Task 2: ConnectivityService

**Files:**
- Create: `frontend/lib/services/connectivity_service.dart`

- [ ] **Step 1: Create the file**

```dart
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('window')
external JSObject get _jsWindow;

class ConnectivityService {
  static final StreamController<bool> _ctrl =
      StreamController<bool>.broadcast();

  static bool _initialized = false;

  static Stream<bool> get onConnectivityChanged => _ctrl.stream;

  static bool get isOnline {
    final nav = _jsWindow.getProperty<JSObject?>('navigator'.toJS);
    if (nav == null) return true;
    return nav.getProperty<JSBoolean?>('onLine'.toJS)?.toDart ?? true;
  }

  static void init() {
    if (_initialized) return;
    _initialized = true;
    _jsWindow.callMethod(
      'addEventListener'.toJS,
      'online'.toJS,
      ((JSObject _) { _ctrl.add(true); }).toJS,
    );
    _jsWindow.callMethod(
      'addEventListener'.toJS,
      'offline'.toJS,
      ((JSObject _) { _ctrl.add(false); }).toJS,
    );
  }
}
```

- [ ] **Step 2: Analyze**

```bash
cd frontend && flutter analyze lib/services/connectivity_service.dart
```

Expected: no errors. (Ignore `avoid_web_libraries_in_flutter` if it fires — `dart:js_interop` is the approved web interop layer.)

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/services/connectivity_service.dart
git commit -m "feat(offline): add ConnectivityService — online/offline stream via js_interop"
```

---

## Task 3: ConnectivityProvider + wire into main.dart

**Files:**
- Create: `frontend/lib/providers/connectivity_provider.dart`
- Modify: `frontend/lib/main.dart`

- [ ] **Step 1: Create `connectivity_provider.dart`**

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/connectivity_service.dart';

class ConnectivityProvider extends ChangeNotifier {
  bool _isOnline;
  StreamSubscription<bool>? _sub;

  ConnectivityProvider()
      : _isOnline = kIsWeb ? ConnectivityService.isOnline : true {
    if (kIsWeb) {
      ConnectivityService.init();
      _sub = ConnectivityService.onConnectivityChanged.listen((online) {
        _isOnline = online;
        notifyListeners();
      });
    }
  }

  bool get isOnline => _isOnline;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 2: Add `ConnectivityProvider` to `MultiProvider` in `main.dart`**

Open `frontend/lib/main.dart`. Add the import near the top with the other provider imports:

```dart
import 'providers/connectivity_provider.dart';
```

Then in the `MultiProvider` `providers` list, add `ConnectivityProvider` as the **first** entry (before `AuthProvider`) so it is available to all downstream providers and widgets:

```dart
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider.value(value: _pwaProvider),
        // ... rest unchanged
```

- [ ] **Step 3: Analyze**

```bash
cd frontend && flutter analyze lib/providers/connectivity_provider.dart lib/main.dart
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/providers/connectivity_provider.dart frontend/lib/main.dart
git commit -m "feat(offline): add ConnectivityProvider, wire into MultiProvider"
```

---

## Task 4: OfflineStore

**Files:**
- Create: `frontend/lib/services/offline_store.dart`

- [ ] **Step 1: Create the file**

```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class OfflineStore {
  static const _outboxKey = 'offline_victim_outbox';

  static Future<void> saveVictimReport(
      Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_outboxKey);
    final list = raw != null
        ? (jsonDecode(raw) as List).cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];
    list.add(payload);
    await prefs.setString(_outboxKey, jsonEncode(list));
  }

  static Future<List<Map<String, dynamic>>>
      getPendingVictimReports() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_outboxKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> setPendingVictimReports(
      List<Map<String, dynamic>> reports) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_outboxKey, jsonEncode(reports));
  }
}
```

- [ ] **Step 2: Analyze**

```bash
cd frontend && flutter analyze lib/services/offline_store.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/services/offline_store.dart
git commit -m "feat(offline): add OfflineStore — victim report outbox backed by SharedPreferences"
```

---

## Task 5: AuthProvider — Offline Login Cache

**Files:**
- Modify: `frontend/lib/providers/auth_provider.dart`

- [ ] **Step 1: Add SharedPreferences import**

At the top of `frontend/lib/providers/auth_provider.dart`, add:

```dart
import 'package:shared_preferences/shared_preferences.dart';
```

- [ ] **Step 2: Cache user profile on successful load**

Replace the existing `_loadCurrentUser` method:

```dart
  Future<void> _loadCurrentUser() async {
    final res = await _api.get('/auth/me');
    if (res.statusCode == 200) {
      _user = jsonDecode(res.body);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_user', res.body);
    }
  }
```

- [ ] **Step 3: Load from cache when network is unavailable**

Replace the existing `_tryAutoLogin` method:

```dart
  Future<void> _tryAutoLogin() async {
    _loading = true;
    notifyListeners();
    try {
      await _api.loadToken();
      await _loadCurrentUser();
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_user');
      if (cached != null) {
        _user = jsonDecode(cached);
      }
    }
    _loading = false;
    notifyListeners();
  }
```

- [ ] **Step 4: Clear cached user on logout**

Replace the existing `logout` method:

```dart
  Future<void> logout() async {
    await _api.clearToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_user');
    _user = null;
    notifyListeners();
  }
```

- [ ] **Step 5: Analyze**

```bash
cd frontend && flutter analyze lib/providers/auth_provider.dart
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/providers/auth_provider.dart
git commit -m "feat(offline): cache user profile in SharedPreferences for offline auto-login"
```

---

## Task 6: VictimProvider — Offline Outbox

**Files:**
- Modify: `frontend/lib/providers/victim_provider.dart`

- [ ] **Step 1: Add import and `_pendingCount` field**

At the top of `frontend/lib/providers/victim_provider.dart`, add:

```dart
import '../services/offline_store.dart';
```

Inside `VictimProvider`, add the field and getter after the existing `_loading` field:

```dart
  int _pendingCount = 0;
  int get pendingCount => _pendingCount;
```

- [ ] **Step 2: Load pending count in the constructor**

Add a constructor that kicks off an async load of the pending count:

```dart
  VictimProvider() {
    OfflineStore.getPendingVictimReports().then((reports) {
      _pendingCount = reports.length;
      notifyListeners();
    });
  }
```

- [ ] **Step 3: Queue report on network failure in `createVictim`**

Replace the existing `createVictim` method:

```dart
  Future<String?> createVictim(Map<String, dynamic> data) async {
    try {
      final res = await _api.post('/victims', body: data);
      if (res.statusCode == 201) {
        await fetchVictims();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (_) {
      await OfflineStore.saveVictimReport(data);
      _pendingCount++;
      notifyListeners();
      return null;
    }
  }
```

- [ ] **Step 4: Add `syncOutbox` method**

Add this method after `createVictim`:

```dart
  Future<void> syncOutbox() async {
    final pending = await OfflineStore.getPendingVictimReports();
    if (pending.isEmpty) return;

    final remaining = <Map<String, dynamic>>[];
    bool anySynced = false;
    bool networkFailed = false;

    for (final report in pending) {
      if (networkFailed) {
        remaining.add(report);
        continue;
      }
      try {
        final res = await _api.post('/victims', body: report);
        if (res.statusCode == 201) {
          anySynced = true;
        } else {
          remaining.add(report);
        }
      } catch (_) {
        networkFailed = true;
        remaining.add(report);
      }
    }

    await OfflineStore.setPendingVictimReports(remaining);
    _pendingCount = remaining.length;
    notifyListeners();
    if (anySynced) await fetchVictims();
  }
```

- [ ] **Step 5: Analyze**

```bash
cd frontend && flutter analyze lib/providers/victim_provider.dart
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/providers/victim_provider.dart
git commit -m "feat(offline): queue victim reports locally when offline, add syncOutbox"
```

---

## Task 7: OfflineBanner Widget

**Files:**
- Create: `frontend/lib/widgets/offline_banner.dart`

- [ ] **Step 1: Create the file**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connectivity_provider.dart';
import '../providers/victim_provider.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final isOnline = context.watch<ConnectivityProvider>().isOnline;
    final victims = context.watch<VictimProvider>();
    final pending = victims.pendingCount;

    if (isOnline && pending == 0) return const SizedBox.shrink();

    final String message;
    if (!isOnline && pending == 0) {
      message = 'Χωρίς σύνδεση';
    } else if (!isOnline) {
      message = 'Χωρίς σύνδεση — $pending αναφορές εκκρεμούν';
    } else {
      message = '$pending αναφορές εκκρεμούν';
    }

    final color =
        isOnline ? const Color(0xFFFEF3C7) : const Color(0xFFFEE2E2);
    final textColor =
        isOnline ? const Color(0xFF92400E) : const Color(0xFF991B1B);

    return Material(
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              isOnline
                  ? Icons.cloud_upload_outlined
                  : Icons.wifi_off_rounded,
              size: 16,
              color: textColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  color: textColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (pending > 0)
              TextButton(
                onPressed:
                    isOnline ? () => victims.syncOutbox() : null,
                style: TextButton.styleFrom(foregroundColor: textColor),
                child: const Text('Συγχρονισμός'),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

```bash
cd frontend && flutter analyze lib/widgets/offline_banner.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/widgets/offline_banner.dart
git commit -m "feat(offline): add OfflineBanner widget — shows connectivity state and sync button"
```

---

## Task 8: Wire OfflineBanner into ShellScreen

**Files:**
- Modify: `frontend/lib/screens/shell_screen.dart`

- [ ] **Step 1: Add the import**

At the top of `frontend/lib/screens/shell_screen.dart`, add:

```dart
import '../widgets/offline_banner.dart';
```

- [ ] **Step 2: Inject banner in the desktop layout**

Find this block (around line 44–46):

```dart
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: child),
```

Replace it with:

```dart
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: Column(
                    children: [
                      const OfflineBanner(),
                      Expanded(child: child),
                    ],
                  ),
                ),
```

- [ ] **Step 3: Inject banner in the mobile layout**

Find this block (around line 52–53):

```dart
        return Scaffold(
          body: child,
```

Replace it with:

```dart
        return Scaffold(
          body: Column(
            children: [
              const OfflineBanner(),
              Expanded(child: child),
            ],
          ),
```

- [ ] **Step 4: Analyze**

```bash
cd frontend && flutter analyze lib/screens/shell_screen.dart
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/shell_screen.dart
git commit -m "feat(offline): show OfflineBanner at top of ShellScreen on mobile and desktop"
```

---

## Task 9: StaleBanner Widget

**Files:**
- Create: `frontend/lib/widgets/stale_banner.dart`

- [ ] **Step 1: Create the file**

```dart
import 'package:flutter/material.dart';

class StaleBanner extends StatelessWidget {
  final bool isStale;
  const StaleBanner({super.key, required this.isStale});

  @override
  Widget build(BuildContext context) {
    if (!isStale) return const SizedBox.shrink();
    return Material(
      color: const Color(0xFFFEF3C7),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: const [
            Icon(Icons.history_rounded, size: 16, color: Color(0xFF92400E)),
            SizedBox(width: 8),
            Text(
              'Εμφάνιση αποθηκευμένων δεδομένων',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

```bash
cd frontend && flutter analyze lib/widgets/stale_banner.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/widgets/stale_banner.dart
git commit -m "feat(offline): add StaleBanner widget for cached read data"
```

---

## Task 10: ServiceProvider — Stale Cache + ServicesScreen Banner

**Files:**
- Modify: `frontend/lib/providers/service_provider.dart`
- Modify: `frontend/lib/screens/services_screen.dart`

- [ ] **Step 1: Add `_isStale` to `ServiceProvider`**

In `frontend/lib/providers/service_provider.dart`, add the import at the top:

```dart
import 'package:shared_preferences/shared_preferences.dart';
```

Add the field and getter after the existing `_loading` field:

```dart
  bool _isStale = false;
  bool get isStale => _isStale;
```

- [ ] **Step 2: Cache on success and load from cache on failure in `fetchMyServices`**

Replace the existing `fetchMyServices` method:

```dart
  Future<void> fetchMyServices() async {
    _loading = true;
    notifyListeners();
    try {
      final res = await _api.get('/services/my');
      if (res.statusCode == 200) {
        _services = jsonDecode(res.body);
        _isStale = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_services', res.body);
      } else {
        debugPrint('fetchMyServices failed: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      debugPrint('fetchMyServices error: $e');
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_services');
      if (cached != null) {
        _services = jsonDecode(cached);
        _isStale = true;
      }
    }
    _loading = false;
    notifyListeners();
  }
```

- [ ] **Step 3: Analyze provider**

```bash
cd frontend && flutter analyze lib/providers/service_provider.dart
```

Expected: no errors.

- [ ] **Step 4: Add `StaleBanner` to `ServicesScreen`**

In `frontend/lib/screens/services_screen.dart`, add the import near the top:

```dart
import '../widgets/stale_banner.dart';
```

Find the `build` method's `return Scaffold(` (around line 299). Its `body` currently starts with:

```dart
      body: Stack(
        children: [
          SafeArea(
```

Replace it with:

```dart
      body: Column(
        children: [
          StaleBanner(isStale: svcProv.isStale),
          Expanded(
            child: Stack(
              children: [
                SafeArea(
```

You also need to close the new `Expanded` and `Column`. Find the closing of the existing `Stack` (the last `],` and `)` that closes the Stack's `children` list and the `Stack` widget itself, just before the `floatingActionButton` or closing of `Scaffold`). Add the two extra closing brackets:

```dart
                ),   // closes Stack
              ],     // closes Expanded's child (was Stack's children)
            ),       // closes Expanded
          ],         // closes Column's children
        ),           // closes Column
```

> **Tip:** The `Stack` in `ServicesScreen` has two children: the `SafeArea` content and the FAB overlay. Both stay inside the `Expanded(child: Stack(...))`. Only the `StaleBanner` moves outside.

- [ ] **Step 5: Analyze screen**

```bash
cd frontend && flutter analyze lib/screens/services_screen.dart
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/providers/service_provider.dart frontend/lib/screens/services_screen.dart
git commit -m "feat(offline): cache services list, show StaleBanner in ServicesScreen"
```

---

## Task 11: ItemProvider — Stale Cache + ItemsScreen Banner

**Files:**
- Modify: `frontend/lib/providers/item_provider.dart`
- Modify: `frontend/lib/screens/items_screen.dart`

- [ ] **Step 1: Add `_isStale` to `ItemProvider`**

In `frontend/lib/providers/item_provider.dart`, add the import at the top:

```dart
import 'package:shared_preferences/shared_preferences.dart';
```

Add the field and getter after the existing `_pageSize` field:

```dart
  bool _isStale = false;
  bool get isStale => _isStale;
```

- [ ] **Step 2: Cache on success and load from cache on failure in `fetchItems`**

Replace the existing `fetchItems` method:

```dart
  Future<void> fetchItems({int? containerId, String? search, bool? available, int? categoryId, int? departmentId, int page = 1, int limit = 20, String? sortField, String? sortOrder}) async {
    _loading = true;
    notifyListeners();
    try {
      final params = <String>[];
      if (containerId != null) params.add('containerId=$containerId');
      if (search != null && search.isNotEmpty) params.add('search=${Uri.encodeComponent(search)}');
      if (available == true) params.add('available=true');
      if (categoryId != null) params.add('categoryId=$categoryId');
      if (departmentId != null) params.add('departmentId=$departmentId');
      if (sortField != null) params.add('sortField=${Uri.encodeComponent(sortField)}');
      if (sortOrder != null) params.add('sortOrder=${Uri.encodeComponent(sortOrder)}');
      params.add('page=$page');
      params.add('limit=$limit');
      final q = '?${params.join('&')}';
      final res = await _api.get('/items$q');
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        _items = body['data'];
        _currentPage = body['page'];
        _totalPages = body['totalPages'];
        _totalItems = body['total'];
        _pageSize = body['limit'];
        _isStale = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_items', res.body);
      }
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_items');
      if (cached != null) {
        final body = jsonDecode(cached);
        _items = body['data'];
        _currentPage = body['page'];
        _totalPages = body['totalPages'];
        _totalItems = body['total'];
        _pageSize = body['limit'];
        _isStale = true;
      }
    }
    _loading = false;
    notifyListeners();
  }
```

- [ ] **Step 3: Analyze provider**

```bash
cd frontend && flutter analyze lib/providers/item_provider.dart
```

Expected: no errors.

- [ ] **Step 4: Add `StaleBanner` to `ItemsScreen`**

In `frontend/lib/screens/items_screen.dart`, add the import near the top:

```dart
import '../widgets/stale_banner.dart';
```

In the `build` method, add a watch for `ItemProvider` after the existing `cats` line (around line 1088):

```dart
    final cats = context.watch<CategoryProvider>().categories;
    final itemProv = context.watch<ItemProvider>();
```

Find the `return Scaffold(` (around line 1090). Its `body` currently starts with:

```dart
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
```

Replace it with:

```dart
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                StaleBanner(isStale: itemProv.isStale),
```

That's the only change — one line added as the first child of the existing inner `Column`.

- [ ] **Step 5: Analyze screen**

```bash
cd frontend && flutter analyze lib/screens/items_screen.dart
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/providers/item_provider.dart frontend/lib/screens/items_screen.dart
git commit -m "feat(offline): cache items list, show StaleBanner in ItemsScreen"
```

---

## Task 12: VehicleProvider — Stale Cache + VehiclesScreen Banner + Smoke Test

**Files:**
- Modify: `frontend/lib/providers/vehicle_provider.dart`
- Modify: `frontend/lib/screens/vehicles_screen.dart`

- [ ] **Step 1: Add `_isStale` to `VehicleProvider`**

In `frontend/lib/providers/vehicle_provider.dart`, add the import at the top:

```dart
import 'package:shared_preferences/shared_preferences.dart';
```

Add the field and getter after the existing `_loading` field:

```dart
  bool _isStale = false;
  bool get isStale => _isStale;
```

- [ ] **Step 2: Cache on success and load from cache on failure in `fetchVehicles`**

Replace the existing `fetchVehicles` method:

```dart
  Future<void> fetchVehicles({int? departmentId}) async {
    _loading = true;
    notifyListeners();
    try {
      final q = departmentId != null ? '?departmentId=$departmentId' : '';
      final res = await _api.get('/vehicles$q');
      if (res.statusCode == 200) {
        _vehicles = jsonDecode(res.body);
        _isStale = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_vehicles', res.body);
      }
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_vehicles');
      if (cached != null) {
        _vehicles = jsonDecode(cached);
        _isStale = true;
      }
    }
    _loading = false;
    notifyListeners();
  }
```

- [ ] **Step 3: Analyze provider**

```bash
cd frontend && flutter analyze lib/providers/vehicle_provider.dart
```

Expected: no errors.

- [ ] **Step 4: Add `StaleBanner` to `VehiclesScreen`**

In `frontend/lib/screens/vehicles_screen.dart`, add the import near the top:

```dart
import '../widgets/stale_banner.dart';
```

In the `build` method, the `prov` variable is already `context.watch<VehicleProvider>()`.

Find the `return Scaffold(` (around line 177). Its `body` currently starts with:

```dart
      body: SafeArea(
        child: RefreshIndicator(
```

Replace it with:

```dart
      body: Column(
        children: [
          StaleBanner(isStale: prov.isStale),
          Expanded(
            child: SafeArea(
              child: RefreshIndicator(
```

Then find the closing of `SafeArea` (the `)` that closes `SafeArea(child: RefreshIndicator(...))`). Add two extra closing brackets after it:

```dart
            ),   // closes SafeArea
          ),     // closes Expanded
        ],       // closes Column's children
      ),         // closes Column
```

- [ ] **Step 5: Full analysis pass**

```bash
cd frontend && flutter analyze
```

Expected: no errors across the entire project.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/providers/vehicle_provider.dart frontend/lib/screens/vehicles_screen.dart
git commit -m "feat(offline): cache vehicles list, show StaleBanner in VehiclesScreen"
```

- [ ] **Step 7: Smoke test — offline login**

Start the app (`flutter run -d chrome`) with network available and log in. Open DevTools → Application → Service Workers and confirm `sw.js` is registered and active.

Then in Chrome DevTools → Network tab, tick **Offline**. Refresh the page. Confirm:
- The app loads from the service worker cache (no blank screen).
- The shell (`/`) is served from cache.
- The user is still logged in (auto-login from `cached_user`).

- [ ] **Step 8: Smoke test — victim report outbox**

With the app loaded and logged in, remain in DevTools → Network → Offline. Navigate to create a victim report, fill in a name, and submit. Confirm:
- No error snackbar. Navigation goes to `/victims` as normal.
- The `OfflineBanner` appears with "Χωρίς σύνδεση — 1 αναφορά εκκρεμεί".

Un-tick Offline. Tap **Συγχρονισμός**. Confirm:
- The banner disappears after sync.
- The victim appears in the list.

- [ ] **Step 9: Smoke test — stale data**

With the app loaded and some items/vehicles/services visible, tick Offline and navigate away from and back to the Services, Items, and Vehicles screens. Confirm:
- Data is shown.
- The amber `StaleBanner` appears on each screen.
- Un-tick Offline and refresh the screen — banner disappears.
