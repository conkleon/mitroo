# FHIR R4 Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add bidirectional FHIR R4 support to the victim system via `GET /api/victims/:id/fhir` (export) and `POST /api/victims/fhir` (import), with API key authentication for external EHR systems.

**Architecture:** A pure-function mapper module (`backend/src/fhir/`) converts between Prisma victim objects and FHIR R4 Bundles. Two new endpoints are added to the existing victim router. A new `authenticateOrApiKey` middleware accepts either a JWT or a static `X-Api-Key` header, enabling both in-app users and external systems to use the same endpoints.

**Tech Stack:** TypeScript, Express, Prisma, Zod, Jest + ts-jest + supertest, `@types/fhir` (FHIR R4 type definitions)

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `backend/src/fhir/codes.ts` | LOINC/SNOMED constants and system URL strings |
| Create | `backend/src/fhir/victimToBundle.ts` | Export mapper: `VictimFull → fhir4.Bundle` |
| Create | `backend/src/fhir/bundleToVictim.ts` | Import mapper: `fhir4.Bundle → CreateVictimInput` |
| Create | `backend/src/fhir/victimToBundle.test.ts` | Unit tests for export mapper |
| Create | `backend/src/fhir/bundleToVictim.test.ts` | Unit tests for import mapper |
| Create | `backend/src/routes/victim.fhir.test.ts` | Integration tests for FHIR endpoints |
| Create | `backend/jest.config.ts` | Jest configuration |
| Modify | `backend/package.json` | Add Jest, supertest, @types/fhir dev deps + test script |
| Modify | `backend/src/middleware/auth.ts` | Add `authenticateOrApiKey` |
| Modify | `backend/src/routes/victim.routes.ts` | Add `GET /:id/fhir` and `POST /fhir` endpoints |
| Modify | `backend/.env.example` (root) | Add `FHIR_API_KEY` and `FHIR_SYSTEM_USER_ID` |

---

## Task 1: Test Infrastructure + Dependencies + Env Vars

**Files:**
- Modify: `backend/package.json`
- Create: `backend/jest.config.ts`
- Modify: `.env.example` (root of repo)
- Modify: `backend/src/middleware/auth.ts`
- Create: `backend/src/middleware/auth.fhir.test.ts`

- [ ] **Step 1: Install test dependencies and @types/fhir**

```bash
cd backend
npm install --save-dev jest @types/jest ts-jest supertest @types/supertest @types/fhir
```

Expected: packages installed, `node_modules/@types/fhir` directory exists.

- [ ] **Step 2: Create jest.config.ts**

```typescript
import type { Config } from 'jest';

const config: Config = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testMatch: ['**/*.test.ts'],
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
  },
};

export default config;
```

- [ ] **Step 3: Add test script to package.json**

In `backend/package.json`, add to the `"scripts"` section:
```json
"test": "jest",
"test:watch": "jest --watch"
```

- [ ] **Step 4: Add FHIR env vars to .env.example**

Append to the root `.env.example` file (after the `MITROO_EXTERNAL_BASE_URL` line):

```
# ── FHIR R4 Integration ───────────────────────
# API key for external EHR systems. Generate with:
# node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
FHIR_API_KEY=

# ID of the Mitroo user that owns records created via FHIR import.
# Create a system user in Prisma Studio and set its ID here.
FHIR_SYSTEM_USER_ID=
```

- [ ] **Step 5: Write the failing middleware test**

Create `backend/src/middleware/auth.fhir.test.ts`:

```typescript
import { Request, Response, NextFunction } from 'express';
import { authenticateOrApiKey } from './auth';

const makeReq = (headers: Record<string, string> = {}) =>
  ({ headers, user: undefined } as unknown as Request);

const makeRes = () => {
  const json = jest.fn();
  const status = jest.fn().mockReturnValue({ json });
  return { status, json } as unknown as Response;
};

describe('authenticateOrApiKey', () => {
  beforeEach(() => {
    process.env.FHIR_API_KEY = 'test-secret-key';
    process.env.FHIR_SYSTEM_USER_ID = '99';
    process.env.JWT_SECRET = 'jwt-secret';
  });

  afterEach(() => {
    delete process.env.FHIR_API_KEY;
    delete process.env.FHIR_SYSTEM_USER_ID;
  });

  it('sets admin user and calls next() when API key matches', () => {
    const req = makeReq({ 'x-api-key': 'test-secret-key' });
    const res = makeRes();
    const next = jest.fn() as NextFunction;

    authenticateOrApiKey(req, res, next);

    expect(next).toHaveBeenCalledTimes(1);
    expect(req.user).toEqual({ userId: 99, isAdmin: true });
  });

  it('returns 401 when API key is wrong and no JWT is present', () => {
    const req = makeReq({ 'x-api-key': 'wrong-key' });
    const res = makeRes();
    const next = jest.fn() as NextFunction;

    authenticateOrApiKey(req, res, next);

    expect(next).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(401);
  });

  it('returns 401 when neither API key nor JWT is present', () => {
    const req = makeReq({});
    const res = makeRes();
    const next = jest.fn() as NextFunction;

    authenticateOrApiKey(req, res, next);

    expect(next).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(401);
  });
});
```

- [ ] **Step 6: Run test to confirm it fails**

```bash
cd backend
npm test -- --testPathPattern=auth.fhir
```

Expected: FAIL — `authenticateOrApiKey` not found.

- [ ] **Step 7: Add authenticateOrApiKey to auth.ts**

Append the following to `backend/src/middleware/auth.ts` (after the last export):

```typescript
/**
 * Accepts either a valid X-Api-Key header (for external FHIR integrations)
 * or a valid JWT Bearer token. Falls through to JWT auth if API key is absent
 * or does not match.
 */
export function authenticateOrApiKey(req: Request, res: Response, next: NextFunction): void {
  const apiKey = req.headers['x-api-key'];
  const expectedKey = process.env.FHIR_API_KEY;

  if (expectedKey && apiKey === expectedKey) {
    req.user = {
      userId: parseInt(process.env.FHIR_SYSTEM_USER_ID ?? '0', 10),
      isAdmin: true,
    };
    next();
    return;
  }

  authenticate(req, res, next);
}
```

