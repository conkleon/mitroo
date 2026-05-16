import { Router, Request, Response } from "express";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate } from "../middleware/auth";

const router = Router();
router.use(authenticate);

// ── Helpers ─────────────────────────────────────

/** Check whether the caller is a global admin or has `itemAdmin` / `missionAdmin` role in any department. */
async function isItemManager(req: Request): Promise<boolean> {
  if (req.user?.isAdmin) return true;
  const count = await prisma.userDepartment.count({
    where: { userId: req.user!.userId, role: { in: ["itemAdmin", "missionAdmin"] } },
  });
  return count > 0;
}

/** Recursively collect all descendant item IDs inside a container (BFS). */
async function getAllContainedItemIds(containerId: number): Promise<number[]> {
  const ids: number[] = [];
  const queue = [containerId];
  while (queue.length > 0) {
    const parentId = queue.shift()!;
    const children = await prisma.item.findMany({
      where: { containedById: parentId },
      select: { id: true, isContainer: true },
    });
    for (const child of children) {
      ids.push(child.id);
      if (child.isContainer) queue.push(child.id);
    }
  }
  return ids;
}

// Shared include used when returning a single item with full relations.
const ITEM_DETAIL_INCLUDE = {
  department: { select: { id: true, name: true } },
  containedBy: { select: { id: true, name: true } },
  contents: {
    select: {
      id: true,
      name: true,
      barCode: true,
      imagePath: true,
      isContainer: true,
      location: true,
      assignedTo: { select: { id: true, forename: true, surname: true } },
    },
  },
  assignedTo: { select: { id: true, forename: true, surname: true, eame: true } },
  category: { select: { id: true, name: true, departmentId: true } },
  itemServices: {
    include: {
      service: { select: { id: true, name: true } },
      user: { select: { id: true, forename: true, surname: true } },
    },
    orderBy: { assignedAt: "desc" as const },
  },
  comments: {
    include: { user: { select: { id: true, forename: true, surname: true, eame: true } } },
    orderBy: { createdAt: "desc" as const },
  },
};

// ── Schemas ─────────────────────────────────────

const createSchema = z.object({
  name: z.string().min(1).max(255),
  description: z.string().optional().nullable(),
  barCode: z.string().optional().nullable(),
  containedById: z.number().int().optional().nullable(),
  isContainer: z.boolean().optional(),
  location: z.string().optional().nullable(),
  expirationDate: z.string().optional().nullable(), // ISO-8601
  quantity: z.number().int().min(0).optional(),
  availableForAssignment: z.boolean().optional(),
  categoryId: z.number().int().optional().nullable(),
  departmentId: z.number().int(),
});

const assignServiceSchema = z.object({
  serviceId: z.number().int(),
  userId: z.number().int(),
  itemId: z.number().int(),
  comment: z.string().optional(),
});

const assignUserSchema = z.object({
  userId: z.number().int(),
});
// ── CSV Export / Import (MUST be before /:id routes) ──────────

const CSV_HEADER_FULL =
  "id,name,description,barCode,location,categoryName,isContainer,availableForAssignment,quantity,containedById,containedByName,assignedToId,assignedToName,expirationDate,departmentId,departmentName";

const CSV_HEADER_TEMPLATE =
  "name,description,barCode,location,categoryName,isContainer,quantity,expirationDate";

function csvRow(item: any): string {
  const assignedName = item.assignedTo
    ? `${item.assignedTo.forename} ${item.assignedTo.surname}`
    : "";
  return [
    item.id,
    `"${(item.name || "").replace(/"/g, '""')}"`,
    `"${(item.description || "").replace(/"/g, '""')}"`,
    `"${item.barCode || ""}"`,
    `"${(item.location || "").replace(/"/g, '""')}"`,
    `"${(item.category?.name || "").replace(/"/g, '""')}"`,
    item.isContainer,
    item.availableForAssignment,
    item.quantity,
    item.containedById || "",
    `"${item.containedBy?.name || ""}"`,
    item.assignedToId || "",
    `"${assignedName}"`,
    item.expirationDate ? item.expirationDate.toISOString() : "",
    item.departmentId,
    `"${item.department?.name || ""}"`,
  ].join(",");
}

