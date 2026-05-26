# FHIR R4 Compatibility for Victim System

**Date:** 2026-05-26  
**Status:** Approved  
**Scope:** Backend only — bidirectional FHIR R4 integration on the victim resource

---

## Overview

Add FHIR R4 export and import to the victim system so Mitroo can exchange clinical records with hospital EHRs and other FHIR-capable systems. The integration is implemented as two new endpoints on the existing victim router, backed by a pure-function mapper module. No changes to the Flutter frontend or the internal data model are required.

---

## Architecture

A new `backend/src/fhir/` module contains three files:

| File | Purpose |
|---|---|
| `codes.ts` | LOINC/SNOMED constants (GCS codes, condition categories, gender values) |
| `victimToBundle.ts` | Pure export mapper: `victimToBundle(victim) → fhir.Bundle` |
| `bundleToVictim.ts` | Pure import mapper: `bundleToVictim(bundle) → CreateVictimInput` |

Two endpoints are added to `victim.routes.ts`. They accept **either** a valid Mitroo JWT (`authenticate` middleware) **or** a valid API key (`requireFhirApiKey` middleware), allowing both internal app users and external EHR systems to use the same endpoints:

- `GET /api/victims/:id/fhir` — fetches victim with vitals and treatments, calls `victimToBundle`, responds with `Content-Type: application/fhir+json`
- `POST /api/victims/fhir` — accepts a FHIR Bundle body, calls `bundleToVictim`, validates the result with the existing Zod `createSchema`, then creates the victim via Prisma (same code path as `POST /api/victims`)

The mapper functions are stateless and have no Prisma dependency — pure data transformations with no side effects.

---

## FHIR R4 Resource Mapping

Each victim export produces a `Bundle` of type `collection`. The `Patient` resource carries a Mitroo-namespaced identifier (`system: "https://mitroo.app/victims"`, `value: victim.id`) for cross-system correlation. All other resources reference the Patient via relative reference `Patient/mitroo-{id}`.

| FHIR Resource | Source fields | Notes |
|---|---|---|
| `Patient` | name, dateOfBirth, gender, address, city, postalCode, telephone, emergencyContact, emergencyPhone | emergencyContact → `contact[]` |
| `Condition` | chiefComplaint | category: `encounter-diagnosis` |
| `Condition` | medicalHistory | category: `problem-list-item`, clinicalStatus: `resolved` |
| `Condition` | allergies | category: `problem-list-item` |
| `Observation` | gcsEye | LOINC 9267-6 |
| `Observation` | gcsVerbal | LOINC 9270-0 |
| `Observation` | gcsMotor | LOINC 9268-4 |
| `Observation` | gcsTotal | LOINC 9269-2 |
| `Observation` | avpu | SNOMED 67521003; value as CodeableConcept |
| `Observation` | systolicBP / diastolicBP | LOINC 8480-6 / 8462-4; paired under a BP panel Observation |
| `Observation` | heartRate | LOINC 8867-4 |
| `Observation` | respiratoryRate | LOINC 9279-1 |
| `Observation` | oxygenSat | LOINC 59408-5 |
| `Observation` | temperature | LOINC 8310-5 |
| `Observation` | bloodGlucose | LOINC 15074-8 |
| `Observation` | painScore | LOINC 72514-3 |
| `MedicationStatement` | medications | free text → `medicationCodeableConcept.text` |
| `Encounter` | serviceId, isFinalized, createdAt | serviceId as identifier; isFinalized → status `finished`/`in-progress`; createdAt → period.start |

Only non-null fields are included in the exported Bundle. Null fields are omitted rather than emitted as null entries.

On **import**, `bundleToVictim` extracts resources by `resourceType`, maps known fields, and silently ignores unrecognised resource types or extensions (lenient ingest). Fields absent from the Bundle map to `null` in the returned input object. The Encounter identifier is used to look up a matching `serviceId`; if not found, `serviceId` is set to `null`.

---

## External Access & Authentication

### Network
In production, nginx proxies `/api/` to the backend, so the FHIR endpoints are reachable at:
```
https://your-domain/api/victims/:id/fhir
https://your-domain/api/victims/fhir
```
No extra infrastructure is required.

### API Key Auth for External Systems
A new `requireFhirApiKey` middleware is added to `backend/src/middleware/auth.ts`. It reads the `X-Api-Key` request header and compares it against `FHIR_API_KEY` from the environment. If the header matches, the request proceeds with a synthetic admin-level identity (full read/write access, no department scoping). If it does not match, the middleware falls through to the standard JWT `authenticate` middleware — so both auth paths work on the same endpoints.

**Environment:**
```
FHIR_API_KEY=<long random secret>   # added to .env and .env.example
```

The API key is provisioned once and shared with the external EHR system out-of-band (e.g. over a secure channel). Key rotation requires updating the env var and restarting the backend.

**Error:** Missing or invalid `X-Api-Key` when no JWT is present → 401 `{ error: "Unauthorized" }` (same as existing JWT failure).

---

## Dependency

Add `@types/fhir` as a dev dependency for TypeScript type definitions of FHIR R4 structures. No runtime FHIR library is required.

```
npm install --save-dev @types/fhir
```

---

## Error Handling

### Export (`GET /api/victims/:id/fhir`)
- Victim not found → 404 (reuses existing pattern)
- User lacks read access → 403 (reuses `canReadVictim`)
- No FHIR `OperationOutcome` format — standard JSON error response consistent with rest of API

### Import (`POST /api/victims/fhir`)
- Body is not a valid FHIR Bundle → 400 `{ error: "Expected FHIR R4 Bundle" }`
- Bundle contains no `Patient` resource → 400 `{ error: "Bundle must contain a Patient resource" }`
- Mapped data fails Zod `createSchema` → 422 with field-level errors (same shape as existing create endpoint)
- Encounter references unknown `serviceId` → import succeeds, `serviceId` set to `null` (soft fallback)

No `OperationOutcome` responses — this is an internal EMS tool, not a public FHIR server.

---

## Testing

| Test file | Coverage |
|---|---|
| `backend/src/fhir/victimToBundle.test.ts` | Full victim with all fields; victim with all-null optionals; GCS-only victim; correct LOINC codes on Observations |
| `backend/src/fhir/bundleToVictim.test.ts` | Round-trip (export then import produces equivalent input); partial Bundle (missing Conditions/Observations); unknown resource types ignored; Encounter with unknown serviceId → null serviceId |
| `backend/src/routes/victim.fhir.test.ts` | JWT auth works; API key auth works; missing auth → 401; invalid API key → 401; 404 on missing victim; 403 on no JWT access; valid Bundle creates victim; malformed Bundle returns 400 |

---

## Out of Scope

- Flutter UI changes — new endpoints are system-to-system only
- FHIR `OperationOutcome` error format
- FHIR R5 support
- `Procedure`, `Location` resources (excluded per agreed scope)
- FHIR Subscription or webhook push
- Public FHIR capability statement (`/metadata`)
