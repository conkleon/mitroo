# Login Screen Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the split-panel branded login screen with a clean centered card that matches the app's Material 3 design language, and remove the register/training-application flows.

**Architecture:** Single-file rewrite of `login_screen.dart`. All decorative brand-panel widgets are deleted. The new screen is a `Scaffold` with a centered white card, a 3px red top border, and a minimal form containing only the login flow. No other files change.

**Tech Stack:** Flutter (Web), Material 3, `provider`, `go_router`, `google_fonts` (dropped from this screen)

---

## Files

| Action | Path |
|--------|------|
| Rewrite | `frontend/lib/screens/login_screen.dart` |

No other files are touched. `AuthProvider.register()` stays in the provider — it's just no longer called from the UI.

---

### Task 1: Rewrite `login_screen.dart`

**Files:**
- Modify: `frontend/lib/screens/login_screen.dart`

- [ ] **Step 1: Open the current file and verify imports**

Read `frontend/lib/screens/login_screen.dart`. Note the current imports — `google_fonts`, `dart:math`, `go_router`, `provider`, `auth_provider`. The new file drops `google_fonts` and `dart:math`.

- [ ] **Step 2: Replace the entire file with the new implementation**

Replace the full contents of `frontend/lib/screens/login_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final err = await auth.login(_emailCtrl.text.trim(), _passwordCtrl.text);
    if (err != null && mounted) {
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border(
                  top: BorderSide(color: cs.primary, width: 3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(15),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Image.asset('assets/logo.png', height: 40),
                        const SizedBox(width: 10),
                        Text(
                          'R.C.D.',
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Συνδεθείτε με τα διαπιστευτήριά σας',
                      style: tt.bodySmall?.copyWith(
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (_error != null) ...[
                      _ErrorBanner(message: _error!),
                      const SizedBox(height: 20),
                    ],
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF1A1C1E),
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(
                          Icons.email_outlined,
                          size: 20,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Εισάγετε έγκυρο email'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF1A1C1E),
                      ),
                      decoration: InputDecoration(
                        labelText: 'Κωδικός',
                        prefixIcon: const Icon(
                          Icons.lock_outline_rounded,
                          size: 20,
                          color: Color(0xFF9CA3AF),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                            color: const Color(0xFF9CA3AF),
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 4)
                          ? 'Τουλάχιστον 4 χαρακτήρες'
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => context.go('/forgot-password'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          minimumSize: const Size(0, 28),
                        ),
                        child: const Text(
                          'Ξεχάσατε τον κωδικό;',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: auth.loading ? null : _submit,
                        child: auth.loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Σύνδεση',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: Color(0xFFDC2626),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFDC2626),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Run the Flutter analyzer to catch any issues**

```bash
cd frontend
flutter analyze lib/screens/login_screen.dart
```

Expected: no errors. If it reports `Unused import 'google_fonts'` or similar — those imports were already removed in the new file, so this should be clean.

- [ ] **Step 4: Run the app and visually verify**

```bash
cd frontend
flutter run -d chrome
```

Check:
- Login screen shows a centered white card on a light gray background
- Card has a red top border accent
- Logo + "R.C.D." header appears at the top of the card
- Email and password fields render correctly
- "Ξεχάσατε τον κωδικό;" link is present and right-aligned
- "Σύνδεση" button fills the card width
- **No** register toggle, sign-up link, or training application button is visible
- On a narrow browser window (< 900px): card is full-width with horizontal padding, no split panel
- Entering invalid credentials shows the red error banner inside the card
- Tapping "Ξεχάσατε τον κωδικό;" navigates to the forgot-password screen

- [ ] **Step 5: Commit**

```bash
cd ..
git add frontend/lib/screens/login_screen.dart
git commit -m "feat: redesign login screen to match app Material 3 style

Replace split-panel branded layout with a centered card. Remove register
and training application flows. Drop Playfair Display / decorative painters."
```
