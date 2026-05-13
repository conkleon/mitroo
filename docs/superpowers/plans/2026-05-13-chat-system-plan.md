# Chat System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a real-time chat system with department chats, mission chats, and configurable custom group chats.

**Architecture:** Socket.io on the backend for real-time messaging, REST endpoints for CRUD operations, Prisma-managed PostgreSQL tables, Flutter provider with socket.io client for state. Existing `sendPushToUser` infrastructure extended for offline notifications.

**Tech Stack:** Node.js/Express/TypeScript, Socket.io (server + client), Prisma, Flutter/Dart, socket_io_client, web-push (existing)

---

### Task 1: Add Prisma models to schema

**Files:**
- Modify: `backend/prisma/schema.prisma`

- [ ] **Step 1: Add ChatType enum and Chat, ChatMember, ChatMessage, ChatMessageAttachment models**

Insert after the `VehicleComment` model block (around line 474) in `schema.prisma`:

```prisma
// ──────────────────────────────────────────────
// Chat
// ──────────────────────────────────────────────

enum ChatType {
  department
  mission
  custom

  @@map("chat_type")
}

model Chat {
  id           Int      @id @default(autoincrement())
  type         ChatType
  name         String?  @db.VarChar(255)
  departmentId Int?     @map("department_id")
  serviceId    Int?     @map("service_id")
  createdById  Int?     @map("created_by_id")

  itemAdminsCanSend Boolean @default(false) @map("item_admins_can_send")
  volunteersCanSend Boolean @default(false) @map("volunteers_can_send")
  deleteAfter24h    Boolean @default(false) @map("delete_after_24h")

  createdAt DateTime @default(now()) @map("created_at")
  updatedAt DateTime @updatedAt @map("updated_at")

  department Department? @relation(fields: [departmentId], references: [id], onDelete: Cascade)
  service    Service?    @relation(fields: [serviceId], references: [id], onDelete: Cascade)
  createdBy  User?       @relation("CreatedChats", fields: [createdById], references: [id], onDelete: SetNull)

  members  ChatMember[]
  messages ChatMessage[]

  @@map("chats")
}

model ChatMember {
  chatId   Int      @map("chat_id")
  userId   Int      @map("user_id")
  joinedAt DateTime @default(now()) @map("joined_at")

  chat Chat @relation(fields: [chatId], references: [id], onDelete: Cascade)
  user User @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@id([chatId, userId])
  @@map("chat_members")
}

model ChatMessage {
  id        Int      @id @default(autoincrement())
  chatId    Int      @map("chat_id")
  userId    Int      @map("user_id")
  text      String   @db.Text
  createdAt DateTime @default(now()) @map("created_at")

  chat Chat        @relation(fields: [chatId], references: [id], onDelete: Cascade)
  user User        @relation("ChatMessages", fields: [userId], references: [id], onDelete: Cascade)

  attachments ChatMessageAttachment[]

  @@index([chatId, createdAt])
  @@map("chat_messages")
}

model ChatMessageAttachment {
  id        Int     @id @default(autoincrement())
  messageId Int?    @map("message_id")
  fileName  String  @map("file_name") @db.VarChar(500)
  filePath  String  @map("file_path")
  mimeType  String? @map("mime_type") @db.VarChar(255)
  fileSize  Int?    @map("file_size")

  message ChatMessage? @relation(fields: [messageId], references: [id], onDelete: Cascade)

  @@map("chat_message_attachments")
}
```

- [ ] **Step 2: Add relation fields to User model**

In the `User` model, find the existing relation arrays (near `pushSubscriptions PushSubscription[]`) and add these lines after it:

```prisma
  createdChats    Chat[]              @relation("CreatedChats")
  chatMemberships ChatMember[]
  chatMessages    ChatMessage[]       @relation("ChatMessages")
```

- [ ] **Step 3: Add back-relations to Department and Service models**

In the `Department` model, add after `syncConfig DepartmentSyncConfig?`:

```prisma
  chats            Chat[]
```

In the `Service` model, add after `attachments FileAttachment[]`:

```prisma
  chats            Chat[]
```

- [ ] **Step 4: Generate Prisma client and run migration**

```bash
cd backend
npm run prisma:generate
npm run prisma:migrate -- --name add_chat_tables
```

Expected: migration created and applied without errors.

- [ ] **Step 5: Commit**

```bash
git add backend/prisma/schema.prisma backend/prisma/migrations/
git commit -m "feat: add Chat, ChatMember, ChatMessage, ChatMessageAttachment models"
```

---

### Task 2: Install Socket.io dependencies

- [ ] **Step 1: Install backend Socket.io**

```bash
cd backend
npm install socket.io
```

- [ ] **Step 2: Install frontend Socket.io client**

```bash
cd frontend
flutter pub add socket_io_client
```

- [ ] **Step 3: Commit**

```bash
git add backend/package.json backend/package-lock.json frontend/pubspec.yaml frontend/pubspec.lock
git commit -m "chore: add socket.io and socket_io_client dependencies"
```

---

### Task 3: Create Socket.io setup with auth and event handlers

**Files:**
- Create: `backend/src/socket.ts`

- [ ] **Step 1: Write the socket module**

