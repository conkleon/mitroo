# Victim/Incident Management — Design Spec
_Date: 2026-05-16_

## Overview

Add a first-class victim/patient management module to Mitroo. Rescuers can log incidents (victims) during or outside of a service, record timestamped vital signs, and log treatments with optional references to inventory items. The feature is accessible from the services screen (primary entry point) and from a dedicated global list screen in the nav rail.

---

## 1. Data Model

### 1.1 Schema changes (`backend/prisma/schema.prisma`)

Add three new models. All IDs are `Int` (auto-increment), consistent with the rest of the schema.

#### `Victim`

```prisma
model Victim {
  id        Int    @id @default(autoincrement())

  // Personal information
  name            String
  age             Int?
  dateOfBirth     DateTime? @map("date_of_birth")
  gender          String?   // 'male' | 'female' | 'other' | 'unknown'
  address         String?   @db.Text
  city            String?   @db.VarChar(255)
  postalCode      String?   @map("postal_code") @db.VarChar(20)
  telephone       String?   @db.VarChar(30)
  emergencyContact String?  @map("emergency_contact") @db.VarChar(255)
  emergencyPhone  String?   @map("emergency_phone") @db.VarChar(30)

  // Medical assessment
  chiefComplaint  String?   @map("chief_complaint") @db.Text
  allergies       String?   @db.Text
  medications     String?   @db.Text
  medicalHistory  String?   @map("medical_history") @db.Text

  // GCS (Glasgow Coma Scale)
  gcsEye          Int?      @map("gcs_eye")     // 1–4
  gcsVerbal       Int?      @map("gcs_verbal")  // 1–5
  gcsMotor        Int?      @map("gcs_motor")   // 1–6
  gcsTotal        Int?      @map("gcs_total")   // 3–15 (computed, stored for query convenience)

  // AVPU
  avpu            String?   // 'ALERT' | 'VOICE' | 'PAIN' | 'UNRESPONSIVE'

  // Location
  latitude        Float?
  longitude       Float?
  locationNotes   String?   @map("location_notes") @db.Text

  // Optional service link
  serviceId       Int?      @map("service_id")

  // Notes
  notes           String?   @db.Text

  // Finalization
  isFinalized     Boolean   @default(false) @map("is_finalized")
  finalizedAt     DateTime? @map("finalized_at")
  finalizedById   Int?      @map("finalized_by_id")

  // Metadata
  createdById     Int       @map("created_by_id")
  createdAt       DateTime  @default(now()) @map("created_at")
  updatedAt       DateTime  @updatedAt @map("updated_at")

  // Relations
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
```

#### `VitalSign`

```prisma
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
  painScore       Int?     @map("pain_score")   // 0–10

  measuredAt      DateTime @default(now()) @map("measured_at")
  notes           String?  @db.Text
  measuredBy      String?  @map("measured_by") @db.VarChar(255)

  victim          Victim   @relation(fields: [victimId], references: [id], onDelete: Cascade)

  @@index([victimId])
  @@index([measuredAt])
  @@map("vital_signs")
}
```

#### `Treatment`

```prisma
model Treatment {
  id              Int      @id @default(autoincrement())
  victimId        Int      @map("victim_id")

  action          String   @db.Text
  materialUsed    String?  @map("material_used") @db.Text
  notes           String?  @db.Text

  // Item reference (optional — from service kit or user's assigned items)
  itemId          Int?     @map("item_id")
  consumedNote    String?  @map("consumed_note") @db.Text  // e.g. "εξαντλήθηκε", "μερικώς χρησιμοποιήθηκε"

  performedAt     DateTime @default(now()) @map("performed_at")
  performedBy     String?  @map("performed_by") @db.VarChar(255)

  victim          Victim   @relation(fields: [victimId], references: [id], onDelete: Cascade)
  item            Item?    @relation(fields: [itemId], references: [id], onDelete: SetNull)

  @@index([victimId])
  @@index([performedAt])
  @@map("treatments")
}
```

### 1.2 Relations added to existing models

- `User`: add `createdVictims Victim[] @relation("VictimCreatedBy")` and `finalizedVictims Victim[] @relation("VictimFinalizedBy")`
- `Service`: add `victims Victim[]`
- `Item`: add `treatments Treatment[]`

---

## 2. Backend

### 2.1 File

`backend/src/routes/victim.routes.ts` — registered in `app.ts` as `/api/victims`.

### 2.2 Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/api/victims` | authenticate | List accessible victims. Optional `?serviceId=` filter. |
| `POST` | `/api/victims` | authenticate | Create a new victim. |
| `GET` | `/api/victims/:id` | authenticate | Get single victim with vitals + treatments. |
| `PATCH` | `/api/victims/:id` | authenticate | Update victim fields. Blocked if finalized (unless admin). |
| `DELETE` | `/api/victims/:id` | authenticate | Delete. Blocked if finalized (unless admin). |
| `POST` | `/api/victims/:id/finalize` | authenticate | Finalize record. Only creator or admin/missionAdmin. |
| `POST` | `/api/victims/:id/vital-signs` | authenticate | Add a vital sign measurement. |
| `DELETE` | `/api/victims/:id/vital-signs/:vsId` | authenticate | Delete a vital sign. Not allowed if finalized (unless admin). |
| `POST` | `/api/victims/:id/treatments` | authenticate | Add a treatment entry. |
| `DELETE` | `/api/victims/:id/treatments/:tId` | authenticate | Delete a treatment. Not allowed if finalized (unless admin). |

### 2.3 Access rules (enforced per handler)

**Read access:** user can read a victim if any of:
- They are the creator (`createdById == req.user.id`)
- They are a global admin (`user.isAdmin`)
- They are a missionAdmin in the service's department
- The victim has a `serviceId` and the user has an `accepted` `UserService` record for that service

