import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';

/// Full detail view for a single department.
/// Shows info, members (with role management), recent services, vehicles.
class DepartmentDetailScreen extends StatefulWidget {
  final int departmentId;
  const DepartmentDetailScreen({super.key, required this.departmentId});

  @override
  State<DepartmentDetailScreen> createState() => _DepartmentDetailScreenState();
}

class _DepartmentDetailScreenState extends State<DepartmentDetailScreen> {
  final _api = ApiClient();
  Map<String, dynamic>? _dept;
  List<dynamic> _allUsers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.get('/departments/${widget.departmentId}'),
        _api.get('/users'),
      ]);
      if (results[0].statusCode == 200) {
        _dept = jsonDecode(results[0].body);
      }
      if (results[1].statusCode == 200) {
        _allUsers = jsonDecode(results[1].body);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // ── helpers ──
  List<dynamic> get _members =>
      (_dept?['userDepartments'] as List<dynamic>?) ?? [];
  List<dynamic> get _services =>
      (_dept?['services'] as List<dynamic>?) ?? [];
  List<dynamic> get _vehicles =>
      (_dept?['vehicles'] as List<dynamic>?) ?? [];

  // ── Edit department ─────────────────────────────
  void _editDepartment() {
    if (_dept == null) return;
    final nameCtrl = TextEditingController(text: _dept!['name'] ?? '');
    final descCtrl =
        TextEditingController(text: _dept!['description'] ?? '');
    final locCtrl = TextEditingController(text: _dept!['location'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Department'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Name', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder()),
                    maxLines: 2),
                const SizedBox(height: 12),
                TextField(
                    controller: locCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Location',
                        border: OutlineInputBorder())),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final body = <String, dynamic>{
                'name': nameCtrl.text.trim(),
              };
              if (descCtrl.text.isNotEmpty) {
                body['description'] = descCtrl.text.trim();
              }
              if (locCtrl.text.isNotEmpty) {
                body['location'] = locCtrl.text.trim();
              }
              await _api.patch('/departments/${widget.departmentId}',
                  body: body);
              if (ctx.mounted) Navigator.pop(ctx);
              _load();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ── Delete department ──────────────────────────────
  void _deleteDepartment() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Department'),
        content:
            const Text('Are you sure? All associations will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _api.delete('/departments/${widget.departmentId}');
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) context.pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ── Add Member ──────────────────────────────────
  void _addMember() {
    final currentIds = _members.map((m) {
      final u = m['user'] as Map<String, dynamic>?;
      return u?['id'] as int?;
    }).whereType<int>().toSet();

    final available =
        _allUsers.where((u) => !currentIds.contains(u['id'])).toList();

    int? selectedUser;
    String? selectedUserName;
    String selectedRole = 'volunteer';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return AlertDialog(
          title: const Text('Add Member'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Autocomplete<Map<String, dynamic>>(
                  displayStringForOption: (u) =>
                      '${u['forename'] ?? ''} ${u['surname'] ?? ''} (${u['ename'] ?? ''})'
                          .trim(),
                  optionsBuilder: (textEditingValue) {
                    final q = textEditingValue.text.toLowerCase();
                    final opts = available.cast<Map<String, dynamic>>();
                    if (q.isEmpty) return opts;
                    return opts.where((u) {
                      final name =
                          '${u['forename'] ?? ''} ${u['surname'] ?? ''}'
                              .toLowerCase();
                      final ename =
                          (u['ename'] ?? '').toString().toLowerCase();
                      return name.contains(q) || ename.contains(q);
                    });
                  },
                  onSelected: (u) {
                    setS(() {
                      selectedUser = u['id'] as int;
                      selectedUserName =
                          '${u['forename'] ?? ''} ${u['surname'] ?? ''} (${u['ename'] ?? ''})'
                              .trim();
                    });
                  },
                  fieldViewBuilder: (context, controller, focusNode,
                      onFieldSubmitted) {
                    if (selectedUserName != null &&
                        controller.text.isEmpty) {
                      controller.text = selectedUserName!;
                    }
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        labelText: 'User',
                        hintText: 'Type to search...',
                        border: const OutlineInputBorder(),
                        prefixIcon:
                            const Icon(Icons.search, size: 20),
                        suffixIcon: controller.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear,
                                    size: 18),
                                onPressed: () {
                                  controller.clear();
                                  setS(() {
                                    selectedUser = null;
                                    selectedUserName = null;
                                  });
                                },
                              )
                            : null,
                      ),
                      onChanged: (_) {
                        setS(() {
                          selectedUser = null;
                          selectedUserName = null;
                        });
                      },
                    );
                  },
                  optionsViewBuilder:
                      (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              maxHeight: 200, maxWidth: 370),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (context, i) {
                              final opt = options.elementAt(i);
                              final name =
                                  '${opt['forename'] ?? ''} ${opt['surname'] ?? ''}'
                                      .trim();
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.person,
                                    size: 18,
                                    color: Color(0xFF2563EB)),
                                title: Text(
                                    name.isNotEmpty
                                        ? name
                                        : opt['ename'] ?? '',
                                    style: const TextStyle(
                                        fontSize: 14)),
                                subtitle: Text(
                                    opt['ename'] ?? '',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF9CA3AF))),
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
                  value: selectedRole,
                  decoration: const InputDecoration(
                      labelText: 'Role', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(
                        value: 'volunteer', child: Text('Volunteer')),
                    DropdownMenuItem(
                        value: 'missionAdmin',
                        child: Text('Mission Admin')),
                    DropdownMenuItem(
                        value: 'itemAdmin', child: Text('Item Admin')),
                  ],
                  onChanged: (v) => setS(() => selectedRole = v ?? selectedRole),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: selectedUser == null
                  ? null
                  : () async {
                      await _api.post(
                          '/departments/${widget.departmentId}/members',
                          body: {
                            'userId': selectedUser,
                            'role': selectedRole,
                          });
                      if (ctx.mounted) Navigator.pop(ctx);
                      _load();
                    },
              child: const Text('Add'),
            ),
          ],
        );
      }),
    );
  }

  // ── Change member role ──
  Future<void> _changeRole(int userId, String newRole) async {
    await _api.patch(
        '/departments/${widget.departmentId}/members/$userId',
        body: {'role': newRole});
    _load();
  }

  // ── Remove member ──
  Future<void> _removeMember(int userId) async {
    await _api
        .delete('/departments/${widget.departmentId}/members/$userId');
    _load();
  }

  // ═══════════════════════════ BUILD ═══════════════════════════
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(_dept?['name'] ?? 'Department',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _editDepartment,
              tooltip: 'Edit'),
          IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _deleteDepartment,
              tooltip: 'Delete'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _dept == null
              ? const Center(child: Text('Department not found'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: LayoutBuilder(builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 900;
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.all(isWide ? 32 : 16),
                      child: isWide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _infoCard(tt)),
                                const SizedBox(width: 20),
                                Expanded(
                                    flex: 2,
                                    child: Column(
                                      children: [
                                        _membersCard(tt),
                                        const SizedBox(height: 16),
                                        _servicesCard(tt),
                                        const SizedBox(height: 16),
                                        _vehiclesCard(tt),
                                      ],
                                    )),
                              ],
                            )
                          : Column(children: [
                              _infoCard(tt),
                              const SizedBox(height: 16),
                              _membersCard(tt),
                              const SizedBox(height: 16),
                              _servicesCard(tt),
                              const SizedBox(height: 16),
                              _vehiclesCard(tt),
                            ]),
                    );
                  }),
                ),
    );
  }

  // ── Info Card ──
  Widget _infoCard(TextTheme tt) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE9FE),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.business,
                    size: 48, color: Color(0xFF7C3AED)),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(_dept!['name'] ?? '',
                  style:
                      tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center),
            ),
            if ((_dept!['description'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_dept!['description'],
                  style: tt.bodyMedium
                      ?.copyWith(color: const Color(0xFF6B7280))),
            ],
            const Divider(height: 24),
            _infoRow(Icons.location_on, 'Location',
                _dept!['location'] ?? '—'),
            _infoRow(
                Icons.people, 'Members', '${_members.length}'),
            _infoRow(Icons.miscellaneous_services, 'Services',
                '${_services.length}'),
            _infoRow(Icons.directions_car, 'Vehicles',
                '${_vehicles.length}'),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF6B7280)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF6B7280)))),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Members Card ──
  Widget _membersCard(TextTheme tt) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.people, color: Color(0xFF2563EB)),
              const SizedBox(width: 8),
              Text('Members (${_members.length})',
                  style:
                      tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              ActionChip(
                label: const Text('Add'),
                avatar: const Icon(Icons.add, size: 16),
                onPressed: _addMember,
              ),
            ]),
            const SizedBox(height: 12),
            if (_members.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                    child: Text('No members yet',
                        style: TextStyle(color: Color(0xFF9CA3AF)))),
              )
            else
              ..._members.map((m) {
                final user = m['user'] as Map<String, dynamic>? ?? {};
                final role = m['role']?.toString() ?? 'volunteer';
                final uid = user['id'] as int? ?? 0;
                final name =
                    '${user['forename'] ?? ''} ${user['surname'] ?? ''}'
                        .trim();
                final ename = user['ename'] ?? '';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFFE5E7EB),
                        child: Text(
                            name.isNotEmpty
                                ? name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name.isNotEmpty ? name : ename,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                            Text(ename,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF9CA3AF))),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        initialValue: role,
                        tooltip: 'Change role',
                        onSelected: (r) {
                          if (r == '__remove__') {
                            _removeMember(uid);
                          } else {
                            _changeRole(uid, r);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'volunteer',
                              child: Text('Volunteer')),
                          const PopupMenuItem(
                              value: 'missionAdmin',
                              child: Text('Mission Admin')),
                          const PopupMenuItem(
                              value: 'itemAdmin',
                              child: Text('Item Admin')),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: '__remove__',
                            child: Text('Remove',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _roleBg(role),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_roleLabel(role),
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _roleColor(role))),
                              Icon(Icons.arrow_drop_down,
                                  size: 16, color: _roleColor(role)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'missionAdmin':
        return 'Mission Admin';
      case 'itemAdmin':
        return 'Item Admin';
      default:
        return 'Volunteer';
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'missionAdmin':
        return const Color(0xFF7C3AED);
      case 'itemAdmin':
        return const Color(0xFF2563EB);
      default:
        return const Color(0xFF059669);
    }
  }

  Color _roleBg(String role) {
    switch (role) {
      case 'missionAdmin':
        return const Color(0xFFEDE9FE);
      case 'itemAdmin':
        return const Color(0xFFDBEAFE);
      default:
        return const Color(0xFFD1FAE5);
    }
  }

  // ── Recent Services Card ──
  Widget _servicesCard(TextTheme tt) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.miscellaneous_services,
                color: Color(0xFF059669)),
            const SizedBox(width: 8),
            Text('Recent Services (${_services.length})',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          if (_services.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                  child: Text('No services',
                      style: TextStyle(color: Color(0xFF9CA3AF)))),
            )
          else
            ..._services.take(10).map((s) {
              final title = s['title'] ?? '—';
              final status = s['status'] ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusBg(status),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(status,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _statusFg(status))),
                    ),
                  ],
                ),
              );
            }),
        ]),
      ),
    );
  }

  Color _statusFg(String s) {
    switch (s) {
      case 'active':
        return const Color(0xFF059669);
      case 'completed':
        return const Color(0xFF2563EB);
      case 'cancelled':
        return Colors.red;
      default:
        return const Color(0xFF6B7280);
    }
  }

  Color _statusBg(String s) {
    switch (s) {
      case 'active':
        return const Color(0xFFD1FAE5);
      case 'completed':
        return const Color(0xFFDBEAFE);
      case 'cancelled':
        return const Color(0xFFFEE2E2);
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  // ── Vehicles Card ──
  Widget _vehiclesCard(TextTheme tt) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.directions_car, color: Color(0xFFD97706)),
            const SizedBox(width: 8),
            Text('Vehicles (${_vehicles.length})',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          if (_vehicles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                  child: Text('No vehicles',
                      style: TextStyle(color: Color(0xFF9CA3AF)))),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _vehicles.map((v) {
                final plate = v['plate'] ?? '';
                final type = v['type'] ?? '';
                return Chip(
                  avatar: const Icon(Icons.directions_car,
                      size: 16, color: Color(0xFFD97706)),
                  label: Text(
                      '$plate${type.isNotEmpty ? ' ($type)' : ''}',
                      style: const TextStyle(fontSize: 12)),
                );
              }).toList(),
            ),
        ]),
      ),
    );
  }
}
