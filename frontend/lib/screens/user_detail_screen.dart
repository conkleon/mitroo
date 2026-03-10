import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';

/// Full detail view for a single user. Admins can edit profile, toggle admin,
/// manage department memberships, and manage specializations.
class UserDetailScreen extends StatefulWidget {
  final int userId;
  const UserDetailScreen({super.key, required this.userId});

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  final _api = ApiClient();
  Map<String, dynamic>? _user;
  List<dynamic> _allDepts = [];
  List<dynamic> _allSpecs = [];
  List<Map<String, dynamic>> _services = [];
  bool _loading = true;

  // Services table state
  String _svcSearch = '';
  String _svcStatusFilter = 'all'; // all, accepted, requested, rejected
  String _svcSortField = 'date'; // date, name, totalHours, hours, hoursVol, hoursTraining, hoursTrainers
  bool _svcSortAsc = false;
  int _svcPage = 0;
  int _svcRowsPerPage = 10;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.get('/users/${widget.userId}'),
        _api.get('/departments'),
        _api.get('/specializations'),
        _api.get('/users/${widget.userId}/services'),
      ]);
      if (results[0].statusCode == 200) _user = jsonDecode(results[0].body);
      if (results[1].statusCode == 200) _allDepts = jsonDecode(results[1].body);
      if (results[2].statusCode == 200) _allSpecs = jsonDecode(results[2].body);
      if (results[3].statusCode == 200) {
        _services = (jsonDecode(results[3].body) as List).cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // ── Edit profile ──────────────────────────────────
  void _editProfile() {
    if (_user == null) return;
    final forenameCtrl = TextEditingController(text: _user!['forename'] ?? '');
    final surnameCtrl = TextEditingController(text: _user!['surname'] ?? '');
    final emailCtrl = TextEditingController(text: _user!['email'] ?? '');
    final phoneCtrl = TextEditingController(text: _user!['phonePrimary'] ?? '');
    final addressCtrl = TextEditingController(text: _user!['address'] ?? '');
    bool isAdmin = _user!['isAdmin'] == true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Επεξεργασία Προφίλ'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: forenameCtrl, decoration: const InputDecoration(labelText: 'Όνομα', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: surnameCtrl, decoration: const InputDecoration(labelText: 'Επώνυμο', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Τηλέφωνο', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Διεύθυνση', border: OutlineInputBorder()), maxLines: 2),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Διαχειριστής Συστήματος'),
                    value: isAdmin,
                    onChanged: (v) => setDlgState(() => isAdmin = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
            FilledButton(
              onPressed: () async {
                final body = <String, dynamic>{
                  'forename': forenameCtrl.text.trim(),
                  'surname': surnameCtrl.text.trim(),
                  'email': emailCtrl.text.trim(),
                  'isAdmin': isAdmin,
                };
                if (phoneCtrl.text.trim().isNotEmpty) body['phonePrimary'] = phoneCtrl.text.trim();
                if (addressCtrl.text.trim().isNotEmpty) body['address'] = addressCtrl.text.trim();
                try {
                  final res = await _api.patch('/users/${widget.userId}', body: body);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (res.statusCode == 200) {
                    _load();
                  } else {
                    final err = jsonDecode(res.body)['error'] ?? 'Αποτυχία';
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  }
                } catch (e) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Σφάλμα: $e')));
                }
              },
              child: const Text('Αποθήκευση'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Delete user ───────────────────────────────────
  void _deleteUser() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή Χρήστη'),
        content: Text('Οριστική διαγραφή "${_user?['forename']} ${_user?['surname']}";\nΔεν μπορεί να αναιρεθεί.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final res = await _api.delete('/users/${widget.userId}');
      if (!mounted) return;
      if (res.statusCode == 204) {
        context.pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Αποτυχία διαγραφής χρήστη')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Σφάλμα: $e')));
    }
  }

  // ── Manage department membership ─────────────────
  void _addToDepartment() {
    final userDepts = (_user?['departments'] as List<dynamic>? ?? [])
        .map((d) => d['departmentId'] ?? d['department']?['id'])
        .toSet();
    final available = _allDepts.where((d) => !userDepts.contains(d['id'])).toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ο χρήστης είναι ήδη σε όλα τα τμήματα')));
      return;
    }

    int? selectedDeptId;
    String? selectedDeptName;
    String selectedRole = 'volunteer';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Προσθήκη σε Τμήμα'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Autocomplete<Map<String, dynamic>>(
                  displayStringForOption: (d) => d['name'] ?? '',
                  optionsBuilder: (textEditingValue) {
                    final q = textEditingValue.text.toLowerCase();
                    if (q.isEmpty) return available.cast<Map<String, dynamic>>();
                    return available.cast<Map<String, dynamic>>().where(
                        (d) => (d['name'] ?? '').toString().toLowerCase().contains(q));
                  },
                  onSelected: (d) {
                    setDlgState(() {
                      selectedDeptId = d['id'] as int;
                      selectedDeptName = d['name'] as String?;
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
                        labelText: 'Τμήμα',
                        hintText: 'Πληκτρολογήστε...',
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
                          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 340),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (context, i) {
                              final opt = options.elementAt(i);
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.business, size: 18, color: Color(0xFF7C3AED)),
                                title: Text(opt['name'] ?? '', style: const TextStyle(fontSize: 14)),
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
                  decoration: const InputDecoration(labelText: 'Ρόλος', border: OutlineInputBorder()),
                  value: selectedRole,
                  items: const [
                    DropdownMenuItem(value: 'volunteer', child: Text('Εθελοντής')),
                    DropdownMenuItem(value: 'missionAdmin', child: Text('Διαχ. Αποστολών')),
                    DropdownMenuItem(value: 'itemAdmin', child: Text('Διαχ. Υλικού')),
                  ],
                  onChanged: (v) => setDlgState(() => selectedRole = v ?? 'volunteer'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
            FilledButton(
              onPressed: selectedDeptId == null
                  ? null
                  : () async {
                      try {
                        final res = await _api.post(
                          '/departments/$selectedDeptId/members',
                          body: {'userId': widget.userId, 'role': selectedRole},
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (res.statusCode == 201) {
                          _load();
                        } else {
                          final err = jsonDecode(res.body)['error'] ?? 'Αποτυχία';
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                        }
                      } catch (e) {
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Σφάλμα: $e')));
                      }
                    },
              child: const Text('Προσθήκη'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeDeptMembership(int deptId) async {
    try {
      final res = await _api.delete('/departments/$deptId/members/${widget.userId}');
      if (res.statusCode == 204) _load();
    } catch (_) {}
  }

  Future<void> _changeDeptRole(int deptId, String newRole) async {
    try {
      final res = await _api.patch('/departments/$deptId/members/${widget.userId}', body: {'role': newRole});
      if (res.statusCode == 200) _load();
    } catch (_) {}
  }

  // ── Manage specializations ───────────────────────
  void _addSpecialization() {
    final userSpecIds = (_user?['specializations'] as List<dynamic>? ?? [])
        .map((us) => (us['specialization']?['id'] ?? us['specializationId']) as int)
        .toSet();
    final available = _allSpecs.where((s) => !userSpecIds.contains(s['id'])).toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Όλες οι ειδικεύσεις έχουν ανατεθεί')));
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Προσθήκη Ειδίκευσης'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Πατήστε μια ειδίκευση:', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: available.map((s) {
                  return ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: Text(s['name'] ?? '', style: const TextStyle(fontSize: 13)),
                    onPressed: () async {
                      try {
                        final res = await _api.post('/users/${widget.userId}/specializations', body: {'specializationId': s['id']});
                        if (res.statusCode == 201) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          _load();
                        }
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Σφάλμα: $e')));
                      }
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Κλείσιμο')),
        ],
      ),
    );
  }

  Future<void> _removeSpecialization(int specId) async {
    try {
      final res = await _api.delete('/users/${widget.userId}/specializations/$specId');
      if (res.statusCode == 204) _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Λεπτομέρειες Χρήστη'), backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Λεπτομέρειες Χρήστη'), backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(child: Text('Χρήστης δεν βρέθηκε')),
      );
    }

    final u = _user!;
    final name = '${u['forename'] ?? ''} ${u['surname'] ?? ''}'.trim();
    final isAdmin = u['isAdmin'] == true;
    final departments = u['departments'] as List<dynamic>? ?? [];
    final specializations = u['specializations'] as List<dynamic>? ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(name.isNotEmpty ? name : u['ename'] ?? 'User',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.edit), onPressed: _editProfile, tooltip: 'Επεξεργασία'),
          IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: _deleteUser, tooltip: 'Διαγραφή'),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;

            final profileCard = _buildProfileCard(u, name, isAdmin, tt, cs);
            final deptsCard = _buildDepartmentsCard(departments, tt, cs);
            final specsCard = _buildSpecializationsCard(specializations, tt, cs);
            final servicesCard = _buildServicesCard(tt, cs);

            if (isWide) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 380, child: profileCard),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(children: [deptsCard, const SizedBox(height: 16), specsCard]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        servicesCard,
                      ],
                    ),
                  ),
                ),
              );
            }

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Column(children: [
                profileCard, const SizedBox(height: 16),
                deptsCard, const SizedBox(height: 16),
                specsCard, const SizedBox(height: 16),
                servicesCard,
              ]),
            );
          },
        ),
      ),
    );
  }

  // ── Profile card ──────────────────────────────────
  Widget _buildProfileCard(Map<String, dynamic> u, String name, bool isAdmin, TextTheme tt, ColorScheme cs) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: isAdmin ? Colors.amber.shade100 : const Color(0xFFDBEAFE),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'U',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: isAdmin ? Colors.amber.shade800 : const Color(0xFF2563EB)),
              ),
            ),
            const SizedBox(height: 16),
            Text(name.isNotEmpty ? name : u['ename'] ?? '', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('@${u['ename'] ?? ''}', style: tt.bodyMedium?.copyWith(color: const Color(0xFF6B7280))),
            if (isAdmin) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: Colors.amber.withAlpha(25), borderRadius: BorderRadius.circular(8)),
                child: Text('Διαχειριστής Συστήματος', style: tt.labelMedium?.copyWith(color: Colors.amber.shade800, fontWeight: FontWeight.w600)),
              ),
            ],
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            _InfoRow(icon: Icons.email, label: 'Email', value: u['email'] ?? '—'),
            _InfoRow(icon: Icons.phone, label: 'Τηλέφωνο', value: u['phonePrimary'] ?? '—'),
            _InfoRow(icon: Icons.location_on, label: 'Διεύθυνση', value: u['address'] ?? '—'),
            _InfoRow(icon: Icons.calendar_today, label: 'Ημ. Γέννησης', value: _formatDate(u['birthDate'])),
            if ((u['extraInfo'] ?? '').toString().isNotEmpty)
              _InfoRow(icon: Icons.info_outline, label: 'Επιπλέον Πληρ.', value: u['extraInfo']),
          ],
        ),
      ),
    );
  }

  String _formatDate(dynamic val) {
    if (val == null) return '—';
    final dt = DateTime.tryParse(val.toString());
    if (dt == null) return '—';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  // ── Departments card ──────────────────────────────
  Widget _buildDepartmentsCard(List<dynamic> departments, TextTheme tt, ColorScheme cs) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.business, color: cs.primary, size: 22),
                const SizedBox(width: 10),
                Text('Τμήματα', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addToDepartment,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Προσθήκη'),
                ),
              ],
            ),
            const Divider(),
            if (departments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('Χωρίς τμήματα', style: TextStyle(color: Color(0xFF9CA3AF)))),
              )
            else
              ...departments.map((ud) {
                final dept = ud['department'] as Map<String, dynamic>?;
                final deptName = dept?['name'] ?? 'Unknown';
                final deptId = (ud['departmentId'] ?? dept?['id']) as int;
                final role = ud['role'] as String? ?? 'volunteer';

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFEDE9FE), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.business, color: Color(0xFF7C3AED), size: 20),
                  ),
                  title: Text(deptName, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  subtitle: Text(_roleLabelFull(role), style: tt.bodySmall?.copyWith(color: _roleColor(role))),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (action) {
                      if (action == 'remove') {
                        _removeDeptMembership(deptId);
                      } else {
                        _changeDeptRole(deptId, action);
                      }
                    },
                    itemBuilder: (_) => [
                      if (role != 'volunteer')
                        const PopupMenuItem(value: 'volunteer', child: Text('Ορισμός Εθελοντή')),
                      if (role != 'missionAdmin')
                        const PopupMenuItem(value: 'missionAdmin', child: Text('Ορισμός Διαχ. Αποστολών')),
                      if (role != 'itemAdmin')
                        const PopupMenuItem(value: 'itemAdmin', child: Text('Ορισμός Διαχ. Υλικού')),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'remove', child: Text('Αφαίρεση', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ── Specializations card ──────────────────────────
  Widget _buildSpecializationsCard(List<dynamic> specializations, TextTheme tt, ColorScheme cs) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.school, color: Color(0xFFD97706), size: 22),
                const SizedBox(width: 10),
                Text('Ειδικεύσεις', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addSpecialization,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Προσθήκη'),
                ),
              ],
            ),
            const Divider(),
            if (specializations.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('Χωρίς ειδικεύσεις', style: TextStyle(color: Color(0xFF9CA3AF)))),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: specializations.map((us) {
                  final spec = us['specialization'] as Map<String, dynamic>?;
                  final specName = spec?['name'] ?? 'Unknown';
                  final specId = (spec?['id'] ?? us['specializationId']) as int;
                  return Chip(
                    avatar: const Icon(Icons.school, size: 16, color: Color(0xFFD97706)),
                    label: Text(specName),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => _removeSpecialization(specId),
                    backgroundColor: const Color(0xFFFEF3C7),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  // ── Services / Missions card ──────────────────
  List<Map<String, dynamic>> get _processedServices {
    var list = List<Map<String, dynamic>>.from(_services);

    // Status filter
    if (_svcStatusFilter != 'all') {
      list = list.where((s) => s['status'] == _svcStatusFilter).toList();
    }

    // Search
    if (_svcSearch.isNotEmpty) {
      final q = _svcSearch.toLowerCase();
      list = list.where((s) {
        final svc = s['service'] as Map<String, dynamic>? ?? {};
        final name = (svc['name'] ?? '').toString().toLowerCase();
        final loc = (svc['location'] ?? '').toString().toLowerCase();
        final dept = (svc['department']?['name'] ?? '').toString().toLowerCase();
        return name.contains(q) || loc.contains(q) || dept.contains(q);
      }).toList();
    }

    // Sort
    list.sort((a, b) {
      int cmp;
      switch (_svcSortField) {
        case 'name':
          final na = (a['service']?['name'] ?? '').toString().toLowerCase();
          final nb = (b['service']?['name'] ?? '').toString().toLowerCase();
          cmp = na.compareTo(nb);
          break;
        case 'totalHours':
          cmp = ((a['totalHours'] ?? 0) as int).compareTo((b['totalHours'] ?? 0) as int);
          break;
        case 'hours':
          cmp = ((a['hours'] ?? 0) as int).compareTo((b['hours'] ?? 0) as int);
          break;
        case 'hoursVol':
          cmp = ((a['hoursVol'] ?? 0) as int).compareTo((b['hoursVol'] ?? 0) as int);
          break;
        case 'hoursTraining':
          cmp = ((a['hoursTraining'] ?? 0) as int).compareTo((b['hoursTraining'] ?? 0) as int);
          break;
        case 'hoursTrainers':
          cmp = ((a['hoursTrainers'] ?? 0) as int).compareTo((b['hoursTrainers'] ?? 0) as int);
          break;
        default: // date
          final da = a['service']?['startAt'] ?? '';
          final db = b['service']?['startAt'] ?? '';
          cmp = da.toString().compareTo(db.toString());
      }
      return _svcSortAsc ? cmp : -cmp;
    });

    return list;
  }

  void _setSvcSort(String field) {
    setState(() {
      if (_svcSortField == field) {
        _svcSortAsc = !_svcSortAsc;
      } else {
        _svcSortField = field;
        _svcSortAsc = field == 'name' || field == 'date';
      }
      _svcPage = 0;
    });
  }

  Widget _buildServicesCard(TextTheme tt, ColorScheme cs) {
    final processed = _processedServices;
    final totalPages = processed.isEmpty ? 1 : (processed.length / _svcRowsPerPage).ceil();
    final pageStart = _svcPage * _svcRowsPerPage;
    final pageEnd = (pageStart + _svcRowsPerPage).clamp(0, processed.length);
    final pageItems = processed.sublist(pageStart, pageEnd);

    // Sum hours for summary
    int sumTotal = 0, sumH = 0, sumVol = 0, sumTrain = 0, sumTrainer = 0;
    for (final s in _services.where((s) => s['status'] == 'accepted')) {
      sumTotal += (s['totalHours'] ?? 0) as int;
      sumH += (s['hours'] ?? 0) as int;
      sumVol += (s['hoursVol'] ?? 0) as int;
      sumTrain += (s['hoursTraining'] ?? 0) as int;
      sumTrainer += (s['hoursTrainers'] ?? 0) as int;
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              Icon(Icons.work_history, color: cs.primary, size: 22),
              const SizedBox(width: 10),
              Text('Υπηρεσίες / Αποστολές', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${_services.length} total',
                  style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
            ]),
            const SizedBox(height: 8),

            // Summary chips
            Wrap(spacing: 8, runSpacing: 6, children: [
              _hoursSummaryChip('Total', sumTotal, const Color(0xFF2563EB)),
              _hoursSummaryChip('Hours', sumH, const Color(0xFF059669)),
              _hoursSummaryChip('Vol', sumVol, const Color(0xFF7C3AED)),
              _hoursSummaryChip('Training', sumTrain, const Color(0xFFD97706)),
              _hoursSummaryChip('Trainer', sumTrainer, const Color(0xFFDC2626)),
            ]),
            const SizedBox(height: 12),

            // Filters row
            Row(children: [
              // Status filter
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _svcStatusFilter,
                    isDense: true,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Όλες οι καταστάσεις')),
                      DropdownMenuItem(value: 'accepted', child: Text('Εγκεκριμένη')),
                      DropdownMenuItem(value: 'requested', child: Text('Εκκρεμής')),
                      DropdownMenuItem(value: 'rejected', child: Text('Απορριφθείσα')),
                    ],
                    onChanged: (v) => setState(() { _svcStatusFilter = v ?? 'all'; _svcPage = 0; }),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Αναζήτηση υπηρεσιών...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (v) => setState(() { _svcSearch = v; _svcPage = 0; }),
                ),
              ),
            ]),
            const SizedBox(height: 8),

            // Pagination
            Row(children: [
              Text('${processed.length} shown',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
              const Spacer(),
              const Text('Γραμμές: ', style: TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _svcRowsPerPage,
                    isDense: true,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF374151)),
                    items: const [
                      DropdownMenuItem(value: 5, child: Text('5')),
                      DropdownMenuItem(value: 10, child: Text('10')),
                      DropdownMenuItem(value: 25, child: Text('25')),
                      DropdownMenuItem(value: 50, child: Text('50')),
                    ],
                    onChanged: (v) => setState(() { _svcRowsPerPage = v ?? 10; _svcPage = 0; }),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 18),
                onPressed: _svcPage > 0 ? () => setState(() => _svcPage--) : null,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              Text('${_svcPage + 1}/${totalPages.clamp(1, 999)}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 18),
                onPressed: _svcPage < totalPages - 1 ? () => setState(() => _svcPage++) : null,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
            const SizedBox(height: 4),

            // Table header
            Container(
              color: const Color(0xFFEEF0F4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(children: [
                _svcHeaderCell('Service', 'name', flex: 3),
                _svcHeaderCell('Date', 'date', flex: 2),
                _svcHeaderCell('Status', 'status'),
                _svcHeaderCell('Total', 'totalHours'),
                _svcHeaderCell('Hrs', 'hours'),
                _svcHeaderCell('Vol', 'hoursVol'),
                _svcHeaderCell('Train', 'hoursTraining'),
                _svcHeaderCell('Trnr', 'hoursTrainers'),
              ]),
            ),

            // Rows
            if (pageItems.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Δεν βρέθηκαν υπηρεσίες', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13))),
              )
            else
              ...pageItems.asMap().entries.map((e) => _buildSvcRow(e.value, e.key.isEven)),
          ],
        ),
      ),
    );
  }

  Widget _svcHeaderCell(String label, String field, {int flex = 1}) {
    final isActive = _svcSortField == field;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => _setSvcSort(field),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                    color: isActive ? const Color(0xFF2563EB) : const Color(0xFF374151))),
            if (isActive)
              Icon(_svcSortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 10, color: const Color(0xFF2563EB)),
          ],
        ),
      ),
    );
  }

  Widget _buildSvcRow(Map<String, dynamic> enrolment, bool even) {
    final svc = enrolment['service'] as Map<String, dynamic>? ?? {};
    final name = svc['name'] ?? 'Unknown';
    final dept = svc['department']?['name'] ?? '';
    final status = enrolment['status'] as String? ?? '';
    final startAt = DateTime.tryParse(svc['startAt']?.toString() ?? '');
    final endAt = DateTime.tryParse(svc['endAt']?.toString() ?? '');

    String dateStr = '—';
    if (startAt != null) {
      dateStr = '${startAt.day}/${startAt.month}/${startAt.year}';
      if (endAt != null && endAt != startAt) {
        dateStr += ' - ${endAt.day}/${endAt.month}/${endAt.year}';
      }
    }

    Color statusColor;
    switch (status) {
      case 'accepted': statusColor = const Color(0xFF059669); break;
      case 'rejected': statusColor = Colors.red; break;
      default: statusColor = Colors.amber.shade700;
    }

    return Container(
      color: even ? Colors.white : const Color(0xFFF9FAFB),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(children: [
        // Name + department
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (dept.isNotEmpty)
                Text(dept, style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        // Date
        Expanded(
          flex: 2,
          child: Text(dateStr, style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
        ),
        // Status
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(20),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              status.isNotEmpty ? status[0].toUpperCase() + status.substring(1) : '',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: statusColor),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        // Hours cells
        _svcHoursCell(enrolment['totalHours'], bold: true),
        _svcHoursCell(enrolment['hours']),
        _svcHoursCell(enrolment['hoursVol']),
        _svcHoursCell(enrolment['hoursTraining']),
        _svcHoursCell(enrolment['hoursTrainers']),
      ]),
    );
  }

  Widget _svcHoursCell(dynamic val, {bool bold = false}) {
    final h = (val ?? 0) as int;
    return Expanded(
      child: Text(
        h > 0 ? '$h' : '—',
        style: TextStyle(
          fontSize: 11,
          fontWeight: h > 0 && bold ? FontWeight.w700 : (h > 0 ? FontWeight.w600 : FontWeight.w400),
          color: h > 0 ? const Color(0xFF111827) : const Color(0xFFD1D5DB),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _hoursSummaryChip(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$value', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, color: color.withAlpha(180))),
      ]),
    );
  }

  static String _roleLabelFull(String role) {
    switch (role) {
      case 'missionAdmin': return 'Διαχ. Αποστολών';
      case 'itemAdmin': return 'Διαχ. Υλικού';
      case 'volunteer': return 'Εθελοντής';
      default: return role;
    }
  }

  static Color _roleColor(String role) {
    switch (role) {
      case 'missionAdmin': return const Color(0xFF059669);
      case 'itemAdmin': return const Color(0xFF7C3AED);
      default: return const Color(0xFF2563EB);
    }
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF6B7280)),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Text(label, style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF374151))),
          ),
          Expanded(child: Text(value, style: tt.bodySmall?.copyWith(color: const Color(0xFF4B5563)))),
        ],
      ),
    );
  }
}
