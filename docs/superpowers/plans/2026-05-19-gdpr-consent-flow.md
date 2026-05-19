# GDPR Consent Flow — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show an unskippable GDPR consent dialog to any user who has not yet accepted, persist the acceptance timestamp, and redirect decliners back to `/login`.

**Architecture:** A nullable `gdprAcceptedAt` column on the `users` table gates access. The backend login endpoint and `/auth/me` both return this field; the frontend holds an `_gdprConsentRequired` flag in `AuthProvider` that keeps `isAuthenticated` false until consent is recorded. The dialog is shown from `LoginScreen` for both fresh logins and auto-logins (stored token, existing users).

**Tech Stack:** Prisma (PostgreSQL migration), TypeScript/Express backend, Flutter/Dart frontend, `go_router`, `provider`, `shared_preferences`.

---

## File Map

| Action | File | Purpose |
|--------|------|---------|
| Modify | `backend/prisma/schema.prisma` | Add `gdprAcceptedAt` field to `User` model |
| Modify | `backend/src/routes/auth.routes.ts` | Update `AuthUser` type, `selectAuthUser`, both login responses, `/me` select; add `/gdpr-consent` route |
| Modify | `frontend/lib/providers/auth_provider.dart` | Add `_gdprConsentRequired` state, `acceptGdpr()`, `declineGdpr()`; update `login()` and `_tryAutoLogin()` |
| Create | `frontend/lib/widgets/gdpr_consent_dialog.dart` | Stateful dialog with Greek/English toggle and accept/decline callbacks |
| Modify | `frontend/lib/screens/login_screen.dart` | Call `_showGdprDialog()` from `_submit()` and auto-show via `build()` for auto-login path |

---

## Task 1: Add `gdprAcceptedAt` to the database

**Files:**
- Modify: `backend/prisma/schema.prisma`
- Auto-created: `backend/prisma/migrations/[timestamp]_add_gdpr_accepted_at/migration.sql`

- [ ] **Step 1.1: Add field to User model**

In `backend/prisma/schema.prisma`, inside `model User`, after the `passwordResetExpires` line and before `createdAt`, add:

```prisma
  gdprAcceptedAt   DateTime? @map("gdpr_accepted_at")
```

The surrounding context should look like:
```prisma
  passwordResetToken   String?   @unique @map("password_reset_token") @db.VarChar(255)
  passwordResetExpires DateTime? @map("password_reset_expires")

  gdprAcceptedAt   DateTime? @map("gdpr_accepted_at")

  createdAt DateTime @default(now()) @map("created_at")
  updatedAt DateTime @updatedAt @map("updated_at")
```

- [ ] **Step 1.2: Generate and apply migration**

```bash
cd backend
npm run prisma:migrate
```

When prompted for a migration name, enter: `add_gdpr_accepted_at`

Expected output includes: `The following migration(s) have been created and applied` and `Your database is now in sync with your schema.`

- [ ] **Step 1.3: Verify column exists**

```bash
cd backend
npm run prisma:studio
```

Open the `users` table — confirm `gdpr_accepted_at` column exists and all existing rows show `null`.

Close Prisma Studio when done.

- [ ] **Step 1.4: Commit**

```bash
git add backend/prisma/schema.prisma backend/prisma/migrations/
git commit -m "feat(db): add gdpr_accepted_at to users table"
```

---

## Task 2: Update backend login responses and add `/gdpr-consent` endpoint

**Files:**
- Modify: `backend/src/routes/auth.routes.ts`

- [ ] **Step 2.1: Update `AuthUser` type and `selectAuthUser`**

In `backend/src/routes/auth.routes.ts`, replace the `AuthUser` type and `selectAuthUser` constant (lines 30–50) with:

```ts
type AuthUser = {
  id: number;
  eame: string;
  forename: string;
  surname: string;
  email: string;
  rank: string;
  isAdmin: boolean;
  imagePath: string | null;
  gdprAcceptedAt: Date | null;
};

const selectAuthUser = {
  id: true,
  eame: true,
  forename: true,
  surname: true,
  email: true,
  rank: true,
  isAdmin: true,
  imagePath: true,
  gdprAcceptedAt: true,
};
```

- [ ] **Step 2.2: Update external-Mitroo login response**

Find the line (around line 296) in the external-Mitroo login path inside `router.post("/login", ...)`:
```ts
      res.json({ user: externalResult.user, token });
```

