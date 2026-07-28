export interface VictimNarrativeInput {
  chiefComplaint: string | null;
  medicalHistory: string | null;
  notes: string | null;
}

/**
 * Defensive allow-list: only these three free-text fields may ever reach
 * an external AI provider. Never widen this to include name, address,
 * telephone, emergencyContact, emergencyPhone, dateOfBirth, city, or
 * postalCode, even if the caller's input object happens to carry them.
 */
export function anonymizeVictimForPrompt(victim: VictimNarrativeInput): VictimNarrativeInput {
  return {
    chiefComplaint: victim.chiefComplaint,
    medicalHistory: victim.medicalHistory,
    notes: victim.notes,
  };
}
