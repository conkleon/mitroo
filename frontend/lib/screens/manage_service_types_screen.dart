import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_client.dart';

class ManageServiceTypesScreen extends StatefulWidget {
  const ManageServiceTypesScreen({super.key});

  @override
  State<ManageServiceTypesScreen> createState() => _ManageServiceTypesScreenState();
}

class _ManageServiceTypesScreenState extends State<ManageServiceTypesScreen> {
  final _api = ApiClient();
  List<dynamic> _types = [];
  List<dynamic> _allSpecs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get('/service-types');
      if (res.statusCode == 200) _types = jsonDecode(res.body);
      final specRes = await _api.get('/specializations');
      if (specRes.statusCode == 200) _allSpecs = jsonDecode(specRes.body);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleDefaultVisible(int typeId, bool current) async {
    await _api.patch('/service-types/$typeId', body: {'isDefaultVisible': !current});
    _fetch();
  }

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final extIdCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        bool isDefaultVisible = false;

        return AlertDialog(
          title: const Text('Νέος Τύπος Υπηρεσίας'),
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
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: extIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'External Mission Type ID',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: isDefaultVisible,
                    onChanged: (v) => setS(() => isDefaultVisible = v ?? false),
                    title: const Text('Ορατό από προεπιλογή'),
                    subtitle: const Text('Ορατό σε όλες τις ειδικεύσεις'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Άκυρο'),
            ),
            FilledButton(
              onPressed: () async {
                final body = <String, dynamic>{
                  'name': nameCtrl.text.trim(),
                  'isDefaultVisible': isDefaultVisible,
                };
                final extIdParsed = int.tryParse(extIdCtrl.text.trim());
                if (extIdParsed != null) {
                  body['externalMissionTypeId'] = extIdParsed;
                }
                await _api.post('/service-types', body: body);
                if (ctx.mounted) Navigator.pop(ctx);
                _fetch();
              },
              child: const Text('Δημιουργία'),
            ),
          ],
        );
      }),
    );
  }

  void _showEditSheet(Map<String, dynamic> type) async {
    final typeId = type['id'] as int;

    List<int> selectedSpecIds = [];
    try {
      final res = await _api.get('/service-types/$typeId/specializations');
      if (res.statusCode == 200) {
        final rows = jsonDecode(res.body) as List<dynamic>;
        selectedSpecIds = rows.map((r) => r['specializationId'] as int).toList();
      }
    } catch (_) {}

    final selected = Set<int>.from(selectedSpecIds);

    final nameCtrl = TextEditingController(text: type['name'] ?? '');
    final extIdCtrl = TextEditingController(text: '${type['externalMissionTypeId'] ?? ''}');
    bool isDefaultVisible = type['isDefaultVisible'] == true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollCtrl) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: ListView(
              controller: scrollCtrl,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Επεξεργασία Τύπου Υπηρεσίας',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Όνομα',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: extIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'External Mission Type ID',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: isDefaultVisible,
                  onChanged: (v) => setS(() => isDefaultVisible = v ?? false),
                  title: const Text('Ορατό από προεπιλογή'),
                  subtitle: const Text('Ορατό σε όλες τις ειδικεύσεις'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 20),
                Text('Ειδικεύσεις που βλέπουν αυτό τον τύπο',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (_allSpecs.isEmpty)
                  const Text('Δεν υπάρχουν ειδικεύσεις')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _allSpecs.map((s) {
                      final specId = s['id'] as int;
                      final sel = selected.contains(specId);
                      return FilterChip(
                        label: Text(s['name'] ?? ''),
                        selected: sel,
                        onSelected: (v) {
                          setS(() {
                            if (v) {
                              selected.add(specId);
                            } else {
                              selected.remove(specId);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Άκυρο'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          final body = <String, dynamic>{
                            'name': nameCtrl.text.trim(),
                            'isDefaultVisible': isDefaultVisible,
                          };
                          final extIdParsed = int.tryParse(extIdCtrl.text.trim());
                          if (extIdParsed != null) {
                            body['externalMissionTypeId'] = extIdParsed;
                          }
                          await _api.patch('/service-types/$typeId', body: body);

                          await _api.put('/service-types/$typeId/specializations',
                              body: {'specializationIds': selected.toList()});

                          if (ctx.mounted) Navigator.pop(ctx);
                          _fetch();
                        },
                        child: const Text('Αποθήκευση'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Τύποι Υπηρεσιών', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetch,
            tooltip: 'Ανανέωση',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _types.isEmpty
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
                          child: const Icon(Icons.category, size: 32, color: Color(0xFF9CA3AF)),
                        ),
                        const SizedBox(height: 16),
                        Text('Δεν υπάρχουν τύποι υπηρεσιών',
                            style: tt.bodyLarge?.copyWith(color: const Color(0xFF6B7280), fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text('Πατήστε το + για να δημιουργήσετε',
                            style: tt.bodySmall?.copyWith(color: const Color(0xFF9CA3AF))),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: _types.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final t = _types[i];
                    final name = t['name'] ?? '';
                    final defaultVisible = t['isDefaultVisible'] == true;
                    final specCount = (t['_count']?['specializations'] ?? 0) as int;
                    final serviceCount = (t['_count']?['services'] ?? 0) as int;

                    return Card(
                      child: ListTile(
                        title: Text(name, style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                        subtitle: Text('$specCount ειδικεύσεις • $serviceCount υπηρεσίες'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FilterChip(
                              label: Text(defaultVisible ? 'Προεπιλογή' : 'Περιορισμένο',
                                  style: TextStyle(fontSize: 11)),
                              selected: defaultVisible,
                              onSelected: (_) => _toggleDefaultVisible(t['id'], defaultVisible),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () => _showEditSheet(Map<String, dynamic>.from(t as Map)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
