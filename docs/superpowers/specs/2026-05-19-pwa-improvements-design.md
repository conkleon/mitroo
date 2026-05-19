# PWA Improvements — Installability, Notification Deep-linking & PWA Service Consolidation

**Date:** 2026-05-19
**Scope:** Frontend (Flutter web) + minor backend push payload change

---

## Goal

Deliver two user-facing PWA improvements — a first-login install prompt and notification deep-linking to any entity type — while consolidating all PWA JS interop into a unified `PwaService` and migrating off the deprecated `dart:js` library. The service worker is restructured to support future offline caching without requiring further architectural changes.

---

## Architecture

### Files changed / created

```
frontend/web/
  sw.js                        ← replaces push_sw.js (unified service worker)
  index.html                   ← stripped: register sw.js only, no logic

frontend/lib/
  services/
    pwa_service.dart           ← new: replaces push_service.dart
  providers/
    pwa_provider.dart          ← new: ChangeNotifier wrapping PwaService install state
  config/
    router.dart                ← add auth.loading guard
  main.dart                    ← swap PushService → PwaService, register PwaProvider

backend/src/routes/
  push.ts (or wherever push payloads are built)  ← add `route` + `tag` fields
```

`push_service.dart` is deleted. All push subscription logic moves into `PwaService`.

---

## Service Worker (`sw.js`)

Three event handlers:

### Push → show notification
```js
self.addEventListener('push', event => {
  const data = event.data?.json() ?? {};
  event.waitUntil(self.registration.showNotification(data.title ?? 'Mitroo', {
    body: data.body ?? '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: data.tag ?? 'default',
    data: { route: data.route ?? '/' },
  }));
});
```

### Notification click → focus existing client or open new window
```js
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const route = event.notification.data?.route ?? '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
      const existing = list.find(c => c.url.includes(self.location.origin));
      if (existing) {
        existing.focus();
        existing.postMessage({ type: 'navigate', route });
      } else {
        clients.openWindow(route);
      }
    })
  );
});
```

### Fetch (offline stub — no-op passthrough)
```js
self.addEventListener('fetch', event => {
  // passthrough — offline caching added in a future iteration
});
```

---

## JS Bridge (`index.html`)

The `<script>` block is reduced to registration + two event listeners. No logic lives here.

```js
navigator.serviceWorker.register('/sw.js')
  .then(reg => { window._swReg = reg; });

window.addEventListener('beforeinstallprompt', e => {
  e.preventDefault();
  window._installPrompt = e;
});

window.addEventListener('appinstalled', () => {
  window._appInstalled = true;
});
```

The `urlBase64ToUint8Array` helper and `mitrooSubscribePush` function move into `sw.js` / `pwa_service.dart` respectively.

---

## `PwaService` (Dart)

Replaces `PushService`. Uses `dart:js_interop` + `dart:js_interop_unsafe` (resolves existing TODO in `push_service.dart`).

```dart
class PwaService {
  static final StreamController<String> _navigateStream =
      StreamController<String>.broadcast();

  static Stream<String> get navigateStream => _navigateStream.stream;

  /// Called once in main.dart after the widget tree is built.
  static Future<void> init() async {
    _listenForSwMessages();
    await _subscribeAndRegister(); // push subscription, best-effort
  }

  /// True when the browser has a deferred install prompt ready.
  static bool canInstall();

  /// Triggers the native install prompt. Returns true if accepted.
  static Future<bool> triggerInstall();

  static void _listenForSwMessages(); // wires navigator.serviceWorker.onmessage
  static Future<void> _subscribeAndRegister(); // VAPID subscribe → POST /push/subscribe
}
```

`navigateStream` emits route strings received via `postMessage` from the service worker. In `main.dart`, after `PwaService.init()`, a `StreamSubscription` is set up on `navigateStream` that calls `router.go(route)` on the app's `GoRouter` instance.

---

## `PwaProvider` (Dart)

```dart
class PwaProvider extends ChangeNotifier {
  bool get installAvailable;  // true when window._installPrompt is set
  bool get installed;         // true after appinstalled fires
  Future<void> triggerInstall();
}
```

`PwaProvider` is created in `main.dart` before `PwaService.init()` is called. `PwaService` holds a reference to `PwaProvider` (passed at init) and calls `provider.notifyInstallAvailable()` when `beforeinstallprompt` is detected (checked by polling `window._installPrompt` once after init, since the event fires before the Dart app boots). Exposed via `MultiProvider` in `main.dart`.

---

## Install Dialog

Triggered once per session in `AuthProvider.login()` (or `_loadCurrentUser()`) on successful authentication:

```dart
final pwa = context.read<PwaProvider>();
if (pwa.installAvailable && !pwa.installed) {
  showDialog(/* "Add Mitroo to your home screen" AlertDialog */);
}
```

Dialog has two actions: **Install** (calls `pwa.triggerInstall()`) and **Not now** (dismisses).

Shown only on explicit `login()` success (not on `_tryAutoLogin()` restores). After showing once — regardless of outcome — a `SharedPreferences` key `pwa_install_shown` is set to `true` so it never appears again on that device.

---

## Router Auth Guard Fix (`router.dart`)

```dart
redirect: (context, state) {
  if (auth.loading) return null; // wait for _tryAutoLogin before redirecting
  // ... existing logic unchanged
}
```

This prevents cold-start notification deep-links from being redirected to `/login` before the stored JWT is validated. GoRouter re-evaluates automatically once `auth.notifyListeners()` fires at the end of `_tryAutoLogin()`.

---

## Backend Push Payload

All push-sending code adds two new fields to the notification payload:

```json
{
  "title": "...",
  "body": "...",
  "tag": "<entity-type>-<id>",
  "route": "/services/42"
}
```

`tag` enables notification deduplication (a second push for the same entity replaces the first).

Route conventions:
| Entity | Route pattern |
|---|---|
| Service | `/services/:id` |
| Chat room | `/chat/:id` |
| Direct message | `/chat/:id` |
| Item | `/items` (no detail route currently) |
| Vehicle | `/vehicles` |
| Department | `/admin/departments/:id` |

---

## Out of Scope (this iteration)

- Offline caching / Background Sync (fetch handler is a stub)
- `dart:js_interop` migration beyond `PwaService` (existing screens untouched)
- Apple splash screen / additional icon sizes
- Manifest enhancements (`screenshots`, `shortcuts`, `id` field)
