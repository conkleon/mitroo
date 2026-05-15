# Service Types Overhaul — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `missionCategories` JSON + `ServiceVisibility` with a proper `ServiceType` entity — services get one type, specializations are assigned which types they can see.

**Architecture:** New `ServiceType` and `SpecializationServiceType` tables. Service gets `serviceTypeId` FK. Visibility computed at query time via Prisma joins through the FK chain: `Service -> ServiceType <- SpecializationServiceType -> Specialization`. Drop `ServiceVisibility` table and `missionCategories` column.

**Tech Stack:** Prisma (PostgreSQL), Express/TypeScript, Flutter/Dart

---

### Task 1: Prisma Schema Migration

**Files:**
- Modify: `backend/prisma/schema.prisma`

- [ ] **Step 1: Add ServiceType and SpecializationServiceType models, modify Service and Specialization**

In `backend/prisma/schema.prisma`, add these models before the `Specialization` model:

```prisma
// ──────────────────────────────────────────────
// Service types (replaces missionCategories)
// ──────────────────────────────────────────────

model ServiceType {
  id                    Int     @id @default(autoincrement())
  name                  String  @unique @db.VarChar(255)
  externalMissionTypeId Int?    @unique @map("external_mission_type_id")
  isDefaultVisible      Boolean @default(false) @map("is_default_visible")

  services        Service[]
  specializations SpecializationServiceType[]

  @@map("service_types")
}

model SpecializationServiceType {
  specializationId Int @map("specialization_id")
  serviceTypeId    Int @map("service_type_id")

  specialization Specialization @relation(fields: [specializationId], references: [id], onDelete: Cascade)
  serviceType    ServiceType    @relation(fields: [serviceTypeId], references: [id], onDelete: Cascade)

  @@id([specializationId, serviceTypeId])
  @@map("specialization_service_types")
}
```

In the `Service` model, add:
```prisma
  serviceTypeId Int? @map("service_type_id")
  serviceType   ServiceType? @relation(fields: [serviceTypeId], references: [id], onDelete: SetNull)
```

Remove from `Service` model:
```prisma
  visibility      ServiceVisibility[]
```

In the `Specialization` model, remove:
```prisma
  missionCategories   Json    @default("[]") @map("mission_categories")
  serviceVisibility    ServiceVisibility[]
```

Add to `Specialization` model:
```prisma
  serviceTypes    SpecializationServiceType[]
```

Delete the entire `ServiceVisibility` model (lines 380-389).

- [ ] **Step 2: Commit schema changes**

```bash
git add backend/prisma/schema.prisma
git commit -m "feat: add ServiceType and SpecializationServiceType models, drop ServiceVisibility and missionCategories"
```

---

### Task 2: Create and Run Prisma Migration

**Files:**
- Create: `backend/prisma/migrations/<timestamp>_service_types/migration.sql`

- [ ] **Step 1: Run Prisma migrate dev to generate the migration SQL**

```bash
cd backend
npm run prisma:migrate -- --name service_types
```

- [ ] **Step 2: Verify migration SQL looks correct**

Check that the generated migration:
- Creates `service_types` table with columns `id`, `name`, `external_mission_type_id`, `is_default_visible`
- Creates `specialization_service_types` table with `specialization_id`, `service_type_id`
- Adds `service_type_id` column to `services` table
- Drops `mission_categories` column from `specializations`
- Drops `service_visibility` table

- [ ] **Step 3: Generate Prisma client**

```bash
cd backend
npm run prisma:generate
```

- [ ] **Step 4: Commit migration**

```bash
git add backend/prisma/migrations
git commit -m "chore: run service_types migration"
```

---

### Task 3: Update Seed Script

**Files:**
- Modify: `backend/prisma/seed.ts`

- [ ] **Step 1: Replace missionCategories seeding with ServiceType and SpecializationServiceType**

Replace the entire content of `backend/prisma/seed.ts` with:

```typescript
import { PrismaClient, DepartmentRole } from "@prisma/client";
import bcrypt from "bcryptjs";

const prisma = new PrismaClient();

async function main() {
  console.log("🌱 Seeding database …");

  // ── Admin user ────────────────────────────────
  const hashedPassword = await bcrypt.hash("admin123", 12);
  const admin = await prisma.user.upsert({
    where: { eame: "admin" },
    update: {},
    create: {
      eame: "admin",
      password: hashedPassword,
      forename: "System",
      surname: "Admin",
      email: "admin@mitroo.local",
      isAdmin: true,
    },
  });

  // ── Sample volunteer ──────────────────────────
  const volPassword = await bcrypt.hash("volunteer1", 12);
  const volunteer = await prisma.user.upsert({
    where: { eame: "jdoe" },
    update: {},
    create: {
      eame: "jdoe",
      password: volPassword,
      forename: "Jane",
      surname: "Doe",
      email: "jane.doe@example.com",
    },
  });

  // ── Departments ───────────────────────────────
  const ops = await prisma.department.upsert({
    where: { id: 1 },
    update: {},
    create: { name: "Τμήμα Αθήνας", description: "Health / Medical services", location: "HQ" },
  });

  // ── Department memberships ────────────────────
  await prisma.userDepartment.upsert({
    where: { userId_departmentId: { userId: admin.id, departmentId: ops.id } },
    update: {},
    create: { userId: admin.id, departmentId: ops.id, role: DepartmentRole.missionAdmin },
  });

  // ── Role types ────────────────────────────────
  for (const rt of [
    { name: "missionAdmin", description: "Can create & assign users to services" },
    { name: "itemAdmin", description: "Can manage items" },
    { name: "volunteer", description: "Can request service access & view info" },
  ]) {
    await prisma.roleType.upsert({ where: { name: rt.name }, update: {}, create: rt });
  }

  // ── Service types (11 types from old Mitroo) ──
  const serviceTypes = [
    { name: "BLS “ΒΑΣΙΚΗ ΥΠΟΣΤΗΡΙΞΗ ΖΩΗΣ’’", externalMissionTypeId: 71, isDefaultVisible: false },
    { name: "ΔΡΑΣΗ ΠΡΟΛΗΨΗΣ", externalMissionTypeId: 56, isDefaultVisible: false },
    { name: "ΕΘΕΛΟΝΤΙΚΗ ΔΡΑΣΤΗΡΙΟΤΗΤΑ", externalMissionTypeId: 57, isDefaultVisible: false },
    { name: "ΕΚΠΑΙΔΕΥΣΗ Α΄ ΒΟΗΘΕΙΩΝ ΣΕ ΠΟΛΙΤΕΣ", externalMissionTypeId: 36, isDefaultVisible: false },
    { name: "ΕΚΠΑΙΔΕΥΣΗ Α' ΒΟΗΘΕΙΕΣ ΓΙΑ ΣΚΥΛΟΥΣ", externalMissionTypeId: 86, isDefaultVisible: false },
    { name: "ΕΚΠΑΙΔΕΥΣΗ ΔΟΚΙΜΩΝ ΣΑΜΑΡΕΙΤΩΝ", externalMissionTypeId: 33, isDefaultVisible: false },
    { name: "ΕΚΠΑΙΔΕΥΣΗ ΕΝΕΡΓΟΠΟΙΗΣΗΣ ΑΝΕΝΕΡΓΩΝ ΕΘΕΛΟΝΤΩΝ", externalMissionTypeId: 83, isDefaultVisible: false },
    { name: "ΝΑΥΑΓΟΣΩΣΤΙΚΗ ΚΑΛΥΨΗ", externalMissionTypeId: 60, isDefaultVisible: false },
    { name: "Τ.Ε.Π. ΔΟΚΙΜΩΝ", externalMissionTypeId: 85, isDefaultVisible: false },
    { name: "ΥΓΕΙΟΝΟΜΙΚΗ ΚΑΛΥΨΗ", externalMissionTypeId: 16, isDefaultVisible: false },
    { name: "ΥΠΟΧΡΕΩΤΙΚΗ ΕΤΗΣΙΑ ΕΚΠΑΙΔΕΥΣΗ ΕΘΕΛΟΝΤΗ", externalMissionTypeId: 81, isDefaultVisible: false },
  ];

  const createdTypes: Record<string, number> = {};
  for (const st of serviceTypes) {
    const created = await prisma.serviceType.upsert({
      where: { name: st.name },
      update: { externalMissionTypeId: st.externalMissionTypeId, isDefaultVisible: st.isDefaultVisible },
      create: st,
    });
    createdTypes[st.name] = created.id;
  }

  // ── Specializations ───────────────────────────
  const specsToCreate = [
    { name: "Δόκιμος Σαμαρείτης", description: "Δόκιμος Σαμαρείτης" },
    { name: "Δόκιμος Ναυαγοσώστης", description: "Δόκιμος Ναυαγοσώστης" },
    { name: "Σαμαρείτης", description: "Σαμαρείτης" },
    { name: "Ναυαγοσώστης", description: "Ναυαγοσώστης" },
    { name: "Εκπαιδευτής Α' Βοηθειών", description: "Εκπαιδευτής Πρώτων Βοηθειών" },
    { name: "Εκπαιδευτής Ναυαγοσωστικής", description: "Εκπαιδευτής Ναυαγοσωστικής" },
  ];

  const createdSpecs: Record<string, number> = {};
  for (const spec of specsToCreate) {
    const created = await prisma.specialization.upsert({
      where: { name: spec.name },
      update: { description: spec.description },
      create: spec,
    });
    createdSpecs[spec.name] = created.id;
  }

  // ── Specialization ↔ ServiceType assignments ──
  // Mapping which specs can see which service types
  // All specs see: BLS (71), Prevention (56), Volunteer Activity (57),
  //                First Aid Citizens (36), First Aid Dogs (86),
  //                Candidate Training (33), Reactivation (83),
  //                Mandatory Annual (81)
  const defaultVisibleTypeNames = [
    "BLS “ΒΑΣΙΚΗ ΥΠΟΣΤΗΡΙΞΗ ΖΩΗΣ’’",
    "ΔΡΑΣΗ ΠΡΟΛΗΨΗΣ",
    "ΕΘΕΛΟΝΤΙΚΗ ΔΡΑΣΤΗΡΙΟΤΗΤΑ",
    "ΕΚΠΑΙΔΕΥΣΗ Α΄ ΒΟΗΘΕΙΩΝ ΣΕ ΠΟΛΙΤΕΣ",
    "ΕΚΠΑΙΔΕΥΣΗ Α' ΒΟΗΘΕΙΕΣ ΓΙΑ ΣΚΥΛΟΥΣ",
    "ΕΚΠΑΙΔΕΥΣΗ ΔΟΚΙΜΩΝ ΣΑΜΑΡΕΙΤΩΝ",
    "ΕΚΠΑΙΔΕΥΣΗ ΕΝΕΡΓΟΠΟΙΗΣΗΣ ΑΝΕΝΕΡΓΩΝ ΕΘΕΛΟΝΤΩΝ",
    "ΥΠΟΧΡΕΩΤΙΚΗ ΕΤΗΣΙΑ ΕΚΠΑΙΔΕΥΣΗ ΕΘΕΛΟΝΤΗ",
  ];

  // Build visible-to-all assignments for all specs
  for (const specName of Object.keys(createdSpecs)) {
    for (const typeName of defaultVisibleTypeNames) {
      if (createdTypes[typeName] && createdSpecs[specName]) {
        await prisma.specializationServiceType.upsert({
          where: {
            specializationId_serviceTypeId: {
              specializationId: createdSpecs[specName],
              serviceTypeId: createdTypes[typeName],
            },
          },
          update: {},
          create: {
            specializationId: createdSpecs[specName],
            serviceTypeId: createdTypes[typeName],
          },
        });
      }
    }
  }

  // Σαμαρείτης + Δόκιμος Σαμαρείτης see sanitary coverage + TEP
  for (const specName of ["Σαμαρείτης", "Δόκιμος Σαμαρείτης"]) {
    for (const typeName of ["ΥΓΕΙΟΝΟΜΙΚΗ ΚΑΛΥΨΗ", "Τ.Ε.Π. ΔΟΚΙΜΩΝ"]) {
      if (createdTypes[typeName] && createdSpecs[specName]) {
        await prisma.specializationServiceType.upsert({
          where: {
            specializationId_serviceTypeId: {
              specializationId: createdSpecs[specName],
              serviceTypeId: createdTypes[typeName],
            },
          },
          update: {},
          create: {
            specializationId: createdSpecs[specName],
            serviceTypeId: createdTypes[typeName],
          },
        });
      }
    }
  }

  // Ναυαγοσώστης + Δόκιμος Ναυαγοσώστης see lifeguard + sanitary + TEP
  for (const specName of ["Ναυαγοσώστης", "Δόκιμος Ναυαγοσώστης"]) {
    for (const typeName of ["ΝΑΥΑΓΟΣΩΣΤΙΚΗ ΚΑΛΥΨΗ", "ΥΓΕΙΟΝΟΜΙΚΗ ΚΑΛΥΨΗ", "Τ.Ε.Π. ΔΟΚΙΜΩΝ"]) {
      if (createdTypes[typeName] && createdSpecs[specName]) {
        await prisma.specializationServiceType.upsert({
          where: {
            specializationId_serviceTypeId: {
              specializationId: createdSpecs[specName],
              serviceTypeId: createdTypes[typeName],
            },
          },
          update: {},
          create: {
            specializationId: createdSpecs[specName],
            serviceTypeId: createdTypes[typeName],
          },
        });
      }
    }
  }

  // Εκπαιδευτής Α' Βοηθειών sees sanitary coverage + TEP
  for (const typeName of ["ΥΓΕΙΟΝΟΜΙΚΗ ΚΑΛΥΨΗ", "Τ.Ε.Π. ΔΟΚΙΜΩΝ"]) {
    if (createdTypes[typeName] && createdSpecs["Εκπαιδευτής Α' Βοηθειών"]) {
      await prisma.specializationServiceType.upsert({
        where: {
          specializationId_serviceTypeId: {
            specializationId: createdSpecs["Εκπαιδευτής Α' Βοηθειών"],
            serviceTypeId: createdTypes[typeName],
          },
        },
        update: {},
        create: {
          specializationId: createdSpecs["Εκπαιδευτής Α' Βοηθειών"],
          serviceTypeId: createdTypes[typeName],
        },
      });
    }
  }

  // Εκπαιδευτής Ναυαγοσωστικής sees lifeguard + sanitary + TEP
  for (const typeName of ["ΝΑΥΑΓΟΣΩΣΤΙΚΗ ΚΑΛΥΨΗ", "ΥΓΕΙΟΝΟΜΙΚΗ ΚΑΛΥΨΗ", "Τ.Ε.Π. ΔΟΚΙΜΩΝ"]) {
    if (createdTypes[typeName] && createdSpecs["Εκπαιδευτής Ναυαγοσωστικής"]) {
      await prisma.specializationServiceType.upsert({
        where: {
          specializationId_serviceTypeId: {
            specializationId: createdSpecs["Εκπαιδευτής Ναυαγοσωστικής"],
            serviceTypeId: createdTypes[typeName],
          },
        },
        update: {},
        create: {
          specializationId: createdSpecs["Εκπαιδευτής Ναυαγοσωστικής"],
          serviceTypeId: createdTypes[typeName],
        },
      });
    }
  }

  // ── User ↔ Specialization assignments ─────────
  for (const specId of [createdSpecs["Σαμαρείτης"], createdSpecs["Εκπαιδευτής Α' Βοηθειών"], createdSpecs["Εκπαιδευτής Ναυαγοσωστικής"]]) {
    await prisma.userSpecialization.upsert({
      where: { userId_specializationId: { userId: admin.id, specializationId: specId } },
      update: {},
      create: { userId: admin.id, specializationId: specId },
    });
  }
  for (const specId of [createdSpecs["Δόκιμος Σαμαρείτης"], createdSpecs["Σαμαρείτης"]]) {
    await prisma.userSpecialization.upsert({
      where: { userId_specializationId: { userId: volunteer.id, specializationId: specId } },
      update: {},
      create: { userId: volunteer.id, specializationId: specId },
    });
  }

  // ── Services ───────────────────────────────────
  const serviceNames = [
    "Υγειονομική Κάλυψη Αγώνα Α",
    "Υγειονομική Κάλυψη Αγώνα Β",
    "Ναυαγοσωστική Κάλυψη",
    "Εκπαίδευση Πρώτων Βοηθειών",
    "BLS/AED Session 1", "BLS/AED Session 2", "BLS/AED Session 3",
    "BLS/AED Session 4", "BLS/AED Session 5", "BLS/AED Session 6",
    "BLS/AED Session 7", "BLS/AED Session 8", "BLS/AED Session 9",
    "BLS/AED Session 10", "BLS/AED Session 11", "BLS/AED Session 12",
  ];
  for (let i = 0; i < serviceNames.length; i++) {
    await prisma.service.upsert({
      where: { id: i + 1 },
      update: {},
      create: { name: serviceNames[i], departmentId: ops.id },
    });
  }

  // ── Item categories ────────────────────────────
  const catMedical = await prisma.itemCategory.upsert({
    where: { name_departmentId: { name: "Ιατρικά", departmentId: ops.id } },
    update: {},
    create: { name: "Ιατρικά", departmentId: ops.id },
  });

  // ── Vehicles ──────────────────────────────────
  await prisma.vehicle.upsert({
    where: { id: 1 },
    update: {},
    create: {
      name: "Patrol Boat #1",
      type: "boat",
      registrationNumber: "PB-001",
      meterType: "hours",
      departmentId: ops.id,
    },
  });

  await prisma.vehicle.upsert({
    where: { id: 2 },
    update: {},
    create: {
      name: "Pickup Truck #1",
      type: "car",
      registrationNumber: "PT-001",
      meterType: "km",
      departmentId: ops.id,
    },
  });

  console.log("✅ Seed complete");
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
```