Replace it with:
```ts
      res.json({
        user: externalResult.user,
        token,
        gdprConsentRequired: !externalResult.user!.gdprAcceptedAt,
      });
```

- [ ] **Step 2.3: Update local-password login response**

Find the local-password success response (around lines 312–325):
```ts
    res.json({
      user: {
        id: user.id,
        eame: user.eame,
        forename: user.forename,
        surname: user.surname,
        email: user.email,
        rank: user.rank,
        isAdmin: user.isAdmin,
        imagePath: user.imagePath,
      },
      token,
    });
```

Replace it with:
```ts
    res.json({
      user: {
        id: user.id,
        eame: user.eame,
        forename: user.forename,
        surname: user.surname,
        email: user.email,
        rank: user.rank,
        isAdmin: user.isAdmin,
        imagePath: user.imagePath,
      },
      token,
      gdprConsentRequired: !user.gdprAcceptedAt,
    });
```

- [ ] **Step 2.4: Add `gdprAcceptedAt` to the `/auth/me` select**

In the `router.get("/me", ...)` handler, find the `select` object and add `gdprAcceptedAt: true,` after `extraInfo: true,`:

```ts
    select: {
      id: true, eame: true, forename: true, surname: true, email: true,
      rank: true,
      isAdmin: true, imagePath: true, phonePrimary: true, phoneSecondary: true,
      birthDate: true, address: true, extraInfo: true,
      gdprAcceptedAt: true,
      departments: { include: { department: { select: { id: true, name: true } } } },
      specializations: {
        include: { specialization: { select: { id: true, name: true, description: true } } },
      },
    },
```

- [ ] **Step 2.5: Add `POST /api/auth/gdpr-consent` endpoint**

After the closing brace of the `router.get("/me", ...)` handler and before `router.get("/me/profile", ...)`, add:

```ts
// ── POST /api/auth/gdpr-consent ─────────────────
router.post("/gdpr-consent", authenticate, async (req: Request, res: Response) => {
  await prisma.user.update({
    where: { id: req.user!.userId },
    data: { gdprAcceptedAt: new Date() },
  });
  res.json({ ok: true });
});
```

- [ ] **Step 2.6: Verify TypeScript compiles**

```bash
cd backend
npm run build
```

Expected: no errors, `dist/` updated.

- [ ] **Step 2.7: Start backend and test login response**

```bash
cd backend
npm run dev
```

In a second terminal (replace email/password with a real test user):
```bash
curl -s -X POST http://localhost:4000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"testpassword"}' | jq '{gdprConsentRequired, token: .token[0:20]}'
```

Expected: `{ "gdprConsentRequired": true, "token": "<first 20 chars>" }` — `true` because all existing users have `gdpr_accepted_at = NULL`.

- [ ] **Step 2.8: Test `/gdpr-consent` endpoint**

```bash
TOKEN=$(curl -s -X POST http://localhost:4000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"testpassword"}' | jq -r '.token')

curl -s -X POST http://localhost:4000/api/auth/gdpr-consent \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'
```

Expected: `{"ok":true}`

Re-run the login test — `gdprConsentRequired` should now be `false` for this user.

- [ ] **Step 2.9: Commit**

```bash
git add backend/src/routes/auth.routes.ts
git commit -m "feat(auth): add gdprConsentRequired to login response and gdpr-consent endpoint"
```

---

## Task 3: Update `AuthProvider` with GDPR consent state and methods

**Files:**
- Modify: `frontend/lib/providers/auth_provider.dart`

- [ ] **Step 3.1: Add `_gdprConsentRequired` field and getter**

In `_LoginScreenState`, after `bool _loading = false;`, add:
```dart
  bool _gdprConsentRequired = false;
```

After `bool get loading => _loading;`, add:
```dart
  bool get gdprConsentRequired => _gdprConsentRequired;
```

- [ ] **Step 3.2: Update `login()` to detect GDPR requirement**

Replace the entire `login()` method with:

```dart
  Future<String?> login(String email, String password) async {
    _loading = true;
    notifyListeners();
    try {
      final res = await _api.post('/auth/login', body: {
        'email': email,
        'password': password,
      });
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        await _api.setToken(data['token']);
        if (data['gdprConsentRequired'] == true) {
          _gdprConsentRequired = true;
          _loading = false;
          notifyListeners();
          return null;
        }
        _user = data['user'];
        try {
          await _loadCurrentUser();
        } catch (_) {}
        _loading = false;
        notifyListeners();
        return null;
      }
      _loading = false;
      notifyListeners();
      return data['error'] ?? 'Login failed';
    } catch (e) {
      _loading = false;
      notifyListeners();
      return 'Connection error: $e';
    }
  }
```

