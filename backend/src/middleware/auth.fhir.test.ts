import { Request, Response, NextFunction } from 'express';
import { authenticateOrApiKey } from './auth';

const makeReq = (headers: Record<string, string> = {}) =>
  ({ headers, user: undefined } as unknown as Request);

const makeRes = () => {
  const json = jest.fn();
  const status = jest.fn().mockReturnValue({ json });
  return { status, json } as unknown as Response;
};

describe('authenticateOrApiKey', () => {
  beforeEach(() => {
    process.env.FHIR_API_KEY = 'test-secret-key';
    process.env.FHIR_SYSTEM_USER_ID = '99';
    process.env.JWT_SECRET = 'jwt-secret';
  });

  afterEach(() => {
    delete process.env.FHIR_API_KEY;
    delete process.env.FHIR_SYSTEM_USER_ID;
  });

  it('sets admin user and calls next() when API key matches', () => {
    const req = makeReq({ 'x-api-key': 'test-secret-key' });
    const res = makeRes();
    const next = jest.fn() as NextFunction;

    authenticateOrApiKey(req, res, next);

    expect(next).toHaveBeenCalledTimes(1);
    expect(req.user).toEqual({ userId: 99, isAdmin: true });
  });

  it('returns 401 when API key is wrong and no JWT is present', () => {
    const req = makeReq({ 'x-api-key': 'wrong-key' });
    const res = makeRes();
    const next = jest.fn() as NextFunction;

    authenticateOrApiKey(req, res, next);

    expect(next).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(401);
  });

  it('returns 401 when neither API key nor JWT is present', () => {
    const req = makeReq({});
    const res = makeRes();
    const next = jest.fn() as NextFunction;

    authenticateOrApiKey(req, res, next);

    expect(next).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(401);
  });
});