// GET /api/items/export/csv
// ?template=true — returns a single example row instead of all items
router.get("/export/csv", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }

  const isTemplate = req.query.template === "true";

  if (isTemplate) {
    const example = [
      CSV_HEADER_TEMPLATE,
      '"Παράδειγμα","Περιγραφή","BC-001","Αποθήκη Α","Αναλώσιμα",false,1,',
    ].join("\n");
    res.setHeader("Content-Type", "text/csv");
    res.setHeader(
      "Content-Disposition",
      "attachment; filename=items_template.csv",
    );
    res.send(example);
    return;
  }

  const items = await prisma.item.findMany({
    include: {
      containedBy: { select: { id: true, name: true } },
      assignedTo: { select: { id: true, forename: true, surname: true } },
      department: { select: { id: true, name: true } },
      category: { select: { name: true } },
    },
    orderBy: { id: "asc" },
  });

  const csv = [CSV_HEADER_FULL, ...items.map(csvRow)].join("\n");
  res.setHeader("Content-Type", "text/csv");
  res.setHeader("Content-Disposition", "attachment; filename=items.csv");
  res.send(csv);
});

const importSchema = z.object({
  departmentId: z.number().int(),
  rows: z
    .array(z.record(z.unknown()))
    .min(1),
});

// POST /api/items/import/csv
router.post("/import/csv", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }

  let body: { departmentId: number; rows: Record<string, unknown>[] };
  try {
    body = importSchema.parse(req.body);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res
        .status(400)
        .json({ error: "Validation failed", details: err.errors });
      return;
    }
    throw err;
  }

  const { departmentId, rows } = body;

  // Resolve category cache: name → categoryId for this department
  const catCache = new Map<string, number>();
  async function resolveCategory(
    name: string,
  ): Promise<number> {
    const key = name.trim();
    const cached = catCache.get(key);
    if (cached !== undefined) return cached;

    let cat = await prisma.itemCategory.findFirst({
      where: { name: key, departmentId },
    });
    if (!cat) {
      cat = await prisma.itemCategory.create({
        data: { name: key, departmentId },
      });
    }
    catCache.set(key, cat.id);
    return cat.id;
  }

  let created = 0;
  const errors: string[] = [];
  for (let i = 0; i < rows.length; i++) {
    const r = rows[i];
    const rowNum = i + 1;

    const name =
      typeof r.name === "string" ? r.name.trim() : "";
    if (!name) {
      errors.push(`Row ${rowNum}: name is required`);
      continue;
    }

    try {
      let categoryId: number | null = null;
      if (typeof r.categoryName === "string" && r.categoryName.trim()) {
        categoryId = await resolveCategory(r.categoryName);
      }

      const data: any = {
        name,
        departmentId,
        description:
          typeof r.description === "string" && r.description.trim()
            ? r.description.trim()
            : null,
        barCode:
          typeof r.barCode === "string" && r.barCode.trim()
            ? r.barCode.trim()
            : null,
        location:
          typeof r.location === "string" && r.location.trim()
            ? r.location.trim()
            : null,
        categoryId,
        isContainer: r.isContainer === true || r.isContainer === "true",
        availableForAssignment:
          r.availableForAssignment === true ||
          r.availableForAssignment === "true",
        quantity:
          r.quantity !== undefined && r.quantity !== ""
            ? Number(r.quantity)
            : 1,
        expirationDate: r.expirationDate
          ? new Date(r.expirationDate as string)
          : null,
      };

      await prisma.item.create({ data });
      created++;
    } catch (e: any) {
      errors.push(`Row ${rowNum}: ${e.message}`);
    }
  }

  res.json({ created, errors });
});
// ── GET /api/items ──────────────────────────────
router.get("/", async (req: Request, res: Response) => {
  const { containerId, search, barCode, available, categoryId, departmentId, page, limit, sortField, sortOrder } = req.query;
  const where: any = {};
  if (containerId) where.containedById = Number(containerId);
  if (search) {
    const term = { contains: String(search), mode: "insensitive" as const };
    where.OR = [{ name: term }, { description: term }];
  }
  if (barCode) where.barCode = String(barCode);
  if (categoryId) where.categoryId = Number(categoryId);
  if (departmentId) where.departmentId = Number(departmentId);
  if (available === "true") {
    where.availableForAssignment = true;
    where.assignedToId = null; // only show unassigned items
  }

  const pageNum = Math.max(1, parseInt(String(page || "1"), 10) || 1);
  const pageSize = Math.min(10000, Math.max(1, parseInt(String(limit || "20"), 10) || 20));

  const include = {
    department: { select: { id: true, name: true } },
    containedBy: { select: { id: true, name: true } },
    assignedTo: { select: { id: true, forename: true, surname: true } },
    category: { select: { id: true, name: true, departmentId: true } },
    _count: { select: { contents: true } },
    attachments: {
      where: { isImage: true },
      select: { id: true, thumbnailPath: true },
      take: 1,
      orderBy: { uploadedAt: "asc" as const },
    },
  };

  const [items, total] = await Promise.all([
    prisma.item.findMany({
      where,
      include,
      orderBy: (() => {
        const validSortFields = ["name", "createdAt", "updatedAt", "quantity", "location", "departmentId", "categoryId", "availableForAssignment"];
        const field = String(sortField || "name");
        if (validSortFields.includes(field)) {
          return { [field]: sortOrder === "desc" ? "desc" : "asc" };
        }
        return { name: "asc" as const };
      })(),
      skip: (pageNum - 1) * pageSize,
      take: pageSize,
    }),
    prisma.item.count({ where }),
  ]);

  res.json({ data: items, total, page: pageNum, limit: pageSize, totalPages: Math.ceil(total / pageSize) });
});

