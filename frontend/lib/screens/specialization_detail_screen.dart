import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import 'package:mitroo_frontend/theme/theme.dart';

/// Full detail view for a single specialization.
/// Shows info, parent/children hierarchy, assigned users, edit/delete.
class SpecializationDetailScreen extends StatefulWidget {
  final int specializationId;
  const SpecializationDetailScreen({super.key, required this.specializationId});

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

  List<dynamic> get _users => (_spec?['users'] as List<dynamic>?) ?? [];
  List<dynamic> get _children => (_spec?['children'] as List<dynamic>?) ?? [];
  Map<String, dynamic>? get _root => _spec?['root'] as Map<String, dynamic>?;

  // ── Edit ─────────────────────────────────
  void _edit() {
    if (_spec == null) return;
    final nameCtrl = TextEditingController(text: _spec!['name'] ?? '');
    final descCtrl = TextEditingController(text: _spec!['description'] ?? '');
    final yearlyHoursCtrl =
        TextEditingController(text: (_spec!['yearlyHours'] ?? 0).toString());
    final yearlyHoursTrainingCtrl = TextEditingController(
        text: (_spec!['yearlyHoursTraining'] ?? 0).toString());
    final hoursCtrl =
        TextEditingController(text: (_spec!['hoursTraining'] ?? 0).toString());
    final hoursTepCtrl =
        TextEditingController(text: (_spec!['hoursTEP'] ?? 0).toString());
    final eamePrefixCtrl =
        TextEditingController(text: (_spec!['eamePrefix'] ?? '').toString());
    int? selectedRoot = _spec!['rootId'] as int?;
    // Service type visibility is managed via the service types admin screen

    final roots = _allSpecs
        .where((s) => s['rootId'] == null && s['id'] != widget.specializationId)
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return AlertDialog(
          title: const Text('Επεξεργασία Ειδίκευσης'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Όνομα', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Περιγραφή', border: OutlineInputBorder()),
                      maxLines: 2),
                  const SizedBox(height: 12),
                  TextField(
                      controller: yearlyHoursCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Ετήσιες Ώρες',
                          border: OutlineInputBorder()),
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  TextField(
                      controller: yearlyHoursTrainingCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Ετήσιες Ώρες Εκπαίδευσης',
                          border: OutlineInputBorder()),
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  TextField(
                      controller: hoursCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Ώρες Εκπαίδευσης',
                          border: OutlineInputBorder()),
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  TextField(
                      controller: hoursTepCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Ώρες ΤΕΠ', border: OutlineInputBorder()),
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  TextField(
                      controller: eamePrefixCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Πρόθεμα EAME',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: selectedRoot,
                    decoration: const InputDecoration(
                        labelText: 'Γονικό', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('— Κανένα (ρίζα) —')),
                      ...roots.map((r) => DropdownMenuItem<int?>(
                            value: r['id'],
                            child: Text(r['name'] ?? ''),
                          )),
                    ],
                    onChanged: (v) => setS(() => selectedRoot = v),
                  ),
                  const SizedBox(height: 12),
                  Text(
                      'Η ορατότητα τύπων υπηρεσίας ρυθμίζεται από την οθόνη Τύποι Υπηρεσιών',
                      style: Theme.of(ctx)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.gray500)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Άκυρο')),
            FilledButton(
              onPressed: () async {
                final body = <String, dynamic>{
                  'name': nameCtrl.text.trim(),
                  'rootId': selectedRoot,
                };
                if (descCtrl.text.isNotEmpty) {
                  body['description'] = descCtrl.text.trim();
                }
                if (yearlyHoursCtrl.text.isNotEmpty) {
                  body['yearlyHours'] = int.tryParse(yearlyHoursCtrl.text) ?? 0;
                }
                if (yearlyHoursTrainingCtrl.text.isNotEmpty) {
                  body['yearlyHoursTraining'] =
                      int.tryParse(yearlyHoursTrainingCtrl.text) ?? 0;
                }
                if (hoursCtrl.text.isNotEmpty) {
                  body['hoursTraining'] = int.tryParse(hoursCtrl.text) ?? 0;
                }
                if (hoursTepCtrl.text.isNotEmpty) {
                  body['hoursTEP'] = int.tryParse(hoursTepCtrl.text) ?? 0;
                }
                body['eamePrefix'] = eamePrefixCtrl.text.trim();
                await _api.patch('/specializations/${widget.specializationId}',
                    body: body);
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              },
              child: const Text('Αποθήκευση'),
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
        title: const Text('Διαγραφή Ειδίκευσης'),
        content: const Text(
            'Είστε σίγουροι; Αυτό θα αφαιρέσει την ειδίκευση και όλες τις αναθέσεις.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red600),
            onPressed: () async {
              await _api.delete('/specializations/${widget.specializationId}');
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) context.pop();
            },
            child: const Text('Διαγραφή'),
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
          title: const Text('Προσθήκη Χρήστη'),
          content: SizedBox(
            width: 400,
            child: Autocomplete<Map<String, dynamic>>(
              displayStringForOption: (u) =>
                  '${u['forename'] ?? ''} ${u['surname'] ?? ''} (${u['eame'] ?? ''})'
                      .trim(),
              optionsBuilder: (textEditingValue) {
                final q = textEditingValue.text.toLowerCase();
                final opts = available.cast<Map<String, dynamic>>();
                if (q.isEmpty) return opts;
                return opts.where((u) {
                  final name = '${u['forename'] ?? ''} ${u['surname'] ?? ''}'
                      .toLowerCase();
                  final eame = (u['eame'] ?? '').toString().toLowerCase();
                  return name.contains(q) || eame.contains(q);
                });
              },
              onSelected: (u) {
                setS(() {
                  selectedUser = u['id'] as int;
                  selectedUserName =
                      '${u['forename'] ?? ''} ${u['surname'] ?? ''} (${u['eame'] ?? ''})'
                          .trim();
                });
              },
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                if (selectedUserName != null && controller.text.isEmpty) {
                  controller.text = selectedUserName!;
                }
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: 'Χρήστης',
                    hintText: 'Πληκτρολογήστε...',
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
                    borderRadius: AppRadius.r8,
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxHeight: 200, maxWidth: 370),
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
                                size: 18, color: AppColors.red600),
                            title: Text(
                                name.isNotEmpty ? name : opt['eame'] ?? '',
                                style:
                                    const TextStyle(fontSize: AppFontSize.lg)),
                            subtitle: Text(opt['eame'] ?? '',
                                style: const TextStyle(
                                    fontSize: AppFontSize.base,
                                    color: AppColors.gray400)),
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
                child: const Text('Άκυρο')),
            FilledButton(
              onPressed: selectedUser == null
                  ? null
                  : () async {
                      await _api.post('/users/$selectedUser/specializations',
                          body: {'specializationId': widget.specializationId});
                      if (ctx.mounted) Navigator.pop(ctx);
                      _load();
                    },
              child: const Text('Προσθήκη'),
            ),
          ],
        );
      }),
    );
  }

  // ── Remove user ──
  Future<void> _removeUser(int userId) async {
    await _api
        .delete('/users/$userId/specializations/${widget.specializationId}');
    _load();
  }

  // ═══════════════════════════ BUILD ═══════════════════════════
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_spec?['name'] ?? 'Ειδίκευση',
            style: tt.titleLarge?.copyWith(fontWeight: AppFontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _edit,
              tooltip: 'Επεξεργασία'),
          IconButton(
              icon: const Icon(Icons.delete, color: AppColors.red600),
              onPressed: _delete,
              tooltip: 'Διαγραφή'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _spec == null
              ? const Center(child: Text('Ειδίκευση δεν βρέθηκε'))
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
                                Expanded(
                                    child: Column(children: [
                                  _infoCard(tt),
                                  const SizedBox(height: 16),
                                  _hierarchyCard(tt),
                                ])),
                                const SizedBox(width: 20),
                                Expanded(flex: 2, child: _usersCard(tt)),
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
      shape: RoundedRectangleBorder(borderRadius: AppRadius.r16),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isRoot ? AppColors.violet100 : AppColors.red100,
                borderRadius: AppRadius.r16,
              ),
              child: Icon(
                  isRoot ? Icons.school : Icons.subdirectory_arrow_right,
                  size: 48,
                  color: isRoot ? AppColors.violet600 : AppColors.red600),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(_spec!['name'] ?? '',
                style: tt.titleMedium?.copyWith(fontWeight: AppFontWeight.bold),
                textAlign: TextAlign.center),
          ),
          if (isRoot)
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.violet100,
                  borderRadius: AppRadius.r6,
                ),
                child: const Text('Ρίζα',
                    style: TextStyle(
                        fontSize: AppFontSize.sm,
                        fontWeight: AppFontWeight.semibold,
                        color: AppColors.violet600)),
              ),
            ),
          if ((_spec!['description'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_spec!['description'],
                style: tt.bodyMedium?.copyWith(color: AppColors.gray500)),
          ],
          const Divider(height: 24),
          _infoRow(Icons.schedule, 'Ώρες Εκπαίδευσης',
              '${_spec!['hoursTraining'] ?? 0}h'),
          _infoRow(Icons.calendar_month, 'Ετήσιες Ώρες',
              '${_spec!['yearlyHours'] ?? 0}h'),
          _infoRow(Icons.school_outlined, 'Ετήσιες Ώρες Εκπαίδευσης',
              '${_spec!['yearlyHoursTraining'] ?? 0}h'),
          _infoRow(Icons.timer, 'Ώρες ΤΕΠ', '${_spec!['hoursTEP'] ?? 0}h'),
          _infoRow(
              Icons.badge_outlined,
              'Πρόθεμα EAME',
              (_spec!['eamePrefix'] ?? '').toString().isEmpty
                  ? '—'
                  : (_spec!['eamePrefix'] ?? '').toString()),
          _infoRow(Icons.people, 'Ανατεθ. Χρήστες', '${_users.length}'),
          _infoRow(
              Icons.account_tree, 'Υπο-ειδικεύσεις', '${_children.length}'),
          const Divider(height: 24),
          Row(children: [
            const Icon(Icons.visibility, size: 18, color: AppColors.gray500),
            const SizedBox(width: 10),
            const Expanded(
                child: Text('Ορατότητα Αποστολών',
                    style: TextStyle(
                        fontSize: AppFontSize.md, color: AppColors.gray500))),
          ]),
          const SizedBox(height: 8),
          Builder(builder: (_) {
            final types = (_spec!['serviceTypes'] as List<dynamic>?)
                    ?.map((st) =>
                        (st['serviceType'] as Map<String, dynamic>?)?['name'] ??
                        '')
                    .where((n) => n.isNotEmpty)
                    .toList() ??
                [];
            if (types.isEmpty) {
              return const Text('—',
                  style: TextStyle(
                      fontSize: AppFontSize.md, color: AppColors.gray400));
            }
            return Wrap(
              spacing: 6,
              runSpacing: 4,
              children: types
                  .map((name) => Chip(
                        label: Text(name,
                            style: const TextStyle(fontSize: AppFontSize.sm)),
                        backgroundColor: AppColors.violet100,
                        side: BorderSide.none,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            );
          }),
        ]),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 18, color: AppColors.gray500),
        const SizedBox(width: 10),
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: AppFontSize.md, color: AppColors.gray500))),
        Text(value,
            style: const TextStyle(
                fontSize: AppFontSize.md, fontWeight: AppFontWeight.semibold)),
      ]),
    );
  }

  // ── Hierarchy Card ──
  Widget _hierarchyCard(TextTheme tt) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.r16),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.account_tree, color: AppColors.violet600),
            const SizedBox(width: 8),
            Text('Ιεραρχία',
                style: tt.titleSmall?.copyWith(fontWeight: AppFontWeight.bold)),
          ]),
          const SizedBox(height: 12),
          if (_root != null)
            ListTile(
              dense: true,
              leading: const Icon(Icons.arrow_upward,
                  color: AppColors.gray500, size: 20),
              title: Text('Γονικό: ${_root!['name'] ?? ''}'),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () async {
                await context.push('/admin/specializations/${_root!['id']}');
                _load();
              },
            ),
          if (_children.isEmpty && _root == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                  child: Text('Χωρίς γονικές ή υπο-ειδικεύσεις',
                      style: TextStyle(color: AppColors.gray400))),
            ),
          ..._children.map((c) => ListTile(
                dense: true,
                leading: const Icon(Icons.subdirectory_arrow_right,
                    color: AppColors.red600, size: 20),
                title: Text(c['name'] ?? ''),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () async {
                  await context.push('/admin/specializations/${c['id']}');
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
      shape: RoundedRectangleBorder(borderRadius: AppRadius.r16),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.people, color: AppColors.red600),
            const SizedBox(width: 8),
            Text('Ανατεθ. Χρήστες (${_users.length})',
                style: tt.titleSmall?.copyWith(fontWeight: AppFontWeight.bold)),
            const Spacer(),
            ActionChip(
              label: const Text('Προσθήκη'),
              avatar: const Icon(Icons.add, size: 16),
              onPressed: _addUser,
            ),
          ]),
          const SizedBox(height: 12),
          if (_users.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child: Text('Κανένας χρήστης',
                      style: TextStyle(color: AppColors.gray400))),
            )
          else
            ..._users.map((us) {
              final user = us['user'] as Map<String, dynamic>? ?? {};
              final uid = user['id'] as int? ?? 0;
              final name =
                  '${user['forename'] ?? ''} ${user['surname'] ?? ''}'.trim();
              final eame = user['eame'] ?? '';

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.gray200,
                    child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                            fontWeight: AppFontWeight.semibold)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name.isNotEmpty ? name : eame,
                            style: const TextStyle(
                                fontWeight: AppFontWeight.semibold,
                                fontSize: AppFontSize.md)),
                        Text(eame,
                            style: const TextStyle(
                                fontSize: AppFontSize.sm,
                                color: AppColors.gray400)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: AppColors.red600, size: 20),
                    onPressed: () => _removeUser(uid),
                    tooltip: 'Αφαίρεση',
                  ),
                ]),
              );
            }),
        ]),
      ),
    );
  }
}