- [ ] **Step 3.3: Update `_tryAutoLogin()` to detect GDPR requirement**

Replace the entire `_tryAutoLogin()` method with:

```dart
  Future<void> _tryAutoLogin() async {
    _loading = true;
    notifyListeners();
    try {
      await _api.loadToken();
      final res = await _api.get('/auth/me');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['gdprAcceptedAt'] == null) {
          _gdprConsentRequired = true;
        } else {
          _user = data;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('cached_user', res.body);
        }
      }
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_user');
      if (cached != null) {
        final data = jsonDecode(cached) as Map<String, dynamic>;
        if (data['gdprAcceptedAt'] != null) {
          _user = data;
        }
      }
    }
    _loading = false;
    notifyListeners();
  }
```

- [ ] **Step 3.4: Add `acceptGdpr()` method**

After the `login()` method, add:

```dart
  Future<void> acceptGdpr() async {
    await _api.post('/auth/gdpr-consent', body: {});
    _gdprConsentRequired = false;
    await _loadCurrentUser();
    notifyListeners();
  }
```

- [ ] **Step 3.5: Add `declineGdpr()` method**

After `acceptGdpr()`, add:

```dart
  Future<void> declineGdpr() async {
    _gdprConsentRequired = false;
    await logout();
  }
```

- [ ] **Step 3.6: Commit**

```bash
git add frontend/lib/providers/auth_provider.dart
git commit -m "feat(auth): add GDPR consent state and methods to AuthProvider"
```

---

## Task 4: Create `GdprConsentDialog` widget

**Files:**
- Create: `frontend/lib/widgets/gdpr_consent_dialog.dart`

- [ ] **Step 4.1: Create the file**

Create `frontend/lib/widgets/gdpr_consent_dialog.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class GdprConsentDialog extends StatefulWidget {
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const GdprConsentDialog({
    super.key,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<GdprConsentDialog> createState() => _GdprConsentDialogState();
}

class _GdprConsentDialogState extends State<GdprConsentDialog> {
  bool _showEnglish = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Πολιτική Απορρήτου',
        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _showEnglish ? _englishText : _greekText,
                style: GoogleFonts.inter(fontSize: 14, height: 1.6),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => _showEnglish = !_showEnglish),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 28),
                ),
                child: Text(
                  _showEnglish
                      ? 'Εμφάνιση στα Ελληνικά'
                      : 'Show in English',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF6B7280),
                    decoration: TextDecoration.underline,
                    decorationColor: const Color(0xFF6B7280),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onDecline,
          child: Text(
            'Δεν αποδέχομαι',
            style: GoogleFonts.inter(color: const Color(0xFF6B7280)),
          ),
        ),
        FilledButton(
          onPressed: widget.onAccept,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFC62828),
          ),
          child: Text(
            'Αποδέχομαι',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

const _greekText =
    'Η εφαρμογή Mitroo συλλέγει και επεξεργάζεται τα προσωπικά σας δεδομένα '
    '(ονοματεπώνυμο, email, τηλέφωνο, διεύθυνση, ημερομηνία γέννησης, ειδικότητες) '
    'αποκλειστικά για τη διαχείριση αποστολών και πόρων του Ελληνικού Ερυθρού Σταυρού. '
    'Τα δεδομένα αποθηκεύονται σε ασφαλείς διακομιστές και δεν κοινοποιούνται σε τρίτους '
    'εκτός Ε.Ε.Σ. Έχετε δικαίωμα πρόσβασης, διόρθωσης και διαγραφής των δεδομένων σας '
    'επικοινωνώντας με τον διαχειριστή. Με την αποδοχή, συναινείτε στην επεξεργασία των '
    'δεδομένων σας σύμφωνα με τον ΓΚΠΔ (Κανονισμός ΕΕ 2016/679).';

const _englishText =
    'The Mitroo application collects and processes your personal data '
    '(name, email, phone, address, date of birth, specializations) solely for mission '
    'and resource management within the Hellenic Red Cross. Data is stored on secure '
    'servers and is not shared with third parties outside H.R.C. You have the right to '
    'access, correct, and delete your data by contacting the administrator. By accepting, '
    'you consent to the processing of your data in accordance with the GDPR '
    '(EU Regulation 2016/679).';
```

