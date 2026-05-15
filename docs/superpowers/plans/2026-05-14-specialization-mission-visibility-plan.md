# Specialization Mission Visibility & Seeding — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace 4 English specializations with 6 Greek ones, auto-assign imported services to specializations via mission type, and let admins customize per-specialization mission type visibility.

**Architecture:** A JSON array `missionCategories` on `Specialization` stores category strings (trainer, training, tep, volunteer, sanitary_general, sanitary_lifeguard). During import, `syncServiceVisibility()` resolves mission_type_id → categories, finds matching specializations via Prisma `hasSome`, and rebuilds ServiceVisibility rows. The Zod schema and Flutter dialogs expose these categories as toggles.

**Tech Stack:** Prisma (PostgreSQL JSON column), Express/Zod (backend validation), Flutter (FilterChip toggles)

---

### Task 1: Add missionCategories column to Prisma schema

**Files:**
- Modify: `backend/prisma/schema.prisma:342-361` (Specialization model)

- [ ] **Step 1: Add missionCategories field**

Add inside the `model Specialization` block, after `eamePrefix`:

```prisma
  missionCategories  Json     @default("[]") @map("mission_categories")
```

The full model should read (showing relevant portion):

```prisma
model Specialization {
  id                  Int     @id @default(autoincrement())
  name                String  @unique @db.VarChar(255)
  description         String? @db.Text
  yearlyHours         Int     @default(0) @map("yearly_hours")
  yearlyHoursTraining Int     @default(0) @map("yearly_hours_training")
  hoursTraining       Int     @default(0) @map("hours_training")
  hoursTEP            Int     @default(0) @map("hours_tep")
  eamePrefix          String? @map("eame_prefix") @db.VarChar(8)
  missionCategories   Json    @default("[]") @map("mission_categories")
  rootId              Int?    @map("root_id")

  // ... relations unchanged ...
}
```

- [ ] **Step 2: Run Prisma migration**

```bash
cd backend && npx prisma migrate dev --name add_mission_categories
```

Expected: Creates migration SQL and regenerates Prisma client.

- [ ] **Step 3: Verify Prisma client compiles**

```bash
cd backend && npx prisma generate
```

Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add backend/prisma/schema.prisma backend/prisma/migrations/
git commit -m "feat: add missionCategories JSON column to specializations"
```

---

### Task 2: Replace seed specializations

**Files:**
- Modify: `backend/prisma/seed.ts:64-161` (specializations + assignments + visibility sections)

- [ ] **Step 1: Remove old specialization seed block (lines 64-94) and old visibility block (lines 133-161)**

Delete the four old specialization upserts (First Aid, ALS, Lifeguard, BLS/AED Instructor) and the entire `// ── Service visibility` block.

- [ ] **Step 2: Replace with 6 Greek specializations**

Insert at line 64 (replacing old specialization block):

```ts
  // ── Specializations ───────────────────────────
  const BASE_CATEGORIES = ["training", "volunteer", "sanitary_general"];

  const dokimosSamaritis = await prisma.specialization.upsert({
    where: { name: "Δόκιμος Σαμαρείτης" },
    update: { missionCategories: [...BASE_CATEGORIES, "tep"] },
    create: {
      name: "Δόκιμος Σαμαρείτης",
      description: "Δόκιμος Σαμαρείτης",
      missionCategories: [...BASE_CATEGORIES, "tep"],
    },
  });

  const dokimosNavagosostis = await prisma.specialization.upsert({
    where: { name: "Δόκιμος Ναυαγοσώστης" },
    update: { missionCategories: [...BASE_CATEGORIES, "tep"] },
    create: {
      name: "Δόκιμος Ναυαγοσώστης",
      description: "Δόκιμος Ναυαγοσώστης",
      missionCategories: [...BASE_CATEGORIES, "tep"],
    },
  });

  const samaritis = await prisma.specialization.upsert({
    where: { name: "Σαμαρείτης" },
    update: { missionCategories: BASE_CATEGORIES },
    create: {
      name: "Σαμαρείτης",
      description: "Σαμαρείτης",
      missionCategories: BASE_CATEGORIES,
    },
  });

  const navagosostis = await prisma.specialization.upsert({
    where: { name: "Ναυαγοσώστης" },
    update: { missionCategories: [...BASE_CATEGORIES, "sanitary_lifeguard"] },
    create: {
      name: "Ναυαγοσώστης",
      description: "Ναυαγοσώστης",
      missionCategories: [...BASE_CATEGORIES, "sanitary_lifeguard"],
    },
  });

  const ekpaidytisAB = await prisma.specialization.upsert({
    where: { name: "Εκπαιδευτής Α' Βοηθειών" },
    update: { missionCategories: [...BASE_CATEGORIES, "trainer"] },
    create: {
      name: "Εκπαιδευτής Α' Βοηθειών",
      description: "Εκπαιδευτής Πρώτων Βοηθειών",
      missionCategories: [...BASE_CATEGORIES, "trainer"],
    },
  });

  const ekpaidytisNav = await prisma.specialization.upsert({
    where: { name: "Εκπαιδευτής Ναυαγοσωστικής" },
    update: { missionCategories: [...BASE_CATEGORIES, "trainer", "sanitary_lifeguard"] },
    create: {
      name: "Εκπαιδευτής Ναυαγοσωστικής",
      description: "Εκπαιδευτής Ναυαγοσωστικής",
      missionCategories: [...BASE_CATEGORIES, "trainer", "sanitary_lifeguard"],
    },
  });
```