// ── GET /api/items/barcode/:code ────────────────
// Returns all items matching a barcode (useful after scanning a barcode)
router.get("/barcode/:code", async (req: Request, res: Response) => {
  const items = await prisma.item.findMany({
    where: { barCode: String(req.params.code) },
    include: {
      department: { select: { id: true, name: true } },
      containedBy: { select: { id: true, name: true } },
      assignedTo: { select: { id: true, forename: true, surname: true } },
      category: { select: { id: true, name: true, departmentId: true } },
      _count: { select: { contents: true } },
    },
    orderBy: { name: "asc" },
  });
  res.json(items);
});

// ── POST /api/items ─────────────────────────────
router.post("/", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  try {
    const body = createSchema.parse(req.body);
    const data: any = { ...body };
    // Convert ISO string to Date
    if (data.expirationDate) data.expirationDate = new Date(data.expirationDate);
    // If containedById is set, verify the target is a container
    if (data.containedById) {
      const parent = await prisma.item.findUnique({ where: { id: data.containedById } });
      if (!parent || !parent.isContainer) {
        res.status(400).json({ error: "Target item is not a container" });
        return;
      }
    }
    const item = await prisma.item.create({ data, include: ITEM_DETAIL_INCLUDE });
    res.status(201).json(item);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── GET /api/items/:id ──────────────────────────
router.get("/:id", async (req: Request, res: Response) => {
  const item = await prisma.item.findUnique({
    where: { id: Number(req.params.id) },
    include: ITEM_DETAIL_INCLUDE,
  });
  if (!item) { res.status(404).json({ error: "Item not found" }); return; }
  res.json(item);
});

// ── PATCH /api/items/:id ────────────────────────
router.patch("/:id", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  try {
    const body = createSchema.partial().parse(req.body);
    const data: any = { ...body };
    if (data.expirationDate !== undefined) {
      data.expirationDate = data.expirationDate ? new Date(data.expirationDate) : null;
    }
    if (data.containedById) {
      const parent = await prisma.item.findUnique({ where: { id: data.containedById } });
      if (!parent || !parent.isContainer) {
        res.status(400).json({ error: "Target item is not a container" });
        return;
      }
    }
    const item = await prisma.item.update({
      where: { id: Number(req.params.id) },
      data,
      include: ITEM_DETAIL_INCLUDE,
    });
    res.json(item);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// ── DELETE /api/items/:id ───────────────────────
router.delete("/:id", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  await prisma.item.delete({ where: { id: Number(req.params.id) } });
  res.status(204).end();
});

// ── Self-assign: regular user claims an available item ─────

// POST /api/items/:id/self-assign
router.post("/:id/self-assign", async (req: Request, res: Response) => {
  const itemId = Number(req.params.id);
  const userId = req.user!.userId;

  const item = await prisma.item.findUnique({ where: { id: itemId } });
  if (!item) { res.status(404).json({ error: "Item not found" }); return; }
  if (!item.availableForAssignment) {
    res.status(400).json({ error: "Item is not available for assignment" }); return;
  }
  if (item.assignedToId) {
    res.status(400).json({ error: "Item is already assigned to someone" }); return;
  }

  const updated = await prisma.$transaction(async (tx) => {
    const result = await tx.item.update({
      where: { id: itemId },
      data: { assignedToId: userId },
      include: ITEM_DETAIL_INCLUDE,
    });
    if (item.isContainer) {
      const containedIds = await getAllContainedItemIds(itemId);
      if (containedIds.length > 0) {
        await tx.item.updateMany({
          where: { id: { in: containedIds } },
          data: { assignedToId: userId },
        });
      }
    }
    return result;
  });
  res.json(updated);
});

// POST /api/items/:id/self-unassign
router.post("/:id/self-unassign", async (req: Request, res: Response) => {
  const itemId = Number(req.params.id);
  const userId = req.user!.userId;

  const item = await prisma.item.findUnique({ where: { id: itemId } });
  if (!item) { res.status(404).json({ error: "Item not found" }); return; }
  if (item.assignedToId !== userId) {
    res.status(403).json({ error: "Item is not assigned to you" }); return;
  }

  const updated = await prisma.$transaction(async (tx) => {
    await tx.itemService.deleteMany({ where: { itemId, userId } });
    if (item.isContainer) {
      const containedIds = await getAllContainedItemIds(itemId);
      if (containedIds.length > 0) {
        await tx.itemService.deleteMany({ where: { itemId: { in: containedIds }, userId } });
        await tx.item.updateMany({
          where: { id: { in: containedIds } },
          data: { assignedToId: null },
        });
      }
    }
    return tx.item.update({
      where: { id: itemId },
      data: { assignedToId: null },
      include: ITEM_DETAIL_INCLUDE,
    });
  });
  res.json(updated);
});

// ── Assign / unassign item to a user ────────────

// POST /api/items/:id/assign-user
router.post("/:id/assign-user", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  try {
    const { userId } = assignUserSchema.parse(req.body);
    const [existingItem, user] = await Promise.all([
      prisma.item.findUnique({ where: { id: Number(req.params.id) } }),
      prisma.user.findUnique({ where: { id: userId } }),
    ]);
    if (!existingItem) { res.status(404).json({ error: "Item not found" }); return; }
    if (!user) { res.status(404).json({ error: "User not found" }); return; }
    const item = await prisma.$transaction(async (tx) => {
      const result = await tx.item.update({
        where: { id: Number(req.params.id) },
        data: { assignedToId: userId },
        include: ITEM_DETAIL_INCLUDE,
      });
      if (existingItem.isContainer) {
        const containedIds = await getAllContainedItemIds(Number(req.params.id));
        if (containedIds.length > 0) {
          await tx.item.updateMany({
            where: { id: { in: containedIds } },
            data: { assignedToId: userId },
          });
        }
      }
      return result;
    });
    res.json(item);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    throw err;
  }
});

// DELETE /api/items/:id/assign-user
router.delete("/:id/assign-user", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  const itemId = Number(req.params.id);
  const existing = await prisma.item.findUnique({ where: { id: itemId } });
  if (!existing) { res.status(404).json({ error: "Item not found" }); return; }
  const item = await prisma.$transaction(async (tx) => {
    const assignedUserId = existing.assignedToId;
    if (assignedUserId) {
      await tx.itemService.deleteMany({ where: { itemId, userId: assignedUserId } });
    }
    if (existing.isContainer) {
      const containedIds = await getAllContainedItemIds(itemId);
      if (containedIds.length > 0) {
        if (assignedUserId) {
          await tx.itemService.deleteMany({ where: { itemId: { in: containedIds }, userId: assignedUserId } });
        }
        await tx.item.updateMany({
          where: { id: { in: containedIds } },
          data: { assignedToId: null },
        });
      }
    }
    return tx.item.update({
      where: { id: itemId },
      data: { assignedToId: null },
      include: ITEM_DETAIL_INCLUDE,
    });
  });
  res.json(item);
});

// ── Move item into / out of a container ─────────

// PATCH /api/items/:id/move
router.patch("/:id/move", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  const { containerId } = req.body; // null = remove from container
  if (containerId != null) {
    const parent = await prisma.item.findUnique({ where: { id: containerId } });
    if (!parent || !parent.isContainer) {
      res.status(400).json({ error: "Target item is not a container" });
      return;
    }
    // Prevent placing a container inside itself
    if (containerId === Number(req.params.id)) {
      res.status(400).json({ error: "Cannot place an item inside itself" });
      return;
    }
  }
  const item = await prisma.item.update({
    where: { id: Number(req.params.id) },
    data: { containedById: containerId ?? null },
    include: ITEM_DETAIL_INCLUDE,
  });
  res.json(item);
});

