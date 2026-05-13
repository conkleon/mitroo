# Login Screen Redesign

**Date:** 2026-05-13  
**Status:** Approved

## Goal

Redesign `login_screen.dart` so it matches the rest of the app's design language (clean Material 3, light gray backgrounds, red accent used sparingly) and remove the registration and training application flows, which are no longer needed due to Mitroo synchronization.

## What Changes

### Visual redesign

- **Remove** the split-panel layout (brand panel + form panel).
- **Replace** with a single centered white card on a `0xFFF5F7FA` background, `BorderRadius.circular(16)`, subtle box shadow, `maxWidth: 400`.
- The card has a `3px` top border in `0xFFDC2626` (the app's primary red, same as sidebar active accent).
- **Drop** Playfair Display serif font entirely. Use the app's `Theme.of(context).textTheme` throughout.
- **Drop** `_CrossGridPainter`, `_BrandPanel`, `_CompactBrandHeader`, `_CapChip` — all decorative brand panel widgets are deleted.
- Responsive: on narrow screens the card takes full width with horizontal padding (no split panel needed).

### Card contents (top to bottom)

1. Logo (`assets/logo.png`, height 40) + "R.C.D." title using `titleMedium` `fontWeight: w700` `color: cs.primary` — mirrors the shell sidebar header.
2. Subtitle: "Συνδεθείτε με τα διαπιστευτήριά σας" in `0xFF6B7280`.
3. Error banner (shown conditionally, unchanged styling).
4. Email `TextFormField`.
5. Password `TextFormField` with show/hide toggle.
6. "Ξεχάσατε τον κωδικό;" right-aligned `TextButton`.
7. Full-width `FilledButton` — "Σύνδεση".

### Flows removed

| Element | Action |
|---|---|
| `_isRegister` bool + `_toggleMode()` | Deleted |
| Register-mode form fields (`_forenameCtrl`, `_surnameCtrl`, `_enameCtrl`) | Deleted |
| "Δεν έχετε λογαριασμό; Εγγραφή" toggle button | Deleted |
| Training application `OutlinedButton.icon` | Deleted |
| "ή" divider row | Deleted |
| `AuthProvider.register()` call in `_submit()` | Deleted (login-only path remains) |

### Flows kept

- Login (`AuthProvider.login()`)
- Forgot password link → `/forgot-password`

## Files Affected

- `frontend/lib/screens/login_screen.dart` — full rewrite of the widget tree; all removed classes deleted

## Out of Scope

- `forgot_password_screen.dart`, `reset_password_screen.dart` — no changes
- Router configuration — no route changes needed (register route can stay in router but is simply unreachable from UI)
- `AuthProvider.register()` — leave in place; just not called from the UI
