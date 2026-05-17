import { Router, Request, Response } from "express";
import { z } from "zod";
import prisma from "../lib/prisma";
import { authenticate, isMissionAdminInDepartment } from "../middleware/auth";
import { getIO } from "../socket";
import multer from "multer";
import path from "path";
import sharp from "sharp";
import fs from "fs";

const router = Router();
router.use(authenticate);

const chatUploadDir = path.resolve(__dirname, "../../uploads/chat");
if (!fs.existsSync(chatUploadDir)) {
  fs.mkdirSync(chatUploadDir, { recursive: true });
}

const chatStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, chatUploadDir),
  filename: (_req, file, cb) => {
    const unique = `${Date.now()}-${Math.round(Math.random() * 1e9)}`;
    cb(null, `${unique}${path.extname(file.originalname)}`);
  },
});

const chatUpload = multer({
  storage: chatStorage,
  limits: { fileSize: 10 * 1024 * 1024 },
});

// ── GET /api/chats ──────────────────────────────
router.get("/", async (req: Request, res: Response) => {
  const userId = req.user!.userId;

  // Ensure department chats exist
  const userDepts = await prisma.userDepartment.findMany({
    where: { userId },
    include: { department: true },
  });

  for (const ud of userDepts) {
    let chat = await prisma.chat.findFirst({
      where: { type: "department", departmentId: ud.departmentId },
    });
    if (!chat) {
      chat = await prisma.chat.create({
        data: { type: "department", departmentId: ud.departmentId },
      });
      const deptMembers = await prisma.userDepartment.findMany({
        where: { departmentId: ud.departmentId },
        select: { userId: true },
      });
      await prisma.chatMember.createMany({
        data: deptMembers.map((m) => ({ chatId: chat!.id, userId: m.userId })),
        skipDuplicates: true,
      });
    }
    await prisma.chatMember.upsert({
      where: { chatId_userId: { chatId: chat.id, userId } },
      update: {},
      create: { chatId: chat.id, userId },
    });
  }

  // Ensure mission chats exist for accepted enrollments
  const now = new Date();
  const acceptedServices = await prisma.userService.findMany({
    where: {
      userId,
      status: "accepted",
      service: {
        OR: [
          { endAt: { gte: now } },
          { endAt: null, startAt: { gte: now } },
          { endAt: null, startAt: null },
        ],
      },
    },
    include: { service: { include: { department: true } } },
  });

  for (const us of acceptedServices) {
    let chat = await prisma.chat.findFirst({
      where: { type: "mission", serviceId: us.serviceId },
    });
    if (!chat) {
      chat = await prisma.chat.create({
        data: {
          type: "mission",
          name: us.service.name,
          serviceId: us.serviceId,
          departmentId: us.service.departmentId,
        },
      });
      const acceptedUsers = await prisma.userService.findMany({
        where: { serviceId: us.serviceId, status: "accepted" },
        select: { userId: true },
      });
      const missionAdmins = await prisma.userDepartment.findMany({
        where: { departmentId: us.service.departmentId, role: "missionAdmin" },
        select: { userId: true },
      });
      const memberIds = new Set([
        ...acceptedUsers.map((u) => u.userId),
        ...missionAdmins.map((u) => u.userId),
      ]);
      if (us.service.responsibleUserId) {
        memberIds.add(us.service.responsibleUserId);
      }
      await prisma.chatMember.createMany({
        data: [...memberIds].map((id) => ({ chatId: chat!.id, userId: id })),
        skipDuplicates: true,
      });
    }
    await prisma.chatMember.upsert({
      where: { chatId_userId: { chatId: chat.id, userId } },
      update: {},
      create: { chatId: chat.id, userId },
    });
  }

  const allChats = await prisma.chat.findMany({
    where: { members: { some: { userId } } },
    include: {
      messages: {
        take: 1,
        orderBy: { createdAt: "desc" },
        include: {
          user: { select: { id: true, forename: true, surname: true } },
        },
      },
      department: { select: { id: true, name: true } },
      service: { select: { id: true, name: true } },
      _count: { select: { members: true } },
    },
    orderBy: { updatedAt: "desc" },
  });

  const result = allChats.map((chat) => ({
    id: chat.id,
    type: chat.type,
    name: chat.name ?? chat.department?.name ?? chat.service?.name ?? "Chat",
    departmentId: chat.departmentId,
    serviceId: chat.serviceId,
    itemAdminsCanSend: chat.itemAdminsCanSend,
    volunteersCanSend: chat.volunteersCanSend,
    deleteAfter24h: chat.deleteAfter24h,
    memberCount: chat._count.members,
    lastMessage: chat.messages[0] ?? null,
    createdAt: chat.createdAt,
    updatedAt: chat.updatedAt,
  }));

  res.json(result);
});

