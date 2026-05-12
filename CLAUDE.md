# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mitroo is an organisation asset management & team dispatch system. Stack: Flutter (Web) frontend + Node.js/Express/TypeScript backend + PostgreSQL + Redis, all orchestrated with Docker Compose.

## Development Setup

Start databases only (dev mode — backend and frontend run on the host):

```bash
docker compose -f docker-compose.dev.yml up -d
```

**Backend** (runs on port 4000):
```bash
cd backend
npm install
npm run prisma:generate
npm run prisma:migrate   # runs migrations against local DB
npm run dev              # ts-node-dev with hot reload
```

**Frontend** (runs in Chrome):
```bash
cd frontend
flutter pub get
flutter run -d chrome
```

## Backend Commands

```bash
cd backend
npm run build            # compile TypeScript → dist/
npm run lint             # ESLint on src/
npm run prisma:studio    # open Prisma Studio UI
npm run prisma:reset     # reset + re-migrate dev DB
npm run seed             # run prisma/seed.ts
```

The `prisma:*` scripts use `scripts/run-with-dev-env.js` to inject dev env vars; they should NOT be used in production (use `prisma:migrate:prod` instead).

## Environment

Both services share a root `.env` file (see `.env.example`). The backend reads it directly; the frontend gets `API_BASE_URL` injected at Flutter build time via `--dart-define=API_BASE_URL=...`. Default dev API base: `http://localhost:4000/api`.

## Architecture

### Backend (`backend/src/`)

- `server.ts` → entry point; `app.ts` → Express setup + static `/uploads` mount
- `lib/prisma.ts` — Prisma client singleton; `lib/redis.ts` — Redis (ioredis) singleton
- `middleware/auth.ts` — JWT `authenticate` + `requireAdmin` middlewares
- `routes/` — one file per resource; all routes require JWT except `/api/health` and `/api/auth/*`
- Validation is done with **Zod** inside route handlers
- File uploads handled by **multer**; images processed with **sharp**

### Frontend (`frontend/lib/`)

- `config/api_config.dart` — single `baseUrl` constant
- `config/router.dart` — GoRouter with auth guard
- `services/api_client.dart` — HTTP client wrapper
- `providers/` — one Provider per domain (auth, department, service, item, vehicle); all extend `ChangeNotifier`
- `screens/` — shell screen with nav rail + one screen per domain

### Data Model Key Points

- **Department** → users join via `UserDepartment` pivot with per-department roles (`missionAdmin | itemAdmin | volunteer`)
- **Service** → users enroll via `UserService` (status: `requested | accepted | rejected`); `ServiceVisibility` gates access by `Specialization`
- **Item** — self-referencing containment tree (`containedById`); assigned to services via `ItemService`
- **Specialization** — hierarchical tree via `rootId`; users have specializations via `UserSpecialization`
- **Vehicle** → usage tracked via `VehicleLog` with meter readings (km or hours)
- **FileAttachment** — polymorphic table with nullable FKs to each entity type

### Production Docker

`docker-compose.yml` runs the full stack on a private bridge network. Only the frontend (port 8080) is published. Nginx proxies `/api/` → `backend:4000`. Backend runs `prisma migrate deploy` on startup.
