import { Router, Request, Response } from "express";
import multer from "multer";
import path from "path";
import fs from "fs";
import sharp from "sharp";
import prisma from "../lib/prisma";
import { authenticate } from "../middleware/auth";

const router = Router();
router.use(authenticate);

// ── Constants ───────────────────────────────────
const BASE_UPLOAD_DIR = path.resolve(__dirname, "../../uploads");
const ENTITY_TYPES = ["users", "departments", "services", "items", "vehicles"] as const;
type EntityType = (typeof ENTITY_TYPES)[number];

const ALLOWED_IMAGE_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/gif",
  "image/avif",
]);

const ALLOWED_FILE_TYPES = new Set([
  ...ALLOWED_IMAGE_TYPES,
  "application/pdf",
  "application/msword",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "application/vnd.ms-excel",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "text/csv",
]);

const MAX_FILE_SIZE = 20 * 1024 * 1024; // 20 MB
const THUMB_WIDTH = 300;
const THUMB_HEIGHT = 300;
const MAX_IMAGE_WIDTH = 1920;
const MAX_IMAGE_HEIGHT = 1920;

// ── Helpers ─────────────────────────────────────

/** Map query param key → entity type subdirectory name */
const FK_TO_ENTITY: Record<string, EntityType> = {
  userId: "users",
  departmentId: "departments",
  serviceId: "services",
  itemId: "items",
  vehicleId: "vehicles",
};

/** Check whether the caller is admin or has itemAdmin/missionAdmin role. */
async function isFileManager(req: Request): Promise<boolean> {
  if (req.user?.isAdmin) return true;
  const count = await prisma.userDepartment.count({
    where: { userId: req.user!.userId, role: { in: ["itemAdmin", "missionAdmin"] } },
  });
  return count > 0;
}

/** Build the date-based directory:  uploads/{entity}/{YYYY}/{MM} */
function buildEntityDir(entityType: EntityType): string {
  const now = new Date();
  const yyyy = String(now.getFullYear());
  const mm = String(now.getMonth() + 1).padStart(2, "0");
  return path.join(BASE_UPLOAD_DIR, entityType, yyyy, mm);
}

/** Parse exactly one entity FK from query params */
function parseEntityFk(query: Record<string, any>): { fk: Record<string, number>; entityType: EntityType } | null {
  for (const [qk, entity] of Object.entries(FK_TO_ENTITY)) {
    if (query[qk]) {
      const id = Number(query[qk]);
      if (Number.isNaN(id) || id <= 0) continue;
      return { fk: { [qk]: id }, entityType: entity };
    }
  }
  return null;
}

/** Validate that the referenced entity actually exists */
async function validateEntity(fk: Record<string, number>): Promise<boolean> {
  if (fk.userId) return !!(await prisma.user.findUnique({ where: { id: fk.userId }, select: { id: true } }));
  if (fk.departmentId) return !!(await prisma.department.findUnique({ where: { id: fk.departmentId }, select: { id: true } }));
  if (fk.serviceId) return !!(await prisma.service.findUnique({ where: { id: fk.serviceId }, select: { id: true } }));
  if (fk.itemId) return !!(await prisma.item.findUnique({ where: { id: fk.itemId }, select: { id: true } }));
  if (fk.vehicleId) return !!(await prisma.vehicle.findUnique({ where: { id: fk.vehicleId }, select: { id: true } }));
  return false;
}

/** Generate a unique filename preserving original extension */
function uniqueFilename(originalName: string): string {
  const ext = path.extname(originalName).toLowerCase();
  const ts = Date.now();
  const rand = Math.random().toString(36).slice(2, 10);
  return `${ts}-${rand}${ext}`;
}

