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
