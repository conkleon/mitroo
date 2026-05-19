# PWA Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a first-login PWA install prompt, deep-linking notification clicks, and a unified `PwaService` that replaces the deprecated `dart:js`-based `PushService`.

**Architecture:** Replace `push_sw.js` with a unified `sw.js` that handles push, notification routing, and a fetch passthrough stub. On the Dart side, delete `PushService` and create `PwaService` (using `dart:js_interop`) + `PwaProvider`. Wire everything in a refactored `main.dart` where `AuthProvider`, `PwaProvider`, and `GoRouter` are created once in `State.initState`. Fix the router auth guard so cold-start deep-links survive the async auto-login check.

**Tech Stack:** Flutter Web, `dart:js_interop` + `dart:js_interop_unsafe`, Service Worker API, Web Push API, Node.js/TypeScript backend with `web-push`

---

## File Map

| Action | Path |
|--------|------|
| Modify | `backend/src/lib/webpush.ts` |
| Modify | `backend/src/socket.ts` |
| Modify | `backend/src/routes/service.routes.ts` |
| Create | `frontend/web/sw.js` |
| Modify | `frontend/web/index.html` |
| Create | `frontend/lib/providers/pwa_provider.dart` |
| Create | `frontend/lib/services/pwa_service.dart` |
| Modify | `frontend/lib/config/router.dart` |
| Modify | `frontend/lib/main.dart` |
| Modify | `frontend/lib/providers/auth_provider.dart` |
| Modify | `frontend/lib/screens/login_screen.dart` |
| Delete | `frontend/lib/services/push_service.dart` |
| Delete | `frontend/web/push_sw.js` |

---

## Task 1: Backend — add `route` + `tag` to push payloads

**Files:**
- Modify: `backend/src/lib/webpush.ts`
- Modify: `backend/src/socket.ts`
- Modify: `backend/src/routes/service.routes.ts`

- [ ] **Step 1: Update `sendPushToUser` payload type in `webpush.ts`**

Replace lines 10-12 with:

```typescript
export async function sendPushToUser(
  userId: number,
  payload: { title: string; body: string; tag?: string; route?: string; data?: Record<string, unknown> }
): Promise<void> {
```

- [ ] **Step 2: Add `tag` and `route` to the chat message push in `socket.ts`**

Find the `sendPushToUser` call around line 234 and replace it:

```typescript
sendPushToUser(m.userId, {
  title: chatName,
  body: `${senderName}: ${truncated}`,
  tag: `chat-${chat.id}`,
  route: `/chat/${chat.id}`,
  data: { chatId: chat.id, type: "chat_message" },
}).catch(() => {});
```

- [ ] **Step 3: Add `tag` and `route` to the service enrollment push in `service.routes.ts`**

Find the `sendPushToUser` call around line 380 (inside the `if (status === "requested")` block) and replace it:

```typescript
sendPushToUser(admin.user.id, {
  title: "Νέα αίτηση",
  body: `${applicantName} αιτήθηκε για "${service.name}"`,
  tag: `service-enroll-${serviceId}`,
  route: `/services/${serviceId}`,
}).catch(() => {}),
```

- [ ] **Step 4: Add `tag` and `route` to the service status push in `service.routes.ts`**

Find the `sendPushToUser` call around line 444 (inside `if (status === "accepted" || status === "rejected")`) and replace it:

```typescript
sendPushToUser(record.user.id, {
  title: "Ενημέρωση αίτησης",
  body: `Η αίτησή σας για "${service.name}" ${status === "accepted" ? "εγκρίθηκε" : "απορρίφθηκε"}`,
  tag: `service-status-${sid}`,
  route: `/services/${sid}`,
}).catch(() => {});
```

- [ ] **Step 5: Compile to verify no TypeScript errors**

```bash
cd backend && npm run build
```

Expected: exits 0, no errors.

- [ ] **Step 6: Commit**

```bash
git add backend/src/lib/webpush.ts backend/src/socket.ts backend/src/routes/service.routes.ts
git commit -m "feat(push): add route and tag fields to push payloads for deep-linking"
```

---

## Task 2: Create unified service worker (`sw.js`)

**Files:**
- Create: `frontend/web/sw.js`

- [ ] **Step 1: Create `frontend/web/sw.js` with the full content below**

```javascript
// Push notification → show to user
self.addEventListener('push', function(event) {
  const data = event.data ? event.data.json() : {};
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

// Fetch passthrough — offline caching added in a future iteration
self.addEventListener('fetch', function(event) {
  // no-op
});
```

