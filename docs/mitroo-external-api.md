# Original Mitroo External API Reference

Documentation for all HTTP endpoints on `mitroo.redcross.gr` that the Mitroo backend communicates with via `MitrooClient` (`backend/src/lib/mitrooClient.ts`) and orchestrated by `mitrooSync.ts`.

The external system is a PHP/CodeIgniter application — it has no REST API. All data exchange is done through HTML form submissions (POST with `application/x-www-form-urlencoded`) and XHR JSON endpoints. Authentication is session-based (cookies + CSRF token).

---

## Authentication

### Session Model

All requests must carry a `Cookie` header with the session cookie (`rccrm_app_sessions`). Write operations additionally require a CSRF token (`rccrmtk`) obtained by scraping the login page HTML.

---

### `GET /index.php/auth/login`

Fetch the login page to extract the CSRF token.

**Response:** HTML page containing:
```html
<input name="rccrmtk" value="<csrf_token>">
```

---

### `POST /index.php/auth/login`

Submit login credentials.

**Content-Type:** `application/x-www-form-urlencoded`

| Field | Type | Description |
|-------|------|-------------|
| `identity` | string | Username (email) |
| `password` | string | Password |
| `rccrmtk` | string | CSRF token from the login page |
| `remember` | string | `"1"` |

**Success:** Response sets `rccrm_app_sessions` cookie. Absence of this cookie means login failed.

---

### `GET /index.php/auth/forgot_password`

Fetch the forgot-password page to extract the CSRF token.

**Response:** HTML page containing `<input name="rccrmtk" ...>`.

---

### `POST /index.php/auth/forgot_password`

Trigger a password reset email in the external system.

**Content-Type:** `application/x-www-form-urlencoded`

| Field | Type | Description |
|-------|------|-------------|
| `identity` | string | Email address |
| `rccrmtk` | string | CSRF token |
| `submit` | string | `"Υποβολή"` |

**Success:** HTTP 200.

---

### `GET /index.php/auth/profile`

Fetch the logged-in user's profile page (HTML scrape).

**Headers required:** `Cookie`

**Scraped fields:**

| Field | Source in HTML |
|-------|----------------|
| `eame` | Pattern `[A-ZΑ-Ω]\d{5}\/\d{1,2}\/\d{2}` |
| `email` | Standard email regex |
| `forename` / `surname` | `.sidebar-username` div text |
| `phonePrimary` / `phoneSecondary` | `Τηλέφωνα` section, pipe-separated |
| `birthDate` | `Ημερομηνία γέννησης` section, `DD-MM-YYYY` |
| `address` | `Διεύθυνση` section |
| `specializationNames` | Flex divs with `&nbsp;` delimiter in profile |

---

## Volunteer / Member Endpoints

All volunteer endpoints are XHR (`X-Requested-With: XMLHttpRequest`) and return JSON.

---

### `GET /index.php/ajaxmember/grid_get_volunteers`

Fetch all volunteers (single page, no pagination params).

**Response:**
```json
{ "count": "N", "result": [ ExternalVolunteer, ... ] }
```

or a plain array `[ExternalVolunteer, ...]`.

**`ExternalVolunteer` shape:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | string \| number | External member ID |
| `first_name` | string | Given name |
| `last_name` | string | Family name |
| `registration_code` | string? | EAME registration code |
| `member_status` | string? | Membership status |
| `rank_id` | string? | Rank identifier |
| `member_department` | string? | Department name |
| `member_rank` | string? | Rank name |

---

### `GET /index.php/ajaxmember/grid_get_volunteers/?$count=true&$skip=N&$top=M`

Paginated volunteer fetch (used by `findVolunteerByEmail` and `findVolunteerByCode`).

**Query params:**

| Param | Description |
|-------|-------------|
| `$count` | `"true"` |
| `$skip` | Records to skip (page offset) |
| `$top` | Page size (200 per page) |

**Response:** Same shape as above. A page with fewer rows than `$top` signals the last page.

**Safety limit:** 200 pages maximum.

---

## Mission / Service Endpoints

Missions correspond to local `Service` records. Each mission contains one or more shifts (also mapped to `Service`).

---

### `GET /index.php/ajaxdptadmin/GridGetMissions`

Fetch all missions for the logged-in department admin. Also used to verify admin access (non-admins receive an HTML redirect instead of JSON).

**Response:**
```json
{ "result": [ ExternalMission, ... ] }
```
or a plain array.

