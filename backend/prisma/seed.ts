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
    create: { name: "Τμήμα Αθήνας", description: "Health / Medical services", location: "HQ" },
  });


  // ── Department memberships ────────────────────
  await prisma.userDepartment.upsert({
    where: { userId_departmentId: { userId: admin.id, departmentId: ops.id } },
    update: {},
    create: { userId: admin.id, departmentId: ops.id, role: DepartmentRole.missionAdmin },
  });


  // ── Role types (reference) ────────────────────
  for (const rt of [
    { name: "missionAdmin", description: "Can create & assign users to services" },
    { name: "itemAdmin", description: "Can manage items" },
    { name: "volunteer", description: "Can request service access & view info" },
  ]) {
    await prisma.roleType.upsert({ where: { name: rt.name }, update: {}, create: rt });
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