- [ ] **Step 2: Run the seed to verify it works**

```bash
cd backend
npm run seed
```

Expected: "✅ Seed complete" with no errors.

- [ ] **Step 3: Commit**

```bash
git add backend/prisma/seed.ts
git commit -m "feat: update seed for service types instead of missionCategories"
```

---

### Task 4: Backend — New ServiceType Routes

**Files:**
- Create: `backend/src/routes/serviceType.routes.ts`
- Modify: `backend/src/app.ts`

- [ ] **Step 1: Create the service type routes file**

Create `backend/src/routes/serviceType.routes.ts`:

```typescript
import { Router, Request, Response } from "express";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate, requireAdmin } from "../middleware/auth";

const router = Router();
router.use(authenticate);

const createSchema = z.object({
  name: z.string().min(1).max(255),
  externalMissionTypeId: z.number().int().optional().nullable(),
  isDefaultVisible: z.boolean().optional(),
});

const updateSchema = createSchema.partial();

// ── GET /api/service-types ──────────────────────
router.get("/", async (_req: Request, res: Response) => {
  const types = await prisma.serviceType.findMany({
    include: {
      _count: { select: { specializations: true, services: true } },
    },
    orderBy: { name: "asc" },
  });
  res.json(types);
});

// ── POST /api/service-types ─────────────────────
router.post("/", requireAdmin, async (req: Request, res: Response) => {
  try {
    const data = createSchema.parse(req.body);
    const serviceType = await prisma.serviceType.create({ data });
    res.status(201).json(serviceType);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── PATCH /api/service-types/:id ────────────────
router.patch("/:id", requireAdmin, async (req: Request, res: Response) => {
  try {
    const data = updateSchema.parse(req.body);
    const serviceType = await prisma.serviceType.update({
      where: { id: Number(req.params.id) },
      data,
      include: { _count: { select: { specializations: true, services: true } } },
    });
    res.json(serviceType);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── DELETE /api/service-types/:id ───────────────
router.delete("/:id", requireAdmin, async (req: Request, res: Response) => {
  await prisma.serviceType.delete({ where: { id: Number(req.params.id) } });
  res.status(204).end();
});

// ── GET /api/service-types/:id/specializations ──
router.get("/:id/specializations", async (req: Request, res: Response) => {
  const rows = await prisma.specializationServiceType.findMany({
    where: { serviceTypeId: Number(req.params.id) },
    include: { specialization: { select: { id: true, name: true } } },
  });
  res.json(rows);
});

// ── PUT /api/service-types/:id/specializations ──
router.put("/:id/specializations", requireAdmin, async (req: Request, res: Response) => {
  const schema = z.object({ specializationIds: z.array(z.number().int()) });
  const { specializationIds } = schema.parse(req.body);
  const serviceTypeId = Number(req.params.id);

  await prisma.$transaction([
    prisma.specializationServiceType.deleteMany({ where: { serviceTypeId } }),
    prisma.specializationServiceType.createMany({
      data: specializationIds.map((sid) => ({ specializationId: sid, serviceTypeId })),
    }),
  ]);

  res.json({ ok: true });
});

export default router;
```

