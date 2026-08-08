import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/department_provider.dart';
import '../providers/mission_report_provider.dart';

import 'package:mitroo_frontend/theme/theme.dart';

const _defaultMissionListLimit = 20;

class MissionReportSelectionScreen extends StatefulWidget {
  const MissionReportSelectionScreen({super.key});

  @override
  State<MissionReportSelectionScreen> createState() =>
      _MissionReportSelectionScreenState();
}

class _MissionReportSelectionScreenState
    extends State<MissionReportSelectionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // ── Mission selection tab ────────────────────────
  final Set<int> _selectedMissionIds = {};
  final _searchController = TextEditingController();
  String _search = '';
  DateTime? _listFromDate;
  DateTime? _listToDate;
  Timer? _debounceTimer;

  // ── Date-range (aggregate) tab ───────────────────
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _departmentFilter;

  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    Future.microtask(() {
      if (!mounted) return;
      _fetchMissionList();
      final deptProv = context.read<DepartmentProvider>();
      if (deptProv.departments.isEmpty) deptProv.fetchDepartments();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _fetchMissionList() {
    final hasFilters =
        _search.isNotEmpty || _listFromDate != null || _listToDate != null;
    context.read<MissionReportProvider>().fetchMissions(
          search: _search.isEmpty ? null : _search,
          from: _listFromDate?.toUtc().toIso8601String(),
          to: _listToDate != null
              ? DateTime(_listToDate!.year, _listToDate!.month,
                      _listToDate!.day, 23, 59, 59)
                  .toUtc()
                  .toIso8601String()
              : null,
          limit: hasFilters ? null : _defaultMissionListLimit,
        );
  }

  void _onSearchChanged(String value) {
    setState(() => _search = value);
    _debounceTimer?.cancel();
    _debounceTimer =
        Timer(const Duration(milliseconds: 400), _fetchMissionList);
  }

  Future<void> _pickListDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_listFromDate ?? now) : (_listToDate ?? now),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _listFromDate = picked;
      } else {
        _listToDate = picked;
      }
    });
    _fetchMissionList();
  }

  void _clearListDate({required bool isFrom}) {
    setState(() {
      if (isFrom) {
        _listFromDate = null;
      } else {
        _listToDate = null;
      }
    });
    _fetchMissionList();
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
      if (_selectedMissionIds.isEmpty) {
        setState(() => _error = 'Επιλέξτε τουλάχιστον μία αποστολή');
        return;
      }
      body = {'serviceIds': _selectedMissionIds.toList()};
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

  String _missionSubtitle(Map<String, dynamic> m) {
    final dept = (m['department'] as Map<String, dynamic>?)?['name'] as String?;
    final start = DateTime.tryParse(m['startAt'] as String? ?? '');
    final parts = <String>[
      if (start != null) '${start.day}/${start.month}/${start.year}',
      if (dept != null && dept.isNotEmpty) dept,
    ];
    return parts.join(' • ');
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
            Tab(text: 'Αποστολές'),
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
                _buildMissionListTab(provider),
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
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Δημιουργία Αναφοράς'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateChip({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    final isSet = value != null;
    final text = isSet
        ? '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}'
        : label;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isSet
              ? Theme.of(context).colorScheme.primary.withAlpha(20)
              : AppColors.gray100,
          borderRadius: AppRadius.r12,
          border: Border.all(
            color: isSet
                ? Theme.of(context).colorScheme.primary.withAlpha(80)
                : AppColors.gray200,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 14,
                color: isSet
                    ? Theme.of(context).colorScheme.primary
                    : AppColors.gray500),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppFontSize.base,
                  fontWeight: AppFontWeight.medium,
                  color: isSet
                      ? Theme.of(context).colorScheme.primary
                      : AppColors.gray500,
                ),
              ),
            ),
            if (isSet)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close,
                    size: 14, color: Theme.of(context).colorScheme.primary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissionListTab(MissionReportProvider provider) {
    final hasFilters =
        _search.isNotEmpty || _listFromDate != null || _listToDate != null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Αναζήτηση αποστολών...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: AppRadius.r12),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: _buildDateChip(
                  label: 'Από ημερομηνία',
                  value: _listFromDate,
                  onTap: () => _pickListDate(isFrom: true),
                  onClear: () => _clearListDate(isFrom: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDateChip(
                  label: 'Έως ημερομηνία',
                  value: _listToDate,
                  onTap: () => _pickListDate(isFrom: false),
                  onClear: () => _clearListDate(isFrom: false),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hasFilters
                      ? '${provider.missions.length} αποτελέσματα'
                      : 'Οι $_defaultMissionListLimit πιο πρόσφατες αποστολές',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.gray400),
                ),
              ),
              if (_selectedMissionIds.isNotEmpty)
                Text(
                  '${_selectedMissionIds.length} επιλεγμένες',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: AppFontWeight.bold,
                      ),
                ),
            ],
          ),
        ),
        Expanded(
          child: provider.loadingMissions
              ? const Center(child: CircularProgressIndicator())
              : provider.missions.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: provider.missions.length,
                      itemBuilder: (context, i) {
                        final map =
                            provider.missions[i] as Map<String, dynamic>;
                        final id = map['id'] as int;
                        return CheckboxListTile(
                          value: _selectedMissionIds.contains(id),
                          title: Text(map['name'] as String? ?? ''),
                          subtitle: Text(_missionSubtitle(map)),
                          onChanged: (sel) {
                            setState(() {
                              if (sel == true) {
                                _selectedMissionIds.add(id);
                              } else {
                                _selectedMissionIds.remove(id);
                              }
                            });
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox, size: 64, color: AppColors.gray300),
          const SizedBox(height: 12),
          Text('Δεν βρέθηκαν αποστολές',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: AppColors.gray500)),
        ],
      ),
    );
  }

  Widget _buildDateRangeTab(AuthProvider auth) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          title: const Text('Από'),
          subtitle: Text(
              _fromDate?.toLocal().toString().split(' ').first ?? 'Επιλογή'),
          trailing: const Icon(Icons.calendar_today),
          onTap: () => _pickDate(isFrom: true),
        ),
        ListTile(
          title: const Text('Έως'),
          subtitle:
              Text(_toDate?.toLocal().toString().split(' ').first ?? 'Επιλογή'),
          trailing: const Icon(Icons.calendar_today),
          onTap: () => _pickDate(isFrom: false),
        ),
        if (auth.isAdmin) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<int?>(
            value: _departmentFilter,
            decoration: const InputDecoration(labelText: 'Τμήμα (προαιρετικό)'),
            items: [
              const DropdownMenuItem<int?>(
                  value: null, child: Text('Όλα τα τμήματα')),
              ...context.watch<DepartmentProvider>().departments.map((d) {
                final map = d as Map<String, dynamic>;
                return DropdownMenuItem<int?>(
                  value: map['id'] as int,
                  child: Text(map['name'] as String? ?? 'Τμήμα'),
                );
              }),
            ],
            onChanged: (value) => setState(() => _departmentFilter = value),
          ),
        ],
      ],
    );
  }
}
