# Direct Messages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 1-on-1 direct messaging between users and mission admins, surfaced as a dedicated "ΑΜΕΣΑ ΜΗΝΥΜΑΤΑ" section below group chats in the chat list screen.

**Architecture:** Add a `direct` value to the existing `ChatType` DB enum. A new idempotent `POST /api/chats/direct` endpoint finds or creates a 2-member chat. The Flutter chat list splits into two sections (groups above, DMs below); a new `DirectMessagePickerScreen` lets users pick a recipient grouped by department.

**Tech Stack:** Node.js/Express/Prisma/PostgreSQL (backend), Flutter/Provider/GoRouter (frontend), Socket.IO (real-time delivery).

---

## File Map

| Action | Path | Purpose |
|---|---|---|
| Create | `backend/prisma/migrations/20260517200000_add_direct_chat_type/migration.sql` | Adds `direct` enum value to DB |
| Modify | `backend/prisma/schema.prisma` | Adds `direct` to `ChatType` enum |
| Modify | `backend/src/routes/chat.routes.ts` | Two new endpoints; DM name resolution in `GET /chats` |
| Modify | `frontend/lib/helpers/chat_models.dart` | Adds `DmCandidate` and `DmCandidateGroup` models |
| Modify | `frontend/lib/providers/chat_provider.dart` | Adds `createDirectChat()` and `fetchDmCandidates()` |
| Modify | `frontend/lib/config/router.dart` | Adds `/chat/direct/new` route |
| Create | `frontend/lib/screens/direct_message_picker_screen.dart` | New screen for picking a DM recipient |
| Modify | `frontend/lib/screens/chat_screen.dart` | Splits chat list into two labelled sections |
| Modify | `frontend/lib/screens/chat_detail_screen.dart` | DM-specific AppBar; always-on send permission |

---

## Task 1: DB Migration — add `direct` to `ChatType`

**Files:**
- Modify: `backend/prisma/schema.prisma`
- Create: `backend/prisma/migrations/20260517200000_add_direct_chat_type/migration.sql`

- [ ] **Step 1: Edit `schema.prisma` to add `direct` to the enum**

In `backend/prisma/schema.prisma`, find the `ChatType` enum and add `direct`:

```prisma
enum ChatType {
  department
  mission
  custom
  direct

  @@map("chat_type")
}
```

- [ ] **Step 2: Create the migration SQL file**

Create directory `backend/prisma/migrations/20260517200000_add_direct_chat_type/` and write `migration.sql`:

```sql
-- AlterEnum
ALTER TYPE "chat_type" ADD VALUE 'direct';
```

- [ ] **Step 3: Run the migration**

```bash
cd backend
npm run prisma:migrate
```

Expected output includes: `The following migration(s) have been applied: 20260517200000_add_direct_chat_type`

- [ ] **Step 4: Regenerate the Prisma client**

```bash
cd backend
npm run prisma:generate
```

Expected output: `✔ Generated Prisma Client`

- [ ] **Step 5: Commit**

```bash
git add backend/prisma/schema.prisma backend/prisma/migrations/20260517200000_add_direct_chat_type/
git commit -m "feat(db): add direct chat type to ChatType enum"
```

---

## Task 2: Backend — `GET /api/chats/direct/candidates`

**Files:**
- Modify: `backend/src/routes/chat.routes.ts`

- [ ] **Step 1: Add the candidates route**

Open `backend/src/routes/chat.routes.ts`. Insert the following block **before** the existing `router.get("/:id", ...)` handler (around line 223):

```typescript
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
```

- [ ] **Step 2: Start the backend dev server**

```bash
cd backend && npm run dev
```

- [ ] **Step 3: Verify the endpoint as a regular user**

Replace `<TOKEN>` with a valid JWT from SharedPreferences (log in via the app and grab the token). The response should be a JSON array of `{ departmentId, departmentName, users: [...] }` objects where `users` are missionAdmins only.

```bash
curl -s -H "Authorization: Bearer <TOKEN>" http://localhost:4000/api/chats/direct/candidates | jq .
```

- [ ] **Step 4: Commit**

```bash
git add backend/src/routes/chat.routes.ts
git commit -m "feat(api): add GET /chats/direct/candidates endpoint"
```

---

## Task 3: Backend — `GET /api/chats` DM name + `POST /api/chats/direct`

**Files:**
- Modify: `backend/src/routes/chat.routes.ts`