/** Generate thumbnail for an image and return metadata + thumb relative path */
async function processImage(
  diskPath: string,
  relDir: string,
  filename: string,
): Promise<{ thumbnailPath: string; width: number; height: number }> {
  const thumbDir = path.join(path.dirname(diskPath), "thumbs");
  if (!fs.existsSync(thumbDir)) fs.mkdirSync(thumbDir, { recursive: true });

  const thumbFilename = filename;
  const thumbDisk = path.join(thumbDir, thumbFilename);

  const metadata = await sharp(diskPath).metadata();

  await sharp(diskPath)
    .resize(THUMB_WIDTH, THUMB_HEIGHT, { fit: "inside", withoutEnlargement: true })
    .webp({ quality: 75 })
    .toFile(thumbDisk.replace(/\.[^.]+$/, ".webp"));

  const webpThumbName = thumbFilename.replace(/\.[^.]+$/, ".webp");

  return {
    thumbnailPath: `/${relDir}/thumbs/${webpThumbName}`,
    width: metadata.width ?? 0,
    height: metadata.height ?? 0,
  };
}

/** Clean up disk files (original + thumbnail) */
function removeFromDisk(filePath: string, thumbnailPath?: string | null) {
  const abs = path.resolve(__dirname, "../..", filePath.replace(/^\//, ""));
  if (fs.existsSync(abs)) fs.unlinkSync(abs);
  if (thumbnailPath) {
    const tAbs = path.resolve(__dirname, "../..", thumbnailPath.replace(/^\//, ""));
    if (fs.existsSync(tAbs)) fs.unlinkSync(tAbs);
  }
}

/** Resolve MIME type from file extension when client sends octet-stream */
function resolveMime(file: Express.Multer.File): string {
  if (file.mimetype && file.mimetype !== 'application/octet-stream') return file.mimetype;
  const ext = path.extname(file.originalname).toLowerCase();
  const map: Record<string, string> = {
    '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png',
    '.gif': 'image/gif', '.webp': 'image/webp', '.avif': 'image/avif',
    '.pdf': 'application/pdf', '.doc': 'application/msword',
    '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.xls': 'application/vnd.ms-excel',
    '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    '.csv': 'text/csv',
  };
  return map[ext] ?? file.mimetype;
}

// ── Multer: memory storage (buffer) for image processing pipeline ───
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_FILE_SIZE },
  fileFilter: (_req, file, cb) => {
    const mime = resolveMime(file);
    if (!ALLOWED_FILE_TYPES.has(mime)) {
      cb(new Error(`File type ${file.mimetype} is not allowed`));
      return;
    }
    // Patch the mimetype so downstream code uses the resolved value
    file.mimetype = mime;
    cb(null, true);
  },
});

// ── Shared upload handler ───────────────────────
async function handleUpload(
  file: Express.Multer.File,
  entityType: EntityType,
  fk: Record<string, number>,
) {
  const dir = buildEntityDir(entityType);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

  const filename = uniqueFilename(file.originalname);
  const diskPath = path.join(dir, filename);

  // Relative path from uploads root for DB storage
  const relDir = path.relative(BASE_UPLOAD_DIR, dir).replace(/\\/g, "/");
  const relFilePath = `uploads/${relDir}/${filename}`;

  const isImage = ALLOWED_IMAGE_TYPES.has(file.mimetype);

  // Resize image to max dimensions before saving; keep buffer for thumbnail step
  let buffer = file.buffer;
  if (isImage) {
    const meta = await sharp(file.buffer).metadata();
    if (meta.width && meta.height && (meta.width > MAX_IMAGE_WIDTH || meta.height > MAX_IMAGE_HEIGHT)) {
      buffer = await sharp(file.buffer)
        .resize(MAX_IMAGE_WIDTH, MAX_IMAGE_HEIGHT, { fit: "inside", withoutEnlargement: true })
        .toBuffer();
    }
  }

  // Write (possibly resized) file to disk
  fs.writeFileSync(diskPath, buffer);

  let imageData: { thumbnailPath: string; width: number; height: number } | null = null;
  if (isImage) {
    imageData = await processImage(diskPath, `uploads/${relDir}`, filename);
  }

  return prisma.fileAttachment.create({
    data: {
      fileName: file.originalname,
      filePath: `/${relFilePath}`,
      mimeType: file.mimetype,
      fileSize: buffer.length,
      isImage,
      thumbnailPath: imageData?.thumbnailPath ?? null,
      width: imageData?.width ?? null,
      height: imageData?.height ?? null,
      ...fk,
    },
  });
}

// ── GET /api/files?userId=&departmentId=&… ──────
router.get("/", async (req: Request, res: Response) => {
  const parsed = parseEntityFk(req.query as Record<string, any>);
  const where = parsed ? parsed.fk : {};

  const page = Math.max(1, Number(req.query.page) || 1);
  const limit = Math.min(100, Math.max(1, Number(req.query.limit) || 50));
  const imagesOnly = req.query.imagesOnly === "true";

  if (imagesOnly) Object.assign(where, { isImage: true });

  const [files, total] = await Promise.all([
    prisma.fileAttachment.findMany({
      where,
      orderBy: { uploadedAt: "desc" },
      skip: (page - 1) * limit,
      take: limit,
    }),
    prisma.fileAttachment.count({ where }),
  ]);

  res.json({ data: files, total, page, limit });
});

// ── POST /api/files?itemId=1 (single file) ─────
router.post("/", upload.single("file"), async (req: Request, res: Response) => {
  if (!(await isFileManager(req))) {
    res.status(403).json({ error: "Admin or item-admin access required" });
    return;
  }
  if (!req.file) {
    res.status(400).json({ error: "No file uploaded" });
    return;
  }

  const parsed = parseEntityFk(req.query as Record<string, any>);
  if (!parsed) {
    res.status(400).json({ error: "Specify one entity query param: userId, departmentId, serviceId, itemId, or vehicleId" });
    return;
  }

  const exists = await validateEntity(parsed.fk);
  if (!exists) {
    res.status(404).json({ error: "Referenced entity not found" });
    return;
  }

  const record = await handleUpload(req.file, parsed.entityType, parsed.fk);
  res.status(201).json(record);
});

// ── POST /api/files/bulk?departmentId=1 (up to 10 files) ─
router.post("/bulk", upload.array("files", 10), async (req: Request, res: Response) => {
  if (!(await isFileManager(req))) {
    res.status(403).json({ error: "Admin or item-admin access required" });
    return;
  }
  const files = req.files as Express.Multer.File[];
  if (!files?.length) {
    res.status(400).json({ error: "No files uploaded" });
    return;
  }

  const parsed = parseEntityFk(req.query as Record<string, any>);
  if (!parsed) {
    res.status(400).json({ error: "Specify one entity query param" });
    return;
  }

  const exists = await validateEntity(parsed.fk);
  if (!exists) {
    res.status(404).json({ error: "Referenced entity not found" });
    return;
  }

  const records = await Promise.all(
    files.map((f) => handleUpload(f, parsed.entityType, parsed.fk)),
  );
  res.status(201).json(records);
});

// ── GET /api/files/:id ──────────────────────────
router.get("/:id", async (req: Request, res: Response) => {
  const file = await prisma.fileAttachment.findUnique({
    where: { id: Number(req.params.id) },
  });
  if (!file) {
    res.status(404).json({ error: "File not found" });
    return;
  }
  res.json(file);
});

// ── DELETE /api/files/:id ───────────────────────
router.delete("/:id", async (req: Request, res: Response) => {
  if (!(await isFileManager(req))) {
    res.status(403).json({ error: "Admin or item-admin access required" });
    return;
  }
  const file = await prisma.fileAttachment.findUnique({ where: { id: Number(req.params.id) } });
  if (!file) {
    res.status(404).json({ error: "File not found" });
    return;
  }

  removeFromDisk(file.filePath, file.thumbnailPath);

  await prisma.fileAttachment.delete({ where: { id: file.id } });
  res.status(204).end();
});

export default router;