- [ ] **Step 8: Run test to confirm it passes**

```bash
cd backend
npm test -- --testPathPattern=auth.fhir
```

Expected: PASS — 3 tests pass.

- [ ] **Step 9: Confirm TypeScript compiles**

```bash
cd backend
npx tsc --noEmit
```

Expected: no errors.

- [ ] **Step 10: Commit**

```bash
git add backend/package.json backend/package-lock.json backend/jest.config.ts \
  backend/src/middleware/auth.ts backend/src/middleware/auth.fhir.test.ts \
  .env.example
git commit -m "feat(fhir): add test infra, @types/fhir dep, API key middleware"
```

---

## Task 2: FHIR Codes Module

**Files:**
- Create: `backend/src/fhir/codes.ts`

- [ ] **Step 1: Create codes.ts**

```typescript
export const LOINC = {
  GCS_EYE: '9267-6',
  GCS_VERBAL: '9270-0',
  GCS_MOTOR: '9268-4',
  GCS_TOTAL: '9269-2',
  SYSTOLIC_BP: '8480-6',
  DIASTOLIC_BP: '8462-4',
  BP_PANEL: '55284-4',
  HEART_RATE: '8867-4',
  RESPIRATORY_RATE: '9279-1',
  OXYGEN_SAT: '59408-5',
  TEMPERATURE: '8310-5',
  BLOOD_GLUCOSE: '15074-8',
  PAIN_SCORE: '72514-3',
} as const;

export const SNOMED = {
  AVPU: '67521003',
} as const;

export const FHIR_SYSTEM = {
  LOINC: 'http://loinc.org',
  SNOMED: 'http://snomed.info/sct',
  CONDITION_CATEGORY: 'http://terminology.hl7.org/CodeSystem/condition-category',
  CONDITION_CLINICAL: 'http://terminology.hl7.org/CodeSystem/condition-clinical',
  ACT_CODE: 'http://terminology.hl7.org/CodeSystem/v3-ActCode',
  UCUM: 'http://unitsofmeasure.org',
  MITROO_VICTIMS: 'https://mitroo.app/victims',
  MITROO_SERVICES: 'https://mitroo.app/services',
} as const;
```

- [ ] **Step 2: Commit**

```bash
git add backend/src/fhir/codes.ts
git commit -m "feat(fhir): add LOINC/SNOMED codes and system URLs"
```

---

## Task 3: victimToBundle Mapper (TDD)

**Files:**
- Create: `backend/src/fhir/victimToBundle.test.ts`
- Create: `backend/src/fhir/victimToBundle.ts`

- [ ] **Step 1: Write the failing test file**

Create `backend/src/fhir/victimToBundle.test.ts`:

```typescript
import { victimToBundle } from './victimToBundle';
import { LOINC, FHIR_SYSTEM } from './codes';

const BASE_VICTIM = {
  id: 1,
  name: 'Παπαδόπουλος Γεώργιος',
  age: 45,
  dateOfBirth: new Date('1980-03-15'),
  gender: 'male',
  address: 'Οδός Αθηνών 5',
  city: 'Αθήνα',
  postalCode: '10001',
  telephone: '+302101234567',
  emergencyContact: 'Παπαδοπούλου Μαρία',
  emergencyPhone: '+306912345678',
  chiefComplaint: 'Θωρακικό άλγος',
  allergies: 'Πενικιλίνη',
  medications: 'Ασπιρίνη 100mg',
  medicalHistory: 'Υπέρταση',
  gcsEye: 4,
  gcsVerbal: 5,
  gcsMotor: 6,
  gcsTotal: 15,
  avpu: 'A',
  latitude: 37.9838,
  longitude: 23.7275,
  locationNotes: 'Κοντά στην είσοδο',
  serviceId: 10,
  notes: 'Σταθερός',
  isFinalized: false,
  finalizedAt: null,
  finalizedById: null,
  createdById: 2,
  createdAt: new Date('2026-05-26T10:00:00Z'),
  updatedAt: new Date('2026-05-26T10:00:00Z'),
  vitalSigns: [],
  treatments: [],
};

describe('victimToBundle', () => {
  it('returns a FHIR R4 collection Bundle', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    expect(bundle.resourceType).toBe('Bundle');
    expect(bundle.type).toBe('collection');
    expect(Array.isArray(bundle.entry)).toBe(true);
  });

  it('includes a Patient with Mitroo identifier', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    const patient = bundle.entry!
      .map(e => e.resource)
      .find(r => r?.resourceType === 'Patient') as fhir4.Patient;

    expect(patient).toBeDefined();
    expect(patient.id).toBe('mitroo-1');
    expect(patient.identifier![0].system).toBe(FHIR_SYSTEM.MITROO_VICTIMS);
    expect(patient.identifier![0].value).toBe('1');
    expect(patient.name![0].text).toBe('Παπαδόπουλος Γεώργιος');
    expect(patient.gender).toBe('male');
    expect(patient.birthDate).toBe('1980-03-15');
  });

  it('maps address fields to Patient.address', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    const patient = bundle.entry!
      .map(e => e.resource)
      .find(r => r?.resourceType === 'Patient') as fhir4.Patient;

    expect(patient.address![0].line![0]).toBe('Οδός Αθηνών 5');
    expect(patient.address![0].city).toBe('Αθήνα');
    expect(patient.address![0].postalCode).toBe('10001');
  });

  it('maps emergency contact to Patient.contact', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    const patient = bundle.entry!
      .map(e => e.resource)
      .find(r => r?.resourceType === 'Patient') as fhir4.Patient;

    expect(patient.contact![0].name!.text).toBe('Παπαδοπούλου Μαρία');
    expect(patient.contact![0].telecom![0].value).toBe('+306912345678');
  });

  it('includes chief complaint as encounter-diagnosis Condition', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    const conditions = bundle.entry!
      .map(e => e.resource)
      .filter((r): r is fhir4.Condition => r?.resourceType === 'Condition');

    const cc = conditions.find(
      c => c.category![0].coding![0].code === 'encounter-diagnosis'
    );
    expect(cc).toBeDefined();
    expect(cc!.code!.text).toBe('Θωρακικό άλγος');
  });

  it('includes medical history as resolved problem-list-item Condition', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    const conditions = bundle.entry!
      .map(e => e.resource)
      .filter((r): r is fhir4.Condition => r?.resourceType === 'Condition');

    const history = conditions.find(
      c => c.clinicalStatus?.coding![0].code === 'resolved'
    );
    expect(history).toBeDefined();
    expect(history!.code!.text).toBe('Υπέρταση');
  });

  it('includes allergies as problem-list-item Condition without resolved status', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    const conditions = bundle.entry!
      .map(e => e.resource)
      .filter((r): r is fhir4.Condition => r?.resourceType === 'Condition');

    const allergy = conditions.find(
      c =>
        c.category![0].coding![0].code === 'problem-list-item' &&
        c.clinicalStatus?.coding![0].code !== 'resolved'
    );
    expect(allergy).toBeDefined();
    expect(allergy!.code!.text).toBe('Πενικιλίνη');
  });

  it('maps GCS scores to Observations with correct LOINC codes', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    const obs = bundle.entry!
      .map(e => e.resource)
      .filter((r): r is fhir4.Observation => r?.resourceType === 'Observation');

    const find = (code: string) => obs.find(o => o.code.coding![0].code === code);

    expect(find(LOINC.GCS_EYE)!.valueInteger).toBe(4);
    expect(find(LOINC.GCS_VERBAL)!.valueInteger).toBe(5);
    expect(find(LOINC.GCS_MOTOR)!.valueInteger).toBe(6);
    expect(find(LOINC.GCS_TOTAL)!.valueInteger).toBe(15);
  });

  it('maps AVPU to an Observation with SNOMED system', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    const obs = bundle.entry!
      .map(e => e.resource)
      .filter((r): r is fhir4.Observation => r?.resourceType === 'Observation');

    const avpuObs = obs.find(o => o.code.coding![0].system === FHIR_SYSTEM.SNOMED);
    expect(avpuObs).toBeDefined();
    expect(avpuObs!.valueCodeableConcept!.text).toBe('A');
  });

  it('maps medications to MedicationStatement', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    const med = bundle.entry!
      .map(e => e.resource)
      .find(r => r?.resourceType === 'MedicationStatement') as fhir4.MedicationStatement;

    expect(med).toBeDefined();
    expect((med as any).medicationCodeableConcept.text).toBe('Ασπιρίνη 100mg');
  });

  it('includes Encounter with serviceId identifier and in-progress status', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    const encounter = bundle.entry!
      .map(e => e.resource)
      .find(r => r?.resourceType === 'Encounter') as fhir4.Encounter;

    expect(encounter).toBeDefined();
    expect(encounter.status).toBe('in-progress');
    expect(encounter.identifier![0].system).toBe(FHIR_SYSTEM.MITROO_SERVICES);
    expect(encounter.identifier![0].value).toBe('10');
    expect(encounter.period!.start).toBe('2026-05-26T10:00:00.000Z');
  });

  it('marks Encounter as finished when isFinalized is true', () => {
    const victim = {
      ...BASE_VICTIM,
      isFinalized: true,
      finalizedAt: new Date('2026-05-26T12:00:00Z'),
    };
    const bundle = victimToBundle(victim as any);
    const encounter = bundle.entry!
      .map(e => e.resource)
      .find(r => r?.resourceType === 'Encounter') as fhir4.Encounter;

    expect(encounter.status).toBe('finished');
    expect(encounter.period!.end).toBe('2026-05-26T12:00:00.000Z');
  });

  it('emits BP panel Observation from vitalSigns', () => {
    const victim = {
      ...BASE_VICTIM,
      vitalSigns: [{
        id: 1,
        victimId: 1,
        systolicBP: 120,
        diastolicBP: 80,
        heartRate: 72,
        respiratoryRate: null,
        oxygenSat: null,
        temperature: null,
        bloodGlucose: null,
        painScore: null,
        measuredAt: new Date('2026-05-26T10:30:00Z'),
        notes: null,
        measuredBy: null,
      }],
    };
    const bundle = victimToBundle(victim as any);
    const obs = bundle.entry!
      .map(e => e.resource)
      .filter((r): r is fhir4.Observation => r?.resourceType === 'Observation');

    const bp = obs.find(o => o.code.coding![0].code === LOINC.BP_PANEL);
    expect(bp).toBeDefined();
    expect(bp!.component![0].valueQuantity!.value).toBe(120);
    expect(bp!.component![1].valueQuantity!.value).toBe(80);

    const hr = obs.find(o => o.code.coding![0].code === LOINC.HEART_RATE);
    expect(hr!.valueInteger).toBe(72);
  });

  it('omits entries for null optional fields', () => {
    const victim = {
      ...BASE_VICTIM,
      chiefComplaint: null,
      allergies: null,
      medications: null,
      medicalHistory: null,
      gcsEye: null,
      gcsVerbal: null,
      gcsMotor: null,
      gcsTotal: null,
      avpu: null,
    };
    const bundle = victimToBundle(victim as any);
    const types = bundle.entry!.map(e => e.resource?.resourceType);

    expect(types).not.toContain('Condition');
    expect(types).not.toContain('MedicationStatement');
    // Observations only from vitalSigns (none here), GCS and AVPU all null
    const obsEntries = bundle.entry!.filter(e => e.resource?.resourceType === 'Observation');
    expect(obsEntries).toHaveLength(0);
  });
});
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
cd backend
npm test -- --testPathPattern=victimToBundle
```

