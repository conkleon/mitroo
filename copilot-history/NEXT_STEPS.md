# Mitroo – Next Steps

Prioritised backlog for the next agent session(s). Check items off as they are completed and move them to `CHANGELOG.md`.

---

## Priority 1 – Essential for MVP

- [ ] **Run initial migration** – `cd backend && npx prisma migrate dev --name init` to create the DB schema.
- [ ] **Run seed** – `npm run seed` to populate default admin + sample data.
- [ ] **Verify backend starts** – `npm run dev` should serve on port 4000; hit `/api/health`.
- [ ] **Install frontend dependencies** – `cd frontend && flutter pub get`.
- [ ] **Verify frontend compiles** – `flutter run -d chrome` should launch the web app.
- [ ] **End-to-end smoke test** – Login with admin/admin123 → See dashboard → Browse departments/services.

## Priority 2 – Hardening

- [ ] **Pagination** – Add `?page=&limit=` query params to list endpoints; return `{ data, meta }`.
- [ ] **Request rate limiting** – Add `express-rate-limit` to auth routes.
- [ ] **Better error responses** – Distinguish Prisma-specific errors (unique constraint, not found) with proper HTTP codes.
- [ ] **CORS tightening** – In production, lock `origin` to the actual frontend domain.
- [ ] **Department-level authorization** – Middleware to check if user has missionAdmin/itemAdmin role in a dept before mutating its data.
- [ ] **Image upload endpoints** – Connect imagePath fields to actual file upload (multer already configured).

## Priority 3 – Features

- [ ] **Detailed entity views** – Drill-down screens for departments, services, items, vehicles.
- [ ] **Service calendar** – Timeline/calendar view for services with startAt/endAt.
- [ ] **Item barcode scanner** – Integrate a barcode scanner for item lookup.
- [ ] **Vehicle meter dashboard** – Charts showing vehicle usage over time.
- [ ] **Specialization tree view** – Visual hierarchy for specializations and their children.
- [ ] **Real-time updates** – WebSocket (socket.io) backed by Redis pub/sub for live service enrollment.
- [ ] **Audit log** – Track who changed what (enrollment, hours, items moved).
- [ ] **Reports & analytics** – Service participation, hours summaries, item utilisation.
- [ ] **Mobile-responsive shell** – Switch NavigationRail to BottomNavigationBar on narrow screens.

## Priority 4 – DevOps

- [ ] **CI/CD pipeline** – GitHub Actions: lint → test → build Docker images → push to registry.
- [ ] **Automated tests** – Jest for backend API routes; Flutter widget tests.
- [ ] **Terraform / IaC** – Infrastructure as code for cloud deployment (e.g. AWS ECS, Fly.io).
- [ ] **Monitoring** – Health-check dashboard, Prometheus metrics, or Sentry error tracking.

---

*When starting a new session, review the above list, pick the highest-priority unchecked items, implement them, then update both this file and `CHANGELOG.md`.*