- [ ] **Step 2: Commit**

```bash
git add frontend/web/sw.js
git commit -m "feat(pwa): add unified service worker with push, deep-link routing, and fetch stub"
```

---

## Task 3: Update `index.html` JS bridge

**Files:**
- Modify: `frontend/web/index.html`

- [ ] **Step 1: Replace the entire `<script>` block in `index.html`**

The current `<script>` block (lines 28–76) contains SW registration, `urlBase64ToUint8Array`, and `mitrooSubscribePush`. Replace it entirely with:

```html
  <script>
    // Register unified service worker
    if ('serviceWorker' in navigator) {
      window.addEventListener('load', function() {
        navigator.serviceWorker.register('/sw.js').then(function(reg) {
          window._swReg = reg;
        }).catch(function(err) {
          console.error('sw registration failed', err);
        });
      });
    }

    // Capture install prompt for PwaService to use
    window.addEventListener('beforeinstallprompt', function(e) {
      e.preventDefault();
      window._installPrompt = e;
    });

    // Track successful installation
    window.addEventListener('appinstalled', function() {
      window._appInstalled = true;
    });
  </script>
```

Also fix the inconsistent Apple title on line 11: change `content="R.C.D."` to `content="Mitroo"`:

```html
  <meta name="apple-mobile-web-app-title" content="Mitroo">
```

- [ ] **Step 2: Commit**

```bash
git add frontend/web/index.html
git commit -m "feat(pwa): simplify index.html JS bridge — register sw.js, capture install prompt"
```

---

## Task 4: Create `PwaProvider`

**Files:**
- Create: `frontend/lib/providers/pwa_provider.dart`

- [ ] **Step 1: Create the file**

```dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/pwa_service.dart';

class PwaProvider extends ChangeNotifier {
  bool _installAvailable = false;
  bool _installed = false;
  bool _installDialogShown = false;

  bool get installAvailable => _installAvailable;
  bool get installed => _installed;

  /// True when the install dialog should be shown: prompt available, not yet
  /// installed, and not already shown this device lifetime.
  bool get shouldShowInstallDialog =>
      _installAvailable && !_installed && !_installDialogShown;

  void setInstallAvailable(bool value) {
    _installAvailable = value;
    notifyListeners();
  }

  void setInstalled(bool value) {
    _installed = value;
    _installAvailable = false;
    notifyListeners();
  }

  /// Call before showing the install dialog. Prevents re-showing and persists
  /// the flag so it survives app restarts.
  /// Called by the UI before showing the dialog. Persists the flag so it
  /// survives app restarts.
  void markInstallDialogShown() {
    _setInstallDialogShown(persist: true);
  }

  /// Called by PwaService on init to restore the persisted flag without
  /// writing to SharedPreferences again.
  void restoreInstallDialogShown() {
    _setInstallDialogShown(persist: false);
  }

  void _setInstallDialogShown({required bool persist}) {
    _installDialogShown = true;
    notifyListeners();
    if (persist) {
      SharedPreferences.getInstance()
          .then((p) => p.setBool('pwa_install_shown', true));
    }
  }

  Future<bool> triggerInstall() async {
    final accepted = await PwaService.triggerInstall();
    if (accepted) setInstalled(true);
    return accepted;
  }
}
```

- [ ] **Step 2: Run analysis to verify no errors**

```bash
cd frontend && flutter analyze lib/providers/pwa_provider.dart
```