Expected: FAIL — Cannot find module `'./victimToBundle'`.

- [ ] **Step 3: Implement victimToBundle.ts**

Create `backend/src/fhir/victimToBundle.ts`:

```typescript
import { Prisma } from '@prisma/client';
import { LOINC, SNOMED, FHIR_SYSTEM } from './codes';

type VictimFull = Prisma.VictimGetPayload<{
  include: { vitalSigns: true; treatments: true };
}>;

export function victimToBundle(victim: VictimFull): fhir4.Bundle {
  const patientId = `mitroo-${victim.id}`;
  const patientRef = `Patient/${patientId}`;
  const entries: fhir4.BundleEntry[] = [];

  entries.push({ resource: buildPatient(victim, patientId) });

  if (victim.chiefComplaint) {
    entries.push({ resource: buildCondition(victim.chiefComplaint, 'encounter-diagnosis', patientRef) });
  }
  if (victim.medicalHistory) {
    entries.push({ resource: buildCondition(victim.medicalHistory, 'problem-list-item', patientRef, 'resolved') });
  }
  if (victim.allergies) {
    entries.push({ resource: buildCondition(victim.allergies, 'problem-list-item', patientRef) });
  }

  if (victim.gcsEye != null) entries.push({ resource: buildIntObs(LOINC.GCS_EYE, victim.gcsEye, patientRef) });
  if (victim.gcsVerbal != null) entries.push({ resource: buildIntObs(LOINC.GCS_VERBAL, victim.gcsVerbal, patientRef) });
  if (victim.gcsMotor != null) entries.push({ resource: buildIntObs(LOINC.GCS_MOTOR, victim.gcsMotor, patientRef) });
  if (victim.gcsTotal != null) entries.push({ resource: buildIntObs(LOINC.GCS_TOTAL, victim.gcsTotal, patientRef) });

  if (victim.avpu) {
    entries.push({
      resource: {
        resourceType: 'Observation',
        status: 'final',
        code: { coding: [{ system: FHIR_SYSTEM.SNOMED, code: SNOMED.AVPU }], text: 'AVPU' },
        subject: { reference: patientRef },
        valueCodeableConcept: { text: victim.avpu },
      } as fhir4.Observation,
    });
  }

  for (const vs of victim.vitalSigns) {
    const dt = vs.measuredAt.toISOString();
    if (vs.systolicBP != null && vs.diastolicBP != null) {
      entries.push({ resource: buildBpObs(vs.systolicBP, vs.diastolicBP, patientRef, dt) });
    }
    if (vs.heartRate != null) entries.push({ resource: buildIntObs(LOINC.HEART_RATE, vs.heartRate, patientRef, dt) });
    if (vs.respiratoryRate != null) entries.push({ resource: buildIntObs(LOINC.RESPIRATORY_RATE, vs.respiratoryRate, patientRef, dt) });
    if (vs.oxygenSat != null) entries.push({ resource: buildIntObs(LOINC.OXYGEN_SAT, vs.oxygenSat, patientRef, dt) });
    if (vs.temperature != null) entries.push({ resource: buildDecimalObs(LOINC.TEMPERATURE, vs.temperature, patientRef, dt) });
    if (vs.bloodGlucose != null) entries.push({ resource: buildDecimalObs(LOINC.BLOOD_GLUCOSE, vs.bloodGlucose, patientRef, dt) });
    if (vs.painScore != null) entries.push({ resource: buildIntObs(LOINC.PAIN_SCORE, vs.painScore, patientRef, dt) });
  }

  if (victim.medications) {
    entries.push({
      resource: {
        resourceType: 'MedicationStatement',
        status: 'active',
        subject: { reference: patientRef },
        medicationCodeableConcept: { text: victim.medications },
      } as fhir4.MedicationStatement,
    });
  }

  entries.push({ resource: buildEncounter(victim, patientRef) });

  return { resourceType: 'Bundle', type: 'collection', entry: entries };
}

function buildPatient(victim: VictimFull, patientId: string): fhir4.Patient {
  const patient: fhir4.Patient = {
    resourceType: 'Patient',
    id: patientId,
    identifier: [{ system: FHIR_SYSTEM.MITROO_VICTIMS, value: String(victim.id) }],
    name: [{ text: victim.name }],
  };

  if (victim.dateOfBirth) {
    patient.birthDate = victim.dateOfBirth.toISOString().split('T')[0];
  }
  if (victim.gender) {
    patient.gender = victim.gender as fhir4.Patient['gender'];
  }

  const addr: fhir4.Address = {};
  if (victim.address) addr.line = [victim.address];
  if (victim.city) addr.city = victim.city;
  if (victim.postalCode) addr.postalCode = victim.postalCode;
  if (Object.keys(addr).length > 0) patient.address = [addr];

  if (victim.telephone) {
    patient.telecom = [{ system: 'phone', value: victim.telephone, use: 'home' }];
  }

  if (victim.emergencyContact || victim.emergencyPhone) {
    const contact: fhir4.PatientContact = {};
    if (victim.emergencyContact) contact.name = { text: victim.emergencyContact };
    if (victim.emergencyPhone) contact.telecom = [{ system: 'phone', value: victim.emergencyPhone }];
    patient.contact = [contact];
  }

  return patient;
}

function buildCondition(
  text: string,
  category: string,
  subjectRef: string,
  clinicalStatus?: string,
): fhir4.Condition {
  const condition: fhir4.Condition = {
    resourceType: 'Condition',
    subject: { reference: subjectRef },
    code: { text },
    category: [{
      coding: [{ system: FHIR_SYSTEM.CONDITION_CATEGORY, code: category }],
    }],
  };
  if (clinicalStatus) {
    condition.clinicalStatus = {
      coding: [{ system: FHIR_SYSTEM.CONDITION_CLINICAL, code: clinicalStatus }],
    };
  }
  return condition;
}

function buildIntObs(loincCode: string, value: number, subjectRef: string, effectiveDateTime?: string): fhir4.Observation {
  const obs: fhir4.Observation = {
    resourceType: 'Observation',
    status: 'final',
    code: { coding: [{ system: FHIR_SYSTEM.LOINC, code: loincCode }] },
    subject: { reference: subjectRef },
    valueInteger: value,
  };
  if (effectiveDateTime) obs.effectiveDateTime = effectiveDateTime;
  return obs;
}

function buildDecimalObs(loincCode: string, value: number, subjectRef: string, effectiveDateTime?: string): fhir4.Observation {
  const obs: fhir4.Observation = {
    resourceType: 'Observation',
    status: 'final',
    code: { coding: [{ system: FHIR_SYSTEM.LOINC, code: loincCode }] },
    subject: { reference: subjectRef },
    valueQuantity: { value },
  };
  if (effectiveDateTime) obs.effectiveDateTime = effectiveDateTime;
  return obs;
}

function buildBpObs(systolic: number, diastolic: number, subjectRef: string, effectiveDateTime: string): fhir4.Observation {
  return {
    resourceType: 'Observation',
    status: 'final',
    code: { coding: [{ system: FHIR_SYSTEM.LOINC, code: LOINC.BP_PANEL }], text: 'Blood Pressure' },
    subject: { reference: subjectRef },
    effectiveDateTime,
    component: [
      {
        code: { coding: [{ system: FHIR_SYSTEM.LOINC, code: LOINC.SYSTOLIC_BP }] },
        valueQuantity: { value: systolic, unit: 'mmHg', system: FHIR_SYSTEM.UCUM, code: 'mm[Hg]' },
      },
      {
        code: { coding: [{ system: FHIR_SYSTEM.LOINC, code: LOINC.DIASTOLIC_BP }] },
        valueQuantity: { value: diastolic, unit: 'mmHg', system: FHIR_SYSTEM.UCUM, code: 'mm[Hg]' },
      },
    ],
  };
}

function buildEncounter(victim: VictimFull, subjectRef: string): fhir4.Encounter {
  const encounter: fhir4.Encounter = {
    resourceType: 'Encounter',
    status: victim.isFinalized ? 'finished' : 'in-progress',
    class: { system: FHIR_SYSTEM.ACT_CODE, code: 'EMER' },
    subject: { reference: subjectRef },
    period: { start: victim.createdAt.toISOString() },
  };
  if (victim.serviceId != null) {
    encounter.identifier = [{ system: FHIR_SYSTEM.MITROO_SERVICES, value: String(victim.serviceId) }];
  }
  if (victim.isFinalized && victim.finalizedAt) {
    encounter.period!.end = victim.finalizedAt.toISOString();
  }
  return encounter;
}
```

