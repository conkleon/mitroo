import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/mission_report_provider.dart';

class MissionReportResultScreen extends StatefulWidget {
  const MissionReportResultScreen({super.key});

  @override
  State<MissionReportResultScreen> createState() => _MissionReportResultScreenState();
}

class _MissionReportResultScreenState extends State<MissionReportResultScreen> {
  late final TextEditingController _narrativeController;
  String? _exportError;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final provider = context.read<MissionReportProvider>();
    _narrativeController = TextEditingController(text: provider.narrativeText ?? '');
  }

  @override
  void dispose() {
    _narrativeController.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _exportError = null;
    });
    final provider = context.read<MissionReportProvider>();
    provider.setNarrativeText(_narrativeController.text);
    final error = await provider.exportPdf();
    if (!mounted) return;
    setState(() {
      _exporting = false;
      _exportError = error;
    });
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MissionReportProvider>();
    final data = provider.structuredData;

    if (data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Αναφορά Αποστολής')),
        body: const Center(child: Text('Δεν υπάρχουν δεδομένα αναφοράς.')),
      );
    }

    final missions = data['missions'] as List<dynamic>? ?? [];
    final personnel = data['personnel'] as List<dynamic>? ?? [];
    final vehicles = data['vehicles'] as List<dynamic>? ?? [];
    final items = data['items'] as List<dynamic>? ?? [];
    final totals = data['totals'] as Map<String, dynamic>? ?? {};

    return Scaffold(
      appBar: AppBar(title: const Text('Αναφορά Αποστολής')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('ΔΕΛΤΙΟ ΤΥΠΟΥ', [
            if (provider.narrativeError != null) ...[
              Text(provider.narrativeError!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  // Re-request narrative generation with the same mission set.
                  final missionIds = missions
                      .map((m) => (m as Map<String, dynamic>)['id'] as int)
                      .toList();
                  await provider.generateReport({'serviceIds': missionIds});
                  _narrativeController.text = provider.narrativeText ?? '';
                },
                child: const Text('Δημιουργία Ξανά'),
              ),
            ] else
              TextField(
                controller: _narrativeController,
                maxLines: 8,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
          ]),
          _section('Αποστολές', missions.map((m) {
            final map = m as Map<String, dynamic>;
            return Text('${map['name']} — ${map['departmentName']}');
          }).toList()),
          _section('Προσωπικό (${totals['personnelCount'] ?? 0})', personnel.map((p) {
            final map = p as Map<String, dynamic>;
            return Text('${map['fullName']} (${map['rank']}) — ${map['hours']} ώρες');
          }).toList()),
          _section('Οχήματα (${totals['vehicleCount'] ?? 0})', vehicles.map((v) {
            final map = v as Map<String, dynamic>;
            return Text('${map['vehicleName']} — οδηγός: ${map['driverFullName']}');
          }).toList()),
          _section('Υλικό (${totals['itemCount'] ?? 0})', items.map((i) {
            final map = i as Map<String, dynamic>;
            return Text('${map['itemName']} — ${map['userFullName']}');
          }).toList()),
          _section('Διασωθέντες / Τραυματίες', [
            Text('Σύνολο: ${totals['victimCount'] ?? 0}'),
          ]),
          if (_exportError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_exportError!, style: const TextStyle(color: Colors.red)),
            ),
          FilledButton.icon(
            onPressed: _exporting ? null : _export,
            icon: _exporting
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf),
            label: const Text('Εξαγωγή PDF'),
          ),
        ],
      ),
    );
  }
}
