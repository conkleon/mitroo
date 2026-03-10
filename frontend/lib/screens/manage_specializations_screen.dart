import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';

/// Professional specialization list with search, hierarchy indicator,
/// stats, and grid/list layout.
class ManageSpecializationsScreen extends StatefulWidget {
  const ManageSpecializationsScreen({super.key});

  @override
  State<ManageSpecializationsScreen> createState() =>
      _ManageSpecializationsScreenState();
}

class _ManageSpecializationsScreenState
    extends State<ManageSpecializationsScreen> {
  final _api = ApiClient();
  List<dynamic> _specs = [];
  bool _loading = true;
  String _search = '';
  String _filter = 'all'; // all | root | sub

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get('/specializations');
      if (res.statusCode == 200) _specs = jsonDecode(res.body);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<dynamic> get _filtered {
    var list = List<dynamic>.from(_specs);
    // filter
    if (_filter == 'root') {
      list = list.where((s) => s['rootId'] == null).toList();
    } else if (_filter == 'sub') {
      list = list.where((s) => s['rootId'] != null).toList();
    }
    // search
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((s) {
        return (s['name'] ?? '').toString().toLowerCase().contains(q);
      }).toList();
    }
    return list;
  }

  int _count(String type) {
    if (type == 'root') return _specs.where((s) => s['rootId'] == null).length;
    if (type == 'sub') return _specs.where((s) => s['rootId'] != null).length;
    return _specs.length;
  }

  int get _totalUsers => _specs.fold<int>(
      0, (sum, s) => sum + ((s['_count']?['users'] ?? 0) as int));

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final hoursCtrl = TextEditingController();
    int? selectedRoot;

    final roots = _specs.where((s) => s['rootId'] == null).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return AlertDialog(
          title: const Text('Νέα Ειδίκευση'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Όνομα *',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Περιγραφή',
                          border: OutlineInputBorder()),
                      maxLines: 2),
                  const SizedBox(height: 12),
                  TextField(
                      controller: hoursCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Ώρες Εκπαίδευσης',
                          border: OutlineInputBorder()),
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: selectedRoot,
                    decoration: const InputDecoration(
                        labelText: 'Γονικό (προαιρετικό)',
                        border: OutlineInputBorder()),
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
                };
                if (descCtrl.text.isNotEmpty) {
                  body['description'] = descCtrl.text.trim();
                }
                if (hoursCtrl.text.isNotEmpty) {
                  body['hoursTraining'] = int.tryParse(hoursCtrl.text) ?? 0;
                }
                if (selectedRoot != null) body['rootId'] = selectedRoot;
                final res =
                    await _api.post('/specializations', body: body);
                if (ctx.mounted) Navigator.pop(ctx);
                if (res.statusCode == 201) {
                  _fetch();
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Αποτυχία δημιουργίας')));
                }
              },
              child: const Text('Δημιουργία'),
            ),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text('Διαχείριση Ειδικεύσεων',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fetch,
              tooltip: 'Ανανέωση'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text('Νέα Ειδίκευση'),
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          final hPad = isWide ? 32.0 : 16.0;

          return Column(children: [
            // ── Search ──
            Padding(
              padding:
                  EdgeInsets.symmetric(horizontal: hPad, vertical: 12),
              child: TextField(
                decoration: InputDecoration(
                hintText: 'Αναζήτηση ειδικεύσεων...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),

            // ── Filter chips ──
            Padding(
              padding: EdgeInsets.symmetric(horizontal: hPad),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _chip('All', 'all', _count('all')),
                  const SizedBox(width: 8),
                  _chip('Ρίζα', 'root', _count('root')),
                  const SizedBox(width: 8),
                  _chip('Sub', 'sub', _count('sub')),
                ]),
              ),
            ),
            const SizedBox(height: 8),

            // ── Stats ──
            Padding(
              padding: EdgeInsets.symmetric(horizontal: hPad),
              child: Row(children: [
                _MiniStat(
                    label: 'Ειδικεύσεις',
                    value: '${_specs.length}',
                    icon: Icons.school,
                    color: const Color(0xFF7C3AED)),
                const SizedBox(width: 12),
                _MiniStat(
                    label: 'Χρήστες',
                    value: '$_totalUsers',
                    icon: Icons.people,
                    color: const Color(0xFF2563EB)),
                const SizedBox(width: 12),
                _MiniStat(
                    label: 'Εμφαν.',
                    value: '${filtered.length}',
                    icon: Icons.filter_list,
                    color: const Color(0xFF6B7280)),
              ]),
            ),
            const SizedBox(height: 8),

            // ── List / Grid ──
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.school,
                                  size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text('Δεν βρέθηκαν ειδικεύσεις',
                                  style: tt.bodyLarge?.copyWith(
                                      color: Colors.grey.shade500)),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetch,
                          child: isWide
                              ? _buildGrid(filtered)
                              : _buildList(filtered),
                        ),
            ),
          ]);
        }),
      ),
    );
  }

  Widget _chip(String label, String key, int count) {
    final selected = _filter == key;
    return FilterChip(
      label: Text('$label ($count)'),
      selected: selected,
      onSelected: (_) => setState(() => _filter = key),
      selectedColor: const Color(0xFFEDE9FE),
      checkmarkColor: const Color(0xFF7C3AED),
    );
  }

  Widget _buildList(List<dynamic> specs) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
      itemCount: specs.length,
      itemBuilder: (context, i) => _SpecCard(
        spec: specs[i],
        onTap: () async {
          await context.push('/admin/specializations/${specs[i]['id']}');
          _fetch();
        },
      ),
    );
  }

  Widget _buildGrid(List<dynamic> specs) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 90),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 12,
        childAspectRatio: 3.2,
      ),
      itemCount: specs.length,
      itemBuilder: (context, i) => _SpecCard(
        spec: specs[i],
        onTap: () async {
          await context.push('/admin/specializations/${specs[i]['id']}');
          _fetch();
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
class _SpecCard extends StatelessWidget {
  final dynamic spec;
  final VoidCallback onTap;
  const _SpecCard({required this.spec, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final counts = (spec['_count'] as Map<String, dynamic>?) ?? {};
    final userCount = counts['users'] ?? 0;
    final childCount = counts['children'] ?? 0;
    final root = spec['root'] as Map<String, dynamic>?;
    final hours = spec['hoursTraining'] ?? 0;
    final isRoot = spec['rootId'] == null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isRoot
                    ? const Color(0xFFEDE9FE)
                    : const Color(0xFFDBEAFE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                  isRoot ? Icons.school : Icons.subdirectory_arrow_right,
                  color: isRoot
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFF2563EB),
                  size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(spec['name'] ?? '',
                        style: tt.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Wrap(spacing: 12, children: [
                      if (root != null)
                        _MiniLabel(
                            icon: Icons.account_tree,
                            text: root['name'] ?? '',
                            color: const Color(0xFF6B7280)),
                      _MiniLabel(
                          icon: Icons.people,
                          text: '$userCount',
                          color: const Color(0xFF2563EB)),
                      if (isRoot && childCount > 0)
                        _MiniLabel(
                            icon: Icons.subdirectory_arrow_right,
                            text: '$childCount',
                            color: const Color(0xFF7C3AED)),
                      if (hours > 0)
                        _MiniLabel(
                            icon: Icons.schedule,
                            text: '${hours}h',
                            color: const Color(0xFFD97706)),
                    ]),
                  ]),
            ),
            Icon(Icons.chevron_right,
                color: Colors.grey.shade400, size: 20),
          ]),
        ),
      ),
    );
  }
}

class _MiniLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _MiniLabel(
      {required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 3),
      Text(text,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    ]);
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MiniStat(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: color)),
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6B7280))),
              ]),
        ]),
      ),
    );
  }
}
