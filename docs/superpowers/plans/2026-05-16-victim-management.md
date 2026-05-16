# Victim/Incident Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a victim/patient management module with 3 DB models, 10 REST endpoints, a ChangeNotifier provider, and 4 screens.

**Architecture:** Three new Prisma models (Victim, VitalSign, Treatment) with relations to User/Service/Item. A single Express route file at `/api/victims` follows the project's Zod + authenticate pattern. A `VictimProvider extends ChangeNotifier` on the frontend follows the project's provider conventions. Four new screens (list, create, detail) plus modifications to services screen (FAB), service detail (victims section), shell screen (nav rail), and router.

**Tech Stack:** Prisma, Express, Zod, Flutter, Provider, GoRouter

---

### Task 1: Add Prisma Schema Models and Relations

**Files:**
- Modify: `backend/prisma/schema.prisma`
- Create: (none yet — migration in Task 2)

- [ ] **Step 1: Add Victim, VitalSign, and Treatment models**

Open `backend/prisma/schema.prisma` and add these three models before the existing enum blocks (or at the end, before the enum blocks — order doesn't matter to Prisma). Add them after the last existing model.

```prisma
model Victim {
  id        Int    @id @default(autoincrement())

  name            String
  age             Int?
  dateOfBirth     DateTime? @map("date_of_birth")
  gender          String?
  address         String?   @db.Text
  city            String?   @db.VarChar(255)
  postalCode      String?   @map("postal_code") @db.VarChar(20)
  telephone       String?   @db.VarChar(30)
  emergencyContact String?  @map("emergency_contact") @db.VarChar(255)
  emergencyPhone  String?   @map("emergency_phone") @db.VarChar(30)

  chiefComplaint  String?   @map("chief_complaint") @db.Text
  allergies       String?   @db.Text
  medications     String?   @db.Text
  medicalHistory  String?   @map("medical_history") @db.Text

  gcsEye          Int?      @map("gcs_eye")
  gcsVerbal       Int?      @map("gcs_verbal")
  gcsMotor        Int?      @map("gcs_motor")
  gcsTotal        Int?      @map("gcs_total")

  avpu            String?

  latitude        Float?
  longitude       Float?
  locationNotes   String?   @map("location_notes") @db.Text

  serviceId       Int?      @map("service_id")

  notes           String?   @db.Text

  isFinalized     Boolean   @default(false) @map("is_finalized")
  finalizedAt     DateTime? @map("finalized_at")
  finalizedById   Int?      @map("finalized_by_id")

  createdById     Int       @map("created_by_id")
  createdAt       DateTime  @default(now()) @map("created_at")
  updatedAt       DateTime  @updatedAt @map("updated_at")

  createdBy       User       @relation("VictimCreatedBy", fields: [createdById], references: [id])
  finalizedBy     User?      @relation("VictimFinalizedBy", fields: [finalizedById], references: [id], onDelete: SetNull)
  service         Service?   @relation(fields: [serviceId], references: [id], onDelete: SetNull)
  vitalSigns      VitalSign[]
  treatments      Treatment[]

  @@index([createdById])
  @@index([serviceId])
  @@index([createdAt])
  @@map("victims")
}

model VitalSign {
  id              Int      @id @default(autoincrement())
  victimId        Int      @map("victim_id")

  systolicBP      Int?     @map("systolic_bp")
  diastolicBP     Int?     @map("diastolic_bp")
  heartRate       Int?     @map("heart_rate")
  respiratoryRate Int?     @map("respiratory_rate")
  oxygenSat       Int?     @map("oxygen_sat")
  temperature     Float?
  bloodGlucose    Float?   @map("blood_glucose")
  painScore       Int?     @map("pain_score")

  measuredAt      DateTime @default(now()) @map("measured_at")
  notes           String?  @db.Text
  measuredBy      String?  @map("measured_by") @db.VarChar(255)

  victim          Victim   @relation(fields: [victimId], references: [id], onDelete: Cascade)

  @@index([victimId])
  @@index([measuredAt])
  @@map("vital_signs")
}

model Treatment {
  id              Int      @id @default(autoincrement())
  victimId        Int      @map("victim_id")

  action          String   @db.Text
  materialUsed    String?  @map("material_used") @db.Text
  notes           String?  @db.Text

  itemId          Int?     @map("item_id")
  consumedNote    String?  @map("consumed_note") @db.Text

  performedAt     DateTime @default(now()) @map("performed_at")
  performedBy     String?  @map("performed_by") @db.VarChar(255)

  victim          Victim   @relation(fields: [victimId], references: [id], onDelete: Cascade)
  item            Item?    @relation(fields: [itemId], references: [id], onDelete: SetNull)

  @@index([victimId])
  @@index([performedAt])
  @@map("treatments")
}
```

- [ ] **Step 2: Add reverse relations to existing models**

Find the `User` model and add these two relation fields alongside the existing relation fields (e.g., after `chats Chat[]` or similar):

```prisma
createdVictims   Victim[]       @relation("VictimCreatedBy")
finalizedVictims Victim[]       @relation("VictimFinalizedBy")
```

Find the `Service` model and add alongside existing relation fields:

```prisma
victims          Victim[]
```

Find the `Item` model and add alongside existing relation fields:

```prisma
treatments       Treatment[]
```

- [ ] **Step 3: Verify schema parses**

Run: `npx prisma validate`
Expected: "The Prisma schema is valid."

- [ ] **Step 4: Commit**

```bash
git add backend/prisma/schema.prisma
git commit -m "feat: add Victim, VitalSign, Treatment models to schema"
```

---

### Task 2: Run Database Migration

**Files:**
- Create: `backend/prisma/migrations/*/migration.sql` (auto-generated)

- [ ] **Step 1: Ensure dev database is running**

```bash
docker compose -f docker-compose.dev.yml up -d
```

- [ ] **Step 2: Run migration**

```bash
cd backend && npm run prisma:migrate -- --name add_victim_models
```

If prompted for a migration name, use `add_victim_models`.

Expected: Migration created and applied. Should show "Applying migration..." without errors.

- [ ] **Step 3: Generate Prisma client**

```bash
cd backend && npm run prisma:generate
```

Expected: Client generated successfully. No errors.

- [ ] **Step 4: Verify tables exist**

```bash
cd backend && npx prisma db execute --stdin <<< "SELECT table_name FROM information_schema.tables WHERE table_name IN ('victims', 'vital_signs', 'treatments');"
```

Expected: Should list `victims`, `vital_signs`, `treatments`.

- [ ] **Step 5: Commit**

```bash
git add backend/prisma/migrations backend/prisma/schema.prisma
git commit -m "feat: run migration for victim management tables"
```

---

### Task 3: Create Victim Routes — Core CRUD

**Files:**
- Create: `backend/src/routes/victim.routes.ts`

- [ ] **Step 1: Create the route file with imports, schemas, and access helpers**

```typescript
import { Router, Request, Response } from "express";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate, isMissionAdminInDepartment } from "../middleware/auth";

const router = Router();
router.use(authenticate);

// ── Zod schemas ──────────────────────────────────

const createSchema = z.object({
  name: z.string().min(1).max(255),
  age: z.number().int().min(0).max(150).optional().nullable(),
  dateOfBirth: z.string().datetime().optional().nullable(),
  gender: z.enum(["male", "female", "other", "unknown"]).optional().nullable(),
  address: z.string().optional().nullable(),
  city: z.string().max(255).optional().nullable(),
  postalCode: z.string().max(20).optional().nullable(),
  telephone: z.string().max(30).optional().nullable(),
  emergencyContact: z.string().max(255).optional().nullable(),
  emergencyPhone: z.string().max(30).optional().nullable(),
  chiefComplaint: z.string().optional().nullable(),
  allergies: z.string().optional().nullable(),
  medications: z.string().optional().nullable(),
  medicalHistory: z.string().optional().nullable(),
  gcsEye: z.number().int().min(1).max(4).optional().nullable(),
  gcsVerbal: z.number().int().min(1).max(5).optional().nullable(),
  gcsMotor: z.number().int().min(1).max(6).optional().nullable(),
  gcsTotal: z.number().int().min(3).max(15).optional().nullable(),
  avpu: z.enum(["ALERT", "VOICE", "PAIN", "UNRESPONSIVE"]).optional().nullable(),
  latitude: z.number().optional().nullable(),
  longitude: z.number().optional().nullable(),
  locationNotes: z.string().optional().nullable(),
  serviceId: z.number().int().optional().nullable(),
  notes: z.string().optional().nullable(),
});

const vitalSignSchema = z.object({
  systolicBP: z.number().int().min(0).optional().nullable(),
  diastolicBP: z.number().int().min(0).optional().nullable(),
  heartRate: z.number().int().min(0).optional().nullable(),
  respiratoryRate: z.number().int().min(0).optional().nullable(),
  oxygenSat: z.number().int().min(0).max(100).optional().nullable(),
  temperature: z.number().optional().nullable(),
  bloodGlucose: z.number().optional().nullable(),
  painScore: z.number().int().min(0).max(10).optional().nullable(),
  measuredAt: z.string().datetime().optional(),
  notes: z.string().optional().nullable(),
  measuredBy: z.string().max(255).optional().nullable(),
});

const treatmentSchema = z.object({
  action: z.string().min(1),
  materialUsed: z.string().optional().nullable(),
  notes: z.string().optional().nullable(),
  itemId: z.number().int().optional().nullable(),
  consumedNote: z.string().optional().nullable(),
  performedAt: z.string().datetime().optional(),
  performedBy: z.string().max(255).optional().nullable(),
});

// ── Access helpers ───────────────────────────────

async function canReadVictim(
  victimId: number,
  userId: number,
  isAdmin: boolean,
): Promise<boolean> {
  if (isAdmin) return true;

  const victim = await prisma.victim.findUnique({
    where: { id: victimId },
    select: { createdById: true, serviceId: true },
  });
  if (!victim) return false;

  // Creator
  if (victim.createdById === userId) return true;

  // Mission admin in service's department
  if (victim.serviceId) {
    const service = await prisma.service.findUnique({
      where: { id: victim.serviceId },
      select: { departmentId: true },
    });
    if (service) {
      const isMissionAdmin = await isMissionAdminInDepartment(
        userId,
        service.departmentId,
      );
      if (isMissionAdmin) return true;

      // Accepted member of the service
      const enrollment = await prisma.userService.findUnique({
        where: {
          userId_serviceId: { userId, serviceId: victim.serviceId },
        },
      });
      if (enrollment && enrollment.status === "accepted") return true;
    }
  }

  return false;
}

async function canWriteVictim(
  victimId: number,
  userId: number,
  isAdmin: boolean,
): Promise<{ allowed: boolean; isFinalized: boolean; departmentId: number | null }> {
  const victim = await prisma.victim.findUnique({
    where: { id: victimId },
    select: { createdById: true, isFinalized: true, serviceId: true },
  });
  if (!victim) return { allowed: false, isFinalized: false, departmentId: null };

  if (isAdmin) return { allowed: true, isFinalized: victim.isFinalized, departmentId: null };

  // Non-admin, finalized — blocked
  if (victim.isFinalized) {
    // Check missionAdmin in service's department
    if (victim.serviceId) {
      const service = await prisma.service.findUnique({
        where: { id: victim.serviceId },
        select: { departmentId: true },
      });
      if (service && await isMissionAdminInDepartment(userId, service.departmentId)) {
        return { allowed: true, isFinalized: true, departmentId: service.departmentId };
      }
    }
    return { allowed: false, isFinalized: true, departmentId: null };
  }

  // Not finalized: creator or missionAdmin can write
  if (victim.createdById === userId) return { allowed: true, isFinalized: false, departmentId: null };

  if (victim.serviceId) {
    const service = await prisma.service.findUnique({
      where: { id: victim.serviceId },
      select: { departmentId: true },
    });
    if (service && await isMissionAdminInDepartment(userId, service.departmentId)) {
      return { allowed: true, isFinalized: false, departmentId: service.departmentId };
    }
  }

  return { allowed: false, isFinalized: false, departmentId: null };
}

// ── GET /api/victims ─────────────────────────────

router.get("/", async (req: Request, res: Response) => {
  const { serviceId } = req.query;
  const userId = req.user!.userId;
  const isAdmin = req.user!.isAdmin;

  try {
    const where: any = {};

    if (serviceId) {
      where.serviceId = Number(serviceId);
    }

    if (!isAdmin) {
      // Build a list of accessible victim IDs
      const missionAdminDeptIds: number[] = [];
      const userDeptIds = await prisma.userDepartment.findMany({
        where: { userId, role: "missionAdmin" },
        select: { departmentId: true },
      });
      missionAdminDeptIds.push(...userDeptIds.map((d) => d.departmentId));

      where.OR = [
        { createdById: userId },
        // Victims in services where user is missionAdmin of the department
        ...(missionAdminDeptIds.length > 0
          ? [
              {
                service: {
                  departmentId: { in: missionAdminDeptIds },
                },
              },
            ]
          : []),
        // Victims in services where user is an accepted member
        {
          service: {
            userServices: {
              some: { userId, status: "accepted" },
            },
          },
        },
      ];
    }

    const victims = await prisma.victim.findMany({
      where,
      orderBy: { createdAt: "desc" },
      select: {
        id: true,
        name: true,
        age: true,
        gender: true,
        isFinalized: true,
        createdAt: true,
        service: { select: { id: true, name: true } },
        createdBy: { select: { id: true, forename: true, surname: true } },
      },
    });

    res.json(victims);
  } catch (err) {
    res.status(500).json({ error: "Αποτυχία ανάκτησης περιστατικών" });
  }
});

// ── GET /api/victims/:id ─────────────────────────

router.get("/:id", async (req: Request, res: Response) => {
  const id = Number(req.params.id);
  if (isNaN(id)) { res.status(400).json({ error: "Άκυρο ID" }); return; }

  const allowed = await canReadVictim(id, req.user!.userId, req.user!.isAdmin);
  if (!allowed) { res.status(404).json({ error: "Δεν βρέθηκε" }); return; }

  try {
    const victim = await prisma.victim.findUnique({
      where: { id },
      include: {
        createdBy: { select: { id: true, forename: true, surname: true } },
        finalizedBy: { select: { id: true, forename: true, surname: true } },
        service: { select: { id: true, name: true } },
        vitalSigns: { orderBy: { measuredAt: "desc" } },
        treatments: {
          orderBy: { performedAt: "desc" },
          include: { item: { select: { id: true, name: true } } },
        },
      },
    });
    if (!victim) { res.status(404).json({ error: "Δεν βρέθηκε" }); return; }
    res.json(victim);
  } catch (err) {
    res.status(500).json({ error: "Αποτυχία ανάκτησης περιστατικού" });
  }
});

// ── POST /api/victims ────────────────────────────

router.post("/", async (req: Request, res: Response) => {
  try {
    const data = createSchema.parse(req.body);

    // Compute gcsTotal if not provided but components are
    let gcsTotal = data.gcsTotal;
    if (gcsTotal == null && data.gcsEye != null && data.gcsVerbal != null && data.gcsMotor != null) {
      gcsTotal = data.gcsEye + data.gcsVerbal + data.gcsMotor;
    }

    // Convert ISO date strings to Date objects
    const dateOfBirth = data.dateOfBirth ? new Date(data.dateOfBirth) : undefined;

    const victim = await prisma.victim.create({
      data: {
        ...data,
        dateOfBirth,
        gcsTotal,
        createdById: req.user!.userId,
      },
      select: { id: true },
    });

    res.status(201).json(victim);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Μη έγκυρα δεδομένα", details: err.errors });
      return;
    }
    res.status(500).json({ error: "Αποτυχία δημιουργίας περιστατικού" });
  }
});

// ── PATCH /api/victims/:id ────────────────────────

router.patch("/:id", async (req: Request, res: Response) => {
  const id = Number(req.params.id);
  if (isNaN(id)) { res.status(400).json({ error: "Άκυρο ID" }); return; }

  const access = await canWriteVictim(id, req.user!.userId, req.user!.isAdmin);
  if (!access.allowed) {
    res.status(access.isFinalized ? 403 : 404).json({
      error: access.isFinalized ? "Το περιστατικό έχει οριστικοποιηθεί" : "Δεν βρέθηκε",
    });
    return;
  }

  try {
    const data = createSchema.partial().parse(req.body);

    // Recompute gcsTotal if any GCS component changed
    const existing = data.gcsEye !== undefined || data.gcsVerbal !== undefined || data.gcsMotor !== undefined
      ? await prisma.victim.findUnique({ where: { id }, select: { gcsEye: true, gcsVerbal: true, gcsMotor: true } })
      : null;

    let gcsTotal = data.gcsTotal;
    if (gcsTotal === undefined && existing) {
      const eye = data.gcsEye ?? existing.gcsEye;
      const verbal = data.gcsVerbal ?? existing.gcsVerbal;
      const motor = data.gcsMotor ?? existing.gcsMotor;
      if (eye != null && verbal != null && motor != null) {
        gcsTotal = eye + verbal + motor;
      }
    }

    const dateOfBirth = data.dateOfBirth ? new Date(data.dateOfBirth) : undefined;

    const victim = await prisma.victim.update({
      where: { id },
      data: { ...data, dateOfBirth, gcsTotal },
    });

    res.json(victim);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Μη έγκυρα δεδομένα", details: err.errors });
      return;
    }
    if (err?.code === "P2025") {
      res.status(404).json({ error: "Δεν βρέθηκε" });
      return;
    }
    res.status(500).json({ error: "Αποτυχία ενημέρωσης περιστατικού" });
  }
});

// ── DELETE /api/victims/:id ───────────────────────

router.delete("/:id", async (req: Request, res: Response) => {
  const id = Number(req.params.id);
  if (isNaN(id)) { res.status(400).json({ error: "Άκυρο ID" }); return; }

  const access = await canWriteVictim(id, req.user!.userId, req.user!.isAdmin);
  if (!access.allowed) {
    res.status(access.isFinalized ? 403 : 404).json({
      error: access.isFinalized ? "Το περιστατικό έχει οριστικοποιηθεί" : "Δεν βρέθηκε",
    });
    return;
  }

  try {
    await prisma.victim.delete({ where: { id } });
    res.status(204).send();
  } catch (err: any) {
    if (err?.code === "P2025") {
      res.status(404).json({ error: "Δεν βρέθηκε" });
      return;
    }
    res.status(500).json({ error: "Αποτυχία διαγραφής περιστατικού" });
  }
});

export default router;
```

- [ ] **Step 2: Verify the file compiles**

```bash
cd backend && npx tsc --noEmit src/routes/victim.routes.ts
```

Expected: No type errors.

- [ ] **Step 3: Commit**

```bash
git add backend/src/routes/victim.routes.ts
git commit -m "feat: add victim routes — core CRUD endpoints"
```

---

### Task 4: Add Sub-Routes — Finalize, Vital Signs, Treatments

**Files:**
- Modify: `backend/src/routes/victim.routes.ts`

- [ ] **Step 1: Append finalize, vital-sign, and treatment routes**

Append the following code to `backend/src/routes/victim.routes.ts`, before the `export default router;` line:

```typescript
// ── POST /api/victims/:id/finalize ───────────────

router.post("/:id/finalize", async (req: Request, res: Response) => {
  const id = Number(req.params.id);
  if (isNaN(id)) { res.status(400).json({ error: "Άκυρο ID" }); return; }

  const userId = req.user!.userId;
  const isAdmin = req.user!.isAdmin;

  const victim = await prisma.victim.findUnique({
    where: { id },
    select: { createdById: true, isFinalized: true, serviceId: true },
  });
  if (!victim) { res.status(404).json({ error: "Δεν βρέθηκε" }); return; }

  if (victim.isFinalized) {
    res.status(400).json({ error: "Το περιστατικό έχει ήδη οριστικοποιηθεί" });
    return;
  }

  // Check permission: creator, admin, or missionAdmin
  let allowed = isAdmin || victim.createdById === userId;
  if (!allowed && victim.serviceId) {
    const service = await prisma.service.findUnique({
      where: { id: victim.serviceId },
      select: { departmentId: true },
    });
    if (service) {
      allowed = await isMissionAdminInDepartment(userId, service.departmentId);
    }
  }

  if (!allowed) { res.status(403).json({ error: "Δεν έχετε δικαίωμα" }); return; }

  try {
    const updated = await prisma.victim.update({
      where: { id },
      data: {
        isFinalized: true,
        finalizedAt: new Date(),
        finalizedById: userId,
      },
    });
    res.json(updated);
  } catch (err: any) {
    if (err?.code === "P2025") { res.status(404).json({ error: "Δεν βρέθηκε" }); return; }
    res.status(500).json({ error: "Αποτυχία οριστικοποίησης" });
  }
});

// ── POST /api/victims/:id/vital-signs ─────────────

router.post("/:id/vital-signs", async (req: Request, res: Response) => {
  const victimId = Number(req.params.id);
  if (isNaN(victimId)) { res.status(400).json({ error: "Άκυρο ID" }); return; }

  const access = await canWriteVictim(victimId, req.user!.userId, req.user!.isAdmin);
  if (!access.allowed) {
    res.status(access.isFinalized ? 403 : 404).json({
      error: access.isFinalized ? "Το περιστατικό έχει οριστικοποιηθεί" : "Δεν βρέθηκε",
    });
    return;
  }

  try {
    const data = vitalSignSchema.parse(req.body);
    const measuredAt = data.measuredAt ? new Date(data.measuredAt) : undefined;

    const vs = await prisma.vitalSign.create({
      data: { ...data, measuredAt, victimId },
    });
    res.status(201).json(vs);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Μη έγκυρα δεδομένα", details: err.errors });
      return;
    }
    res.status(500).json({ error: "Αποτυχία καταγραφής ζωτικών σημείων" });
  }
});

// ── DELETE /api/victims/:id/vital-signs/:vsId ──────

router.delete("/:id/vital-signs/:vsId", async (req: Request, res: Response) => {
  const victimId = Number(req.params.id);
  const vsId = Number(req.params.vsId);
  if (isNaN(victimId) || isNaN(vsId)) { res.status(400).json({ error: "Άκυρο ID" }); return; }

  const access = await canWriteVictim(victimId, req.user!.userId, req.user!.isAdmin);
  if (!access.allowed) {
    res.status(access.isFinalized ? 403 : 404).json({
      error: access.isFinalized ? "Το περιστατικό έχει οριστικοποιηθεί" : "Δεν βρέθηκε",
    });
    return;
  }

  try {
    await prisma.vitalSign.delete({ where: { id: vsId, victimId } });
    res.status(204).send();
  } catch (err: any) {
    if (err?.code === "P2025") { res.status(404).json({ error: "Δεν βρέθηκε" }); return; }
    res.status(500).json({ error: "Αποτυχία διαγραφής" });
  }
});

// ── POST /api/victims/:id/treatments ──────────────

router.post("/:id/treatments", async (req: Request, res: Response) => {
  const victimId = Number(req.params.id);
  if (isNaN(victimId)) { res.status(400).json({ error: "Άκυρο ID" }); return; }

  const access = await canWriteVictim(victimId, req.user!.userId, req.user!.isAdmin);
  if (!access.allowed) {
    res.status(access.isFinalized ? 403 : 404).json({
      error: access.isFinalized ? "Το περιστατικό έχει οριστικοποιηθεί" : "Δεν βρέθηκε",
    });
    return;
  }

  try {
    const data = treatmentSchema.parse(req.body);
    const performedAt = data.performedAt ? new Date(data.performedAt) : undefined;

    const treatment = await prisma.treatment.create({
      data: { ...data, performedAt, victimId },
      include: { item: { select: { id: true, name: true } } },
    });
    res.status(201).json(treatment);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Μη έγκυρα δεδομένα", details: err.errors });
      return;
    }
    res.status(500).json({ error: "Αποτυχία καταγραφής θεραπείας" });
  }
});

// ── DELETE /api/victims/:id/treatments/:tId ────────

router.delete("/:id/treatments/:tId", async (req: Request, res: Response) => {
  const victimId = Number(req.params.id);
  const tId = Number(req.params.tId);
  if (isNaN(victimId) || isNaN(tId)) { res.status(400).json({ error: "Άκυρο ID" }); return; }

  const access = await canWriteVictim(victimId, req.user!.userId, req.user!.isAdmin);
  if (!access.allowed) {
    res.status(access.isFinalized ? 403 : 404).json({
      error: access.isFinalized ? "Το περιστατικό έχει οριστικοποιηθεί" : "Δεν βρέθηκε",
    });
    return;
  }

  try {
    await prisma.treatment.delete({ where: { id: tId, victimId } });
    res.status(204).send();
  } catch (err: any) {
    if (err?.code === "P2025") { res.status(404).json({ error: "Δεν βρέθηκε" }); return; }
    res.status(500).json({ error: "Αποτυχία διαγραφής" });
  }
});
```

- [ ] **Step 2: Verify compilation**

```bash
cd backend && npx tsc --noEmit
```

Expected: No new type errors (may have pre-existing ones in other files, but none from victim.routes.ts).

- [ ] **Step 3: Commit**

```bash
git add backend/src/routes/victim.routes.ts
git commit -m "feat: add victim sub-routes — finalize, vital signs, treatments"
```

---

### Task 5: Register Victim Routes in app.ts

**Files:**
- Modify: `backend/src/app.ts`

- [ ] **Step 1: Add import and route registration**

In `backend/src/app.ts`, add the import alongside the other route imports:

```typescript
import victimRoutes from "./routes/victim.routes";
```

Add the route registration alongside the other `app.use` lines (e.g., after the services route line):

```typescript
app.use("/api/victims", victimRoutes);
```

- [ ] **Step 2: Verify compilation**

```bash
cd backend && npx tsc --noEmit
```

Expected: No new errors.

- [ ] **Step 3: Start backend and smoke-test**

Start the backend in a separate terminal:

```bash
cd backend && npm run dev
```

Test the GET endpoint works (returns empty array or 401 without token):

```bash
curl -s http://localhost:4000/api/victims
```

Expected: 401 or 200 with JSON array.

- [ ] **Step 4: Commit**

```bash
git add backend/src/app.ts
git commit -m "feat: register victim routes at /api/victims"
```

---

### Task 6: Create VictimProvider

**Files:**
- Create: `frontend/lib/providers/victim_provider.dart`

- [ ] **Step 1: Create the provider file**

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/api_client.dart';

class VictimProvider extends ChangeNotifier {
  final _api = ApiClient();

  List<Map<String, dynamic>> _victims = [];
  Map<String, dynamic>? _selected;
  bool _loading = false;

  List<Map<String, dynamic>> get victims => _victims;
  Map<String, dynamic>? get selected => _selected;
  bool get loading => _loading;

  Future<void> fetchVictims({int? serviceId}) async {
    _loading = true;
    notifyListeners();
    try {
      final q = serviceId != null ? '?serviceId=$serviceId' : '';
      final res = await _api.get('/victims$q');
      if (res.statusCode == 200) {
        _victims = (jsonDecode(res.body) as List)
            .map((e) => e as Map<String, dynamic>)
            .toList();
      } else {
        debugPrint('fetchVictims failed: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('fetchVictims error: $e');
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> fetchVictim(int id) async {
    _loading = true;
    notifyListeners();
    try {
      final res = await _api.get('/victims/$id');
      if (res.statusCode == 200) {
        _selected = jsonDecode(res.body);
      }
    } catch (e) {
      debugPrint('fetchVictim error: $e');
    }
    _loading = false;
    notifyListeners();
  }

  Future<String?> createVictim(Map<String, dynamic> data) async {
    try {
      final res = await _api.post('/victims', body: data);
      if (res.statusCode == 201) {
        final created = jsonDecode(res.body);
        await fetchVictims();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> updateVictim(int id, Map<String, dynamic> data) async {
    try {
      final res = await _api.patch('/victims/$id', body: data);
      if (res.statusCode == 200) {
        await fetchVictims();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> deleteVictim(int id) async {
    try {
      final res = await _api.delete('/victims/$id');
      if (res.statusCode == 204) {
        await fetchVictims();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> finalizeVictim(int id) async {
    try {
      final res = await _api.post('/victims/$id/finalize');
      if (res.statusCode == 200) {
        await fetchVictim(id);
        await fetchVictims();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> addVitalSign(int victimId, Map<String, dynamic> data) async {
    try {
      final res = await _api.post('/victims/$victimId/vital-signs', body: data);
      if (res.statusCode == 201) {
        await fetchVictim(victimId);
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> deleteVitalSign(int victimId, int vsId) async {
    try {
      final res = await _api.delete('/victims/$victimId/vital-signs/$vsId');
      if (res.statusCode == 204) {
        await fetchVictim(victimId);
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> addTreatment(int victimId, Map<String, dynamic> data) async {
    try {
      final res = await _api.post('/victims/$victimId/treatments', body: data);
      if (res.statusCode == 201) {
        await fetchVictim(victimId);
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> deleteTreatment(int victimId, int tId) async {
    try {
      final res = await _api.delete('/victims/$victimId/treatments/$tId');
      if (res.statusCode == 204) {
        await fetchVictim(victimId);
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/providers/victim_provider.dart
git commit -m "feat: add VictimProvider with full API surface"
```

---

### Task 7: Register VictimProvider in main.dart

**Files:**
- Modify: `frontend/lib/main.dart`

- [ ] **Step 1: Add import**

In `frontend/lib/main.dart`, add alongside the other provider imports:

```dart
import 'providers/victim_provider.dart';
```

- [ ] **Step 2: Register provider**

In the `providers:` list of `MultiProvider`, add after the ChatProvider line:

```dart
ChangeNotifierProvider(create: (_) => VictimProvider()),
```

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/main.dart
git commit -m "feat: register VictimProvider in main.dart"
```

---

### Task 8: Add Victim Routes to Router

**Files:**
- Modify: `frontend/lib/config/router.dart`

- [ ] **Step 1: Add screen imports**

Add these imports alongside the existing screen imports in `frontend/lib/config/router.dart`:

```dart
import '../screens/victims_screen.dart';
import '../screens/create_victim_screen.dart';
import '../screens/victim_detail_screen.dart';
```

- [ ] **Step 2: Add routes inside the ShellRoute**

Inside the `ShellRoute`'s `routes:` list, add these three GoRoute entries. Add them after the `/services/:id` route and before the `/items` route:

```dart
GoRoute(
  path: '/victims',
  builder: (context, state) => const VictimsScreen(),
),
GoRoute(
  path: '/victims/create',
  builder: (context, state) {
    final serviceId = int.tryParse(state.uri.queryParameters['serviceId'] ?? '');
    return CreateVictimScreen(prefilledServiceId: serviceId);
  },
),
GoRoute(
  path: '/victims/:id',
  builder: (context, state) {
    final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
    return VictimDetailScreen(victimId: id);
  },
),
```

- [ ] **Step 3: Add `/victims` to public path list (non-public = requires auth)**

Since victims require authentication (just like services/items), no change needed — the default redirect logic already redirects unauthenticated users to `/login`.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/config/router.dart
git commit -m "feat: add victim routes to GoRouter"
```

---

### Task 9: Update ShellScreen Nav Rail

**Files:**
- Modify: `frontend/lib/screens/shell_screen.dart`

The nav rail currently has: Services, Items, Vehicles, Chat (and admin section). We insert "Περιστατικά" between Services and Items.

- [ ] **Step 1: Update mainPaths list**

Change the `mainPaths` list (around line 21):

```dart
final mainPaths = ['/services', '/victims', '/items', '/vehicles', if (showAdmin) '/admin', '/chat'];
```

This shifts indexes: Services=0, Victims=1, Items=2, Vehicles=3, Admin=4 (conditional), Chat=5 (or 4 when no admin).

- [ ] **Step 2: Update mobile NavigationBar destinations**

In the mobile `NavigationBar`'s `destinations:` list, insert the victims destination after Services and before Items:

```dart
const NavigationDestination(
  icon: Icon(Icons.personal_injury_outlined),
  selectedIcon: Icon(Icons.personal_injury),
  label: 'Περιστατικά',
),
```

Place it between the Services destination and the Items destination.

- [ ] **Step 3: Update desktop sidebar nav items**

In the `_DesktopSidebar.build()` method's `ListView` children, insert a new `_BrandSidebarItem` for victims after the Services item and before the Items item:

```dart
_BrandSidebarItem(
  icon: Icons.personal_injury_outlined,
  selectedIcon: Icons.personal_injury,
  label: 'Περιστατικά',
  selected: selectedIndex == 1,
  onTap: () => context.go('/victims'),
),
```

- [ ] **Step 4: Update selectedIndex logic for shifted indices**

Since inserting a nav item shifts all subsequent indices, the `selectedIndex` computation at line 25 (`mainPaths.indexWhere(...)`) will automatically handle the new ordering. No manual index updates needed — `indexWhere` finds the correct index dynamically.

- [ ] **Step 5: Run frontend to verify nav rail**

```bash
cd frontend && flutter run -d chrome
```

Navigate between nav items to confirm:
- "Περιστατικά" appears between Services and Items on both desktop sidebar and mobile bottom nav
- The correct destination is selected when navigating
- Chat and Admin still work correctly

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/screens/shell_screen.dart
git commit -m "feat: add Περιστατικά nav destination between Services and Items"
```

---

### Task 10: Create Victims List Screen

**Files:**
- Create: `frontend/lib/screens/victims_screen.dart`

- [ ] **Step 1: Create the screen file**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/victim_provider.dart';

class VictimsScreen extends StatefulWidget {
  const VictimsScreen({super.key});

  @override
  State<VictimsScreen> createState() => _VictimsScreenState();
}

class _VictimsScreenState extends State<VictimsScreen> {
  String _filter = 'all'; // 'all' | 'open' | 'finalized'

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<VictimProvider>().fetchVictims());
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VictimProvider>();
    final victims = provider.victims;

    final filtered = _filter == 'all'
        ? victims
        : _filter == 'open'
            ? victims.where((v) => v['isFinalized'] != true).toList()
            : victims.where((v) => v['isFinalized'] == true).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Περιστατικά'),
        scrolledUnderElevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/victims/create'),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => provider.fetchVictims(),
        child: Column(
          children: [
            _FilterRow(selected: _filter, onChanged: (v) => setState(() => _filter = v)),
            Expanded(
              child: provider.loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                            _filter == 'all'
                                ? 'Δεν υπάρχουν περιστατικά'
                                : _filter == 'open'
                                    ? 'Δεν υπάρχουν ανοιχτά περιστατικά'
                                    : 'Δεν υπάρχουν οριστικοποιημένα περιστατικά',
                            style: GoogleFonts.inter(color: const Color(0xFF6B7280), fontSize: 15),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final v = filtered[index];
                            return _VictimCard(victim: v);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _FilterRow({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _FilterChip(label: 'Όλα', value: 'all', selected: selected, onChanged: onChanged),
          const SizedBox(width: 8),
          _FilterChip(label: 'Ανοιχτά', value: 'open', selected: selected, onChanged: onChanged),
          const SizedBox(width: 8),
          _FilterChip(label: 'Οριστικοποιημένα', value: 'finalized', selected: selected, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onChanged;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final active = selected == value;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (_) => onChanged(value),
      selectedColor: const Color(0xFFC62828),
      labelStyle: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: active ? Colors.white : const Color(0xFF1A1C1E),
      ),
    );
  }
}

class _VictimCard extends StatelessWidget {
  final Map<String, dynamic> victim;

  const _VictimCard({required this.victim});

  @override
  Widget build(BuildContext context) {
    final name = victim['name'] ?? 'Άγνωστο';
    final age = victim['age'];
    final isFinalized = victim['isFinalized'] == true;
    final createdAt = victim['createdAt'] as String?;
    final serviceName = (victim['service'] as Map?)?.let((s) => s['name']) ?? '—';
    final id = victim['id'] as int;

    String dateStr = '';
    if (createdAt != null) {
      final dt = DateTime.tryParse(createdAt)?.toLocal();
      if (dt != null) {
        dateStr = '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/victims/$id'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name,
                            style: GoogleFonts.literata(fontSize: 15, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isFinalized)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(Icons.lock, size: 14, color: const Color(0xFF6B7280)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [if (age != null) '$age ετών', serviceName].where((s) => s.isNotEmpty).join(' · '),
                      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
              Text(dateStr, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF9CA3AF))),
            ],
          ),
        ),
      ),
    );
  }
}

extension _MapLet on Map? {
  R? let<R>(R Function(Map m) fn) {
    final self = this;
    if (self == null) return null;
    return fn(self);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/screens/victims_screen.dart
git commit -m "feat: add victims list screen with filter chips"
```

---

### Task 11: Create Victim Form Screen (Multi-Step)

**Files:**
- Create: `frontend/lib/screens/create_victim_screen.dart`

This is the largest single file. It uses a `Stepper` widget with 4 steps.

- [ ] **Step 1: Create the form screen**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/victim_provider.dart';
import '../services/api_client.dart';
import 'dart:convert';

class CreateVictimScreen extends StatefulWidget {
  final int? prefilledServiceId;

  const CreateVictimScreen({super.key, this.prefilledServiceId});

  @override
  State<CreateVictimScreen> createState() => _CreateVictimScreenState();
}

class _CreateVictimScreenState extends State<CreateVictimScreen> {
  int _currentStep = 0;
  final _api = ApiClient();

  // Step 0: Στοιχεία
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  DateTime? _dateOfBirth;
  String? _gender;
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _postalCodeCtrl = TextEditingController();
  final _telephoneCtrl = TextEditingController();
  final _emergencyContactCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();

  // Step 1: Ιατρικό ιστορικό
  final _chiefComplaintCtrl = TextEditingController();
  final _allergiesCtrl = TextEditingController();
  final _medicationsCtrl = TextEditingController();
  final _medicalHistoryCtrl = TextEditingController();

  // Step 2: Αξιολόγηση
  double _gcsEye = 4;
  double _gcsVerbal = 5;
  double _gcsMotor = 6;
  String? _avpu;
  final _locationNotesCtrl = TextEditingController();
  int? _serviceId;
  List<Map<String, dynamic>> _acceptedServices = [];
  bool _servicesLoaded = false;

  // Step 3: Notes
  final _notesCtrl = TextEditingController();

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _serviceId = widget.prefilledServiceId;
    _loadAcceptedServices();
  }

  Future<void> _loadAcceptedServices() async {
    try {
      final res = await _api.get('/services/my');
      if (res.statusCode == 200) {
        final all = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
        setState(() {
          _acceptedServices = all.where((s) {
            final userServices = s['userServices'];
            if (userServices is List) {
              return userServices.any((us) => us['status'] == 'accepted');
            }
            return false;
          }).toList();
          _servicesLoaded = true;
        });
      }
    } catch (_) {
      setState(() => _servicesLoaded = true);
    }
  }

  int get _gcsTotal => _gcsEye.round() + _gcsVerbal.round() + _gcsMotor.round();

  Map<String, dynamic> _buildPayload() {
    return {
      'name': _nameCtrl.text.trim(),
      if (_ageCtrl.text.isNotEmpty) 'age': int.tryParse(_ageCtrl.text),
      if (_dateOfBirth != null) 'dateOfBirth': _dateOfBirth!.toIso8601String(),
      if (_gender != null) 'gender': _gender,
      if (_addressCtrl.text.isNotEmpty) 'address': _addressCtrl.text.trim(),
      if (_cityCtrl.text.isNotEmpty) 'city': _cityCtrl.text.trim(),
      if (_postalCodeCtrl.text.isNotEmpty) 'postalCode': _postalCodeCtrl.text.trim(),
      if (_telephoneCtrl.text.isNotEmpty) 'telephone': _telephoneCtrl.text.trim(),
      if (_emergencyContactCtrl.text.isNotEmpty) 'emergencyContact': _emergencyContactCtrl.text.trim(),
      if (_emergencyPhoneCtrl.text.isNotEmpty) 'emergencyPhone': _emergencyPhoneCtrl.text.trim(),
      if (_chiefComplaintCtrl.text.isNotEmpty) 'chiefComplaint': _chiefComplaintCtrl.text.trim(),
      if (_allergiesCtrl.text.isNotEmpty) 'allergies': _allergiesCtrl.text.trim(),
      if (_medicationsCtrl.text.isNotEmpty) 'medications': _medicationsCtrl.text.trim(),
      if (_medicalHistoryCtrl.text.isNotEmpty) 'medicalHistory': _medicalHistoryCtrl.text.trim(),
      'gcsEye': _gcsEye.round(),
      'gcsVerbal': _gcsVerbal.round(),
      'gcsMotor': _gcsMotor.round(),
      'gcsTotal': _gcsTotal,
      if (_avpu != null) 'avpu': _avpu,
      if (_locationNotesCtrl.text.isNotEmpty) 'locationNotes': _locationNotesCtrl.text.trim(),
      if (_serviceId != null) 'serviceId': _serviceId,
      if (_notesCtrl.text.isNotEmpty) 'notes': _notesCtrl.text.trim(),
    };
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Το όνομα είναι υποχρεωτικό'),
          backgroundColor: Color(0xFFB91C1C),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    final err = await context.read<VictimProvider>().createVictim(_buildPayload());
    setState(() => _submitting = false);

    if (!mounted) return;

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: const Color(0xFFB91C1C)),
      );
    } else {
      context.go('/victims');
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _postalCodeCtrl.dispose();
    _telephoneCtrl.dispose();
    _emergencyContactCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    _chiefComplaintCtrl.dispose();
    _allergiesCtrl.dispose();
    _medicationsCtrl.dispose();
    _medicalHistoryCtrl.dispose();
    _locationNotesCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefilled = widget.prefilledServiceId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Νέο Περιστατικό')),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep < 3) {
            setState(() => _currentStep += 1);
          } else {
            _submit();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) setState(() => _currentStep -= 1);
        },
        onStepTapped: (step) => setState(() => _currentStep = step),
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                if (_currentStep > 0)
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: const Text('Προηγούμενο'),
                  ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _submitting ? null : details.onStepContinue,
                  child: Text(_currentStep == 3 ? 'Υποβολή' : 'Επόμενο'),
                ),
              ],
            ),
          );
        },
        steps: [
          // ── Step 0: Στοιχεία ──
          Step(
            title: const Text('Στοιχεία'),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            content: Column(
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Ονοματεπώνυμο *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ageCtrl,
                  decoration: const InputDecoration(labelText: 'Ηλικία'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime(1990),
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _dateOfBirth = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Ημερομηνία γέννησης'),
                    child: Text(
                      _dateOfBirth != null
                          ? '${_dateOfBirth!.day}/${_dateOfBirth!.month}/${_dateOfBirth!.year}'
                          : 'Επιλέξτε...',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _gender,
                  decoration: const InputDecoration(labelText: 'Φύλο'),
                  items: const [
                    DropdownMenuItem(value: 'male', child: Text('Άνδρας')),
                    DropdownMenuItem(value: 'female', child: Text('Γυναίκα')),
                    DropdownMenuItem(value: 'other', child: Text('Άλλο')),
                    DropdownMenuItem(value: 'unknown', child: Text('Άγνωστο')),
                  ],
                  onChanged: (v) => setState(() => _gender = v),
                ),
                const SizedBox(height: 12),
                TextField(controller: _addressCtrl, decoration: const InputDecoration(labelText: 'Διεύθυνση')),
                const SizedBox(height: 12),
                TextField(controller: _cityCtrl, decoration: const InputDecoration(labelText: 'Πόλη')),
                const SizedBox(height: 12),
                TextField(controller: _postalCodeCtrl, decoration: const InputDecoration(labelText: 'Τ.Κ.')),
                const SizedBox(height: 12),
                TextField(controller: _telephoneCtrl, decoration: const InputDecoration(labelText: 'Τηλέφωνο'), keyboardType: TextInputType.phone),
                const SizedBox(height: 12),
                TextField(controller: _emergencyContactCtrl, decoration: const InputDecoration(labelText: 'Επαφή έκτακτης ανάγκης')),
                const SizedBox(height: 12),
                TextField(controller: _emergencyPhoneCtrl, decoration: const InputDecoration(labelText: 'Τηλέφωνο επαφής έκτακτης ανάγκης'), keyboardType: TextInputType.phone),
              ],
            ),
          ),

          // ── Step 1: Ιατρικό ιστορικό ──
          Step(
            title: const Text('Ιατρικό ιστορικό'),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
            content: Column(
              children: [
                TextField(
                  controller: _chiefComplaintCtrl,
                  decoration: const InputDecoration(labelText: 'Κύριο σύμπτωμα'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _allergiesCtrl,
                  decoration: const InputDecoration(labelText: 'Αλλεργίες'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _medicationsCtrl,
                  decoration: const InputDecoration(labelText: 'Φαρμακευτική αγωγή'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _medicalHistoryCtrl,
                  decoration: const InputDecoration(labelText: 'Ιατρικό ιστορικό'),
                  maxLines: 2,
                ),
              ],
            ),
          ),

          // ── Step 2: Αξιολόγηση ──
          Step(
            title: const Text('Αξιολόγηση'),
            isActive: _currentStep >= 2,
            state: _currentStep > 2 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('GCS (Glasgow Coma Scale)', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Σύνολο: $_gcsTotal / 15', style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFFC62828), fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _GcsSlider(label: 'Οφθαλμοί (E)', value: _gcsEye, min: 1, max: 4, onChanged: (v) => setState(() => _gcsEye = v)),
                _GcsSlider(label: 'Λεκτική (V)', value: _gcsVerbal, min: 1, max: 5, onChanged: (v) => setState(() => _gcsVerbal = v)),
                _GcsSlider(label: 'Κινητική (M)', value: _gcsMotor, min: 1, max: 6, onChanged: (v) => setState(() => _gcsMotor = v)),
                const SizedBox(height: 16),
                const Text('AVPU', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['ALERT', 'VOICE', 'PAIN', 'UNRESPONSIVE'].map((v) {
                    return ChoiceChip(
                      label: Text(v == 'ALERT' ? 'Σε εγρήγορση' : v == 'VOICE' ? 'Αντιδρά σε φωνή' : v == 'PAIN' ? 'Αντιδρά στον πόνο' : 'Χωρίς αντίδραση'),
                      selected: _avpu == v,
                      onSelected: (_) => setState(() => _avpu = _avpu == v ? null : v),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _locationNotesCtrl,
                  decoration: const InputDecoration(labelText: 'Σημειώσεις τοποθεσίας'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                if (prefilled && widget.prefilledServiceId != null)
                  Text('Υπηρεσία: Προσυμπληρωμένη', style: GoogleFonts.inter(color: const Color(0xFF6B7280)))
                else ...[
                  DropdownButtonFormField<int>(
                    value: _serviceId,
                    decoration: const InputDecoration(labelText: 'Υπηρεσία'),
                    items: [
                      const DropdownMenuItem<int>(value: null, child: Text('Καμία')),
                      ..._acceptedServices.map((s) => DropdownMenuItem<int>(
                        value: s['id'],
                        child: Text(s['name'] ?? 'Υπηρεσία ${s['id']}'),
                      )),
                    ],
                    onChanged: (v) => setState(() => _serviceId = v),
                  ),
                ],
              ],
            ),
          ),

          // ── Step 3: Επισκόπηση ──
          Step(
            title: const Text('Επισκόπηση'),
            isActive: _currentStep >= 3,
            state: _currentStep > 3 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SummaryRow(label: 'Ονοματεπώνυμο', value: _nameCtrl.text.trim()),
                if (_ageCtrl.text.isNotEmpty) _SummaryRow(label: 'Ηλικία', value: _ageCtrl.text),
                if (_dateOfBirth != null)
                  _SummaryRow(label: 'Ημ/νία γέννησης', value: '${_dateOfBirth!.day}/${_dateOfBirth!.month}/${_dateOfBirth!.year}'),
                if (_gender != null) _SummaryRow(label: 'Φύλο', value: _gender!),
                if (_chiefComplaintCtrl.text.isNotEmpty) _SummaryRow(label: 'Κύριο σύμπτωμα', value: _chiefComplaintCtrl.text),
                _SummaryRow(label: 'GCS', value: '$_gcsTotal (E$_gcsEye / V$_gcsVerbal / M$_gcsMotor)'),
                if (_avpu != null) _SummaryRow(label: 'AVPU', value: _avpu!),
                if (_serviceId != null) _SummaryRow(label: 'Συνδεδεμένη υπηρεσία', value: 'ID $_serviceId'),
                if (_notesCtrl.text.isNotEmpty) _SummaryRow(label: 'Σημειώσεις', value: _notesCtrl.text),
                const SizedBox(height: 16),
                TextField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(labelText: 'Σημειώσεις'),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GcsSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _GcsSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 130, child: Text(label, style: GoogleFonts.inter(fontSize: 13))),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: (max - min).round(),
            label: value.round().toString(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 24, child: Text(value.round().toString(), textAlign: TextAlign.center)),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text('$label:', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280))),
          ),
          Expanded(child: Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/screens/create_victim_screen.dart
git commit -m "feat: add multi-step victim creation form"
```

---

### Task 12: Create Victim Detail Screen

**Files:**
- Create: `frontend/lib/screens/victim_detail_screen.dart`

- [ ] **Step 1: Create the detail screen**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../providers/victim_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';

class VictimDetailScreen extends StatefulWidget {
  final int victimId;

  const VictimDetailScreen({super.key, required this.victimId});

  @override
  State<VictimDetailScreen> createState() => _VictimDetailScreenState();
}

class _VictimDetailScreenState extends State<VictimDetailScreen> {
  final _api = ApiClient();
  bool _vitalsExpanded = false;
  bool _treatmentsExpanded = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<VictimProvider>().fetchVictim(widget.victimId));
  }

  void _showAddVitalSignDialog() {
    final systolicCtrl = TextEditingController();
    final diastolicCtrl = TextEditingController();
    final hrCtrl = TextEditingController();
    final rrCtrl = TextEditingController();
    final spo2Ctrl = TextEditingController();
    final tempCtrl = TextEditingController();
    final glucoseCtrl = TextEditingController();
    final painCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final measuredByCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Προσθήκη ζωτικών σημείων'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: systolicCtrl, decoration: const InputDecoration(labelText: 'Συστολική (mmHg)'), keyboardType: TextInputType.number),
              TextField(controller: diastolicCtrl, decoration: const InputDecoration(labelText: 'Διαστολική (mmHg)'), keyboardType: TextInputType.number),
              TextField(controller: hrCtrl, decoration: const InputDecoration(labelText: 'Καρδιακοί παλμοί'), keyboardType: TextInputType.number),
              TextField(controller: rrCtrl, decoration: const InputDecoration(labelText: 'Αναπνοές/λεπτό'), keyboardType: TextInputType.number),
              TextField(controller: spo2Ctrl, decoration: const InputDecoration(labelText: 'SpO2 (%)'), keyboardType: TextInputType.number),
              TextField(controller: tempCtrl, decoration: const InputDecoration(labelText: 'Θερμοκρασία (°C)'), keyboardType: TextInputType.number),
              TextField(controller: glucoseCtrl, decoration: const InputDecoration(labelText: 'Γλυκόζη (mg/dL)'), keyboardType: TextInputType.number),
              TextField(controller: painCtrl, decoration: const InputDecoration(labelText: 'Πόνος (0–10)'), keyboardType: TextInputType.number),
              TextField(controller: measuredByCtrl, decoration: const InputDecoration(labelText: 'Καταγραφή από')),
              TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Σημειώσεις'), maxLines: 2),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () async {
              final data = <String, dynamic>{};
              if (systolicCtrl.text.isNotEmpty) data['systolicBP'] = int.tryParse(systolicCtrl.text);
              if (diastolicCtrl.text.isNotEmpty) data['diastolicBP'] = int.tryParse(diastolicCtrl.text);
              if (hrCtrl.text.isNotEmpty) data['heartRate'] = int.tryParse(hrCtrl.text);
              if (rrCtrl.text.isNotEmpty) data['respiratoryRate'] = int.tryParse(rrCtrl.text);
              if (spo2Ctrl.text.isNotEmpty) data['oxygenSat'] = int.tryParse(spo2Ctrl.text);
              if (tempCtrl.text.isNotEmpty) data['temperature'] = double.tryParse(tempCtrl.text);
              if (glucoseCtrl.text.isNotEmpty) data['bloodGlucose'] = double.tryParse(glucoseCtrl.text);
              if (painCtrl.text.isNotEmpty) data['painScore'] = int.tryParse(painCtrl.text);
              if (measuredByCtrl.text.isNotEmpty) data['measuredBy'] = measuredByCtrl.text;
              if (notesCtrl.text.isNotEmpty) data['notes'] = notesCtrl.text;

              final err = await context.read<VictimProvider>().addVitalSign(widget.victimId, data);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                if (err != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(err), backgroundColor: const Color(0xFFB91C1C)),
                  );
                }
              }
            },
            child: const Text('Καταγραφή'),
          ),
        ],
      ),
    );
  }

  void _showAddTreatmentDialog() async {
    final actionCtrl = TextEditingController();
    final materialCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final consumedCtrl = TextEditingController();
    final performedByCtrl = TextEditingController();

    // Fetch items from service + user equipment
    List<Map<String, dynamic>> availableItems = [];
    try {
      final victim = context.read<VictimProvider>().selected;
      if (victim != null && victim['serviceId'] != null) {
        final svcRes = await _api.get('/services/${victim['serviceId']}');
        if (svcRes.statusCode == 200) {
          final svc = jsonDecode(svcRes.body);
          final itemServices = svc['itemServices'] as List? ?? [];
          for (final is_ in itemServices) {
            final item = is_['item'];
            if (item != null) availableItems.add(item);
          }
        }
      }
    } catch (_) {}

    // User equipment
    try {
      final profileRes = await _api.get('/auth/me/profile');
      if (profileRes.statusCode == 200) {
        final profile = jsonDecode(profileRes.body);
        final equipment = profile['equipment'] as List? ?? [];
        for (final item in equipment) {
          final exists = availableItems.any((i) => i['id'] == item['id']);
          if (!exists) availableItems.add(item as Map<String, dynamic>);
        }
      }
    } catch (_) {}

    int? selectedItemId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Προσθήκη θεραπείας'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: actionCtrl, decoration: const InputDecoration(labelText: 'Ενέργεια *')),
                TextField(controller: materialCtrl, decoration: const InputDecoration(labelText: 'Υλικά που χρησιμοποιήθηκαν')),
                if (availableItems.isNotEmpty)
                  DropdownButtonFormField<int>(
                    value: selectedItemId,
                    decoration: const InputDecoration(labelText: 'Αντικείμενο (από εξοπλισμό)'),
                    items: [
                      const DropdownMenuItem<int>(value: null, child: Text('—')),
                      ...availableItems.map((item) => DropdownMenuItem<int>(
                        value: item['id'],
                        child: Text(item['name'] ?? 'Αντικείμενο ${item['id']}'),
                      )),
                    ],
                    onChanged: (v) => setDialogState(() => selectedItemId = v),
                  ),
                if (selectedItemId != null)
                  TextField(controller: consumedCtrl, decoration: const InputDecoration(labelText: 'Σημείωση κατανάλωσης')),
                TextField(controller: performedByCtrl, decoration: const InputDecoration(labelText: 'Εκτελέστηκε από')),
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Σημειώσεις'), maxLines: 2),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
            FilledButton(
              onPressed: () async {
                if (actionCtrl.text.trim().isEmpty) return;
                final data = <String, dynamic>{'action': actionCtrl.text.trim()};
                if (materialCtrl.text.isNotEmpty) data['materialUsed'] = materialCtrl.text;
                if (selectedItemId != null) data['itemId'] = selectedItemId;
                if (consumedCtrl.text.isNotEmpty) data['consumedNote'] = consumedCtrl.text;
                if (performedByCtrl.text.isNotEmpty) data['performedBy'] = performedByCtrl.text;
                if (notesCtrl.text.isNotEmpty) data['notes'] = notesCtrl.text;

                final err = await context.read<VictimProvider>().addTreatment(widget.victimId, data);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  if (err != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(err), backgroundColor: const Color(0xFFB91C1C)),
                    );
                  }
                }
              },
              child: const Text('Καταγραφή'),
            ),
          ],
        ),
      ),
    );
  }

  void _showFinalizeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Οριστικοποίηση περιστατικού'),
        content: const Text('Μετά την οριστικοποίηση, το περιστατικό μπορεί να τροποποιηθεί μόνο από διαχειριστές. Συνέχεια;'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final err = await context.read<VictimProvider>().finalizeVictim(widget.victimId);
              if (err != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(err), backgroundColor: const Color(0xFFB91C1C)),
                );
              }
            },
            child: const Text('Οριστικοποίηση'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή περιστατικού'),
        content: const Text('Αυτή η ενέργεια είναι μη αναστρέψιμη. Συνέχεια;'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
            onPressed: () async {
              Navigator.pop(ctx);
              final err = await context.read<VictimProvider>().deleteVictim(widget.victimId);
              if (err != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(err), backgroundColor: const Color(0xFFB91C1C)),
                );
              } else if (context.mounted) {
                context.go('/victims');
              }
            },
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<VictimProvider>();
    final victim = provider.selected;

    if (victim == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Περιστατικό')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isFinalized = victim['isFinalized'] == true;
    final isCreator = victim['createdById'] == auth.user?['id'];
    final isAdmin = auth.isAdmin;
    final canEdit = !isFinalized && (isCreator || isAdmin || auth.isMissionAdmin);
    final canFinalize = !isFinalized && (isCreator || isAdmin || auth.isMissionAdmin);
    final canDelete = isAdmin || auth.isMissionAdmin;

    final vitals = (victim['vitalSigns'] as List?) ?? [];
    final treatments = (victim['treatments'] as List?) ?? [];

    return Scaffold(
      appBar: AppBar(title: Text(victim['name'] ?? 'Περιστατικό')),
      body: RefreshIndicator(
        onRefresh: () => provider.fetchVictim(widget.victimId),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isFinalized) _FinalizedBanner(victim: victim),

              // Στοιχεία section
              _SectionHeader(title: 'Στοιχεία'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _DetailRow(label: 'Ονοματεπώνυμο', value: victim['name']),
                      if (victim['age'] != null) _DetailRow(label: 'Ηλικία', value: '${victim['age']}'),
                      if (victim['dateOfBirth'] != null) _DetailRow(label: 'Ημ/νία γέννησης', value: _formatDate(victim['dateOfBirth'])),
                      if (victim['gender'] != null) _DetailRow(label: 'Φύλο', value: _genderLabel(victim['gender'])),
                      if (victim['address'] != null) _DetailRow(label: 'Διεύθυνση', value: victim['address']),
                      if (victim['city'] != null) _DetailRow(label: 'Πόλη', value: victim['city']),
                      if (victim['telephone'] != null) _DetailRow(label: 'Τηλέφωνο', value: victim['telephone']),
                      if (victim['emergencyContact'] != null) _DetailRow(label: 'Επαφή έκτακτης ανάγκης', value: victim['emergencyContact']),
                      if (victim['emergencyPhone'] != null) _DetailRow(label: 'Τηλ. επαφής έκτακτης ανάγκης', value: victim['emergencyPhone']),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Ιατρικό section
              _SectionHeader(title: 'Ιατρικό ιστορικό'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      if (victim['chiefComplaint'] != null) _DetailRow(label: 'Κύριο σύμπτωμα', value: victim['chiefComplaint']),
                      if (victim['allergies'] != null) _DetailRow(label: 'Αλλεργίες', value: victim['allergies']),
                      if (victim['medications'] != null) _DetailRow(label: 'Φαρμακευτική αγωγή', value: victim['medications']),
                      if (victim['medicalHistory'] != null) _DetailRow(label: 'Ιατρικό ιστορικό', value: victim['medicalHistory']),
                      if (victim['chiefComplaint'] == null && victim['allergies'] == null && victim['medications'] == null && victim['medicalHistory'] == null)
                        const Text('Δεν καταγράφηκαν', style: TextStyle(color: Color(0xFF9CA3AF))),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Αξιολόγηση section
              _SectionHeader(title: 'Αξιολόγηση'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      if (victim['gcsTotal'] != null)
                        _DetailRow(label: 'GCS', value: '${victim['gcsTotal']} (E${victim['gcsEye']} / V${victim['gcsVerbal']} / M${victim['gcsMotor']})'),
                      if (victim['avpu'] != null) _DetailRow(label: 'AVPU', value: victim['avpu']),
                      if (victim['locationNotes'] != null) _DetailRow(label: 'Σημ. τοποθεσίας', value: victim['locationNotes']),
                      if (victim['service'] != null)
                        _DetailRow(label: 'Υπηρεσία', value: (victim['service'] as Map)['name'] ?? '—'),
                      if (victim['notes'] != null) _DetailRow(label: 'Σημειώσεις', value: victim['notes']),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Vital signs expandable section
              Card(
                child: ExpansionTile(
                  title: Text('Ζωτικά Σημεία (${vitals.length})', style: GoogleFonts.literata(fontSize: 15, fontWeight: FontWeight.w600)),
                  initiallyExpanded: _vitalsExpanded,
                  onExpansionChanged: (v) => setState(() => _vitalsExpanded = v),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canEdit)
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, color: Color(0xFFC62828)),
                          onPressed: _showAddVitalSignDialog,
                        ),
                      const Icon(Icons.expand_more),
                    ],
                  ),
                  children: vitals.isEmpty
                      ? [const Padding(padding: EdgeInsets.all(14), child: Text('Δεν υπάρχουν καταγραφές', style: TextStyle(color: Color(0xFF9CA3AF))))]
                      : vitals.map((vs) {
                          final sbp = vs['systolicBP'];
                          final dbp = vs['diastolicBP'];
                          final hr = vs['heartRate'];
                          final spo2 = vs['oxygenSat'];
                          final temp = vs['temperature'];
                          final pain = vs['painScore'];
                          final measuredAt = vs['measuredAt'] as String?;
                          final measuredBy = vs['measuredBy'];

                          return ListTile(
                            dense: true,
                            title: Text([
                              if (sbp != null && dbp != null) 'ΑΠ $sbp/$dbp',
                              if (hr != null) 'ΣΦ $hr',
                              if (spo2 != null) 'SpO2 $spo2%',
                              if (temp != null) '${temp}°C',
                              if (pain != null) 'Πόνος $pain/10',
                            ].join(' · '), style: GoogleFonts.inter(fontSize: 13)),
                            subtitle: Text([
                              if (measuredAt != null) _formatDateTime(measuredAt),
                              if (measuredBy != null) 'από $measuredBy',
                            ].join(' '), style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF9CA3AF))),
                            trailing: canEdit ? IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFB91C1C)),
                              onPressed: () async {
                                final err = await context.read<VictimProvider>().deleteVitalSign(widget.victimId, vs['id']);
                                if (err != null && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(err), backgroundColor: const Color(0xFFB91C1C)),
                                  );
                                }
                              },
                            ) : null,
                          );
                        }).toList(),
                ),
              ),

              const SizedBox(height: 8),

              // Treatments expandable section
              Card(
                child: ExpansionTile(
                  title: Text('Θεραπείες (${treatments.length})', style: GoogleFonts.literata(fontSize: 15, fontWeight: FontWeight.w600)),
                  initiallyExpanded: _treatmentsExpanded,
                  onExpansionChanged: (v) => setState(() => _treatmentsExpanded = v),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canEdit)
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, color: Color(0xFFC62828)),
                          onPressed: _showAddTreatmentDialog,
                        ),
                      const Icon(Icons.expand_more),
                    ],
                  ),
                  children: treatments.isEmpty
                      ? [const Padding(padding: EdgeInsets.all(14), child: Text('Δεν υπάρχουν καταγραφές', style: TextStyle(color: Color(0xFF9CA3AF))))]
                      : treatments.map((t) {
                          final action = t['action'] ?? '';
                          final material = t['materialUsed'];
                          final performedAt = t['performedAt'] as String?;
                          final performedBy = t['performedBy'];
                          final item = t['item'] as Map?;

                          return ListTile(
                            dense: true,
                            title: Text(action, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                            subtitle: Text([
                              if (material != null) material,
                              if (item != null) 'Αντικείμενο: ${item['name']}',
                              if (performedAt != null) _formatDateTime(performedAt),
                              if (performedBy != null) 'από $performedBy',
                            ].join(' · '), style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF9CA3AF))),
                            trailing: canEdit ? IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFB91C1C)),
                              onPressed: () async {
                                final err = await context.read<VictimProvider>().deleteTreatment(widget.victimId, t['id']);
                                if (err != null && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(err), backgroundColor: const Color(0xFFB91C1C)),
                                  );
                                }
                              },
                            ) : null,
                          );
                        }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
      // Bottom action bar
      bottomNavigationBar: (canEdit || canFinalize || canDelete)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    if (canEdit)
                      FilledButton.icon(
                        onPressed: () => context.push('/victims/create?serviceId=${widget.victimId}'), // reuse create for edit — actually, just push to edit
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Επεξεργασία'),
                      ),
                    if (canEdit) const SizedBox(width: 8),
                    if (canFinalize)
                      FilledButton.icon(
                        onPressed: _showFinalizeDialog,
                        icon: const Icon(Icons.lock_outline, size: 18),
                        label: const Text('Οριστικοποίηση'),
                      ),
                    if (canDelete) ...[
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
                        onPressed: _showDeleteDialog,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Διαγραφή'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : null,
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _formatDateTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _genderLabel(String? g) {
    switch (g) {
      case 'male': return 'Άνδρας';
      case 'female': return 'Γυναίκα';
      case 'other': return 'Άλλο';
      case 'unknown': return 'Άγνωστο';
      default: return g ?? '';
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(title, style: GoogleFonts.literata(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF1A1C1E))),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text('$label:', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280))),
          ),
          Expanded(child: Text(value, style: GoogleFonts.inter(fontSize: 13))),
        ],
      ),
    );
  }
}