**`ExternalMission` shape:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | number | Mission ID |
| `title` | string? | Mission title |
| `start_date` | string? | `"YYYY-MM-DD"` |
| `end_date` | string? | `"YYYY-MM-DD"` |
| `location_text` | string? | Location description |
| `mission_type_id` | string \| number? | Mission type identifier |

---

### `GET /index.php/ajaxdptadmin/GridGetMissions/open/?$count=true&$skip=N&$top=M`

Paginated fetch of open missions only.

**Query params:** Same as volunteer pagination.

**Safety limit:** 200 pages maximum.

---

### `GET /index.php/ajaxdptadmin/mission_shifts_by_mission_with_members/{missionId}`

Fetch all shifts (and their members) for a specific mission.

**Path param:** `missionId` — integer mission ID.

**Response:**
```json
{
  "status": 1,
  "mission_shifts": {
    "count": N,
    "data": [ ExternalShift, ... ]
  }
}
```

**`ExternalShift` shape:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | number \| string | Shift ID |
| `mission_id` | number \| string | Parent mission ID |
| `shift_start_date` | string? | `"YYYY-MM-DD HH:mm:ss"` |
| `shift_end_date` | string? | `"YYYY-MM-DD HH:mm:ss"` |
| `total_participants` | number \| string? | Max participants |
| `title` | string? | Shift title |
| `hours_lifeguard` | number \| string? | Hours (lifeguard) |
| `hours_sanitary` | number \| string? | Hours (sanitary/general) |
| `hours_training` | number \| string? | Hours (training) |
| `hours_retraining` | number \| string? | Hours (retraining/trainers) |
| `hours_tep` | number \| string? | Hours (TEP) |
| `hours_volunteering` | number \| string? | Hours (volunteering) |

---

### `POST /index.php/dptadmin/newmission`

Create a new mission. The external system does not return the new mission ID in the response body; the ID is inferred from a `Refresh` header redirect, response HTML, or a before/after snapshot comparison.

**Content-Type:** `application/x-www-form-urlencoded` (not XHR)

| Field | Type | Description |
|-------|------|-------------|
| `title` | string | Mission title |
| `start_date` | string | `"YYYY-MM-DD"` |
| `end_date` | string | `"YYYY-MM-DD"` |
| `location_text` | string | Location description |
| `location_url` | string | Location URL |
| `comments` | string | Notes |
| `mission_type_id` | string | Numeric type ID (default `"16"`) |
| `rccrmtk` | string | CSRF token |
| `submit` | string | `"ΔΗΜΙΟΥΡΓΙΑ"` |

**ID detection strategy (in order):**
1. `Refresh` response header containing `/mission/{id}`
2. Response body pattern `/mission/{id}` or `mission_id" value="{id}"`
3. After-snapshot diff against `fetchOpenMissions()` / `fetchMissions()` — up to 6 attempts with exponential backoff (500 ms, 1 s, …)
4. Relaxed title-only match (case-insensitive)
5. Newest unseen mission in the all-missions list

---

### `POST /ajaxdptadmin/MissionAddShift`

Create a shift within an existing mission.

**Content-Type:** `application/x-www-form-urlencoded`

| Field | Type | Description |
|-------|------|-------------|
| `mission_id` | string | Parent mission ID |
| `mission_type_id` | string | Type ID (default `"16"`) |
| `shift_start_date` | string | `"YYYY-MM-DD HH:mm"` |
| `shift_end_date` | string | `"YYYY-MM-DD HH:mm"` |
| `admin_member_id` | string | `"0"` |
| `total_participants` | string | Max participants (default `"1"`) |
| `comments` | string | Notes |
| `hours_lifeguard` | string | Hours (default `"0"`) |
| `hours_sanitary` | string | Hours (default `"0"`) |
| `hours_training` | string | Hours (default `"0"`) |
| `hours_retraining` | string | Hours (default `"0"`) |
| `hours_tep` | string | Hours (default `"0"`) |
| `hours_volunteering` | string | Hours (default `"0"`) |
| `rccrmtk` | string | CSRF token |

**Response:**
```json
{ "new_shift_id": 123 }
```

---

### `POST /ajaxdptadmin/MissionCancelShift`

Cancel a specific shift. Also sends a notification email to enrolled members.

**Content-Type:** `application/x-www-form-urlencoded`