- [ ] **Step 4: Run test to confirm it passes**

```bash
cd backend
npm test -- --testPathPattern=victimToBundle
```

Expected: PASS — 11 tests pass.

- [ ] **Step 5: Commit**

```bash
git add backend/src/fhir/victimToBundle.ts backend/src/fhir/victimToBundle.test.ts
git commit -m "feat(fhir): implement victimToBundle mapper with full test coverage"
```

---

## Task 4: bundleToVictim Mapper (TDD)

**Files:**
- Create: `backend/src/fhir/bundleToVictim.test.ts`
- Create: `backend/src/fhir/bundleToVictim.ts`

- [ ] **Step 1: Write the failing test file**

Create `backend/src/fhir/bundleToVictim.test.ts`:

```typescript
import { victimToBundle } from './victimToBundle';
import { bundleToVictim, CreateVictimInput } from './bundleToVictim';
import { FHIR_SYSTEM } from './codes';

const FULL_VICTIM = {
  id: 1,
  name: 'Παπαδόπουλος Γεώργιος',
  age: 45,
  dateOfBirth: new Date('1980-03-15'),
  gender: 'male',
  address: 'Οδός Αθηνών 5',
  city: 'Αθήνα',
  postalCode: '10001',
  telephone: '+302101234567',
  emergencyContact: 'Παπαδοπούλου Μαρία',
  emergencyPhone: '+306912345678',
  chiefComplaint: 'Θωρακικό άλγος',
  allergies: 'Πενικιλίνη',
  medications: 'Ασπιρίνη 100mg',
  medicalHistory: 'Υπέρταση',
  gcsEye: 4,
  gcsVerbal: 5,
  gcsMotor: 6,
  gcsTotal: 15,
  avpu: 'A',
  latitude: 37.9838,
  longitude: 23.7275,
  locationNotes: null,
  serviceId: 10,
  notes: null,
  isFinalized: false,
  finalizedAt: null,
  finalizedById: null,
  createdById: 2,
  createdAt: new Date('2026-05-26T10:00:00Z'),
  updatedAt: new Date('2026-05-26T10:00:00Z'),
  vitalSigns: [],
  treatments: [],
};

describe('bundleToVictim', () => {
  it('round-trips demographics through export then import', () => {
    const bundle = victimToBundle(FULL_VICTIM as any);
    const result = bundleToVictim(bundle);

    expect(result.name).toBe('Παπαδόπουλος Γεώργιος');
    expect(result.dateOfBirth).toBe('1980-03-15');
    expect(result.gender).toBe('male');
    expect(result.address).toBe('Οδός Αθηνών 5');
    expect(result.city).toBe('Αθήνα');
    expect(result.postalCode).toBe('10001');
    expect(result.telephone).toBe('+302101234567');
    expect(result.emergencyContact).toBe('Παπαδοπούλου Μαρία');
    expect(result.emergencyPhone).toBe('+306912345678');
  });

  it('round-trips clinical fields through export then import', () => {
    const bundle = victimToBundle(FULL_VICTIM as any);
    const result = bundleToVictim(bundle);

    expect(result.chiefComplaint).toBe('Θωρακικό άλγος');
    expect(result.allergies).toBe('Πενικιλίνη');
    expect(result.medications).toBe('Ασπιρίνη 100mg');
    expect(result.medicalHistory).toBe('Υπέρταση');
    expect(result.gcsEye).toBe(4);
    expect(result.gcsVerbal).toBe(5);
    expect(result.gcsMotor).toBe(6);
    expect(result.gcsTotal).toBe(15);
    expect(result.avpu).toBe('A');
  });

  it('round-trips serviceId from Encounter', () => {
    const bundle = victimToBundle(FULL_VICTIM as any);
    const result = bundleToVictim(bundle);

    expect(result.serviceId).toBe(10);
  });

  it('returns null serviceId when Encounter identifier is absent', () => {
    const bundle = victimToBundle({ ...FULL_VICTIM, serviceId: null } as any);
    const result = bundleToVictim(bundle);

    expect(result.serviceId).toBeNull();
  });

  it('returns null for fields absent in the Bundle', () => {
    const minimalBundle: fhir4.Bundle = {
      resourceType: 'Bundle',
      type: 'collection',
      entry: [
        {
          resource: {
            resourceType: 'Patient',
            id: 'mitroo-99',
            name: [{ text: 'Test User' }],
          } as fhir4.Patient,
        },
        {
          resource: {
            resourceType: 'Encounter',
            status: 'in-progress',
            class: { system: FHIR_SYSTEM.ACT_CODE, code: 'EMER' },
            subject: { reference: 'Patient/mitroo-99' },
          } as fhir4.Encounter,
        },
      ],
    };
    const result = bundleToVictim(minimalBundle);

    expect(result.name).toBe('Test User');
    expect(result.chiefComplaint).toBeNull();
    expect(result.allergies).toBeNull();
    expect(result.medicalHistory).toBeNull();
    expect(result.medications).toBeNull();
    expect(result.gcsEye).toBeNull();
    expect(result.avpu).toBeNull();
    expect(result.serviceId).toBeNull();
  });

  it('ignores unknown resource types without throwing', () => {
    const bundle = victimToBundle(FULL_VICTIM as any);
    bundle.entry!.push({
      resource: { resourceType: 'DocumentReference' } as any,
    });
    expect(() => bundleToVictim(bundle)).not.toThrow();
  });

  it('throws when Bundle contains no Patient', () => {
    const bundle: fhir4.Bundle = {
      resourceType: 'Bundle',
      type: 'collection',
      entry: [],
    };
    expect(() => bundleToVictim(bundle)).toThrow('Bundle must contain a Patient resource');
  });

  it('calculates age from birthDate on import', () => {
    const bundle = victimToBundle(FULL_VICTIM as any);
    const result = bundleToVictim(bundle);

    // Born 1980-03-15, tested at 2026-05-26 → age 46
    expect(result.age).toBe(46);
  });
});
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
cd backend
npm test -- --testPathPattern=bundleToVictim
```