// ── Item ↔ Service assignments ──────────────────

// POST /api/items/assign
router.post("/assign", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  try {
    const data = assignServiceSchema.parse(req.body);
    const [service, user, item] = await Promise.all([
      prisma.service.findUnique({ where: { id: data.serviceId } }),
      prisma.user.findUnique({ where: { id: data.userId } }),
      prisma.item.findUnique({ where: { id: data.itemId } }),
    ]);
    if (!service) { res.status(404).json({ error: "Service not found" }); return; }
    if (!user) { res.status(404).json({ error: "User not found" }); return; }
    if (!item) { res.status(404).json({ error: "Item not found" }); return; }
    const record = await prisma.itemService.create({
      data,
      include: { item: true, service: { select: { id: true, name: true } }, user: { select: { id: true, forename: true, surname: true } } },
    });
    res.status(201).json(record);
  } catch (err: any) {
    if (err instanceof z.ZodError) { res.status(400).json({ error: "Validation failed", details: err.errors }); return; }
    if ((err as any).code === "P2002") { res.status(409).json({ error: "Item already assigned to this user in this service" }); return; }
    throw err;
  }
});

// ── DELETE /api/items/assign/:id
router.delete("/assign/:id", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  const existing = await prisma.itemService.findUnique({ where: { id: Number(req.params.id) } });
  if (!existing) { res.status(404).json({ error: "Assignment not found" }); return; }
  await prisma.itemService.delete({ where: { id: Number(req.params.id) } });
  res.status(204).end();
});

