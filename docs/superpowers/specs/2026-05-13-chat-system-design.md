# Chat System Design

## Overview

Add real-time chat to Mitroo with three chat types:

1. **Department chat** — one per department. All department members can read; only mission admins can send.
2. **Mission chat** — auto-created per upcoming/active service. Members: accepted enrollees + responsible user + department mission admins. Auto-deletes (hard) 24h after the service ends.
3. **Custom group chat** — created by mission admins. Named. Configurable: whether item admins can send, whether volunteers can send, whether messages auto-delete after 24h. Mission admins own member management (invite/kick).

Real-time via Socket.io. Push notifications for offline recipients.

---

## Data Model

Four new tables:

### Chat

```prisma
enum ChatType {
  department
  mission
  custom
}

model Chat {
  id           Int      @id @default(autoincrement())
  type         ChatType
  name         String?  @db.VarChar(255)          // required for custom chats
  departmentId Int?     @map("department_id")
  serviceId    Int?     @map("service_id")
  createdById  Int?     @map("created_by_id")

  // Custom-chat permission flags
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
```

### ChatMember

```prisma
model ChatMember {
  chatId   Int @map("chat_id")
  userId   Int @map("user_id")
  joinedAt DateTime @default(now()) @map("joined_at")

  chat Chat @relation(fields: [chatId], references: [id], onDelete: Cascade)
  user User @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@id([chatId, userId])
  @@map("chat_members")
}
```

### ChatMessage

```prisma
model ChatMessage {
  id        Int      @id @default(autoincrement())
  chatId    Int      @map("chat_id")
  userId    Int      @map("user_id")
  text      String   @db.Text
  createdAt DateTime @default(now()) @map("created_at")

  chat Chat @relation(fields: [chatId], references: [id], onDelete: Cascade)
  user User @relation("ChatMessages", fields: [userId], references: [id], onDelete: Cascade)

  attachments ChatMessageAttachment[]

  @@index([chatId, createdAt])
  @@map("chat_messages")
}
```

### ChatMessageAttachment

```prisma
model ChatMessageAttachment {
  id        Int    @id @default(autoincrement())
  messageId Int    @map("message_id")
  fileName  String @map("file_name") @db.VarChar(500)
  filePath  String @map("file_path")
  mimeType  String? @map("mime_type") @db.VarChar(255)
  fileSize  Int?    @map("file_size")

  message ChatMessage @relation(fields: [messageId], references: [id], onDelete: Cascade)

  @@map("chat_message_attachments")
}
```

New relations on `User`:
- `createdChats Chat[] @relation("CreatedChats")`
- `chatMemberships ChatMember[]`
- `chatMessages ChatMessage[] @relation("ChatMessages")`

`Department` and `Service` get `chats Chat[]` back-relations.

---

## Backend API

### REST Endpoints

All under `/api/chats`, all require `authenticate` middleware.

| Method | Path | Description |
|---|---|---|
| `GET` | `/` | List chats for current user (sorted by most recent message) |
| `POST` | `/` | Create custom group chat (mission admin of target department) |
| `GET` | `/:id` | Get chat details + member list |
| `GET` | `/:id/messages?before=&limit=` | Cursor-paginated message history (newest first, default limit 50) |
| `POST` | `/:id/members` | Invite user(s) to custom chat (body: `{ userIds: number[] }`, mission admin only) |
| `DELETE` | `/:id/members/:userId` | Kick member from custom chat (mission admin only) |
| `PATCH` | `/:id` | Update custom chat name/permissions (mission admin only) |

### Chat Auto-Creation

Department and mission chats are created lazily — on `GET /`, the server ensures every department the user belongs to has a department chat, and every service the user has an accepted enrollment in (that is upcoming/active) has a mission chat. Missing chats are created and the user's own `ChatMember` row is inserted. Department chat members are drawn from `UserDepartment`; mission chat members from accepted `UserService` rows + the service's responsible user + department mission admins.

### File Upload

`POST /api/chats/:id/upload` — multipart file upload. Saves to `uploads/chat/` with sharp-processed thumbnails for images. Returns the attachment record ID for the client to reference in the next `chat:send` event. Files are deleted alongside messages during cleanup.

---

## Socket.io Events

Socket.io initialized on the same HTTP server. Auth via JWT handshake (token in `auth.token` handshake field).

| Client → Server | Server → Client | Payload |
|---|---|---|
| `chat:send` | — | `{ chatId: number, text: string, attachmentIds?: number[] }` |
| — | `chat:message` | `{ id, chatId, text, createdAt, user: { id, forename, surname, imagePath }, attachments: [...] }` |
| — | `chat:error` | `{ message: string }` (authorization failures, etc.) |
| `chat:join` | — | `{ chatId: number }` (validates membership) |
| `chat:leave` | — | `{ chatId: number }` |
| — | `chat:member-joined` | `{ chatId, user: { id, forename, surname } }` |
| — | `chat:member-left` | `{ chatId, userId }` |