Expected: FAIL — Cannot find module `'./bundleToVictim'`.

- [ ] **Step 3: Implement bundleToVictim.ts**

Create `backend/src/fhir/bundleToVictim.ts`:

```typescript
import { LOINC, SNOMED, FHIR_SYSTEM } from './codes';

export interface CreateVictimInput {
  name: string;
  age?: number | null;
  dateOfBirth?: string | null;
  gender?: 'male' | 'female' | 'other' | 'unknown' | null;
  address?: string | null;
  city?: string | null;
  postalCode?: string | null;
  telephone?: string | null;
  emergencyContact?: string | null;
  emergencyPhone?: string | null;
  chiefComplaint?: string | null;
  allergies?: string | null;
  medications?: string | null;
  medicalHistory?: string | null;
  gcsEye?: number | null;
  gcsVerbal?: number | null;
  gcsMotor?: number | null;
  gcsTotal?: number | null;
  avpu?: string | null;
  serviceId?: number | null;
  notes?: string | null;
}

export function bundleToVictim(bundle: fhir4.Bundle): CreateVictimInput {
  const resources = (bundle.entry ?? []).map(e => e.resource).filter(Boolean);

  const patient = resources.find((r): r is fhir4.Patient => r!.resourceType === 'Patient');
  if (!patient) throw new Error('Bundle must contain a Patient resource');

  const conditions = resources.filter((r): r is fhir4.Condition => r!.resourceType === 'Condition');
  const observations = resources.filter((r): r is fhir4.Observation => r!.resourceType === 'Observation');
  const medStatement = resources.find((r): r is fhir4.MedicationStatement => r!.resourceType === 'MedicationStatement');
  const encounter = resources.find((r): r is fhir4.Encounter => r!.resourceType === 'Encounter');

  // Demographics
  const name = patient.name?.[0]?.text ?? '';
  const birthDate = patient.birthDate ?? null;
  let age: number | null = null;
  if (birthDate) {
    const dob = new Date(birthDate);
    age = Math.floor((Date.now() - dob.getTime()) / (365.25 * 24 * 60 * 60 * 1000));
  }
  const gender = (patient.gender ?? null) as CreateVictimInput['gender'];
  const addr = patient.address?.[0];
  const telephone = patient.telecom?.find(t => t.system === 'phone')?.value ?? null;
  const emergencyContact = patient.contact?.[0]?.name?.text ?? null;
  const emergencyPhone = patient.contact?.[0]?.telecom?.[0]?.value ?? null;

  // Conditions
  const chiefComplaintCondition = conditions.find(
    c => c.category?.[0]?.coding?.[0]?.code === 'encounter-diagnosis'
  );
  const historyCondition = conditions.find(
    c => c.clinicalStatus?.coding?.[0]?.code === 'resolved'
  );
  const allergyCondition = conditions.find(
    c =>
      c.category?.[0]?.coding?.[0]?.code === 'problem-list-item' &&
      c.clinicalStatus?.coding?.[0]?.code !== 'resolved'
  );

  // GCS Observations
  const findIntObs = (code: string): number | null =>
    observations.find(o => o.code.coding?.[0]?.code === code)?.valueInteger ?? null;

  // AVPU
  const avpuObs = observations.find(
    o => o.code.coding?.[0]?.system === FHIR_SYSTEM.SNOMED && o.code.coding?.[0]?.code === SNOMED.AVPU
  );

  // Medications
  const medications = (medStatement as any)?.medicationCodeableConcept?.text ?? null;

  // Encounter → serviceId
  let serviceId: number | null = null;
  if (encounter?.identifier?.[0]?.system === FHIR_SYSTEM.MITROO_SERVICES) {
    const parsed = parseInt(encounter.identifier[0].value ?? '', 10);
    if (!isNaN(parsed)) serviceId = parsed;
  }

  return {
    name,
    age,
    dateOfBirth: birthDate,
    gender,
    address: addr?.line?.[0] ?? null,
    city: addr?.city ?? null,
    postalCode: addr?.postalCode ?? null,
    telephone,
    emergencyContact,
    emergencyPhone,
    chiefComplaint: chiefComplaintCondition?.code?.text ?? null,
    allergies: allergyCondition?.code?.text ?? null,
    medications,
    medicalHistory: historyCondition?.code?.text ?? null,
    gcsEye: findIntObs(LOINC.GCS_EYE),
    gcsVerbal: findIntObs(LOINC.GCS_VERBAL),
    gcsMotor: findIntObs(LOINC.GCS_MOTOR),
    gcsTotal: findIntObs(LOINC.GCS_TOTAL),
    avpu: avpuObs?.valueCodeableConcept?.text ?? null,
    serviceId,
    notes: null,
  };
}
```