- [ ] **Step 2: Register the new routes in app.ts**

In `backend/src/app.ts`, add the import (after the existing imports):

```typescript
import serviceTypeRoutes from "./routes/serviceType.routes";
```

And add the route registration (after the existing routes):

```typescript
app.use("/api/service-types", serviceTypeRoutes);
```

- [ ] **Step 3: Verify it compiles**

```bash
cd backend
npm run build
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add backend/src/routes/serviceType.routes.ts backend/src/app.ts
git commit -m "feat: add service type CRUD and specialization assignment routes"
```

---

### Task 5: Backend — Update Service Routes

**Files:**
- Modify: `backend/src/routes/service.routes.ts`

- [ ] **Step 1: Add `serviceTypeId` to createSchema and remove visibility sub-routes**

In `backend/src/routes/service.routes.ts`, modify the `createSchema` (line 56-71) to add:

```typescript
  serviceTypeId: z.number().int().optional().nullable(),
```

So the full schema becomes:

```typescript
const createSchema = z.object({
  departmentId: z.number().int(),
  name: z.string().min(1).max(255),
  description: z.string().optional(),
  location: z.string().optional(),
  carrier: z.string().max(255).optional(),
  responsibleUserId: z.number().int().nullable().optional(),
  defaultHours: z.number().int().min(0).optional(),
  defaultHoursVol: z.number().int().min(0).optional(),
  defaultHoursTraining: z.number().int().min(0).optional(),
  defaultHoursTrainers: z.number().int().min(0).optional(),
  defaultHoursTEP: z.number().int().min(0).optional(),
  maxParticipants: z.number().int().min(1).optional(),
  startAt: z.string().datetime().optional(),
  endAt: z.string().datetime().optional(),
  serviceTypeId: z.number().int().optional().nullable(),
});
```

- [ ] **Step 2: Update the GET /api/services handler to filter by specialization via serviceType chain**

Find the `specializationId` filter block around line 118-122:

```typescript
  // Filter by specialization visibility
  if (specializationId) {
    where.visibility = {
      some: { specializationId: Number(specializationId) },
    };
  }
```

Replace with:

```typescript
  // Filter by specialization via service type chain
  if (specializationId) {
    where.serviceType = {
      specializations: {
        some: { specializationId: Number(specializationId) },
      },
    };
  }
```

Also update the `include` on GET / to include serviceType info (around line 126-128). Change:

```typescript
    include: {
      department: { select: { id: true, name: true } },
      responsibleUser: { select: { id: true, eame: true, forename: true, surname: true, imagePath: true } },
      visibility: { include: { specialization: { select: { id: true, name: true } } } },
      _count: { select: { userServices: true, itemServices: true } },
    },
```

To:

```typescript
    include: {
      department: { select: { id: true, name: true } },
      responsibleUser: { select: { id: true, eame: true, forename: true, surname: true, imagePath: true } },
      serviceType: { select: { id: true, name: true } },
      _count: { select: { userServices: true, itemServices: true } },
    },
```

- [ ] **Step 3: Update the GET /api/services/my handler**

Find the visibility filter in the `/my` handler (around lines 178-192). Replace the AND block:

```typescript
    where.AND = [
      {
        OR: [
          // services with NO visibility restrictions → visible to all dept members
          { visibility: { none: {} } },
          // services whose required specializations overlap the user's
          { visibility: { some: { specializationId: { in: specIds } } } },
        ],
      },
    ];
```

With:

```typescript
    where.AND = [
      {
        OR: [
          // services with no type → visible to all (safety net)
          { serviceTypeId: null },
          // services with default-visible types
          { serviceType: { isDefaultVisible: true } },
          // services whose types are assigned to the user's specializations
          { serviceType: { specializations: { some: { specializationId: { in: specIds } } } } },
        ],
      },
    ];
```

In the same handler's `include`, replace:

```typescript
      visibility: { include: { specialization: { select: { id: true, name: true } } } },
```

With:

```typescript
      serviceType: {
        include: {
          specializations: { include: { specialization: { select: { id: true, name: true } } } },
        },
      },
```

- [ ] **Step 4: Update the GET /api/services/:id handler include**

Find the single-service GET handler (around line 256). Replace:

```typescript
      visibility: { include: { specialization: true } },
```

With:

```typescript
      serviceType: {
        include: {
          specializations: { include: { specialization: { select: { id: true, name: true } } } },
        },
      },
```

- [ ] **Step 5: Remove visibility sub-routes**

Delete the `POST /:id/visibility` and `DELETE /:sid/visibility/:specId` routes (around lines 494-520).

- [ ] **Step 6: Verify it compiles**

```bash
cd backend
npm run build
```

Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add backend/src/routes/service.routes.ts
git commit -m "feat: update service routes for serviceTypeId, remove ServiceVisibility sub-routes"
```

---

### Task 6: Backend — Update Specialization Routes

**Files:**
- Modify: `backend/src/routes/specialization.routes.ts`

- [ ] **Step 1: Remove `missionCategories` from the create/update schemas**

In `backend/src/routes/specialization.routes.ts`, find the `createSchema` (around line 18) and remove the `missionCategories` line:

```typescript
  missionCategories: z.array(z.enum(MISSION_CATEGORIES)).optional(),
```

Also remove the `MISSION_CATEGORIES` constant if it's only used here. If the file still imports or defines it, remove the definition and any related imports.

Also add `serviceTypes` to the GET include so the frontend can use it. Find the GET / handler (around line 31-39) and change the include to:

```typescript
  const specs = await prisma.specialization.findMany({
    include: {
      root: { select: { id: true, name: true } },
      serviceTypes: { include: { serviceType: { select: { id: true, name: true } } } },
      _count: { select: { children: true, users: true } },
    },
    orderBy: { name: "asc" },
  });
```

On the single GET handler (around line 67), add the same `serviceTypes` include:

```typescript
  const spec = await prisma.specialization.findUnique({
    where: { id: Number(req.params.id) },
    include: {
      root: { select: { id: true, name: true } },
      children: { select: { id: true, name: true } },
      serviceTypes: { include: { serviceType: { select: { id: true, name: true } } } },
      _count: { select: { children: true, users: true } },
    },
  });
```

- [ ] **Step 2: Verify it compiles**

```bash
cd backend
npm run build
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add backend/src/routes/specialization.routes.ts
git commit -m "feat: remove missionCategories from specialization routes, add serviceTypes include"
```

---

### Task 7: Backend — Update Sync Logic

**Files:**
- Modify: `backend/src/lib/mitrooSync.ts`

- [ ] **Step 1: Remove old constants and function, add serviceTypeId lookup**

Remove these constants (around lines 10-31):
- `TRAINER_MISSION_TYPE_IDS`
- `TRAINING_MISSION_TYPE_IDS`
- `TEP_MISSION_TYPE_IDS`
- `VOLUNTEER_MISSION_TYPE_IDS`
- `SANITARY_MISSION_TYPE_IDS`
- `MISSION_CATEGORY_MAP`
- `getCategoriesForMissionType` function

Remove the entire `syncServiceVisibility` function (lines 184-215).

- [ ] **Step 2: Add a helper to build the mission type → serviceTypeId map**

Add after the `cleanServiceName` function:

```typescript
let _serviceTypeIdMap: Map<number, number> | null = null;

async function getServiceTypeIdMap(): Promise<Map<number, number>> {
  if (_serviceTypeIdMap) return _serviceTypeIdMap;
  const types = await prisma.serviceType.findMany({
    where: { externalMissionTypeId: { not: null } },
    select: { id: true, externalMissionTypeId: true },
  });
  _serviceTypeIdMap = new Map();
  for (const t of types) {
    if (t.externalMissionTypeId != null) {
      _serviceTypeIdMap.set(t.externalMissionTypeId, t.id);
    }
  }
  return _serviceTypeIdMap;
}

function lookupServiceTypeId(map: Map<number, number>, missionTypeId: unknown): number | null {
  const id = Number(missionTypeId);
  if (!Number.isFinite(id)) return null;
  return map.get(id) ?? null;
}
```

- [ ] **Step 3: Pre-fetch the map and replace syncServiceVisibility calls**

In the `syncServices` function, at the start of the missions loop (after line 386), load the map:

```typescript
    const typeIdMap = await getServiceTypeIdMap();
```

Then, for both `existing` (update) and `newService` (create) cases, replace the old code.

In the sync loop (around lines 436-470), for both `existing` (update) and `newService` (create) cases:

For the update branch, replace:
```typescript
            await prisma.service.update({
              where: { id: existing.id },
              data: {
                name,
                startAt,
                endAt,
                externalMissionId: missionId,
                defaultHours,
                defaultHoursVol,
                defaultHoursTraining,
                defaultHoursTrainers,
                defaultHoursTEP,
              },
            });
            result.updated++;
            await syncServiceVisibility(existing.id, mission.mission_type_id);
```

With:
```typescript
            const serviceTypeId = lookupServiceTypeId(typeIdMap, mission.mission_type_id);
            await prisma.service.update({
              where: { id: existing.id },
              data: {
                name,
                startAt,
                endAt,
                externalMissionId: missionId,
                defaultHours,
                defaultHoursVol,
                defaultHoursTraining,
                defaultHoursTrainers,
                defaultHoursTEP,
                serviceTypeId,
              },
            });
            result.updated++;
```

For the create branch, replace:
```typescript
            const newService = await prisma.service.create({
              data: {
                departmentId,
                name,
                externalShiftId,
                externalMissionId: missionId,
                startAt,
                endAt,
                defaultHours,
                defaultHoursVol,
                defaultHoursTraining,
                defaultHoursTrainers,
                defaultHoursTEP,
              },
            });
            result.created++;
            await syncServiceVisibility(newService.id, mission.mission_type_id);
