import { Prisma } from '@prisma/client';
import { LOINC, SNOMED, FHIR_SYSTEM } from './codes';

type VictimFull = Prisma.VictimGetPayload<{
  include: { vitalSigns: true; treatments: true };
}>;

export function victimToBundle(victim: VictimFull): fhir4.Bundle {
  const patientId = `mitroo-${victim.id}`;
  const patientRef = `Patient/${patientId}`;
  const entries: fhir4.BundleEntry[] = [];

  entries.push({ resource: buildPatient(victim, patientId) });

  if (victim.chiefComplaint) {
    entries.push({ resource: buildCondition(victim.chiefComplaint, 'encounter-diagnosis', patientRef) });
  }
  if (victim.medicalHistory) {
    entries.push({ resource: buildCondition(victim.medicalHistory, 'problem-list-item', patientRef, 'resolved') });
  }
  if (victim.allergies) {
    entries.push({ resource: buildCondition(victim.allergies, 'problem-list-item', patientRef) });
  }

  if (victim.gcsEye != null) entries.push({ resource: buildIntObs(LOINC.GCS_EYE, victim.gcsEye, patientRef) });
  if (victim.gcsVerbal != null) entries.push({ resource: buildIntObs(LOINC.GCS_VERBAL, victim.gcsVerbal, patientRef) });
  if (victim.gcsMotor != null) entries.push({ resource: buildIntObs(LOINC.GCS_MOTOR, victim.gcsMotor, patientRef) });
  if (victim.gcsTotal != null) entries.push({ resource: buildIntObs(LOINC.GCS_TOTAL, victim.gcsTotal, patientRef) });

  if (victim.avpu) {
    entries.push({
      resource: {
        resourceType: 'Observation',
        status: 'final',
        code: { coding: [{ system: FHIR_SYSTEM.SNOMED, code: SNOMED.AVPU }], text: 'AVPU' },
        subject: { reference: patientRef },
        valueCodeableConcept: { text: victim.avpu },
      } as fhir4.Observation,
    });
  }

  for (const vs of victim.vitalSigns) {
    const dt = vs.measuredAt.toISOString();
    if (vs.systolicBP != null && vs.diastolicBP != null) {
      entries.push({ resource: buildBpObs(vs.systolicBP, vs.diastolicBP, patientRef, dt) });
    }
    if (vs.heartRate != null) entries.push({ resource: buildIntObs(LOINC.HEART_RATE, vs.heartRate, patientRef, dt) });
    if (vs.respiratoryRate != null) entries.push({ resource: buildIntObs(LOINC.RESPIRATORY_RATE, vs.respiratoryRate, patientRef, dt) });
    if (vs.oxygenSat != null) entries.push({ resource: buildIntObs(LOINC.OXYGEN_SAT, vs.oxygenSat, patientRef, dt) });
    if (vs.temperature != null) entries.push({ resource: buildDecimalObs(LOINC.TEMPERATURE, vs.temperature, patientRef, dt) });
    if (vs.bloodGlucose != null) entries.push({ resource: buildDecimalObs(LOINC.BLOOD_GLUCOSE, vs.bloodGlucose, patientRef, dt) });
    if (vs.painScore != null) entries.push({ resource: buildIntObs(LOINC.PAIN_SCORE, vs.painScore, patientRef, dt) });
  }

  if (victim.medications) {
    entries.push({
      resource: {
        resourceType: 'MedicationStatement',
        status: 'active',
        subject: { reference: patientRef },
        medicationCodeableConcept: { text: victim.medications },
      } as fhir4.MedicationStatement,
    });
  }

  entries.push({ resource: buildEncounter(victim, patientRef) });

  return { resourceType: 'Bundle', type: 'collection', entry: entries };
}