```typescript
import { Server as HttpServer } from "http";
import { Server, Socket } from "socket.io";
import jwt from "jsonwebtoken";
import prisma from "./lib/prisma";
import { sendPushToUser } from "./lib/webpush";

interface AuthPayload {
  userId: number;
  isAdmin: boolean;
}

let io: Server | null = null;

export function initSocket(httpServer: HttpServer): Server {
  io = new Server(httpServer, {
    cors: { origin: true, credentials: true },
    pingTimeout: 60000,
  });

  // Auth middleware: verify JWT on connection
  io.use(async (socket, next) => {
    const token = socket.handshake.auth?.token as string | undefined;
    if (!token) return next(new Error("Authentication required"));
    try {
      const payload = jwt.verify(token, process.env.JWT_SECRET!) as AuthPayload;
      (socket as any).userId = payload.userId;
      (socket as any).isAdmin = payload.isAdmin;
      next();
    } catch {
      next(new Error("Invalid or expired token"));
    }
  });

  io.on("connection", async (socket) => {
    const userId = (socket as any).userId as number;
    console.log(`[socket] user ${userId} connected (${socket.id})`);

    // Auto-join all chats the user is a member of
    const memberships = await prisma.chatMember.findMany({
      where: { userId },
      select: { chatId: true },
    });
    memberships.forEach((m) => socket.join(`chat:${m.chatId}`));
    // Also join a user-specific room for notifications (new chat invites, etc.)
    socket.join(`user:${userId}`);

    socket.on("chat:join", async (data: { chatId: number }) => {
      const member = await prisma.chatMember.findUnique({
        where: { chatId_userId: { chatId: data.chatId, userId } },
      });
      if (!member) {
        socket.emit("chat:error", { message: "Not a member of this chat" });
        return;
      }
      socket.join(`chat:${data.chatId}`);
    });

    socket.on("chat:leave", (data: { chatId: number }) => {
      socket.leave(`chat:${data.chatId}`);
    });

    socket.on("chat:send", async (data: { chatId: number; text: string; attachmentIds?: number[] }) => {
      try {
        const chat = await prisma.chat.findUnique({
          where: { id: data.chatId },
          include: { service: { select: { id: true, responsibleUserId: true, endAt: true } } },
        });
        if (!chat) {
          socket.emit("chat:error", { message: "Chat not found" });
          return;
        }

        const member = await prisma.chatMember.findUnique({
          where: { chatId_userId: { chatId: data.chatId, userId } },
        });
        if (!member) {
          socket.emit("chat:error", { message: "Not a member of this chat" });
          return;
        }

        const canSend = await checkSendPermission(userId, chat);
        if (!canSend) {
          socket.emit("chat:error", { message: "You cannot send messages in this chat" });
          return;
        }

        const message = await prisma.chatMessage.create({
          data: { chatId: data.chatId, userId, text: data.text },
          include: {
            user: { select: { id: true, forename: true, surname: true, imagePath: true } },
            attachments: true,
          },
        });

        // Link pre-uploaded attachments to this message
        if (data.attachmentIds?.length) {
          await prisma.chatMessageAttachment.updateMany({
            where: { id: { in: data.attachmentIds }, messageId: null },
            data: { messageId: message.id },
          });
          const refreshed = await prisma.chatMessage.findUnique({
            where: { id: message.id },
            include: {
              user: { select: { id: true, forename: true, surname: true, imagePath: true } },
              attachments: true,
            },
          });
          io!.to(`chat:${data.chatId}`).emit("chat:message", refreshed);
        } else {
          io!.to(`chat:${data.chatId}`).emit("chat:message", message);
        }

        // Push notify offline members
        notifyOfflineMembers(chat, message, userId);
      } catch (err) {
        console.error("[socket] chat:send error:", err);
        socket.emit("chat:error", { message: "Failed to send message" });
      }
    });

    socket.on("disconnect", () => {
      console.log(`[socket] user ${userId} disconnected (${socket.id})`);
    });
  });

  return io;
}

async function checkSendPermission(
  userId: number,
  chat: {
    type: string;
    departmentId: number | null;
    serviceId: number | null;
    itemAdminsCanSend: boolean;
    volunteersCanSend: boolean;
    service?: { responsibleUserId: number | null } | null;
  }
): Promise<boolean> {
  if (!chat.departmentId) return false;

  const userDeptRoles = await prisma.userDepartment.findMany({
    where: { userId, departmentId: chat.departmentId },
    select: { role: true },
  });

  const isMissionAdmin = userDeptRoles.some((r) => r.role === "missionAdmin");
  const isItemAdmin = userDeptRoles.some(
    (r) => r.role === "itemAdmin" || r.role === "missionAdmin"
  );

  if (isMissionAdmin) return true;

  switch (chat.type) {
    case "department":
      return false;

    case "mission": {
      if (chat.serviceId) {
        const enrollment = await prisma.userService.findUnique({
          where: { userId_serviceId: { userId, serviceId: chat.serviceId } },
          select: { status: true },
        });
        if (enrollment?.status === "accepted") return true;
      }
      if (chat.service?.responsibleUserId === userId) return true;
      return false;
    }

    case "custom":
      if (chat.itemAdminsCanSend && isItemAdmin) return true;
      if (chat.volunteersCanSend) return true;
      return false;

    default:
      return false;
  }
}

async function notifyOfflineMembers(
  chat: {
    id: number;
    type: string;
    name: string | null;
    departmentId: number | null;
    serviceId: number | null;
  },
  message: { user: { forename: string; surname: string }; text: string },
  senderId: number
): Promise<void> {
  if (!io) return;

  const roomSockets = await io.in(`chat:${chat.id}`).fetchSockets();
  const onlineUserIds = new Set(
    roomSockets.map((s) => (s as any).userId as number)
  );

  const allMembers = await prisma.chatMember.findMany({
    where: { chatId: chat.id, userId: { not: senderId } },
    select: { userId: true },
  });

  let chatName = chat.name ?? "Chat";
  if (!chat.name) {
    if (chat.type === "department" && chat.departmentId) {
      const dept = await prisma.department.findUnique({
        where: { id: chat.departmentId },
        select: { name: true },
      });
      chatName = dept?.name ?? "Department";
    } else if (chat.type === "mission" && chat.serviceId) {
      const svc = await prisma.service.findUnique({
        where: { id: chat.serviceId },
        select: { name: true },
      });
      chatName = svc?.name ?? "Mission";
    }
  }

  const senderName = `${message.user.forename} ${message.user.surname}`.trim();
  const truncated =
    message.text.length > 100
      ? message.text.slice(0, 97) + "..."
      : message.text;

  for (const m of allMembers) {
    if (!onlineUserIds.has(m.userId)) {
      sendPushToUser(m.userId, {
        title: chatName,
        body: `${senderName}: ${truncated}`,
        data: { chatId: chat.id, type: "chat_message" },
      }).catch(() => {});
    }
  }
}

export function getIO(): Server {
  if (!io) throw new Error("Socket.io not initialized");
  return io;
}
```