On connection, the server joins the user to all their chat rooms automatically based on `ChatMember` records.

**Authorization on `chat:send`:**
- Verify user is a `ChatMember` of the chat
- **Department chat**: require `missionAdmin` role in the department
- **Mission chat**: require accepted enrollment OR be the responsible user OR be a department mission admin
- **Custom chat**: mission admins always allowed; item admins allowed if `itemAdminsCanSend == true`; volunteers allowed if `volunteersCanSend == true`
- Item admins in a custom chat are identified by their `UserDepartment.role` being `itemAdmin` (mission admins inherit implicitly)

---

## Auto-Deletion Cleanup

A polling interval runs every 15 minutes on the backend (`setInterval` in the Socket.io bootstrap):

1. **Mission chats**: for each `Chat` where `type = mission` AND `service.endAt < now - 24h`, delete all messages, attachments, members, and the chat itself. Delete attachment files from disk.
2. **Custom chats with `deleteAfter24h`**: delete `ChatMessage` rows (and their attachment files) where `createdAt < now - 24h`.

Hard deletes only — cascading via Prisma relations.

---

## Push Notifications

When a `chat:send` event is processed, after saving the message and broadcasting to the room, the server looks up members who are NOT in the target chat room (i.e., not currently connected/viewing) and sends them a push notification via the existing `sendPushToUser` infrastructure:

- **Title**: chat name (department name, service name, or custom chat name)
- **Body**: `"{sender forename surname}: {truncated text}"` (truncated to ~100 chars)
- **Data payload**: `{ chatId, type: "chat_message" }` so the client can navigate on tap

This is fire-and-forget (no retry, catch errors silently).

---

## Frontend

### Routes (GoRouter, inside ShellRoute)

| Path | Screen | Notes |
|---|---|---|
| `/chat` | `ChatListScreen` | Replaces placeholder |
| `/chat/:id` | `ChatDetailScreen` | Message view |
| `/chat/create` | `CreateChatScreen` | Custom group chat form |
| `/chat/:id/settings` | `ChatSettingsScreen` | Permissions + members |

### ChatProvider

`ChatProvider` extends `ChangeNotifier`, manages:
- `List<ChatSummary> chats` — chat list with last message preview + unread count
- `Map<int, List<ChatMessage>> messages` — messages per chat
- `Socket.io` client — connected on provider init, disconnected on dispose
- Methods: `fetchChats()`, `fetchMessages(chatId, {before, limit})`, `sendMessage(chatId, text, attachments)`, `createChat(...)`, `inviteMembers(chatId, userIds)`, `kickMember(chatId, userId)`, `updateSettings(chatId, ...)`
- Listens for `chat:message` → prepends/appends to active chat, increments unread for others
- Unread counts reset when entering a chat detail screen

### ChatListScreen

- Flat list of chat tiles, ordered by most recent message
- Each tile: avatar (department/service icon or group icon), chat name, last message preview, relative timestamp, unread badge
- FAB "New Group" visible only to mission admins
- Tapping a tile navigates to `/chat/:id`

### ChatDetailScreen

- AppBar: chat name + subtitle ("N members")
- Message list: reverse-scrollable (newest at bottom), pull-to-load-older at top
- Each bubble: sender avatar + name (unless consecutive from same sender), text, attachment thumbnails, time
- Bottom bar: text field + send button + attach file button
- If user lacks send permission, text field is hidden and replaced with "Only admins can send messages"

### CreateChatScreen

- Text field for chat name
- Department selector (which department's members to choose from)
- Member multi-select (search + checkboxes)
- Toggles: "Item admins can send", "Volunteers can send", "Auto-delete after 24h"

### ChatSettingsScreen

- Edit name
- Permission toggles (same as create)
- Member list with avatar + name + kick button per row
- "Invite" button → user search + add dialog

---

## Files to Create / Modify

**Backend (new):**
- `backend/prisma/migrations/...` — migration for new tables
- `backend/src/socket.ts` — Socket.io setup + event handlers
- `backend/src/routes/chat.routes.ts` — REST endpoints
- `backend/src/lib/chatCleanup.ts` — periodic deletion logic

**Backend (modify):**
- `backend/prisma/schema.prisma` — add models + relations
- `backend/src/app.ts` — add chat routes
- `backend/src/server.ts` — attach Socket.io to HTTP server

**Frontend (new):**
- `frontend/lib/providers/chat_provider.dart` — state management + socket client
- `frontend/lib/screens/chat_list_screen.dart`
- `frontend/lib/screens/chat_detail_screen.dart`
- `frontend/lib/screens/create_chat_screen.dart`
- `frontend/lib/screens/chat_settings_screen.dart`

**Frontend (modify):**
- `frontend/lib/config/router.dart` — add chat routes
- `frontend/lib/screens/chat_screen.dart` — replace placeholder (becomes ChatListScreen or redirect)
- `frontend/pubspec.yaml` — add `socket_io_client` dependency
