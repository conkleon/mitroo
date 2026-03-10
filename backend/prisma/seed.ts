import { PrismaClient, DepartmentRole } from "@prisma/client";
import bcrypt from "bcryptjs";

const prisma = new PrismaClient();

async function main() {
  console.log("🌱 Seeding database …");

  // ── Admin user ────────────────────────────────
  const hashedPassword = await bcrypt.hash("admin123", 12);
  const admin = await prisma.user.upsert({
    where: { ename: "admin" },
    update: {},
    create: {
      ename: "admin",
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
    where: { ename: "jdoe" },
    update: {},
    create: {
      ename: "jdoe",
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
    create: { name: "Υγειονομικές", description: "Health / Medical services", location: "HQ" },
  });

  const rescue = await prisma.department.upsert({
    where: { id: 2 },
    update: {},
    create: { name: "Ναυαγοσωστικές", description: "Lifeguard / Rescue services" },
  });

  const general = await prisma.department.upsert({
    where: { id: 3 },
    update: {},
    create: { name: "Γενικές", description: "General-purpose services" },
  });

  const education = await prisma.department.upsert({
    where: { id: 4 },
    update: {},
    create: { name: "Εκπαιδευτικές", description: "Educational services" },
  });

  const trainers = await prisma.department.upsert({
    where: { id: 5 },
    update: {},
    create: { name: "Εκπαιδευτών", description: "Trainer staffing services" },
  });

  // ── Department memberships ────────────────────
  await prisma.userDepartment.upsert({
    where: { userId_departmentId: { userId: admin.id, departmentId: ops.id } },
    update: {},
    create: { userId: admin.id, departmentId: ops.id, role: DepartmentRole.missionAdmin },
  });

  await prisma.userDepartment.upsert({
    where: { userId_departmentId: { userId: admin.id, departmentId: rescue.id } },
    update: {},
    create: { userId: admin.id, departmentId: rescue.id, role: DepartmentRole.missionAdmin },
  });

  await prisma.userDepartment.upsert({
    where: { userId_departmentId: { userId: volunteer.id, departmentId: ops.id } },
    update: {},
    create: { userId: volunteer.id, departmentId: ops.id, role: DepartmentRole.volunteer },
  });

  await prisma.userDepartment.upsert({
    where: { userId_departmentId: { userId: volunteer.id, departmentId: trainers.id } },
    update: {},
    create: { userId: volunteer.id, departmentId: trainers.id, role: DepartmentRole.volunteer },
  });

  // ── Role types (reference) ────────────────────
  for (const rt of [
    { name: "missionAdmin", description: "Can create & assign users to services" },
    { name: "itemAdmin", description: "Can manage items" },
    { name: "volunteer", description: "Can request service access & view info" },
  ]) {
    await prisma.roleType.upsert({ where: { name: rt.name }, update: {}, create: rt });
  }

  // ── Services ──────────────────────────────────
  await prisma.service.upsert({
    where: { id: 1 },
    update: {},
    create: {
      departmentId: ops.id,
      name: "Υγειονομική κάλυψη αγώνα",
      description: "ΑΓΩΝΕΣ ΠΟΔΟΣΦΑΙΡΟΥ",
      carrier: "ΣΥΛΛΟΓΟΣ ΔΑΒΟΥΡΛΗ",
      location: "ΓΗΠΕΔΟ ΠΡΟΣΦΥΓΙΚΩΝ",
      defaultHours: 3,
      startAt: new Date("2026-03-02T19:30:00"),
      endAt: new Date("2026-03-02T22:30:00"),
    },
  });

  await prisma.service.upsert({
    where: { id: 2 },
    update: {},
    create: {
      departmentId: ops.id,
      name: "Υγειονομική κάλυψη αγώνα",
      description: "ΑΓΩΝΕΣ ΜΠΑΣΚΕΤ",
      carrier: "ΑΣ ΟΛΥΜΠΙΑΚΟΣ",
      location: "ΚΛΕΙΣΤΟ ΓΥΜΝΑΣΤΗΡΙΟ",
      defaultHours: 3,
      startAt: new Date("2026-03-04T20:30:00"),
      endAt: new Date("2026-03-04T22:30:00"),
    },
  });

  await prisma.service.upsert({
    where: { id: 3 },
    update: {},
    create: {
      departmentId: rescue.id,
      name: "Ναυαγοσωστική κάλυψη",
      description: "Κάλυψη κολυμβητηρίου",
      carrier: "ΔΗΜΟΣ ΑΘΗΝΑΙΩΝ",
      location: "ΔΗΜΟΤΙΚΟ ΚΟΛΥΜΒΗΤΗΡΙΟ",
      defaultHours: 6,
      startAt: new Date("2026-03-05T09:00:00"),
      endAt: new Date("2026-03-05T15:00:00"),
    },
  });

  await prisma.service.upsert({
    where: { id: 4 },
    update: {},
    create: {
      departmentId: trainers.id,
      name: "Εκπαίδευση Πρώτων Βοηθειών",
      description: "Σεμινάριο βασικών πρώτων βοηθειών",
      carrier: "ΕΕΣ ΤΜΗΜΑ ΑΘΗΝΑΣ",
      location: "ΑΙΘΟΥΣΑ Α",
      defaultHours: 4,
      defaultHoursTraining: 4,
      startAt: new Date("2026-03-03T17:00:00"),
      endAt: new Date("2026-03-03T21:00:00"),
    },
  });

  for (let i = 5; i <= 16; i++) {
    const day = 5 + (i - 5);
    await prisma.service.upsert({
      where: { id: i },
      update: {},
      create: {
        departmentId: trainers.id,
        name: `Εκπαίδευση BLS/AED #${i - 4}`,
        description: "Εκπαιδευτικό σεμινάριο BLS/AED",
        carrier: "ΕΕΣ",
        location: "ΑΙΘΟΥΣΑ Β",
        defaultHours: 3,
        defaultHoursTrainers: 3,
        defaultHoursTEP: 0,
        startAt: new Date(`2026-03-${String(day).padStart(2, '0')}T18:00:00`),
        endAt: new Date(`2026-03-${String(day).padStart(2, '0')}T21:00:00`),
      },
    });
  }

  // ── Specializations ───────────────────────────
  const firstAid = await prisma.specialization.upsert({
    where: { name: "First Aid" },
    update: {},
    create: { name: "First Aid", description: "Basic first-aid certification", hoursTraining: 16 },
  });

  const als = await prisma.specialization.upsert({
    where: { name: "Advanced Life Support" },
    update: {},
    create: {
      name: "Advanced Life Support",
      description: "ALS certification",
      hoursTraining: 40,
      rootId: firstAid.id,
    },
  });

  const lifeguard = await prisma.specialization.upsert({
    where: { name: "Lifeguard" },
    update: {},
    create: { name: "Lifeguard", description: "Ναυαγοσωστική πιστοποίηση", hoursTraining: 24 },
  });

  const blsAed = await prisma.specialization.upsert({
    where: { name: "BLS/AED Instructor" },
    update: {},
    create: { name: "BLS/AED Instructor", description: "BLS/AED εκπαιδευτής", hoursTraining: 20 },
  });

  // ── User ↔ Specialization assignments ─────────
  // Admin has First Aid + ALS + BLS/AED Instructor
  for (const specId of [firstAid.id, als.id, blsAed.id]) {
    await prisma.userSpecialization.upsert({
      where: { userId_specializationId: { userId: admin.id, specializationId: specId } },
      update: {},
      create: { userId: admin.id, specializationId: specId },
    });
  }
  // Volunteer has First Aid + Lifeguard
  for (const specId of [firstAid.id, lifeguard.id]) {
    await prisma.userSpecialization.upsert({
      where: { userId_specializationId: { userId: volunteer.id, specializationId: specId } },
      update: {},
      create: { userId: volunteer.id, specializationId: specId },
    });
  }

  // ── Service visibility (specialization requirements) ──
  // Health-coverage games require First Aid (services 1 & 2)
  for (const svcId of [1, 2]) {
    await prisma.serviceVisibility.upsert({
      where: { serviceId_specializationId: { serviceId: svcId, specializationId: firstAid.id } },
      update: {},
      create: { serviceId: svcId, specializationId: firstAid.id },
    });
  }
  // Lifeguard service requires Lifeguard specialization (service 3)
  await prisma.serviceVisibility.upsert({
    where: { serviceId_specializationId: { serviceId: 3, specializationId: lifeguard.id } },
    update: {},
    create: { serviceId: 3, specializationId: lifeguard.id },
  });
  // First-aid training requires First Aid spec (service 4)
  await prisma.serviceVisibility.upsert({
    where: { serviceId_specializationId: { serviceId: 4, specializationId: firstAid.id } },
    update: {},
    create: { serviceId: 4, specializationId: firstAid.id },
  });
  // BLS/AED sessions require BLS/AED Instructor spec (services 5–16)
  for (let svcId = 5; svcId <= 16; svcId++) {
    await prisma.serviceVisibility.upsert({
      where: { serviceId_specializationId: { serviceId: svcId, specializationId: blsAed.id } },
      update: {},
      create: { serviceId: svcId, specializationId: blsAed.id },
    });
  }

  // ── Items ─────────────────────────────────────
  const kit = await prisma.item.upsert({
    where: { id: 1 },
    update: {},
    create: { name: "Rescue Kit #1", isContainer: true, location: "Warehouse A" },
  });

  await prisma.item.upsert({
    where: { id: 2 },
    update: {},
    create: { name: "Defibrillator", barCode: "DEF-001", containedById: kit.id },
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
