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


  // ── Role types (reference) ────────────────────
  for (const rt of [
    { name: "missionAdmin", description: "Can create & assign users to services" },
    { name: "itemAdmin", description: "Can manage items" },
    { name: "volunteer", description: "Can request service access & view info" },
  ]) {
    await prisma.roleType.upsert({ where: { name: rt.name }, update: {}, create: rt });
  }


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
