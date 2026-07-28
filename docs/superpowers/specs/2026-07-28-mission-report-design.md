# Mission Report — Design

## Summary

A new admin-facing tool that generates a "mission report" (in this codebase, "mission" = the `Service` domain model — the Greek UI already labels it Αποστολή/Αποστολές). Admins select a single mission, multiple missions, or a date range; the system aggregates data about the selected mission(s) and produces a report with:

- Structured data sections (personnel, vehicles, items, timeline/status, victims/injuries)
- A natural-language section in the style of a Greek press release (ΔΕΛΤΙΟ ΤΥΠΟΥ), generated via an AI API call

The report is viewed in-app and exportable as PDF. Reports are **not persisted** — generated fresh each time, nothing saved server-side beyond the request/response.

## Access Control

New tile "Αναφορά Αποστολών" in `AdminPanelScreen`'s system-management grid (`frontend/lib/screens/admin_panel_screen.dart`), visible to:

- **System admins** — unrestricted, all departments.
- **Department mission admins** (`missionAdmin` role via `UserDepartment`) — scoped to their own department(s) only.

All backend endpoints require a scope check (sys-admin OR department mission-admin for at least one relevant department), not the blanket `requireAdmin` middleware alone. Every mission ID resolved for a report — whether client-supplied or server-resolved from a date range — is re-validated against the caller's allowed department scope before any data is read.

## Backend

New file: `backend/src/routes/missionReport.routes.ts`, mounted at `/api/reports`.

### `GET /api/reports/missions`

Query params: `departmentId?`, `from?`, `to?`, `search?`.

Returns a lightweight, scoped list of `Service` rows (id, name, department, startAt/endAt, lifecycleStatus) for the selection UI. Department mission admins only ever see missions in their own department(s); sys admins may filter by department or see all.

### `POST /api/reports/generate`

Body is one of:

```jsonc
{ "serviceIds": [1, 2, 3] }                          // single/multiple mode
{ "departmentId": 4, "from": "2026-01-01", "to": "2026-01-31" } // date-range mode
```

Server behavior:

1. Resolve the target `Service` ids (date-range mode: query `Service` by `startAt`/`endAt` overlap + department scope).
2. Re-validate every resolved id is within the caller's allowed scope.
3. Aggregate structured data:
   - Mission metadata: name, description, location, department, start/end dates, lifecycle status.
   - Personnel: `UserService` rows + `User` (forename/surname/eame/rank), hours worked breakdown.
   - Vehicles: `VehicleLog` rows linked via `serviceId` — usage, mileage/hours, destination.
   - Items/equipment: `ItemService` rows — item, assigned user, timestamp.
   - Victims/injuries: `Victim` rows (+ `VitalSign`, `Treatment`) linked via `serviceId` — counts, and anonymized free-text (see Privacy below).
4. Build the AI prompt (Greek) from the aggregated data, anonymizing victim PII first.
5. Call the AI provider (see AI Integration below) to generate the press-release narrative draft.
6. Return `{ structuredData, narrativeDraft, narrativeError? }`. If the AI call fails, `narrativeDraft` is `null` and `narrativeError` carries a message — the structured data is still returned so the report isn't blocked.

Nothing is written to the database in this flow.

### `POST /api/reports/pdf`

Body: `{ structuredData, narrativeText }` — the frontend's current state, including any admin edits to the narrative text. Server renders a PDF via `pdfkit` and streams it back as `application/pdf`. Stateless.

## Privacy: Victim Data

Victim records (`Victim` model) include sensitive medical free text (`chiefComplaint`, `medicalHistory`, `notes`) alongside identifying fields (`name`, `address`, `telephone`, `emergencyContact`, `emergencyPhone`, `dateOfBirth`).

Before any data reaches the AI provider:

- **Stripped entirely**: `name`, `address`, `telephone`, `emergencyContact`, `emergencyPhone`, `dateOfBirth`, `city`, `postalCode`.
- **Sent as-is**: free-text medical fields (`chiefComplaint`, `medicalHistory`, `notes`), vitals, and treatment descriptions — so the AI can summarize injury types/severity in the narrative.

This anonymization happens server-side, before prompt construction — the AI provider never receives victim names or contact details.

## AI Integration (Pluggable Provider)

New module `backend/src/lib/ai/`:

- `AIProvider` interface: `generatePressRelease(prompt: string): Promise<string>`.
- `deepseekProvider.ts` — the only implementation for this version. DeepSeek's API is OpenAI-compatible REST; implemented via plain `fetch()` against `https://api.deepseek.com/chat/completions` (model `deepseek-chat`) — no new npm dependency.
- `index.ts` — factory reading `AI_PROVIDER` env var (default `deepseek`), returns the matching provider. Throws a clear config error if the provider's API key env var is missing. Adding another provider (Anthropic, OpenAI, etc.) later is a new file implementing the same interface — no changes to callers.

New `.env.example` entries:

```
AI_PROVIDER=deepseek
DEEPSEEK_API_KEY=
```

### Prompt

Server builds a Greek-language prompt summarizing: mission name(s)/dates/department, personnel count, vehicle usage, items used, victim counts, and anonymized injury/complaint text. Asks the model for a formal ΔΕΛΤΙΟ ΤΥΠΟΥ — a press-release-style paragraph in Greek suitable for public communication.

### Failure handling

If the AI call errors (bad key, network failure, timeout, rate limit), `POST /api/reports/generate` still succeeds with `structuredData` populated and `narrativeDraft: null` + `narrativeError` set. The admin sees the structured report and can retry AI generation or write the narrative by hand — the AI call is not a hard blocker for producing a report.

## Frontend (Flutter)

- `providers/mission_report_provider.dart` (new `ChangeNotifier`), new methods on `services/api_client.dart`.
- New route `/admin/mission-report` in `router.dart`; tile added to `AdminPanelScreen`.

### Screen 1 — Selection (`mission_report_selection_screen.dart`)

Tabbed mode switcher:

- **Μία Αποστολή** — searchable single-select dropdown (`GET /api/reports/missions`).
- **Πολλές Αποστολές** — multi-select checklist, same endpoint.
- **Εύρος Ημερομηνιών** — date-from/date-to pickers, optional department filter for sys admins (auto-scoped for dept admins).

"Δημιουργία Αναφοράς" button calls `POST /api/reports/generate` and shows a loading state (AI call may take several seconds).

### Screen 2 — Report view (`mission_report_result_screen.dart`)

- Structured sections: mission overview/timeline, personnel table, vehicles/mileage, items used, victims/injuries summary.
- Editable text area pre-filled with `narrativeDraft` — or, on `narrativeError`, an inline error message with a "Δημιουργία Ξανά" retry button.
- "Εξαγωγή PDF" button sends the current structured data + edited narrative text to `POST /api/reports/pdf` and downloads/opens the resulting PDF, following the app's existing file-download handling pattern.

## Out of Scope (this version)

- Persisting generated reports / report history.
- Multiple AI providers implemented simultaneously (only DeepSeek now; interface supports adding more later).
- Editing structured data sections (only the narrative text is editable).
