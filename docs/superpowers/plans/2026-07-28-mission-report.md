# Mission Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an admin-only "Mission Report" feature — select one/many missions or a date range, aggregate mission data (personnel, vehicles, items, victims), generate a Greek ΔΕΛΤΙΟ ΤΥΠΟΥ narrative via a pluggable AI provider (DeepSeek), and export the whole thing as a PDF. Nothing is persisted server-side.

**Architecture:** New backend route module (`/api/reports`) built from small, independently-testable pure functions (anonymization, prompt-building, PDF rendering) wired together by thin Express handlers, plus a pluggable `AIProvider` interface with a DeepSeek implementation. New Flutter provider + two screens (selection, result) reusing existing app patterns (`ChangeNotifier` providers, `ApiClient`, `downloadFile`).

**Tech Stack:** Backend: Express, Prisma, Zod, `pdfkit` (new dependency), native `fetch` for the DeepSeek HTTP call (no new AI SDK dependency). Frontend: Flutter, `provider`, `go_router`, existing `http`-based `ApiClient` and `download_helper.dart`.

## Global Constraints

- Backend targets Node 22 / TypeScript `^5.7.3` (per `backend/package.json` `@types/node`/`typescript`) — use native `fetch`, no polyfill.
- Follow existing route conventions exactly: `Router()` + `router.use(authenticate)`, inline `z.object()` schemas, `try { ... } catch (err: any) { if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; } throw err; }`, plain `res.json(...)` responses (no envelope), user-facing error strings in Greek, system/validation error strings in English — mirrored from `backend/src/routes/user.routes.ts` and `backend/src/routes/service.routes.ts`.
- Access control uses the **existing** `getMissionAdminDepartmentIds(userId)` and `isMissionAdminInDepartment(userId, departmentId)` helpers from `backend/src/middleware/auth.ts` — do not write new scoping helpers from scratch.
- **Never query victim PII** (`name`, `address`, `telephone`, `emergencyContact`, `emergencyPhone`, `dateOfBirth`, `city`, `postalCode`) anywhere in this feature — the Prisma `select` for `Victim` must only ever list `id`, `chiefComplaint`, `medicalHistory`, `notes`, `isFinalized`.
- Reports are **ephemeral** — no new Prisma model, no database writes anywhere in this feature.
- Frontend: no new pubspec dependency — `http`, `provider`, `go_router`, and the existing `services/download_helper.dart` cover everything needed.
- Frontend data stays loosely typed (`Map<String, dynamic>` / `List<dynamic>`) to match every existing provider in this codebase (e.g. `DepartmentProvider`) — do not introduce Dart model classes for API payloads.

---

## File Structure

**Backend — create:**
- `backend/src/lib/ai/types.ts` — `AIProvider` interface
- `backend/src/lib/ai/deepseekProvider.ts` — DeepSeek implementation
- `backend/src/lib/ai/index.ts` — provider factory (`getAIProvider()`)
- `backend/src/lib/missionReportAnonymize.ts` — victim PII-stripping pure function
- `backend/src/lib/missionReportPrompt.ts` — Greek press-release prompt builder
- `backend/src/lib/missionReportData.ts` — types + Prisma aggregation query
- `backend/src/lib/missionReportPdf.ts` — `pdfkit`-based PDF renderer
- `backend/src/routes/missionReport.routes.ts` — the 3 endpoints

**Backend — modify:**
- `backend/package.json` (add `pdfkit` + `@types/pdfkit`)
- `.env.example` (add `AI_PROVIDER`, `DEEPSEEK_API_KEY`, `DEEPSEEK_MODEL`)
- `backend/src/app.ts` (mount new router)

**Frontend — create:**
- `frontend/lib/providers/mission_report_provider.dart`
- `frontend/lib/screens/mission_report_selection_screen.dart`
- `frontend/lib/screens/mission_report_result_screen.dart`

**Frontend — modify:**
- `frontend/lib/main.dart` (register provider)
- `frontend/lib/config/router.dart` (register 2 routes)
- `frontend/lib/screens/admin_panel_screen.dart` (add tile)

---

### Task 1: Backend dependency & environment setup

**Files:**
- Modify: `backend/package.json`
- Modify: `.env.example`

**Interfaces:**
- Produces: `pdfkit` + `@types/pdfkit` available to import in later tasks; `AI_PROVIDER`, `DEEPSEEK_API_KEY`, `DEEPSEEK_MODEL` env vars documented.

- [ ] **Step 1: Install pdfkit**

Run from `backend/`:
```bash
npm install pdfkit
npm install --save-dev @types/pdfkit
```

- [ ] **Step 2: Verify package.json updated**

Open `backend/package.json` and confirm `"pdfkit"` appears under `dependencies` and `"@types/pdfkit"` under `devDependencies` (npm will have written the resolved version ranges — do not hand-edit them).

- [ ] **Step 3: Add AI provider env vars**

Edit `.env.example` (repo root), adding this block after the `FHIR_SYSTEM_USER_ID=` line at the end of the file:

```
# ── AI Mission Report Narrative ───────────────
# Provider for the ΔΕΛΤΙΟ ΤΥΠΟΥ narrative text. Currently only "deepseek" is implemented.
AI_PROVIDER=deepseek
DEEPSEEK_API_KEY=
DEEPSEEK_MODEL=deepseek-chat
```

- [ ] **Step 4: Commit**

```bash
git add backend/package.json backend/package-lock.json .env.example
git commit -m "chore: add pdfkit dependency and AI provider env config"
```

---

### Task 2: AIProvider interface + DeepSeek implementation

**Files:**
- Create: `backend/src/lib/ai/types.ts`
- Create: `backend/src/lib/ai/deepseekProvider.ts`
- Test: `backend/src/lib/ai/deepseekProvider.test.ts`

**Interfaces:**
- Produces: `interface AIProvider { generatePressRelease(prompt: string): Promise<string>; }` (from `types.ts`); `class DeepSeekProvider implements AIProvider` with constructor `(apiKey: string, model?: string)` (from `deepseekProvider.ts`).

- [ ] **Step 1: Write `types.ts`**

```ts
export interface AIProvider {
  generatePressRelease(prompt: string): Promise<string>;
}
```

- [ ] **Step 2: Write the failing test for DeepSeekProvider**