- [ ] **Step 2: Commit**

```bash
git add backend/src/socket.ts
git commit -m "feat: add Socket.io setup with chat event handlers"
```

---

### Task 4: Create chat cleanup logic

**Files:**
- Create: `backend/src/lib/chatCleanup.ts`

- [ ] **Step 1: Write the cleanup module**

```typescript
import prisma from "./prisma";
import fs from "fs";
import path from "path";

const UPLOADS_DIR = path.resolve(__dirname, "../../uploads/chat");

export async function cleanupExpiredChats(): Promise<void> {
  const now = new Date();

  // Delete mission chats whose service ended > 24h ago
  const expiredMissionChats = await prisma.chat.findMany({
    where: {
      type: "mission",
      service: {
        endAt: { lt: new Date(now.getTime() - 24 * 60 * 60 * 1000) },
      },
    },
    select: { id: true },
  });

  for (const chat of expiredMissionChats) {
    await deleteChatFiles(chat.id);
    await prisma.chat.delete({ where: { id: chat.id } });
  }

  // Delete old messages from custom chats with deleteAfter24h
  const cutoff = new Date(now.getTime() - 24 * 60 * 60 * 1000);

  const oldMessages = await prisma.chatMessage.findMany({
    where: {
      chat: { type: "custom", deleteAfter24h: true },
      createdAt: { lt: cutoff },
    },
    include: { attachments: true },
  });

  for (const msg of oldMessages) {
    for (const att of msg.attachments) {
      fs.unlink(path.resolve(UPLOADS_DIR, att.filePath), () => {});
    }
  }

  if (oldMessages.length > 0) {
    await prisma.chatMessage.deleteMany({
      where: {
        chat: { type: "custom", deleteAfter24h: true },
        createdAt: { lt: cutoff },
      },
    });
  }

  if (expiredMissionChats.length > 0 || oldMessages.length > 0) {
    console.log(
      `[cleanup] Removed ${expiredMissionChats.length} mission chats, ${oldMessages.length} old messages`
    );
  }
}

async function deleteChatFiles(chatId: number): Promise<void> {
  const messages = await prisma.chatMessage.findMany({
    where: { chatId },
    include: { attachments: true },
  });
  for (const msg of messages) {
    for (const att of msg.attachments) {
      fs.unlink(path.resolve(UPLOADS_DIR, att.filePath), () => {});
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add backend/src/lib/chatCleanup.ts
git commit -m "feat: add chat cleanup logic for expired missions and auto-delete messages"
```

---

### Task 5: Extend sendPushToUser for chat data payload

**Files:**
- Modify: `backend/src/lib/webpush.ts`

- [ ] **Step 1: Add optional data field to payload**

In `backend/src/lib/webpush.ts`, change the function signature from:

```typescript
export async function sendPushToUser(userId: number, payload: { title: string; body: string }): Promise<void> {
```

To:

```typescript
export async function sendPushToUser(
  userId: number,
  payload: { title: string; body: string; data?: Record<string, unknown> }
): Promise<void> {
```

The function body stays identical — `JSON.stringify(payload)` automatically includes `data` when present.

- [ ] **Step 2: Commit**

```bash
git add backend/src/lib/webpush.ts
git commit -m "feat: extend sendPushToUser with optional data payload for chat notifications"
```

---

### Task 6: Create chat REST routes

**Files:**
- Create: `backend/src/routes/chat.routes.ts`

- [ ] **Step 1: Write the chat routes file**

```typescript
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

export default router;
```

- [ ] **Step 2: Commit**

```bash
git add backend/src/routes/chat.routes.ts
git commit -m "feat: add chat REST routes — list, get, create, messages, members, upload"
```

---

### Task 7: Wire chat routes and socket into app.ts and server.ts

**Files:**
- Modify: `backend/src/app.ts`
- Modify: `backend/src/server.ts`

- [ ] **Step 1: Add chat routes to app.ts**

In `backend/src/app.ts`, add the import (with the other route imports):

```typescript
import chatRoutes from "./routes/chat.routes";
```

And add the route registration (with the other route registrations):

```typescript
app.use("/api/chats", chatRoutes);
```

- [ ] **Step 2: Attach Socket.io to the HTTP server in server.ts**

Modify `backend/src/server.ts` to import and initialize socket, and to start the cleanup interval:

```typescript
import dotenv from "dotenv";
import path from "path";

dotenv.config({ path: path.resolve(__dirname, "../../.env") });

if (process.env.NODE_ENV !== "production") {
  if (process.env.DATABASE_URL_DEV) {
    process.env.DATABASE_URL = process.env.DATABASE_URL_DEV;
  }
  if (process.env.REDIS_URL_DEV) {
    process.env.REDIS_URL = process.env.REDIS_URL_DEV;
  }
}

import { createServer } from "http";
import app from "./app";
import { initSocket } from "./socket";
import { cleanupExpiredChats } from "./lib/chatCleanup";

const PORT = parseInt(process.env.APP_PORT || "4000", 10);

const httpServer = createServer(app);
initSocket(httpServer);

// Run cleanup every 15 minutes
setInterval(cleanupExpiredChats, 15 * 60 * 1000);

httpServer.listen(PORT, () => {
  console.log(`🚀 Mitroo API running on http://localhost:${PORT}`);
  console.log(`   Environment: ${process.env.NODE_ENV}`);
});
```

- [ ] **Step 3: Commit**

```bash
git add backend/src/app.ts backend/src/server.ts
git commit -m "feat: wire chat routes and Socket.io into app and server"
```

---

### Task 8: Create frontend chat data models

**Files:**
- Create: `frontend/lib/helpers/chat_models.dart`

- [ ] **Step 1: Write Dart data classes**

```dart
class ChatSummary {
  final int id;
  final String type; // 'department', 'mission', 'custom'
  final String name;
  final int? departmentId;
  final int? serviceId;
  final bool itemAdminsCanSend;
  final bool volunteersCanSend;
  final bool deleteAfter24h;
  final int memberCount;
  final LastMessage? lastMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatSummary({
    required this.id,
    required this.type,
    required this.name,
    this.departmentId,
    this.serviceId,
    this.itemAdminsCanSend = false,
    this.volunteersCanSend = false,
    this.deleteAfter24h = false,
    this.memberCount = 0,
    this.lastMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChatSummary.fromJson(Map<String, dynamic> json) {
    return ChatSummary(
      id: json['id'] as int,
      type: json['type'] as String,
      name: json['name'] as String? ?? 'Chat',
      departmentId: json['departmentId'] as int?,
      serviceId: json['serviceId'] as int?,
      itemAdminsCanSend: json['itemAdminsCanSend'] as bool? ?? false,
      volunteersCanSend: json['volunteersCanSend'] as bool? ?? false,
      deleteAfter24h: json['deleteAfter24h'] as bool? ?? false,
      memberCount: json['memberCount'] as int? ?? 0,
      lastMessage: json['lastMessage'] != null
          ? LastMessage.fromJson(json['lastMessage'] as Map<String, dynamic>)
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

class LastMessage {
  final int id;
  final String text;
  final DateTime createdAt;
  final LastMessageUser user;

  LastMessage({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.user,
  });

  factory LastMessage.fromJson(Map<String, dynamic> json) {
    return LastMessage(
      id: json['id'] as int,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      user: LastMessageUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}

class LastMessageUser {
  final int id;
  final String forename;
  final String surname;

  LastMessageUser({
    required this.id,
    required this.forename,
    required this.surname,
  });

  factory LastMessageUser.fromJson(Map<String, dynamic> json) {
    return LastMessageUser(
      id: json['id'] as int,
      forename: json['forename'] as String? ?? '',
      surname: json['surname'] as String? ?? '',
    );
  }
}

class ChatMessage {
  final int id;
  final int chatId;
  final int userId;
  final String text;
  final DateTime createdAt;
  final ChatUser user;
  final List<ChatAttachment> attachments;

  ChatMessage({
    required this.id,
    required this.chatId,
    required this.userId,
    required this.text,
    required this.createdAt,
    required this.user,
    this.attachments = const [],
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as int,
      chatId: json['chatId'] as int,
      userId: json['userId'] as int,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      user: ChatUser.fromJson(json['user'] as Map<String, dynamic>),
      attachments: (json['attachments'] as List<dynamic>?)
              ?.map((a) => ChatAttachment.fromJson(a as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class ChatUser {
  final int id;
  final String forename;
  final String surname;
  final String? imagePath;

  ChatUser({
    required this.id,
    required this.forename,
    required this.surname,
    this.imagePath,
  });

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    return ChatUser(
      id: json['id'] as int,
      forename: json['forename'] as String? ?? '',
      surname: json['surname'] as String? ?? '',
      imagePath: json['imagePath'] as String?,
    );
  }
}

class ChatAttachment {
  final int id;
  final String fileName;
  final String filePath;
  final String? mimeType;
  final int? fileSize;

  ChatAttachment({
    required this.id,
    required this.fileName,
    required this.filePath,
    this.mimeType,
    this.fileSize,
  });

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      id: json['id'] as int,
      fileName: json['fileName'] as String,
      filePath: json['filePath'] as String,
      mimeType: json['mimeType'] as String?,
      fileSize: json['fileSize'] as int?,
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/helpers/chat_models.dart
git commit -m "feat: add chat data models"
```

---

### Task 9: Create ChatProvider with socket integration

**Files:**
- Create: `frontend/lib/providers/chat_provider.dart`

- [ ] **Step 1: Write the ChatProvider**

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../helpers/chat_models.dart';
import '../services/api_client.dart';

class ChatProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient();

  List<ChatSummary> _chats = [];
  final Map<int, List<ChatMessage>> _messages = {};
  final Map<int, int> _unread = {};
  bool _loading = false;
  int? _activeChatId;
  io.Socket? _socket;

  List<ChatSummary> get chats => _chats;
  Map<int, List<ChatMessage>> get messages => _messages;
  Map<int, int> get unread => _unread;
  bool get loading => _loading;
  int? get activeChatId => _activeChatId;

  List<ChatMessage> messagesForChat(int chatId) => _messages[chatId] ?? [];

  void connect(String token) {
    _socket = io.io(
      'http://localhost:4000',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .build(),
    );
    _socket!.connect();

    _socket!.on('chat:message', (data) {
      final msg = ChatMessage.fromJson(data as Map<String, dynamic>);
      _messages.putIfAbsent(msg.chatId, () => []);
      _messages[msg.chatId]!.add(msg);

      if (_activeChatId != msg.chatId) {
        _unread[msg.chatId] = (_unread[msg.chatId] ?? 0) + 1;
      }

      // Move this chat to top in list
      final idx = _chats.indexWhere((c) => c.id == msg.chatId);
      if (idx > 0) {
        final chat = _chats.removeAt(idx);
        _chats.insert(0, chat);
      }

      notifyListeners();
    });

    _socket!.on('chat:new', (data) {
      fetchChats();
    });

    _socket!.on('chat:member-joined', (data) {
      fetchChats();
    });

    _socket!.on('chat:member-left', (data) {
      final chatId = data['chatId'] as int;
      final userId = data['userId'] as int;
      // If current user was removed, refresh list
      fetchChats();
    });

    _socket!.on('chat:error', (data) {
      debugPrint('Chat socket error: ${data['message']}');
    });
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  void setActiveChat(int? chatId) {
    _activeChatId = chatId;
    if (chatId != null) {
      _unread[chatId] = 0;
      notifyListeners();
    }
  }

  Future<void> fetchChats() async {
    _loading = true;
    notifyListeners();
    try {
      final res = await _api.get('/chats');
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        _chats = list
            .map((j) => ChatSummary.fromJson(j as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Error fetching chats: $e');
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> fetchMessages(int chatId, {int? before, int limit = 50}) async {
    var path = '/chats/$chatId/messages?limit=$limit';
    if (before != null) path += '&before=$before';
    try {
      final res = await _api.get(path);
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        final msgs = list
            .map((j) => ChatMessage.fromJson(j as Map<String, dynamic>))
            .toList();
        _messages[chatId] = msgs;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching messages: $e');
    }
  }

  Future<void> sendMessage(int chatId, String text, {List<int>? attachmentIds}) async {
    _socket?.emit('chat:send', {
      'chatId': chatId,
      'text': text,
      if (attachmentIds != null) 'attachmentIds': attachmentIds,
    });
  }

  Future<ChatSummary?> createChat({
    required String name,
    required int departmentId,
    required List<int> memberIds,
    bool itemAdminsCanSend = false,
    bool volunteersCanSend = false,
    bool deleteAfter24h = false,
  }) async {
    try {
      final res = await _api.post('/chats', body: {
        'name': name,
        'departmentId': departmentId,
        'memberIds': memberIds,
        'itemAdminsCanSend': itemAdminsCanSend,
        'volunteersCanSend': volunteersCanSend,
        'deleteAfter24h': deleteAfter24h,
      });
      if (res.statusCode == 201) {
        final chat = ChatSummary.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
        _chats.insert(0, chat);
        notifyListeners();
        return chat;
      }
    } catch (e) {
      debugPrint('Error creating chat: $e');
    }
    return null;
  }

  Future<bool> inviteMembers(int chatId, List<int> userIds) async {
    try {
      final res = await _api.post('/chats/$chatId/members', body: {
        'userIds': userIds,
      });
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Error inviting members: $e');
      return false;
    }
  }

  Future<bool> kickMember(int chatId, int userId) async {
    try {
      final res = await _api.delete('/chats/$chatId/members/$userId');
      return res.statusCode == 204;
    } catch (e) {
      debugPrint('Error kicking member: $e');
      return false;
    }
  }

  Future<bool> updateChatSettings(int chatId, {
    String? name,
    bool? itemAdminsCanSend,
    bool? volunteersCanSend,
    bool? deleteAfter24h,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (itemAdminsCanSend != null) body['itemAdminsCanSend'] = itemAdminsCanSend;
      if (volunteersCanSend != null) body['volunteersCanSend'] = volunteersCanSend;
      if (deleteAfter24h != null) body['deleteAfter24h'] = deleteAfter24h;
      final res = await _api.patch('/chats/$chatId', body: body);
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Error updating chat: $e');
      return false;
    }
  }

  Future<int?> uploadAttachment(int chatId, List<int> fileBytes, String fileName) async {
    try {
      final res = await _api.uploadFile(
        '/chats/$chatId/upload',
        fileBytes: fileBytes,
        fileName: fileName,
        fieldName: 'file',
      );
      if (res.statusCode == 201) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['id'] as int;
      }
    } catch (e) {
      debugPrint('Error uploading attachment: $e');
    }
    return null;
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/providers/chat_provider.dart
git commit -m "feat: add ChatProvider with socket.io integration"
```

---

### Task 10: Replace chat_screen.dart with ChatListScreen

**Files:**
- Modify: `frontend/lib/screens/chat_screen.dart`

- [ ] **Step 1: Rewrite chat_screen.dart as ChatListScreen**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  @override
  void initState() {
    super.initState();
    final chatProv = context.read<ChatProvider>();
    chatProv.setActiveChat(null);
    chatProv.fetchChats();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final chatProv = context.watch<ChatProvider>();
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Συνομιλίες'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: chatProv.loading && chatProv.chats.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : chatProv.chats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 48, color: const Color(0xFF9CA3AF)),
                      const SizedBox(height: 16),
                      Text('Δεν υπάρχουν συνομιλίες', style: tt.bodyLarge?.copyWith(color: const Color(0xFF6B7280))),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: chatProv.chats.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                  itemBuilder: (context, index) {
                    final chat = chatProv.chats[index];
                    final unread = chatProv.unread[chat.id] ?? 0;
                    final icon = _chatIcon(chat.type);

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: cs.primary.withAlpha(25),
                        child: Icon(icon, color: cs.primary, size: 22),
                      ),
                      title: Text(
                        chat.name,
                        style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: chat.lastMessage != null
                          ? Text(
                              '${chat.lastMessage!.user.forename}: ${chat.lastMessage!.text}',
                              style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : Text(
                              '${chat.memberCount} μέλη',
                              style: tt.bodySmall?.copyWith(color: const Color(0xFF9CA3AF)),
                            ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (chat.lastMessage != null)
                            Text(
                              _formatTime(chat.lastMessage!.createdAt),
                              style: tt.labelSmall?.copyWith(color: const Color(0xFF9CA3AF)),
                            ),
                          if (unread > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: cs.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$unread',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ],
                      ),
                      onTap: () => context.push('/chat/${chat.id}'),
                    );
                  },
                ),
      floatingActionButton: auth.isMissionAdmin
          ? FloatingActionButton(
              onPressed: () => context.push('/chat/create'),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  IconData _chatIcon(String type) {
    switch (type) {
      case 'department':
        return Icons.business;
      case 'mission':
        return Icons.assignment;
      case 'custom':
        return Icons.group;
      default:
        return Icons.chat;
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'τώρα';
    if (diff.inHours < 1) return '${diff.inMinutes}λ';
    if (diff.inDays < 1) return DateFormat('HH:mm').format(dt);
    if (diff.inDays < 7) return DateFormat('EEEE', 'el').format(dt);
    return DateFormat('d/M').format(dt);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/screens/chat_screen.dart
git commit -m "feat: replace chat placeholder with ChatListScreen"
```

---

### Task 11: Create ChatDetailScreen

**Files:**
- Create: `frontend/lib/screens/chat_detail_screen.dart`

- [ ] **Step 1: Write the ChatDetailScreen**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../helpers/chat_models.dart';
import '../config/api_config.dart';

class ChatDetailScreen extends StatefulWidget {
  final int chatId;

  const ChatDetailScreen({super.key, required this.chatId});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _loadingOlder = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    final chatProv = context.read<ChatProvider>();
    chatProv.setActiveChat(widget.chatId);
    chatProv.fetchMessages(widget.chatId);
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels <= 100 && !_loadingOlder && _hasMore) {
      final msgs = context.read<ChatProvider>().messagesForChat(widget.chatId);
      if (msgs.isNotEmpty) {
        setState(() => _loadingOlder = true);
        context.read<ChatProvider>().fetchMessages(widget.chatId, before: msgs.first.id).then((_) {
          if (mounted) setState(() => _loadingOlder = false);
        });
      }
    }
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    context.read<ChatProvider>().sendMessage(widget.chatId, text);
  }

  Future<void> _attachFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    final chatProv = context.read<ChatProvider>();
    final attId = await chatProv.uploadAttachment(widget.chatId, file.bytes!, file.name);
    if (attId != null) {
      chatProv.sendMessage(widget.chatId, file.name, attachmentIds: [attId]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final chatProv = context.watch<ChatProvider>();
    final auth = context.watch<AuthProvider>();

    final chat = chatProv.chats.where((c) => c.id == widget.chatId).firstOrNull;
    final msgs = chatProv.messagesForChat(widget.chatId);

    final bool canSend = _canSend(chat, auth);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            chatProv.setActiveChat(null);
            context.pop();
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(chat?.name ?? 'Συνομιλία', style: tt.titleSmall),
            Text('${chat?.memberCount ?? 0} μέλη',
                style: tt.labelSmall?.copyWith(color: const Color(0xFF6B7280))),
          ],
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          if (chat?.type == 'custom')
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => context.push('/chat/${widget.chatId}/settings'),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_loadingOlder)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: msgs.length,
              itemBuilder: (context, index) {
                final reversed = msgs.reversed.toList();
                final msg = reversed[index];
                final isMe = msg.userId == (auth.user?['id'] as int?);
                final showAvatar = index == reversed.length - 1 ||
                    reversed[index + 1].userId != msg.userId;
                return _MessageBubble(
                  message: msg,
                  isMe: isMe,
                  showAvatar: showAvatar,
                );
              },
            ),
          ),
          _BottomBar(
            textCtrl: _textCtrl,
            onSend: _send,
            onAttach: _attachFile,
            canSend: canSend,
          ),
        ],
      ),
    );
  }

  bool _canSend(ChatSummary? chat, AuthProvider auth) {
    if (chat == null) return false;
    if (auth.isMissionAdmin) return true;
    switch (chat.type) {
      case 'department':
        return false;
      case 'mission':
      case 'custom':
        return true; // Permission handled server-side
      default:
        return false;
    }
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final bool showAvatar;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        top: showAvatar ? 12 : 2,
        bottom: 2,
      ),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe && showAvatar) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: cs.primary.withAlpha(30),
              child: Text(
                message.user.forename.isNotEmpty ? message.user.forename[0] : '?',
                style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (!isMe && !showAvatar) const SizedBox(width: 36),
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? cs.primary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(8),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showAvatar && !isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${message.user.forename} ${message.user.surname}',
                        style: tt.labelSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Text(
                    message.text,
                    style: (isMe ? tt.bodyMedium : tt.bodyMedium)?.copyWith(
                      color: isMe ? Colors.white : const Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('HH:mm').format(message.createdAt),
                    style: tt.labelSmall?.copyWith(
                      color: isMe ? Colors.white.withAlpha(180) : const Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe && showAvatar) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 14,
              backgroundColor: cs.primary,
              child: Text(
                message.user.forename.isNotEmpty ? message.user.forename[0] : '?',
                style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
          if (isMe && !showAvatar) const SizedBox(width: 36),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final TextEditingController textCtrl;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final bool canSend;

  const _BottomBar({
    required this.textCtrl,
    required this.onSend,
    required this.onAttach,
    required this.canSend,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!canSend) {
      return SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Center(
            child: Text(
              'Μόνο οι διαχειριστές μπορούν να στείλουν μηνύματα',
              style: TextStyle(color: const Color(0xFF9CA3AF), fontSize: 13),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        color: Colors.white,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file, size: 22),
              color: const Color(0xFF6B7280),
              onPressed: onAttach,
            ),
            Expanded(
              child: TextField(
                controller: textCtrl,
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Μήνυμα...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF3F4F6),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 20,
              backgroundColor: cs.primary,
              child: IconButton(
                icon: const Icon(Icons.send, size: 18, color: Colors.white),
                onPressed: onSend,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/screens/chat_detail_screen.dart
git commit -m "feat: add ChatDetailScreen with message list and file attachment"
```

---

### Task 12: Create CreateChatScreen

**Files:**
- Create: `frontend/lib/screens/create_chat_screen.dart`

- [ ] **Step 1: Write CreateChatScreen**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import 'dart:convert';

class CreateChatScreen extends StatefulWidget {
  const CreateChatScreen({super.key});

  @override
  State<CreateChatScreen> createState() => _CreateChatScreenState();
}

class _CreateChatScreenState extends State<CreateChatScreen> {
  final _nameCtrl = TextEditingController();
  int? _selectedDeptId;
  final _selectedUserIds = <int>{};
  bool _itemAdminsCanSend = false;
  bool _volunteersCanSend = false;
  bool _deleteAfter24h = false;
  bool _creating = false;

  List<Map<String, dynamic>> _deptUsers = [];
  bool _loadingUsers = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchDeptUsers(int deptId) async {
    setState(() => _loadingUsers = true);
    try {
      final api = ApiClient();
      final res = await api.get('/users?departmentId=$deptId');
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        _deptUsers = list.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    setState(() => _loadingUsers = false);
  }

  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty || _selectedDeptId == null || _selectedUserIds.isEmpty) return;
    setState(() => _creating = true);
    final chatProv = context.read<ChatProvider>();
    final chat = await chatProv.createChat(
      name: _nameCtrl.text.trim(),
      departmentId: _selectedDeptId!,
      memberIds: _selectedUserIds.toList(),
      itemAdminsCanSend: _itemAdminsCanSend,
      volunteersCanSend: _volunteersCanSend,
      deleteAfter24h: _deleteAfter24h,
    );
    setState(() => _creating = false);
    if (chat != null && mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final auth = context.watch<AuthProvider>();
    final depts = auth.isAdmin
        ? (context.read<DepartmentProvider?>()?.departments ?? []).cast<Map<String, dynamic>>()
        : auth.missionAdminDepartments;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Νέα Ομαδική Συνομιλία'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Όνομα συνομιλίας',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            value: _selectedDeptId,
            decoration: const InputDecoration(
              labelText: 'Τμήμα',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
            items: depts.map((d) => DropdownMenuItem(
              value: d['id'] as int,
              child: Text(d['name'] as String? ?? 'Department'),
            )).toList(),
            onChanged: (val) {
              setState(() {
                _selectedDeptId = val;
                _selectedUserIds.clear();
                _deptUsers = [];
              });
              if (val != null) _fetchDeptUsers(val);
            },
          ),
          const SizedBox(height: 24),
          Text('Επιλογή Μελών', style: tt.titleSmall),
          const SizedBox(height: 8),
          if (_loadingUsers)
            const Center(child: CircularProgressIndicator())
          else if (_deptUsers.isEmpty && _selectedDeptId != null)
            Text('Δεν βρέθηκαν χρήστες', style: tt.bodySmall)
          else
            ...(_deptUsers.map((u) => CheckboxListTile(
                  title: Text('${u['forename']} ${u['surname']}'),
                  subtitle: Text(u['eame'] as String? ?? ''),
                  value: _selectedUserIds.contains(u['id'] as int),
                  onChanged: (sel) {
                    setState(() {
                      if (sel == true) {
                        _selectedUserIds.add(u['id'] as int);
                      } else {
                        _selectedUserIds.remove(u['id'] as int);
                      }
                    });
                  },
                  dense: true,
                ))),
          const SizedBox(height: 24),
          Text('Δικαιώματα', style: tt.titleSmall),
          SwitchListTile(
            title: const Text('Οι διαχειριστές αντικειμένων μπορούν να στέλνουν'),
            value: _itemAdminsCanSend,
            onChanged: (v) => setState(() => _itemAdminsCanSend = v),
            dense: true,
          ),
          SwitchListTile(
            title: const Text('Οι εθελοντές μπορούν να στέλνουν'),
            value: _volunteersCanSend,
            onChanged: (v) => setState(() => _volunteersCanSend = v),
            dense: true,
          ),
          SwitchListTile(
            title: const Text('Αυτόματη διαγραφή μετά από 24 ώρες'),
            value: _deleteAfter24h,
            onChanged: (v) => setState(() => _deleteAfter24h = v),
            dense: true,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _creating ? null : _create,
            icon: _creating
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check),
            label: const Text('Δημιουργία'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/screens/create_chat_screen.dart
git commit -m "feat: add CreateChatScreen for custom group chat creation"
```

---

### Task 13: Create ChatSettingsScreen

**Files:**
- Create: `frontend/lib/screens/chat_settings_screen.dart`

- [ ] **Step 1: Write ChatSettingsScreen**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../helpers/chat_models.dart';
import 'dart:convert';

class ChatSettingsScreen extends StatefulWidget {
  final int chatId;

  const ChatSettingsScreen({super.key, required this.chatId});

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  bool _loading = true;
  Map<String, dynamic>? _chatDetail;
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    _loadChat();
  }

  Future<void> _loadChat() async {
    final api = ApiClient();
    final res = await api.get('/chats/${widget.chatId}');
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _chatDetail = data;
        _members = (data['members'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        _loading = false;
      });
    }
  }

  Future<void> _kickUser(int userId) async {
    final chatProv = context.read<ChatProvider>();
    final ok = await chatProv.kickMember(widget.chatId, userId);
    if (ok) {
      setState(() => _members.removeWhere((m) => m['userId'] == userId));
      _chatDetail?['_count']?['members'] != null
          ? _chatDetail!['_count']['members'] = (_chatDetail!['_count']['members'] as int) - 1
          : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final chatProv = context.read<ChatProvider>();
    final auth = context.watch<AuthProvider>();

    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7FA),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final name = _chatDetail?['name'] as String? ?? 'Ομαδική';
    final itemAdminsCanSend = _chatDetail?['itemAdminsCanSend'] as bool? ?? false;
    final volunteersCanSend = _chatDetail?['volunteersCanSend'] as bool? ?? false;
    final deleteAfter24h = _chatDetail?['deleteAfter24h'] as bool? ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Ρυθμίσεις Συνομιλίας'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Μέλη (${_members.length})', style: tt.titleSmall),
          const SizedBox(height: 8),
          ...(_members.map((m) {
            final user = m['user'] as Map<String, dynamic>?;
            final userName = '${user?['forename'] ?? ''} ${user?['surname'] ?? ''}'.trim();
            return Card(
              color: Colors.white,
              child: ListTile(
                leading: CircleAvatar(
                  radius: 14,
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                title: Text(userName),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                  onPressed: () => _kickUser(m['userId'] as int),
                ),
              ),
            );
          })),
          const SizedBox(height: 24),
          Text('Δικαιώματα', style: tt.titleSmall),
          SwitchListTile(
            title: const Text('Οι διαχειριστές αντικειμένων μπορούν να στέλνουν'),
            value: itemAdminsCanSend,
            onChanged: (v) async {
              await chatProv.updateChatSettings(widget.chatId, itemAdminsCanSend: v);
              setState(() => _chatDetail?['itemAdminsCanSend'] = v);
            },
          ),
          SwitchListTile(
            title: const Text('Οι εθελοντές μπορούν να στέλνουν'),
            value: volunteersCanSend,
            onChanged: (v) async {
              await chatProv.updateChatSettings(widget.chatId, volunteersCanSend: v);
              setState(() => _chatDetail?['volunteersCanSend'] = v);
            },
          ),
          SwitchListTile(
            title: const Text('Αυτόματη διαγραφή μετά από 24 ώρες'),
            value: deleteAfter24h,
            onChanged: (v) async {
              await chatProv.updateChatSettings(widget.chatId, deleteAfter24h: v);
              setState(() => _chatDetail?['deleteAfter24h'] = v);
            },
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/screens/chat_settings_screen.dart
git commit -m "feat: add ChatSettingsScreen for managing custom chat members and permissions"
```

---

### Task 14: Add chat routes to router.dart

**Files:**
- Modify: `frontend/lib/config/router.dart`

- [ ] **Step 1: Add imports and routes**

In `frontend/lib/config/router.dart`, add these imports at the top (with the other screen imports):

```dart
import '../screens/chat_detail_screen.dart';
import '../screens/create_chat_screen.dart';
import '../screens/chat_settings_screen.dart';
```

Replace the existing `/chat` route:

```dart
GoRoute(
  path: '/chat',
  builder: (context, state) => const ChatScreen(),
),
```

With these routes:

```dart
GoRoute(
  path: '/chat',
  builder: (context, state) => const ChatListScreen(),
),
GoRoute(
  path: '/chat/:id',
  builder: (context, state) {
    final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
    return ChatDetailScreen(chatId: id);
  },
),
GoRoute(
  path: '/chat/create',
  builder: (context, state) => const CreateChatScreen(),
),
GoRoute(
  path: '/chat/:id/settings',
  builder: (context, state) {
    final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
    return ChatSettingsScreen(chatId: id);
  },
),
```

Note: The import for `ChatScreen` should be replaced with `chat_list_screen.dart` (the same file, since we rewrote `chat_screen.dart` to be `ChatListScreen`). Change the import:

```dart
// Replace:
import '../screens/chat_screen.dart';
// With:
import '../screens/chat_list_screen.dart';
```

Wait — we didn't create a `chat_list_screen.dart` file. We rewrote `chat_screen.dart`. So the import stays the same but the class name changes. Update the import line in router.dart to reference the new class name from the same file.

Actually, re-reading our Task 10 — we rewrote `chat_screen.dart` to contain `ChatListScreen`. So the import `import '../screens/chat_screen.dart';` is still correct, but the usage should reference `ChatListScreen` instead of `ChatScreen`. 

So the change in the router is:
1. Keep the import as `import '../screens/chat_screen.dart';`
2. Replace `ChatScreen` with `ChatListScreen` in the route builder

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/config/router.dart
git commit -m "feat: add chat routes to GoRouter"
```

---

### Task 15: Wire ChatProvider into the app and connect socket

**Files:**
- Modify: `frontend/lib/main.dart` (or wherever providers are registered)

- [ ] **Step 1: Find and update the provider registration**

First check `frontend/lib/main.dart` for the `MultiProvider` setup. The `ChatProvider` needs to be provided above the router so it's available everywhere.

In the `MultiProvider` list in `main.dart`, add:

```dart
ChangeNotifierProvider(create: (_) => ChatProvider()),
```

Also, the `ChatProvider.connect()` method needs to be called with the JWT token. This should happen after authentication. The best place is in the `ShellScreen` or `ChatListScreen` init, where we have access to the auth token.

In `ChatListScreen.initState()` (which we already wrote in Task 10), add socket connection logic. But we need the token. The `ApiClient` stores it but doesn't expose it directly. 

Instead, add a `connectSocket` method to `ChatProvider` that reads the token from `SharedPreferences`:

In `ChatProvider` (Task 9), update the `connect` method to accept the token from the caller. Then in the auth provider or wherever the token is available, call `chatProv.connect(token)`.

The simplest approach: in `ChatListScreen.initState()`, read the token from SharedPreferences and connect:

```dart
@override
void initState() {
  super.initState();
  final chatProv = context.read<ChatProvider>();
  chatProv.setActiveChat(null);
  chatProv.fetchChats();
  _connectSocket();
}

Future<void> _connectSocket() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('jwt_token');
  if (token != null) {
    if (mounted) context.read<ChatProvider>().connect(token);
  }
}
```

But we also need to add the import for `SharedPreferences` and make `_ChatListScreenState` properly handle this. Let's update Task 10 to include this.

Actually, let's keep this task focused on wiring. I'll add the socket connection in the ChatListScreen's initState.

- [ ] **Step 2: Verify main.dart provider registration**

Read `frontend/lib/main.dart` and ensure `ChatProvider` is in the providers list. If using `MultiProvider`, add:

```dart
ChangeNotifierProvider(create: (_) => ChatProvider()),
```

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/main.dart
git commit -m "feat: wire ChatProvider into app and connect socket"
```

---

### Task 16: End-to-end integration test run

- [ ] **Step 1: Ensure backend compiles**

```bash
cd backend
npm run build
```

Expected: TypeScript compilation succeeds with no errors.

- [ ] **Step 2: Run the dev backend and verify chat endpoints**

```bash
cd backend
npm run dev
```

Then in another terminal, test:

```bash
# Login to get a token
curl -X POST http://localhost:4000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"...","password":"..."}'

# List chats (uses token from login)
curl http://localhost:4000/api/chats \
  -H "Authorization: Bearer <token>"
```

Expected: 200 with chat list (should auto-create department/mission chats).

- [ ] **Step 3: Run Flutter frontend**

```bash
cd frontend
flutter pub get
flutter run -d chrome
```

Expected: app compiles, chat tab works, socket connects, messages flow.

- [ ] **Step 4: Fix any issues found during integration testing**

- [ ] **Step 5: Final commit if changes needed**

```bash
git add -A
git commit -m "fix: integration test fixes for chat system"
```
