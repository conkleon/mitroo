import { victimToBundle } from './victimToBundle';
import { LOINC, FHIR_SYSTEM } from './codes';

const BASE_VICTIM = {
  id: 1,
  name: 'Παπαδόπουλος Γεώργιος',
  age: 45,
  dateOfBirth: new Date('1980-03-15'),
  gender: 'male',
  address: 'Οδός Αθηνών 5',
  city: 'Αθήνα',
  postalCode: '10001',
  telephone: '+302101234567',
  emergencyContact: 'Παπαδοπούλου Μαρία',
  emergencyPhone: '+306912345678',
  chiefComplaint: 'Θωρακικό άλγος',
  allergies: 'Πενικιλίνη',
  medications: 'Ασπιρίνη 100mg',
  medicalHistory: 'Υπέρταση',
  gcsEye: 4,
  gcsVerbal: 5,
  gcsMotor: 6,
  gcsTotal: 15,
  avpu: 'A',
  latitude: 37.9838,
  longitude: 23.7275,
  locationNotes: 'Κοντά στην είσοδο',
  serviceId: 10,
  notes: 'Σταθερός',
  isFinalized: false,
  finalizedAt: null,
  finalizedById: null,
  createdById: 2,
  createdAt: new Date('2026-05-26T10:00:00Z'),
  updatedAt: new Date('2026-05-26T10:00:00Z'),
  vitalSigns: [],
  treatments: [],
};

