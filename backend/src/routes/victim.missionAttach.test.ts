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
    userService: { findUnique: jest.fn(), findMany: jest.fn() },
  },
}));

import prisma from '../lib/prisma';
import victimRouter from './victim.routes';

const mockVictimCreate = prisma.victim.create as jest.Mock;
const mockUserServiceFindMany = prisma.userService.findMany as jest.Mock;

function buildApp() {
  const app = express();
  app.use(express.json());
  app.use('/victims', victimRouter);
  return app;
}

const USER_ID = 7;
let token: string;

beforeAll(() => {
  process.env.JWT_SECRET = 'test-jwt-secret';
  token = jwt.sign({ userId: USER_ID, isAdmin: false }, process.env.JWT_SECRET);
});

beforeEach(() => {
  jest.clearAllMocks();
  mockVictimCreate.mockImplementation(async ({ data }: any) => ({ id: 1, ...data }));
});

function acceptedAssignment(id: number, startAt: string, endAt: string | null) {
  return {
    service: { id, startAt: new Date(startAt), endAt: endAt ? new Date(endAt) : null },
  };
}

const BASE_PAYLOAD = {
  name: 'Test Patient',
  gcsEye: 4,
  gcsVerbal: 5,
  gcsMotor: 6,
};

describe('POST /victims — mission auto-attachment', () => {
  it('attaches the mission whose window contains now', async () => {
    jest.useFakeTimers().setSystemTime(new Date('2026-05-26T10:00:00Z'));
    mockUserServiceFindMany.mockResolvedValue([
      acceptedAssignment(42, '2026-05-26T09:00:00Z', '2026-05-26T12:00:00Z'),
    ]);

    const res = await request(buildApp())
      .post('/victims')
      .set('Authorization', `Bearer ${token}`)
      .send(BASE_PAYLOAD);

    expect(res.status).toBe(201);
    expect(mockUserServiceFindMany).toHaveBeenCalledWith({
      where: { userId: USER_ID, status: 'accepted' },
      select: { service: { select: { id: true, startAt: true, endAt: true } } },
    });
    expect(mockVictimCreate.mock.calls[0][0].data.serviceId).toBe(42);
    jest.useRealTimers();
  });

  it('attaches a mission that starts shortly after now, within the grace buffer', async () => {
    jest.useFakeTimers().setSystemTime(new Date('2026-05-26T09:45:00Z'));
    mockUserServiceFindMany.mockResolvedValue([
      acceptedAssignment(42, '2026-05-26T10:00:00Z', '2026-05-26T12:00:00Z'),
    ]);

    const res = await request(buildApp())
      .post('/victims')
      .set('Authorization', `Bearer ${token}`)
      .send(BASE_PAYLOAD);

    expect(res.status).toBe(201);
    expect(mockVictimCreate.mock.calls[0][0].data.serviceId).toBe(42);
    jest.useRealTimers();
  });

  it('does not attach a mission outside the grace buffer', async () => {
    jest.useFakeTimers().setSystemTime(new Date('2026-05-26T06:00:00Z'));
    mockUserServiceFindMany.mockResolvedValue([
      acceptedAssignment(42, '2026-05-26T10:00:00Z', '2026-05-26T12:00:00Z'),
    ]);

    const res = await request(buildApp())
      .post('/victims')
      .set('Authorization', `Bearer ${token}`)
      .send(BASE_PAYLOAD);

    expect(res.status).toBe(201);
    expect(mockVictimCreate.mock.calls[0][0].data.serviceId).toBeNull();
    jest.useRealTimers();
  });

  it('attaches an ongoing mission (no endAt) once it has started', async () => {
    jest.useFakeTimers().setSystemTime(new Date('2026-05-26T15:00:00Z'));
    mockUserServiceFindMany.mockResolvedValue([
      acceptedAssignment(42, '2026-05-26T09:00:00Z', null),
    ]);

    const res = await request(buildApp())
      .post('/victims')
      .set('Authorization', `Bearer ${token}`)
      .send(BASE_PAYLOAD);

    expect(res.status).toBe(201);
    expect(mockVictimCreate.mock.calls[0][0].data.serviceId).toBe(42);
    jest.useRealTimers();
  });

  it('picks the mission closest to now when several are within the buffer', async () => {
    jest.useFakeTimers().setSystemTime(new Date('2026-05-26T10:00:00Z'));
    mockUserServiceFindMany.mockResolvedValue([
      acceptedAssignment(1, '2026-05-26T08:30:00Z', '2026-05-26T09:30:00Z'), // ended 30 min ago
      acceptedAssignment(2, '2026-05-26T09:45:00Z', '2026-05-26T11:00:00Z'), // active now
    ]);

    const res = await request(buildApp())
      .post('/victims')
      .set('Authorization', `Bearer ${token}`)
      .send(BASE_PAYLOAD);

    expect(res.status).toBe(201);
    expect(mockVictimCreate.mock.calls[0][0].data.serviceId).toBe(2);
    jest.useRealTimers();
  });

  it('ignores any client-supplied serviceId and computes it server-side', async () => {
    jest.useFakeTimers().setSystemTime(new Date('2026-05-26T10:00:00Z'));
    mockUserServiceFindMany.mockResolvedValue([]);

    const res = await request(buildApp())
      .post('/victims')
      .set('Authorization', `Bearer ${token}`)
      .send({ ...BASE_PAYLOAD, serviceId: 999 });

    expect(res.status).toBe(201);
    expect(mockVictimCreate.mock.calls[0][0].data.serviceId).toBeNull();
    jest.useRealTimers();
  });
});