- [ ] **Step 4.2: Commit**

```bash
git add frontend/lib/widgets/gdpr_consent_dialog.dart
git commit -m "feat(ui): add GdprConsentDialog with Greek/English toggle"
```

---

## Task 5: Wire up `GdprConsentDialog` in `LoginScreen`

**Files:**
- Modify: `frontend/lib/screens/login_screen.dart`

- [ ] **Step 5.1: Add import**

At the top of `frontend/lib/screens/login_screen.dart`, after the existing imports, add:

```dart
import '../widgets/gdpr_consent_dialog.dart';
```

- [ ] **Step 5.2: Add `_gdprDialogScheduled` flag to state**

In `_LoginScreenState`, after `bool _obscurePassword = true;`, add:

```dart
  bool _gdprDialogScheduled = false;
```

- [ ] **Step 5.3: Add `_showGdprDialog()` method**

Add this method to `_LoginScreenState` after the `_maybeShowInstallDialog()` method:

```dart
  void _showGdprDialog() {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => GdprConsentDialog(
        onDecline: () {
          Navigator.of(ctx).pop();
          auth.declineGdpr();
        },
        onAccept: () {
          Navigator.of(ctx).pop();
          _maybeShowInstallDialog();
          auth.acceptGdpr();
        },
      ),
    );
  }
```

- [ ] **Step 5.4: Update `_submit()` to show GDPR dialog when needed**

Replace the entire `_submit()` method with:

```dart
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final err = await auth.login(_emailCtrl.text.trim(), _passwordCtrl.text);
    if (err != null && mounted) {
      setState(() => _error = err);
      return;
    }
    if (!mounted) return;
    if (auth.gdprConsentRequired) {
      _gdprDialogScheduled = true;
      _showGdprDialog();
    } else {
      _maybeShowInstallDialog();
    }
  }
```

- [ ] **Step 5.5: Auto-show dialog on auto-login for existing users**

In the `build()` method of `_LoginScreenState`, add the GDPR auto-show check immediately after `final auth = context.watch<AuthProvider>();`:

```dart
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.gdprConsentRequired && !auth.loading && !_gdprDialogScheduled) {
      _gdprDialogScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showGdprDialog());
    }
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;
    // ... rest of build unchanged
```

- [ ] **Step 5.6: Run the app and verify all three flows**

```bash
cd frontend
flutter run -d chrome
```

**Flow A — Fresh login, decline:**
1. Enter credentials and submit → GDPR dialog appears in Greek, cannot be dismissed by clicking outside
2. Click "Show in English" → text switches to English
3. Click "Εμφάνιση στα Ελληνικά" → switches back
4. Click "Δεν αποδέχομαι" → dialog closes, user stays on `/login`, form is empty and usable

**Flow B — Fresh login, accept:**
1. Enter credentials and submit → GDPR dialog appears
2. Click "Αποδέχομαι" → dialog closes, user is redirected to `/services`
3. Logout → login again → **no GDPR dialog** (consent was recorded)

**Flow C — Auto-login with stored token (existing users without consent):**

Simulate by resetting consent in the DB:
```bash
cd backend
npx prisma studio
```
In Prisma Studio, find a user and set `gdpr_accepted_at` to `null`. Save, close Prisma Studio.

4. Reload the browser (app auto-logs in with stored token) → GDPR dialog appears automatically on top of the login screen
5. Click "Αποδέχομαι" → redirected to `/services`

- [ ] **Step 5.7: Commit**

```bash
git add frontend/lib/screens/login_screen.dart
git commit -m "feat(login): show unskippable GDPR consent dialog on first login"
```

---

## Self-Review Notes

- `_gdprConsentRequired` is reset to `false` in both `acceptGdpr()` and `declineGdpr()` before navigation fires, preventing re-show.
- `declineGdpr()` calls `logout()` which clears the stored JWT, so on next app load `_tryAutoLogin()` fails cleanly and the user must log in again (triggering the dialog via `_submit()`).
- Cached user data from offline mode only restores `_user` if `gdprAcceptedAt != null` — users who haven't consented cannot access the app in offline mode.
- The PWA install dialog (`_maybeShowInstallDialog`) is called from inside `onAccept` before `auth.acceptGdpr()` navigates away, so both dialogs can stack while `LoginScreen` is still mounted.