- [ ] **Step 4: Run test to confirm it passes**

```bash
cd backend
npm test -- --testPathPattern=bundleToVictim
```

Expected: PASS — 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add backend/src/fhir/bundleToVictim.ts backend/src/fhir/bundleToVictim.test.ts
git commit -m "feat(fhir): implement bundleToVictim mapper with round-trip tests"
```

---

## Task 5: FHIR Endpoints (TDD)

**Files:**
- Create: `backend/src/routes/victim.fhir.test.ts`
- Modify: `backend/src/routes/victim.routes.ts`

The integration tests mock Prisma and test the two new endpoints against the real Express router.

- [ ] **Step 1: Write the failing integration tests**

Create `backend/src/routes/victim.fhir.test.ts`:

```typescript
import request from 'supertest';
import express from 'express';
import victimRouter from './victim.routes';

// Mock Prisma before importing routes
jest.mock('../lib/prisma', () => ({
  default: {
    victim: {
      findUnique: jest.fn(),
      findMany: jest.fn(),
      count: jest.fn(),
      create: jest.fn(),
    },
    service: { findUnique: jest.fn() },
    userDepartment: { count: jest.fn() },
    userService: { findUnique: jest.fn() },
  },
}));

import prisma from '../lib/prisma';
const mockPrisma = prisma as jest.Mocked<typeof prisma>;

const VICTIM_DB = {
  id: 1,
  name: 'Test Patient',
  age: 30,
  dateOfBirth: new Date('1995-06-15'),
  gender: 'female',
  address: null,
  city: null,
  postalCode: null,
  telephone: null,
  emergencyContact: null,
  emergencyPhone: null,
  chiefComplaint: 'Headache',
  allergies: null,
  medications: null,
  medicalHistory: null,
  gcsEye: 4,
  gcsVerbal: 5,
  gcsMotor: 6,
  gcsTotal: 15,
  avpu: 'A',
  latitude: null,
  longitude: null,
  locationNotes: null,
  serviceId: null,
  notes: null,
  isFinalized: false,
  finalizedAt: null,
  finalizedById: null,
  createdById: 1,
  createdAt: new Date('2026-05-26T09:00:00Z'),
  updatedAt: new Date('2026-05-26T09:00:00Z'),
  vitalSigns: [],
  treatments: [],
};

function buildApp() {
  const app = express();
  app.use(express.json());
  app.use('/victims', victimRouter);
  return app;
}

const VALID_API_KEY = 'integration-test-key';
const SYSTEM_USER_ID = '1';

beforeAll(() => {
  process.env.FHIR_API_KEY = VALID_API_KEY;
  process.env.FHIR_SYSTEM_USER_ID = SYSTEM_USER_ID;
  process.env.JWT_SECRET = 'test-jwt-secret';
});

afterAll(() => {
  delete process.env.FHIR_API_KEY;
  delete process.env.FHIR_SYSTEM_USER_ID;
});

beforeEach(() => {
  jest.clearAllMocks();
});

describe('GET /victims/:id/fhir', () => {
  it('returns 401 with no auth', async () => {
    const res = await request(buildApp()).get('/victims/1/fhir');
    expect(res.status).toBe(401);
  });

  it('returns 401 with invalid API key', async () => {
    const res = await request(buildApp())
      .get('/victims/1/fhir')
      .set('x-api-key', 'wrong-key');
    expect(res.status).toBe(401);
  });

  it('returns 404 when victim does not exist', async () => {
    (mockPrisma.victim.findUnique as jest.Mock).mockResolvedValue(null);
    const res = await request(buildApp())
      .get('/victims/999/fhir')
      .set('x-api-key', VALID_API_KEY);
    expect(res.status).toBe(404);
  });

  it('returns FHIR Bundle with correct Content-Type for valid victim', async () => {
    (mockPrisma.victim.findUnique as jest.Mock).mockResolvedValue(VICTIM_DB);
    const res = await request(buildApp())
      .get('/victims/1/fhir')
      .set('x-api-key', VALID_API_KEY);

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch('application/fhir+json');
    expect(res.body.resourceType).toBe('Bundle');
    expect(res.body.type).toBe('collection');

    const patient = res.body.entry.find((e: any) => e.resource?.resourceType === 'Patient');
    expect(patient.resource.name[0].text).toBe('Test Patient');
  });
});

