# Universal Style System — Design

## Problem

The Flutter frontend has no shared design-token file. `main.dart` builds a
`ThemeData` with two private color constants (`_primaryRed`, `_accentRed`),
but individual screens don't read from that theme — they redeclare raw hex
colors, font sizes, font weights, and border radii inline. A repo-wide scan
found:

- **~70 distinct hardcoded `Color(0xFFxxxxxx)` literals**, ~1,300
  occurrences, across 38 screens (plus widgets/helpers).
- The palette is not arbitrary — it's the **Tailwind CSS default palette**,
  reused consistently by value (e.g. `0xFFDC2626` = Tailwind `red-600`,
  `0xFF059669` = `emerald-600`) but redeclared by hand every time, with no
  single source of truth.
- 5 `FontWeight.wN` values and ~14 `fontSize:` sizes repeated hundreds of
  times.
- 15 distinct `BorderRadius.circular(N)` values repeated ~340 times.

This causes drift risk (a color tweak requires find-and-replace across 38
files) and makes it hard to reason about consistency (is this red the same
red as that one?).

## Goals

- One set of files screens import to get colors, text sizes/weights, and
  radii — no more inline hex/magic numbers for these three categories.
- Zero visual regressions: every existing value is preserved exactly, just
  given a name.
- `main.dart`'s `ThemeData` reads from the same tokens instead of its own
  private constants.
- All 38 screens (plus `widgets/`, `helpers/` where applicable) migrated to
  use the new tokens — not just the token file created in isolation.

## Non-goals

- No redesign of the actual visual language (no new colors, no color
  changes, no re-theming). This is pure extraction/centralization.
- Flutter's own built-in `Colors.white`, `Colors.black`, `Colors.transparent`
  (and the rare direct `Colors.red`/`Colors.amber`/`Colors.orange`) are
  **left as-is**. They're framework constants, not app-specific hardcoded
  debt, and remapping the bare `Colors.red`/`Colors.amber` family would
  subtly shift the actual shade shown (Material's `Colors.red` ≠ Tailwind
  `red-600`).
- Raw `EdgeInsets`/padding numeric literals are **not** touched. They're
  one-off layout tuning, not a reusable "style," and blanket-replacing them
  risks nudging spacing that was hand-tuned per screen. `AppSpacing` is
  still defined for new code to adopt going forward.
- No dark mode. The app is light-only today (`themeMode: ThemeMode.light`);
  tokens are light-mode values only.

## Architecture

New folder `frontend/lib/theme/`:

| File | Contents |
|---|---|
| `app_colors.dart` | `AppColors` class: full palette (see mapping below) + semantic aliases. |
| `app_text_styles.dart` | `AppFontSize` (double constants), `AppFontWeight` (FontWeight aliases), `AppTextStyles` (a few composed presets). |
| `app_radius.dart` | `AppRadius` class: `static final BorderRadius rN` constants matching every radius value in use. |
| `app_spacing.dart` | `AppSpacing` class: standard 4/8/12/16/20/24/32/40 scale for new code (not used in this migration's mechanical replacement). |
| `theme.dart` | Barrel: `export 'app_colors.dart'; export 'app_text_styles.dart'; export 'app_radius.dart'; export 'app_spacing.dart';` |

Every migrated file imports one line:
```dart
import 'package:mitroo_frontend/theme/theme.dart';
```

### `AppColors` — full token mapping

Named with real Tailwind shade numbers so every hex maps 1:1, no judgment
calls. Grouped by hue family; each entry is `token = hex // usage count`.

**Brand (app-specific, not Tailwind):**
```
brandPrimary = 0xFFC62828  // 20  (primary brand red, used in main.dart today)
brandAccent  = 0xFFE53935  // 1
brandDark    = 0xFF6B0000  // 4
```

**Gray:**
```
gray50  = 0xFFF9FAFB // 30    gray300 = 0xFFD1D5DB // 45
gray100 = 0xFFF3F4F6 // 40    gray400 = 0xFF9CA3AF // 100
gray200 = 0xFFE5E7EB // 68    gray500 = 0xFF6B7280 // 194
gray600 = 0xFF4B5563 // 15    gray800 = 0xFF1F2937 // 11
gray700 = 0xFF374151 // 41    gray900 = 0xFF111827 // 8
```

**Neutral extras** (near-gray custom values that don't sit on the Tailwind
scale exactly — kept as their own named tokens rather than force-fit, to
avoid any visual drift):
```
ink           = 0xFF1A1C1E // 18  (near-black text/icon, main.dart onSurface)
borderSubtle  = 0xFFE0E0E0 // 2
divider       = 0xFFE8ECF0 // 1   (main.dart dividerTheme)
surfaceTint   = 0xFFEEF0F4 // 4
surfaceTint2  = 0xFFE9EBF0 // 4
slate50       = 0xFFF8FAFC // 2
surfaceAlt    = 0xFFF5F7FA // 2
```

**Red:**
```
red50  = 0xFFFEF2F2 // 9   red400 = 0xFFF87171 // 7   red700 = 0xFFB91C1C // 18
red100 = 0xFFFEE2E2 // 12  red500 = 0xFFEF4444 // 9   red800 = 0xFF991B1B // 1
red200 = 0xFFFECACA // 4   red600 = 0xFFDC2626 // 142
red300 = 0xFFFCA5A5 // 2
```

**Orange:**
```
orange50  = 0xFFFFF7ED // 1   orange700 = 0xFFC2410C // 2
orange300 = 0xFFFED7AA // 1   orange800 = 0xFF9A3412 // 2
orange600 = 0xFFEA580C // 1   orangeDeep = 0xFFD84315 // 2 (Material deep-orange 700)
```

**Amber:**
```
amber50  = 0xFFFFFBEB // 2   amber500 = 0xFFF59E0B // 22   amber700 = 0xFFB45309 // 2
amber100 = 0xFFFEF3C7 // 11  amber600 = 0xFFD97706 // 48   amber800 = 0xFF92400E // 6
amber300 = 0xFFFDE68A // 1
```

**Green / Emerald:**
```
green50    = 0xFFF0FDF4 // 2   green200 = 0xFFBBF7D0 // 1
emerald100 = 0xFFD1FAE5 // 5
emerald500 = 0xFF10B981 // 3
emerald600 = 0xFF059669 // 68
```

**Teal / Cyan / Sky:**
```
teal600 = 0xFF0D9488 // 1     cyan50  = 0xFFECFEFF // 1
teal700 = 0xFF0F766E // 1     cyan600 = 0xFF0891B2 // 14
                               sky500  = 0xFF0EA5E9 // 1
```

**Blue / Indigo:**
```
indigo50   = 0xFFEEF2FF // 2   blue700  = 0xFF1D4ED8 // 1
blue100    = 0xFFDBEAFE // 1   blueDeep = 0xFF0D47A1 // 2 (Material blue 900)
blue500    = 0xFF3B82F6 // 9   indigo500 = 0xFF6366F1 // 8
blue600    = 0xFF2563EB // 29  indigo950 = 0xFF1E1B4B // 2
```

**Violet / Purple:**
```
violet50  = 0xFFF5F3FF // 3   violet500 = 0xFF8B5CF6 // 1   violet800 = 0xFF5B21B6 // 1
violet100 = 0xFFEDE9FE // 13  violet600 = 0xFF7C3AED // 100
violet200 = 0xFFDDD6FE // 2   violet700 = 0xFF6D28D9 // 3
```

**Semantic aliases** (convenience only — point at the tokens above, for
status-chip/role-badge code where the meaning is consistent):
```dart
static const success = emerald600;   static const successBg = emerald100;
static const danger  = red600;       static const dangerBg  = red100;
static const warning = amber600;     static const warningBg = amber100;
static const info    = cyan600;      static const infoBg    = cyan50;
static const accent  = violet600;    static const accentBg  = violet100;
static const textPrimary   = ink;
static const textSecondary = gray500;
static const textTertiary  = gray400;
static const border        = gray200;
```

### `AppFontSize` / `AppFontWeight` / `AppTextStyles`

```dart
class AppFontSize {
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

class AppFontWeight {
  static const regular = FontWeight.w400;
  static const medium = FontWeight.w500;
  static const semibold = FontWeight.w600;
  static const bold = FontWeight.w700;
  static const extrabold = FontWeight.w800;
}

class AppTextStyles {
  static const heading1 = TextStyle(fontSize: AppFontSize.display, fontWeight: AppFontWeight.bold);
  static const sectionTitle = TextStyle(fontSize: AppFontSize.xl5, fontWeight: AppFontWeight.bold);
  static const cardTitle = TextStyle(fontSize: AppFontSize.xl2, fontWeight: AppFontWeight.bold);
  static const subtitle = TextStyle(fontSize: AppFontSize.lg, fontWeight: AppFontWeight.semibold);
  static const body = TextStyle(fontSize: AppFontSize.md, fontWeight: AppFontWeight.regular);
  static const bodyStrong = TextStyle(fontSize: AppFontSize.md, fontWeight: AppFontWeight.semibold);
  static const caption = TextStyle(fontSize: AppFontSize.base, fontWeight: AppFontWeight.medium);
  static const label = TextStyle(fontSize: AppFontSize.sm, fontWeight: AppFontWeight.semibold);
}
```
These presets are opportunistic — the mechanical migration replaces raw
`fontSize:`/`FontWeight.wN` literals with `AppFontSize.x`/`AppFontWeight.x`
constants (preserving exact per-call combinations), it does not force every
inline `TextStyle` onto one of these presets. Screens can adopt presets by
hand later where it reads better.

### `AppRadius`

```dart
class AppRadius {
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
(Not `const` — `BorderRadius.circular()` is a regular factory, not a const
constructor, matching how it's already used today.)

### `AppSpacing`

```dart
class AppSpacing {
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

## `main.dart` rewiring

Replace `_primaryRed`/`_accentRed` private constants with
`AppColors.brandPrimary`/`AppColors.brandAccent`, and replace the inline
hex literals throughout the `ThemeData` (`0xFF1A1C1E`, `0xFFE5E7EB`,
`0xFF6B7280`, etc.) with the matching `AppColors` tokens. Behavior
unchanged — same values, now sourced from the shared file.

## Migration mechanics

Every replacement below is a **pure 1:1 value substitution** (same hex in,
same token out) — there is no judgment call per occurrence, so it's safe to
do as a scripted find/replace across all of `lib/` rather than by hand
per-screen:

1. `const Color(0xFFxxxxxx)` and bare `Color(0xFFxxxxxx)` → `AppColors.token`
   (the `const` keyword is dropped — referencing a static const field is
   already constant, Dart doesn't want `const` in front of a bare
   identifier expression). Chained calls like `.withAlpha(20)` are
   unaffected since `AppColors.token` is still just a `Color` value.
2. `FontWeight.wN` → `AppFontWeight.token`.
3. `fontSize: N` (integer literal) → `fontSize: AppFontSize.token`.
4. `BorderRadius.circular(N)` (literal N only, not variable args) →
   `AppRadius.rN`.
5. Add `import 'package:mitroo_frontend/theme/theme.dart';` to every file
   touched, if not already present.
6. Run `dart format` on changed files, then `flutter analyze` (or
   `dart analyze`) and fix any stragglers (e.g. a `BorderRadius.circular`
   call using a variable that happens to hold one of these values won't be
   touched — that's correct, not a straggler).

Scope of files touched: everything under `frontend/lib/` that matches these
patterns — primarily `screens/`, plus `widgets/` and `helpers/` where they
also declare colors/radii/font styles (e.g. `widgets/service_card.dart`).
`theme/` files themselves are the source of truth and excluded from the
replacement pass.

## Verification

- `flutter analyze` clean (no new errors/warnings introduced).
- Spot-check a handful of screens visually (`flutter run -d chrome`) to
  confirm no visual diff — dashboard, admin panel, items list, a status
  chip screen (department detail).
- `git diff --stat` should show ~38+ files changed, each a mechanical
  swap — no logic changes.