- [ ] **Step 3: Update UserSpecialization assignments**

Replace the old admin + volunteer assignment blocks (which reference `firstAid.id`, `als.id`, `blsAed.id`, `lifeguard.id`) with:

```ts
  // ── User ↔ Specialization assignments ─────────
  // Admin has Σαμαρείτης, Εκπαιδευτής Α' Βοηθειών, Εκπαιδευτής Ναυαγοσωστικής
  for (const specId of [samaritis.id, ekpaidytisAB.id, ekpaidytisNav.id]) {
    await prisma.userSpecialization.upsert({
      where: { userId_specializationId: { userId: admin.id, specializationId: specId } },
      update: {},
      create: { userId: admin.id, specializationId: specId },
    });
  }
  // Volunteer has Δόκιμος Σαμαρείτης, Σαμαρείτης
  for (const specId of [dokimosSamaritis.id, samaritis.id]) {
    await prisma.userSpecialization.upsert({
      where: { userId_specializationId: { userId: volunteer.id, specializationId: specId } },
      update: {},
      create: { userId: volunteer.id, specializationId: specId },
    });
  }
```

- [ ] **Step 4: Verify seed compiles**

```bash
cd backend && npx tsc --noEmit src/../prisma/seed.ts 2>&1 || true
```

Alternative: just run the seed against a fresh DB:

```bash
cd backend && npm run prisma:reset
```

Expected: Seed completes with ✅ message, no constraint errors.

- [ ] **Step 5: Commit**

```bash
git add backend/prisma/seed.ts
git commit -m "feat: replace English specializations with 6 Greek ones, add missionCategories"
```

---

### Task 3: Add mission-category mapping and visibility sync to import logic

**Files:**
- Modify: `backend/src/lib/mitrooSync.ts:10-14` (add category map after existing constants)
- Modify: `backend/src/lib/mitrooSync.ts:302-414` (add syncServiceVisibility call in syncServices)

- [ ] **Step 1: Add MISSION_CATEGORY_MAP and helper function**

After the existing `SANITARY_MISSION_TYPE_IDS` line (line 14), add:

```ts
const MISSION_CATEGORY_MAP: Record<string, Set<number>> = {
  trainer:           new Set([71, 36, 86, 33, 83]),
  training:          new Set([81]),
  tep:               new Set([85]),
  volunteer:         new Set([56, 57]),
  sanitary_general:  new Set([16]),
  sanitary_lifeguard: new Set([60]),
};

function getCategoriesForMissionType(missionTypeId: number): string[] {
  return Object.entries(MISSION_CATEGORY_MAP)
    .filter(([, ids]) => ids.has(missionTypeId))
    .map(([cat]) => cat);
}
```

- [ ] **Step 2: Add syncServiceVisibility function**

After `remapDefaultHoursByMissionType` (after line 157), add:

```ts
async function syncServiceVisibility(
  serviceId: number,
  missionTypeId: unknown,
): Promise<void> {
  const id = Number(missionTypeId);
  if (!Number.isFinite(id)) return;

  const categories = getCategoriesForMissionType(id);
  if (!categories.length) return;

  const specs = await prisma.specialization.findMany({
    where: {
      missionCategories: { hasSome: categories },
    },
    select: { id: true },
  });

  await prisma.serviceVisibility.deleteMany({ where: { serviceId } });

  if (specs.length) {
    await prisma.serviceVisibility.createMany({
      data: specs.map((s) => ({ serviceId, specializationId: s.id })),
    });
  }
}
```