### Part A: Fix DM name resolution in `GET /api/chats`

- [ ] **Step 1: Add `members` include to the `allChats` query**

Find the `allChats` query in `GET /api/chats` (around line 123). Replace it with:

```typescript
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
    members: {
      where: { userId: { not: userId } },
      include: { user: { select: { id: true, forename: true, surname: true } } },
      take: 1,
    },
  },
  orderBy: { updatedAt: "desc" },
});
```

- [ ] **Step 2: Update the `result` mapping to resolve DM names**

Find the `result` mapping (around line 140). Replace the `name:` line:

```typescript
const result = allChats.map((chat) => {
  const dmPeer = chat.type === "direct" ? (chat.members[0]?.user ?? null) : null;
  return {
    id: chat.id,
    type: chat.type,
    name: dmPeer
      ? `${dmPeer.forename} ${dmPeer.surname}`.trim()
      : chat.name ?? chat.department?.name ?? chat.service?.name ?? "Chat",
    departmentId: chat.departmentId,
    serviceId: chat.serviceId,
    itemAdminsCanSend: chat.itemAdminsCanSend,
    volunteersCanSend: chat.volunteersCanSend,
    deleteAfter24h: chat.deleteAfter24h,
    memberCount: chat._count.members,
    lastMessage: chat.messages[0] ?? null,
    createdAt: chat.createdAt,
    updatedAt: chat.updatedAt,
  };
});
```

### Part B: Add `POST /api/chats/direct`

- [ ] **Step 3: Add the direct chat create/find route**

Insert the following block **before** the existing `router.post("/", ...)` handler:

```typescript
// ── POST /api/chats/direct ───────────────────────────
const directChatSchema = z.object({
  targetUserId: z.number().int(),
});

router.post("/direct", async (req: Request, res: Response) => {
  try {
    const userId = req.user!.userId;
    const isAdmin = req.user!.isAdmin;
    const { targetUserId } = directChatSchema.parse(req.body);

    if (userId === targetUserId) {
      res.status(400).json({ error: "Cannot start a DM with yourself" });
      return;
    }

    if (!isAdmin) {
      const callerAdminDepts = await prisma.userDepartment.findMany({
        where: { userId, role: "missionAdmin" },
        select: { departmentId: true },
      });

      if (callerAdminDepts.length > 0) {
        // Caller is missionAdmin: target must be a member of one of their departments
        const allowed = await prisma.userDepartment.count({
          where: {
            userId: targetUserId,
            departmentId: { in: callerAdminDepts.map((d) => d.departmentId) },
          },
        });
        if (allowed === 0) {
          res.status(403).json({ error: "Target user is not in any of your departments" });
          return;
        }
      } else {
        // Regular user: target must be missionAdmin in a shared department
        const callerDepts = await prisma.userDepartment.findMany({
          where: { userId },
          select: { departmentId: true },
        });
        const allowed = await prisma.userDepartment.count({
          where: {
            userId: targetUserId,
            role: "missionAdmin",
            departmentId: { in: callerDepts.map((d) => d.departmentId) },
          },
        });
        if (allowed === 0) {
          res.status(403).json({ error: "You can only DM mission admins in your departments" });
          return;
        }
      }
    }

    // Find existing DM between the two users
    const existing = await prisma.chat.findFirst({
      where: {
        type: "direct",
        AND: [
          { members: { some: { userId } } },
          { members: { some: { userId: targetUserId } } },
        ],
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

    if (existing) {
      res.json(existing);
      return;
    }

    // Create new DM
    const chat = await prisma.chat.create({
      data: {
        type: "direct",
        members: {
          create: [{ userId }, { userId: targetUserId }],
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
    io.to(`user:${targetUserId}`).emit("chat:new", { id: chat.id, type: "direct" });

    res.status(201).json(chat);
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Validation failed", details: err.errors });
      return;
    }
    throw err;
  }
});
```

- [ ] **Step 4: Update `DELETE /:id/leave` to reject `direct` chats**

Find the `DELETE /:id/leave` handler. Change the type check from:

```typescript
if (chat.type !== "custom") {
  res.status(400).json({ error: "Cannot leave department or mission chats" });
  return;
}
```

To:

```typescript
if (chat.type !== "custom") {
  res.status(400).json({ error: "Cannot leave department, mission, or direct chats" });
  return;
}
```

- [ ] **Step 5: Verify `POST /api/chats/direct` creates a DM**