Expected: no errors (warnings about missing `PwaService` import are expected until Task 5).

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/providers/pwa_provider.dart
git commit -m "feat(pwa): add PwaProvider with install prompt state management"
```

---

## Task 5: Create `PwaService`

**Files:**
- Create: `frontend/lib/services/pwa_service.dart`

- [ ] **Step 1: Create the file**

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/pwa_provider.dart';
import 'api_client.dart';

@JS('window')
external JSObject get _jsWindow;

@JS('navigator.serviceWorker')
external JSObject? get _swContainer;

class PwaService {
  static final StreamController<String> _navigateCtrl =
      StreamController<String>.broadcast();

  static Stream<String> get navigateStream => _navigateCtrl.stream;

  static PwaProvider? _provider;

  /// Called once from main.dart after the first frame on web only.
  static Future<void> init(PwaProvider provider) async {
    if (!kIsWeb) return;
    _provider = provider;
    await _checkInstallState();
    _listenForSwMessages();
    try {
      await _subscribeAndRegister();
    } catch (_) {
      // Push subscription is best-effort
    }
  }

  /// True when the browser has a deferred install prompt ready.
  static bool canInstall() {
    if (!kIsWeb) return false;
    return _jsWindow.getProperty<JSAny?>('_installPrompt'.toJS) != null;
  }

  /// Triggers the native install prompt. Returns true if the user accepted.
  static Future<bool> triggerInstall() async {
    if (!kIsWeb) return false;
    final prompt = _jsWindow.getProperty<JSObject?>('_installPrompt'.toJS);
    if (prompt == null) return false;
    try {
      final result =
          await prompt.callMethod<JSPromise>('prompt'.toJS).toDart as JSObject;
      final outcome =
          result.getProperty<JSString?>('outcome'.toJS)?.toDart;
      return outcome == 'accepted';
    } catch (_) {
      return false;
    }
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  static Future<void> _checkInstallState() async {
    // Check if the install prompt fired before Dart booted
    if (_jsWindow.getProperty<JSAny?>('_installPrompt'.toJS) != null) {
      _provider?.setInstallAvailable(true);
    }
    // Check if already installed (e.g. user installed in a previous session)
    final appInstalled =
        _jsWindow.getProperty<JSBoolean?>('_appInstalled'.toJS);
    if (appInstalled?.toDart == true) {
      _provider?.setInstalled(true);
    }
    // Restore persisted "dialog shown" flag without writing it again
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('pwa_install_shown') ?? false) {
      _provider?.restoreInstallDialogShown();
    }
  }

  static void _listenForSwMessages() {
    final sw = _swContainer;
    if (sw == null) return;
    sw.callMethod(
      'addEventListener'.toJS,
      'message'.toJS,
      ((JSObject event) {
        final data = event.getProperty<JSObject?>('data'.toJS);
        if (data == null) return;
        final type = data.getProperty<JSString?>('type'.toJS)?.toDart;
        if (type == 'navigate') {
          final route = data.getProperty<JSString?>('route'.toJS)?.toDart;
          if (route != null) _navigateCtrl.add(route);
        }
      }).toJS,
    );
  }

  static Future<void> _subscribeAndRegister() async {
    final sw = _swContainer;
    if (sw == null) return;

    // 1. Fetch VAPID public key from backend
    final keyRes = await ApiClient().get('/push/vapid-public-key');
    if (keyRes.statusCode != 200) return;
    final vapidPublicKey =
        (jsonDecode(keyRes.body) as Map<String, dynamic>)['publicKey']
            as String?;
    if (vapidPublicKey == null) return;

    // 2. Get the SW registration (set by index.html on load)
    JSObject reg;
    final cached = _jsWindow.getProperty<JSObject?>('_swReg'.toJS);
    if (cached != null) {
      reg = cached;
    } else {
      final ready = sw.getProperty<JSPromise>('ready'.toJS);
      reg = await ready.toDart as JSObject;
    }

    // 3. Subscribe via PushManager
    final pushManager = reg.getProperty<JSObject?>('pushManager'.toJS);
    if (pushManager == null) return;

    final options = JSObject();
    options.setProperty('userVisibleOnly'.toJS, true.toJS);
    options.setProperty(
        'applicationServerKey'.toJS, _urlBase64ToUint8Array(vapidPublicKey));

    final sub = await pushManager
        .callMethod<JSPromise>('subscribe'.toJS, options)
        .toDart as JSObject;

    // 4. Extract endpoint + keys via toJSON()
    final subJson =
        sub.callMethod('toJSON'.toJS) as JSObject;
    final endpoint =
        subJson.getProperty<JSString?>('endpoint'.toJS)?.toDart;
    if (endpoint == null) return;
    final keys = subJson.getProperty<JSObject?>('keys'.toJS);
    if (keys == null) return;
    final p256dh = keys.getProperty<JSString?>('p256dh'.toJS)?.toDart;
    final auth = keys.getProperty<JSString?>('auth'.toJS)?.toDart;
    if (p256dh == null || auth == null) return;

    // 5. POST subscription to backend
    await ApiClient().post('/push/subscribe', body: {
      'endpoint': endpoint,
      'p256dhKey': p256dh,
      'authKey': auth,
    });
  }

  static JSUint8Array _urlBase64ToUint8Array(String base64String) {
    final padding = '=' * ((4 - base64String.length % 4) % 4);
    final padded = (base64String + padding)
        .replaceAll('-', '+')
        .replaceAll('_', '/');
    return (base64Decode(padded) as Uint8List).toJS;
  }
}
```

- [ ] **Step 2: Run analysis**