```

With:
```typescript
            const serviceTypeId = lookupServiceTypeId(typeIdMap, mission.mission_type_id);
            const newService = await prisma.service.create({
              data: {
                departmentId,
                name,
                externalShiftId,
                externalMissionId: missionId,
                startAt,
                endAt,
                defaultHours,
                defaultHoursVol,
                defaultHoursTraining,
                defaultHoursTrainers,
                defaultHoursTEP,
                serviceTypeId,
              },
            });
            result.created++;
```

- [ ] **Step 4: Verify it compiles**

```bash
cd backend
npm run build
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add backend/src/lib/mitrooSync.ts
git commit -m "feat: replace syncServiceVisibility with direct serviceTypeId lookup in sync"
```

---

### Task 8: Frontend — New ManageServiceTypesScreen

**Files:**
- Create: `frontend/lib/screens/manage_service_types_screen.dart`

- [ ] **Step 1: Create the admin screen for managing service types**

Create `frontend/lib/screens/manage_service_types_screen.dart`:

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_client.dart';

class ManageServiceTypesScreen extends StatefulWidget {
  const ManageServiceTypesScreen({super.key});

  @override
  State<ManageServiceTypesScreen> createState() => _ManageServiceTypesScreenState();
}

class _ManageServiceTypesScreenState extends State<ManageServiceTypesScreen> {
  final _api = ApiClient();
  List<dynamic> _types = [];
  List<dynamic> _allSpecs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get('/service-types');
      if (res.statusCode == 200) _types = jsonDecode(res.body);
      final specRes = await _api.get('/specializations');
      if (specRes.statusCode == 200) _allSpecs = jsonDecode(specRes.body);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleDefaultVisible(int typeId, bool current) async {
    await _api.patch('/service-types/$typeId', body: {'isDefaultVisible': !current});
    _fetch();
  }

  void _showEditSheet(Map<String, dynamic> type) async {
    final typeId = type['id'] as int;

    // Load existing spec assignments
    List<int> selectedSpecIds = [];
    try {
      final res = await _api.get('/service-types/$typeId/specializations');
      if (res.statusCode == 200) {
        final rows = jsonDecode(res.body) as List<dynamic>;
        selectedSpecIds = rows.map((r) => r['specializationId'] as int).toList();
      }
    } catch (_) {}

    final selected = Set<int>.from(selectedSpecIds);

    final nameCtrl = TextEditingController(text: type['name'] ?? '');
    final extIdCtrl = TextEditingController(text: '${type['externalMissionTypeId'] ?? ''}');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollCtrl) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: ListView(
              controller: scrollCtrl,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Επεξεργασία Τύπου Υπηρεσίας',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Όνομα',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: extIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'External Mission Type ID',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),
                Text('Ειδικεύσεις που βλέπουν αυτό τον τύπο',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (_allSpecs.isEmpty)
                  const Text('Δεν υπάρχουν ειδικεύσεις')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _allSpecs.map((s) {
                      final specId = s['id'] as int;
                      final sel = selected.contains(specId);
                      return FilterChip(
                        label: Text(s['name'] ?? ''),
                        selected: sel,
                        onSelected: (v) {
                          setS(() {
                            if (v) {
                              selected.add(specId);
                            } else {
                              selected.remove(specId);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Άκυρο'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          // Update name/externalId
                          final body = <String, dynamic>{
                            'name': nameCtrl.text.trim(),
                          };
                          final extIdParsed = int.tryParse(extIdCtrl.text.trim());
                          if (extIdParsed != null) {
                            body['externalMissionTypeId'] = extIdParsed;
                          }
                          await _api.patch('/service-types/$typeId', body: body);

                          // Update specialization assignments
                          await _api.put('/service-types/$typeId/specializations',
                              body: {'specializationIds': selected.toList()});

                          if (ctx.mounted) Navigator.pop(ctx);
                          _fetch();
                        },
                        child: const Text('Αποθήκευση'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Τύποι Υπηρεσιών', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _types.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final t = _types[i];
                final name = t['name'] ?? '';
                final defaultVisible = t['isDefaultVisible'] == true;
                final specCount = (t['_count']?['specializations'] ?? 0) as int;
                final serviceCount = (t['_count']?['services'] ?? 0) as int;

                return Card(
                  child: ListTile(
                    title: Text(name, style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text('$specCount ειδικεύσεις • $serviceCount υπηρεσίες'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilterChip(
                          label: Text(defaultVisible ? 'Προεπιλογή' : 'Περιορισμένο',
                              style: TextStyle(fontSize: 11)),
                          selected: defaultVisible,
                          onSelected: (_) => _toggleDefaultVisible(t['id'], defaultVisible),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          onPressed: () => _showEditSheet(Map<String, dynamic>.from(t as Map)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
```

- [ ] **Step 2: Add router entry and admin panel navigation**

In `frontend/lib/config/router.dart`, add the import:

```dart
import '../screens/manage_service_types_screen.dart';
```

Add the route (after the specializations routes, around line 216):

```dart
          GoRoute(
            path: '/admin/service-types',
            builder: (context, state) => const ManageServiceTypesScreen(),
          ),
```

In `frontend/lib/screens/admin_panel_screen.dart`, add a new tile after the specializations tile (after line 167):

```dart
                              _AdminTileData(
                                icon: Icons.category,
                                iconColor: const Color(0xFF0891B2),
                                bgColor: const Color(0xFFECFEFF),
                                title: 'Τύποι Υπηρεσιών',
                                subtitle:
                                    'Διαχείριση τύπων υπηρεσιών & ορατότητας',
                                onTap: () =>
                                    context.push('/admin/service-types'),
                              ),
```

- [ ] **Step 3: Verify it compiles with Flutter**

```bash
cd frontend
flutter analyze
```

