import { LOINC, SNOMED, FHIR_SYSTEM } from './codes';

export interface CreateVictimInput {
  name: string;
  age?: number | null;
  dateOfBirth?: string | null;
  gender?: 'male' | 'female' | 'other' | 'unknown' | null;
  address?: string | null;
  city?: string | null;
  postalCode?: string | null;
  telephone?: string | null;
  emergencyContact?: string | null;
  emergencyPhone?: string | null;
  chiefComplaint?: string | null;
  allergies?: string | null;
  medications?: string | null;
  medicalHistory?: string | null;
  gcsEye?: number | null;
  gcsVerbal?: number | null;
  gcsMotor?: number | null;
  gcsTotal?: number | null;
  avpu?: string | null;
  serviceId?: number | null;
  notes?: string | null;
}

export function bundleToVictim(bundle: fhir4.Bundle): CreateVictimInput {
  const resources = (bundle.entry ?? []).map(e => e.resource).filter(Boolean);

  const patient = resources.find((r): r is fhir4.Patient => r!.resourceType === 'Patient');
  if (!patient) throw new Error('Bundle must contain a Patient resource');

  const conditions = resources.filter((r): r is fhir4.Condition => r!.resourceType === 'Condition');
  const observations = resources.filter((r): r is fhir4.Observation => r!.resourceType === 'Observation');
  const medStatement = resources.find((r): r is fhir4.MedicationStatement => r!.resourceType === 'MedicationStatement');
  const encounter = resources.find((r): r is fhir4.Encounter => r!.resourceType === 'Encounter');

  // Demographics
  const name = patient.name?.[0]?.text ?? '';
  const birthDate = patient.birthDate ?? null;
  let age: number | null = null;
  if (birthDate) {
    const dob = new Date(birthDate);
    age = Math.floor((Date.now() - dob.getTime()) / (365.25 * 24 * 60 * 60 * 1000));
  }
  const gender = (patient.gender ?? null) as CreateVictimInput['gender'];
  const addr = patient.address?.[0];
  const telephone = patient.telecom?.find(t => t.system === 'phone')?.value ?? null;
  const emergencyContact = patient.contact?.[0]?.name?.text ?? null;
  const emergencyPhone = patient.contact?.[0]?.telecom?.[0]?.value ?? null;

  // Condition disambiguation matches our own victimToBundle output convention:
  // - encounter-diagnosis → chiefComplaint
  // - problem-list-item + resolved → medicalHistory
  // - problem-list-item (no resolved status) → allergies
  // Third-party bundles with different conventions may not map correctly.
  const chiefComplaintCondition = conditions.find(
    c => c.category?.[0]?.coding?.[0]?.code === 'encounter-diagnosis',
  );
  const historyCondition = conditions.find(
    c => c.clinicalStatus?.coding?.[0]?.code === 'resolved',
  );
  const allergyCondition = conditions.find(
    c =>
      c.category?.[0]?.coding?.[0]?.code === 'problem-list-item' &&
      c.clinicalStatus?.coding?.[0]?.code !== 'resolved',
  );

  // GCS Observations
  const findIntObs = (code: string): number | null =>
    observations.find(o => o.code.coding?.[0]?.code === code)?.valueInteger ?? null;

  // AVPU
  const avpuObs = observations.find(
    o =>
      o.code.coding?.[0]?.system === FHIR_SYSTEM.SNOMED &&
      o.code.coding?.[0]?.code === SNOMED.AVPU,
  );

  // Medications
  const medications =
    (medStatement as fhir4.MedicationStatement & { medicationCodeableConcept?: fhir4.CodeableConcept })
      ?.medicationCodeableConcept?.text ?? null;

  // Encounter → serviceId
  let serviceId: number | null = null;
  if (encounter?.identifier?.[0]?.system === FHIR_SYSTEM.MITROO_SERVICES) {
    const parsed = parseInt(encounter.identifier[0].value ?? '', 10);
    if (!isNaN(parsed)) serviceId = parsed;
  }

  return {
    name,
    age,
    dateOfBirth: birthDate ? `${birthDate}T00:00:00.000Z` : null,
    gender,
    address: addr?.line?.[0] ?? null,
    city: addr?.city ?? null,
    postalCode: addr?.postalCode ?? null,
    telephone,
    emergencyContact,
    emergencyPhone,
    chiefComplaint: chiefComplaintCondition?.code?.text ?? null,
    allergies: allergyCondition?.code?.text ?? null,
    medications,
    medicalHistory: historyCondition?.code?.text ?? null,
    gcsEye: findIntObs(LOINC.GCS_EYE),
    gcsVerbal: findIntObs(LOINC.GCS_VERBAL),
    gcsMotor: findIntObs(LOINC.GCS_MOTOR),
    gcsTotal: findIntObs(LOINC.GCS_TOTAL),
    avpu: avpuObs?.valueCodeableConcept?.text ?? null,
    serviceId,
    notes: null,
  };
}
