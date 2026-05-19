# GDPR Consent Flow — Design Spec

**Date:** 2026-05-19  
**Status:** Approved

## Overview

On first login (and for any existing user who has never consented), show an unskippable GDPR notice dialog. The user must explicitly accept before gaining access to the app. If they decline, they are logged out and redirected to `/login`. Consent is persisted as a timestamp in the database so the dialog never appears again.

---

## Data Model

Add one nullable field to the `User` model in `backend/prisma/schema.prisma`:

```prisma
gdprAcceptedAt DateTime? @map("gdpr_accepted_at")
```

- `null` → user has not yet consented → dialog must be shown on next login
- non-null → user accepted; value is the timestamp of acceptance
- Applies to all users, new and existing

---

## Backend

### Login response (`POST /api/auth/login`)

- Add `gdprAcceptedAt: true` to `selectAuthUser` so the field is fetched
- In both the external-Mitroo path and the local-password path, include in the JSON response:
  ```json
  { "user": {...}, "token": "...", "gdprConsentRequired": true }
  ```
  where `gdprConsentRequired = (user.gdprAcceptedAt === null)`

### New endpoint: `POST /api/auth/gdpr-consent`

- Protected by `authenticate` middleware
- Sets `gdprAcceptedAt = new Date()` for the authenticated user
- Returns `{ ok: true }`
- No other side effects

---

## Frontend

### `AuthProvider` changes (`frontend/lib/providers/auth_provider.dart`)

- Add `bool _gdprConsentRequired = false`
- Add getter `bool get gdprConsentRequired => _gdprConsentRequired`
- In `login()`: on HTTP 200, if `gdprConsentRequired` is true in the response:
  - Store the JWT token (call `_api.setToken(...)`)
  - Set `_gdprConsentRequired = true`
  - Do **not** set `_user` (keeps `isAuthenticated = false`, router stays on `/login`)
  - Return `null` (no error)
- Add `Future<void> acceptGdpr()`:
  - Calls `POST /api/auth/gdpr-consent`
  - Calls `_loadCurrentUser()` to populate `_user`
  - Sets `_gdprConsentRequired = false`
  - Calls `notifyListeners()` → router redirects to `/services`
- Add `Future<void> declineGdpr()`:
  - Calls `logout()` (clears token, clears `_user`, notifies listeners)
  - Sets `_gdprConsentRequired = false`

### `LoginScreen` changes (`frontend/lib/screens/login_screen.dart`)

- In `_submit()`, after `auth.login()` returns null (success):
  - If `auth.gdprConsentRequired` → call `_showGdprDialog()` instead of `_maybeShowInstallDialog()`
  - Else → call `_maybeShowInstallDialog()` as before
- Add `_showGdprDialog()` method: shows `GdprConsentDialog` via `showDialog` with `barrierDismissible: false`
- After `acceptGdpr()` completes inside the dialog, `_maybeShowInstallDialog()` is called

### New widget: `GdprConsentDialog`

A stateful `AlertDialog` (or custom dialog) with:

- **Not dismissible**: `barrierDismissible: false`, no X/close button
- **Title**: "Πολιτική Απορρήτου"
- **Body**: Greek text by default; a small `TextButton` ("Show in English" / "Εμφάνιση στα Ελληνικά") toggles language locally within the widget
- **Actions**:
  - "Δεν αποδέχομαι" (Decline) → calls `auth.declineGdpr()`; dialog closes; router returns user to `/login`
  - "Αποδέχομαι" (Accept) → pops the dialog, then calls `_maybeShowInstallDialog()` (PWA prompt, if applicable), then awaits `auth.acceptGdpr()`. PWA prompt must be shown before `acceptGdpr()` navigates away from `LoginScreen`.

---

## GDPR Notice Text

### Greek (default)

> Η εφαρμογή Mitroo συλλέγει και επεξεργάζεται τα προσωπικά σας δεδομένα (ονοματεπώνυμο, email, τηλέφωνο, διεύθυνση, ημερομηνία γέννησης, ειδικότητες) αποκλειστικά για τη διαχείριση αποστολών και πόρων του Ελληνικού Ερυθρού Σταυρού. Τα δεδομένα αποθηκεύονται σε ασφαλείς διακομιστές και δεν κοινοποιούνται σε τρίτους εκτός Ε.Ε.Σ. Έχετε δικαίωμα πρόσβασης, διόρθωσης και διαγραφής των δεδομένων σας επικοινωνώντας με τον διαχειριστή. Με την αποδοχή, συναινείτε στην επεξεργασία των δεδομένων σας σύμφωνα με τον ΓΚΠΔ (Κανονισμός ΕΕ 2016/679).

### English (toggle)

> The Mitroo application collects and processes your personal data (name, email, phone, address, date of birth, specializations) solely for mission and resource management within the Hellenic Red Cross. Data is stored on secure servers and is not shared with third parties outside H.R.C. You have the right to access, correct, and delete your data by contacting the administrator. By accepting, you consent to the processing of your data in accordance with the GDPR (EU Regulation 2016/679).

---

## Migration

A Prisma migration adds the nullable `gdpr_accepted_at` column to the `users` table. Existing rows default to `NULL`, so all existing users will be prompted on their next login.

---

## Out of Scope

- Admin UI to view consent records
- Consent versioning / re-consent on policy changes
- Email confirmation of consent
