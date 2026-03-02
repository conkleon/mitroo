# Mitroo – Changelog

All notable changes performed by AI agents are documented here.

---

## [Session 1] – 2026-03-02

### Summary
Initial project scaffold – full-stack setup from zero.

### What was done
1. **Root configuration**
   - Created `.env` with all shared environment variables (Postgres, Redis, JWT, ports)
   - Created `.env.example` as a safe-to-commit template
   - Created `.gitignore` covering Node, Flutter, IDE, OS, and Docker artifacts

2. **Backend (`backend/`)**
   - Initialised `package.json` with Express, Prisma, bcryptjs, ioredis, JWT, Zod, Helmet, etc.
   - TypeScript config (`tsconfig.json`) targeting ES2022
   - Prisma schema with 7 models: `User`, `AssetCategory`, `Asset`, `Team`, `TeamMember`, `Dispatch`, `DispatchAsset`
   - Role-based enums: `Role`, `AssetStatus`, `DispatchStatus`, `DispatchPriority`
   - Seed script creating admin user, sample categories, assets, and a team
   - Express app with middleware: Helmet, CORS, Morgan, cookie-parser
   - JWT authentication + role-based authorization middleware
   - 6 route modules: health, auth, users, assets, teams, dispatches
   - Redis caching on asset list endpoint
   - Redis pub/sub publish on dispatch create/update (for future WebSocket support)
   - Multi-stage Dockerfile (build → production)

3. **Frontend (`frontend/`)**
   - Flutter web project with `pubspec.yaml` (http, provider, go_router, shared_preferences, google_fonts)
   - `ApiClient` service with token management via SharedPreferences
   - 4 Providers: Auth, Asset, Team, Dispatch
   - GoRouter with auth guard (redirect to `/login` if not authenticated)
   - 6 screens: Login (with register toggle), Shell (NavigationRail), Dashboard, Assets, Teams, Dispatches
   - Material 3 theming with system dark/light mode
   - Multi-stage Dockerfile (Flutter build → nginx)
   - nginx config: SPA fallback + `/api/` reverse proxy to backend

4. **Docker Compose**
   - `docker-compose.yml` – production: Postgres, Redis, Backend, Frontend on private `mitroo-network`; only frontend port 8080 published
   - `docker-compose.dev.yml` – development: Postgres (5432) + Redis (6379) exposed to host

5. **Copilot History (`copilot-history/`)**
   - `README.md`, `CHANGELOG.md` (this file), `ARCHITECTURE.md`, `NEXT_STEPS.md`

### Files created
```
.env
.env.example
.gitignore
docker-compose.yml
docker-compose.dev.yml
backend/Dockerfile
backend/package.json
backend/tsconfig.json
backend/.gitignore
backend/prisma/schema.prisma
backend/prisma/seed.ts
backend/src/server.ts
backend/src/app.ts
backend/src/lib/prisma.ts
backend/src/lib/redis.ts
backend/src/middleware/auth.ts
backend/src/middleware/errorHandler.ts
backend/src/middleware/notFound.ts
backend/src/routes/health.routes.ts
backend/src/routes/auth.routes.ts
backend/src/routes/user.routes.ts
backend/src/routes/asset.routes.ts
backend/src/routes/team.routes.ts
backend/src/routes/dispatch.routes.ts
frontend/Dockerfile
frontend/nginx.conf
frontend/pubspec.yaml
frontend/analysis_options.yaml
frontend/.gitignore
frontend/web/index.html
frontend/web/manifest.json
frontend/lib/main.dart
frontend/lib/config/api_config.dart
frontend/lib/config/router.dart
frontend/lib/services/api_client.dart
frontend/lib/providers/auth_provider.dart
frontend/lib/providers/asset_provider.dart
frontend/lib/providers/team_provider.dart
frontend/lib/providers/dispatch_provider.dart
frontend/lib/screens/login_screen.dart
frontend/lib/screens/shell_screen.dart
frontend/lib/screens/dashboard_screen.dart
frontend/lib/screens/assets_screen.dart
frontend/lib/screens/teams_screen.dart
frontend/lib/screens/dispatches_screen.dart
copilot-history/README.md
copilot-history/CHANGELOG.md
copilot-history/ARCHITECTURE.md
copilot-history/NEXT_STEPS.md
```

---

## [Session 2] – Domain Model Rewrite