Get two user JWTs (one regular user, one missionAdmin in the same department). Replace `<USER_TOKEN>` and `<ADMIN_ID>`:

```bash
curl -s -X POST \
  -H "Authorization: Bearer <USER_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"targetUserId": <ADMIN_ID>}' \
  http://localhost:4000/api/chats/direct | jq '{id, type}'
```

Expected: `{ "id": <some_int>, "type": "direct" }`

Call the same endpoint again with the same token — the same `id` must be returned (idempotency check).

- [ ] **Step 6: Commit**

```bash
git add backend/src/routes/chat.routes.ts
git commit -m "feat(api): add POST /chats/direct with find-or-create logic"
```

---

## Task 4: Frontend Models — `DmCandidate` and `DmCandidateGroup`

**Files:**
- Modify: `frontend/lib/helpers/chat_models.dart`

- [ ] **Step 1: Add the two model classes**

Append the following to the end of `frontend/lib/helpers/chat_models.dart`:

```dart
class DmCandidate {
  final int id;
  final String forename;
  final String surname;
  final String role;
  final String? imagePath;

  DmCandidate({
    required this.id,
    required this.forename,
    required this.surname,
    required this.role,
    this.imagePath,
  });

  String get fullName => '$forename $surname'.trim();

  factory DmCandidate.fromJson(Map<String, dynamic> json) {
    return DmCandidate(
      id: (json['id'] as num?)?.toInt() ?? 0,
      forename: json['forename'] as String? ?? '',
      surname: json['surname'] as String? ?? '',
      role: json['role'] as String? ?? '',
      imagePath: json['imagePath'] as String?,
    );
  }
}

class DmCandidateGroup {
  final int departmentId;
  final String departmentName;
  final List<DmCandidate> users;

  DmCandidateGroup({
    required this.departmentId,
    required this.departmentName,
    required this.users,
  });

  factory DmCandidateGroup.fromJson(Map<String, dynamic> json) {
    return DmCandidateGroup(
      departmentId: (json['departmentId'] as num?)?.toInt() ?? 0,
      departmentName: json['departmentName'] as String? ?? '',
      users: (json['users'] as List<dynamic>? ?? [])
          .map((u) => DmCandidate.fromJson(u as Map<String, dynamic>))
          .toList(),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/helpers/chat_models.dart
git commit -m "feat(models): add DmCandidate and DmCandidateGroup"
```

---

## Task 5: Frontend Provider — `createDirectChat()` and `fetchDmCandidates()`

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart`

- [ ] **Step 1: Add the import for `DmCandidateGroup`**

The `DmCandidateGroup` class is already in `chat_models.dart` which is already imported at the top of `chat_provider.dart` — no import change needed.

- [ ] **Step 2: Add `fetchDmCandidates()` method**

After the `createChat()` method (around line 197), add:

```dart
Future<List<DmCandidateGroup>> fetchDmCandidates() async {
  try {
    final res = await _api.get('/chats/direct/candidates');
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      return list
          .map((g) => DmCandidateGroup.fromJson(g as Map<String, dynamic>))
          .toList();
    }
  } catch (e) {
    debugPrint('Error fetching DM candidates: $e');
  }
  return [];
}
```

- [ ] **Step 3: Add `createDirectChat()` method**

Directly after `fetchDmCandidates()`, add:

```dart
Future<int?> createDirectChat(int targetUserId) async {
  try {
    final res = await _api.post(
      '/chats/direct',
      body: {'targetUserId': targetUserId},
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      await fetchChats();
      return (data['id'] as num?)?.toInt();
    }
  } catch (e) {
    debugPrint('Error creating direct chat: $e');
  }
  return null;
}
```

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/providers/chat_provider.dart
git commit -m "feat(provider): add createDirectChat and fetchDmCandidates"
```

---

## Task 6: Frontend Router — `/chat/direct/new`

**Files:**
- Modify: `frontend/lib/config/router.dart`

- [ ] **Step 1: Add import for the new screen**

At the top of `router.dart`, after the `create_chat_screen.dart` import (line 28), add:

```dart
import '../screens/direct_message_picker_screen.dart';
```

- [ ] **Step 2: Add the route**

In `router.dart`, find the existing `/chat/create` route (around line 96). Add the new route immediately after it:

```dart
GoRoute(
  path: '/chat/direct/new',
  builder: (context, state) => const DirectMessagePickerScreen(),
),
```

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/config/router.dart
git commit -m "feat(router): add /chat/direct/new route"
```

---

## Task 7: Frontend — `DirectMessagePickerScreen`

**Files:**
- Create: `frontend/lib/screens/direct_message_picker_screen.dart`

- [ ] **Step 1: Create the file**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../helpers/chat_models.dart';

class DirectMessagePickerScreen extends StatefulWidget {
  const DirectMessagePickerScreen({super.key});

  @override
  State<DirectMessagePickerScreen> createState() =>
      _DirectMessagePickerScreenState();
}

class _DirectMessagePickerScreenState
    extends State<DirectMessagePickerScreen> {
  List<DmCandidateGroup> _groups = [];
  bool _loading = true;
  bool _creating = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final groups = await context.read<ChatProvider>().fetchDmCandidates();
    if (mounted) setState(() { _groups = groups; _loading = false; });
  }

  List<DmCandidateGroup> get _filtered {
    if (_searchQuery.isEmpty) return _groups;
    final q = _searchQuery.toLowerCase();
    return _groups
        .map((g) => DmCandidateGroup(
              departmentId: g.departmentId,
              departmentName: g.departmentName,
              users: g.users
                  .where((u) => u.fullName.toLowerCase().contains(q))
                  .toList(),
            ))
        .where((g) => g.users.isNotEmpty)
        .toList();
  }

  Future<void> _pick(DmCandidate candidate) async {
    if (_creating) return;
    setState(() => _creating = true);
    final chatId =
        await context.read<ChatProvider>().createDirectChat(candidate.id);
    if (!mounted) return;
    setState(() => _creating = false);
    if (chatId != null) {
      context.pop();
      context.push('/chat/$chatId');
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'missionAdmin':
        return 'Διαχ. Αποστολών';
      case 'itemAdmin':
        return 'Διαχ. Αντικειμένων';
      case 'volunteer':
        return 'Εθελοντής';
      default:
        return role;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final groups = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Νέο άμεσο μήνυμα'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Αναζήτηση...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) =>
                  setState(() => _searchQuery = v.trim().toLowerCase()),
            ),
          ),
          if (_creating)
            const LinearProgressIndicator()
          else
            const SizedBox(height: 2),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : groups.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'Δεν βρέθηκαν αποτελέσματα'
                              : 'Δεν υπάρχουν διαθέσιμοι χρήστες',
                          style: tt.bodyLarge
                              ?.copyWith(color: const Color(0xFF6B7280)),
                        ),
                      )
                    : ListView.builder(
                        itemCount: groups.fold<int>(
                          0,
                          (sum, g) => sum + 1 + g.users.length,
                        ),
                        itemBuilder: (context, index) {
                          int offset = 0;
                          for (final group in groups) {
                            if (index == offset) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Text(
                                  group.departmentName.toUpperCase(),
                                  style: tt.labelSmall?.copyWith(
                                    color: const Color(0xFF9CA3AF),
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                            }
                            offset++;
                            final userIndex = index - offset;
                            if (userIndex < group.users.length) {
                              final candidate = group.users[userIndex];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: cs.primary.withAlpha(25),
                                  child: Text(
                                    candidate.forename.isNotEmpty
                                        ? candidate.forename[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                        color: cs.primary,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                title: Text(candidate.fullName),
                                subtitle: Text(_roleLabel(candidate.role)),
                                onTap: () => _pick(candidate),
                              );
                            }
                            offset += group.users.length;
                          }
                          return const SizedBox.shrink();
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Run Flutter and open the picker**

```bash
cd frontend && flutter run -d chrome
```

Navigate to the chat screen, tap "+" in the DM section header (not yet wired — you can test by navigating directly to `http://localhost:PORT/chat/direct/new` in the browser). Verify the list loads with department headers and user rows.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/screens/direct_message_picker_screen.dart
git commit -m "feat(screen): add DirectMessagePickerScreen"
```

---

## Task 8: Frontend — Chat List Screen split into two sections

**Files:**
- Modify: `frontend/lib/screens/chat_screen.dart`

- [ ] **Step 1: Replace the `build` method body**

In `chat_screen.dart`, the current `build` method returns a `Scaffold` with a single `ListView.separated`. Replace the entire `Scaffold` body with the two-section layout below.

The key change: split `chatProv.chats` by type into `_groupChats` and `_directChats`, render a section header + list for each, and add a "+" button to the DM header that navigates to `/chat/direct/new`.

Replace the entire `build` method (lines 51–203) with:

```dart
@override
Widget build(BuildContext context) {
  final tt = Theme.of(context).textTheme;
  final cs = Theme.of(context).colorScheme;
  final chatProv = context.watch<ChatProvider>();
  final auth = context.watch<AuthProvider>();

  final allFiltered = _filteredChats(chatProv);
  final groupChats =
      allFiltered.where((c) => c.type != 'direct').toList();
  final directChats =
      allFiltered.where((c) => c.type == 'direct').toList();

  return Scaffold(
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Αναζήτηση συνομιλιών...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (v) =>
                setState(() => _searchQuery = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: chatProv.loading && chatProv.chats.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    _SectionHeader(
                      label: 'ΣΥΝΟΜΙΛΙΕΣ ΟΜΑΔΩΝ',
                    ),
                    if (groupChats.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'Δεν βρέθηκαν συνομιλίες'
                              : 'Δεν υπάρχουν συνομιλίες ομάδων',
                          style: tt.bodySmall
                              ?.copyWith(color: const Color(0xFF9CA3AF)),
                        ),
                      )
                    else
                      ...groupChats.map((chat) => _buildChatTile(
                          context, chat, chatProv, cs, tt)),
                    _SectionHeader(
                      label: 'ΑΜΕΣΑ ΜΗΝΥΜΑΤΑ',
                      trailing: IconButton(
                        icon: Icon(Icons.add_circle,
                            color: cs.primary, size: 20),
                        tooltip: 'Νέο άμεσο μήνυμα',
                        onPressed: () =>
                            context.push('/chat/direct/new'),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),
                    if (directChats.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'Δεν βρέθηκαν άμεσα μηνύματα'
                              : 'Δεν υπάρχουν άμεσα μηνύματα',
                          style: tt.bodySmall
                              ?.copyWith(color: const Color(0xFF9CA3AF)),
                        ),
                      )
                    else
                      ...directChats.map((chat) => _buildChatTile(
                          context, chat, chatProv, cs, tt)),
                  ],
                ),
        ),
      ],
    ),
    floatingActionButton: auth.isMissionAdmin
        ? FloatingActionButton(
            onPressed: () => context.push('/chat/create'),
            child: const Icon(Icons.add),
          )
        : null,
  );
}

