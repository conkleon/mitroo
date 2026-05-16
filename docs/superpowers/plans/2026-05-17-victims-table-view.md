# Victims Table View Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the card-based victims list with a paginated table view showing name, date added, and chief complaint, with server-side search and date-range filtering.

**Architecture:** Backend `GET /api/victims` gains query params (`search`, `dateFrom`, `dateTo`, `status`, `page`, `limit`) and returns `{ data, total, page, limit }` with `chiefComplaint` in the select. Frontend `VictimProvider` accepts filter args and exposes pagination state. `VictimsScreen` rewritten with search bar, date pickers, `DataTable`, and page controls.

**Tech Stack:** Node.js/Express/TypeScript/Prisma (backend), Flutter/Dart (frontend)

---

### Task 1: Backend — Add search, date, status, pagination params and chiefComplaint

**Files:**
- Modify: `backend/src/routes/victim.routes.ts:144-210`

- [ ] **Step 1: Replace the GET /api/victims handler with filtered + paginated version**

Replace lines 144-210 (the entire `router.get("/", ...)` block) with:

```typescript
// ── GET /api/victims ─────────────────────────────

router.get("/", async (req: Request, res: Response) => {
  const { serviceId, search, dateFrom, dateTo, status, page, limit } = req.query;
  const userId = req.user!.userId;
  const isAdmin = req.user!.isAdmin;

  try {
    const where: any = {};

    if (serviceId) {
      where.serviceId = Number(serviceId);
    }

    // Search filter — case-insensitive name contains
    if (typeof search === "string" && search.trim().length > 0) {
      where.name = { contains: search.trim(), mode: "insensitive" };
    }

    // Date range filter
    if (typeof dateFrom === "string" && dateFrom) {
      const from = new Date(dateFrom);
      if (!isNaN(from.getTime())) {
        where.createdAt = { ...(where.createdAt ?? {}), gte: from };
      }
    }
    if (typeof dateTo === "string" && dateTo) {
      const to = new Date(dateTo);
      if (!isNaN(to.getTime())) {
        to.setHours(23, 59, 59, 999);
        where.createdAt = { ...(where.createdAt ?? {}), lte: to };
      }
    }

    // Status filter
    if (status === "open") {
      where.isFinalized = false;
    } else if (status === "finalized") {
      where.isFinalized = true;
    }

    // Access control (non-admin)
    if (!isAdmin) {
      const missionAdminDeptIds: number[] = [];
      const userDeptIds = await prisma.userDepartment.findMany({
        where: { userId, role: "missionAdmin" },
        select: { departmentId: true },
      });
      missionAdminDeptIds.push(...userDeptIds.map((d) => d.departmentId));

      where.OR = [
        { createdById: userId },
        ...(missionAdminDeptIds.length > 0
          ? [
              {
                service: {
                  departmentId: { in: missionAdminDeptIds },
                },
              },
            ]
          : []),
        {
          service: {
            userServices: {
              some: { userId, status: "accepted" },
            },
          },
        },
      ];
    }

    // Pagination
    const pageNum = Math.max(1, Number(page) || 1);
    const limitNum = Math.min(100, Math.max(1, Number(limit) || 20));
    const skip = (pageNum - 1) * limitNum;

    const [data, total] = await Promise.all([
      prisma.victim.findMany({
        where,
        orderBy: { createdAt: "desc" },
        skip,
        take: limitNum,
        select: {
          id: true,
          name: true,
          age: true,
          gender: true,
          chiefComplaint: true,
          isFinalized: true,
          createdAt: true,
          service: { select: { id: true, name: true } },
          createdBy: { select: { id: true, forename: true, surname: true } },
        },
      }),
      prisma.victim.count({ where }),
    ]);

    res.json({ data, total, page: pageNum, limit: limitNum });
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: "Μη έγκυρα δεδομένα", details: err.errors });
      return;
    }
    throw err;
  }
});
```

- [ ] **Step 2: Build check**

