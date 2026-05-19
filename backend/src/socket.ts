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
  if (!chat.departmentId) {
    if (chat.type === 'direct') return true;
    return false;
  }

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

    case "direct":
      return true;

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
        tag: `chat-${chat.id}`,
        route: `/chat/${chat.id}`,
        data: { chatId: chat.id, type: "chat_message" },
      }).catch(() => {});
    }
  }
}

export function getIO(): Server {
  if (!io) throw new Error("Socket.io not initialized");
  return io;
}
