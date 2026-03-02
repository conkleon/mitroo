# Mitroo – Architecture Overview

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Database | PostgreSQL 16 |
| Cache | Redis 7 |
| ORM | Prisma 6 |
| Backend | Node.js 20 + Express 4 + TypeScript |
| Frontend | Flutter (Web) with Provider state management |

## Folder Layout

```
mitroo/
├── .env                      # Shared env vars (backend + frontend)
├── .env.example              # Template for .env
├── .gitignore
├── docker-compose.yml        # Production – full stack, private network
├── docker-compose.dev.yml    # Dev – databases only, ports exposed to host
├── backend/
│   ├── Dockerfile
│   ├── package.json
│   ├── tsconfig.json
│   ├── prisma/
│   │   ├── schema.prisma     # Domain schema (Departments, Services, Items, Vehicles, etc.)
│   │   └── seed.ts           # Seed data
│   └── src/
│       ├── server.ts         # Entry point
│       ├── app.ts            # Express app setup + static /uploads
│       ├── lib/
│       │   ├── prisma.ts     # Prisma client singleton
│       │   └── redis.ts      # Redis client singleton
│       ├── middleware/
│       │   ├── auth.ts       # JWT authenticate + requireAdmin
│       │   ├── errorHandler.ts
│       │   └── notFound.ts
│       └── routes/
│           ├── health.routes.ts
│           ├── auth.routes.ts        # Login/register (ename-based)
│           ├── user.routes.ts        # CRUD + specializations
│           ├── department.routes.ts  # CRUD + member management
│           ├── service.routes.ts     # CRUD + enrollment + visibility
│           ├── item.routes.ts        # CRUD + container hierarchy + service assignment
│           ├── vehicle.routes.ts     # CRUD + vehicle logs (meter tracking)
│           ├── specialization.routes.ts  # CRUD (hierarchical)
│           └── file.routes.ts        # Upload/list/delete (multer, polymorphic)
├── frontend/
│   ├── Dockerfile
│   ├── nginx.conf            # Nginx config (SPA fallback + API proxy)
│   ├── pubspec.yaml
│   ├── web/
│   │   └── index.html
│   └── lib/
│       ├── main.dart
│       ├── config/
│       │   ├── api_config.dart
│       │   └── router.dart   # GoRouter with auth guard
│       ├── services/
│       │   └── api_client.dart
│       ├── providers/
│       │   ├── auth_provider.dart       # ename-based login, isAdmin
│       │   ├── department_provider.dart
│       │   ├── service_provider.dart
│       │   ├── item_provider.dart
│       │   └── vehicle_provider.dart
│       └── screens/
│           ├── login_screen.dart      # Username login
│           ├── shell_screen.dart      # Nav rail (5 destinations)
│           ├── dashboard_screen.dart  # Summary cards
│           ├── departments_screen.dart
│           ├── services_screen.dart
│           ├── items_screen.dart
│           └── vehicles_screen.dart
└── copilot-history/
    ├── README.md
    ├── CHANGELOG.md
    ├── NEXT_STEPS.md
    └── ARCHITECTURE.md       # (this file)
```

## Data Model (Prisma)

### Users
- Int auto-increment PK, ename (unique username), bcrypt password, forename/surname
- `isAdmin` boolean for system-level admin
- Optional: email, address, phones, birthDate, imagePath, extraInfo

### Department → UserDepartment (pivot)
- Departments group users and services
- UserDepartment assigns per-department roles: missionAdmin | itemAdmin | volunteer

### Service → UserService (enrollment pivot)
- Services belong to a Department; have default hours fields
- UserService tracks enrollment status (requested | accepted | rejected) and actual hours
- ServiceVisibility controls which specializations can see which services

### Item (self-referencing containment)
- Items can be containers holding other items (containedById self-reference)
- ItemService assigns items to services (by a user, with timestamp)

### Specialization (hierarchical)
- Self-referencing via rootId for parent/child specialization trees
- UserSpecialization tracks which users have which specializations

### Vehicle → VehicleLog
- Vehicles have meterType (km | hours) and currentMeter tracking
- VehicleLogs record usage: start/end times, meter readings, optional service link