### Summary
Complete domain model rewrite from generic Asset/Team/Dispatch to organization-specific: Departments, Services, Items, Vehicles, Specializations, and file attachments.

### What was done

1. **Prisma schema rewrite** (`backend/prisma/schema.prisma`)
   - Replaced 7 old models (User, AssetCategory, Asset, Team, TeamMember, Dispatch, DispatchAsset)
   - New domain models: Department, RoleType, Service, User (with ename login), UserDepartment, UserService, Item (self-referencing containment), ItemService, Specialization (hierarchical), UserSpecialization, ServiceVisibility, Vehicle (meter tracking), VehicleLog, FileAttachment (polymorphic)
   - Enums: DepartmentRole (missionAdmin, itemAdmin, volunteer), ServiceStatus (requested, accepted, rejected)
   - Added `imagePath` to User, Item, Department, Vehicle, Service
   - Used Int IDs (not BigInt) for JSON serialization compatibility

2. **Backend route files rewritten/created**
   - Rewrote: auth.routes.ts (ename login), user.routes.ts (new model + specializations)
   - Created: department.routes.ts, service.routes.ts, item.routes.ts, vehicle.routes.ts, specialization.routes.ts, file.routes.ts
   - Deleted: asset.routes.ts, team.routes.ts, dispatch.routes.ts
   - Added multer for file uploads

3. **Auth & middleware updates**
   - JWT payload now uses `{ userId, isAdmin }` instead of `{ userId, role }`
   - `authenticate` + `requireAdmin` replaced old `authorize(...roles)` pattern
   - Department-level roles via UserDepartment table

4. **Seed file rewrite** – admin user (ename: admin), departments, role types, sample service, specializations, items, vehicles

5. **Frontend rewrite**
   - Deleted old providers: asset_provider, team_provider, dispatch_provider
   - Created new providers: department_provider, service_provider, item_provider, vehicle_provider
   - Updated auth_provider for ename-based login
   - Deleted old screens: assets_screen, teams_screen, dispatches_screen
   - Created new screens: departments_screen, services_screen, items_screen, vehicles_screen
   - Updated login_screen (ename instead of email), dashboard_screen, shell_screen, router, main.dart

### Schema corrections from user's SQL draft
- Fixed typo: `eame` → `ename`
- Fixed: `container BOOLEAN DEFAULT 0` → `isContainer Boolean @default(false)`
- Added missing `name` field to Service model
- Added `password` field to User (needed for auth, missing from SQL draft)
- Computed column `vehicle_log.total_used` → handled in app layer (Prisma doesn't support GENERATED ALWAYS AS)
- CHECK constraints → enforced via Zod validation in routes

### Files created
```
backend/src/routes/department.routes.ts
backend/src/routes/service.routes.ts
backend/src/routes/item.routes.ts
backend/src/routes/vehicle.routes.ts
backend/src/routes/specialization.routes.ts
backend/src/routes/file.routes.ts
frontend/lib/providers/department_provider.dart
frontend/lib/providers/service_provider.dart
frontend/lib/providers/item_provider.dart
frontend/lib/providers/vehicle_provider.dart
frontend/lib/screens/departments_screen.dart
frontend/lib/screens/services_screen.dart
frontend/lib/screens/items_screen.dart
frontend/lib/screens/vehicles_screen.dart
```

### Files deleted
```
backend/src/routes/asset.routes.ts
backend/src/routes/team.routes.ts
backend/src/routes/dispatch.routes.ts
frontend/lib/providers/asset_provider.dart
frontend/lib/providers/team_provider.dart
frontend/lib/providers/dispatch_provider.dart
frontend/lib/screens/assets_screen.dart
frontend/lib/screens/teams_screen.dart
frontend/lib/screens/dispatches_screen.dart
```

### Files modified
```
backend/prisma/schema.prisma
backend/prisma/seed.ts
backend/package.json
backend/src/app.ts
backend/src/middleware/auth.ts
backend/src/routes/auth.routes.ts
backend/src/routes/user.routes.ts
frontend/lib/main.dart
frontend/lib/config/router.dart
frontend/lib/providers/auth_provider.dart
frontend/lib/screens/login_screen.dart
frontend/lib/screens/shell_screen.dart
frontend/lib/screens/dashboard_screen.dart
copilot-history/CHANGELOG.md
copilot-history/ARCHITECTURE.md
copilot-history/NEXT_STEPS.md
```