| Field | Type | Description |
|-------|------|-------------|
| `mission_id` | string | Mission ID |
| `shift_id` | string | Shift ID |
| `email_message` | string | Notification text (Greek, e.g. `"Η βάρδια X έχει ακυρωθεί."`) |
| `rccrmtk` | string | CSRF token |

**Success:** HTTP 200.

---

### `POST /ajaxdptadmin/MissionCancel`

Cancel an entire mission (sets status to `7`).

**Content-Type:** `application/x-www-form-urlencoded`

| Field | Type | Description |
|-------|------|-------------|
| `mission_id` | string | Mission ID |
| `new_status_id` | string | `"7"` (cancelled) |
| `rccrmtk` | string | CSRF token |

**Success:** HTTP 200.

---

### `POST /ajaxdptadmin/MissionChangeStatus`

Change a mission's status.

**Content-Type:** `application/x-www-form-urlencoded`

| Field | Type | Description |
|-------|------|-------------|
| `mission_id` | string | Mission ID |
| `new_status_id` | string | Target status ID (e.g. `"22"` = open/published) |
| `rccrmtk` | string | CSRF token |

**Response:**
```json
{ "status": 1 }
```
`status !== 1` is treated as a failure.

**Known status IDs:**

| ID | Meaning |
|----|---------|
| `7` | Cancelled |
| `22` | Open / published (used after `createMission` + `createShift`) |

---

## Shift Application Endpoints

Shift applications correspond to local `UserService` records (the `requested | accepted | rejected` enrollment of a user in a service).

---

### `GET /index.php/ajaxdptadmin/grid_get_shiftapplications/?$count=true&$skip=N&$top=M`

Paginated fetch of all shift applications for the department.

**Query params:** Same as volunteer pagination (500 per page, max 100 pages).

**Response:**
```json
{ "count": "N", "result": [ ExternalShiftApplication, ... ] }
```

**`ExternalShiftApplication` shape:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | number \| string | Application ID |
| `mission_id` | number \| string? | Parent mission ID |
| `mission_shift_id` | number \| string? | Shift ID |
| `member_id` | number \| string? | External volunteer ID |
| `application_status_id` | number \| string? | Status (see below) |
| `hours_volunteering` | number \| string? | |
| `hours_sanitary` | number \| string? | |
| `hours_training` | number \| string? | |
| `hours_retraining` | number \| string? | |
| `hours_tep` | number \| string? | |
| `hours_lifeguard` | number \| string? | |

**Application status IDs:**

| ID | Local mapping |
|----|---------------|
| `1` | `requested` (ΑΡΧΙΚΗ) |
| `3` | `accepted` |
| `4` | `rejected` |
| other | Ignored (e.g. member-cancelled) |

---

### `GET /ajaxdptadmin/ShiftApplicationStatusChange/{applicationId}/{statusId}`

Change an application's status via XHR GET.

**Path params:**

| Param | Description |
|-------|-------------|
| `applicationId` | Application ID |
| `statusId` | `3` = approve, `4` = reject/cancel |

**Response:**
```json
{ "status": 1 }
```

**Used by:**
- `approveShiftApplication(applicationId)` → status `3`
- `cancelShiftApplication(applicationId)` → status `4` (admin-initiated)

---

### `POST /ajaxcommon/mission_shifts_application_add/0/1/{memberId}`

Add a volunteer to a shift (creates a new application on their behalf).

**Path param:** `memberId` — external volunteer ID.

**Content-Type:** `application/x-www-form-urlencoded`

| Field | Type | Description |
|-------|------|-------------|
| `mission_shift_id` | string | Shift ID |
| `mission_application_comments` | string | Empty string |
| `rccrmtk` | string | CSRF token |

**Response:**
```json
{ "status": 1, "application_id": 456 }
```

`status !== 1` typically means the user already has an application for this shift.

---

### `POST /ajaxcommon/member_shift_application_cancel`

Member-initiated cancellation of their own shift application.

**Content-Type:** `application/x-www-form-urlencoded`

| Field | Type | Description |
|-------|------|-------------|
| `shift_application_id` | string | Application ID |
| `rccrmtk` | string | CSRF token |

**Response:**
```json
{ "status": 1 }
```

**Used by:** `writeBackUnenroll` (when the user withdraws their own enrollment).

---

### `POST /ajaxdptadmin/ShiftApplicationUpdateHours`

Update the recorded hours for a specific application.

**Content-Type:** `application/x-www-form-urlencoded`

