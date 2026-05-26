export const LOINC = {
  GCS_EYE: '9267-6',
  GCS_VERBAL: '9270-0',
  GCS_MOTOR: '9268-4',
  GCS_TOTAL: '9269-2',
  SYSTOLIC_BP: '8480-6',
  DIASTOLIC_BP: '8462-4',
  BP_PANEL: '55284-4',
  HEART_RATE: '8867-4',
  RESPIRATORY_RATE: '9279-1',
  OXYGEN_SAT: '59408-5',
  TEMPERATURE: '8310-5',
  BLOOD_GLUCOSE: '15074-8',
  PAIN_SCORE: '72514-3',
} as const;

export const SNOMED = {
  AVPU: '67521003',
} as const;

export const FHIR_SYSTEM = {
  LOINC: 'http://loinc.org',
  SNOMED: 'http://snomed.info/sct',
  CONDITION_CATEGORY: 'http://terminology.hl7.org/CodeSystem/condition-category',
  CONDITION_CLINICAL: 'http://terminology.hl7.org/CodeSystem/condition-clinical',
  ACT_CODE: 'http://terminology.hl7.org/CodeSystem/v3-ActCode',
  UCUM: 'http://unitsofmeasure.org',
  MITROO_VICTIMS: 'https://mitroo.app/victims',
  MITROO_SERVICES: 'https://mitroo.app/services',
} as const;