```bash
cd frontend && flutter analyze lib/services/pwa_service.dart
```

Expected: no errors. Ignore "avoid_web_libraries_in_flutter" if it appears — `dart:js_interop` is the approved replacement for `dart:js`.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/services/pwa_service.dart
git commit -m "feat(pwa): add PwaService with dart:js_interop — install prompt, SW messages, push subscription"
```

---

## Task 6: Fix router auth guard

**Files:**
- Modify: `frontend/lib/config/router.dart:41-48`

- [ ] **Step 1: Add the `auth.loading` guard at the top of the `redirect` callback**

Find the `redirect` function (around line 41) and add one line at the top:

```dart
    redirect: (context, state) {
      if (auth.loading) return null; // wait for _tryAutoLogin before any redirect
      final loggedIn = auth.isAuthenticated;
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/config/router.dart
git commit -m "fix(router): defer redirect until auto-login resolves to preserve deep-link URLs"
```

---

## Task 7: Refactor `main.dart` and clean up `auth_provider.dart`

**Files:**
- Modify: `frontend/lib/main.dart`
- Modify: `frontend/lib/providers/auth_provider.dart`

- [ ] **Step 1: Convert `MitrooApp` to `StatefulWidget` in `main.dart`**

Replace the entire file with:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:go_router/go_router.dart';

import 'config/router.dart';
import 'providers/auth_provider.dart';
import 'providers/category_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/department_provider.dart';
import 'providers/item_provider.dart';
import 'providers/pwa_provider.dart';
import 'providers/service_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/vehicle_provider.dart';
import 'providers/victim_provider.dart';
import 'services/pwa_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('el_GR', null);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const MitrooApp());
}

class MitrooApp extends StatefulWidget {
  const MitrooApp({super.key});

  @override
  State<MitrooApp> createState() => _MitrooAppState();
}

class _MitrooAppState extends State<MitrooApp> {
  static const _primaryRed = Color(0xFFC62828);
  static const _accentRed = Color(0xFFE53935);

  late final AuthProvider _authProvider;
  late final PwaProvider _pwaProvider;
  late final GoRouter _router;
  StreamSubscription<String>? _navSub;

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider();
    _pwaProvider = PwaProvider();
    _router = appRouter(_authProvider);

    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await PwaService.init(_pwaProvider);
        _navSub = PwaService.navigateStream.listen(_router.go);
      });
    }
  }

  @override
  void dispose() {
    _navSub?.cancel();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = GoogleFonts.interTextTheme();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider.value(value: _pwaProvider),
        ChangeNotifierProvider(create: (_) => DepartmentProvider()),
        ChangeNotifierProvider(create: (_) => ServiceProvider()),
        ChangeNotifierProvider(create: (_) => ItemProvider()),
        ChangeNotifierProvider(create: (_) => VehicleProvider()),
        ChangeNotifierProvider(create: (_) => CategoryProvider()),
        ChangeNotifierProvider(create: (_) => SyncProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => VictimProvider()),
      ],
      child: MaterialApp.router(
        title: 'R.C.D.',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(
            seedColor: _primaryRed,
            brightness: Brightness.light,
            primary: _primaryRed,
            secondary: _accentRed,
            surface: Colors.white,
            onSurface: const Color(0xFF1A1C1E),
          ),
          scaffoldBackgroundColor: Colors.white,
          textTheme: baseTextTheme,
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            color: Colors.white,
            surfaceTintColor: Colors.transparent,
            margin: EdgeInsets.zero,
          ),
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: false,
            titleTextStyle: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1C1E),
              letterSpacing: -0.5,
            ),
            iconTheme: const IconThemeData(color: Color(0xFFC62828)),
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: Colors.white,
            elevation: 0,
            height: 56,
            indicatorColor: _primaryRed.withAlpha(25),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return baseTextTheme.labelSmall?.copyWith(
                  color: _primaryRed,
                  fontWeight: FontWeight.w600,
                );
              }
              return baseTextTheme.labelSmall
                  ?.copyWith(color: const Color(0xFF6B7280));
            }),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const IconThemeData(color: Color(0xFFC62828), size: 24);
              }
              return const IconThemeData(color: Color(0xFF6B7280), size: 24);
            }),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _primaryRed, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: _primaryRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
          floatingActionButtonTheme: FloatingActionButtonThemeData(
            backgroundColor: _primaryRed,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          dividerTheme: const DividerThemeData(
            color: Color(0xFFE8ECF0),
            thickness: 1,
          ),
        ),
        themeMode: ThemeMode.light,
        routerConfig: _router,
      ),
    );
  }
}
```

- [ ] **Step 2: Remove `PushService` from `auth_provider.dart`**

In `frontend/lib/providers/auth_provider.dart`, remove the import on line 3:

```dart
import '../services/push_service.dart';
```

And remove the push init call in `_loadCurrentUser` (around line 113-114):

```dart
  Future<void> _loadCurrentUser() async {
    final res = await _api.get('/auth/me');
    if (res.statusCode == 200) {
      _user = jsonDecode(res.body);
      // remove: if (kIsWeb) PushService.init();
    }
  }
```

Also remove the now-unused `import 'package:flutter/foundation.dart';` if `kIsWeb` was its only use. Check the file — if `kIsWeb` appears elsewhere keep the import.

- [ ] **Step 3: Run analysis**

```bash
cd frontend && flutter analyze lib/main.dart lib/providers/auth_provider.dart
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/main.dart frontend/lib/providers/auth_provider.dart
git commit -m "refactor(main): convert MitrooApp to StatefulWidget, wire PwaService and PwaProvider"
```

---

## Task 8: Add install dialog to `LoginScreen`

**Files:**
- Modify: `frontend/lib/screens/login_screen.dart`

- [ ] **Step 1: Add `PwaProvider` import**

At the top of `login_screen.dart`, add:

```dart
import '../providers/pwa_provider.dart';
```

- [ ] **Step 2: Add `_maybeShowInstallDialog` method to `_LoginScreenState`**

Add this method directly after the `_submit` method:

```dart
  void _maybeShowInstallDialog() {
    if (!mounted) return;
    final pwa = context.read<PwaProvider>();
    if (!pwa.shouldShowInstallDialog) return;
    pwa.markInstallDialogShown();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Προσθήκη στην αρχική οθόνη'),
        content: const Text(
          'Εγκαταστήστε το Mitroo για γρήγορη πρόσβαση χωρίς το πρόγραμμα περιήγησης.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Όχι τώρα'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.read<PwaProvider>().triggerInstall();
            },
            child: const Text('Εγκατάσταση'),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 3: Call `_maybeShowInstallDialog` on successful login in `_submit`**

Update the `_submit` method. After `auth.login()` returns `null` (success), add the dialog call:

```dart
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final err = await auth.login(_emailCtrl.text.trim(), _passwordCtrl.text);
    if (err != null && mounted) {
      setState(() => _error = err);
      return;
    }
    _maybeShowInstallDialog();
  }
