# Universal Style System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Centralize the frontend's hardcoded colors, font sizes/weights, and border radii into a shared `lib/theme/` token system, and migrate all 38 screens (plus widgets/helpers) to use it, with zero visual change.

**Architecture:** Four small token files (`app_colors.dart`, `app_text_styles.dart`, `app_radius.dart`, `app_spacing.dart`) + a barrel (`theme.dart`) under `frontend/lib/theme/`. `main.dart`'s `ThemeData` is rewired by hand to read from these tokens. Every other occurrence across `lib/` is migrated by a Node.js codemod script that does pure 1:1 value substitution (documented in the design spec) — safe to run unattended because every mapping is a lossless value swap, not a judgment call.

**Tech Stack:** Flutter/Dart (frontend), Node.js (one-off migration script, not shipped — lives in `frontend/scripts/`).

## Global Constraints

- Every existing color/size/weight/radius value must be preserved exactly — this is centralization, not a redesign. (Design spec, Non-goals.)
- `Colors.white`/`Colors.black`/`Colors.transparent` and bare `Colors.red`/`Colors.amber`/`Colors.orange` are left untouched — not part of this migration. (Design spec, Non-goals.)
- Raw `EdgeInsets` / padding numeric literals are left untouched. (Design spec, Non-goals.)
- No dark mode — light-mode values only. (Design spec, Non-goals.)
- Package name for imports is `mitroo_frontend` (from `frontend/pubspec.yaml`).
- Flutter SDK in use: 3.32.2 stable, Dart SDK `>=3.2.0 <4.0.0` — avoid `Color.value` (potentially deprecated on newer Flutter); compare colors with `==` against `const Color(0x...)` in tests instead.

---

### Task 1: `AppColors` token file

**Files:**
- Create: `frontend/lib/theme/app_colors.dart`
- Test: `frontend/test/theme/app_colors_test.dart`

**Interfaces:**
- Produces: `AppColors` class with ~70 named `static const Color` fields (brand, gray, red, orange, amber, green/emerald, teal, cyan, blue/indigo, violet families) plus semantic aliases (`success`, `successBg`, `danger`, `dangerBg`, `warning`, `warningBg`, `info`, `infoBg`, `accent`, `accentBg`, `textPrimary`, `textSecondary`, `textTertiary`, `border`). Full name→hex mapping is fixed by the design spec (`docs/superpowers/specs/2026-08-08-universal-style-system-design.md`) — do not rename or add tokens beyond what's listed there.

- [ ] **Step 1: Write the failing test**