Expected: no issues.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/screens/manage_service_types_screen.dart
git add frontend/lib/config/router.dart
git add frontend/lib/screens/admin_panel_screen.dart
git commit -m "feat: add admin screen for managing service types with navigation"
```

---

### Task 9: Frontend — Update CreateServiceScreen

**Files:**
- Modify: `frontend/lib/screens/create_service_screen.dart`

- [ ] **Step 1: Replace specialization picker with service type dropdown**

Change the state variables. Replace:

```dart
  List<dynamic> _allSpecs = [];
  final Set<int> _selectedSpecIds = {};
  Set<int> _originalSpecIds = {};
```

With:

```dart
  List<dynamic> _serviceTypes = [];
  int? _selectedServiceTypeId;
```

- [ ] **Step 2: Update `_loadData` to fetch service types instead of specializations**

In the `_loadData` method, replace the specialization fetch:

```dart
    // Load all specializations
    try {
      final res = await _api.get('/specializations');
      if (res.statusCode == 200 && mounted) {
        _allSpecs = jsonDecode(res.body);
      }
    } catch (_) {}
```

With:

```dart
    // Load all service types
    try {
      final res = await _api.get('/service-types');
      if (res.statusCode == 200 && mounted) {
        _serviceTypes = jsonDecode(res.body);
      }
    } catch (_) {}
```

When editing, replace the visibility loading (lines 114-120):

```dart
          // Pre-select existing visibility specializations
          final vis = svc['visibility'] as List<dynamic>? ?? [];
          for (final v in vis) {
            final specId = v['specializationId'] as int?;
            if (specId != null) _selectedSpecIds.add(specId);
          }
          _originalSpecIds = Set<int>.from(_selectedSpecIds);
```

With:

```dart
          _selectedServiceTypeId = svc['serviceTypeId'] as int?;
```

- [ ] **Step 3: Update the submit method**

In the `_submit` method, add `serviceTypeId` to the data:

```dart
    if (_selectedServiceTypeId != null) data['serviceTypeId'] = _selectedServiceTypeId;
