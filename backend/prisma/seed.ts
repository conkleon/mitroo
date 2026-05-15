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

  // ── Role types ────────────────────────────────
  for (const rt of [
    { name: "missionAdmin", description: "Can create & assign users to services" },
    { name: "itemAdmin", description: "Can manage items" },
    { name: "volunteer", description: "Can request service access & view info" },
  ]) {
    await prisma.roleType.upsert({ where: { name: rt.name }, update: {}, create: rt });
  }

  // ── Service types (11 types from old Mitroo) ──
  const serviceTypes = [
    { name: "BLS “ΒΑΣΙΚΗ ΥΠΟΣΤΗΡΙΞΗ ΖΩΗΣ’’", externalMissionTypeId: 71, isDefaultVisible: false },
    { name: "ΔΡΑΣΗ ΠΡΟΛΗΨΗΣ", externalMissionTypeId: 56, isDefaultVisible: false },
    { name: "ΕΘΕΛΟΝΤΙΚΗ ΔΡΑΣΤΗΡΙΟΤΗΤΑ", externalMissionTypeId: 57, isDefaultVisible: false },
    { name: "ΕΚΠΑΙΔΕΥΣΗ Α΄ ΒΟΗΘΕΙΩΝ ΣΕ ΠΟΛΙΤΕΣ", externalMissionTypeId: 36, isDefaultVisible: false },
    { name: "ΕΚΠΑΙΔΕΥΣΗ Α' ΒΟΗΘΕΙΕΣ ΓΙΑ ΣΚΥΛΟΥΣ", externalMissionTypeId: 86, isDefaultVisible: false },
    { name: "ΕΚΠΑΙΔΕΥΣΗ ΔΟΚΙΜΩΝ ΣΑΜΑΡΕΙΤΩΝ", externalMissionTypeId: 33, isDefaultVisible: false },
    { name: "ΕΚΠΑΙΔΕΥΣΗ ΕΝΕΡΓΟΠΟΙΗΣΗΣ ΑΝΕΝΕΡΓΩΝ ΕΘΕΛΟΝΤΩΝ", externalMissionTypeId: 83, isDefaultVisible: false },
    { name: "ΝΑΥΑΓΟΣΩΣΤΙΚΗ ΚΑΛΥΨΗ", externalMissionTypeId: 60, isDefaultVisible: false },
    { name: "Τ.Ε.Π. ΔΟΚΙΜΩΝ", externalMissionTypeId: 85, isDefaultVisible: false },
    { name: "ΥΓΕΙΟΝΟΜΙΚΗ ΚΑΛΥΨΗ", externalMissionTypeId: 16, isDefaultVisible: false },
    { name: "ΥΠΟΧΡΕΩΤΙΚΗ ΕΤΗΣΙΑ ΕΚΠΑΙΔΕΥΣΗ ΕΘΕΛΟΝΤΗ", externalMissionTypeId: 81, isDefaultVisible: false },
  ];

  const createdTypes: Record<string, number> = {};
  for (const st of serviceTypes) {
    const created = await prisma.serviceType.upsert({
      where: { name: st.name },
      update: { externalMissionTypeId: st.externalMissionTypeId, isDefaultVisible: st.isDefaultVisible },
      create: st,
    });
    createdTypes[st.name] = created.id;
  }

  // ── Specializations ───────────────────────────
  const specsToCreate = [
    { name: "Δόκιμος Σαμαρείτης", description: "Δόκιμος Σαμαρείτης" },
    { name: "Δόκιμος Ναυαγοσώστης", description: "Δόκιμος Ναυαγοσώστης" },
    { name: "Σαμαρείτης", description: "Σαμαρείτης" },
    { name: "Ναυαγοσώστης", description: "Ναυαγοσώστης" },
    { name: "Εκπαιδευτής Α' Βοηθειών", description: "Εκπαιδευτής Πρώτων Βοηθειών" },
    { name: "Εκπαιδευτής Ναυαγοσωστικής", description: "Εκπαιδευτής Ναυαγοσωστικής" },
  ];

  const createdSpecs: Record<string, number> = {};
  for (const spec of specsToCreate) {
    const created = await prisma.specialization.upsert({
      where: { name: spec.name },
      update: { description: spec.description },
      create: spec,
    });
    createdSpecs[spec.name] = created.id;
  }

  // ── Specialization ↔ ServiceType assignments ──
  const defaultVisibleTypeNames = [
    "BLS “ΒΑΣΙΚΗ ΥΠΟΣΤΗΡΙΞΗ ΖΩΗΣ’’",
    "ΔΡΑΣΗ ΠΡΟΛΗΨΗΣ",
    "ΕΘΕΛΟΝΤΙΚΗ ΔΡΑΣΤΗΡΙΟΤΗΤΑ",
    "ΕΚΠΑΙΔΕΥΣΗ Α΄ ΒΟΗΘΕΙΩΝ ΣΕ ΠΟΛΙΤΕΣ",
    "ΕΚΠΑΙΔΕΥΣΗ Α' ΒΟΗΘΕΙΕΣ ΓΙΑ ΣΚΥΛΟΥΣ",
    "ΕΚΠΑΙΔΕΥΣΗ ΔΟΚΙΜΩΝ ΣΑΜΑΡΕΙΤΩΝ",
    "ΕΚΠΑΙΔΕΥΣΗ ΕΝΕΡΓΟΠΟΙΗΣΗΣ ΑΝΕΝΕΡΓΩΝ ΕΘΕΛΟΝΤΩΝ",
    "ΥΠΟΧΡΕΩΤΙΚΗ ΕΤΗΣΙΑ ΕΚΠΑΙΔΕΥΣΗ ΕΘΕΛΟΝΤΗ",
  ];

  for (const specName of Object.keys(createdSpecs)) {
    for (const typeName of defaultVisibleTypeNames) {
      if (createdTypes[typeName] && createdSpecs[specName]) {
        await prisma.specializationServiceType.upsert({
          where: {
            specializationId_serviceTypeId: {
              specializationId: createdSpecs[specName],
              serviceTypeId: createdTypes[typeName],
            },
          },
          update: {},
          create: {
            specializationId: createdSpecs[specName],
            serviceTypeId: createdTypes[typeName],
          },
        });
      }
    }
  }

  // Σαμαρείτης + Δόκιμος Σαμαρείτης see sanitary coverage + TEP
  for (const specName of ["Σαμαρείτης", "Δόκιμος Σαμαρείτης"]) {
    for (const typeName of ["ΥΓΕΙΟΝΟΜΙΚΗ ΚΑΛΥΨΗ", "Τ.Ε.Π. ΔΟΚΙΜΩΝ"]) {
      if (createdTypes[typeName] && createdSpecs[specName]) {
        await prisma.specializationServiceType.upsert({
          where: {
            specializationId_serviceTypeId: {
              specializationId: createdSpecs[specName],
              serviceTypeId: createdTypes[typeName],
            },
          },
          update: {},
          create: {
            specializationId: createdSpecs[specName],
            serviceTypeId: createdTypes[typeName],
          },
        });
      }
    }
  }

  // Ναυαγοσώστης + Δόκιμος Ναυαγοσώστης see lifeguard + sanitary + TEP
  for (const specName of ["Ναυαγοσώστης", "Δόκιμος Ναυαγοσώστης"]) {
    for (const typeName of ["ΝΑΥΑΓΟΣΩΣΤΙΚΗ ΚΑΛΥΨΗ", "ΥΓΕΙΟΝΟΜΙΚΗ ΚΑΛΥΨΗ", "Τ.Ε.Π. ΔΟΚΙΜΩΝ"]) {
      if (createdTypes[typeName] && createdSpecs[specName]) {
        await prisma.specializationServiceType.upsert({
          where: {
            specializationId_serviceTypeId: {
              specializationId: createdSpecs[specName],
              serviceTypeId: createdTypes[typeName],
            },
          },
          update: {},
          create: {
            specializationId: createdSpecs[specName],
            serviceTypeId: createdTypes[typeName],
          },
        });
      }
    }
  }

  // Εκπαιδευτής Α' Βοηθειών sees sanitary coverage + TEP
  for (const typeName of ["ΥΓΕΙΟΝΟΜΙΚΗ ΚΑΛΥΨΗ", "Τ.Ε.Π. ΔΟΚΙΜΩΝ"]) {
    if (createdTypes[typeName] && createdSpecs["Εκπαιδευτής Α' Βοηθειών"]) {
      await prisma.specializationServiceType.upsert({
        where: {
          specializationId_serviceTypeId: {
            specializationId: createdSpecs["Εκπαιδευτής Α' Βοηθειών"],
            serviceTypeId: createdTypes[typeName],
          },
        },
        update: {},
        create: {
          specializationId: createdSpecs["Εκπαιδευτής Α' Βοηθειών"],
          serviceTypeId: createdTypes[typeName],
        },
      });
    }
  }

  // Εκπαιδευτής Ναυαγοσωστικής sees lifeguard + sanitary + TEP
  for (const typeName of ["ΝΑΥΑΓΟΣΩΣΤΙΚΗ ΚΑΛΥΨΗ", "ΥΓΕΙΟΝΟΜΙΚΗ ΚΑΛΥΨΗ", "Τ.Ε.Π. ΔΟΚΙΜΩΝ"]) {
    if (createdTypes[typeName] && createdSpecs["Εκπαιδευτής Ναυαγοσωστικής"]) {
      await prisma.specializationServiceType.upsert({
        where: {
          specializationId_serviceTypeId: {
            specializationId: createdSpecs["Εκπαιδευτής Ναυαγοσωστικής"],
            serviceTypeId: createdTypes[typeName],
          },
        },
        update: {},
        create: {
          specializationId: createdSpecs["Εκπαιδευτής Ναυαγοσωστικής"],
          serviceTypeId: createdTypes[typeName],
        },
      });
    }
  }

  // ── User ↔ Specialization assignments ─────────
  for (const specId of [createdSpecs["Σαμαρείτης"], createdSpecs["Εκπαιδευτής Α' Βοηθειών"], createdSpecs["Εκπαιδευτής Ναυαγοσωστικής"]]) {
    await prisma.userSpecialization.upsert({
      where: { userId_specializationId: { userId: admin.id, specializationId: specId } },
      update: {},
      create: { userId: admin.id, specializationId: specId },
    });
  }
  for (const specId of [createdSpecs["Δόκιμος Σαμαρείτης"], createdSpecs["Σαμαρείτης"]]) {
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
