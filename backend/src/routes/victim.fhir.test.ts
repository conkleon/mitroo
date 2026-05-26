/// <reference path="../fhir/fhir4.d.ts" />
import request from 'supertest';
import express from 'express';
import jwt from 'jsonwebtoken';

jest.mock('../lib/prisma', () => ({
  __esModule: true,
  default: {
    victim: {
      findUnique: jest.fn(),
      findMany: jest.fn(),
      count: jest.fn(),
      create: jest.fn(),
    },
    service: { findUnique: jest.fn() },
    userDepartment: { count: jest.fn() },
    userService: { findUnique: jest.fn() },
  },
}));

import prisma from '../lib/prisma';
import victimRouter from './victim.routes';

const mockVictimFindUnique = prisma.victim.findUnique as jest.Mock;
const mockVictimCreate = prisma.victim.create as jest.Mock;

const VICTIM_DB = {
  id: 1,
  name: 'Test Patient',
  age: 30,
  dateOfBirth: new Date('1995-06-15'),
  gender: 'female',
  address: null,
  city: null,
  postalCode: null,
  telephone: null,
  emergencyContact: null,
  emergencyPhone: null,
  chiefComplaint: 'Headache',
  allergies: null,
  medications: null,
  medicalHistory: null,
  gcsEye: 4,
  gcsVerbal: 5,
  gcsMotor: 6,
  gcsTotal: 15,
  avpu: 'A',
  latitude: null,
  longitude: null,
  locationNotes: null,
  serviceId: null,
  notes: null,
  isFinalized: false,
  finalizedAt: null,
  finalizedById: null,
  createdById: 1,
  createdAt: new Date('2026-05-26T09:00:00Z'),
  updatedAt: new Date('2026-05-26T09:00:00Z'),
  vitalSigns: [],
  treatments: [],
};

function buildApp() {
  const app = express();
  app.use(express.json());
  app.use('/victims', victimRouter);
  return app;
}

const VALID_API_KEY = 'integration-test-key';
const SYSTEM_USER_ID = '1';

beforeAll(() => {
  process.env.FHIR_API_KEY = VALID_API_KEY;
  process.env.FHIR_SYSTEM_USER_ID = SYSTEM_USER_ID;
  process.env.JWT_SECRET = 'test-jwt-secret';
});

afterAll(() => {
  delete process.env.FHIR_API_KEY;
  delete process.env.FHIR_SYSTEM_USER_ID;
});

beforeEach(() => {
  jest.clearAllMocks();
});

describe('GET /victims/:id/fhir', () => {
  it('returns 401 with no auth', async () => {
    const res = await request(buildApp()).get('/victims/1/fhir');
    expect(res.status).toBe(401);
  });

  it('returns 401 with invalid API key', async () => {
    const res = await request(buildApp())
      .get('/victims/1/fhir')
      .set('x-api-key', 'wrong-key');
    expect(res.status).toBe(401);
  });

  it('returns 404 when victim does not exist', async () => {
    mockVictimFindUnique.mockResolvedValue(null);
    const res = await request(buildApp())
      .get('/victims/999/fhir')
      .set('x-api-key', VALID_API_KEY);
    expect(res.status).toBe(404);
  });

  it('returns FHIR Bundle with correct Content-Type for valid victim', async () => {
    mockVictimFindUnique.mockResolvedValue(VICTIM_DB);
    const res = await request(buildApp())
      .get('/victims/1/fhir')
      .set('x-api-key', VALID_API_KEY);

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch('application/fhir+json');
    expect(res.body.resourceType).toBe('Bundle');
    expect(res.body.type).toBe('collection');

    const patient = res.body.entry.find((e: any) => e.resource?.resourceType === 'Patient');
    expect(patient.resource.name[0].text).toBe('Test Patient');
  });

  it('returns 200 Bundle when authenticated via JWT', async () => {
    mockVictimFindUnique.mockResolvedValue(VICTIM_DB);
    const token = jwt.sign(
      { userId: 1, isAdmin: false },
      process.env.JWT_SECRET!,
    );
    const res = await request(buildApp())
      .get('/victims/1/fhir')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch('application/fhir+json');
    expect(res.body.resourceType).toBe('Bundle');
  });

  it('returns 403 when authenticated user lacks read access', async () => {
    // First call: canReadVictim checks victim ownership (different createdById)
    // Second call: victim fetch after access check (never reached)
    const mockUserService = prisma.userService.findUnique as jest.Mock;
    const mockUserDepartmentCount = prisma.userDepartment.count as jest.Mock;

    // Victim belongs to user 99, not user 2; serviceId is null so no enrollment check
    mockVictimFindUnique.mockResolvedValue({ ...VICTIM_DB, createdById: 99, serviceId: null });
    mockUserService.mockResolvedValue(null);
    mockUserDepartmentCount.mockResolvedValue(0);

    const token = jwt.sign(
      { userId: 2, isAdmin: false },
      process.env.JWT_SECRET!,
    );
    const res = await request(buildApp())
      .get('/victims/1/fhir')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(403);
  });
});

describe('POST /victims/fhir', () => {
  const MINIMAL_BUNDLE = {
    resourceType: 'Bundle',
    type: 'collection',
    entry: [
      {
        resource: {
          resourceType: 'Patient',
          name: [{ text: 'Import Patient' }],
          gender: 'male',
        },
      },
      {
        resource: {
          resourceType: 'Encounter',
          status: 'in-progress',
          class: { system: 'http://terminology.hl7.org/CodeSystem/v3-ActCode', code: 'EMER' },
          subject: { reference: 'Patient/mitroo-0' },
        },
      },
    ],
  };

  it('returns 401 with no auth', async () => {
    const res = await request(buildApp()).post('/victims/fhir').send(MINIMAL_BUNDLE);
    expect(res.status).toBe(401);
  });

  it('returns 400 when body is not a FHIR Bundle', async () => {
    const res = await request(buildApp())
      .post('/victims/fhir')
      .set('x-api-key', VALID_API_KEY)
      .send({ foo: 'bar' });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('Expected FHIR R4 Bundle');
  });

  it('returns 400 when Bundle has no Patient resource', async () => {
    const res = await request(buildApp())
      .post('/victims/fhir')
      .set('x-api-key', VALID_API_KEY)
      .send({ resourceType: 'Bundle', type: 'collection', entry: [] });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('Bundle must contain a Patient resource');
  });

  it('creates and returns victim from valid Bundle', async () => {
    const created = { ...VICTIM_DB, id: 5, name: 'Import Patient' };
    mockVictimCreate.mockResolvedValue(created);

    const res = await request(buildApp())
      .post('/victims/fhir')
      .set('x-api-key', VALID_API_KEY)
      .send(MINIMAL_BUNDLE);

    expect(res.status).toBe(201);
    expect(res.body.name).toBe('Import Patient');
    expect(mockVictimCreate).toHaveBeenCalledTimes(1);

    const callArg = mockVictimCreate.mock.calls[0][0].data;
    expect(callArg.name).toBe('Import Patient');
    expect(callArg.createdById).toBe(parseInt(SYSTEM_USER_ID));
  });
});