describe('POST /victims/fhir', () => {
  const MINIMAL_BUNDLE: fhir4.Bundle = {
    resourceType: 'Bundle',
    type: 'collection',
    entry: [
      {
        resource: {
          resourceType: 'Patient',
          name: [{ text: 'Import Patient' }],
          gender: 'male',
        } as fhir4.Patient,
      },
      {
        resource: {
          resourceType: 'Encounter',
          status: 'in-progress',
          class: { system: 'http://terminology.hl7.org/CodeSystem/v3-ActCode', code: 'EMER' },
          subject: { reference: 'Patient/mitroo-0' },
        } as fhir4.Encounter,
      },
    ],
  };

  it('returns 401 with no auth', async () => {
    const res = await request(buildApp()).post('/victims/fhir').send(MINIMAL_BUNDLE);
    expect(res.status).toBe(401);
  });

  it('returns 400 when body is not a FHIR Bundle', async () => {
    const res = await request(buildApp())
      .post('/victims/fhir')
      .set('x-api-key', VALID_API_KEY)
      .send({ foo: 'bar' });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('Expected FHIR R4 Bundle');
  });

  it('returns 400 when Bundle has no Patient resource', async () => {
    const res = await request(buildApp())
      .post('/victims/fhir')
      .set('x-api-key', VALID_API_KEY)
      .send({ resourceType: 'Bundle', type: 'collection', entry: [] });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('Bundle must contain a Patient resource');
  });

  it('creates and returns victim from valid Bundle', async () => {
    const created = { ...VICTIM_DB, id: 5, name: 'Import Patient' };
    (mockPrisma.victim.create as jest.Mock).mockResolvedValue(created);

    const res = await request(buildApp())
      .post('/victims/fhir')
      .set('x-api-key', VALID_API_KEY)
      .send(MINIMAL_BUNDLE);

    expect(res.status).toBe(201);
    expect(res.body.name).toBe('Import Patient');
    expect(mockPrisma.victim.create).toHaveBeenCalledTimes(1);

    const callArg = (mockPrisma.victim.create as jest.Mock).mock.calls[0][0].data;
    expect(callArg.name).toBe('Import Patient');
    expect(callArg.createdById).toBe(parseInt(SYSTEM_USER_ID));
  });
});
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd backend
npm test -- --testPathPattern=victim.fhir
```

Expected: FAIL — routes not yet implemented. Some tests may show different errors; all should fail.

- [ ] **Step 3: Add FHIR endpoints to victim.routes.ts**

In `backend/src/routes/victim.routes.ts`, add the following imports at the top of the file (after the existing imports):

```typescript
import { authenticateOrApiKey } from "../middleware/auth";
import { victimToBundle } from "../fhir/victimToBundle";
import { bundleToVictim } from "../fhir/bundleToVictim";
```

Then add the two new routes **before** the line `export default router;` at the bottom of the file:

```typescript
// ── GET /api/victims/:id/fhir ────────────────────
router.get("/:id/fhir", authenticateOrApiKey, async (req: Request, res: Response) => {
  const victimId = parseInt(req.params.id);
  const userId = req.user!.userId;
  const isAdmin = req.user!.isAdmin;

  if (!(await canReadVictim(victimId, userId, isAdmin))) {
    res.status(404).json({ error: "Δεν βρέθηκε" });
    return;
  }

  const victim = await prisma.victim.findUnique({
    where: { id: victimId },
    include: { vitalSigns: true, treatments: true },
  });

  if (!victim) {
    res.status(404).json({ error: "Δεν βρέθηκε" });
    return;
  }

  const bundle = victimToBundle(victim);
  res.setHeader("Content-Type", "application/fhir+json");
  res.json(bundle);
});

// ── POST /api/victims/fhir ───────────────────────
router.post("/fhir", authenticateOrApiKey, async (req: Request, res: Response) => {
  const body = req.body;

  if (!body || body.resourceType !== "Bundle") {
    res.status(400).json({ error: "Expected FHIR R4 Bundle" });
    return;
  }

  let victimInput;
  try {
    victimInput = bundleToVictim(body as fhir4.Bundle);
  } catch (err: any) {
    res.status(400).json({ error: err.message ?? "Invalid Bundle" });
    return;
  }

  try {
    const data = createSchema.parse(victimInput);
    const victim = await prisma.victim.create({
      data: {
        ...data,
        dateOfBirth: data.dateOfBirth ? new Date(data.dateOfBirth) : undefined,
        createdById: req.user!.userId,
      },
    });
    res.status(201).json(victim);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(422).json({ error: "Μη έγκυρα δεδομένα", details: err.errors });
      return;
    }
    throw err;
  }
});
```

Also add the `fhir4` global type reference at the top of `victim.routes.ts` after the existing imports:

```typescript
// Allow global fhir4 namespace from @types/fhir
/// <reference types="fhir" />
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
cd backend
npm test -- --testPathPattern=victim.fhir
```

Expected: PASS — 8 tests pass.

- [ ] **Step 5: Run full test suite to confirm no regressions**

```bash
cd backend
npm test
```

Expected: all tests pass (auth.fhir + victimToBundle + bundleToVictim + victim.fhir).

- [ ] **Step 6: Confirm TypeScript compiles cleanly**

```bash
cd backend
npx tsc --noEmit
```

Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add backend/src/routes/victim.routes.ts backend/src/routes/victim.fhir.test.ts
git commit -m "feat(fhir): add GET /:id/fhir export and POST /fhir import endpoints"
```

---

## Post-Implementation Checklist

- [ ] Create a FHIR system user in the database (via Prisma Studio or `npm run prisma:studio`) and set `FHIR_SYSTEM_USER_ID` in `.env`
- [ ] Generate `FHIR_API_KEY` and add to `.env`: `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`
- [ ] Verify manually: start backend with `npm run dev`, then `curl -H "x-api-key: <key>" http://localhost:4000/api/victims/1/fhir | python -m json.tool`