```ts
// backend/src/lib/ai/deepseekProvider.test.ts
import { DeepSeekProvider } from "./deepseekProvider";

describe("DeepSeekProvider", () => {
  const originalFetch = global.fetch;

  afterEach(() => {
    global.fetch = originalFetch;
    jest.restoreAllMocks();
  });

  it("posts the prompt to the DeepSeek chat completions endpoint and returns the trimmed content", async () => {
    const mockFetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        choices: [{ message: { content: "  Το κείμενο του δελτίου τύπου.  " } }],
      }),
    });
    global.fetch = mockFetch as unknown as typeof fetch;

    const provider = new DeepSeekProvider("test-key", "deepseek-chat");
    const result = await provider.generatePressRelease("Γράψε ένα δελτίο τύπου.");

    expect(result).toBe("Το κείμενο του δελτίου τύπου.");
    expect(mockFetch).toHaveBeenCalledWith(
      "https://api.deepseek.com/chat/completions",
      expect.objectContaining({
        method: "POST",
        headers: expect.objectContaining({
          "Content-Type": "application/json",
          Authorization: "Bearer test-key",
        }),
      }),
    );
    const body = JSON.parse((mockFetch.mock.calls[0][1] as RequestInit).body as string);
    expect(body.model).toBe("deepseek-chat");
    expect(body.messages).toEqual([{ role: "user", content: "Γράψε ένα δελτίο τύπου." }]);
  });

  it("throws when the API responds with a non-ok status", async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      status: 401,
      text: async () => "Unauthorized",
    }) as unknown as typeof fetch;

    const provider = new DeepSeekProvider("bad-key");
    await expect(provider.generatePressRelease("prompt")).rejects.toThrow(
      "DeepSeek API error (401): Unauthorized",
    );
  });

  it("throws when the response has no message content", async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ choices: [] }),
    }) as unknown as typeof fetch;

    const provider = new DeepSeekProvider("test-key");
    await expect(provider.generatePressRelease("prompt")).rejects.toThrow(
      "DeepSeek API returned no content",
    );
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd backend && npx jest src/lib/ai/deepseekProvider.test.ts`
Expected: FAIL with "Cannot find module './deepseekProvider'"

- [ ] **Step 4: Implement DeepSeekProvider**

```ts
// backend/src/lib/ai/deepseekProvider.ts
import { AIProvider } from "./types";

interface DeepSeekChatResponse {
  choices?: { message?: { content?: string } }[];
}

export class DeepSeekProvider implements AIProvider {
  constructor(
    private readonly apiKey: string,
    private readonly model: string = "deepseek-chat",
  ) {}

  async generatePressRelease(prompt: string): Promise<string> {
    const response = await fetch("https://api.deepseek.com/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.apiKey}`,
      },
      body: JSON.stringify({
        model: this.model,
        messages: [{ role: "user", content: prompt }],
        temperature: 0.7,
      }),
    });

    if (!response.ok) {
      const text = await response.text().catch(() => "");
      throw new Error(`DeepSeek API error (${response.status}): ${text}`);
    }

    const data = (await response.json()) as DeepSeekChatResponse;
    const content = data.choices?.[0]?.message?.content;
    if (!content) {
      throw new Error("DeepSeek API returned no content");
    }
    return content.trim();
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd backend && npx jest src/lib/ai/deepseekProvider.test.ts`
Expected: PASS (3 tests)

- [ ] **Step 6: Commit**

```bash
git add backend/src/lib/ai/types.ts backend/src/lib/ai/deepseekProvider.ts backend/src/lib/ai/deepseekProvider.test.ts
git commit -m "feat: add AIProvider interface and DeepSeek implementation"
```

---

### Task 3: AI provider factory

**Files:**
- Create: `backend/src/lib/ai/index.ts`
- Test: `backend/src/lib/ai/index.test.ts`

**Interfaces:**
- Consumes: `AIProvider` (types.ts), `DeepSeekProvider` (deepseekProvider.ts) from Task 2.
- Produces: `function getAIProvider(): AIProvider` — reads `AI_PROVIDER`/`DEEPSEEK_API_KEY`/`DEEPSEEK_MODEL` from `process.env`.

- [ ] **Step 1: Write the failing test**

```ts
// backend/src/lib/ai/index.test.ts
import { getAIProvider } from "./index";
import { DeepSeekProvider } from "./deepseekProvider";