describe('victimToBundle', () => {
  it('returns a FHIR R4 collection Bundle', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    expect(bundle.resourceType).toBe('Bundle');
    expect(bundle.type).toBe('collection');
    expect(Array.isArray(bundle.entry)).toBe(true);
  });

  it('includes a Patient with Mitroo identifier', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    const patient = bundle.entry!
      .map(e => e.resource)
      .find(r => r?.resourceType === 'Patient') as fhir4.Patient;

    expect(patient).toBeDefined();
    expect(patient.id).toBe('mitroo-1');
    expect(patient.identifier![0].system).toBe(FHIR_SYSTEM.MITROO_VICTIMS);
    expect(patient.identifier![0].value).toBe('1');
    expect(patient.name![0].text).toBe('Παπαδόπουλος Γεώργιος');
    expect(patient.gender).toBe('male');
    expect(patient.birthDate).toBe('1980-03-15');
  });

  it('maps address fields to Patient.address', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    const patient = bundle.entry!
      .map(e => e.resource)
      .find(r => r?.resourceType === 'Patient') as fhir4.Patient;

    expect(patient.address![0].line![0]).toBe('Οδός Αθηνών 5');
    expect(patient.address![0].city).toBe('Αθήνα');
    expect(patient.address![0].postalCode).toBe('10001');
  });

  it('maps emergency contact to Patient.contact', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    const patient = bundle.entry!
      .map(e => e.resource)
      .find(r => r?.resourceType === 'Patient') as fhir4.Patient;

    expect(patient.contact![0].name!.text).toBe('Παπαδοπούλου Μαρία');
    expect(patient.contact![0].telecom![0].value).toBe('+306912345678');
  });

  it('includes chief complaint as encounter-diagnosis Condition', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    const conditions = bundle.entry!
      .map(e => e.resource)
      .filter((r): r is fhir4.Condition => r?.resourceType === 'Condition');

    const cc = conditions.find(
      c => c.category![0].coding![0].code === 'encounter-diagnosis'
    );
    expect(cc).toBeDefined();
    expect(cc!.code!.text).toBe('Θωρακικό άλγος');
  });

  it('includes medical history as resolved problem-list-item Condition', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    const conditions = bundle.entry!
      .map(e => e.resource)
      .filter((r): r is fhir4.Condition => r?.resourceType === 'Condition');

    const history = conditions.find(
      c => c.clinicalStatus?.coding![0].code === 'resolved'
    );
    expect(history).toBeDefined();
    expect(history!.code!.text).toBe('Υπέρταση');
  });

  it('includes allergies as problem-list-item Condition without resolved status', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    const conditions = bundle.entry!
      .map(e => e.resource)
      .filter((r): r is fhir4.Condition => r?.resourceType === 'Condition');

    const allergy = conditions.find(
      c =>
        c.category![0].coding![0].code === 'problem-list-item' &&
        c.clinicalStatus?.coding![0].code !== 'resolved'
    );
    expect(allergy).toBeDefined();
    expect(allergy!.code!.text).toBe('Πενικιλίνη');
  });

  it('maps GCS scores to Observations with correct LOINC codes', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    const obs = bundle.entry!
      .map(e => e.resource)
      .filter((r): r is fhir4.Observation => r?.resourceType === 'Observation');

    const find = (code: string) => obs.find(o => o.code.coding![0].code === code);

    expect(find(LOINC.GCS_EYE)!.valueInteger).toBe(4);
    expect(find(LOINC.GCS_VERBAL)!.valueInteger).toBe(5);
    expect(find(LOINC.GCS_MOTOR)!.valueInteger).toBe(6);
    expect(find(LOINC.GCS_TOTAL)!.valueInteger).toBe(15);
  });

  it('maps AVPU to an Observation with SNOMED system', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    const obs = bundle.entry!
      .map(e => e.resource)
      .filter((r): r is fhir4.Observation => r?.resourceType === 'Observation');

    const avpuObs = obs.find(o => o.code.coding![0].system === FHIR_SYSTEM.SNOMED);
    expect(avpuObs).toBeDefined();
    expect(avpuObs!.valueCodeableConcept!.text).toBe('A');
  });

  it('maps medications to MedicationStatement', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    const med = bundle.entry!
      .map(e => e.resource)
      .find(r => r?.resourceType === 'MedicationStatement') as fhir4.MedicationStatement;

    expect(med).toBeDefined();
    expect((med as any).medicationCodeableConcept.text).toBe('Ασπιρίνη 100mg');
  });

  it('includes Encounter with serviceId identifier and in-progress status', () => {
    const bundle = victimToBundle(BASE_VICTIM as any);
    const encounter = bundle.entry!
      .map(e => e.resource)
      .find(r => r?.resourceType === 'Encounter') as fhir4.Encounter;

    expect(encounter).toBeDefined();
    expect(encounter.status).toBe('in-progress');
    expect(encounter.identifier![0].system).toBe(FHIR_SYSTEM.MITROO_SERVICES);
    expect(encounter.identifier![0].value).toBe('10');
    expect(encounter.period!.start).toBe('2026-05-26T10:00:00.000Z');
  });

  it('marks Encounter as finished when isFinalized is true', () => {
    const victim = {
      ...BASE_VICTIM,
      isFinalized: true,
      finalizedAt: new Date('2026-05-26T12:00:00Z'),
    };
    const bundle = victimToBundle(victim as any);
    const encounter = bundle.entry!
      .map(e => e.resource)
      .find(r => r?.resourceType === 'Encounter') as fhir4.Encounter;

    expect(encounter.status).toBe('finished');
    expect(encounter.period!.end).toBe('2026-05-26T12:00:00.000Z');
  });

  it('emits BP panel Observation from vitalSigns', () => {
    const victim = {
      ...BASE_VICTIM,
      vitalSigns: [{
        id: 1,
        victimId: 1,
        systolicBP: 120,
        diastolicBP: 80,
        heartRate: 72,
        respiratoryRate: null,
        oxygenSat: null,
        temperature: null,
        bloodGlucose: null,
        painScore: null,
        measuredAt: new Date('2026-05-26T10:30:00Z'),
        notes: null,
        measuredBy: null,
      }],
    };
    const bundle = victimToBundle(victim as any);
    const obs = bundle.entry!
      .map(e => e.resource)
      .filter((r): r is fhir4.Observation => r?.resourceType === 'Observation');

    const bp = obs.find(o => o.code.coding![0].code === LOINC.BP_PANEL);
    expect(bp).toBeDefined();
    expect(bp!.component![0].valueQuantity!.value).toBe(120);
    expect(bp!.component![1].valueQuantity!.value).toBe(80);

    const hr = obs.find(o => o.code.coding![0].code === LOINC.HEART_RATE);
    expect(hr!.valueInteger).toBe(72);
  });

  it('omits entries for null optional fields', () => {
    const victim = {
      ...BASE_VICTIM,
      chiefComplaint: null,
      allergies: null,
      medications: null,
      medicalHistory: null,
      gcsEye: null,
      gcsVerbal: null,
      gcsMotor: null,
      gcsTotal: null,
      avpu: null,
    };
    const bundle = victimToBundle(victim as any);
    const types = bundle.entry!.map(e => e.resource?.resourceType);

    expect(types).not.toContain('Condition');
    expect(types).not.toContain('MedicationStatement');
    const obsEntries = bundle.entry!.filter(e => e.resource?.resourceType === 'Observation');
    expect(obsEntries).toHaveLength(0);
  });
});