```

And remove the entire visibility update logic for editing (lines 208-225 — the toRemove/toAdd loop). For create, remove the visibility assignment loop (lines 247-255).

- [ ] **Step 4: Update the build method to show service type dropdown**

Replace the specialization chips section (around lines 383-420) with:

```dart
              // ── Service type dropdown ──
              Text('Τύπος Υπηρεσίας', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Επιλέξτε τον τύπο της υπηρεσίας',
                  style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
              const SizedBox(height: 8),
              if (_serviceTypes.isEmpty)
                const Text('Φόρτωση τύπων...', style: TextStyle(color: Color(0xFF6B7280)))
              else
                DropdownButtonFormField<int>(
                  value: _selectedServiceTypeId,
                  decoration: const InputDecoration(
                    labelText: 'Τύπος Υπηρεσίας',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int>(
                      value: null,
                      child: Text('— Κανένας (ορατό σε όλους) —'),
                    ),
                    ..._serviceTypes.map((t) => DropdownMenuItem<int>(
                      value: t['id'] as int,
                      child: Text(t['name'] ?? ''),
                    )),
                  ],
                  onChanged: (v) => setState(() => _selectedServiceTypeId = v),
                ),
              if (_selectedServiceTypeId == null) ...[
                const SizedBox(height: 4),
                Text('Χωρίς τύπο — η υπηρεσία είναι ορατή σε όλα τα μέλη',
                    style: tt.bodySmall?.copyWith(color: Color(0xFFC2410C), fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 20),
```

- [ ] **Step 5: Verify it compiles**

```bash
cd frontend
flutter analyze lib/screens/create_service_screen.dart
```

Expected: no issues.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/screens/create_service_screen.dart
git commit -m "feat: replace specialization picker with service type dropdown in create service screen"
```

---

### Task 10: Frontend — Update Specialization Screens

**Files:**
- Modify: `frontend/lib/screens/manage_specializations_screen.dart`
- Modify: `frontend/lib/screens/specialization_detail_screen.dart`

- [ ] **Step 1: Update manage_specializations_screen.dart**

Replace the import:
```dart
import '../utils/specialization_labels.dart';
```
With:
(remove it — no longer needed)

In `_showCreateDialog`:
Replace:
```dart
    final allCategories = ['trainer', 'tep', 'sanitary_lifeguard'];
    final selectedCategories = <String>{};
```

With:
```dart
    List<dynamic> _allServiceTypes = [];
    final Map<int, bool> _selectedTypeIds = {};

    // Fetch service types inside the dialog
    try {
      final res = await _api.get('/service-types');
      if (res.statusCode == 200) {
        _allServiceTypes = (jsonDecode(res.body) as List<dynamic>)
            .map((t) => Map<String, dynamic>.from(t as Map))
            .toList();
      }
    } catch (_) {}
```

Wait — the dialog is a StatefulBuilder. Let me use a simpler approach. Actually, let me fetch the service types in the main widget state and pass them.

Replace the dialog's missionCategories chips section (lines 157-178) with:

```dart
                  const SizedBox(height: 12),
                  Text('Τύποι Υπηρεσιών',
                      style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  FutureBuilder(
                    future: _api.get('/service-types'),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Text('Φόρτωση...');
                      final res = snapshot.data!;
                      if (res.statusCode != 200) return const Text('Σφάλμα');
                      final types = (jsonDecode(res.body) as List<dynamic>)
                          .map((t) => Map<String, dynamic>.from(t as Map))
                          .toList();
                      return Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: types.map((t) {
                          final typeId = t['id'] as int;
                          final selected = _selectedTypeIds[typeId] == true;
                          return FilterChip(
                            label: Text(t['name'] ?? ''),
                            selected: selected,
                            onSelected: (v) {
                              setS(() {
                                _selectedTypeIds[typeId] = v;
                              });
                            },
                            selectedColor: const Color(0xFFEDE9FE),
                            checkmarkColor: const Color(0xFF7C3AED),
                          );
                        }).toList(),
                      );
                    },
                  ),
```

And in the create body (around line 208), replace:
```dart
                body['missionCategories'] = selectedCategories.toList();
```
With:
```dart
                // Specialization-visibility assignments are done separately via the service types screen
```

- [ ] **Step 2: Update specialization_detail_screen.dart**

Remove the import of `specialization_labels.dart`.

Replace the `allCategories` and selection logic in the edit dialog (around line 78):
```dart
    final allCategories = ['trainer', 'tep', 'sanitary_lifeguard'];
    final existingCats = (_spec!['missionCategories'] as List<dynamic>?)
        ?.map((c) => c.toString())
        .toSet() ?? <String>{};
    final selectedCategories = <String>{...existingCats};
```

With:
```dart
    // Service type visibility is managed via the service types admin screen
```

Replace the missionCategories chips in the edit dialog (around lines 161-177) with a note:
```dart
                  const SizedBox(height: 12),
                  Text('Η ορατότητα τύπων υπηρεσίας ρυθμίζεται από την οθόνη Τύποι Υπηρεσιών',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Color(0xFF6B7280))),
```

In the submit body (around line 214), remove:
```dart
                body['missionCategories'] = selectedCategories.toList();
```

Replace the display section (around lines 550-576) that shows mission categories with service types from the API response:

```dart
              // Show service types this specialization can see
              Builder(builder: (_) {
                final types = (_spec!['serviceTypes'] as List<dynamic>?)
                    ?.map((st) => (st['serviceType'] as Map<String, dynamic>?)?['name'] ?? '')
                    .where((n) => n.isNotEmpty)
                    .toList() ?? [];
                if (types.isEmpty) {
                  return const Text('—',
                      style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)));
                }
                return Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: types.map((name) => Chip(
                    label: Text(name,
                        style: const TextStyle(fontSize: 11)),
                    backgroundColor: const Color(0xFFEDE9FE),
                    side: BorderSide.none,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  )).toList(),
                );
              }),
```

- [ ] **Step 3: Verify it compiles**

```bash
cd frontend
flutter analyze
```

Expected: no issues.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/screens/manage_specializations_screen.dart frontend/lib/screens/specialization_detail_screen.dart
git commit -m "feat: replace missionCategories with service types in specialization screens"
```

---

### Task 11: Frontend — Cleanup

**Files:**
- Delete: `frontend/lib/utils/specialization_labels.dart`
- Modify: `frontend/lib/screens/manage_services_screen.dart`
- Modify: `frontend/lib/screens/services_screen.dart`

- [ ] **Step 1: Delete specialization_labels.dart**

```bash
rm frontend/lib/utils/specialization_labels.dart
```

- [ ] **Step 2: Update manage_services_screen.dart filter logic**

The `_allSpecs` getter (line 622-636) currently iterates `_services[*].visibility[*].specialization`. Since services no longer have a `visibility` array directly, we need to derive specs from `serviceType.specializations`.

Replace the `_allSpecs` getter:

```dart
  List<Map<String, dynamic>> get _allSpecs {
    final seen = <int>{};
    final specs = <Map<String, dynamic>>[];
    for (final svc in _services) {
      final st = svc['serviceType'] as Map<String, dynamic>?;
      if (st == null) continue;
      final specs2 = st['specializations'] as List<dynamic>? ?? [];
      for (final row in specs2) {
        final spec = row['specialization'] as Map<String, dynamic>?;
        if (spec != null) {
          final id = spec['id'] as int;
          if (seen.add(id)) specs.add(spec);
        }
      }
    }
    return specs;
  }
```

Similarly, update the `_filtered` getter specialization filter (around line 92-97):

```dart
    if (_selectedSpecId != null) {
      list = list.where((s) {
        final st = s['serviceType'] as Map<String, dynamic>?;
        if (st == null) return false;
        final specs2 = st['specializations'] as List<dynamic>? ?? [];
        return specs2.any((row) => row['specialization']?['id'] == _selectedSpecId);
      }).toList();
    }
```

- [ ] **Step 3: Update services_screen.dart filter logic**

Replace the `_filteredServices` getter (line 139-146):

```dart
  List<dynamic> get _filteredServices {
    final all = context.read<ServiceProvider>().services;
    if (_selectedSpecId == null) return all;
    return all.where((s) {
      final st = s['serviceType'] as Map<String, dynamic>?;
      if (st == null) return false;
      final specs2 = st['specializations'] as List<dynamic>? ?? [];
      return specs2.any((row) => row['specializationId'] == _selectedSpecId ||
          row['specialization']?['id'] == _selectedSpecId);
    }).toList();
  }
```

Replace the `_countForSpec` method (line 148-153):

```dart
  int _countForSpec(int specId) {
    return context.read<ServiceProvider>().services.where((s) {
      final st = s['serviceType'] as Map<String, dynamic>?;
      if (st == null) return false;
      final specs2 = st['specializations'] as List<dynamic>? ?? [];
      return specs2.any((row) => row['specializationId'] == specId ||
          row['specialization']?['id'] == specId);
    }).length;
  }
```

Replace the `specMap` building logic (lines 226-239) that used `visibility[*].specialization`:

```dart
    final specMap = <int, String>{};
    for (final svc in allServices) {
      final st = svc['serviceType'] as Map<String, dynamic>?;
      if (st == null) continue;
      final specs2 = st['specializations'] as List<dynamic>? ?? [];
      for (final row in specs2) {
        final spec = row['specialization'] as Map<String, dynamic>?;
        if (spec != null) {
          specMap[spec['id'] as int] = spec['name'] as String? ?? '';
        }
      }
    }
```

- [ ] **Step 4: Verify it compiles**

```bash
cd frontend
flutter analyze
```

Expected: no issues.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/utils/specialization_labels.dart
git add frontend/lib/screens/manage_services_screen.dart
git add frontend/lib/screens/services_screen.dart
git commit -m "feat: update service filter logic for new serviceType chain, remove specialization_labels"
```

---

### Task 12: Docker Rebuild and Verify

- [ ] **Step 1: Build the Docker images**

```bash
docker compose build
```

Expected: both backend and frontend build without errors.

- [ ] **Step 2: Start services and verify**

```bash
docker compose up -d
```

- [ ] **Step 3: Run seed**

```bash
docker compose exec backend npm run seed
```

- [ ] **Step 4: Smoke test**

Verify:
- `GET /api/service-types` returns 11 types
- `GET /api/services/my` returns services filtered by user's specializations
- Admin can see ManageServiceTypesScreen
- Creating a service shows the type dropdown
- Specialization detail shows assigned service types

- [ ] **Step 5: Commit**

```bash
git commit -m "chore: final verification after service types overhaul"
```