Create `frontend/test/theme/app_colors_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitroo_frontend/theme/theme.dart';

void main() {
  group('AppColors', () {
    test('brand colors match original main.dart constants', () {
      expect(AppColors.brandPrimary, const Color(0xFFC62828));
      expect(AppColors.brandAccent, const Color(0xFFE53935));
      expect(AppColors.brandDark, const Color(0xFF6B0000));
    });

    test('gray scale matches Tailwind gray values', () {
      expect(AppColors.gray50, const Color(0xFFF9FAFB));
      expect(AppColors.gray100, const Color(0xFFF3F4F6));
      expect(AppColors.gray200, const Color(0xFFE5E7EB));
      expect(AppColors.gray300, const Color(0xFFD1D5DB));
      expect(AppColors.gray400, const Color(0xFF9CA3AF));
      expect(AppColors.gray500, const Color(0xFF6B7280));
      expect(AppColors.gray600, const Color(0xFF4B5563));
      expect(AppColors.gray700, const Color(0xFF374151));
      expect(AppColors.gray800, const Color(0xFF1F2937));
      expect(AppColors.gray900, const Color(0xFF111827));
    });

    test('neutral extras match custom near-gray values', () {
      expect(AppColors.ink, const Color(0xFF1A1C1E));
      expect(AppColors.borderSubtle, const Color(0xFFE0E0E0));
      expect(AppColors.divider, const Color(0xFFE8ECF0));
      expect(AppColors.surfaceTint, const Color(0xFFEEF0F4));
      expect(AppColors.surfaceTint2, const Color(0xFFE9EBF0));
      expect(AppColors.slate50, const Color(0xFFF8FAFC));
      expect(AppColors.surfaceAlt, const Color(0xFFF5F7FA));
    });

    test('red scale matches Tailwind red values', () {
      expect(AppColors.red50, const Color(0xFFFEF2F2));
      expect(AppColors.red100, const Color(0xFFFEE2E2));
      expect(AppColors.red200, const Color(0xFFFECACA));
      expect(AppColors.red300, const Color(0xFFFCA5A5));
      expect(AppColors.red400, const Color(0xFFF87171));
      expect(AppColors.red500, const Color(0xFFEF4444));
      expect(AppColors.red600, const Color(0xFFDC2626));
      expect(AppColors.red700, const Color(0xFFB91C1C));
      expect(AppColors.red800, const Color(0xFF991B1B));
    });

    test('orange scale matches expected values', () {
      expect(AppColors.orange50, const Color(0xFFFFF7ED));
      expect(AppColors.orange300, const Color(0xFFFED7AA));
      expect(AppColors.orange600, const Color(0xFFEA580C));
      expect(AppColors.orange700, const Color(0xFFC2410C));
      expect(AppColors.orange800, const Color(0xFF9A3412));
      expect(AppColors.orangeDeep, const Color(0xFFD84315));
    });

    test('amber scale matches Tailwind amber values', () {
      expect(AppColors.amber50, const Color(0xFFFFFBEB));
      expect(AppColors.amber100, const Color(0xFFFEF3C7));
      expect(AppColors.amber300, const Color(0xFFFDE68A));
      expect(AppColors.amber500, const Color(0xFFF59E0B));
      expect(AppColors.amber600, const Color(0xFFD97706));
      expect(AppColors.amber700, const Color(0xFFB45309));
      expect(AppColors.amber800, const Color(0xFF92400E));
    });

    test('green/emerald scale matches expected values', () {
      expect(AppColors.green50, const Color(0xFFF0FDF4));
      expect(AppColors.green200, const Color(0xFFBBF7D0));
      expect(AppColors.emerald100, const Color(0xFFD1FAE5));
      expect(AppColors.emerald500, const Color(0xFF10B981));
      expect(AppColors.emerald600, const Color(0xFF059669));
    });

    test('teal, cyan, sky match expected values', () {
      expect(AppColors.teal600, const Color(0xFF0D9488));
      expect(AppColors.teal700, const Color(0xFF0F766E));
      expect(AppColors.cyan50, const Color(0xFFECFEFF));
      expect(AppColors.cyan600, const Color(0xFF0891B2));
      expect(AppColors.sky500, const Color(0xFF0EA5E9));
    });

    test('blue/indigo scale matches expected values', () {
      expect(AppColors.indigo50, const Color(0xFFEEF2FF));
      expect(AppColors.blue100, const Color(0xFFDBEAFE));
      expect(AppColors.blue500, const Color(0xFF3B82F6));
      expect(AppColors.blue600, const Color(0xFF2563EB));
      expect(AppColors.blue700, const Color(0xFF1D4ED8));
      expect(AppColors.blueDeep, const Color(0xFF0D47A1));
      expect(AppColors.indigo500, const Color(0xFF6366F1));
      expect(AppColors.indigo950, const Color(0xFF1E1B4B));
    });

    test('violet scale matches expected values', () {
      expect(AppColors.violet50, const Color(0xFFF5F3FF));
      expect(AppColors.violet100, const Color(0xFFEDE9FE));
      expect(AppColors.violet200, const Color(0xFFDDD6FE));
      expect(AppColors.violet500, const Color(0xFF8B5CF6));
      expect(AppColors.violet600, const Color(0xFF7C3AED));
      expect(AppColors.violet700, const Color(0xFF6D28D9));
      expect(AppColors.violet800, const Color(0xFF5B21B6));
    });

    test('semantic aliases point at the correct palette tokens', () {
      expect(AppColors.success, AppColors.emerald600);
      expect(AppColors.successBg, AppColors.emerald100);
      expect(AppColors.danger, AppColors.red600);
      expect(AppColors.dangerBg, AppColors.red100);
      expect(AppColors.warning, AppColors.amber600);
      expect(AppColors.warningBg, AppColors.amber100);
      expect(AppColors.info, AppColors.cyan600);
      expect(AppColors.infoBg, AppColors.cyan50);
      expect(AppColors.accent, AppColors.violet600);
      expect(AppColors.accentBg, AppColors.violet100);
      expect(AppColors.textPrimary, AppColors.ink);
      expect(AppColors.textSecondary, AppColors.gray500);
      expect(AppColors.textTertiary, AppColors.gray400);
      expect(AppColors.border, AppColors.gray200);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `frontend/`): `flutter test test/theme/app_colors_test.dart`
Expected: FAIL — `package:mitroo_frontend/theme/theme.dart` doesn't exist yet.

- [ ] **Step 3: Create the theme directory and `AppColors`**

Create `frontend/lib/theme/app_colors.dart`:

```dart
import 'package:flutter/material.dart';

/// Design-system color tokens. Named after their Tailwind CSS shade where
/// the value matches Tailwind's default palette exactly; a handful of
/// custom brand/near-gray values are named descriptively instead.
class AppColors {
  AppColors._();

  // Brand
  static const Color brandPrimary = Color(0xFFC62828);
  static const Color brandAccent = Color(0xFFE53935);
  static const Color brandDark = Color(0xFF6B0000);

  // Gray
  static const Color gray50 = Color(0xFFF9FAFB);
  static const Color gray100 = Color(0xFFF3F4F6);
  static const Color gray200 = Color(0xFFE5E7EB);
  static const Color gray300 = Color(0xFFD1D5DB);
  static const Color gray400 = Color(0xFF9CA3AF);
  static const Color gray500 = Color(0xFF6B7280);
  static const Color gray600 = Color(0xFF4B5563);
  static const Color gray700 = Color(0xFF374151);
  static const Color gray800 = Color(0xFF1F2937);
  static const Color gray900 = Color(0xFF111827);

  // Neutral extras (custom near-gray values, kept exact — do not collapse
  // into the gray scale above, they are not the same value).
  static const Color ink = Color(0xFF1A1C1E);
  static const Color borderSubtle = Color(0xFFE0E0E0);
  static const Color divider = Color(0xFFE8ECF0);
  static const Color surfaceTint = Color(0xFFEEF0F4);
  static const Color surfaceTint2 = Color(0xFFE9EBF0);
  static const Color slate50 = Color(0xFFF8FAFC);
  static const Color surfaceAlt = Color(0xFFF5F7FA);

  // Red
  static const Color red50 = Color(0xFFFEF2F2);
  static const Color red100 = Color(0xFFFEE2E2);
  static const Color red200 = Color(0xFFFECACA);
  static const Color red300 = Color(0xFFFCA5A5);
  static const Color red400 = Color(0xFFF87171);
  static const Color red500 = Color(0xFFEF4444);
  static const Color red600 = Color(0xFFDC2626);
  static const Color red700 = Color(0xFFB91C1C);
  static const Color red800 = Color(0xFF991B1B);

