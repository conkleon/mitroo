import { Request, Response, NextFunction } from "express";
import jwt from "jsonwebtoken";
import prisma from "../lib/prisma";

export interface AuthPayload {
  userId: number;
  isAdmin: boolean;
}

declare global {
  namespace Express {
    interface Request {
      user?: AuthPayload;
    }
  }
}

/** Require a valid JWT. */
export function authenticate(req: Request, res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  if (!header?.startsWith("Bearer ")) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  const token = header.split(" ")[1];
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET!) as AuthPayload;
    req.user = payload;
    next();
  } catch {
    res.status(401).json({ error: "Invalid or expired token" });
  }
}

/** Require system-admin flag. */
export function requireAdmin(req: Request, res: Response, next: NextFunction): void {
  if (!req.user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }
  if (!req.user.isAdmin) {
    res.status(403).json({ error: "Admin access required" });
    return;
  }
  next();
}

export async function getMissionAdminDepartmentIds(userId: number): Promise<number[]> {
  const memberships = await prisma.userDepartment.findMany({
    where: {
      userId,
      role: "missionAdmin",
    },
    select: { departmentId: true },
  });

  return memberships.map((membership) => membership.departmentId);
}

export async function isMissionAdminInDepartment(userId: number, departmentId: number): Promise<boolean> {
  const count = await prisma.userDepartment.count({
    where: {
      userId,
      departmentId,
      role: "missionAdmin",
    },
  });

  return count > 0;
}