Widget _buildChatTile(
  BuildContext context,
  ChatSummary chat,
  ChatProvider chatProv,
  ColorScheme cs,
  TextTheme tt,
) {
  final unread = chatProv.unread[chat.id] ?? 0;
  final icon = _chatIcon(chat.type);

  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ListTile(
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
                style:
                    tt.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : Text(
                '${chat.memberCount} μέλη',
                style:
                    tt.bodySmall?.copyWith(color: const Color(0xFF9CA3AF)),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (chat.lastMessage != null)
              Text(
                _formatTime(chat.lastMessage!.createdAt),
                style: tt.labelSmall
                    ?.copyWith(color: const Color(0xFF9CA3AF)),
              ),
            if (unread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$unread',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
        onTap: () => context.push('/chat/${chat.id}'),
      ),
      const Divider(height: 1, indent: 72),
    ],
  );
}
```

- [ ] **Step 2: Add the `_SectionHeader` widget class**

After the closing `}` of `_ChatListScreenState`, add:

```dart
class _SectionHeader extends StatelessWidget {
  final String label;
  final Widget? trailing;

  const _SectionHeader({required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: tt.labelSmall?.copyWith(
                color: const Color(0xFF9CA3AF),
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Update `_chatIcon` to handle the `direct` type**

Find the `_chatIcon` method and add the `direct` case:

```dart
IconData _chatIcon(String type) {
  switch (type) {
    case 'department':
      return Icons.business;
    case 'mission':
      return Icons.assignment;
    case 'custom':
      return Icons.group;
    case 'direct':
      return Icons.person;
    default:
      return Icons.chat;
  }
}
```

- [ ] **Step 4: Hot reload and verify the two-section layout**

With the Flutter app running, hot reload (`r` in the terminal). The chat screen should now show "ΣΥΝΟΜΙΛΙΕΣ ΟΜΑΔΩΝ" and "ΑΜΕΣΑ ΜΗΝΥΜΑΤΑ" sections. Tapping "+" in the DM header should navigate to the picker screen.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/chat_screen.dart
git commit -m "feat(screen): split chat list into group and DM sections"
```

---

## Task 9: Frontend — `ChatDetailScreen` DM mode

**Files:**
- Modify: `frontend/lib/screens/chat_detail_screen.dart`

- [ ] **Step 1: Update the AppBar to show DM-specific subtitle**

Find the `title:` column in the `AppBar` (around line 103):

```dart
title: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(chat?.name ?? 'Συνομιλία', style: tt.titleSmall),
    Text('${chat?.memberCount ?? 0} μέλη',
        style: tt.labelSmall
            ?.copyWith(color: const Color(0xFF6B7280))),
  ],
),
```

Replace with:

```dart
title: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(chat?.name ?? 'Συνομιλία', style: tt.titleSmall),
    Text(
      chat?.type == 'direct'
          ? 'Άμεσο μήνυμα'
          : '${chat?.memberCount ?? 0} μέλη',
      style: tt.labelSmall
          ?.copyWith(color: const Color(0xFF6B7280)),
    ),
  ],
),
```

- [ ] **Step 2: Hide all action buttons for DM chats**

Find the `actions:` list in the `AppBar` (around line 114):

```dart
actions: [
  IconButton(
    icon: const Icon(Icons.people),
    onPressed: () => _showParticipants(context),
  ),
  if (chat?.type == 'custom') ...[
    IconButton(
      icon: const Icon(Icons.settings),
      onPressed: () =>
          context.push('/chat/${widget.chatId}/settings'),
    ),
    IconButton(
      icon: const Icon(Icons.exit_to_app, color: Color(0xFFDC2626)),
      onPressed: () => _confirmLeaveChat(context),
    ),
  ],
],
```

Replace with:

```dart
actions: chat?.type == 'direct'
    ? []
    : [
        IconButton(
          icon: const Icon(Icons.people),
          onPressed: () => _showParticipants(context),
        ),
        if (chat?.type == 'custom') ...[
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () =>
                context.push('/chat/${widget.chatId}/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app,
                color: Color(0xFFDC2626)),
            onPressed: () => _confirmLeaveChat(context),
          ),
        ],
      ],
