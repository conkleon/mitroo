import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../providers/victim_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';

class VictimDetailScreen extends StatefulWidget {
  final int victimId;

  const VictimDetailScreen({super.key, required this.victimId});

  @override
  State<VictimDetailScreen> createState() => _VictimDetailScreenState();
}

class _VictimDetailScreenState extends State<VictimDetailScreen> {
  final _api = ApiClient();
  bool _vitalsExpanded = false;
  bool _treatmentsExpanded = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<VictimProvider>().fetchVictim(widget.victimId));
  }

  void _showAddVitalSignDialog() {
    final systolicCtrl = TextEditingController();
    final diastolicCtrl = TextEditingController();
    final hrCtrl = TextEditingController();
    final rrCtrl = TextEditingController();
    final spo2Ctrl = TextEditingController();
    final tempCtrl = TextEditingController();
    final glucoseCtrl = TextEditingController();
    final painCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final measuredByCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Προσθήκη ζωτικών σημείων'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: systolicCtrl, decoration: const InputDecoration(labelText: 'Συστολική (mmHg)'), keyboardType: TextInputType.number),
              TextField(controller: diastolicCtrl, decoration: const InputDecoration(labelText: 'Διαστολική (mmHg)'), keyboardType: TextInputType.number),
              TextField(controller: hrCtrl, decoration: const InputDecoration(labelText: 'Καρδιακοί παλμοί'), keyboardType: TextInputType.number),
              TextField(controller: rrCtrl, decoration: const InputDecoration(labelText: 'Αναπνοές/λεπτό'), keyboardType: TextInputType.number),
              TextField(controller: spo2Ctrl, decoration: const InputDecoration(labelText: 'SpO2 (%)'), keyboardType: TextInputType.number),
              TextField(controller: tempCtrl, decoration: const InputDecoration(labelText: 'Θερμοκρασία (°C)'), keyboardType: TextInputType.number),
              TextField(controller: glucoseCtrl, decoration: const InputDecoration(labelText: 'Γλυκόζη (mg/dL)'), keyboardType: TextInputType.number),
              TextField(controller: painCtrl, decoration: const InputDecoration(labelText: 'Πόνος (0–10)'), keyboardType: TextInputType.number),
              TextField(controller: measuredByCtrl, decoration: const InputDecoration(labelText: 'Καταγραφή από')),
              TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Σημειώσεις'), maxLines: 2),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () async {
              final data = <String, dynamic>{};
              if (systolicCtrl.text.isNotEmpty) data['systolicBP'] = int.tryParse(systolicCtrl.text);
              if (diastolicCtrl.text.isNotEmpty) data['diastolicBP'] = int.tryParse(diastolicCtrl.text);
              if (hrCtrl.text.isNotEmpty) data['heartRate'] = int.tryParse(hrCtrl.text);
              if (rrCtrl.text.isNotEmpty) data['respiratoryRate'] = int.tryParse(rrCtrl.text);
              if (spo2Ctrl.text.isNotEmpty) data['oxygenSat'] = int.tryParse(spo2Ctrl.text);
              if (tempCtrl.text.isNotEmpty) data['temperature'] = double.tryParse(tempCtrl.text);
              if (glucoseCtrl.text.isNotEmpty) data['bloodGlucose'] = double.tryParse(glucoseCtrl.text);
              if (painCtrl.text.isNotEmpty) data['painScore'] = int.tryParse(painCtrl.text);
              if (measuredByCtrl.text.isNotEmpty) data['measuredBy'] = measuredByCtrl.text;
              if (notesCtrl.text.isNotEmpty) data['notes'] = notesCtrl.text;

              final err = await context.read<VictimProvider>().addVitalSign(widget.victimId, data);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                if (err != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(err), backgroundColor: const Color(0xFFB91C1C)),
                  );
                }
              }
            },
            child: const Text('Καταγραφή'),
          ),
        ],
      ),
    );
  }

  void _showAddTreatmentDialog() async {
    final actionCtrl = TextEditingController();
    final materialCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final consumedCtrl = TextEditingController();
    final performedByCtrl = TextEditingController();

    List<Map<String, dynamic>> availableItems = [];
    try {
      final victim = context.read<VictimProvider>().selected;
      if (victim != null && victim['serviceId'] != null) {
        final svcRes = await _api.get('/services/${victim['serviceId']}');
        if (svcRes.statusCode == 200) {
          final svc = jsonDecode(svcRes.body);
          final itemServices = svc['itemServices'] as List? ?? [];
          for (final is_ in itemServices) {
            final item = is_['item'];
            if (item != null) availableItems.add(item as Map<String, dynamic>);
          }
        }
      }
    } catch (_) {}

    try {
      final profileRes = await _api.get('/auth/me');
      if (profileRes.statusCode == 200) {
        final profile = jsonDecode(profileRes.body);
        final equipment = profile['equipment'] as List? ?? [];
        for (final item in equipment) {
          final exists = availableItems.any((i) => i['id'] == item['id']);
          if (!exists) availableItems.add(item as Map<String, dynamic>);
        }
      }
    } catch (_) {}

    int? selectedItemId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Προσθήκη θεραπείας'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: actionCtrl, decoration: const InputDecoration(labelText: 'Ενέργεια *')),
                TextField(controller: materialCtrl, decoration: const InputDecoration(labelText: 'Υλικά που χρησιμοποιήθηκαν')),
                if (availableItems.isNotEmpty)
                  DropdownButtonFormField<int>(
                    value: selectedItemId,
                    decoration: const InputDecoration(labelText: 'Αντικείμενο (από εξοπλισμό)'),
                    items: [
                      const DropdownMenuItem<int>(value: null, child: Text('—')),
                      ...availableItems.map((item) => DropdownMenuItem<int>(
                        value: item['id'],
                        child: Text(item['name'] ?? 'Αντικείμενο ${item['id']}'),
                      )),
                    ],
                    onChanged: (v) => setDialogState(() => selectedItemId = v),
                  ),
                if (selectedItemId != null)
                  TextField(controller: consumedCtrl, decoration: const InputDecoration(labelText: 'Σημείωση κατανάλωσης')),
                TextField(controller: performedByCtrl, decoration: const InputDecoration(labelText: 'Εκτελέστηκε από')),
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Σημειώσεις'), maxLines: 2),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
            FilledButton(
              onPressed: () async {
                if (actionCtrl.text.trim().isEmpty) return;
                final data = <String, dynamic>{'action': actionCtrl.text.trim()};
                if (materialCtrl.text.isNotEmpty) data['materialUsed'] = materialCtrl.text;
                if (selectedItemId != null) data['itemId'] = selectedItemId;
                if (consumedCtrl.text.isNotEmpty) data['consumedNote'] = consumedCtrl.text;
                if (performedByCtrl.text.isNotEmpty) data['performedBy'] = performedByCtrl.text;
                if (notesCtrl.text.isNotEmpty) data['notes'] = notesCtrl.text;

                final err = await context.read<VictimProvider>().addTreatment(widget.victimId, data);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  if (err != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(err), backgroundColor: const Color(0xFFB91C1C)),
                    );
                  }
                }
              },
              child: const Text('Καταγραφή'),
            ),
          ],
        ),
      ),
    );
  }

  void _showFinalizeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Οριστικοποίηση περιστατικού'),
        content: const Text('Μετά την οριστικοποίηση, το περιστατικό μπορεί να τροποποιηθεί μόνο από διαχειριστές. Συνέχεια;'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final err = await context.read<VictimProvider>().finalizeVictim(widget.victimId);
              if (err != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(err), backgroundColor: const Color(0xFFB91C1C)),
                );
              }
            },
            child: const Text('Οριστικοποίηση'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή περιστατικού'),
        content: const Text('Αυτή η ενέργεια είναι μη αναστρέψιμη. Συνέχεια;'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
            onPressed: () async {
              Navigator.pop(ctx);
              final err = await context.read<VictimProvider>().deleteVictim(widget.victimId);
              if (err != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(err), backgroundColor: const Color(0xFFB91C1C)),
                );
              } else if (context.mounted) {
                context.go('/victims');
              }
            },
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<VictimProvider>();
    final victim = provider.selected;

    if (victim == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Περιστατικό')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isFinalized = victim['isFinalized'] == true;
    final isCreator = victim['createdById'] == auth.user?['id'];
    final isAdmin = auth.isAdmin;
    final canEdit = !isFinalized && (isCreator || isAdmin || auth.isMissionAdmin);
    final canFinalize = !isFinalized && (isCreator || isAdmin || auth.isMissionAdmin);
    final canDelete = isAdmin || auth.isMissionAdmin;

    final vitals = (victim['vitalSigns'] as List?) ?? [];
    final treatments = (victim['treatments'] as List?) ?? [];

    return Scaffold(
      appBar: AppBar(title: Text(victim['name'] ?? 'Περιστατικό')),
      body: RefreshIndicator(
        onRefresh: () => provider.fetchVictim(widget.victimId),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isFinalized) _FinalizedBanner(victim: victim),

              _SectionHeader(title: 'Στοιχεία'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _DetailRow(label: 'Ονοματεπώνυμο', value: victim['name']),
                      if (victim['age'] != null) _DetailRow(label: 'Ηλικία', value: '${victim['age']}'),
                      if (victim['dateOfBirth'] != null) _DetailRow(label: 'Ημ/νία γέννησης', value: _formatDate(victim['dateOfBirth'])),
                      if (victim['gender'] != null) _DetailRow(label: 'Φύλο', value: _genderLabel(victim['gender'])),
                      if (victim['address'] != null) _DetailRow(label: 'Διεύθυνση', value: victim['address']),
                      if (victim['city'] != null) _DetailRow(label: 'Πόλη', value: victim['city']),
                      if (victim['telephone'] != null) _DetailRow(label: 'Τηλέφωνο', value: victim['telephone']),
                      if (victim['emergencyContact'] != null) _DetailRow(label: 'Επαφή έκτακτης ανάγκης', value: victim['emergencyContact']),
                      if (victim['emergencyPhone'] != null) _DetailRow(label: 'Τηλ. επαφής έκτακτης ανάγκης', value: victim['emergencyPhone']),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              _SectionHeader(title: 'Ιατρικό ιστορικό'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      if (victim['chiefComplaint'] != null) _DetailRow(label: 'Κύριο σύμπτωμα', value: victim['chiefComplaint']),
                      if (victim['allergies'] != null) _DetailRow(label: 'Αλλεργίες', value: victim['allergies']),
                      if (victim['medications'] != null) _DetailRow(label: 'Φαρμακευτική αγωγή', value: victim['medications']),
                      if (victim['medicalHistory'] != null) _DetailRow(label: 'Ιατρικό ιστορικό', value: victim['medicalHistory']),
                      if (victim['chiefComplaint'] == null && victim['allergies'] == null && victim['medications'] == null && victim['medicalHistory'] == null)
                        const Text('Δεν καταγράφηκαν', style: TextStyle(color: Color(0xFF9CA3AF))),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              _SectionHeader(title: 'Αξιολόγηση'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      if (victim['gcsTotal'] != null)
                        _DetailRow(label: 'GCS', value: '${victim['gcsTotal']} (E${victim['gcsEye']} / V${victim['gcsVerbal']} / M${victim['gcsMotor']})'),
                      if (victim['avpu'] != null) _DetailRow(label: 'AVPU', value: victim['avpu']),
                      if (victim['locationNotes'] != null) _DetailRow(label: 'Σημ. τοποθεσίας', value: victim['locationNotes']),
                      if (victim['service'] != null)
                        _DetailRow(label: 'Υπηρεσία', value: (victim['service'] as Map)['name'] ?? '—'),
                      if (victim['notes'] != null) _DetailRow(label: 'Σημειώσεις', value: victim['notes']),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Card(
                child: ExpansionTile(
                  title: Text('Ζωτικά Σημεία (${vitals.length})', style: GoogleFonts.literata(fontSize: 15, fontWeight: FontWeight.w600)),
                  initiallyExpanded: _vitalsExpanded,
                  onExpansionChanged: (v) => setState(() => _vitalsExpanded = v),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canEdit)
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, color: Color(0xFFC62828)),
                          onPressed: _showAddVitalSignDialog,
                        ),
                      const Icon(Icons.expand_more),
                    ],
                  ),
                  children: vitals.isEmpty
                      ? [const Padding(padding: EdgeInsets.all(14), child: Text('Δεν υπάρχουν καταγραφές', style: TextStyle(color: Color(0xFF9CA3AF))))]
                      : vitals.map((vs) {
                          final sbp = vs['systolicBP'];
                          final dbp = vs['diastolicBP'];
                          final hr = vs['heartRate'];
                          final spo2 = vs['oxygenSat'];
                          final temp = vs['temperature'];
                          final pain = vs['painScore'];
                          final measuredAt = vs['measuredAt'] as String?;
                          final measuredBy = vs['measuredBy'];

                          return ListTile(
                            dense: true,
                            title: Text([
                              if (sbp != null && dbp != null) 'ΑΠ $sbp/$dbp',
                              if (hr != null) 'ΣΦ $hr',
                              if (spo2 != null) 'SpO2 $spo2%',
                              if (temp != null) '${temp}°C',
                              if (pain != null) 'Πόνος $pain/10',
                            ].join(' · '), style: GoogleFonts.inter(fontSize: 13)),
                            subtitle: Text([
                              if (measuredAt != null) _formatDateTime(measuredAt),
                              if (measuredBy != null) 'από $measuredBy',
                            ].join(' '), style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF9CA3AF))),
                            trailing: canEdit ? IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFB91C1C)),
                              onPressed: () async {
                                final err = await context.read<VictimProvider>().deleteVitalSign(widget.victimId, vs['id']);
                                if (err != null && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(err), backgroundColor: const Color(0xFFB91C1C)),
                                  );
                                }
                              },
                            ) : null,
                          );
                        }).toList(),
                ),
              ),

              const SizedBox(height: 8),

              Card(
                child: ExpansionTile(
                  title: Text('Θεραπείες (${treatments.length})', style: GoogleFonts.literata(fontSize: 15, fontWeight: FontWeight.w600)),
                  initiallyExpanded: _treatmentsExpanded,
                  onExpansionChanged: (v) => setState(() => _treatmentsExpanded = v),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canEdit)
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, color: Color(0xFFC62828)),
                          onPressed: _showAddTreatmentDialog,
                        ),
                      const Icon(Icons.expand_more),
                    ],
                  ),
                  children: treatments.isEmpty
                      ? [const Padding(padding: EdgeInsets.all(14), child: Text('Δεν υπάρχουν καταγραφές', style: TextStyle(color: Color(0xFF9CA3AF))))]
                      : treatments.map((t) {
                          final action = t['action'] ?? '';
                          final material = t['materialUsed'];
                          final performedAt = t['performedAt'] as String?;
                          final performedBy = t['performedBy'];
                          final item = t['item'] as Map?;

                          return ListTile(
                            dense: true,
                            title: Text(action, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                            subtitle: Text([
                              if (material != null) material,
                              if (item != null) 'Αντικείμενο: ${item['name']}',
                              if (performedAt != null) _formatDateTime(performedAt),
                              if (performedBy != null) 'από $performedBy',
                            ].join(' · '), style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF9CA3AF))),
                            trailing: canEdit ? IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFB91C1C)),
                              onPressed: () async {
                                final err = await context.read<VictimProvider>().deleteTreatment(widget.victimId, t['id']);
                                if (err != null && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(err), backgroundColor: const Color(0xFFB91C1C)),
                                  );
                                }
                              },
                            ) : null,
                          );
                        }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: (canEdit || canFinalize || canDelete)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    if (canEdit)
                      FilledButton.icon(
                        onPressed: () => context.push('/victims/create'), // edit not implemented separately — re-create flow
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Επεξεργασία'),
                      ),
                    if (canEdit) const SizedBox(width: 8),
                    if (canFinalize)
                      FilledButton.icon(
                        onPressed: _showFinalizeDialog,
                        icon: const Icon(Icons.lock_outline, size: 18),
                        label: const Text('Οριστικοποίηση'),
                      ),
                    if (canDelete) ...[
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
                        onPressed: _showDeleteDialog,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Διαγραφή'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : null,
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _formatDateTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _genderLabel(String? g) {
    switch (g) {
      case 'male': return 'Άνδρας';
      case 'female': return 'Γυναίκα';
      case 'other': return 'Άλλο';
      case 'unknown': return 'Άγνωστο';
      default: return g ?? '';
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(title, style: GoogleFonts.literata(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF1A1C1E))),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text('$label:', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280))),
          ),
          Expanded(child: Text(value, style: GoogleFonts.inter(fontSize: 13))),
        ],
      ),
    );
  }
}

class _FinalizedBanner extends StatelessWidget {
  final Map<String, dynamic> victim;

  const _FinalizedBanner({required this.victim});

  @override
  Widget build(BuildContext context) {
    final finalizedBy = victim['finalizedBy'] as Map?;
    final name = finalizedBy != null ? '${finalizedBy['forename']} ${finalizedBy['surname']}' : '—';
    final date = _formatDt(victim['finalizedAt'] as String?);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock, color: Color(0xFFD97706), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Οριστικοποιήθηκε από $name στις $date',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF92400E)),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDt(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