```

- [ ] **Step 4: Run analysis**

```bash
cd frontend && flutter analyze lib/screens/login_screen.dart
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/login_screen.dart
git commit -m "feat(pwa): show install prompt dialog on first login when browser supports it"
```

---

## Task 9: Delete `push_service.dart` and `push_sw.js`

**Files:**
- Delete: `frontend/lib/services/push_service.dart`
- Delete: `frontend/web/push_sw.js`

- [ ] **Step 1: Delete both files**

```bash
rm frontend/lib/services/push_service.dart
rm frontend/web/push_sw.js
```

- [ ] **Step 2: Verify no remaining references**

```bash
cd frontend && grep -r "push_service\|push_sw\|PushService" lib/ web/
```

Expected: no output.

- [ ] **Step 3: Full analysis pass**

```bash
cd frontend && flutter analyze
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add -u
git commit -m "refactor(pwa): delete PushService and push_sw.js — replaced by PwaService and sw.js"
```

---

## Manual Verification Checklist

After all tasks are complete, open the app in Chrome and verify:

1. **Push subscription** — Open DevTools → Application → Service Workers. Confirm `sw.js` is registered and active (not `push_sw.js`).

2. **Install prompt** — Log out and log back in on a non-installed browser session. The "Προσθήκη στην αρχική οθόνη" dialog should appear. Dismiss it. Log out and log back in — dialog should NOT appear again.

3. **Notification deep-link (app open)** — Send a test push with `route: "/services/1"` (via the backend). Click the notification while the app is open. Verify navigation to `/services/1` without opening a duplicate tab.

4. **Notification deep-link (app closed)** — Close all tabs. Receive a push with `route: "/services/1"`. Click it. The app should open directly at `/services/1` if the JWT is still valid.

5. **Cold-start deep-link** — Navigate directly to `http://localhost:8080/services/1` (not from a notification). If logged in, you should land on `/services/1`. If not logged in, you should land on `/login`. After logging in, GoRouter should redirect to `/services` (not the original URL — that is the existing behavior and is acceptable for manual URL entry).