// ── POST /api/chats ──────────────────────────────
const createChatSchema = z.object({
  name: z.string().min(1).max(255),
  departmentId: z.number().int(),
  memberIds: z.array(z.number().int()).min(1),
  itemAdminsCanSend: z.boolean().optional(),
  volunteersCanSend: z.boolean().optional(),
  deleteAfter24h: z.boolean().optional(),
});

router.post("/", async (req: Request, res: Response) => {
  try {
    const userId = req.user!.userId;
    const isAdmin = req.user!.isAdmin;
    const data = createChatSchema.parse(req.body);

    if (!isAdmin && !(await isMissionAdminInDepartment(userId, data.departmentId))) {
      res.status(403).json({ error: "Only mission admins can create group chats" });
      return;
    }

    const chat = await prisma.chat.create({
      data: {
        type: "custom",
        name: data.name,
        departmentId: data.departmentId,
        createdById: userId,
        itemAdminsCanSend: data.itemAdminsCanSend ?? false,
        volunteersCanSend: data.volunteersCanSend ?? false,
        deleteAfter24h: data.deleteAfter24h ?? false,
        members: {
          create: [...new Set([...data.memberIds, userId])].map((id) => ({
            userId: id,
          })),
        },
      },
      include: {
        members: {
          include: {
            user: { select: { id: true, forename: true, surname: true, imagePath: true } },
          },
        },
        _count: { select: { members: true } },
      },
    });

    const io = getIO();
    for (const member of chat.members) {
      io.to(`user:${member.userId}`).emit("chat:new", {
        id: chat.id,
        name: chat.name,
        type: chat.type,
      });
    }

    res.status(201).json(chat);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Validation failed", details: err.errors });
      return;
    }
    throw err;
  }
});

// ── GET /api/chats/direct/candidates ────────────────
router.get("/direct/candidates", async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const isAdmin = req.user!.isAdmin;

  if (isAdmin) {
    const depts = await prisma.department.findMany({
      include: {
        userDepartments: {
          where: { userId: { not: userId } },
          include: {
            user: { select: { id: true, forename: true, surname: true, imagePath: true } },
          },
          orderBy: [{ user: { surname: "asc" } }, { user: { forename: "asc" } }],
        },
      },
      orderBy: { name: "asc" },
    });

    res.json(
      depts
        .filter((d) => d.userDepartments.length > 0)
        .map((d) => ({
          departmentId: d.id,
          departmentName: d.name,
          users: d.userDepartments.map((ud) => ({
            id: ud.user.id,
            forename: ud.user.forename,
            surname: ud.user.surname,
            role: ud.role,
            imagePath: ud.user.imagePath,
          })),
        }))
    );
    return;
  }

  // Check if caller is missionAdmin in any department
  const callerAdminDepts = await prisma.userDepartment.findMany({
    where: { userId, role: "missionAdmin" },
    select: { departmentId: true },
  });

  if (callerAdminDepts.length > 0) {
    // Mission admin: return all users in their departments
    const deptIds = callerAdminDepts.map((d) => d.departmentId);
    const depts = await prisma.department.findMany({
      where: { id: { in: deptIds } },
      include: {
        userDepartments: {
          where: { userId: { not: userId } },
          include: {
            user: { select: { id: true, forename: true, surname: true, imagePath: true } },
          },
          orderBy: [{ user: { surname: "asc" } }, { user: { forename: "asc" } }],
        },
      },
      orderBy: { name: "asc" },
    });

    res.json(
      depts.map((d) => ({
        departmentId: d.id,
        departmentName: d.name,
        users: d.userDepartments.map((ud) => ({
          id: ud.user.id,
          forename: ud.user.forename,
          surname: ud.user.surname,
          role: ud.role,
          imagePath: ud.user.imagePath,
        })),
      }))
    );
    return;
  }

  // Regular user: return only missionAdmins in their departments
  const callerDepts = await prisma.userDepartment.findMany({
    where: { userId },
    select: { departmentId: true },
  });
  const deptIds = callerDepts.map((d) => d.departmentId);

  const depts = await prisma.department.findMany({
    where: { id: { in: deptIds } },
    include: {
      userDepartments: {
        where: { role: "missionAdmin", userId: { not: userId } },
        include: {
          user: { select: { id: true, forename: true, surname: true, imagePath: true } },
        },
        orderBy: [{ user: { surname: "asc" } }, { user: { forename: "asc" } }],
      },
    },
    orderBy: { name: "asc" },
  });

  res.json(
    depts
      .filter((d) => d.userDepartments.length > 0)
      .map((d) => ({
        departmentId: d.id,
        departmentName: d.name,
        users: d.userDepartments.map((ud) => ({
          id: ud.user.id,
          forename: ud.user.forename,
          surname: ud.user.surname,
          role: ud.role,
          imagePath: ud.user.imagePath,
        })),
      }))
  );
});

