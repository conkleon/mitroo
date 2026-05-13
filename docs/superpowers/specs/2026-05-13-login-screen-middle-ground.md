# Login Screen — Middle Ground Polish

**Date:** 2026-05-13  
**Status:** Approved

## Goal

Increase visual presence of the login screen without reverting to the original split-panel design. The current centered-card is too plain; this iteration adds brand identity to the card header and lifts the background.

## What Changes

### Background

- Change `Scaffold` `backgroundColor` from `const Color(0xFFF5F7FA)` to `Colors.white`.
- The card's existing `boxShadow` provides natural lift against the white page.

### Card header (inside the card)

Three changes to the header area at the top of the card:

1. **Logo size:** `height: 40` → `height: 56`
2. **App name typography:** `tt.titleMedium` → `tt.titleLarge`, `fontWeight: FontWeight.w700`, `color: cs.primary` (unchanged)
3. **New org subtitle line** added immediately after the logo/title `Row`:
   - `SizedBox(height: 4)` between the `Row` and the new text
   - Text: `'ΕΛΛΗΝΙΚΟΣ ΕΡΥΘΡΟΣ ΣΤΑΥΡΟΣ'`
   - Style: `fontSize: 10`, `fontWeight: FontWeight.w600`, `letterSpacing: 2.5`, `color: cs.primary.withAlpha(150)`

4. **Header-to-form-subtitle spacing:** existing `SizedBox(height: 8)` (between the header block and the "Συνδεθείτε…" subtitle) → `SizedBox(height: 20)`

### Form

No changes to email field, password field, forgot-password link, submit button, or error banner.

## Files Affected

- `frontend/lib/screens/login_screen.dart` — targeted edits only; no structural changes