```

- [ ] **Step 3: Allow sending in DM chats**

Find the `_canSend` method (around line 265):

```dart
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
```

Replace with:

```dart
bool _canSend(ChatSummary? chat, AuthProvider auth) {
  if (chat == null) return false;
  if (auth.isMissionAdmin) return true;
  switch (chat.type) {
    case 'department':
      return false;
    case 'mission':
    case 'custom':
    case 'direct':
      return true;
    default:
      return false;
  }
}
```

- [ ] **Step 4: Hot reload and open a DM conversation**

Create a DM via the picker. Verify:
- AppBar title shows the other person's name
- AppBar subtitle shows "Άμεσο μήνυμα"
- No settings, leave, or members buttons visible
- You can type and send a message
- The message appears in real time on the recipient's device

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/chat_detail_screen.dart
git commit -m "feat(screen): add DM mode to ChatDetailScreen"
```

---

## Task 10: End-to-end smoke test

- [ ] **Step 1: Test as a regular user**

Log in as a user who is `volunteer` in at least one department that has a `missionAdmin`.

1. Go to the Chat screen — verify the two sections render (ΣΥΝΟΜΙΛΙΕΣ ΟΜΑΔΩΝ and ΑΜΕΣΑ ΜΗΝΥΜΑΤΑ)
2. Tap "+" in the ΑΜΕΣΑ ΜΗΝΥΜΑΤΑ header
3. Verify the picker shows mission admins grouped by department
4. Tap a mission admin — verify you land in a DM conversation
5. Send a message — verify it appears in the chat
6. Tap "+" again and pick the same admin — verify you land in the **same** chat (no duplicate)

- [ ] **Step 2: Test as a mission admin**

Log in as a mission admin.

1. Go to Chat — verify the DM section and "+" button are visible
2. Tap "+" — verify the picker shows **all users** in their departments (not just admins)
3. Tap a regular user — verify a DM opens
4. Verify the previously created DM from Step 1 also appears in this admin's DM section

- [ ] **Step 3: Test real-time delivery**

Have two browser tabs open (one per user). Send a DM — verify `chat:new` socket event causes the chat to appear in the recipient's list without a page refresh.

- [ ] **Step 4: Final commit**

```bash
git add .
git commit -m "feat: direct messages — end-to-end complete"
```