class _FinalizedBanner extends StatelessWidget {
  final Map<String, dynamic> victim;

  const _FinalizedBanner({required this.victim});

  @override
  Widget build(BuildContext context) {
    final finalizedBy = victim['finalizedBy'] as Map?;
    final name = finalizedBy != null ? '${finalizedBy['forename']} ${finalizedBy['surname']}' : '—';
    final date = _formatDt(victim['finalizedAt'] as String?);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock, color: Color(0xFFD97706), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Οριστικοποιήθηκε από $name στις $date',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF92400E)),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDt(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/screens/victim_detail_screen.dart
git commit -m "feat: add victim detail screen with vitals and treatments"
```

---

### Task 13: Update Services Screen FAB (SpeedDial)

**Files:**
- Modify: `frontend/lib/screens/services_screen.dart`

- [ ] **Step 1: Add import for victims**

Add at the top of `services_screen.dart` alongside other imports:

```dart
import 'package:go_router/go_router.dart';
```

(This should already exist — verify it's present.)

- [ ] **Step 2: Replace the FAB logic**

Find the `floatingActionButton:` parameter in the `Scaffold` (around line 252). Replace:

```dart
floatingActionButton: (auth.isAdmin || auth.isMissionAdmin)
    ? FloatingActionButton(
        onPressed: () => context.push('/admin/services/create'),
        ...
      )
    : null,
```

With:

```dart
floatingActionButton: (auth.isAdmin || auth.isMissionAdmin)
    ? _SpeedDialFab(
        items: [
          _SpeedDialItem(
            label: 'Καταγραφή Περιστατικού',
            icon: Icons.personal_injury,
            onTap: () => context.push('/victims/create'),
          ),
          _SpeedDialItem(
            label: 'Νέα υπηρεσία',
            icon: Icons.add,
            onTap: () => context.push('/admin/services/create'),
          ),
        ],
      )
    : FloatingActionButton(
        onPressed: () => context.push('/victims/create'),
        child: const Icon(Icons.personal_injury),
      ),
```

- [ ] **Step 3: Add SpeedDial widget classes at the bottom of the file**

Append these private widget classes to `services_screen.dart` (after all existing classes, before the end of the file):

```dart
// ═══════════════════════════════════════════════════════════
// SpeedDial FAB (admin dual-action)
// ═══════════════════════════════════════════════════════════

class _SpeedDialItem {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _SpeedDialItem({required this.label, required this.icon, required this.onTap});
}

class _SpeedDialFab extends StatefulWidget {
  final List<_SpeedDialItem> items;
  const _SpeedDialFab({required this.items});

  @override
  State<_SpeedDialFab> createState() => _SpeedDialFabState();
}

class _SpeedDialFabState extends State<_SpeedDialFab>
    with SingleTickerProviderStateMixin {
  bool _open = false;
  late final AnimationController _controller;
  late final Animation<double> _rotate;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _rotate = Tween<double>(begin: 0, end: 0.125).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _scale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomRight,
      children: [
        // Backdrop
        if (_open)
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggle,
              child: Container(color: Colors.black.withAlpha(60)),
            ),
          ),
        // Action items
        Positioned(
          right: 0,
          bottom: _open ? 72 : 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: widget.items.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              return ScaleTransition(
                scale: _scale,
                child: Padding(
                  padding: EdgeInsets.only(bottom: idx < widget.items.length - 1 ? 12 : 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1C1E).withAlpha(190),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(item.label,
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton.small(
                        heroTag: 'speeddial_$idx',
                        onPressed: () {
                          _toggle();
                          item.onTap();
                        },
                        child: Icon(item.icon),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // Main FAB
        RotationTransition(
          turns: _rotate,
          child: FloatingActionButton(
            onPressed: _toggle,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/screens/services_screen.dart
git commit -m "feat: add SpeedDial FAB for victim creation on services screen"
```

---

### Task 14: Add Victims Section to Service Detail Screen

**Files:**
- Modify: `frontend/lib/screens/service_detail_screen.dart`

- [ ] **Step 1: Add imports**

At the top of `service_detail_screen.dart`, add:

```dart
import 'package:provider/provider.dart';
import '../providers/victim_provider.dart';
```

(Check if `provider` is already imported — if not, add it.)

- [ ] **Step 2: Add a victims section**

Find a suitable location in the service detail layout — after the last existing section card (e.g., after `_VehicleLogsCard`) and before the closing of the main column/list. Add this block:

In the compact layout (single column), add after the last existing section widget:

```dart
const _VictimsSection(serviceId: widget.serviceId),
```

And similarly in the wide layout's column. Create the `_VictimsSection` widget class at the bottom of the file:

```dart
class _VictimsSection extends StatefulWidget {
  final int serviceId;
  const _VictimsSection({required this.serviceId});

  @override
  State<_VictimsSection> createState() => _VictimsSectionState();
}

class _VictimsSectionState extends State<_VictimsSection> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<VictimProvider>().fetchVictims(serviceId: widget.serviceId));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VictimProvider>();
    final victims = provider.victims;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Περιστατικά (${victims.length})',
                  style: GoogleFonts.literata(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: Color(0xFFC62828)),
                  onPressed: () => context.push('/victims/create?serviceId=${widget.serviceId}'),
                  tooltip: 'Νέο περιστατικό',
                ),
              ],
            ),
            if (victims.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Δεν υπάρχουν περιστατικά για αυτή την υπηρεσία',
                  style: GoogleFonts.inter(color: const Color(0xFF9CA3AF), fontSize: 13),
                ),
              )
            else
              ...victims.map((v) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Row(
                  children: [
                    Expanded(
                      child: Text(v['name'] ?? 'Άγνωστο',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (v['isFinalized'] == true)
                      const Icon(Icons.lock, size: 14, color: Color(0xFF6B7280)),
                  ],
                ),
                subtitle: Text(
                  v['age'] != null ? '${v['age']} ετών' : '',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF9CA3AF)),
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => context.push('/victims/${v['id']}'),
              )),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/screens/service_detail_screen.dart
git commit -m "feat: add victims section to service detail screen"
```

---

### Task 15: End-to-End Verification

**Files:**
- None (verification only)

- [ ] **Step 1: Start backend and test API endpoints**

Start backend: `cd backend && npm run dev`

With a valid JWT token (obtain via login or use an existing session):

```bash
# Create a victim
curl -X POST http://localhost:4000/api/victims \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <TOKEN>" \
  -d '{"name":"Test Victim","age":30,"chiefComplaint":"Πόνος στο στήθος"}'

# List victims
curl http://localhost:4000/api/victims -H "Authorization: Bearer <TOKEN>"

# Get by ID (use returned ID from create)
curl http://localhost:4000/api/victims/1 -H "Authorization: Bearer <TOKEN>"

# Add vital sign
curl -X POST http://localhost:4000/api/victims/1/vital-signs \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <TOKEN>" \
  -d '{"systolicBP":120,"diastolicBP":80,"heartRate":72}'

# Add treatment
curl -X POST http://localhost:4000/api/victims/1/treatments \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <TOKEN>" \
  -d '{"action":"Χορήγηση οξυγόνου"}'

# Finalize
curl -X POST http://localhost:4000/api/victims/1/finalize \
  -H "Authorization: Bearer <TOKEN>"
```

Expected: All endpoints return appropriate JSON. 201 for creates, 200 for gets/list/finalize.

- [ ] **Step 2: Run frontend and test UI flow**

```bash
cd frontend && flutter run -d chrome
```

Walk through:
1. Verify "Περιστατικά" appears in nav rail between Services and Items
2. Navigate to Victims list — should show the test victim created above
3. Tap filter chips (Όλα / Ανοιχτά / Οριστικοποιημένα) — verify filtering works
4. Tap FAB → create form opens at Step 1
5. Fill in name, navigate through all 4 steps, submit
6. Verify victim appears in list after creation
7. Tap victim → detail screen shows all sections
8. Expand "Ζωτικά Σημεία" → verify existing measurements shown
9. Tap "+" → add vital sign dialog → submit → verify appears in list
10. Tap "+" on treatments → add treatment → verify appears
11. Tap Οριστικοποίηση → confirm → verify finalization banner appears
12. Return to Services screen → verify:
    - Regular user: sees single victim FAB
    - Admin: sees SpeedDial that expands to two options
13. Open a service detail → verify victims section at bottom

- [ ] **Step 3: Verify against spec**

Check each deliverable from the spec:
- [x] 3 Prisma models with correct relations
- [x] Migration applied
- [x] All 10 API endpoints working
- [x] Access rules enforced (creator, admin, missionAdmin, accepted member)
- [x] VictimProvider with full API surface
- [x] Nav rail updated (desktop + mobile)
- [x] Victims list screen with filters
- [x] Multi-step create form
- [x] Detail screen with vitals + treatments
- [x] SpeedDial FAB on services screen
- [x] Victims section on service detail

- [ ] **Step 4: Commit any remaining changes**

```bash
git status
git add -A
git commit -m "chore: final integration verification for victim management"
```
