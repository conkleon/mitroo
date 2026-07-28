import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/mission_report_provider.dart';

class MissionReportSelectionScreen extends StatefulWidget {
  const MissionReportSelectionScreen({super.key});

  @override
  State<MissionReportSelectionScreen> createState() => _MissionReportSelectionScreenState();
}

class _MissionReportSelectionScreenState extends State<MissionReportSelectionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int? _singleMissionId;
  final Set<int> _multiMissionIds = {};
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _departmentFilter;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    Future.microtask(() {
      if (!mounted) return;
      context.read<MissionReportProvider>().fetchMissions();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_fromDate ?? now) : (_toDate ?? now),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
  }

  Future<void> _generate() async {
    setState(() => _error = null);
    final provider = context.read<MissionReportProvider>();

    Map<String, dynamic> body;
    if (_tabController.index == 0) {
      if (_singleMissionId == null) {
        setState(() => _error = 'Επιλέξτε μία αποστολή');
        return;
      }
      body = {'serviceIds': [_singleMissionId]};
    } else if (_tabController.index == 1) {
      if (_multiMissionIds.isEmpty) {
        setState(() => _error = 'Επιλέξτε τουλάχιστον μία αποστολή');
        return;
      }
      body = {'serviceIds': _multiMissionIds.toList()};
    } else {
      if (_fromDate == null || _toDate == null) {
        setState(() => _error = 'Επιλέξτε εύρος ημερομηνιών');
        return;
      }
      body = {
        'from': _fromDate!.toUtc().toIso8601String(),
        'to': _toDate!.toUtc().toIso8601String(),
        if (_departmentFilter != null) 'departmentId': _departmentFilter,
      };
    }

    final ok = await provider.generateReport(body);
    if (!mounted) return;
    if (ok) {
      context.push('/admin/mission-report/result');
    } else {
      setState(() => _error = provider.reportError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<MissionReportProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Αναφορά Αποστολών'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Μία Αποστολή'),
            Tab(text: 'Πολλές Αποστολές'),
            Tab(text: 'Εύρος Ημερομηνιών'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSingleTab(provider),
                _buildMultiTab(provider),
                _buildDateRangeTab(auth),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: provider.generating ? null : _generate,
                child: provider.generating
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Δημιουργία Αναφοράς'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleTab(MissionReportProvider provider) {
    if (provider.loadingMissions) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<int>(
          value: _singleMissionId,
          decoration: const InputDecoration(labelText: 'Αποστολή'),
          items: provider.missions.map((m) {
            final map = m as Map<String, dynamic>;
            return DropdownMenuItem<int>(
              value: map['id'] as int,
              child: Text(map['name'] as String),
            );
          }).toList(),
          onChanged: (value) => setState(() => _singleMissionId = value),
        ),
      ],
    );
  }

  Widget _buildMultiTab(MissionReportProvider provider) {
    if (provider.loadingMissions) return const Center(child: CircularProgressIndicator());
    return ListView(
      children: provider.missions.map((m) {
        final map = m as Map<String, dynamic>;
        final id = map['id'] as int;
        return CheckboxListTile(
          title: Text(map['name'] as String),
          value: _multiMissionIds.contains(id),
          onChanged: (sel) {
            setState(() {
              if (sel == true) {
                _multiMissionIds.add(id);
              } else {
                _multiMissionIds.remove(id);
              }
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildDateRangeTab(AuthProvider auth) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          title: const Text('Από'),
          subtitle: Text(_fromDate?.toLocal().toString().split(' ').first ?? 'Επιλογή'),
          trailing: const Icon(Icons.calendar_today),
          onTap: () => _pickDate(isFrom: true),
        ),
        ListTile(
          title: const Text('Έως'),
          subtitle: Text(_toDate?.toLocal().toString().split(' ').first ?? 'Επιλογή'),
          trailing: const Icon(Icons.calendar_today),
          onTap: () => _pickDate(isFrom: false),
        ),
        if (auth.isAdmin) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<int?>(
            value: _departmentFilter,
            decoration: const InputDecoration(labelText: 'Τμήμα (προαιρετικό)'),
            items: const [
              DropdownMenuItem<int?>(value: null, child: Text('Όλα τα τμήματα')),
            ],
            onChanged: (value) => setState(() => _departmentFilter = value),
          ),
        ],
      ],
    );
  }
}
