import prisma from "./prisma";

export interface MissionSummary {
  id: number;
  name: string;
  departmentName: string;
  location: string | null;
  startAt: string | null;
  endAt: string | null;
  lifecycleStatus: string;
}

export interface PersonnelEntry {
  userId: number;
  fullName: string;
  rank: string;
  status: string;
  hours: number;
}

export interface VehicleUsageEntry {
  vehicleId: number;
  vehicleName: string;
  driverFullName: string;
  meterType: string;
  startAt: string;
  endAt: string | null;
  distance: number | null;
  destination: string | null;
}

export interface ItemUsageEntry {
  itemName: string;
  userFullName: string;
  assignedAt: string;
  comment: string | null;
}

export interface VictimSummaryEntry {
  id: number;
  chiefComplaint: string | null;
  medicalHistory: string | null;
  notes: string | null;
  isFinalized: boolean;
}

export interface MissionReportData {
  missions: MissionSummary[];
  personnel: PersonnelEntry[];
  vehicles: VehicleUsageEntry[];
  items: ItemUsageEntry[];
  victims: VictimSummaryEntry[];
  totals: {
    personnelCount: number;
    totalHours: number;
    vehicleCount: number;
    itemCount: number;
    victimCount: number;
  };
}

function fullName(user: { forename: string; surname: string }): string {
  return `${user.forename} ${user.surname}`.trim();
}

export async function aggregateMissionReportData(serviceIds: number[]): Promise<MissionReportData> {
  const [servicesRaw, userServicesRaw, vehicleLogsRaw, itemServicesRaw, victimsRaw] = await Promise.all([
    prisma.service.findMany({
      where: { id: { in: serviceIds } },
      select: {
        id: true,
        name: true,
        location: true,
        startAt: true,
        endAt: true,
        lifecycleStatus: true,
        department: { select: { name: true } },
      },
    }),
    // Only people who actually took part count towards the report: rejected
    // applicants and no-shows must not inflate the published headcount/hours.
    prisma.userService.findMany({
      where: { serviceId: { in: serviceIds }, status: { in: ["accepted", "participated"] } },
      select: {
        status: true,
        hours: true,
        hoursVol: true,
        hoursTraining: true,
        hoursTrainers: true,
        hoursTEP: true,
        user: { select: { id: true, forename: true, surname: true, rank: true } },
      },
    }),
    prisma.vehicleLog.findMany({
      where: { serviceId: { in: serviceIds } },
      select: {
        startAt: true,
        endAt: true,
        meterStart: true,
        meterEnd: true,
        destination: true,
        vehicle: { select: { id: true, name: true, meterType: true } },
        user: { select: { forename: true, surname: true } },
      },
    }),
    prisma.itemService.findMany({
      where: { serviceId: { in: serviceIds } },
      select: {
        assignedAt: true,
        comment: true,
        item: { select: { name: true } },
        user: { select: { forename: true, surname: true } },
      },
    }),
    prisma.victim.findMany({
      where: { serviceId: { in: serviceIds } },
      select: {
        id: true,
        chiefComplaint: true,
        medicalHistory: true,
        notes: true,
        isFinalized: true,
      },
    }),
  ]);

  const missions: MissionSummary[] = servicesRaw.map((s) => ({
    id: s.id,
    name: s.name,
    departmentName: s.department.name,
    location: s.location,
    startAt: s.startAt ? s.startAt.toISOString() : null,
    endAt: s.endAt ? s.endAt.toISOString() : null,
    lifecycleStatus: s.lifecycleStatus,
  }));

  const personnel: PersonnelEntry[] = userServicesRaw.map((us) => ({
    userId: us.user.id,
    fullName: fullName(us.user),
    rank: us.user.rank,
    status: us.status,
    hours: us.hours + us.hoursVol + us.hoursTraining + us.hoursTrainers + us.hoursTEP,
  }));

  const vehicles: VehicleUsageEntry[] = vehicleLogsRaw.map((log) => ({
    vehicleId: log.vehicle.id,
    vehicleName: log.vehicle.name,
    driverFullName: fullName(log.user),
    meterType: log.vehicle.meterType,
    startAt: log.startAt.toISOString(),
    endAt: log.endAt ? log.endAt.toISOString() : null,
    distance: log.meterEnd ? log.meterEnd.toNumber() - log.meterStart.toNumber() : null,
    destination: log.destination,
  }));

  const items: ItemUsageEntry[] = itemServicesRaw.map((is) => ({
    itemName: is.item.name,
    userFullName: fullName(is.user),
    assignedAt: is.assignedAt.toISOString(),
    comment: is.comment,
  }));

  const victims: VictimSummaryEntry[] = victimsRaw.map((v) => ({
    id: v.id,
    chiefComplaint: v.chiefComplaint,
    medicalHistory: v.medicalHistory,
    notes: v.notes,
    isFinalized: v.isFinalized,
  }));

  return {
    missions,
    personnel,
    vehicles,
    items,
    victims,
    totals: {
      personnelCount: personnel.length,
      totalHours: personnel.reduce((sum, p) => sum + p.hours, 0),
      vehicleCount: vehicles.length,
      itemCount: items.length,
      victimCount: victims.length,
    },
  };
}
