# Direct Messages Design

**Date:** 2026-05-17  
**Status:** Approved

## Overview

Add a direct messaging (DM) feature to the chat screen. Regular users can initiate a 1-on-1 chat with any mission admin in their department(s). Mission admins can initiate a 1-on-1 chat with any user in their department(s). DMs are 2-person chats that reuse the existing chat infrastructure.

## Data Model

### Schema change

Add `direct` to the `ChatType` enum:

```prisma
enum ChatType {
  department
  mission
  custom
  direct   // new
}
```

No new columns on `Chat`. A direct chat is a `Chat` with `type = direct` and exactly two `ChatMember` rows.

### Uniqueness constraint

A raw migration adds a partial unique index to prevent duplicate DM pairs:

```sql
CREATE UNIQUE INDEX chats_direct_pair
  ON chats (
    LEAST(member_a_id, member_b_id),
    GREATEST(member_a_id, member_b_id)
  )
  WHERE type = 'direct';
```

In practice, uniqueness is enforced primarily in the backend: the `POST /api/chats/direct` handler uses a serializable transaction (select-then-create) so concurrent requests cannot create duplicates. The SQL index above is a reference; the migration will implement the equivalent guarantee at the application level since PostgreSQL partial indexes cannot directly reference a joined table.

## Backend API

### `POST /api/chats/direct`

**Body:** `{ targetUserId: number }`

**Access control:**
- Regular user (`volunteer` or `itemAdmin`) → `targetUserId` must hold `missionAdmin` role in at least one department shared with the caller
- Mission admin → `targetUserId` must be any member of one of the caller's departments (where they are `missionAdmin`)
- Global admin → unrestricted

**Logic (find-or-create, wrapped in a transaction):**
1. Validate access as above
2. Find an existing `Chat` with `type = direct` where both `userId` and `targetUserId` are members
3. If found → return it (HTTP 200)
4. If not → create the `Chat` and two `ChatMember` rows (HTTP 201)
5. Emit `chat:new` via socket to `targetUserId` so the DM appears in their list immediately

**Returns:** the full chat object (same shape as `GET /api/chats/:id`)

### `GET /api/chats/direct/candidates`

Returns the list of people the calling user is allowed to DM, grouped by department.

**Response shape:**
```json
[
  {
    "departmentId": 1,
    "departmentName": "Τμήμα Αθηνών",
    "users": [
      { "id": 5, "forename": "Γιώργος", "surname": "Παπαδόπουλος", "role": "missionAdmin", "imagePath": null }
    ]
  }
]
```

**Logic:**
- Regular user → for each of their departments, return users with `role = missionAdmin`
- Mission admin → for each department where they are `missionAdmin`, return all users in that department (excluding themselves)
- Global admin → all users in all departments

### No changes to existing endpoints

`GET /:id`, `GET /:id/messages`, and `POST /:id/upload` already require membership — they work unchanged for `direct` chats.

`direct` chats behave like `department`/`mission` for leave/delete: users cannot leave or delete them.

## Frontend

### Chat list screen (`chat_screen.dart`)

The chat list is split into two labelled sections:

1. **ΣΥΝΟΜΙΛΙΕΣ ΟΜΑΔΩΝ** — all `department`, `mission`, and `custom` chats, sorted by most recent activity (existing behaviour, unchanged)
2. **ΑΜΕΣΑ ΜΗΝΥΜΑΤΑ** — all `direct` chats, sorted by most recent activity, with a "+" button in the section header

The DM section is always rendered (every authenticated user may have DM candidates). If no DMs exist yet, it shows only the "+" button and an empty-state message. The candidates list is fetched lazily — only when "+" is tapped, not on every chat list load.

The existing search bar filters across both sections.

### DM picker

Tapping "+" navigates to a new full screen — `DirectMessagePickerScreen` (consistent with `CreateChatScreen`). It calls `GET /api/chats/direct/candidates` and displays results in a `ListView` grouped by department with sticky section headers. A search field filters by name.

Tapping a person:
1. Calls `POST /api/chats/direct { targetUserId }`
2. On success, navigates to `/chat/:id` with the returned chat ID
3. If the DM already existed, the same chat is returned — no duplicate

### DM conversation screen

Reuses the existing `ChatDetailScreen`. Differences for `type = direct`:
- AppBar title is the other person's full name
- AppBar subtitle shows their role + department name
- The settings/members button is hidden
- The "send" permission is always granted to both participants (no `volunteersCanSend` / `itemAdminsCanSend` checks)

### Chat provider (`chat_provider.dart`)

- `fetchChats()` already returns all chats the user is a member of — DMs will appear automatically once created
- Add `createDirectChat(int targetUserId)` method that calls `POST /api/chats/direct`
- Add `fetchDmCandidates()` method that calls `GET /api/chats/direct/candidates`

### Router (`router.dart`)

No new routes needed. The DM picker is a new screen added at `/chat/direct/new` or pushed as a modal.

## Access control summary

| Caller role | Can DM |
|---|---|
| volunteer / itemAdmin | Mission admins in shared departments |
| missionAdmin | Any user in departments where they are missionAdmin |
| global admin | Anyone |

## Out of scope

- DM notifications beyond the existing socket `chat:new` event
- Read receipts
- Blocking / muting users
- DMs between two volunteers (not requested)
- DMs across departments where the users share no department membership