  // Orange
  static const Color orange50 = Color(0xFFFFF7ED);
  static const Color orange300 = Color(0xFFFED7AA);
  static const Color orange600 = Color(0xFFEA580C);
  static const Color orange700 = Color(0xFFC2410C);
  static const Color orange800 = Color(0xFF9A3412);
  static const Color orangeDeep = Color(0xFFD84315);

  // Amber
  static const Color amber50 = Color(0xFFFFFBEB);
  static const Color amber100 = Color(0xFFFEF3C7);
  static const Color amber300 = Color(0xFFFDE68A);
  static const Color amber500 = Color(0xFFF59E0B);
  static const Color amber600 = Color(0xFFD97706);
  static const Color amber700 = Color(0xFFB45309);
  static const Color amber800 = Color(0xFF92400E);

  // Green / Emerald
  static const Color green50 = Color(0xFFF0FDF4);
  static const Color green200 = Color(0xFFBBF7D0);
  static const Color emerald100 = Color(0xFFD1FAE5);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald600 = Color(0xFF059669);

  // Teal
  static const Color teal600 = Color(0xFF0D9488);
  static const Color teal700 = Color(0xFF0F766E);

  // Cyan / Sky
  static const Color cyan50 = Color(0xFFECFEFF);
  static const Color cyan600 = Color(0xFF0891B2);
  static const Color sky500 = Color(0xFF0EA5E9);

  // Blue / Indigo
  static const Color indigo50 = Color(0xFFEEF2FF);
  static const Color blue100 = Color(0xFFDBEAFE);
  static const Color blue500 = Color(0xFF3B82F6);
  static const Color blue600 = Color(0xFF2563EB);
  static const Color blue700 = Color(0xFF1D4ED8);
  static const Color blueDeep = Color(0xFF0D47A1);
  static const Color indigo500 = Color(0xFF6366F1);
  static const Color indigo950 = Color(0xFF1E1B4B);

  // Violet / Purple
  static const Color violet50 = Color(0xFFF5F3FF);
  static const Color violet100 = Color(0xFFEDE9FE);
  static const Color violet200 = Color(0xFFDDD6FE);
  static const Color violet500 = Color(0xFF8B5CF6);
  static const Color violet600 = Color(0xFF7C3AED);
  static const Color violet700 = Color(0xFF6D28D9);
  static const Color violet800 = Color(0xFF5B21B6);

  // Semantic aliases (point at the tokens above; use where the meaning is
  // consistent, e.g. status chips / role badges).
  static const Color success = emerald600;
  static const Color successBg = emerald100;
  static const Color danger = red600;
  static const Color dangerBg = red100;
  static const Color warning = amber600;
  static const Color warningBg = amber100;
  static const Color info = cyan600;
  static const Color infoBg = cyan50;
  static const Color accent = violet600;
  static const Color accentBg = violet100;
  static const Color textPrimary = ink;
  static const Color textSecondary = gray500;
  static const Color textTertiary = gray400;
  static const Color border = gray200;
}
```

Create `frontend/lib/theme/theme.dart` (barrel — starts with just this export, more added in later tasks):

```dart
export 'app_colors.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/theme/app_colors_test.dart`
Expected: PASS (all tests green).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/theme/app_colors.dart frontend/lib/theme/theme.dart frontend/test/theme/app_colors_test.dart
git commit -m "feat(theme): add AppColors design tokens"
```

---

### Task 2: `AppFontSize` / `AppFontWeight` / `AppTextStyles`

**Files:**
- Create: `frontend/lib/theme/app_text_styles.dart`
- Modify: `frontend/lib/theme/theme.dart`
- Test: `frontend/test/theme/app_text_styles_test.dart`

**Interfaces:**
- Consumes: none.
- Produces: `AppFontSize` (15 `static const double` fields: `xxs, xs, sm, base, md, lg, xl, xl2, xl3, xl4, xl5, display, display2, display3, hero`), `AppFontWeight` (5 `static const FontWeight` fields: `regular, medium, semibold, bold, extrabold`), `AppTextStyles` (8 `static const TextStyle` fields: `heading1, sectionTitle, cardTitle, subtitle, body, bodyStrong, caption, label`).

- [ ] **Step 1: Write the failing test**

Create `frontend/test/theme/app_text_styles_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitroo_frontend/theme/theme.dart';