Run: `cd backend && npm run build`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add backend/src/routes/victim.routes.ts
git commit -m "feat: add search, date, status, pagination params and chiefComplaint to GET /api/victims"
```

---

### Task 2: Frontend — Update VictimProvider for filters and pagination

**Files:**
- Modify: `frontend/lib/providers/victim_provider.dart`

- [ ] **Step 1: Rewrite VictimProvider with filter params and pagination state**

Replace the entire file:

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/api_client.dart';

class VictimProvider extends ChangeNotifier {
  final _api = ApiClient();

  List<Map<String, dynamic>> _victims = [];
  Map<String, dynamic>? _selected;
  bool _loading = false;
  int _total = 0;
  int _currentPage = 1;
  int _limit = 20;

  List<Map<String, dynamic>> get victims => _victims;
  Map<String, dynamic>? get selected => _selected;
  bool get loading => _loading;
  int get total => _total;
  int get currentPage => _currentPage;
  int get limit => _limit;
  int get totalPages => _total == 0 ? 0 : (_total / _limit).ceil();

  Future<void> fetchVictims({
    int? serviceId,
    String? search,
    String? dateFrom,
    String? dateTo,
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    _loading = true;
    notifyListeners();
    try {
      final params = <String, String>{};
      if (serviceId != null) params['serviceId'] = serviceId.toString();
      if (search != null && search.trim().isNotEmpty) params['search'] = search.trim();
      if (dateFrom != null && dateFrom.isNotEmpty) params['dateFrom'] = dateFrom;
      if (dateTo != null && dateTo.isNotEmpty) params['dateTo'] = dateTo;
      if (status != null && status != 'all') params['status'] = status;
      params['page'] = page.toString();
      params['limit'] = limit.toString();

      final qs = params.entries.map((e) =>
        '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
      final res = await _api.get('/victims?$qs');
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        _victims = (body['data'] as List)
            .map((e) => e as Map<String, dynamic>)
            .toList();
        _total = body['total'] as int;
        _currentPage = body['page'] as int;
        _limit = body['limit'] as int;
      } else {
        debugPrint('fetchVictims failed: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('fetchVictims error: $e');
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> fetchVictim(int id) async {
    _loading = true;
    notifyListeners();
    try {
      final res = await _api.get('/victims/$id');
      if (res.statusCode == 200) {
        _selected = jsonDecode(res.body);
      }
    } catch (e) {
      debugPrint('fetchVictim error: $e');
    }
    _loading = false;
    notifyListeners();
  }

  Future<String?> createVictim(Map<String, dynamic> data) async {
    try {
      final res = await _api.post('/victims', body: data);
      if (res.statusCode == 201) {
        await fetchVictims();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> updateVictim(int id, Map<String, dynamic> data) async {
    try {
      final res = await _api.patch('/victims/$id', body: data);
      if (res.statusCode == 200) {
        await fetchVictims();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> deleteVictim(int id) async {
    try {
      final res = await _api.delete('/victims/$id');
      if (res.statusCode == 204) {
        await fetchVictims();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> finalizeVictim(int id) async {
    try {
      final res = await _api.post('/victims/$id/finalize');
      if (res.statusCode == 200) {
        await fetchVictim(id);
        await fetchVictims();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> addVitalSign(int victimId, Map<String, dynamic> data) async {
    try {
      final res = await _api.post('/victims/$victimId/vital-signs', body: data);
      if (res.statusCode == 201) {
        await fetchVictim(victimId);
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> deleteVitalSign(int victimId, int vsId) async {
    try {
      final res = await _api.delete('/victims/$victimId/vital-signs/$vsId');
      if (res.statusCode == 204) {
        await fetchVictim(victimId);
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> addTreatment(int victimId, Map<String, dynamic> data) async {
    try {
      final res = await _api.post('/victims/$victimId/treatments', body: data);
      if (res.statusCode == 201) {
        await fetchVictim(victimId);
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> deleteTreatment(int victimId, int tId) async {
    try {
      final res = await _api.delete('/victims/$victimId/treatments/$tId');
      if (res.statusCode == 204) {
        await fetchVictim(victimId);
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }
}
```

- [ ] **Step 2: Verify Flutter analysis**