// ── PATCH /api/items/:id/toggle-availability ──────────
router.patch("/:id/toggle-availability", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  const item = await prisma.item.findUnique({ where: { id: Number(req.params.id) } });
  if (!item) { res.status(404).json({ error: "Item not found" }); return; }
  const updated = await prisma.item.update({
    where: { id: item.id },
    data: { availableForAssignment: !item.availableForAssignment },
    include: ITEM_DETAIL_INCLUDE,
  });
  res.json(updated);
});

// ── Item Comments ───────────────────────────────

// GET /api/items/:id/comments
router.get("/:id/comments", async (req: Request, res: Response) => {
  const comments = await prisma.itemComment.findMany({
    where: { itemId: Number(req.params.id) },
    include: { user: { select: { id: true, forename: true, surname: true, eame: true } } },
    orderBy: { createdAt: "desc" },
  });
  res.json(comments);
});

// POST /api/items/:id/comments
router.post("/:id/comments", async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const itemId = Number(req.params.id);
  const { text } = req.body;
  if (!text || typeof text !== "string" || text.trim().length === 0) {
    res.status(400).json({ error: "Text is required" });
    return;
  }

  // Allow: admin, itemAdmin, or user who has this item assigned
  const isManager = await isItemManager(req);
  if (!isManager) {
    const item = await prisma.item.findUnique({ where: { id: itemId } });
    if (!item || item.assignedToId !== userId) {
      res.status(403).json({ error: "Only assigned user or item admin can comment" });
      return;
    }
  }

  const comment = await prisma.itemComment.create({
    data: { itemId, userId, text: text.trim() },
    include: { user: { select: { id: true, forename: true, surname: true, eame: true } } },
  });
  res.status(201).json(comment);
});

// DELETE /api/items/:id/comments/:commentId
router.delete("/:id/comments/:commentId", async (req: Request, res: Response) => {
  if (!(await isItemManager(req))) {
    res.status(403).json({ error: "Item admin access required" });
    return;
  }
  await prisma.itemComment.delete({ where: { id: Number(req.params.commentId) } });
  res.status(204).end();
});

export default router;