### FileAttachment (polymorphic)
- Single table with nullable FKs to User, Department, Service, Item, Vehicle
- Stores fileName, filePath, mimeType, fileSize

## API Routes

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/health` | No | Health check (DB + Redis) |
| POST | `/api/auth/register` | No | Register (ename, password, forename, surname) |
| POST | `/api/auth/login` | No | Login (ename + password) → JWT |
| GET | `/api/auth/me` | Yes | Current user + department memberships |
| GET | `/api/users` | Yes | List users |
| GET | `/api/users/:id` | Yes | Get user detail |
| PATCH | `/api/users/:id` | Yes | Update user |
| DELETE | `/api/users/:id` | Admin | Delete user |
| GET/POST | `/api/users/:id/specializations` | Yes | User specializations |
| GET | `/api/departments` | Yes | List departments |
| POST | `/api/departments` | Admin | Create department |
| GET | `/api/departments/:id` | Yes | Department detail + members + services |
| PATCH | `/api/departments/:id` | Yes | Update department |
| DELETE | `/api/departments/:id` | Admin | Delete department |
| GET/POST | `/api/departments/:id/members` | Yes | Department member management |
| PATCH/DELETE | `/api/departments/:did/members/:uid` | Yes | Update/remove member role |
| GET | `/api/services` | Yes | List services (?departmentId=) |
| POST | `/api/services` | Yes | Create service |
| GET | `/api/services/:id` | Yes | Service detail + enrolled users + items |
| PATCH | `/api/services/:id` | Yes | Update service |
| DELETE | `/api/services/:id` | Yes | Delete service |
| POST | `/api/services/:id/enroll` | Yes | Enroll user in service |
| PATCH | `/api/services/:sid/users/:uid/status` | Yes | Update enrollment status |
| PATCH | `/api/services/:sid/users/:uid/hours` | Yes | Update enrollment hours |
| DELETE | `/api/services/:sid/users/:uid` | Yes | Remove user from service |
| POST/DELETE | `/api/services/:id/visibility` | Yes | Manage specialization visibility |
| GET | `/api/items` | Yes | List items (?containerId=&search=) |
| POST | `/api/items` | Yes | Create item |
| GET | `/api/items/:id` | Yes | Item detail + contents + service assignments |
| PATCH | `/api/items/:id` | Yes | Update item |
| DELETE | `/api/items/:id` | Yes | Delete item |
| POST | `/api/items/assign` | Yes | Assign item to service |
| DELETE | `/api/items/assign/:id` | Yes | Remove item assignment |
| GET | `/api/vehicles` | Yes | List vehicles (?departmentId=) |
| POST | `/api/vehicles` | Yes | Create vehicle |
| GET | `/api/vehicles/:id` | Yes | Vehicle detail + logs |
| PATCH | `/api/vehicles/:id` | Yes | Update vehicle |
| DELETE | `/api/vehicles/:id` | Yes | Delete vehicle |
| GET/POST | `/api/vehicles/:id/logs` | Yes | Vehicle usage logs |
| DELETE | `/api/vehicles/logs/:logId` | Yes | Delete vehicle log |
| GET | `/api/specializations` | Yes | List specializations |
| POST | `/api/specializations` | Yes | Create specialization |
| GET | `/api/specializations/:id` | Yes | Specialization detail + hierarchy |
| PATCH | `/api/specializations/:id` | Yes | Update specialization |
| DELETE | `/api/specializations/:id` | Yes | Delete specialization |
| GET | `/api/files?entityId=` | Yes | List file attachments |
| POST | `/api/files?entityId=` | Yes | Upload file (multipart) |
| POST | `/api/files/bulk?entityId=` | Yes | Upload multiple files |
| DELETE | `/api/files/:id` | Yes | Delete file attachment |

## Docker

### Production (`docker-compose.yml`)
- Private bridge network `mitroo-network`
- Only frontend port 8080 is published; everything else communicates internally
- Frontend nginx proxies `/api/` → `backend:4000`
- Backend runs Prisma migrate deploy on startup

### Development (`docker-compose.dev.yml`)
- Only Postgres (port 5432) and Redis (port 6379) exposed to host
- Backend: `cd backend && npm run dev`
- Frontend: `cd frontend && flutter run -d chrome`