Run: `cd frontend && flutter analyze lib/providers/victim_provider.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/providers/victim_provider.dart
git commit -m "feat: add filter params and pagination state to VictimProvider"
```

---

### Task 3: Frontend — Rewrite VictimsScreen as table view

**Files:**
- Modify: `frontend/lib/screens/victims_screen.dart`

- [ ] **Step 1: Replace entire file with the table-view implementation**

Replace the entire contents of `frontend/lib/screens/victims_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/victim_provider.dart';

class VictimsScreen extends StatefulWidget {
  const VictimsScreen({super.key});

  @override
  State<VictimsScreen> createState() => _VictimsScreenState();
}

class _VictimsScreenState extends State<VictimsScreen> {
  final _searchCtrl = TextEditingController();
  String _status = 'all';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _fetch());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _fetch({int page = 1}) {
    context.read<VictimProvider>().fetchVictims(
      search: _searchCtrl.text,
      dateFrom: _dateFrom != null
          ? '${_dateFrom!.year}-${_dateFrom!.month.toString().padLeft(2, '0')}-${_dateFrom!.day.toString().padLeft(2, '0')}'
          : null,
      dateTo: _dateTo != null
          ? '${_dateTo!.year}-${_dateTo!.month.toString().padLeft(2, '0')}-${_dateTo!.day.toString().padLeft(2, '0')}'
          : null,
      status: _status,
      page: page,
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VictimProvider>();
    final victims = provider.victims;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Περιστατικά'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/victims/create'),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _fetch(),
        child: Column(
          children: [
            // ── Search bar ──────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Αναζήτηση...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            _fetch();
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (_) => _fetch(),
              ),
            ),

            // ── Date range row ─────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: _DatePickerButton(
                      label: 'Από',
                      date: _dateFrom,
                      onPicked: (d) {
                        setState(() => _dateFrom = d);
                        _fetch();
                      },
                      onClear: () {
                        setState(() => _dateFrom = null);
                        _fetch();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DatePickerButton(
                      label: 'Έως',
                      date: _dateTo,
                      onPicked: (d) {
                        setState(() => _dateTo = d);
                        _fetch();
                      },
                      onClear: () {
                        setState(() => _dateTo = null);
                        _fetch();
                      },
                    ),
                  ),
                ],
              ),
            ),

            // ── Status filter chips ────────────
            _FilterRow(
              selected: _status,
              onChanged: (v) {
                setState(() => _status = v);
                _fetch();
              },
            ),

            const SizedBox(height: 4),

            // ── Table or loading/empty ─────────
            Expanded(
              child: provider.loading
                  ? const Center(child: CircularProgressIndicator())
                  : victims.isEmpty
                      ? Center(
                          child: Text(
                            'Δεν υπάρχουν περιστατικά',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF6B7280),
                              fontSize: 15,
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: MediaQuery.of(context).size.width,
                            ),
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(
                                const Color(0xFFF9FAFB),
                              ),
                              dataRowColor: WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return cs.primary.withAlpha(15);
                                }
                                return null;
                              }),
                              columnSpacing: 24,
                              horizontalMargin: 16,
                              columns: [
                                DataColumn(
                                  label: Text('Όνομα',
                                      style: tt.labelLarge?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF374151))),
                                ),
                                DataColumn(
                                  label: Text('Ημ/νία Καταγραφής',
                                      style: tt.labelLarge?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF374151))),
                                ),
                                DataColumn(
                                  label: Text('Κύριο Σύμπτωμα',
                                      style: tt.labelLarge?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF374151))),
                                ),
                              ],
                              rows: victims.asMap().entries.map((entry) {
                                final i = entry.key;
                                final v = entry.value;
                                final name = v['name'] as String? ?? 'Άγνωστο';
                                final chiefComplaint = v['chiefComplaint'] as String? ?? '';
                                return DataRow(
                                  color: i.isEven
                                      ? WidgetStateProperty.all(const Color(0xFFF9FAFB))
                                      : null,
                                  onSelectCallbacks: {
                                    WidgetState.pressed: () => context.push('/victims/${v['id']}'),
                                  },
                                  cells: [
                                    DataCell(
                                      Text(name,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF1F2937)),
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                    DataCell(
                                      Text(_formatDate(v['createdAt'] as String?),
                                          style: const TextStyle(color: Color(0xFF6B7280))),
                                    ),
                                    DataCell(
                                      Text(
                                        chiefComplaint.isNotEmpty ? chiefComplaint : '—',
                                        style: TextStyle(
                                          color: chiefComplaint.isNotEmpty
                                              ? const Color(0xFF374151)
                                              : const Color(0xFF9CA3AF),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
            ),

            // ── Pagination ──────────────────────
            if (provider.totalPages > 1)
              _PaginationBar(
                currentPage: provider.currentPage,
                totalPages: provider.totalPages,
                onPageChanged: (p) => _fetch(page: p),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Date picker button ─────────────────────────────────

class _DatePickerButton extends StatelessWidget {
  final String label;
  final DateTime? date;
  final ValueChanged<DateTime> onPicked;
  final VoidCallback onClear;

  const _DatePickerButton({
    required this.label,
    required this.date,
    required this.onPicked,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
          locale: const Locale('el'),
        );
        if (picked != null) onPicked(picked);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 15, color: cs.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                date != null
                    ? '${date!.day}/${date!.month}/${date!.year}'
                    : label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: date != null ? const Color(0xFF1F2937) : const Color(0xFF9CA3AF),
                ),
              ),
            ),
            if (date != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 16, color: Color(0xFF9CA3AF)),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Status filter chips ────────────────────────────────

class _FilterRow extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _FilterRow({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _FilterChip(label: 'Όλα', value: 'all', selected: selected, onChanged: onChanged),
          const SizedBox(width: 8),
          _FilterChip(label: 'Ανοιχτά', value: 'open', selected: selected, onChanged: onChanged),
          const SizedBox(width: 8),
          _FilterChip(label: 'Οριστικοποιημένα', value: 'finalized', selected: selected, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onChanged;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final active = selected == value;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (_) => onChanged(value),
      selectedColor: const Color(0xFFC62828),
      labelStyle: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: active ? Colors.white : const Color(0xFF1A1C1E),
      ),
    );
  }
}

// ── Pagination bar ─────────────────────────────────────

class _PaginationBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  const _PaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Build page number list (show max 7 with ellipsis)
    final pages = <int>[];
    if (totalPages <= 7) {
      for (int i = 1; i <= totalPages; i++) {
        pages.add(i);
      }
    } else {
      pages.add(1);
      if (currentPage > 3) pages.add(-1); // ellipsis
      for (int i = (currentPage - 1).clamp(2, totalPages - 1);
          i <= (currentPage + 1).clamp(2, totalPages - 1);
          i++) {
        pages.add(i);
      }
      if (currentPage < totalPages - 2) pages.add(-2); // ellipsis
      pages.add(totalPages);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PageButton(
            icon: Icons.chevron_left,
            enabled: currentPage > 1,
            onTap: () => onPageChanged(currentPage - 1),
          ),
          ...pages.map((p) {
            if (p < 0) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: Text('…', style: TextStyle(color: Color(0xFF9CA3AF))),
              );
            }
            return _PageButton(
              label: '$p',
              active: p == currentPage,
              enabled: true,
              onTap: () => onPageChanged(p),
            );
          }),
          _PageButton(
            icon: Icons.chevron_right,
            enabled: currentPage < totalPages,
            onTap: () => onPageChanged(currentPage + 1),
          ),
        ],
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  const _PageButton({
    this.label,
    this.icon,
    this.active = false,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        width: 36,
        height: 36,
        child: Material(
          color: active ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(8),
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 18,
                      color: enabled ? const Color(0xFF374151) : const Color(0xFFD1D5DB))
                  : Text(label!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: active
                            ? Colors.white
                            : enabled
                                ? const Color(0xFF374151)
                                : const Color(0xFFD1D5DB),
                      )),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify Flutter analysis**

Run: `cd frontend && flutter analyze lib/screens/victims_screen.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/screens/victims_screen.dart
git commit -m "feat: rewrite victims screen as table view with search, date filters, and pagination"
```