**Write/delete access:**
- Creator can edit/delete their own records while not finalized
- Admins and missionAdmins can always edit/delete
- Once `isFinalized = true`, only admins/missionAdmins can modify or delete

**Finalize:** only the creator or admin/missionAdmin can call the finalize endpoint.

### 2.4 Item picker (frontend-resolved)

No dedicated endpoint needed. The frontend fetches:
1. Items assigned to the linked service via existing `GET /api/services/:id` (which includes `itemServices`)
2. Items assigned to the current user via `GET /api/auth/me/profile` (which includes `equipment`)

These two lists are merged and deduplicated client-side in the treatment form.

---

## 3. Frontend

### 3.1 Provider

`frontend/lib/providers/victim_provider.dart`

`VictimProvider extends ChangeNotifier`:
- `List<Map<String, dynamic>> victims` — cached list
- `bool loading`
- `fetchVictims({int? serviceId})` — calls `GET /api/victims?serviceId=`
- `createVictim(Map<String, dynamic> data)` → returns error string or null
- `updateVictim(int id, Map<String, dynamic> data)` → returns error string or null
- `deleteVictim(int id)` → returns error string or null
- `finalizeVictim(int id)` → returns error string or null
- `addVitalSign(int victimId, Map<String, dynamic> data)` → returns error string or null
- `deleteVitalSign(int victimId, int vsId)` → returns error string or null
- `addTreatment(int victimId, Map<String, dynamic> data)` → returns error string or null
- `deleteTreatment(int victimId, int tId)` → returns error string or null

Registered in `main.dart` alongside other providers.

### 3.2 Screens

#### `victims_screen.dart` — Global list
- New nav rail destination: icon `Icons.personal_injury_outlined`, label "Περιστατικά"
- Positioned between Services and Items in the nav rail
- Card list of all accessible victims, sorted by `createdAt` descending
- Each card: victim name, age, service name (if linked), timestamp, finalization lock icon
- Filter row: "Όλα" / "Ανοιχτά" / "Οριστικοποιημένα"
- FAB: `Icons.add` → navigates to `create_victim_screen.dart` (no pre-filled serviceId)

#### `create_victim_screen.dart` — Multi-step form
4 steps with a `Stepper` widget or custom step indicator:

1. **Στοιχεία** — name (required), age, date of birth, gender (dropdown), address, city, postal code, telephone, emergency contact + phone
2. **Ιατρικό ιστορικό** — chief complaint, allergies, medications, medical history
3. **Αξιολόγηση** — GCS eye/verbal/motor sliders (total auto-computed and displayed), AVPU radio buttons, location notes, optional service picker (shows the user's accepted services as a dropdown)
4. **Επισκόπηση** — read-only summary of all fields before submit

Navigation: "Επόμενο" / "Προηγούμενο" buttons. Submit on step 4 calls `VictimProvider.createVictim()`.

Accepts an optional `int? prefilledServiceId` parameter — when navigated from a service detail, step 3's service picker is pre-filled and locked.

#### `victim_detail_screen.dart` — Detail view
- Full victim info display (all fields, organised in sections matching the form steps)
- Finalization banner if `isFinalized == true` (lock icon + who/when finalized)
- Two expandable sections:
  - **Ζωτικά Σημεία** — timeline list of `VitalSign` entries with timestamp. "+" button opens an `AlertDialog` form to add a new measurement.
  - **Θεραπείες** — list of `Treatment` entries. "+" button opens an `AlertDialog` form: action (required), material used, item picker (service items + user items), consumed note, performed by, timestamp.
- Bottom action bar (creator + admins only, not finalized):
  - "Επεξεργασία" → back to a pre-filled edit form
  - "Οριστικοποίηση" → confirmation dialog → calls `finalizeVictim()`
  - Admin-only: "Διαγραφή"

### 3.3 Services screen FAB change

In `services_screen.dart`, the existing FAB logic:

```dart
floatingActionButton: (auth.isAdmin || auth.isMissionAdmin)
    ? FloatingActionButton(...)  // "Νέα υπηρεσία"
    : null,
```

Changes to:

- **Regular users** (not admin, not missionAdmin): single FAB with `Icons.personal_injury` and tooltip "Καταγραφή Περιστατικού" → navigates to `create_victim_screen.dart`
- **missionAdmins / global admins**: SpeedDial pattern — a single main FAB that expands to reveal two options:
  - "Καταγραφή Περιστατικού" (icon: `Icons.personal_injury`) → create victim
  - "Νέα υπηρεσία" (icon: `Icons.add`) → create service
  - Implement with a simple custom widget (animated expand/collapse + overlay backdrop), no external package needed

### 3.4 Service detail screen

`service_detail_screen.dart` — add a "Περιστατικά" section at the bottom:
- Fetches victims for this service via `VictimProvider.fetchVictims(serviceId: id)`
- Shows a compact card list
- "+" button navigates to `create_victim_screen.dart` with `prefilledServiceId` set

### 3.5 Router

Add routes in `config/router.dart`:
- `/victims` → `VictimsScreen`
- `/victims/create` → `CreateVictimScreen` (optional `serviceId` query param)
- `/victims/:id` → `VictimDetailScreen`

---

## 4. Navigation

Nav rail order (updated):
1. Services ← existing
2. **Περιστατικά** ← new
3. Items
4. Vehicles
5. Chat
6. (admin panel, etc.)

---

## 5. Out of scope

- Push notifications for new victims
- Victim export / PDF generation
- Photo attachments on victims
- Editing vital signs or treatments after creation (delete + re-add is the flow)