// ── GET /api/chats/:id ───────────────────────────
router.get("/:id", async (req: Request, res: Response) => {
  const chatId = Number(req.params.id);
  const chat = await prisma.chat.findUnique({
    where: { id: chatId },
    include: {
      members: {
        include: {
          user: { select: { id: true, forename: true, surname: true, imagePath: true } },
        },
      },
      department: { select: { id: true, name: true } },
      service: { select: { id: true, name: true, responsibleUserId: true, endAt: true } },
      _count: { select: { members: true } },
    },
  });
  if (!chat) {
    res.status(404).json({ error: "Chat not found" });
    return;
  }
  res.json(chat);
});

// ── GET /api/chats/:id/messages ──────────────────
router.get("/:id/messages", async (req: Request, res: Response) => {
  const chatId = Number(req.params.id);
  const limit = Math.min(Number(req.query.limit) || 50, 100);
  const before = req.query.before ? Number(req.query.before) : undefined;

  const where: any = { chatId };
  if (before) where.id = { lt: before };

  const messages = await prisma.chatMessage.findMany({
    where,
    include: {
      user: { select: { id: true, forename: true, surname: true, imagePath: true } },
      attachments: true,
    },
    orderBy: { createdAt: "desc" },
    take: limit,
  });

  res.json(messages.reverse());
});

// ── POST /api/chats/:id/members ──────────────────
const inviteSchema = z.object({
  userIds: z.array(z.number().int()).min(1),
});

router.post("/:id/members", async (req: Request, res: Response) => {
  try {
    const chatId = Number(req.params.id);
    const userId = req.user!.userId;
    const isAdmin = req.user!.isAdmin;
    const data = inviteSchema.parse(req.body);

    const chat = await prisma.chat.findUnique({
      where: { id: chatId },
      select: { type: true, departmentId: true },
    });
    if (!chat) {
      res.status(404).json({ error: "Chat not found" });
      return;
    }
    if (chat.type !== "custom") {
      res.status(400).json({ error: "Can only manage members in custom chats" });
      return;
    }
    if (!isAdmin && !(await isMissionAdminInDepartment(userId, chat.departmentId!))) {
      res.status(403).json({ error: "Only mission admins can manage members" });
      return;
    }

    await prisma.chatMember.createMany({
      data: data.userIds.map((uid) => ({ chatId, userId: uid })),
      skipDuplicates: true,
    });

    const io = getIO();
    for (const uid of data.userIds) {
      io.to(`user:${uid}`).emit("chat:member-joined", { chatId, userId: uid });
    }

    const members = await prisma.chatMember.findMany({
      where: { chatId },
      include: {
        user: { select: { id: true, forename: true, surname: true, imagePath: true } },
      },
    });
    res.json(members);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Validation failed", details: err.errors });
      return;
    }
    throw err;
  }
});

// ── DELETE /api/chats/:id/members/:userId ─────────
router.delete("/:id/members/:userId", async (req: Request, res: Response) => {
  const chatId = Number(req.params.id);
  const targetUserId = Number(req.params.userId);
  const userId = req.user!.userId;
  const isAdmin = req.user!.isAdmin;

  const chat = await prisma.chat.findUnique({
    where: { id: chatId },
    select: { type: true, departmentId: true },
  });
  if (!chat) {
    res.status(404).json({ error: "Chat not found" });
    return;
  }
  if (chat.type !== "custom") {
    res.status(400).json({ error: "Can only manage members in custom chats" });
    return;
  }
  if (!isAdmin && !(await isMissionAdminInDepartment(userId, chat.departmentId!))) {
    res.status(403).json({ error: "Only mission admins can manage members" });
    return;
  }

  await prisma.chatMember.deleteMany({
    where: { chatId, userId: targetUserId },
  });

  const io = getIO();
  io.to(`user:${targetUserId}`).emit("chat:member-left", { chatId, userId: targetUserId });

  res.status(204).end();
});

