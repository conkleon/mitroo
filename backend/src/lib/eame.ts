import type { Prisma, PrismaClient } from "@prisma/client";

const GENERATED_EAME_PATTERN = /^(?<prefix>.*?)(?<sequence>\d+)\/(?<month>\d{2})\/(?<year>\d{2})$/;

function getCurrentPeriodParts(now: Date): { month: string; year: string } {
  return {
    month: String(now.getMonth() + 1).padStart(2, "0"),
    year: String(now.getFullYear()).slice(-2),
  };
}

function extractGeneratedSequence(value: string): number | null {
  const match = GENERATED_EAME_PATTERN.exec(value.trim());
  if (!match?.groups?.sequence) {
    return null;
  }

  const parsed = Number.parseInt(match.groups.sequence, 10);
  if (!Number.isFinite(parsed) || parsed < 0) {
    return null;
  }

  return parsed;
}

export function formatGeneratedEame(prefix: string | null | undefined, sequence: number, now = new Date()): string {
  const safePrefix = (prefix ?? "").trim();
  const { month, year } = getCurrentPeriodParts(now);
  const serial = String(sequence).padStart(5, "0");
  return `${safePrefix}${serial}/${month}/${year}`;
}

export async function getNextGeneratedEameSequence(
  tx: Prisma.TransactionClient,
): Promise<number> {
  const users = await tx.user.findMany({ select: { eame: true } });

  let maxSequence = 0;
  for (const user of users) {
    const sequence = extractGeneratedSequence(user.eame);
    if (sequence !== null && sequence > maxSequence) {
      maxSequence = sequence;
    }
  }

  return maxSequence + 1;
}

export async function resolveSpecializationPrefix(
  prisma: PrismaClient,
  specializationId: number,
): Promise<string> {
  const specialization = await prisma.specialization.findUnique({
    where: { id: specializationId },
    select: { id: true, eamePrefix: true },
  });

  if (!specialization) {
    throw new Error("Specialization not found for EAME generation");
  }

  return specialization.eamePrefix?.trim() ?? "";
}
