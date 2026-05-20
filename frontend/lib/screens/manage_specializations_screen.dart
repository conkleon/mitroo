import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
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
    final yearlyHoursCtrl = TextEditingController();
    final yearlyHoursTrainingCtrl = TextEditingController();
    final hoursCtrl = TextEditingController();
    final hoursTepCtrl = TextEditingController();
    final eamePrefixCtrl = TextEditingController();
    int? selectedRoot;

    final Map<int, bool> selectedTypeIds = {};

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
                        labelText: 'Ώρες ΤΕΠ',
                        border: OutlineInputBorder()),
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
                  const SizedBox(height: 12),
                  Text('Τύποι Υπηρεσιών',
                      style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  FutureBuilder(
                    future: _api.get('/service-types'),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Text('Φόρτωση...');
                      final res = snapshot.data!;
                      if (res.statusCode != 200) return const Text('Σφάλμα');
                      final types = (jsonDecode(res.body) as List<dynamic>)
                          .map((t) => Map<String, dynamic>.from(t as Map))
                          .toList();
                      return Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: types.map((t) {
                          final typeId = t['id'] as int;
                          final selected = selectedTypeIds[typeId] == true;
                          return FilterChip(
                            label: Text(t['name'] ?? ''),
                            selected: selected,
                            onSelected: (v) {
                              setS(() {
                                selectedTypeIds[typeId] = v;
                              });
                            },
                            selectedColor: const Color(0xFFEDE9FE),
                            checkmarkColor: const Color(0xFF7C3AED),
                          );
                        }).toList(),
                      );
                    },
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
                if (yearlyHoursCtrl.text.isNotEmpty) {
                  body['yearlyHours'] = int.tryParse(yearlyHoursCtrl.text) ?? 0;
                }
                if (yearlyHoursTrainingCtrl.text.isNotEmpty) {
                  body['yearlyHoursTraining'] = int.tryParse(yearlyHoursTrainingCtrl.text) ?? 0;
                }
                if (hoursCtrl.text.isNotEmpty) {
                  body['hoursTraining'] = int.tryParse(hoursCtrl.text) ?? 0;
                }
                if (hoursTepCtrl.text.isNotEmpty) {
                  body['hoursTEP'] = int.tryParse(hoursTepCtrl.text) ?? 0;
                }
                body['eamePrefix'] = eamePrefixCtrl.text.trim();
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
        heroTag: 'manage_specializations_fab',
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text('Νέα Ειδίκευση'),
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          final hPad = isWide ? 32.0 : 16.0;

          return Column(children: [
            // ── Section header ──
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 4),
              child: Row(
                children: [
                  Container(
                    width: 4, height: 22,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Ειδικεύσεις',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1C1E),
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),

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
                    color: const Color(0xFFDC2626)),
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
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 40),
                            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9FAFB),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3F4F6),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.school, size: 32, color: Color(0xFF9CA3AF)),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _search.isNotEmpty ? 'Δεν βρέθηκαν ειδικεύσεις' : 'Δεν υπάρχουν ειδικεύσεις',
                                  style: GoogleFonts.inter(
                                    fontSize: 14, color: const Color(0xFF6B7280), fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _search.isNotEmpty ? 'Δοκιμάστε άλλη αναζήτηση' : 'Πατήστε το + για να προσθέσετε',
                                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF9CA3AF)),
                                ),
                              ],
                            ),
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
        childAspectRatio: 3.8,
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
    final yearlyHours = spec['yearlyHours'] ?? 0;
    final yearlyHoursTraining = spec['yearlyHoursTraining'] ?? 0;
    final hours = spec['hoursTraining'] ?? 0;
    final hoursTep = spec['hoursTEP'] ?? 0;
    final eamePrefix = (spec['eamePrefix'] ?? '').toString();
    final isRoot = spec['rootId'] == null;
    final description = (spec['description'] ?? '').toString();
    final subtitle = isRoot
        ? description
        : (root?['name'] ?? '').toString();
    final accentColor =
        isRoot ? const Color(0xFF7C3AED) : const Color(0xFFDC2626);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(spec['name'] ?? '',
                          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: GoogleFonts.inter(
                                fontSize: 12, color: const Color(0xFF6B7280)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                      ] else
                        const SizedBox(height: 2),
                      Wrap(spacing: 10, children: [
                        _MiniLabel(
                            icon: Icons.people,
                            text: '$userCount',
                            color: const Color(0xFFDC2626)),
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
                        if (yearlyHours > 0)
                          _MiniLabel(
                              icon: Icons.calendar_month,
                              text: 'Ετήσιες ${yearlyHours}h',
                              color: const Color(0xFF2563EB)),
                        if (yearlyHoursTraining > 0)
                          _MiniLabel(
                              icon: Icons.school_outlined,
                              text: 'Εκπ. ${yearlyHoursTraining}h',
                              color: const Color(0xFF0F766E)),
                        if (hoursTep > 0)
                          _MiniLabel(
                              icon: Icons.timer,
                              text: 'TEP ${hoursTep}h',
                              color: const Color(0xFF0EA5E9)),
                        if (eamePrefix.isNotEmpty)
                          _MiniLabel(
                              icon: Icons.badge_outlined,
                              text: 'EAME $eamePrefix',
                              color: const Color(0xFF111827)),
                      ]),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.chevron_right, color: Color(0xFF9CA3AF), size: 18),
              ),
            ],
          ),
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
          style: GoogleFonts.inter(
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
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: color)),
                Text(label,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: const Color(0xFF6B7280))),
              ]),
        ]),
      ),
    );
  }
}
