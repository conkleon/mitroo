import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/service_provider.dart';
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
  List<dynamic> _allSpecs = [];
  bool _loading = true;

  // Filters
  String _search = '';
  int? _deptFilter;
  int? _specFilter;
  bool _deptInitialized = false;

  // Sorting
  String _sortField = 'name';
  bool _sortAsc = true;

  // Pagination
  int _page = 0;
  int _rowsPerPage = 25;

  // Selection
  bool _selectionMode = false;
  final Set<int> _selectedIds = {};

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
        _api.get('/specializations'),
      ]);
      if (results[0].statusCode == 200) {
        _users = (jsonDecode(results[0].body) as List)
            .cast<Map<String, dynamic>>();
      }
      if (results[1].statusCode == 200) {
        _allDepts = jsonDecode(results[1].body);
      }
      if (results[2].statusCode == 200) {
        _allSpecs = jsonDecode(results[2].body);
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

    // Specialization filter
    if (_specFilter != null) {
      list = list.where((u) {
        final specs = u['specializations'] as List<dynamic>? ?? [];
        return specs.any((s) => s['specialization']?['id'] == _specFilter);
      }).toList();
    }

    // Search
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((u) {
        final name = '${u['forename'] ?? ''} ${u['surname'] ?? ''}'.toLowerCase();
        final eame = (u['eame'] ?? '').toString().toLowerCase();
        final email = (u['email'] ?? '').toString().toLowerCase();
        return name.contains(q) || eame.contains(q) || email.contains(q);
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

  int _countSpec(int specId) {
    var users = List<Map<String, dynamic>>.from(_users);
    if (_deptFilter != null) {
      users = users.where((u) {
        final depts = u['departments'] as List<dynamic>? ?? [];
        return depts.any((d) => d['department']?['id'] == _deptFilter);
      }).toList();
    }
    return users.where((u) {
      final specs = u['specializations'] as List<dynamic>? ?? [];
      return specs.any((s) => s['specialization']?['id'] == specId);
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

  // ── Selection ───────────────────────────────────
  void _enterSelectionMode(int userId) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(userId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelect(int userId) {
    setState(() {
      if (_selectedIds.contains(userId)) {
        _selectedIds.remove(userId);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(userId);
      }
    });
  }

  void _toggleSelectAll(List<Map<String, dynamic>> pageUsers) {
    setState(() {
      final pageIds = pageUsers.map((u) => u['id'] as int).toSet();
      if (pageIds.every((id) => _selectedIds.contains(id))) {
        _selectedIds.removeAll(pageIds);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.addAll(pageIds);
      }
    });
  }

  // ── Create user dialog ───────────────────────────
  void _showCreateDialog() {
    final eameCtrl = TextEditingController();
    final forenameCtrl = TextEditingController();
    final surnameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    int? selectedDeptId;
    String? selectedDeptName;
    String selectedDeptRole = 'volunteer';
    int? selectedSpecId;
    String selectedRank = 'Γ';
    final rootSpecs = _allSpecs.where((s) => s['rootId'] == null).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Νέος Χρήστης'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: eameCtrl, decoration: const InputDecoration(labelText: 'EAME (προαιρετικό)', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: forenameCtrl, decoration: const InputDecoration(labelText: 'Όνομα *', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: surnameCtrl, decoration: const InputDecoration(labelText: 'Επώνυμο *', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email *', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedRank,
                    decoration: const InputDecoration(labelText: 'Βαθμός', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'Α', child: Text('Α')),
                      DropdownMenuItem(value: 'Β', child: Text('Β')),
                      DropdownMenuItem(value: 'Γ', child: Text('Γ')),
                    ],
                    onChanged: (v) => setDlgState(() => selectedRank = v ?? 'Γ'),
                  ),
                  const SizedBox(height: 12),
                  Autocomplete<Map<String, dynamic>>(
                    displayStringForOption: (d) => d['name']?.toString() ?? '',
                    optionsBuilder: (textEditingValue) {
                      final q = textEditingValue.text.toLowerCase().trim();
                      final opts = _allDepts.cast<Map<String, dynamic>>();
                      if (q.isEmpty) return opts;
                      return opts.where((d) => (d['name'] ?? '').toString().toLowerCase().contains(q));
                    },
                    onSelected: (d) {
                      setDlgState(() {
                        selectedDeptId = d['id'] as int;
                        selectedDeptName = d['name']?.toString();
                      });
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      if (selectedDeptName != null && controller.text.isEmpty) {
                        controller.text = selectedDeptName!;
                      }
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: 'Τμήμα πρώτης ανάθεσης *',
                          hintText: 'Αναζήτηση τμήματος...',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: controller.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    controller.clear();
                                    setDlgState(() {
                                      selectedDeptId = null;
                                      selectedDeptName = null;
                                    });
                                  },
                                )
                              : null,
                        ),
                        onChanged: (_) {
                          setDlgState(() {
                            selectedDeptId = null;
                            selectedDeptName = null;
                          });
                        },
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220, maxWidth: 380),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, i) {
                                final opt = options.elementAt(i);
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.business, size: 18, color: Color(0xFF7C3AED)),
                                  title: Text(opt['name']?.toString() ?? '', style: const TextStyle(fontSize: 14)),
                                  onTap: () => onSelected(opt),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedDeptRole,
                    decoration: const InputDecoration(labelText: 'Ρόλος στο τμήμα', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'volunteer', child: Text('Εθελοντής')),
                      DropdownMenuItem(value: 'missionAdmin', child: Text('Διαχειριστής Αποστολών')),
                      DropdownMenuItem(value: 'itemAdmin', child: Text('Διαχειριστής Υλικού')),
                    ],
                    onChanged: (v) => setDlgState(() => selectedDeptRole = v ?? 'volunteer'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: selectedSpecId,
                    decoration: const InputDecoration(labelText: 'Ειδίκευση πρώτης ανάθεσης *', border: OutlineInputBorder()),
                    items: rootSpecs.map((s) => DropdownMenuItem<int?>(
                      value: s['id'] as int,
                      child: Text(s['name']?.toString() ?? ''),
                    )).toList(),
                    onChanged: (v) => setDlgState(() => selectedSpecId = v),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Η αρχική ειδίκευση μπορεί να είναι μόνο ριζική. Αν το EAME μείνει κενό, δημιουργείται αυτόματα από αυτήν.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
            FilledButton(
              onPressed: () async {
                if (selectedDeptId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Επιλέξτε τμήμα πρώτης ανάθεσης.')),
                  );
                  return;
                }
                if (selectedSpecId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Επιλέξτε ειδίκευση πρώτης ανάθεσης.')),
                  );
                  return;
                }

                final body = <String, dynamic>{
                  'forename': forenameCtrl.text.trim(),
                  'surname': surnameCtrl.text.trim(),
                  'email': emailCtrl.text.trim(),
                  'rank': selectedRank,
                  'departmentId': selectedDeptId,
                  'specializationId': selectedSpecId,
                  'departmentRole': selectedDeptRole,
                };
                final eame = eameCtrl.text.trim();
                if (eame.isNotEmpty) {
                  body['eame'] = eame;
                }

                try {
                  final res = await _api.post('/users', body: body);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (res.statusCode == 201) {
                    _fetch();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ο χρήστης δημιουργήθηκε και έλαβε email πρόσκλησης.')),
                      );
                    }
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final tt = Theme.of(context).textTheme;
    final processed = _processed;
    final totalPages = (processed.length / _rowsPerPage).ceil();
    final pageStart = _page * _rowsPerPage;
    final pageEnd = (pageStart + _rowsPerPage).clamp(0, processed.length);
    final pageUsers = processed.sublist(pageStart, pageEnd);

    return Scaffold(
      appBar: AppBar(
        title: Text('Διαχείριση Χρηστών', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetch, tooltip: 'Ανανέωση'),
        ],
      ),
      floatingActionButton: auth.isAdmin && !_selectionMode
          ? FloatingActionButton.extended(
              onPressed: _showCreateDialog,
              icon: const Icon(Icons.person_add),
              label: const Text('Νέος Χρήστης'),
            )
          : null,
      body: Stack(
        children: [
          SafeArea(
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
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _chip('Όλοι (${_users.length})', null),
                      const SizedBox(width: 6),
                      ..._allSpecs.map((s) {
                        final specId = s['id'] as int;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _chip(
                            '${s['name']} (${_countSpec(specId)})',
                            specId,
                            color: const Color(0xFF7C3AED),
                          ),
                        );
                      }),
                    ],
                  ),
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
                            Icon(Icons.person_off, size: 64, color: Color(0xFFD1D5DB)),
                            const SizedBox(height: 12),
                            Text('Δεν βρέθηκαν χρήστες', style: tt.bodyLarge?.copyWith(color: Color(0xFF6B7280))),
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
                              if (_selectionMode)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Checkbox(
                                    value: pageUsers.isNotEmpty &&
                                        pageUsers.every((u) =>
                                            _selectedIds.contains(u['id'] as int)),
                                    tristate: false,
                                    onChanged: (_) => _toggleSelectAll(pageUsers),
                                    visualDensity: VisualDensity.compact,
                                    activeColor: const Color(0xFF7C3AED),
                                  ),
                                )
                              else
                                const SizedBox(width: 8),
                              _headerCell('Name', 'name', flex: 3),
                              _headerCell('Phone', 'phone', flex: 2),
                              _headerCell('Email', 'email', flex: 2),
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
          _buildBulkBar(),
        ],
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
    final userId = user['id'] as int;
    final isSelected = _selectedIds.contains(userId);

    return GestureDetector(
      onLongPress: () => _enterSelectionMode(userId),
      child: InkWell(
        onTap: () {
          if (_selectionMode) {
            _toggleSelect(userId);
          } else {
            context.push('/admin/users/$userId').then((_) {
              if (mounted) _fetch();
            });
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: isSelected
              ? const Color(0xFFEEF2FF)
              : even
                  ? Colors.white
                  : const Color(0xFFF9FAFB),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: _selectionMode
                  ? Checkbox(
                      key: ValueKey(userId),
                      value: isSelected,
                      onChanged: (_) => _toggleSelect(userId),
                      visualDensity: VisualDensity.compact,
                      activeColor: const Color(0xFF7C3AED),
                    )
                  : CircleAvatar(
                      key: ValueKey('avatar_$userId'),
                      radius: 15,
                      backgroundColor: isAdmin
                          ? Color(0xFFFEF3C7)
                          : const Color(0xFFFEE2E2),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'U',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isAdmin
                                ? Color(0xFFD97706)
                                : const Color(0xFFDC2626)),
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(name.isNotEmpty ? name : user['eame'] ?? '',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                            color: Colors.amber.withAlpha(30),
                            borderRadius: BorderRadius.circular(3)),
                        child: Text('A',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFD97706))),
                      ),
                    ],
                  ]),
                  Text(user['eame'] ?? '',
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF9CA3AF)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            _editFieldCell(user, 'phonePrimary', 'Τηλέφωνο', flex: 2),
            _editFieldCell(user, 'email', 'Email', flex: 2),
            _hoursCell(user['totalHours']),
            _hoursCell(user['yearHours']),
            _hoursCell(user['yearVolHours']),
            _hoursCell(user['yearTrainingHours']),
            _hoursCell(user['yearTrainerHours']),
            _selectionMode
                ? const SizedBox(width: 16)
                : const Icon(Icons.chevron_right,
                    size: 16, color: Color(0xFFD1D5DB)),
          ]),
        ),
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

  Widget _editFieldCell(Map<String, dynamic> user, String field, String label, {int flex = 1}) {
    final value = (user[field] ?? '').toString();
    final userId = user['id'] as int;
    final canEdit = !_selectionMode;
    final isPhone = field == 'phonePrimary';

    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: canEdit ? () => _showEditFieldDialog(userId, field, label, value) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isPhone && canEdit && value.isNotEmpty)
                GestureDetector(
                  onTap: () => launchUrl(Uri(scheme: 'tel', path: value)),
                  child: const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.call, size: 12, color: Color(0xFF7C3AED)),
                  ),
                ),
              Flexible(
                child: Text(
                  value.isNotEmpty ? value : '—',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: value.isNotEmpty ? FontWeight.w500 : FontWeight.w400,
                    color: value.isNotEmpty ? const Color(0xFF111827) : const Color(0xFFD1D5DB),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (canEdit)
                GestureDetector(
                  onTap: () => _showEditFieldDialog(userId, field, label, value),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: Icon(Icons.edit, size: 12, color: Color(0xFF9CA3AF)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditFieldDialog(int userId, String field, String label, String currentValue) async {
    final ctrl = TextEditingController(text: currentValue);
    final isEmail = field == 'email';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Επεξεργασία $label'),
        content: TextField(
          controller: ctrl,
          keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.phone,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Αποθήκευση'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final newValue = ctrl.text.trim();
    if (newValue == currentValue) return;

    try {
      final res = await _api.patch('/users/$userId', body: {field: newValue});
      if (res.statusCode == 200) {
        _fetch();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Το $label ενημερώθηκε')),
          );
        }
      } else {
        final err = jsonDecode(res.body)['error'] ?? 'Αποτυχία';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Σφάλμα: $e')),
        );
      }
    }
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

  Widget _chip(String label, int? key, {Color? color}) {
    final selected = _specFilter == key;
    final c = color ?? Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () => setState(() { _specFilter = key; _page = 0; }),
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

  Widget _buildBulkBar() {
    return AnimatedSlide(
      offset: _selectionMode ? Offset.zero : const Offset(0, 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: _selectionMode ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1B4B),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withAlpha(60),
                    blurRadius: 16,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                onPressed: _exitSelectionMode,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              const SizedBox(width: 6),
              Text(
                '${_selectedIds.length} επιλεγμένοι',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
              const Spacer(),
              _BulkAction(
                icon: Icons.school_outlined,
                label: 'Ειδίκευση',
                onTap: _showSpecializationDialog,
              ),
              _BulkAction(
                icon: Icons.assignment_outlined,
                label: 'Υπηρεσία',
                onTap: _showServiceDialog,
              ),
              if (_deptFilter != null)
                _BulkAction(
                  icon: Icons.manage_accounts_outlined,
                  label: 'Ρόλος',
                  onTap: _showRoleDialog,
                ),
              _BulkAction(
                icon: Icons.delete_outline,
                label: 'Διαγραφή',
                color: const Color(0xFFEF4444),
                onTap: _showDeleteDialog,
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _showSpecializationDialog() async {
    int? selectedSpecId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('Ανάθεση ειδίκευσης σε ${_selectedIds.length} χρήστες'),
          content: SizedBox(
            width: 320,
            child: DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                  labelText: 'Ειδίκευση', border: OutlineInputBorder()),
              items: _allSpecs
                  .map((s) => DropdownMenuItem<int>(
                        value: s['id'] as int,
                        child: Text(s['name']?.toString() ?? ''),
                      ))
                  .toList(),
              onChanged: (v) => setDlg(() => selectedSpecId = v),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Άκυρο')),
            FilledButton(
                onPressed: selectedSpecId != null
                    ? () => Navigator.pop(ctx, true)
                    : null,
                child: const Text('Ανάθεση')),
          ],
        ),
      ),
    );
    if (confirmed != true || selectedSpecId == null || !mounted) return;

    int ok = 0;
    int fail = 0;
    await Future.wait(_selectedIds.map((uid) async {
      try {
        final res = await _api.post('/users/$uid/specializations',
            body: {'specializationId': selectedSpecId});
        res.statusCode == 201 ? ok++ : fail++;
      } catch (_) {
        fail++;
      }
    }));
    if (!mounted) return;
    _exitSelectionMode();
    _fetch();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(fail == 0
          ? '$ok χρήστες ενημερώθηκαν'
          : '$ok ενημερώθηκαν, $fail αποτυχίες'),
    ));
  }

  Future<void> _showServiceDialog() async {
    if (_deptFilter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Επιλέξτε τμήμα για να αναθέσετε χρήστες σε υπηρεσία')),
      );
      return;
    }

    List<dynamic> services = [];
    try {
      final res = await _api
          .get('/services?departmentId=$_deptFilter&includeEnrollments=false');
      if (res.statusCode == 200) services = jsonDecode(res.body);
    } catch (_) {}

    final now = DateTime.now();
    final active = services.where((s) {
      final end = DateTime.tryParse(s['endAt'] ?? '');
      return end == null || end.isAfter(now);
    }).toList();

    if (!mounted) return;
    if (active.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Δεν υπάρχουν ενεργές υπηρεσίες')),
      );
      return;
    }

    int? selectedServiceId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('Ανάθεση ${_selectedIds.length} χρηστών σε υπηρεσία'),
          content: SizedBox(
            width: 360,
            child: DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                  labelText: 'Υπηρεσία', border: OutlineInputBorder()),
              isExpanded: true,
              items: active
                  .map((s) => DropdownMenuItem<int>(
                        value: s['id'] as int,
                        child: Text(s['name']?.toString() ?? '',
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setDlg(() => selectedServiceId = v),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Άκυρο')),
            FilledButton(
                onPressed: selectedServiceId != null
                    ? () => Navigator.pop(ctx, true)
                    : null,
                child: const Text('Ανάθεση')),
          ],
        ),
      ),
    );
    if (confirmed != true || selectedServiceId == null || !mounted) return;

    int ok = 0;
    int fail = 0;
    final sp = context.read<ServiceProvider>();
    await Future.wait(_selectedIds.map((uid) async {
      final err = await sp.enrollUser(selectedServiceId!, uid, status: 'accepted');
      if (err == null) {
        ok++;
      } else if (err.contains('Ήδη εγγεγραμμένος')) {
        ok++; // Already enrolled counts as success in bulk
      } else {
        fail++;
      }
    }));
    if (!mounted) return;
    _exitSelectionMode();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(fail == 0
          ? '$ok χρήστες εγγράφηκαν'
          : '$ok εγγράφηκαν, $fail αποτυχίες'),
    ));
  }

  Future<void> _showRoleDialog() async {
    if (_deptFilter == null) return;
    String selectedRole = 'volunteer';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('Αλλαγή ρόλου για ${_selectedIds.length} χρήστες'),
          content: SizedBox(
            width: 320,
            child: DropdownButtonFormField<String>(
              value: selectedRole,
              decoration: const InputDecoration(
                  labelText: 'Ρόλος', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(
                    value: 'volunteer', child: Text('Εθελοντής')),
                DropdownMenuItem(
                    value: 'missionAdmin', child: Text('Δ. Αποστολών')),
                DropdownMenuItem(
                    value: 'itemAdmin', child: Text('Δ. Υλικού')),
              ],
              onChanged: (v) =>
                  setDlg(() => selectedRole = v ?? 'volunteer'),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Άκυρο')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Εφαρμογή')),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    int ok = 0;
    int fail = 0;
    await Future.wait(_selectedIds.map((uid) async {
      try {
        final res = await _api.patch(
            '/departments/$_deptFilter/members/$uid',
            body: {'role': selectedRole});
        res.statusCode == 200 ? ok++ : fail++;
      } catch (_) {
        fail++;
      }
    }));
    if (!mounted) return;
    _exitSelectionMode();
    _fetch();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(fail == 0
          ? '$ok χρήστες ενημερώθηκαν'
          : '$ok ενημερώθηκαν, $fail αποτυχίες'),
    ));
  }

  Future<void> _showDeleteDialog() async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή Χρηστών'),
        content: Text(
            'Διαγραφή $count χρηστών; Αυτή η ενέργεια δεν μπορεί να αναιρεθεί.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Color(0xFFDC2626)),
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    int ok = 0;
    int fail = 0;
    await Future.wait(_selectedIds.map((uid) async {
      try {
        final res = await _api.delete('/users/$uid');
        res.statusCode == 204 ? ok++ : fail++;
      } catch (_) {
        fail++;
      }
    }));
    if (!mounted) return;
    _exitSelectionMode();
    _fetch();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(fail == 0
          ? '$ok χρήστες διαγράφηκαν'
          : '$ok διαγράφηκαν, $fail αποτυχίες'),
    ));
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

class _BulkAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _BulkAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
