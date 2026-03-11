import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';

/// User management with table view, hours columns, pagination, sorting.
class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _users = [];
  List<dynamic> _allDepts = [];
  bool _loading = true;

  // Filters
  String _search = '';
  String _roleFilter = 'all';
  int? _deptFilter;
  bool _deptInitialized = false;

  // Sorting
  String _sortField = 'name';
  bool _sortAsc = true;

  // Pagination
  int _page = 0;
  int _rowsPerPage = 25;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.get('/users/stats'),
        _api.get('/departments'),
      ]);
      if (results[0].statusCode == 200) {
        _users = (jsonDecode(results[0].body) as List)
            .cast<Map<String, dynamic>>();
      }
      if (results[1].statusCode == 200) {
        _allDepts = jsonDecode(results[1].body);
      }

      if (!_deptInitialized && mounted) {
        _deptInitialized = true;
        final auth = context.read<AuthProvider>();
        final myDepts = auth.user?['departments'] as List<dynamic>? ?? [];
        if (myDepts.isNotEmpty) {
          _deptFilter = myDepts.first['department']?['id'] as int?;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filterableDepts {
    final auth = context.read<AuthProvider>();
    if (auth.isAdmin) return _allDepts.cast<Map<String, dynamic>>();
    final myDepts = auth.user?['departments'] as List<dynamic>? ?? [];
    return myDepts
        .map((d) => d['department'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  // ── Filtering + Sorting ──────────────────────────
  List<Map<String, dynamic>> get _processed {
    var list = List<Map<String, dynamic>>.from(_users);

    // Department filter
    if (_deptFilter != null) {
      list = list.where((u) {
        final depts = u['departments'] as List<dynamic>? ?? [];
        return depts.any((d) => d['department']?['id'] == _deptFilter);
      }).toList();
    }

    // Role filter
    if (_roleFilter == 'admin') {
      list = list.where((u) => u['isAdmin'] == true).toList();
    } else if (_roleFilter != 'all') {
      list = list.where((u) {
        final depts = u['departments'] as List<dynamic>? ?? [];
        return depts.any((d) => d['role'] == _roleFilter);
      }).toList();
    }

    // Search
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((u) {
        final name = '${u['forename'] ?? ''} ${u['surname'] ?? ''}'.toLowerCase();
        final ename = (u['ename'] ?? '').toString().toLowerCase();
        final email = (u['email'] ?? '').toString().toLowerCase();
        return name.contains(q) || ename.contains(q) || email.contains(q);
      }).toList();
    }

    // Sort
    list.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case 'totalHours':
          cmp = ((a['totalHours'] ?? 0) as int).compareTo((b['totalHours'] ?? 0) as int);
          break;
        case 'yearHours':
          cmp = ((a['yearHours'] ?? 0) as int).compareTo((b['yearHours'] ?? 0) as int);
          break;
        case 'yearVolHours':
          cmp = ((a['yearVolHours'] ?? 0) as int).compareTo((b['yearVolHours'] ?? 0) as int);
          break;
        case 'yearTrainingHours':
          cmp = ((a['yearTrainingHours'] ?? 0) as int).compareTo((b['yearTrainingHours'] ?? 0) as int);
          break;
        case 'yearTrainerHours':
          cmp = ((a['yearTrainerHours'] ?? 0) as int).compareTo((b['yearTrainerHours'] ?? 0) as int);
          break;
        default: // name
          final na = '${a['surname'] ?? ''} ${a['forename'] ?? ''}'.toLowerCase();
          final nb = '${b['surname'] ?? ''} ${b['forename'] ?? ''}'.toLowerCase();
          cmp = na.compareTo(nb);
      }
      return _sortAsc ? cmp : -cmp;
    });

    return list;
  }

  int _countRole(String role) {
    if (role == 'admin') return _users.where((u) => u['isAdmin'] == true).length;
    return _users.where((u) {
      final depts = u['departments'] as List<dynamic>? ?? [];
      return depts.any((d) => d['role'] == role);
    }).length;
  }

  void _setSort(String field) {
    setState(() {
      if (_sortField == field) {
        _sortAsc = !_sortAsc;
      } else {
        _sortField = field;
        _sortAsc = field == 'name'; // name ascending, hours descending by default
      }
      _page = 0;
    });
  }

  // ── Create user dialog ───────────────────────────
  void _showCreateDialog() {
    final enameCtrl = TextEditingController();
    final forenameCtrl = TextEditingController();
    final surnameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Νέος Χρήστης'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: enameCtrl, decoration: const InputDecoration(labelText: 'Κωδ. Μέλους *', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: forenameCtrl, decoration: const InputDecoration(labelText: 'Όνομα *', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: surnameCtrl, decoration: const InputDecoration(labelText: 'Επώνυμο *', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email *', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: passwordCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Κωδικός (ελάχ. 8) *', border: OutlineInputBorder())),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () async {
              final body = {
                'ename': enameCtrl.text.trim(),
                'forename': forenameCtrl.text.trim(),
                'surname': surnameCtrl.text.trim(),
                'email': emailCtrl.text.trim(),
                'password': passwordCtrl.text,
              };
              try {
                final res = await _api.post('/auth/register', body: body);
                if (ctx.mounted) Navigator.pop(ctx);
                if (res.statusCode == 201) {
                  _fetch();
                } else {
                  final err = jsonDecode(res.body)['error'] ?? 'Αποτυχία';
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                }
              } catch (e) {
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Σφάλμα: $e')));
              }
            },
            child: const Text('Δημιουργία'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final processed = _processed;
    final totalPages = (processed.length / _rowsPerPage).ceil();
    final pageStart = _page * _rowsPerPage;
    final pageEnd = (pageStart + _rowsPerPage).clamp(0, processed.length);
    final pageUsers = processed.sublist(pageStart, pageEnd);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text('Διαχείριση Χρηστών', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetch, tooltip: 'Ανανέωση'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Νέος Χρήστης'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Filters ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(children: [
                Row(children: [
                  Expanded(child: _buildDeptFilter()),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Αναζήτηση...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() { _search = v; _page = 0; }),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _chip('Όλοι (${_users.length})', 'all'),
                    const SizedBox(width: 6),
                    _chip('Admins (${_countRole('admin')})', 'admin', color: Colors.amber.shade700),
                    const SizedBox(width: 6),
                    _chip('Δ. Αποστολών (${_countRole('missionAdmin')})', 'missionAdmin', color: const Color(0xFF059669)),
                    const SizedBox(width: 6),
                    _chip('Δ. Υλικού (${_countRole('itemAdmin')})', 'itemAdmin', color: const Color(0xFF7C3AED)),
                    const SizedBox(width: 6),
                    _chip('Εθελοντές (${_countRole('volunteer')})', 'volunteer', color: const Color(0xFFDC2626)),
                  ]),
                ),
              ]),
            ),

            // ── Table ──
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : processed.isEmpty
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.person_off, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text('Δεν βρέθηκαν χρήστες', style: tt.bodyLarge?.copyWith(color: Colors.grey.shade500)),
                          ]),
                        )
                      : Column(children: [
                          // ── Pagination controls ──
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Row(children: [
                              Text('${processed.length} users',
                                  style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
                              const Spacer(),
                              const Text('Γραμμές: ', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                              _pageDropdown(),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: const Icon(Icons.chevron_left, size: 20),
                                onPressed: _page > 0 ? () => setState(() => _page--) : null,
                                visualDensity: VisualDensity.compact,
                              ),
                              Text('${_page + 1} / ${totalPages.clamp(1, 999)}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              IconButton(
                                icon: const Icon(Icons.chevron_right, size: 20),
                                onPressed: _page < totalPages - 1 ? () => setState(() => _page++) : null,
                                visualDensity: VisualDensity.compact,
                              ),
                            ]),
                          ),

                          // ── Header ──
                          Container(
                            color: const Color(0xFFEEF0F4),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: Row(children: [
                              _headerCell('Name', 'name', flex: 3),
                              _headerCell('Total', 'totalHours'),
                              _headerCell('Year', 'yearHours'),
                              _headerCell('Vol', 'yearVolHours'),
                              _headerCell('Train', 'yearTrainingHours'),
                              _headerCell('Trainer', 'yearTrainerHours'),
                              const SizedBox(width: 32), // chevron space
                            ]),
                          ),

                          // ── Rows ──
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: _fetch,
                              child: ListView.builder(
                                padding: const EdgeInsets.only(bottom: 90),
                                itemCount: pageUsers.length,
                                itemBuilder: (context, i) =>
                                    _buildRow(pageUsers[i], tt, i.isEven),
                              ),
                            ),
                          ),
                        ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String label, String field, {int flex = 1}) {
    final isActive = _sortField == field;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => _setSort(field),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                    color: isActive ? const Color(0xFFDC2626) : const Color(0xFF374151))),
            if (isActive)
              Icon(_sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 12, color: const Color(0xFFDC2626)),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> user, TextTheme tt, bool even) {
    final name = '${user['forename'] ?? ''} ${user['surname'] ?? ''}'.trim();
    final isAdmin = user['isAdmin'] == true;

    return InkWell(
      onTap: () async {
        await context.push('/admin/users/${user['id']}');
        if (mounted) _fetch();
      },
      child: Container(
        color: even ? Colors.white : const Color(0xFFF9FAFB),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          // Name cell
          Expanded(
            flex: 3,
            child: Row(children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: isAdmin ? Colors.amber.shade100 : const Color(0xFFFEE2E2),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isAdmin ? Colors.amber.shade800 : const Color(0xFFDC2626)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(name.isNotEmpty ? name : user['ename'] ?? '',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (isAdmin) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                              color: Colors.amber.withAlpha(30),
                              borderRadius: BorderRadius.circular(3)),
                          child: Text('A',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.amber.shade800)),
                        ),
                      ],
                    ]),
                    Text(user['ename'] ?? '',
                        style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ]),
          ),
          // Hours cells
          _hoursCell(user['totalHours']),
          _hoursCell(user['yearHours']),
          _hoursCell(user['yearVolHours']),
          _hoursCell(user['yearTrainingHours']),
          _hoursCell(user['yearTrainerHours']),
          const Icon(Icons.chevron_right, size: 16, color: Color(0xFFD1D5DB)),
        ]),
      ),
    );
  }

  Widget _hoursCell(dynamic val) {
    final h = (val ?? 0) as int;
    return Expanded(
      child: Text(
        h > 0 ? '$h' : '—',
        style: TextStyle(
          fontSize: 12,
          fontWeight: h > 0 ? FontWeight.w600 : FontWeight.w400,
          color: h > 0 ? const Color(0xFF111827) : const Color(0xFFD1D5DB),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _pageDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _rowsPerPage,
          isDense: true,
          style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
          items: const [
            DropdownMenuItem(value: 10, child: Text('10')),
            DropdownMenuItem(value: 25, child: Text('25')),
            DropdownMenuItem(value: 50, child: Text('50')),
            DropdownMenuItem(value: 100, child: Text('100')),
          ],
          onChanged: (v) => setState(() {
            _rowsPerPage = v ?? 25;
            _page = 0;
          }),
        ),
      ),
    );
  }

  Widget _chip(String label, String key, {Color? color}) {
    final selected = _roleFilter == key;
    final c = color ?? Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () => setState(() { _roleFilter = key; _page = 0; }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? c : const Color(0xFFD1D5DB)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF374151))),
      ),
    );
  }

  Widget _buildDeptFilter() {
    final depts = _filterableDepts;
    final auth = context.read<AuthProvider>();
    final showAll = auth.isAdmin;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: _deptFilter,
          isExpanded: true,
          isDense: true,
          icon: const Icon(Icons.filter_list, size: 18),
          hint: const Text('Όλα τα Τμήματα', style: TextStyle(fontSize: 13)),
          style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
          items: [
            if (showAll)
              const DropdownMenuItem<int?>(
                  value: null, child: Text('Όλα τα Τμήματα')),
            ...depts.map((d) => DropdownMenuItem<int?>(
                  value: d['id'] as int?,
                  child: Text(d['name'] ?? 'Τμήμα'),
                )),
          ],
          onChanged: (v) => setState(() { _deptFilter = v; _page = 0; }),
        ),
      ),
    );
  }
}