function buildPatient(victim: VictimFull, patientId: string): fhir4.Patient {
  const patient: fhir4.Patient = {
    resourceType: 'Patient',
    id: patientId,
    identifier: [{ system: FHIR_SYSTEM.MITROO_VICTIMS, value: String(victim.id) }],
    name: [{ text: victim.name }],
  };

  if (victim.dateOfBirth) {
    patient.birthDate = victim.dateOfBirth.toISOString().split('T')[0];
  }
  if (victim.gender) {
    patient.gender = victim.gender as fhir4.Patient['gender'];
  }

  const addr: fhir4.Address = {};
  if (victim.address) addr.line = [victim.address];
  if (victim.city) addr.city = victim.city;
  if (victim.postalCode) addr.postalCode = victim.postalCode;
  if (Object.keys(addr).length > 0) patient.address = [addr];

  if (victim.telephone) {
    patient.telecom = [{ system: 'phone', value: victim.telephone, use: 'home' }];
  }

  if (victim.emergencyContact || victim.emergencyPhone) {
    const contact: fhir4.PatientContact = {};
    if (victim.emergencyContact) contact.name = { text: victim.emergencyContact };
    if (victim.emergencyPhone) contact.telecom = [{ system: 'phone', value: victim.emergencyPhone }];
    patient.contact = [contact];
  }

  return patient;
}

function buildCondition(
  text: string,
  category: string,
  subjectRef: string,
  clinicalStatus?: string,
): fhir4.Condition {
  const condition: fhir4.Condition = {
    resourceType: 'Condition',
    subject: { reference: subjectRef },
    code: { text },
    category: [{
      coding: [{ system: FHIR_SYSTEM.CONDITION_CATEGORY, code: category }],
    }],
  };
  if (clinicalStatus) {
    condition.clinicalStatus = {
      coding: [{ system: FHIR_SYSTEM.CONDITION_CLINICAL, code: clinicalStatus }],
    };
  }
  return condition;
}

function buildIntObs(loincCode: string, value: number, subjectRef: string, effectiveDateTime?: string): fhir4.Observation {
  const obs: fhir4.Observation = {
    resourceType: 'Observation',
    status: 'final',
    code: { coding: [{ system: FHIR_SYSTEM.LOINC, code: loincCode }] },
    subject: { reference: subjectRef },
    valueInteger: value,
  };
  if (effectiveDateTime) obs.effectiveDateTime = effectiveDateTime;
  return obs;
}

function buildDecimalObs(loincCode: string, value: number, subjectRef: string, effectiveDateTime?: string): fhir4.Observation {
  const obs: fhir4.Observation = {
    resourceType: 'Observation',
    status: 'final',
    code: { coding: [{ system: FHIR_SYSTEM.LOINC, code: loincCode }] },
    subject: { reference: subjectRef },
    valueQuantity: { value },
  };
  if (effectiveDateTime) obs.effectiveDateTime = effectiveDateTime;
  return obs;
}

function buildBpObs(systolic: number, diastolic: number, subjectRef: string, effectiveDateTime: string): fhir4.Observation {
  return {
    resourceType: 'Observation',
    status: 'final',
    code: { coding: [{ system: FHIR_SYSTEM.LOINC, code: LOINC.BP_PANEL }], text: 'Blood Pressure' },
    subject: { reference: subjectRef },
    effectiveDateTime,
    component: [
      {
        code: { coding: [{ system: FHIR_SYSTEM.LOINC, code: LOINC.SYSTOLIC_BP }] },
        valueQuantity: { value: systolic, unit: 'mmHg', system: FHIR_SYSTEM.UCUM, code: 'mm[Hg]' },
      },
      {
        code: { coding: [{ system: FHIR_SYSTEM.LOINC, code: LOINC.DIASTOLIC_BP }] },
        valueQuantity: { value: diastolic, unit: 'mmHg', system: FHIR_SYSTEM.UCUM, code: 'mm[Hg]' },
      },
    ],
  };
}

function buildEncounter(victim: VictimFull, subjectRef: string): fhir4.Encounter {
  const encounter: fhir4.Encounter = {
    resourceType: 'Encounter',
    status: victim.isFinalized ? 'finished' : 'in-progress',
    class: { system: FHIR_SYSTEM.ACT_CODE, code: 'EMER' },
    subject: { reference: subjectRef },
    period: { start: victim.createdAt.toISOString() },
  };
  if (victim.serviceId != null) {
    encounter.identifier = [{ system: FHIR_SYSTEM.MITROO_SERVICES, value: String(victim.serviceId) }];
  }
  if (victim.isFinalized && victim.finalizedAt) {
    encounter.period!.end = victim.finalizedAt.toISOString();
  }
  return encounter;
}