- [ ] **Step 3: Call syncServiceVisibility from syncServices**

In `syncServices`, after the existing `prisma.service.update(...)` call (line ~375) and the `result.updated++` line, add:

```ts
            await syncServiceVisibility(existing.id, mission.mission_type_id);
```

After the existing `prisma.service.create(...)` call (line ~393) and the `result.created++` line, add:

```ts
            await syncServiceVisibility(newService.id, mission.mission_type_id);
```

Note: for the create branch, capture the `prisma.service.create` result into a variable:

```ts
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

- [ ] **Step 4: Verify compilation**

```bash
cd backend && npx tsc --noEmit
```

Expected: No TypeScript errors.

- [ ] **Step 5: Commit**

```bash
git add backend/src/lib/mitrooSync.ts
git commit -m "feat: auto-assign service visibility based on mission type during import"
```

---

### Task 4: Add missionCategories to specialization routes Zod schema

**Files:**
- Modify: `backend/src/routes/specialization.routes.ts:14-22` (createSchema)

- [ ] **Step 1: Define MISSION_CATEGORIES constant and update createSchema**

Replace the `const createSchema` block with:

```ts
const MISSION_CATEGORIES = [
  "trainer",
  "training",
  "tep",
  "volunteer",
  "sanitary_general",
  "sanitary_lifeguard",
] as const;

const createSchema = z.object({
  name: z.string().min(1).max(255),
  description: z.string().optional(),
  yearlyHours: z.number().int().min(0).optional(),
  yearlyHoursTraining: z.number().int().min(0).optional(),
  hoursTraining: z.number().int().min(0).optional(),
  hoursTEP: z.number().int().min(0).optional(),
  eamePrefix: z.string().max(8).optional().nullable(),
  rootId: z.number().int().optional().nullable(),
  missionCategories: z.array(z.enum(MISSION_CATEGORIES)).optional(),
});
```

- [ ] **Step 2: Verify compilation**

```bash
cd backend && npx tsc --noEmit
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add backend/src/routes/specialization.routes.ts
git commit -m "feat: add missionCategories to specialization create/update schema"
```

---

### Task 5: Add mission category toggles to frontend create dialog

**Files:**
- Modify: `frontend/lib/screens/manage_specializations_screen.dart:66-197` (create dialog)

- [ ] **Step 1: Add state for selected categories in _showCreateDialog**

Inside `_showCreateDialog()`, after the existing local variable declarations (after `int? selectedRoot;`), add:

```dart
    final allCategories = [
      'trainer', 'training', 'tep', 'volunteer',
      'sanitary_general', 'sanitary_lifeguard',
    ];
    final selectedCategories = <String>{};
```

- [ ] **Step 2: Add category name label helper (top-level function)**

At the bottom of the file, add:

```dart
String _categoryLabel(String cat) => switch (cat) {
  'trainer' => 'Εκπαιδευτικές',
  'training' => 'Εκπαίδευση',
  'tep' => 'ΤΕΠ',
  'volunteer' => 'Εθελοντικές',
  'sanitary_general' => 'Υγειονομικές Γενικές',
  'sanitary_lifeguard' => 'Υγειονομικές Ναυαγοσωστικές',
  _ => cat,
};
```

- [ ] **Step 3: Add FilterChip wrap to the dialog, before the closing of the column's children list**

Insert before the closing `];` of the `Column(children: [...])` in the create dialog, after the root dropdown:

```dart
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: allCategories.map((cat) {
                      final selected = selectedCategories.contains(cat);
                      return FilterChip(
                        label: Text(_categoryLabel(cat)),
                        selected: selected,
                        onSelected: (v) {
                          setS(() {
                            if (v) {
                              selectedCategories.add(cat);
                            } else {
                              selectedCategories.remove(cat);
                            }
                          });
                        },
                        selectedColor: const Color(0xFFEDE9FE),
                        checkmarkColor: const Color(0xFF7C3AED),
                      );
                    }).toList(),
                  ),
```

- [ ] **Step 4: Include missionCategories in POST body**

In the create `onPressed` handler, after `body['eamePrefix'] = eamePrefixCtrl.text.trim();`, add:

```dart
                body['missionCategories'] = selectedCategories.toList();
```

- [ ] **Step 5: Verify Flutter compiles**

```bash
cd frontend && flutter analyze lib/screens/manage_specializations_screen.dart
```

Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/screens/manage_specializations_screen.dart
git commit -m "feat: add mission category toggles to specialization create dialog"
```

---

### Task 6: Show and edit mission categories on specialization detail screen

