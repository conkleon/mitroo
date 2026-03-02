import { Router, Request, Response } from "express";
import multer from "multer";
import path from "path";
import fs from "fs";
import prisma from "../lib/prisma";
import { authenticate } from "../middleware/auth";

const router = Router();
router.use(authenticate);

// ── Multer setup ────────────────────────────────
const UPLOAD_DIR = path.resolve(__dirname, "../../uploads");
if (!fs.existsSync(UPLOAD_DIR)) fs.mkdirSync(UPLOAD_DIR, { recursive: true });

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, UPLOAD_DIR),
  filename: (_req, file, cb) => {
    const unique = `${Date.now()}-${Math.round(Math.random() * 1e9)}`;
    cb(null, `${unique}${path.extname(file.originalname)}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 20 * 1024 * 1024 }, // 20 MB
});

// ── Helper: resolve entity FK ───────────────────
function entityFk(query: Record<string, any>) {
  const map: Record<string, string> = {
    userId: "userId",
    departmentId: "departmentId",
    serviceId: "serviceId",
    itemId: "itemId",
    vehicleId: "vehicleId",
  };
  const fk: Record<string, number> = {};
  for (const [qk, dbk] of Object.entries(map)) {
    if (query[qk]) fk[dbk] = Number(query[qk]);
  }
  return fk;
}

// ── GET /api/files?userId=&departmentId=&… ──────
router.get("/", async (req: Request, res: Response) => {
  const where = entityFk(req.query);
  const files = await prisma.fileAttachment.findMany({
    where,
    orderBy: { uploadedAt: "desc" },
  });
  res.json(files);
});

// ── POST /api/files?userId=1 (multipart) ────────
router.post("/", upload.single("file"), async (req: Request, res: Response) => {
  if (!req.file) { res.status(400).json({ error: "No file uploaded" }); return; }

  const fk = entityFk(req.query);
  if (Object.keys(fk).length === 0) {
    res.status(400).json({ error: "Specify one entity query param: userId, departmentId, serviceId, itemId, or vehicleId" });
    return;
  }

  const record = await prisma.fileAttachment.create({
    data: {
      fileName: req.file.originalname,
      filePath: `/uploads/${req.file.filename}`,
      mimeType: req.file.mimetype,
      fileSize: req.file.size,
      ...fk,
    },
  });
  res.status(201).json(record);
});

// ── POST /api/files/bulk?departmentId=1 (multiple files) ─
router.post("/bulk", upload.array("files", 10), async (req: Request, res: Response) => {
  const files = req.files as Express.Multer.File[];
  if (!files?.length) { res.status(400).json({ error: "No files uploaded" }); return; }

  const fk = entityFk(req.query);
  if (Object.keys(fk).length === 0) {
    res.status(400).json({ error: "Specify one entity query param" });
    return;
  }

  const records = await prisma.fileAttachment.createManyAndReturn({
    data: files.map((f) => ({
      fileName: f.originalname,
      filePath: `/uploads/${f.filename}`,
      mimeType: f.mimetype,
      fileSize: f.size,
      ...fk,
    })),
  });
  res.status(201).json(records);
});

// ── DELETE /api/files/:id ───────────────────────
router.delete("/:id", async (req: Request, res: Response) => {
  const file = await prisma.fileAttachment.findUnique({ where: { id: Number(req.params.id) } });
  if (!file) { res.status(404).json({ error: "File not found" }); return; }

  // Remove from disk
  const diskPath = path.resolve(__dirname, "../..", file.filePath.replace(/^\//, ""));
  if (fs.existsSync(diskPath)) fs.unlinkSync(diskPath);

  await prisma.fileAttachment.delete({ where: { id: file.id } });
  res.status(204).end();
});

export default router;
