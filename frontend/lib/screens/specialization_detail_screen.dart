import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';

/// Full detail view for a single specialization.
/// Shows info, parent/children hierarchy, assigned users, edit/delete.
class SpecializationDetailScreen extends StatefulWidget {
  final int specializationId;
  const SpecializationDetailScreen(
      {super.key, required this.specializationId});

  @override
  State<SpecializationDetailScreen> createState() =>
      _SpecializationDetailScreenState();
}

class _SpecializationDetailScreenState
    extends State<SpecializationDetailScreen> {
  final _api = ApiClient();
  Map<String, dynamic>? _spec;
  List<dynamic> _allUsers = [];
  List<dynamic> _allSpecs = [];
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
        _api.get('/specializations/${widget.specializationId}'),
        _api.get('/users'),
        _api.get('/specializations'),
      ]);
      if (results[0].statusCode == 200) {
        _spec = jsonDecode(results[0].body);
      }
      if (results[1].statusCode == 200) {
        _allUsers = jsonDecode(results[1].body);
      }
      if (results[2].statusCode == 200) {
        _allSpecs = jsonDecode(results[2].body);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<dynamic> get _users =>
      (_spec?['users'] as List<dynamic>?) ?? [];
  List<dynamic> get _children =>
      (_spec?['children'] as List<dynamic>?) ?? [];
  Map<String, dynamic>? get _root =>
      _spec?['root'] as Map<String, dynamic>?;

  // ── Edit ─────────────────────────────────
  void _edit() {
    if (_spec == null) return;
    final nameCtrl = TextEditingController(text: _spec!['name'] ?? '');
    final descCtrl =
        TextEditingController(text: _spec!['description'] ?? '');
    final hoursCtrl = TextEditingController(
        text: (_spec!['hoursTraining'] ?? 0).toString());
    int? selectedRoot = _spec!['rootId'] as int?;

    final roots =
        _allSpecs.where((s) => s['rootId'] == null && s['id'] != widget.specializationId).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return AlertDialog(
          title: const Text('Edit Specialization'),
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
                      controller: hoursCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Training Hours',
                          border: OutlineInputBorder()),
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: selectedRoot,
                    decoration: const InputDecoration(
                        labelText: 'Parent',
                        border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('— None (root) —')),
                      ...roots.map((r) => DropdownMenuItem<int?>(
                            value: r['id'],
                            child: Text(r['name'] ?? ''),
                          )),
                    ],
                    onChanged: (v) => setS(() => selectedRoot = v),
                  ),
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
                  'rootId': selectedRoot,
                };
                if (descCtrl.text.isNotEmpty) {
                  body['description'] = descCtrl.text.trim();
                }
                if (hoursCtrl.text.isNotEmpty) {
                  body['hoursTraining'] =
                      int.tryParse(hoursCtrl.text) ?? 0;
                }
                await _api.patch(
                    '/specializations/${widget.specializationId}',
                    body: body);
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              },
              child: const Text('Save'),
            ),
          ],
        );
      }),
    );
  }

  // ── Delete ──────────────────────────────
  void _delete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Specialization'),
        content: const Text(
            'Are you sure? This will remove the specialization and all user assignments.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _api
                  .delete('/specializations/${widget.specializationId}');
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) context.pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ── Add user ─────────────────────────────
  void _addUser() {
    final assignedIds =
        _users.map((u) => (u['user']?['id'] as int?) ?? 0).toSet();
    final available =
        _allUsers.where((u) => !assignedIds.contains(u['id'])).toList();

    int? selectedUser;
    String? selectedUserName;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return AlertDialog(
          title: const Text('Add User'),
          content: SizedBox(
            width: 400,
            child: Autocomplete<Map<String, dynamic>>(
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
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
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
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
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
              optionsViewBuilder: (context, onSelected, options) {
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
                                style:
                                    const TextStyle(fontSize: 14)),
                            subtitle: Text(opt['ename'] ?? '',
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
                          '/users/$selectedUser/specializations',
                          body: {
                            'specializationId':
                                widget.specializationId
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

  // ── Remove user ──
  Future<void> _removeUser(int userId) async {
    await _api.delete(
        '/users/$userId/specializations/${widget.specializationId}');
    _load();
  }

  // ═══════════════════════════ BUILD ═══════════════════════════
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(_spec?['name'] ?? 'Specialization',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _edit,
              tooltip: 'Edit'),
          IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _delete,
              tooltip: 'Delete'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _spec == null
              ? const Center(child: Text('Specialization not found'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: LayoutBuilder(builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 900;
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.all(isWide ? 32 : 16),
                      child: isWide
                          ? Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                    child: Column(children: [
                                  _infoCard(tt),
                                  const SizedBox(height: 16),
                                  _hierarchyCard(tt),
                                ])),
                                const SizedBox(width: 20),
                                Expanded(
                                    flex: 2,
                                    child: _usersCard(tt)),
                              ],
                            )
                          : Column(children: [
                              _infoCard(tt),
                              const SizedBox(height: 16),
                              _hierarchyCard(tt),
                              const SizedBox(height: 16),
                              _usersCard(tt),
                            ]),
                    );
                  }),
                ),
    );
  }

  // ── Info Card ──
  Widget _infoCard(TextTheme tt) {
    final isRoot = _spec!['rootId'] == null;
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
                    color: isRoot
                        ? const Color(0xFFEDE9FE)
                        : const Color(0xFFDBEAFE),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                      isRoot
                          ? Icons.school
                          : Icons.subdirectory_arrow_right,
                      size: 48,
                      color: isRoot
                          ? const Color(0xFF7C3AED)
                          : const Color(0xFF2563EB)),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(_spec!['name'] ?? '',
                    style: tt.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center),
              ),
              if (isRoot)
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDE9FE),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Root',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF7C3AED))),
                  ),
                ),
              if ((_spec!['description'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_spec!['description'],
                    style: tt.bodyMedium
                        ?.copyWith(color: const Color(0xFF6B7280))),
              ],
              const Divider(height: 24),
              _infoRow(Icons.schedule, 'Training Hours',
                  '${_spec!['hoursTraining'] ?? 0}h'),
              _infoRow(Icons.people, 'Assigned Users',
                  '${_users.length}'),
              _infoRow(Icons.account_tree, 'Sub-specializations',
                  '${_children.length}'),
            ]),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 18, color: const Color(0xFF6B7280)),
        const SizedBox(width: 10),
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF6B7280)))),
        Text(value,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── Hierarchy Card ──
  Widget _hierarchyCard(TextTheme tt) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.account_tree,
                    color: Color(0xFF7C3AED)),
                const SizedBox(width: 8),
                Text('Hierarchy',
                    style: tt.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 12),
              if (_root != null)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.arrow_upward,
                      color: Color(0xFF6B7280), size: 20),
                  title: Text('Parent: ${_root!['name'] ?? ''}'),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () async {
                    await context
                        .push('/admin/specializations/${_root!['id']}');
                    _load();
                  },
                ),
              if (_children.isEmpty && _root == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                      child: Text('No parent or sub-specializations',
                          style:
                              TextStyle(color: Color(0xFF9CA3AF)))),
                ),
              ..._children.map((c) => ListTile(
                    dense: true,
                    leading: const Icon(
                        Icons.subdirectory_arrow_right,
                        color: Color(0xFF2563EB),
                        size: 20),
                    title: Text(c['name'] ?? ''),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () async {
                      await context
                          .push('/admin/specializations/${c['id']}');
                      _load();
                    },
                  )),
            ]),
      ),
    );
  }

  // ── Users Card ──
  Widget _usersCard(TextTheme tt) {
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
                Text('Assigned Users (${_users.length})',
                    style: tt.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                ActionChip(
                  label: const Text('Add'),
                  avatar: const Icon(Icons.add, size: 16),
                  onPressed: _addUser,
                ),
              ]),
              const SizedBox(height: 12),
              if (_users.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                      child: Text('No users assigned',
                          style:
                              TextStyle(color: Color(0xFF9CA3AF)))),
                )
              else
                ..._users.map((us) {
                  final user =
                      us['user'] as Map<String, dynamic>? ?? {};
                  final uid = user['id'] as int? ?? 0;
                  final name =
                      '${user['forename'] ?? ''} ${user['surname'] ?? ''}'
                          .trim();
                  final ename = user['ename'] ?? '';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
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
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                                name.isNotEmpty ? name : ename,
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
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Colors.red, size: 20),
                        onPressed: () => _removeUser(uid),
                        tooltip: 'Remove',
                      ),
                    ]),
                  );
                }),
            ]),
      ),
    );
  }
}