**Files:**
- Modify: `frontend/lib/screens/specialization_detail_screen.dart:60-197` (edit dialog)
- Modify: `frontend/lib/screens/specialization_detail_screen.dart:443-520` (info card)

- [ ] **Step 1: Add category label helper at bottom of file**

```dart
String _specCategoryLabel(String cat) => switch (cat) {
  'trainer' => 'Εκπαιδευτικές',
  'training' => 'Εκπαίδευση',
  'tep' => 'ΤΕΠ',
  'volunteer' => 'Εθελοντικές',
  'sanitary_general' => 'Υγειονομικές Γενικές',
  'sanitary_lifeguard' => 'Υγειονομικές Ναυαγοσωστικές',
  _ => cat,
};
```

- [ ] **Step 2: Show current categories in info card**

In `_infoCard`, after the `_infoRow` for eamePrefix (after line ~512), add:

```dart
              const Divider(height: 24),
              Row(children: [
                const Icon(Icons.visibility, size: 18, color: Color(0xFF6B7280)),
                const SizedBox(width: 10),
                const Expanded(
                    child: Text('Ορατότητα Αποστολών',
                        style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)))),
              ]),
              const SizedBox(height: 8),
              Builder(builder: (_) {
                final cats = (_spec!['missionCategories'] as List<dynamic>?)
                    ?.map((c) => c.toString())
                    .toList() ?? [];
                if (cats.isEmpty) {
                  return const Text('—',
                      style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)));
                }
                return Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: cats.map((c) => Chip(
                    label: Text(_specCategoryLabel(c),
                        style: const TextStyle(fontSize: 11)),
                    backgroundColor: const Color(0xFFEDE9FE),
                    side: BorderSide.none,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  )).toList(),
                );
              }),
```

- [ ] **Step 3: Add mission category editing to the edit dialog**

In the `_edit()` method, after `int? selectedRoot = _spec!['rootId'] as int?;`, add:

```dart
    final allCategories = [
      'trainer', 'training', 'tep', 'volunteer',
      'sanitary_general', 'sanitary_lifeguard',
    ];
    final existingCats = (_spec!['missionCategories'] as List<dynamic>?)
        ?.map((c) => c.toString())
        .toSet() ?? <String>{};
    final selectedCategories = <String>{...existingCats};
```

In the edit dialog's `Column(children: [...])`, add before the closing `];` (after the root dropdown):

```dart
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: allCategories.map((cat) {
                      final selected = selectedCategories.contains(cat);
                      return FilterChip(
                        label: Text(_specCategoryLabel(cat)),
                        selected: selected,
                        onSelected: (v) {
                          setS(() {
                            if (v) {
                              selectedCategories.add(cat);
                            } else {
                              selectedCategories.remove(cat);
                            }
                          });
                        },
                        selectedColor: const Color(0xFFEDE9FE),
                        checkmarkColor: const Color(0xFF7C3AED),
                      );
                    }).toList(),
                  ),
```

In the edit dialog's save handler, after `body['eamePrefix'] = eamePrefixCtrl.text.trim();`, add:

```dart
                body['missionCategories'] = selectedCategories.toList();
```

- [ ] **Step 4: Verify Flutter compiles**

```bash
cd frontend && flutter analyze lib/screens/specialization_detail_screen.dart
```

Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/specialization_detail_screen.dart
git commit -m "feat: show and edit mission category visibility on specialization detail"
```

---

### Task 7: Integration verification

**Files:**
- None (verification only)

- [ ] **Step 1: Reset DB and seed**

```bash
cd backend && npm run prisma:reset
```

Expected: Seeds 6 Greek specializations with correct missionCategories. Verify with:

```bash
cd backend && npx prisma studio
```

Check `specializations` table — confirm 6 rows with correct names and mission_categories JSON arrays.

- [ ] **Step 2: Start backend, test API**

```bash
cd backend && npm run dev
```

Test the API:

```bash
curl -s http://localhost:4000/api/specializations | head -c 500
```

Expected: Returns 6 specializations with `missionCategories` arrays.

- [ ] **Step 3: Start frontend, test UI**

```bash
cd frontend && flutter run -d chrome
```

Navigate to Admin → Διαχείριση Ειδικεύσεων:
- Click "+" to create a new specialization — verify category chips appear
- Click an existing specialization — verify categories shown in info card
- Click edit — verify chips pre-selected and editable

- [ ] **Step 4: Commit any final adjustments**

```bash
git status
git add -A
git commit -m "chore: final integration verification"
```