| Field | Type | Description |
|-------|------|-------------|
| `mission_id` | string | Mission ID |
| `shift_application_id` | string | Application ID |
| `popup_hours_volunteering` | string | Hours (default `"0"`) |
| `popup_hours_sanitary` | string | Hours (default `"0"`) |
| `popup_hours_training` | string | Hours (default `"0"`) |
| `popup_hours_retraining` | string | Hours (default `"0"`) |
| `popup_hours_tep` | string | Hours (default `"0"`) |
| `popup_hours_lifeguard` | string | Hours (default `"0"`) |
| `also_change_application_status` | string | `"0"` |
| `rccrmtk` | string | CSRF token |

**Response:**
```json
{ "status": true }
```

---

## Mission Type ID → Hours Category Mapping

The external system's `mission_type_id` controls which hour bucket is populated locally. `syncServices` uses this mapping to set the correct `defaultHours*` fields on `Service`.

| External `mission_type_id` | Local hours field | Description |
|--------------------------|-------------------|-------------|
| `71, 36, 86, 33, 83` | `defaultHoursTrainers` | Trainer hours |
| `81` | `defaultHoursTraining` | Training hours |
| `85` | `defaultHoursTEP` | TEP hours |
| `56, 57` | `defaultHoursVol` | Volunteering hours |
| `60, 16` | `defaultHours` | Sanitary/general hours |
| (anything else) | Preserved as-is | No remapping |

---

## Write-Back Triggers (Local → External)

These are the local events that fire write-back calls to the external system. All are **fire-and-forget** — failures are logged but do not block the local operation.

| Local event | Write-back function | External calls |
|------------|---------------------|----------------|
| Service created (no `externalShiftId`) | `writeBackNewService` | `createMission` → `createShift` → `changeMissionStatus(22)` |
| Service deleted | `writeBackServiceDelete` | `cancelShift`; then `cancelMission` if no other shifts remain |
| User enrollment accepted | `writeBackAssignment` | `addUserToShift` (if needed) → `approveShiftApplication` → `updateApplicationHours` |
| User enrollment rejected / removed | `writeBackRejection` | `cancelShiftApplication` |
| User self-enrolls (status = `requested`) | `writeBackEnrollmentRequest` | `addUserToShift` → saves `externalApplicationId` |
| User self-unenrolls | `writeBackUnenroll` | `cancelMemberShiftApplication` (member-initiated) |
| User hours updated | `writeBackHoursUpdate` | `updateApplicationHours` |

Write-backs are skipped if:
- The service has no `externalShiftId` / `externalMissionId`
- The department's `syncEnabled` flag is `false`
- The user has no `externalId`

---

## Inbound Sync Triggers

### Hourly cron (`autoSyncAllDepartments`)

Runs every hour in `server.ts`. Calls `syncServices(departmentId)` for every department that has a `DepartmentSyncConfig` row (i.e. any department whose credentials have been saved).

### On admin/missionAdmin login (`autoUpdateSyncConfig`)

Triggered when an external Mitroo credential login succeeds. Saves/updates the department's sync credentials (encrypted) and immediately fires `syncServices`.

### On new external-user login (`syncUserApplications` + `syncUserDepartments`)

When a user with an `externalId` logs in for the first time, their existing shift applications are pulled from the external system and their department memberships are verified/created.

### Manual API endpoints (sync.routes.ts, mounted at `/api/departments`)

| Method | Path | Function called |
|--------|------|----------------|
| `POST` | `/:id/sync/users` | `syncUsers(departmentId)` |
| `POST` | `/:id/sync/services` | `syncServices(departmentId)` |
| `POST` | `/:id/sync/applications` | `syncShiftApplications(departmentId)` |
| `GET` | `/:id/sync/config` | Returns `DepartmentSyncConfig` (no password) |
| `POST` | `/:id/sync/config` | Saves credentials, sets `syncEnabled` |
| `GET` | `/:id/sync/status` | Returns `lastUserSyncAt`, `lastServiceSyncAt`, `lastSyncStatus`, `lastSyncError` |

---

## Environment

| Variable | Default | Description |
|----------|---------|-------------|
| `MITROO_EXTERNAL_BASE_URL` | `https://mitroo.redcross.gr` | Base URL of the external Mitroo system |
| `MITROO_EXTERNAL_DEBUG` | `"0"` | Set to `"1"` to enable verbose client logging |