// ── DELETE /api/chats/:id/leave ──────────────────
router.delete("/:id/leave", async (req: Request, res: Response) => {
  const chatId = Number(req.params.id);
  const userId = req.user!.userId;

  const chat = await prisma.chat.findUnique({
    where: { id: chatId },
    select: { type: true },
  });
  if (!chat) {
    res.status(404).json({ error: "Chat not found" });
    return;
  }
  if (chat.type !== "custom") {
    res.status(400).json({ error: "Cannot leave department or mission chats" });
    return;
  }

  await prisma.chatMember.deleteMany({
    where: { chatId, userId },
  });

  const io = getIO();
  io.to(`user:${userId}`).emit("chat:member-left", { chatId, userId });

  res.status(204).end();
});

// ── PATCH /api/chats/:id ─────────────────────────
const updateChatSchema = z.object({
  name: z.string().min(1).max(255).optional(),
  itemAdminsCanSend: z.boolean().optional(),
  volunteersCanSend: z.boolean().optional(),
  deleteAfter24h: z.boolean().optional(),
});

router.patch("/:id", async (req: Request, res: Response) => {
  try {
    const chatId = Number(req.params.id);
    const userId = req.user!.userId;
    const isAdmin = req.user!.isAdmin;
    const data = updateChatSchema.parse(req.body);

    const chat = await prisma.chat.findUnique({
      where: { id: chatId },
      select: { type: true, departmentId: true },
    });
    if (!chat) {
      res.status(404).json({ error: "Chat not found" });
      return;
    }
    if (chat.type !== "custom") {
      res.status(400).json({ error: "Can only update custom chats" });
      return;
    }
    if (!isAdmin && !(await isMissionAdminInDepartment(userId, chat.departmentId!))) {
      res.status(403).json({ error: "Only mission admins can update settings" });
      return;
    }

    const updated = await prisma.chat.update({ where: { id: chatId }, data });
    res.json(updated);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Validation failed", details: err.errors });
      return;
    }
    throw err;
  }
});

// ── POST /api/chats/:id/upload ───────────────────
router.post("/:id/upload", chatUpload.single("file"), async (req: Request, res: Response) => {
  const chatId = Number(req.params.id);
  const userId = req.user!.userId;
  const file = req.file;

  if (!file) {
    res.status(400).json({ error: "No file provided" });
    return;
  }

  const member = await prisma.chatMember.findUnique({
    where: { chatId_userId: { chatId, userId } },
  });
  if (!member) {
    res.status(403).json({ error: "Not a member of this chat" });
    return;
  }

  // Generate thumbnail for images (best-effort)
  const isImage = file.mimetype.startsWith("image/");
  if (isImage) {
    try {
      const thumbName = `thumb_${file.filename}`;
      await sharp(file.path)
        .resize(400, 400, { fit: "inside" })
        .toFile(path.join(chatUploadDir, thumbName));
    } catch {}
  }

  const attachment = await prisma.chatMessageAttachment.create({
    data: {
      fileName: file.originalname,
      filePath: file.filename,
      mimeType: file.mimetype,
      fileSize: file.size,
    },
  });

  res.status(201).json({
    id: attachment.id,
    fileName: attachment.fileName,
    mimeType: attachment.mimeType,
    fileSize: attachment.fileSize,
  });
});

// ── DELETE /api/chats/:id/messages/:messageId ──────
router.delete("/:id/messages/:messageId", async (req: Request, res: Response) => {
  const chatId = Number(req.params.id);
  const messageId = Number(req.params.messageId);
  const userId = req.user!.userId;
  const isAdmin = req.user!.isAdmin;

  const message = await prisma.chatMessage.findUnique({
    where: { id: messageId },
    include: { chat: { select: { departmentId: true } } },
  });
  if (!message || message.chatId !== chatId) {
    res.status(404).json({ error: "Message not found" });
    return;
  }

  const isAuthor = message.userId === userId;
  const isDeptAdmin =
    isAdmin ||
    (message.chat.departmentId != null &&
      (await isMissionAdminInDepartment(userId, message.chat.departmentId)));

  if (!isAuthor && !isDeptAdmin) {
    res.status(403).json({ error: "Not authorized to delete this message" });
    return;
  }

  await prisma.chatMessage.delete({ where: { id: messageId } });

  const io = getIO();
  io.to(`chat:${chatId}`).emit("chat:message-deleted", { chatId, messageId });

  res.status(204).end();
});

export default router;
