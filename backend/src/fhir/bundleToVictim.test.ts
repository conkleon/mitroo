import { victimToBundle } from './victimToBundle';
import { bundleToVictim, CreateVictimInput } from './bundleToVictim';
import { FHIR_SYSTEM } from './codes';

const FULL_VICTIM = {
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
  locationNotes: null,
  serviceId: 10,
  notes: null,
  isFinalized: false,
  finalizedAt: null,
  finalizedById: null,
  createdById: 2,
  createdAt: new Date('2026-05-26T10:00:00Z'),
  updatedAt: new Date('2026-05-26T10:00:00Z'),
  vitalSigns: [],
  treatments: [],
};

describe('bundleToVictim', () => {
  it('round-trips demographics through export then import', () => {
    const bundle = victimToBundle(FULL_VICTIM as any);
    const result = bundleToVictim(bundle);

    expect(result.name).toBe('Παπαδόπουλος Γεώργιος');
    expect(result.dateOfBirth).toBe('1980-03-15');
    expect(result.gender).toBe('male');
    expect(result.address).toBe('Οδός Αθηνών 5');
    expect(result.city).toBe('Αθήνα');
    expect(result.postalCode).toBe('10001');
    expect(result.telephone).toBe('+302101234567');
    expect(result.emergencyContact).toBe('Παπαδοπούλου Μαρία');
    expect(result.emergencyPhone).toBe('+306912345678');
  });

  it('round-trips clinical fields through export then import', () => {
    const bundle = victimToBundle(FULL_VICTIM as any);
    const result = bundleToVictim(bundle);

    expect(result.chiefComplaint).toBe('Θωρακικό άλγος');
    expect(result.allergies).toBe('Πενικιλίνη');
    expect(result.medications).toBe('Ασπιρίνη 100mg');
    expect(result.medicalHistory).toBe('Υπέρταση');
    expect(result.gcsEye).toBe(4);
    expect(result.gcsVerbal).toBe(5);
    expect(result.gcsMotor).toBe(6);
    expect(result.gcsTotal).toBe(15);
    expect(result.avpu).toBe('A');
  });

  it('round-trips serviceId from Encounter', () => {
    const bundle = victimToBundle(FULL_VICTIM as any);
    const result = bundleToVictim(bundle);

    expect(result.serviceId).toBe(10);
  });

  it('returns null serviceId when Encounter identifier is absent', () => {
    const bundle = victimToBundle({ ...FULL_VICTIM, serviceId: null } as any);
    const result = bundleToVictim(bundle);

    expect(result.serviceId).toBeNull();
  });

  it('returns null for fields absent in the Bundle', () => {
    const minimalBundle: fhir4.Bundle = {
      resourceType: 'Bundle',
      type: 'collection',
      entry: [
        {
          resource: {
            resourceType: 'Patient',
            name: [{ text: 'Test User' }],
          } as fhir4.Patient,
        },
        {
          resource: {
            resourceType: 'Encounter',
            status: 'in-progress',
            class: { system: FHIR_SYSTEM.ACT_CODE, code: 'EMER' },
            subject: { reference: 'Patient/mitroo-99' },
          } as fhir4.Encounter,
        },
      ],
    };
    const result = bundleToVictim(minimalBundle);

    expect(result.name).toBe('Test User');
    expect(result.chiefComplaint).toBeNull();
    expect(result.allergies).toBeNull();
    expect(result.medicalHistory).toBeNull();
    expect(result.medications).toBeNull();
    expect(result.gcsEye).toBeNull();
    expect(result.avpu).toBeNull();
    expect(result.serviceId).toBeNull();
  });

  it('ignores unknown resource types without throwing', () => {
    const bundle = victimToBundle(FULL_VICTIM as any);
    bundle.entry!.push({
      resource: { resourceType: 'DocumentReference' } as any,
    });
    expect(() => bundleToVictim(bundle)).not.toThrow();
  });

  it('throws when Bundle contains no Patient', () => {
    const bundle: fhir4.Bundle = {
      resourceType: 'Bundle',
      type: 'collection',
      entry: [],
    };
    expect(() => bundleToVictim(bundle)).toThrow('Bundle must contain a Patient resource');
  });

  it('calculates age from birthDate on import', () => {
    const bundle = victimToBundle(FULL_VICTIM as any);
    const result = bundleToVictim(bundle);

    // Born 1980-03-15, tested at 2026-05-26 → age 46
    expect(result.age).toBe(46);
  });
});