describe("getAIProvider", () => {
  const ORIGINAL_ENV = process.env;

  beforeEach(() => {
    process.env = { ...ORIGINAL_ENV };
  });

  afterAll(() => {
    process.env = ORIGINAL_ENV;
  });

  it("returns a DeepSeekProvider by default", () => {
    delete process.env.AI_PROVIDER;
    process.env.DEEPSEEK_API_KEY = "key-123";
    const provider = getAIProvider();
    expect(provider).toBeInstanceOf(DeepSeekProvider);
  });

  it("throws a clear error when DEEPSEEK_API_KEY is missing", () => {
    process.env.AI_PROVIDER = "deepseek";
    delete process.env.DEEPSEEK_API_KEY;
    expect(() => getAIProvider()).toThrow("DEEPSEEK_API_KEY environment variable is not set");
  });

  it("throws on an unknown AI_PROVIDER value", () => {
    process.env.AI_PROVIDER = "openai";
    expect(() => getAIProvider()).toThrow("Unknown AI_PROVIDER: openai");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && npx jest src/lib/ai/index.test.ts`
Expected: FAIL with "Cannot find module './index'"

- [ ] **Step 3: Implement the factory**

```ts
// backend/src/lib/ai/index.ts
import { AIProvider } from "./types";
import { DeepSeekProvider } from "./deepseekProvider";

export function getAIProvider(): AIProvider {
  const provider = (process.env.AI_PROVIDER || "deepseek").toLowerCase();

  switch (provider) {
    case "deepseek": {
      const apiKey = process.env.DEEPSEEK_API_KEY;
      if (!apiKey) {
        throw new Error("DEEPSEEK_API_KEY environment variable is not set");
      }
      return new DeepSeekProvider(apiKey, process.env.DEEPSEEK_MODEL || "deepseek-chat");
    }
    default:
      throw new Error(`Unknown AI_PROVIDER: ${provider}`);
  }
}

export type { AIProvider } from "./types";
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && npx jest src/lib/ai/index.test.ts`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add backend/src/lib/ai/index.ts backend/src/lib/ai/index.test.ts
git commit -m "feat: add AI provider factory selected via AI_PROVIDER env var"
```

---

### Task 4: Victim data anonymization

**Files:**
- Create: `backend/src/lib/missionReportAnonymize.ts`
- Test: `backend/src/lib/missionReportAnonymize.test.ts`

**Interfaces:**
- Produces: `interface VictimNarrativeInput { chiefComplaint: string | null; medicalHistory: string | null; notes: string | null; }`, `function anonymizeVictimForPrompt(victim: VictimNarrativeInput): { chiefComplaint: string | null; medicalHistory: string | null; notes: string | null }`.

- [ ] **Step 1: Write the failing test**

```ts
// backend/src/lib/missionReportAnonymize.test.ts
import { anonymizeVictimForPrompt } from "./missionReportAnonymize";

describe("anonymizeVictimForPrompt", () => {
  it("passes through only the free-text medical fields", () => {
    const result = anonymizeVictimForPrompt({
      chiefComplaint: "Θωρακικό άλγος",
      medicalHistory: "Υπέρταση",
      notes: "Μεταφέρθηκε σε νοσοκομείο",
    });

    expect(result).toEqual({
      chiefComplaint: "Θωρακικό άλγος",
      medicalHistory: "Υπέρταση",
      notes: "Μεταφέρθηκε σε νοσοκομείο",
    });
  });

  it("strips any extra fields present on the input object (e.g. accidental PII)", () => {
    const result = anonymizeVictimForPrompt({
      chiefComplaint: "Κάταγμα άκρου",
      medicalHistory: null,
      notes: null,
      // @ts-expect-error verifying extra fields are dropped even if present
      name: "Παπαδόπουλος Γεώργιος",
      // @ts-expect-error
      telephone: "+302101234567",
    });

    expect(result).toEqual({
      chiefComplaint: "Κάταγμα άκρου",
      medicalHistory: null,
      notes: null,
    });
    expect(Object.keys(result)).toEqual(["chiefComplaint", "medicalHistory", "notes"]);
  });

  it("handles all-null fields", () => {
    const result = anonymizeVictimForPrompt({
      chiefComplaint: null,
      medicalHistory: null,
      notes: null,
    });
    expect(result).toEqual({ chiefComplaint: null, medicalHistory: null, notes: null });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && npx jest src/lib/missionReportAnonymize.test.ts`
Expected: FAIL with "Cannot find module './missionReportAnonymize'"

- [ ] **Step 3: Implement the function**

```ts
// backend/src/lib/missionReportAnonymize.ts
export interface VictimNarrativeInput {
  chiefComplaint: string | null;
  medicalHistory: string | null;
  notes: string | null;
}

/**
 * Defensive allow-list: only these three free-text fields may ever reach
 * an external AI provider. Never widen this to include name, address,
 * telephone, emergencyContact, emergencyPhone, dateOfBirth, city, or
 * postalCode, even if the caller's input object happens to carry them.
 */
export function anonymizeVictimForPrompt(victim: VictimNarrativeInput): VictimNarrativeInput {
  return {
    chiefComplaint: victim.chiefComplaint,
    medicalHistory: victim.medicalHistory,
    notes: victim.notes,
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && npx jest src/lib/missionReportAnonymize.test.ts`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add backend/src/lib/missionReportAnonymize.ts backend/src/lib/missionReportAnonymize.test.ts
git commit -m "feat: add victim data anonymization boundary for AI prompts"
```

---

### Task 5: Data types + Prisma aggregation query

**Files:**
- Create: `backend/src/lib/missionReportData.ts`

**Interfaces:**
- Consumes: `prisma` default export from `backend/src/lib/prisma.ts`.
- Produces: `MissionReportData` interface (and its sub-interfaces `MissionSummary`, `PersonnelEntry`, `VehicleUsageEntry`, `ItemUsageEntry`, `VictimSummaryEntry`) and `async function aggregateMissionReportData(serviceIds: number[]): Promise<MissionReportData>` — consumed by Task 8 (routes) and Task 7 (PDF renderer, via its `MissionReportData` type).

This task has no isolated unit test — it is a thin Prisma-query composition with no branching logic worth mocking, and this codebase has no precedent for mocking `PrismaClient` in tests (verified: no `jest.mock` of `../lib/prisma` exists anywhere in `backend/src`). It is exercised end-to-end by Task 8's manual verification step.

- [ ] **Step 1: Write the types and aggregation function**

```ts
// backend/src/lib/missionReportData.ts
import prisma from "./prisma";

export interface MissionSummary {
  id: number;
  name: string;
  departmentName: string;
  location: string | null;
  startAt: string | null;
  endAt: string | null;
  lifecycleStatus: string;
}

export interface PersonnelEntry {
  userId: number;
  fullName: string;
  rank: string;
  status: string;
  hours: number;
}

export interface VehicleUsageEntry {
  vehicleId: number;
  vehicleName: string;
  driverFullName: string;
  meterType: string;
  startAt: string;
  endAt: string | null;
  distance: number | null;
  destination: string | null;
}

export interface ItemUsageEntry {
  itemName: string;
  userFullName: string;
  assignedAt: string;
  comment: string | null;
}

export interface VictimSummaryEntry {
  id: number;
  chiefComplaint: string | null;
  medicalHistory: string | null;
  notes: string | null;
  isFinalized: boolean;
}

export interface MissionReportData {
  missions: MissionSummary[];
  personnel: PersonnelEntry[];
  vehicles: VehicleUsageEntry[];
  items: ItemUsageEntry[];
  victims: VictimSummaryEntry[];
  totals: {
    personnelCount: number;
    totalHours: number;
    vehicleCount: number;
    itemCount: number;
    victimCount: number;
  };
}

function fullName(user: { forename: string; surname: string }): string {
  return `${user.forename} ${user.surname}`.trim();
}

export async function aggregateMissionReportData(serviceIds: number[]): Promise<MissionReportData> {
  const [servicesRaw, userServicesRaw, vehicleLogsRaw, itemServicesRaw, victimsRaw] = await Promise.all([
    prisma.service.findMany({
      where: { id: { in: serviceIds } },
      select: {
        id: true,
        name: true,
        location: true,
        startAt: true,
        endAt: true,
        lifecycleStatus: true,
        department: { select: { name: true } },
      },
    }),
    prisma.userService.findMany({
      where: { serviceId: { in: serviceIds } },
      select: {
        status: true,
        hours: true,
        hoursVol: true,
        hoursTraining: true,
        hoursTrainers: true,
        hoursTEP: true,
        user: { select: { id: true, forename: true, surname: true, rank: true } },
      },
    }),
    prisma.vehicleLog.findMany({
      where: { serviceId: { in: serviceIds } },
      select: {
        startAt: true,
        endAt: true,
        meterStart: true,
        meterEnd: true,
        destination: true,
        vehicle: { select: { id: true, name: true, meterType: true } },
        user: { select: { forename: true, surname: true } },
      },
    }),
    prisma.itemService.findMany({
      where: { serviceId: { in: serviceIds } },
      select: {
        assignedAt: true,
        comment: true,
        item: { select: { name: true } },
        user: { select: { forename: true, surname: true } },
      },
    }),
    prisma.victim.findMany({
      where: { serviceId: { in: serviceIds } },
      select: {
        id: true,
        chiefComplaint: true,
        medicalHistory: true,
        notes: true,
        isFinalized: true,
      },
    }),
  ]);

  const missions: MissionSummary[] = servicesRaw.map((s) => ({
    id: s.id,
    name: s.name,
    departmentName: s.department.name,
    location: s.location,
    startAt: s.startAt ? s.startAt.toISOString() : null,
    endAt: s.endAt ? s.endAt.toISOString() : null,
    lifecycleStatus: s.lifecycleStatus,
  }));

  const personnel: PersonnelEntry[] = userServicesRaw.map((us) => ({
    userId: us.user.id,
    fullName: fullName(us.user),
    rank: us.user.rank,
    status: us.status,
    hours: us.hours + us.hoursVol + us.hoursTraining + us.hoursTrainers + us.hoursTEP,
  }));

  const vehicles: VehicleUsageEntry[] = vehicleLogsRaw.map((log) => ({
    vehicleId: log.vehicle.id,
    vehicleName: log.vehicle.name,
    driverFullName: fullName(log.user),
    meterType: log.vehicle.meterType,
    startAt: log.startAt.toISOString(),
    endAt: log.endAt ? log.endAt.toISOString() : null,
    distance: log.meterEnd ? log.meterEnd.toNumber() - log.meterStart.toNumber() : null,
    destination: log.destination,
  }));

  const items: ItemUsageEntry[] = itemServicesRaw.map((is) => ({
    itemName: is.item.name,
    userFullName: fullName(is.user),
    assignedAt: is.assignedAt.toISOString(),
    comment: is.comment,
  }));

  const victims: VictimSummaryEntry[] = victimsRaw.map((v) => ({
    id: v.id,
    chiefComplaint: v.chiefComplaint,
    medicalHistory: v.medicalHistory,
    notes: v.notes,
    isFinalized: v.isFinalized,
  }));

  return {
    missions,
    personnel,
    vehicles,
    items,
    victims,
    totals: {
      personnelCount: personnel.length,
      totalHours: personnel.reduce((sum, p) => sum + p.hours, 0),
      vehicleCount: vehicles.length,
      itemCount: items.length,
      victimCount: victims.length,
    },
  };
}
```

- [ ] **Step 2: Type-check**

Run: `cd backend && npx tsc --noEmit`
Expected: no errors referencing `missionReportData.ts`.

- [ ] **Step 3: Commit**

```bash
git add backend/src/lib/missionReportData.ts
git commit -m "feat: add mission report data aggregation query"
```

---

### Task 6: Press-release prompt builder

**Files:**
- Create: `backend/src/lib/missionReportPrompt.ts`
- Test: `backend/src/lib/missionReportPrompt.test.ts`

**Interfaces:**
- Consumes: `MissionReportData` from `backend/src/lib/missionReportData.ts` (Task 5), `VictimNarrativeInput` from `backend/src/lib/missionReportAnonymize.ts` (Task 4).
- Produces: `function buildPressReleasePrompt(data: MissionReportData, anonymizedVictims: VictimNarrativeInput[]): string`.

- [ ] **Step 1: Write the failing test**

```ts
// backend/src/lib/missionReportPrompt.test.ts
import { buildPressReleasePrompt } from "./missionReportPrompt";
import { MissionReportData } from "./missionReportData";

const SAMPLE_DATA: MissionReportData = {
  missions: [
    {
      id: 1,
      name: "Πλημμύρες Αττικής",
      departmentName: "Κεντρικό Τμήμα",
      location: "Αθήνα",
      startAt: "2026-06-01T08:00:00.000Z",
      endAt: "2026-06-02T20:00:00.000Z",
      lifecycleStatus: "completed",
    },
  ],
  personnel: [
    { userId: 1, fullName: "Γιώργος Παπαδόπουλος", rank: "Α", status: "accepted", hours: 12 },
  ],
  vehicles: [
    {
      vehicleId: 1,
      vehicleName: "Ασθενοφόρο 1",
      driverFullName: "Μαρία Ιωάννου",
      meterType: "km",
      startAt: "2026-06-01T08:00:00.000Z",
      endAt: "2026-06-01T18:00:00.000Z",
      distance: 45,
      destination: "Νοσοκομείο ΚΑΤ",
    },
  ],
  items: [
    { itemName: "Φορείο", userFullName: "Γιώργος Παπαδόπουλος", assignedAt: "2026-06-01T08:00:00.000Z", comment: null },
  ],
  victims: [
    { id: 1, chiefComplaint: "Κάταγμα άκρου", medicalHistory: null, notes: null, isFinalized: true },
  ],
  totals: { personnelCount: 1, totalHours: 12, vehicleCount: 1, itemCount: 1, victimCount: 1 },
};

describe("buildPressReleasePrompt", () => {
  it("includes mission names, aggregate counts, and asks for a Greek press release", () => {
    const prompt = buildPressReleasePrompt(SAMPLE_DATA, [
      { chiefComplaint: "Κάταγμα άκρου", medicalHistory: null, notes: null },
    ]);

    expect(prompt).toContain("Πλημμύρες Αττικής");
    expect(prompt).toContain("Κεντρικό Τμήμα");
    expect(prompt).toContain("1 άτομα προσωπικού");
    expect(prompt).toContain("1 οχήματα");
    expect(prompt).toContain("1 τραυματίες");
    expect(prompt).toContain("Κάταγμα άκρου");
    expect(prompt).toContain("ΔΕΛΤΙΟ ΤΥΠΟΥ");
  });

  it("omits victim section text when there are no victims", () => {
    const prompt = buildPressReleasePrompt({ ...SAMPLE_DATA, victims: [], totals: { ...SAMPLE_DATA.totals, victimCount: 0 } }, []);
    expect(prompt).toContain("0 τραυματίες");
    expect(prompt).not.toContain("Κάταγμα άκρου");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && npx jest src/lib/missionReportPrompt.test.ts`
Expected: FAIL with "Cannot find module './missionReportPrompt'"

- [ ] **Step 3: Implement the prompt builder**

```ts
// backend/src/lib/missionReportPrompt.ts
import { MissionReportData } from "./missionReportData";
import { VictimNarrativeInput } from "./missionReportAnonymize";

export function buildPressReleasePrompt(
  data: MissionReportData,
  anonymizedVictims: VictimNarrativeInput[],
): string {
  const missionLines = data.missions
    .map((m) => `- ${m.name} (${m.departmentName}), ${m.startAt ?? "άγνωστη ημερομηνία"} έως ${m.endAt ?? "εν εξελίξει"}`)
    .join("\n");

  const victimLines = anonymizedVictims
    .map((v) => [v.chiefComplaint, v.medicalHistory, v.notes].filter(Boolean).join(" — "))
    .filter((line) => line.length > 0)
    .map((line) => `- ${line}`)
    .join("\n");

  return [
    "Είσαι υπεύθυνος επικοινωνίας ενός οργανισμού διάσωσης και παρέχεις υπηρεσίες έκτακτης ανάγκης.",
    "Με βάση τα παρακάτω στοιχεία, συνέταξε ένα επίσημο ΔΕΛΤΙΟ ΤΥΠΟΥ στα ελληνικά, σε μορφή ενιαίας παραγράφου ή δύο σύντομων παραγράφων, κατάλληλο για δημόσια ανακοίνωση.",
    "",
    "Αποστολές:",
    missionLines,
    "",
    `Σύνολα: ${data.totals.personnelCount} άτομα προσωπικού, ${data.totals.totalHours} συνολικές ώρες, ${data.totals.vehicleCount} οχήματα, ${data.totals.itemCount} τεμάχια υλικού, ${data.totals.victimCount} τραυματίες/διασωθέντες.`,
    "",
    ...(victimLines
      ? ["Σύνοψη περιστατικών (χωρίς προσωπικά στοιχεία):", victimLines, ""]
      : []),
    "Γράψε το κείμενο σε επίσημο, αντικειμενικό ύφος, χωρίς να αναφέρεις ονόματα ή προσωπικά στοιχεία διασωθέντων.",
  ].join("\n");
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && npx jest src/lib/missionReportPrompt.test.ts`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add backend/src/lib/missionReportPrompt.ts backend/src/lib/missionReportPrompt.test.ts
git commit -m "feat: add Greek press-release prompt builder"
```

---

### Task 7: PDF renderer

**Files:**
- Create: `backend/src/lib/missionReportPdf.ts`
- Test: `backend/src/lib/missionReportPdf.test.ts`

**Interfaces:**
- Consumes: `MissionReportData` from `backend/src/lib/missionReportData.ts` (Task 5), `pdfkit` (Task 1).
- Produces: `function renderMissionReportPdf(data: MissionReportData, narrativeText: string): Promise<Buffer>`.

- [ ] **Step 1: Write the failing test**

```ts
// backend/src/lib/missionReportPdf.test.ts
import { renderMissionReportPdf } from "./missionReportPdf";
import { MissionReportData } from "./missionReportData";

const SAMPLE_DATA: MissionReportData = {
  missions: [
    { id: 1, name: "Πλημμύρες Αττικής", departmentName: "Κεντρικό Τμήμα", location: "Αθήνα", startAt: null, endAt: null, lifecycleStatus: "completed" },
  ],
  personnel: [],
  vehicles: [],
  items: [],
  victims: [],
  totals: { personnelCount: 0, totalHours: 0, vehicleCount: 0, itemCount: 0, victimCount: 0 },
};

describe("renderMissionReportPdf", () => {
  it("produces a valid, non-empty PDF buffer", async () => {
    const buffer = await renderMissionReportPdf(SAMPLE_DATA, "Δοκιμαστικό κείμενο δελτίου τύπου.");

    expect(Buffer.isBuffer(buffer)).toBe(true);
    expect(buffer.length).toBeGreaterThan(100);
    expect(buffer.subarray(0, 5).toString("latin1")).toBe("%PDF-");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && npx jest src/lib/missionReportPdf.test.ts`
Expected: FAIL with "Cannot find module './missionReportPdf'"

- [ ] **Step 3: Implement the PDF renderer**

```ts
// backend/src/lib/missionReportPdf.ts
import PDFDocument from "pdfkit";
import { MissionReportData } from "./missionReportData";

export function renderMissionReportPdf(data: MissionReportData, narrativeText: string): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ margin: 50 });
    const chunks: Buffer[] = [];
    doc.on("data", (chunk) => chunks.push(chunk));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);

    doc.fontSize(18).text("Αναφορά Αποστολής", { align: "center" });
    doc.moveDown(1.5);

    doc.fontSize(14).text("ΔΕΛΤΙΟ ΤΥΠΟΥ");
    doc.moveDown(0.5);
    doc.fontSize(11).text(narrativeText, { align: "justify" });
    doc.moveDown(1.5);

    doc.fontSize(14).text("Αποστολές");
    doc.moveDown(0.5);
    data.missions.forEach((m) => {
      doc.fontSize(11).text(`${m.name} — ${m.departmentName} (${m.startAt ?? "-"} έως ${m.endAt ?? "-"})`);
    });
    doc.moveDown(1);

    doc.fontSize(14).text("Προσωπικό");
    doc.moveDown(0.5);
    if (data.personnel.length === 0) {
      doc.fontSize(11).text("Δεν καταχωρήθηκε προσωπικό.");
    }
    data.personnel.forEach((p) => {
      doc.fontSize(11).text(`${p.fullName} (${p.rank}) — ${p.status} — ${p.hours} ώρες`);
    });
    doc.moveDown(1);

    doc.fontSize(14).text("Οχήματα");
    doc.moveDown(0.5);
    if (data.vehicles.length === 0) {
      doc.fontSize(11).text("Δεν καταχωρήθηκε χρήση οχημάτων.");
    }
    data.vehicles.forEach((v) => {
      doc.fontSize(11).text(`${v.vehicleName} — οδηγός: ${v.driverFullName} — ${v.distance ?? "-"} ${v.meterType}`);
    });
    doc.moveDown(1);

    doc.fontSize(14).text("Υλικό");
    doc.moveDown(0.5);
    if (data.items.length === 0) {
      doc.fontSize(11).text("Δεν καταχωρήθηκε χρήση υλικού.");
    }
    data.items.forEach((i) => {
      doc.fontSize(11).text(`${i.itemName} — ${i.userFullName}`);
    });
    doc.moveDown(1);

    doc.fontSize(14).text("Διασωθέντες / Τραυματίες");
    doc.moveDown(0.5);
    doc.fontSize(11).text(`Σύνολο: ${data.totals.victimCount}`);

    doc.end();
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && npx jest src/lib/missionReportPdf.test.ts`
Expected: PASS (1 test)

- [ ] **Step 5: Commit**

```bash
git add backend/src/lib/missionReportPdf.ts backend/src/lib/missionReportPdf.test.ts
git commit -m "feat: add pdfkit-based mission report PDF renderer"
```

---

### Task 8: Route handlers + mounting

**Files:**
- Create: `backend/src/routes/missionReport.routes.ts`
- Modify: `backend/src/app.ts`

**Interfaces:**
- Consumes: `authenticate`, `getMissionAdminDepartmentIds` (`backend/src/middleware/auth.ts`); `aggregateMissionReportData`, `MissionReportData` (Task 5); `anonymizeVictimForPrompt` (Task 4); `buildPressReleasePrompt` (Task 6); `getAIProvider` (Task 3); `renderMissionReportPdf` (Task 7).
- Produces: `GET /api/reports/missions`, `POST /api/reports/generate`, `POST /api/reports/pdf`.

- [ ] **Step 1: Write `missionReport.routes.ts`**

```ts
// backend/src/routes/missionReport.routes.ts
import { Router, Request, Response } from "express";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate, getMissionAdminDepartmentIds } from "../middleware/auth";
import { aggregateMissionReportData, MissionReportData } from "../lib/missionReportData";
import { anonymizeVictimForPrompt } from "../lib/missionReportAnonymize";
import { buildPressReleasePrompt } from "../lib/missionReportPrompt";
import { getAIProvider } from "../lib/ai";
import { renderMissionReportPdf } from "../lib/missionReportPdf";

const router = Router();
router.use(authenticate);

interface ReportScope {
  isAdmin: boolean;
  departmentIds: number[];
}

async function getReportScope(req: Request): Promise<ReportScope> {
  if (req.user!.isAdmin) {
    return { isAdmin: true, departmentIds: [] };
  }
  const departmentIds = await getMissionAdminDepartmentIds(req.user!.userId);
  return { isAdmin: false, departmentIds };
}

// ── GET /api/reports/missions ───────────────────
router.get("/missions", async (req: Request, res: Response) => {
  const scope = await getReportScope(req);
  if (!scope.isAdmin && scope.departmentIds.length === 0) {
    res.status(403).json({ error: "Δεν έχετε δικαίωμα πρόσβασης σε αναφορές αποστολών" });
    return;
  }

  const departmentIdParam = req.query.departmentId ? Number(req.query.departmentId) : undefined;
  if (
    departmentIdParam !== undefined &&
    !scope.isAdmin &&
    !scope.departmentIds.includes(departmentIdParam)
  ) {
    res.status(403).json({ error: "Δεν έχετε δικαίωμα για αυτό το τμήμα" });
    return;
  }

  const where: any = scope.isAdmin ? {} : { departmentId: { in: scope.departmentIds } };
  if (departmentIdParam !== undefined) {
    where.departmentId = departmentIdParam;
  }

  const from = req.query.from ? new Date(req.query.from as string) : undefined;
  const to = req.query.to ? new Date(req.query.to as string) : undefined;
  if (from) where.OR = [{ endAt: { gte: from } }, { endAt: null }];
  if (to) where.startAt = { lte: to };

  const search = (req.query.search as string | undefined)?.trim();
  if (search) {
    where.name = { contains: search, mode: "insensitive" };
  }

  const missions = await prisma.service.findMany({
    where,
    select: {
      id: true,
      name: true,
      startAt: true,
      endAt: true,
      lifecycleStatus: true,
      department: { select: { id: true, name: true } },
    },
    orderBy: { startAt: "desc" },
  });

  res.json(missions);
});

// ── POST /api/reports/generate ──────────────────
const generateSchema = z.union([
  z.object({ serviceIds: z.array(z.number().int()).min(1) }),
  z.object({
    departmentId: z.number().int().optional(),
    from: z.string().datetime(),
    to: z.string().datetime(),
  }),
]);

router.post("/generate", async (req: Request, res: Response) => {
  try {
    const scope = await getReportScope(req);
    if (!scope.isAdmin && scope.departmentIds.length === 0) {
      res.status(403).json({ error: "Δεν έχετε δικαίωμα πρόσβασης σε αναφορές αποστολών" });
      return;
    }

    const input = generateSchema.parse(req.body);

    let serviceIds: number[];
    if ("serviceIds" in input) {
      serviceIds = input.serviceIds;
    } else {
      if (
        input.departmentId !== undefined &&
        !scope.isAdmin &&
        !scope.departmentIds.includes(input.departmentId)
      ) {
        res.status(403).json({ error: "Δεν έχετε δικαίωμα για αυτό το τμήμα" });
        return;
      }

      const where: any = {
        startAt: { lte: new Date(input.to) },
        OR: [{ endAt: { gte: new Date(input.from) } }, { endAt: null }],
      };
      if (input.departmentId !== undefined) {
        where.departmentId = input.departmentId;
      } else if (!scope.isAdmin) {
        where.departmentId = { in: scope.departmentIds };
      }

      const resolved = await prisma.service.findMany({ where, select: { id: true } });
      serviceIds = resolved.map((s) => s.id);
    }

    if (serviceIds.length === 0) {
      res.status(400).json({ error: "Δεν βρέθηκαν αποστολές για τα επιλεγμένα κριτήρια" });
      return;
    }

    if (!scope.isAdmin) {
      const allowedCount = await prisma.service.count({
        where: { id: { in: serviceIds }, departmentId: { in: scope.departmentIds } },
      });
      if (allowedCount !== serviceIds.length) {
        res.status(403).json({ error: "Δεν έχετε δικαίωμα για μία ή περισσότερες αποστολές" });
        return;
      }
    }

    const structuredData: MissionReportData = await aggregateMissionReportData(serviceIds);

    let narrativeDraft: string | null = null;
    let narrativeError: string | undefined;
    try {
      const provider = getAIProvider();
      const anonymizedVictims = structuredData.victims.map(anonymizeVictimForPrompt);
      const prompt = buildPressReleasePrompt(structuredData, anonymizedVictims);
      narrativeDraft = await provider.generatePressRelease(prompt);
    } catch (err: any) {
      narrativeError = err.message || "Η δημιουργία του κειμένου απέτυχε";
    }

    res.json({ structuredData, narrativeDraft, narrativeError });
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Validation failed", details: err.errors });
      return;
    }
    throw err;
  }
});

// ── POST /api/reports/pdf ────────────────────────
const pdfSchema = z.object({
  structuredData: z.custom<MissionReportData>((val) => typeof val === "object" && val !== null),
  narrativeText: z.string(),
});

router.post("/pdf", async (req: Request, res: Response) => {
  try {
    const { structuredData, narrativeText } = pdfSchema.parse(req.body);
    const buffer = await renderMissionReportPdf(structuredData, narrativeText);
    res.setHeader("Content-Type", "application/pdf");
    res.setHeader("Content-Disposition", 'attachment; filename="mission-report.pdf"');
    res.send(buffer);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Validation failed", details: err.errors });
      return;
    }
    throw err;
  }
});

export default router;
```

- [ ] **Step 2: Mount the router in `app.ts`**

Edit `backend/src/app.ts`: add the import after line 26 (`import victimRoutes from "./routes/victim.routes";`):

```ts
import missionReportRoutes from "./routes/missionReport.routes";
```

Add the mount line after line 57 (`app.use("/api/victims", victimRoutes);`):

```ts
app.use("/api/reports", missionReportRoutes);
```

- [ ] **Step 3: Type-check**

Run: `cd backend && npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 4: Manual verification against the dev database**

This route composes DB queries with no existing supertest precedent in this codebase (verified: no `.test.ts` file under `backend/src/routes/` uses `supertest` against a live app instance). Verify manually:

```bash
cd backend
npm run dev
```

In a second terminal, log in as a sys admin via `POST /api/auth/login` to get a JWT, then:

```bash
curl -H "Authorization: Bearer <token>" "http://localhost:4000/api/reports/missions"
```
Expected: 200 with a JSON array of missions (or `[]` if none exist in the dev DB — seed one via `npm run seed` or Prisma Studio if needed).

```bash
curl -X POST -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
  -d '{"serviceIds":[1]}' "http://localhost:4000/api/reports/generate"
```
Expected: 200 with `{ structuredData, narrativeDraft, narrativeError }`. If `DEEPSEEK_API_KEY` is unset, `narrativeDraft` is `null` and `narrativeError` is set — this is correct fallback behavior, not a bug.

```bash
curl -X POST -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
  -d '{"structuredData": <paste structuredData from the previous response>, "narrativeText": "Δοκιμή"}' \
  "http://localhost:4000/api/reports/pdf" --output test-report.pdf
```
Expected: `test-report.pdf` opens as a valid PDF.

- [ ] **Step 5: Commit**

```bash
git add backend/src/routes/missionReport.routes.ts backend/src/app.ts
git commit -m "feat: add mission report API endpoints"
```

---

### Task 9: Frontend provider

**Files:**
- Create: `frontend/lib/providers/mission_report_provider.dart`
- Modify: `frontend/lib/main.dart`

**Interfaces:**
- Consumes: `ApiClient` (`services/api_client.dart`), `downloadFile` (`services/download_helper.dart`).
- Produces: `class MissionReportProvider extends ChangeNotifier` with `Future<void> fetchMissions({int? departmentId, String? from, String? to, String? search})`, `Future<bool> generateReport(Map<String, dynamic> body)`, `void setNarrativeText(String text)`, `Future<String?> exportPdf()`, and getters `missions`, `loadingMissions`, `generating`, `structuredData`, `narrativeText`, `narrativeError`, `reportError`.

- [ ] **Step 1: Write the provider**

```dart
// frontend/lib/providers/mission_report_provider.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/api_client.dart';
import '../services/download_helper.dart';

class MissionReportProvider extends ChangeNotifier {
  final _api = ApiClient();

  List<dynamic> _missions = [];
  bool _loadingMissions = false;
  bool _generating = false;
  Map<String, dynamic>? _structuredData;
  String? _narrativeText;
  String? _narrativeError;
  String? _reportError;

  List<dynamic> get missions => _missions;
  bool get loadingMissions => _loadingMissions;
  bool get generating => _generating;
  Map<String, dynamic>? get structuredData => _structuredData;
  String? get narrativeText => _narrativeText;
  String? get narrativeError => _narrativeError;
  String? get reportError => _reportError;

  void setNarrativeText(String text) {
    _narrativeText = text;
    notifyListeners();
  }

  Future<void> fetchMissions({
    int? departmentId,
    String? from,
    String? to,
    String? search,
  }) async {
    _loadingMissions = true;
    notifyListeners();
    try {
      final params = <String, String>{};
      if (departmentId != null) params['departmentId'] = departmentId.toString();
      if (from != null) params['from'] = from;
      if (to != null) params['to'] = to;
      if (search != null && search.isNotEmpty) params['search'] = search;
      final query = params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';
      final res = await _api.get('/reports/missions$query');
      if (res.statusCode == 200) {
        _missions = jsonDecode(res.body);
      }
    } catch (_) {}
    _loadingMissions = false;
    notifyListeners();
  }

  Future<bool> generateReport(Map<String, dynamic> body) async {
    _generating = true;
    _reportError = null;
    notifyListeners();
    try {
      final res = await _api.post('/reports/generate', body: body);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        _structuredData = decoded['structuredData'] as Map<String, dynamic>;
        _narrativeText = decoded['narrativeDraft'] as String?;
        _narrativeError = decoded['narrativeError'] as String?;
        _generating = false;
        notifyListeners();
        return true;
      }
      _reportError = (jsonDecode(res.body) as Map<String, dynamic>)['error'] as String? ??
          'Η δημιουργία της αναφοράς απέτυχε';
    } catch (e) {
      _reportError = 'Σφάλμα: $e';
    }
    _generating = false;
    notifyListeners();
    return false;
  }

  Future<String?> exportPdf() async {
    if (_structuredData == null || _narrativeText == null) {
      return 'Δεν υπάρχουν δεδομένα αναφοράς';
    }
    try {
      final res = await _api.post('/reports/pdf', body: {
        'structuredData': _structuredData,
        'narrativeText': _narrativeText,
      });
      if (res.statusCode == 200) {
        await downloadFile(res.bodyBytes, 'mission-report.pdf');
        return null;
      }
      return 'Η εξαγωγή PDF απέτυχε';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }
}
```

- [ ] **Step 2: Register the provider in `main.dart`**

Edit `frontend/lib/main.dart`: add the import near the other provider imports, and add this line after line 93 (`ChangeNotifierProvider(create: (_) => VictimProvider()),`):

```dart
import 'providers/mission_report_provider.dart';
```

```dart
ChangeNotifierProvider(create: (_) => MissionReportProvider()),
```

- [ ] **Step 3: Verify it compiles**

Run: `cd frontend && flutter analyze lib/providers/mission_report_provider.dart lib/main.dart`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/providers/mission_report_provider.dart frontend/lib/main.dart
git commit -m "feat: add MissionReportProvider"
```

---

### Task 10: Selection screen + route + admin tile

**Files:**
- Create: `frontend/lib/screens/mission_report_selection_screen.dart`
- Modify: `frontend/lib/config/router.dart`
- Modify: `frontend/lib/screens/admin_panel_screen.dart`

**Interfaces:**
- Consumes: `MissionReportProvider` (Task 9), `AuthProvider` (`isAdmin`, `missionAdminDepartments` getters — existing).
- Produces: route `/admin/mission-report`; navigates to `/admin/mission-report/result` on successful generation (built in Task 11).

- [ ] **Step 1: Write the selection screen**

```dart
// frontend/lib/screens/mission_report_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/mission_report_provider.dart';

class MissionReportSelectionScreen extends StatefulWidget {
  const MissionReportSelectionScreen({super.key});

  @override
  State<MissionReportSelectionScreen> createState() => _MissionReportSelectionScreenState();
}

class _MissionReportSelectionScreenState extends State<MissionReportSelectionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int? _singleMissionId;
  final Set<int> _multiMissionIds = {};
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _departmentFilter;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    Future.microtask(() {
      if (!mounted) return;
      context.read<MissionReportProvider>().fetchMissions();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_fromDate ?? now) : (_toDate ?? now),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
  }

  Future<void> _generate() async {
    setState(() => _error = null);
    final provider = context.read<MissionReportProvider>();

    Map<String, dynamic> body;
    if (_tabController.index == 0) {
      if (_singleMissionId == null) {
        setState(() => _error = 'Επιλέξτε μία αποστολή');
        return;
      }
      body = {'serviceIds': [_singleMissionId]};
    } else if (_tabController.index == 1) {
      if (_multiMissionIds.isEmpty) {
        setState(() => _error = 'Επιλέξτε τουλάχιστον μία αποστολή');
        return;
      }
      body = {'serviceIds': _multiMissionIds.toList()};
    } else {
      if (_fromDate == null || _toDate == null) {
        setState(() => _error = 'Επιλέξτε εύρος ημερομηνιών');
        return;
      }
      body = {
        'from': _fromDate!.toUtc().toIso8601String(),
        'to': _toDate!.toUtc().toIso8601String(),
        if (_departmentFilter != null) 'departmentId': _departmentFilter,
      };
    }

    final ok = await provider.generateReport(body);
    if (!mounted) return;
    if (ok) {
      context.push('/admin/mission-report/result');
    } else {
      setState(() => _error = provider.reportError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<MissionReportProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Αναφορά Αποστολών'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Μία Αποστολή'),
            Tab(text: 'Πολλές Αποστολές'),
            Tab(text: 'Εύρος Ημερομηνιών'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSingleTab(provider),
                _buildMultiTab(provider),
                _buildDateRangeTab(auth),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: provider.generating ? null : _generate,
                child: provider.generating
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Δημιουργία Αναφοράς'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleTab(MissionReportProvider provider) {
    if (provider.loadingMissions) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<int>(
          value: _singleMissionId,
          decoration: const InputDecoration(labelText: 'Αποστολή'),
          items: provider.missions.map((m) {
            final map = m as Map<String, dynamic>;
            return DropdownMenuItem<int>(
              value: map['id'] as int,
              child: Text(map['name'] as String),
            );
          }).toList(),
          onChanged: (value) => setState(() => _singleMissionId = value),
        ),
      ],
    );
  }

  Widget _buildMultiTab(MissionReportProvider provider) {
    if (provider.loadingMissions) return const Center(child: CircularProgressIndicator());
    return ListView(
      children: provider.missions.map((m) {
        final map = m as Map<String, dynamic>;
        final id = map['id'] as int;
        return CheckboxListTile(
          title: Text(map['name'] as String),
          value: _multiMissionIds.contains(id),
          onChanged: (sel) {
            setState(() {
              if (sel == true) {
                _multiMissionIds.add(id);
              } else {
                _multiMissionIds.remove(id);
              }
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildDateRangeTab(AuthProvider auth) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          title: const Text('Από'),
          subtitle: Text(_fromDate?.toLocal().toString().split(' ').first ?? 'Επιλογή'),
          trailing: const Icon(Icons.calendar_today),
          onTap: () => _pickDate(isFrom: true),
        ),
        ListTile(
          title: const Text('Έως'),
          subtitle: Text(_toDate?.toLocal().toString().split(' ').first ?? 'Επιλογή'),
          trailing: const Icon(Icons.calendar_today),
          onTap: () => _pickDate(isFrom: false),
        ),
        if (auth.isAdmin) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<int?>(
            value: _departmentFilter,
            decoration: const InputDecoration(labelText: 'Τμήμα (προαιρετικό)'),
            items: const [
              DropdownMenuItem<int?>(value: null, child: Text('Όλα τα τμήματα')),
            ],
            onChanged: (value) => setState(() => _departmentFilter = value),
          ),
        ],
      ],
    );
  }
}
```

- [ ] **Step 2: Register the route**

Edit `frontend/lib/config/router.dart`: add the import near the other screen imports, and add this `GoRoute` right after the `/admin/service-types` block (after line 235):

```dart
import '../screens/mission_report_selection_screen.dart';
```

```dart
GoRoute(
  path: '/admin/mission-report',
  builder: (context, state) => const MissionReportSelectionScreen(),
),
```

(The result-screen route is added in Task 11 alongside its screen.)

- [ ] **Step 3: Add the admin panel tile**

Edit `frontend/lib/screens/admin_panel_screen.dart`: insert a new `_AdminTileData` entry after the "Διαχείρηση Τμημάτων" tile (after line 157, `),`), **before** the `if (isSysAdmin) ...[` block starts at line 158 — so it's visible to both sys admins and department mission admins:

```dart
_AdminTileData(
  icon: Icons.campaign,
  iconColor: const Color(0xFF059669),
  bgColor: const Color(0xFFD1FAE5),
  title: 'Αναφορά Αποστολών',
  subtitle: 'Δημιουργία αναφοράς με τεχνητή νοημοσύνη',
  onTap: () => context.push('/admin/mission-report'),
),
```

- [ ] **Step 4: Verify it compiles**

Run: `cd frontend && flutter analyze lib/screens/mission_report_selection_screen.dart lib/config/router.dart lib/screens/admin_panel_screen.dart`
Expected: no errors. (A warning about the unused `/admin/mission-report/result` route not existing yet is expected until Task 11 — if `flutter analyze` reports an undefined `MissionReportResultScreen` reference, that only happens once Task 11's `context.push` is added, which is not part of this task.)

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/mission_report_selection_screen.dart frontend/lib/config/router.dart frontend/lib/screens/admin_panel_screen.dart
git commit -m "feat: add mission report selection screen, route, and admin tile"
```

---

### Task 11: Result screen

**Files:**
- Create: `frontend/lib/screens/mission_report_result_screen.dart`
- Modify: `frontend/lib/config/router.dart`

**Interfaces:**
- Consumes: `MissionReportProvider` (Task 9) — `structuredData`, `narrativeText`, `narrativeError`, `setNarrativeText`, `generateReport` (for retry), `exportPdf`.

- [ ] **Step 1: Write the result screen**

```dart
// frontend/lib/screens/mission_report_result_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/mission_report_provider.dart';

class MissionReportResultScreen extends StatefulWidget {
  const MissionReportResultScreen({super.key});

  @override
  State<MissionReportResultScreen> createState() => _MissionReportResultScreenState();
}

class _MissionReportResultScreenState extends State<MissionReportResultScreen> {
  late final TextEditingController _narrativeController;
  String? _exportError;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final provider = context.read<MissionReportProvider>();
    _narrativeController = TextEditingController(text: provider.narrativeText ?? '');
  }

  @override
  void dispose() {
    _narrativeController.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _exportError = null;
    });
    final provider = context.read<MissionReportProvider>();
    provider.setNarrativeText(_narrativeController.text);
    final error = await provider.exportPdf();
    if (!mounted) return;
    setState(() {
      _exporting = false;
      _exportError = error;
    });
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MissionReportProvider>();
    final data = provider.structuredData;

    if (data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Αναφορά Αποστολής')),
        body: const Center(child: Text('Δεν υπάρχουν δεδομένα αναφοράς.')),
      );
    }

    final missions = data['missions'] as List<dynamic>? ?? [];
    final personnel = data['personnel'] as List<dynamic>? ?? [];
    final vehicles = data['vehicles'] as List<dynamic>? ?? [];
    final items = data['items'] as List<dynamic>? ?? [];
    final totals = data['totals'] as Map<String, dynamic>? ?? {};

    return Scaffold(
      appBar: AppBar(title: const Text('Αναφορά Αποστολής')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('ΔΕΛΤΙΟ ΤΥΠΟΥ', [
            if (provider.narrativeError != null) ...[
              Text(provider.narrativeError!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  // Re-request narrative generation with the same mission set.
                  final missionIds = missions
                      .map((m) => (m as Map<String, dynamic>)['id'] as int)
                      .toList();
                  await provider.generateReport({'serviceIds': missionIds});
                  _narrativeController.text = provider.narrativeText ?? '';
                },
                child: const Text('Δημιουργία Ξανά'),
              ),
            ] else
              TextField(
                controller: _narrativeController,
                maxLines: 8,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
          ]),
          _section('Αποστολές', missions.map((m) {
            final map = m as Map<String, dynamic>;
            return Text('${map['name']} — ${map['departmentName']}');
          }).toList()),
          _section('Προσωπικό (${totals['personnelCount'] ?? 0})', personnel.map((p) {
            final map = p as Map<String, dynamic>;
            return Text('${map['fullName']} (${map['rank']}) — ${map['hours']} ώρες');
          }).toList()),
          _section('Οχήματα (${totals['vehicleCount'] ?? 0})', vehicles.map((v) {
            final map = v as Map<String, dynamic>;
            return Text('${map['vehicleName']} — οδηγός: ${map['driverFullName']}');
          }).toList()),
          _section('Υλικό (${totals['itemCount'] ?? 0})', items.map((i) {
            final map = i as Map<String, dynamic>;
            return Text('${map['itemName']} — ${map['userFullName']}');
          }).toList()),
          _section('Διασωθέντες / Τραυματίες', [
            Text('Σύνολο: ${totals['victimCount'] ?? 0}'),
          ]),
          if (_exportError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_exportError!, style: const TextStyle(color: Colors.red)),
            ),
          FilledButton.icon(
            onPressed: _exporting ? null : _export,
            icon: _exporting
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf),
            label: const Text('Εξαγωγή PDF'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Register the route**

Edit `frontend/lib/config/router.dart`: add the import alongside the one added in Task 10, and add this `GoRoute` right after the `/admin/mission-report` route added in Task 10:

```dart
import '../screens/mission_report_result_screen.dart';
```

```dart
GoRoute(
  path: '/admin/mission-report/result',
  builder: (context, state) => const MissionReportResultScreen(),
),
```

- [ ] **Step 3: Verify it compiles**

Run: `cd frontend && flutter analyze lib/screens/mission_report_result_screen.dart lib/config/router.dart`
Expected: no errors.

- [ ] **Step 4: Manual end-to-end verification**

Run: `cd frontend && flutter run -d chrome` (backend running per Task 8 Step 4, with a seeded mission).

Log in as a sys admin, open **Πίνακας Διαχείρισης → Αναφορά Αποστολών**, select a mission in each of the 3 tabs, generate a report, confirm the structured sections render, edit the narrative text, and click **Εξαγωγή PDF** — confirm a PDF downloads and opens correctly. Also verify a department mission-admin account only sees missions from their own department(s).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/mission_report_result_screen.dart frontend/lib/config/router.dart
git commit -m "feat: add mission report result screen with editable narrative and PDF export"
```

---

## Self-Review Notes

- **Spec coverage:** Access control (Task 8/10/11), GET missions / POST generate / POST pdf endpoints (Task 8), AI pluggable provider (Tasks 2–3), victim anonymization (Task 4), prompt (Task 6), PDF export (Task 7, 9, 11), selection UI 3 modes (Task 10), editable narrative + retry (Task 11), admin tile + routing (Task 10/11) — all spec sections have a corresponding task.
- **Type consistency:** `MissionReportData` (Task 5) is the single source of truth for the structured-data shape, consumed unchanged by Task 6 (prompt), Task 7 (PDF), and Task 8 (route response) — field names (`missions`, `personnel`, `vehicles`, `items`, `victims`, `totals`) are identical everywhere they're read on the frontend (Task 11) as raw JSON keys.
- **Out of scope carried over from spec:** no persistence, no second AI provider, no structured-data editing — none of the 11 tasks introduce any of these.