void main() {
  group('AppFontSize', () {
    test('matches every distinct fontSize literal found in the codebase', () {
      expect(AppFontSize.xxs, 9);
      expect(AppFontSize.xs, 10);
      expect(AppFontSize.sm, 11);
      expect(AppFontSize.base, 12);
      expect(AppFontSize.md, 13);
      expect(AppFontSize.lg, 14);
      expect(AppFontSize.xl, 15);
      expect(AppFontSize.xl2, 16);
      expect(AppFontSize.xl3, 18);
      expect(AppFontSize.xl4, 20);
      expect(AppFontSize.xl5, 22);
      expect(AppFontSize.display, 28);
      expect(AppFontSize.display2, 30);
      expect(AppFontSize.display3, 32);
      expect(AppFontSize.hero, 52);
    });
  });

  group('AppFontWeight', () {
    test('matches every FontWeight used in the codebase', () {
      expect(AppFontWeight.regular, FontWeight.w400);
      expect(AppFontWeight.medium, FontWeight.w500);
      expect(AppFontWeight.semibold, FontWeight.w600);
      expect(AppFontWeight.bold, FontWeight.w700);
      expect(AppFontWeight.extrabold, FontWeight.w800);
    });
  });

  group('AppTextStyles', () {
    test('presets compose the expected size and weight', () {
      expect(AppTextStyles.heading1.fontSize, AppFontSize.display);
      expect(AppTextStyles.heading1.fontWeight, AppFontWeight.bold);
      expect(AppTextStyles.sectionTitle.fontSize, AppFontSize.xl5);
      expect(AppTextStyles.sectionTitle.fontWeight, AppFontWeight.bold);
      expect(AppTextStyles.cardTitle.fontSize, AppFontSize.xl2);
      expect(AppTextStyles.cardTitle.fontWeight, AppFontWeight.bold);
      expect(AppTextStyles.subtitle.fontSize, AppFontSize.lg);
      expect(AppTextStyles.subtitle.fontWeight, AppFontWeight.semibold);
      expect(AppTextStyles.body.fontSize, AppFontSize.md);
      expect(AppTextStyles.body.fontWeight, AppFontWeight.regular);
      expect(AppTextStyles.bodyStrong.fontSize, AppFontSize.md);
      expect(AppTextStyles.bodyStrong.fontWeight, AppFontWeight.semibold);
      expect(AppTextStyles.caption.fontSize, AppFontSize.base);
      expect(AppTextStyles.caption.fontWeight, AppFontWeight.medium);
      expect(AppTextStyles.label.fontSize, AppFontSize.sm);
      expect(AppTextStyles.label.fontWeight, AppFontWeight.semibold);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/theme/app_text_styles_test.dart`
Expected: FAIL — `AppFontSize` etc. are undefined.

- [ ] **Step 3: Create `app_text_styles.dart` and update the barrel**

Create `frontend/lib/theme/app_text_styles.dart`:

```dart
import 'package:flutter/material.dart';

/// Font size tokens — one per distinct `fontSize:` literal found across
/// the app today.
class AppFontSize {
  AppFontSize._();

  static const double xxs = 9;
  static const double xs = 10;
  static const double sm = 11;
  static const double base = 12;
  static const double md = 13;
  static const double lg = 14;
  static const double xl = 15;
  static const double xl2 = 16;
  static const double xl3 = 18;
  static const double xl4 = 20;
  static const double xl5 = 22;
  static const double display = 28;
  static const double display2 = 30;
  static const double display3 = 32;
  static const double hero = 52;
}

/// Font weight tokens — one per distinct `FontWeight.wN` used across the app.
class AppFontWeight {
  AppFontWeight._();

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
  static const FontWeight extrabold = FontWeight.w800;
}

/// Composed text style presets for the most common size+weight repeats.
/// Opportunistic — screens are not required to adopt these, they can keep
/// using [AppFontSize]/[AppFontWeight] directly for exact per-call control.
class AppTextStyles {
  AppTextStyles._();

  static const TextStyle heading1 =
      TextStyle(fontSize: AppFontSize.display, fontWeight: AppFontWeight.bold);
  static const TextStyle sectionTitle =
      TextStyle(fontSize: AppFontSize.xl5, fontWeight: AppFontWeight.bold);
  static const TextStyle cardTitle =
      TextStyle(fontSize: AppFontSize.xl2, fontWeight: AppFontWeight.bold);
  static const TextStyle subtitle =
      TextStyle(fontSize: AppFontSize.lg, fontWeight: AppFontWeight.semibold);
  static const TextStyle body =
      TextStyle(fontSize: AppFontSize.md, fontWeight: AppFontWeight.regular);
  static const TextStyle bodyStrong =
      TextStyle(fontSize: AppFontSize.md, fontWeight: AppFontWeight.semibold);
  static const TextStyle caption =
      TextStyle(fontSize: AppFontSize.base, fontWeight: AppFontWeight.medium);
  static const TextStyle label =
      TextStyle(fontSize: AppFontSize.sm, fontWeight: AppFontWeight.semibold);
}
```

Update `frontend/lib/theme/theme.dart`:

```dart
export 'app_colors.dart';
export 'app_text_styles.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/theme/app_text_styles_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/theme/app_text_styles.dart frontend/lib/theme/theme.dart frontend/test/theme/app_text_styles_test.dart
git commit -m "feat(theme): add AppFontSize, AppFontWeight, AppTextStyles tokens"
```

---

### Task 3: `AppRadius` token file

**Files:**
- Create: `frontend/lib/theme/app_radius.dart`
- Modify: `frontend/lib/theme/theme.dart`
- Test: `frontend/test/theme/app_radius_test.dart`

**Interfaces:**
- Consumes: none.
- Produces: `AppRadius` class with 15 `static final BorderRadius` fields: `r1, r2, r3, r4, r6, r7, r8, r10, r11, r12, r14, r16, r20, r24, pill`.

- [ ] **Step 1: Write the failing test**

Create `frontend/test/theme/app_radius_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitroo_frontend/theme/theme.dart';

void main() {
  group('AppRadius', () {
    test('matches every distinct BorderRadius.circular(N) found in the codebase', () {
      expect(AppRadius.r1, BorderRadius.circular(1));
      expect(AppRadius.r2, BorderRadius.circular(2));
      expect(AppRadius.r3, BorderRadius.circular(3));
      expect(AppRadius.r4, BorderRadius.circular(4));
      expect(AppRadius.r6, BorderRadius.circular(6));
      expect(AppRadius.r7, BorderRadius.circular(7));
      expect(AppRadius.r8, BorderRadius.circular(8));
      expect(AppRadius.r10, BorderRadius.circular(10));
      expect(AppRadius.r11, BorderRadius.circular(11));
      expect(AppRadius.r12, BorderRadius.circular(12));
      expect(AppRadius.r14, BorderRadius.circular(14));
      expect(AppRadius.r16, BorderRadius.circular(16));
      expect(AppRadius.r20, BorderRadius.circular(20));
      expect(AppRadius.r24, BorderRadius.circular(24));
      expect(AppRadius.pill, BorderRadius.circular(999));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/theme/app_radius_test.dart`
Expected: FAIL — `AppRadius` is undefined.

- [ ] **Step 3: Create `app_radius.dart` and update the barrel**

Create `frontend/lib/theme/app_radius.dart`:

```dart
import 'package:flutter/material.dart';

/// Border radius tokens — one per distinct `BorderRadius.circular(N)` value
/// found across the app today. Not `const` because `BorderRadius.circular`
/// is a regular factory, not a const constructor (matches how it was
/// already used at every call site before this migration).
class AppRadius {
  AppRadius._();

  static final BorderRadius r1 = BorderRadius.circular(1);
  static final BorderRadius r2 = BorderRadius.circular(2);
  static final BorderRadius r3 = BorderRadius.circular(3);
  static final BorderRadius r4 = BorderRadius.circular(4);
  static final BorderRadius r6 = BorderRadius.circular(6);
  static final BorderRadius r7 = BorderRadius.circular(7);
  static final BorderRadius r8 = BorderRadius.circular(8);
  static final BorderRadius r10 = BorderRadius.circular(10);
  static final BorderRadius r11 = BorderRadius.circular(11);
  static final BorderRadius r12 = BorderRadius.circular(12);
  static final BorderRadius r14 = BorderRadius.circular(14);
  static final BorderRadius r16 = BorderRadius.circular(16);
  static final BorderRadius r20 = BorderRadius.circular(20);
  static final BorderRadius r24 = BorderRadius.circular(24);
  static final BorderRadius pill = BorderRadius.circular(999);
}
```

Update `frontend/lib/theme/theme.dart`:

```dart
export 'app_colors.dart';
export 'app_text_styles.dart';
export 'app_radius.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/theme/app_radius_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/theme/app_radius.dart frontend/lib/theme/theme.dart frontend/test/theme/app_radius_test.dart
git commit -m "feat(theme): add AppRadius design tokens"
```

---

### Task 4: `AppSpacing` token file + finalize barrel

**Files:**
- Create: `frontend/lib/theme/app_spacing.dart`
- Modify: `frontend/lib/theme/theme.dart`
- Test: `frontend/test/theme/app_spacing_test.dart`

**Interfaces:**
- Consumes: none.
- Produces: `AppSpacing` class with 8 `static const double` fields: `xs, sm, md, lg, xl, xl2, xl3, xl4` (values 4/8/12/16/20/24/32/40). Not consumed by the migration script (spacing is not mechanically migrated — see design spec Non-goals); available for new code.

- [ ] **Step 1: Write the failing test**

Create `frontend/test/theme/app_spacing_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mitroo_frontend/theme/theme.dart';

void main() {
  group('AppSpacing', () {
    test('exposes the standard 4/8/12/16/20/24/32/40 scale', () {
      expect(AppSpacing.xs, 4);
      expect(AppSpacing.sm, 8);
      expect(AppSpacing.md, 12);
      expect(AppSpacing.lg, 16);
      expect(AppSpacing.xl, 20);
      expect(AppSpacing.xl2, 24);
      expect(AppSpacing.xl3, 32);
      expect(AppSpacing.xl4, 40);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/theme/app_spacing_test.dart`
Expected: FAIL — `AppSpacing` is undefined.

- [ ] **Step 3: Create `app_spacing.dart` and finalize the barrel**

Create `frontend/lib/theme/app_spacing.dart`:

```dart
/// Spacing scale for new code. Not used to mechanically rewrite existing
/// EdgeInsets literals during the style-token migration — see design spec.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xl2 = 24;
  static const double xl3 = 32;
  static const double xl4 = 40;
}
```

Update `frontend/lib/theme/theme.dart` (final form):

```dart
export 'app_colors.dart';
export 'app_text_styles.dart';
export 'app_radius.dart';
export 'app_spacing.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/theme/app_spacing_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full theme test suite**

Run: `flutter test test/theme/`
Expected: All tests PASS (4 files).

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/theme/app_spacing.dart frontend/lib/theme/theme.dart frontend/test/theme/app_spacing_test.dart
git commit -m "feat(theme): add AppSpacing tokens, finalize theme.dart barrel"
```

---

### Task 5: Rewire `main.dart` to use the tokens

**Files:**
- Modify: `frontend/lib/main.dart`

**Interfaces:**
- Consumes: `AppColors.brandPrimary`, `AppColors.brandAccent`, `AppColors.ink`, `AppColors.gray500`, `AppColors.gray200`, `AppColors.gray900` *(check: `main.dart` currently uses `0xFFE0E0E0` for input borders — that maps to `AppColors.borderSubtle`, not `gray200`; verify against the file before editing)*.

This task is a manual edit (not scripted) because it also removes the now-redundant private `_primaryRed`/`_accentRed` constants and renames their call sites — a structural change, not a pure value swap.

- [ ] **Step 1: Read the current file**

Read `frontend/lib/main.dart` in full (it's ~205 lines) to get exact line numbers, since line numbers shift as edits are made.

- [ ] **Step 2: Add the theme import**

Add near the top with the other local imports:

```dart
import 'theme/theme.dart';
```

- [ ] **Step 3: Remove the private brand color constants**

Delete these two lines from `_MitrooAppState`:

```dart
  static const _primaryRed = Color(0xFFC62828);
  static const _accentRed = Color(0xFFE53935);
```

- [ ] **Step 4: Replace every reference to `_primaryRed` and `_accentRed`**

Replace all occurrences of `_primaryRed` with `AppColors.brandPrimary`, and all occurrences of `_accentRed` with `AppColors.brandAccent`, in the `ThemeData(...)` block (`seedColor`, `primary`, `secondary`, `iconTheme` color, `indicatorColor`, the selected-state `labelTextStyle`/`iconTheme` branches, `focusedBorder` side color, `filledButtonTheme` `backgroundColor`, `floatingActionButtonTheme` `backgroundColor`).

- [ ] **Step 5: Replace the remaining inline hex literals**

Replace each of these exact literals in the `ThemeData(...)` block with its token:

| Literal | Replace with |
|---|---|
| `const Color(0xFF1A1C1E)` (in `colorScheme.onSurface`) | `AppColors.ink` |
| `const Color(0xFFE5E7EB)` (card border side) | `AppColors.gray200` |
| `const Color(0xFF1A1C1E)` (appBar `titleTextStyle` color) | `AppColors.ink` |
| `const Color(0xFF6B7280)` (nav bar unselected label/icon color, two occurrences) | `AppColors.gray500` |
| `const Color(0xFFE0E0E0)` (input border, `enabledBorder` — two occurrences) | `AppColors.borderSubtle` |
| `const Color(0xFFE8ECF0)` (`dividerTheme` color) | `AppColors.divider` |

- [ ] **Step 6: Run `flutter analyze` on the file**

Run (from `frontend/`): `flutter analyze lib/main.dart`
Expected: No errors.

- [ ] **Step 7: Run the widget test suite to confirm the app still boots**

Run: `flutter test`
Expected: All existing tests still PASS (no regressions from the theme rewire).

- [ ] **Step 8: Commit**

```bash
git add frontend/lib/main.dart
git commit -m "refactor(theme): wire main.dart ThemeData to AppColors tokens"
```

---

### Task 6: Build the migration codemod script (dry run only)

**Files:**
- Create: `frontend/scripts/migrate_style_tokens.js`

**Interfaces:**
- Consumes: `AppColors`/`AppFontWeight`/`AppFontSize`/`AppRadius` token names (must match Tasks 1–3 exactly — the `COLOR_MAP`/`WEIGHT_MAP`/`SIZE_MAP`/`RADIUS_MAP` values below are those token names as strings).
- Produces: a `--dry-run` report (files that would change, counts per category, any unmapped values) with no filesystem writes. Real writes happen in Task 7.

This script does pure 1:1 value substitution across `frontend/lib/` (excluding `frontend/lib/theme/` and `frontend/lib/main.dart`, which are already done). See the design spec's "Migration mechanics" section for why this is safe to run unattended.

- [ ] **Step 1: Create the script**

Create `frontend/scripts/migrate_style_tokens.js`:

```js
#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const LIB_DIR = path.join(__dirname, '..', 'lib');
const EXCLUDE_DIRS = new Set([path.join(LIB_DIR, 'theme')]);
const EXCLUDE_FILES = new Set([path.join(LIB_DIR, 'main.dart')]);
const DRY_RUN = process.argv.includes('--dry-run');

const COLOR_MAP = {
  // Brand
  C62828: 'brandPrimary', E53935: 'brandAccent', '6B0000': 'brandDark',
  // Gray
  F9FAFB: 'gray50', F3F4F6: 'gray100', E5E7EB: 'gray200', D1D5DB: 'gray300',
  '9CA3AF': 'gray400', '6B7280': 'gray500', '4B5563': 'gray600', '374151': 'gray700',
  '1F2937': 'gray800', '111827': 'gray900',
  // Neutral extras
  '1A1C1E': 'ink', E0E0E0: 'borderSubtle', E8ECF0: 'divider', EEF0F4: 'surfaceTint',
  E9EBF0: 'surfaceTint2', F8FAFC: 'slate50', F5F7FA: 'surfaceAlt',
  // Red
  FEF2F2: 'red50', FEE2E2: 'red100', FECACA: 'red200', FCA5A5: 'red300',
  F87171: 'red400', EF4444: 'red500', DC2626: 'red600', B91C1C: 'red700', '991B1B': 'red800',
  // Orange
  FFF7ED: 'orange50', FED7AA: 'orange300', EA580C: 'orange600', C2410C: 'orange700',
  '9A3412': 'orange800', D84315: 'orangeDeep',
  // Amber
  FFFBEB: 'amber50', FEF3C7: 'amber100', FDE68A: 'amber300', F59E0B: 'amber500',
  D97706: 'amber600', B45309: 'amber700', '92400E': 'amber800',
  // Green / Emerald
  F0FDF4: 'green50', BBF7D0: 'green200', D1FAE5: 'emerald100', '10B981': 'emerald500',
  '059669': 'emerald600',
  // Teal
  '0D9488': 'teal600', '0F766E': 'teal700',
  // Cyan / Sky
  ECFEFF: 'cyan50', '0891B2': 'cyan600', '0EA5E9': 'sky500',
  // Blue / Indigo
  EEF2FF: 'indigo50', DBEAFE: 'blue100', '3B82F6': 'blue500', '2563EB': 'blue600',
  '1D4ED8': 'blue700', '0D47A1': 'blueDeep', '6366F1': 'indigo500', '1E1B4B': 'indigo950',
  // Violet
  F5F3FF: 'violet50', EDE9FE: 'violet100', DDD6FE: 'violet200', '8B5CF6': 'violet500',
  '7C3AED': 'violet600', '6D28D9': 'violet700', '5B21B6': 'violet800',
};

const WEIGHT_MAP = {
  400: 'regular', 500: 'medium', 600: 'semibold', 700: 'bold', 800: 'extrabold',
};

const SIZE_MAP = {
  9: 'xxs', 10: 'xs', 11: 'sm', 12: 'base', 13: 'md', 14: 'lg', 15: 'xl',
  16: 'xl2', 18: 'xl3', 20: 'xl4', 22: 'xl5', 28: 'display', 30: 'display2',
  32: 'display3', 52: 'hero',
};

const RADIUS_MAP = {
  1: 'r1', 2: 'r2', 3: 'r3', 4: 'r4', 6: 'r6', 7: 'r7', 8: 'r8', 10: 'r10',
  11: 'r11', 12: 'r12', 14: 'r14', 16: 'r16', 20: 'r20', 24: 'r24', 999: 'pill',
};

const IMPORT_LINE = "import 'package:mitroo_frontend/theme/theme.dart';";

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (EXCLUDE_DIRS.has(full) || EXCLUDE_FILES.has(full)) continue;
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith('.dart')) out.push(full);
  }
  return out;
}

function migrateFile(filePath, stats) {
  let src = fs.readFileSync(filePath, 'utf8');
  let changed = false;

  src = src.replace(/(const\s+)?Color\(0x(FF[0-9A-Fa-f]{6})\)/g, (match, _const, hexWithFF) => {
    const hex = hexWithFF.slice(2).toUpperCase();
    const token = COLOR_MAP[hex];
    if (!token) {
      stats.unmapped.add(`${path.relative(LIB_DIR, filePath)}: 0x${hexWithFF}`);
      return match;
    }
    changed = true;
    stats.colors++;
    return `AppColors.${token}`;
  });

  src = src.replace(/FontWeight\.w(\d{3})/g, (match, digits) => {
    const token = WEIGHT_MAP[Number(digits)];
    if (!token) {
      stats.unmapped.add(`${path.relative(LIB_DIR, filePath)}: FontWeight.w${digits}`);
      return match;
    }
    changed = true;
    stats.weights++;
    return `AppFontWeight.${token}`;
  });

  src = src.replace(/fontSize:\s*(\d+)\b(?!\.\d)/g, (match, digits) => {
    const token = SIZE_MAP[Number(digits)];
    if (!token) {
      stats.unmapped.add(`${path.relative(LIB_DIR, filePath)}: fontSize: ${digits}`);
      return match;
    }
    changed = true;
    stats.sizes++;
    return `fontSize: AppFontSize.${token}`;
  });

  src = src.replace(/BorderRadius\.circular\((\d+)\)/g, (match, digits) => {
    const token = RADIUS_MAP[Number(digits)];
    if (!token) {
      stats.unmapped.add(`${path.relative(LIB_DIR, filePath)}: BorderRadius.circular(${digits})`);
      return match;
    }
    changed = true;
    stats.radii++;
    return `AppRadius.${token}`;
  });

  if (changed && !src.includes(IMPORT_LINE)) {
    const importBlock = /^(import\s+['"][^'"]+['"];\s*\n)+/m;
    const m = src.match(importBlock);
    if (m) {
      const insertAt = m.index + m[0].length;
      src = src.slice(0, insertAt) + IMPORT_LINE + '\n' + src.slice(insertAt);
    } else {
      src = IMPORT_LINE + '\n\n' + src;
    }
  }

  if (changed) {
    stats.files++;
    stats.changedFiles.push(path.relative(LIB_DIR, filePath));
    if (!DRY_RUN) fs.writeFileSync(filePath, src, 'utf8');
  }
  return changed;
}

function main() {
  const files = walk(LIB_DIR);
  const stats = { files: 0, colors: 0, weights: 0, sizes: 0, radii: 0, unmapped: new Set(), changedFiles: [] };
  for (const file of files) migrateFile(file, stats);

  console.log(`${DRY_RUN ? '[DRY RUN] ' : ''}Files scanned: ${files.length}`);
  console.log(`Files changed: ${stats.files}`);
  console.log(`Colors replaced: ${stats.colors}`);
  console.log(`Font weights replaced: ${stats.weights}`);
  console.log(`Font sizes replaced: ${stats.sizes}`);
  console.log(`Radii replaced: ${stats.radii}`);

  if (stats.unmapped.size) {
    console.log(`\nUNMAPPED (left untouched — needs a manual look):`);
    for (const u of stats.unmapped) console.log(`  ${u}`);
    process.exitCode = 1;
  }
}

main();
```

- [ ] **Step 2: Run it in dry-run mode**

Run (from `frontend/`): `node scripts/migrate_style_tokens.js --dry-run`

- [ ] **Step 3: Verify the report has zero unmapped values**

Expected output ends with just the summary counts — no `UNMAPPED` section, and exit code 0 (check with `echo $?` after the command). If anything is unmapped, it means a color/size/weight/radius literal exists in the codebase that wasn't in the design spec's mapping table — stop and add it to `COLOR_MAP`/`SIZE_MAP`/`WEIGHT_MAP`/`RADIUS_MAP` (and to `AppColors`/`AppFontSize`/`AppRadius` from Tasks 1–3) before proceeding, rather than skip it.

- [ ] **Step 4: Sanity-check the dry-run diff on one file**

Run: `node -e "require('./scripts/migrate_style_tokens.js')" --dry-run` is equivalent to Step 2; instead, temporarily run the script in write mode against a git-clean tree, inspect `git diff lib/screens/admin_panel_screen.dart`, then revert:

```bash
node scripts/migrate_style_tokens.js
git diff --stat lib/screens/admin_panel_screen.dart
git diff lib/screens/admin_panel_screen.dart | head -80
git checkout -- lib/
```

Confirm the diff only swaps `Color(0xFFxxxxxx)` → `AppColors.x`, `FontWeight.wN` → `AppFontWeight.x`, `fontSize: N` → `fontSize: AppFontSize.x`, `BorderRadius.circular(N)` → `AppRadius.rN`, and adds the one import line — nothing else changed, indentation/formatting elsewhere untouched.

- [ ] **Step 5: Commit the script**

```bash
git add frontend/scripts/migrate_style_tokens.js
git commit -m "chore(theme): add style-token migration codemod script"
```

---

### Task 7: Run the migration across the full codebase

**Files:**
- Modify: all `.dart` files under `frontend/lib/screens/`, `frontend/lib/widgets/`, `frontend/lib/helpers/` that contain any of the four patterns (script determines this automatically).

**Interfaces:**
- Consumes: `frontend/scripts/migrate_style_tokens.js` from Task 6.

- [ ] **Step 1: Confirm a clean working tree**

Run (from repo root): `git status`
Expected: only Task 6's commit is ahead; no uncommitted changes in `frontend/`.

- [ ] **Step 2: Run the script for real**

Run (from `frontend/`): `node scripts/migrate_style_tokens.js`
Expected: prints the same category counts as the Task 6 dry run, `Files changed` in the mid-30s, no `UNMAPPED` section, exit code 0.

- [ ] **Step 3: Review the change stats**

Run: `git diff --stat`
Expected: every changed file is a `.dart` file under `lib/`, each with a plausible number of changed lines (roughly matching how many `Color(0xFF...)`/`FontWeight.wN`/`fontSize: N`/`BorderRadius.circular(N)` occurrences that file had) — no file with a wildly out-of-proportion diff, which would indicate the import-insertion regex matched somewhere unexpected.

- [ ] **Step 4: Format the changed files**

Run: `dart format lib/`

- [ ] **Step 5: Commit**

```bash
git add frontend/lib
git commit -m "refactor(theme): migrate screens/widgets/helpers to shared style tokens"
```

---

### Task 8: Static verification and straggler cleanup

**Files:**
- Modify: any file `flutter analyze` flags (expected to be rare — see failure modes below).

**Interfaces:**
- Consumes: nothing new.

- [ ] **Step 1: Run the analyzer**

Run (from `frontend/`): `flutter analyze`
Expected candidates for pre-existing vs. new issues:
- **New "undefined name" errors** for `AppColors`/`AppFontWeight`/`AppFontSize`/`AppRadius` in a specific file → the import-insertion step failed for that file (e.g. the file's first lines aren't a contiguous import block). Fix: manually add `import 'package:mitroo_frontend/theme/theme.dart';` to that file's import section.
- **Any other new error/warning** → inspect the specific line with `git diff <file>` and fix by hand; do not mass-suppress.

- [ ] **Step 2: Re-run analyze until clean**

Run: `flutter analyze`
Expected: no errors/warnings beyond whatever pre-existed before this migration (compare against `git stash` + `flutter analyze` on the pre-migration tree if unsure what's pre-existing).

- [ ] **Step 3: Run the full test suite**

Run: `flutter test`
Expected: all tests PASS, including the 4 new `test/theme/*_test.dart` files and every pre-existing test in `test/screens/`.

- [ ] **Step 4: Confirm no remaining mapped literals**

Run (from `frontend/`):
```bash
grep -rE "Color\(0xFF[0-9A-Fa-f]{6}\)" lib --include=*.dart | grep -v "^lib/theme/"
```
Expected: no output (every hardcoded hex color outside `lib/theme/` has been replaced). If any lines print, check whether they're inside `lib/main.dart` (expected — handled manually in Task 5, verify it was actually replaced) or a genuine miss from the script.

- [ ] **Step 5: Commit any straggler fixes**

```bash
git add -A
git commit -m "fix(theme): resolve analyzer stragglers from style-token migration"
```
(Skip this commit if Step 1 was already clean.)

---

### Task 9: Visual spot-check and final commit

**Files:**
- None (verification only).

**Interfaces:**
- Consumes: the fully migrated app.

- [ ] **Step 1: Start the databases**

Run (from repo root): `docker compose -f docker-compose.dev.yml up -d`

- [ ] **Step 2: Start the backend**

Run (from `backend/`): `npm run dev` (leave running in background).

- [ ] **Step 3: Run the frontend in Chrome**

Run (from `frontend/`): `flutter run -d chrome`

- [ ] **Step 4: Visually compare against `main` before this branch**

Log in and check these four screens render identically to before (same colors, same text sizes/weights, same corner rounding — this is a pure refactor, so nothing should look different):
- Dashboard (`dashboard_screen.dart`) — status badges (active/completed/cancelled colors), quick-stat tiles.
- Admin panel (`admin_panel_screen.dart`) — the colored admin tiles (red/purple/green/amber/cyan).
- Items list (`items_screen.dart`) — condition/status chips.
- Department detail (`department_detail_screen.dart`) — role badges (missionAdmin/itemAdmin/volunteer) and service status chips.

If anything looks different, `git diff` that screen's file against the pre-migration version (`git log` to find the commit before Task 7) to find the mismatch — it means a token was mapped to the wrong hex value in Task 1/2/3 and needs correcting there (fix the source of truth, then re-run affected checks), not patched ad hoc in the screen.

- [ ] **Step 5: Stop the dev servers**

Stop the `flutter run` and backend processes; leave `docker compose -f docker-compose.dev.yml down` to the user if they want the databases stopped too (don't do this automatically — they may have other local work depending on them).

- [ ] **Step 6: Final commit (if Step 4 required fixes)**

```bash
git add -A
git commit -m "fix(theme): correct token value mismatch found in visual verification"
```
(Skip if no fixes were needed.)
