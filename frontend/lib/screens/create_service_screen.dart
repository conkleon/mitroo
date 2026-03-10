import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/department_provider.dart';
import '../providers/service_provider.dart';
import '../services/api_client.dart';

class CreateServiceScreen extends StatefulWidget {
  /// Optional pre-selected department (from admin panel deep-link).
  final int? initialDepartmentId;
  final String? initialDepartmentName;

  /// When non-null, the screen operates in **edit** mode.
  final int? editServiceId;

  const CreateServiceScreen({
    super.key,
    this.initialDepartmentId,
    this.initialDepartmentName,
    this.editServiceId,
  });

  bool get isEditing => editServiceId != null;

  @override
  State<CreateServiceScreen> createState() => _CreateServiceScreenState();
}

class _CreateServiceScreenState extends State<CreateServiceScreen> {
  final _api = ApiClient();
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _carrierCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController(text: '0');
  final _hoursVolCtrl = TextEditingController(text: '0');
  final _hoursTrainingCtrl = TextEditingController(text: '0');
  final _hoursTrainersCtrl = TextEditingController(text: '0');
  final _hoursTEPCtrl = TextEditingController(text: '0');

  DateTime? _startAt;
  DateTime? _endAt;
  bool _saving = false;

  // Department selection
  int? _selectedDeptId;
  String? _selectedDeptName;
  List<Map<String, dynamic>> _departments = [];

  // Specialization selection
  List<dynamic> _allSpecs = [];
  final Set<int> _selectedSpecIds = {};
  // Original spec IDs when editing (to diff removals)
  Set<int> _originalSpecIds = {};

  bool _initialLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedDeptId = widget.initialDepartmentId;
    _selectedDeptName = widget.initialDepartmentName;
    _loadData();
  }

  Future<void> _loadData() async {
    // Load available departments for this admin
    final auth = context.read<AuthProvider>();
    if (auth.isAdmin) {
      await context.read<DepartmentProvider>().fetchDepartments();
      if (mounted) {
        _departments = context
            .read<DepartmentProvider>()
            .departments
            .cast<Map<String, dynamic>>();
      }
    } else {
      _departments = auth.missionAdminDepartments;
    }

    // Load all specializations
    try {
      final res = await _api.get('/specializations');
      if (res.statusCode == 200 && mounted) {
        _allSpecs = jsonDecode(res.body);
      }
    } catch (_) {}

    // If editing, load existing service data
    if (widget.isEditing) {
      try {
        final res = await _api.get('/services/${widget.editServiceId}');
        if (res.statusCode == 200 && mounted) {
          final svc = jsonDecode(res.body) as Map<String, dynamic>;
          _nameCtrl.text = svc['name'] ?? '';
          _descCtrl.text = svc['description'] ?? '';
          _locationCtrl.text = svc['location'] ?? '';
          _carrierCtrl.text = svc['carrier'] ?? '';
          _hoursCtrl.text = '${svc['defaultHours'] ?? 0}';
          _hoursVolCtrl.text = '${svc['defaultHoursVol'] ?? 0}';
          _hoursTrainingCtrl.text = '${svc['defaultHoursTraining'] ?? 0}';
          _hoursTrainersCtrl.text = '${svc['defaultHoursTrainers'] ?? 0}';
          _hoursTEPCtrl.text = '${svc['defaultHoursTEP'] ?? 0}';
          if (svc['startAt'] != null) _startAt = DateTime.tryParse(svc['startAt']);
          if (svc['endAt'] != null) _endAt = DateTime.tryParse(svc['endAt']);
          _selectedDeptId = svc['departmentId'] as int?;
          final dept = svc['department'] as Map<String, dynamic>?;
          if (dept != null) _selectedDeptName = dept['name'] as String?;
          // Pre-select existing visibility specializations
          final vis = svc['visibility'] as List<dynamic>? ?? [];
          for (final v in vis) {
            final specId = v['specializationId'] as int?;
            if (specId != null) _selectedSpecIds.add(specId);
          }
          _originalSpecIds = Set<int>.from(_selectedSpecIds);
        }
      } catch (_) {}
    }

    if (mounted) setState(() => _initialLoading = false);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _carrierCtrl.dispose();
    _hoursCtrl.dispose();
    _hoursVolCtrl.dispose();
    _hoursTrainingCtrl.dispose();
    _hoursTrainersCtrl.dispose();
    _hoursTEPCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null || !mounted) return;

    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startAt = dt;
      } else {
        _endAt = dt;
      }
    });
  }

  String _formatDt(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDeptId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Παρακαλώ επιλέξτε τμήμα')),
      );
      return;
    }
    setState(() => _saving = true);

    final data = <String, dynamic>{
      'departmentId': _selectedDeptId,
      'name': _nameCtrl.text.trim(),
    };
    if (_descCtrl.text.trim().isNotEmpty) data['description'] = _descCtrl.text.trim();
    if (_locationCtrl.text.trim().isNotEmpty) data['location'] = _locationCtrl.text.trim();
    if (_carrierCtrl.text.trim().isNotEmpty) data['carrier'] = _carrierCtrl.text.trim();
    data['defaultHours'] = int.tryParse(_hoursCtrl.text) ?? 0;
    data['defaultHoursVol'] = int.tryParse(_hoursVolCtrl.text) ?? 0;
    data['defaultHoursTraining'] = int.tryParse(_hoursTrainingCtrl.text) ?? 0;
    data['defaultHoursTrainers'] = int.tryParse(_hoursTrainersCtrl.text) ?? 0;
    data['defaultHoursTEP'] = int.tryParse(_hoursTEPCtrl.text) ?? 0;
    if (_startAt != null) data['startAt'] = _startAt!.toUtc().toIso8601String();
    if (_endAt != null) data['endAt'] = _endAt!.toUtc().toIso8601String();

    if (widget.isEditing) {
      // ── Update existing service ──
      final err = await context.read<ServiceProvider>().update(widget.editServiceId!, data);
      if (!mounted) return;
      if (err != null) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
        return;
      }

      final sid = widget.editServiceId!;

      // Remove specs that were deselected
      final toRemove = _originalSpecIds.difference(_selectedSpecIds);
      for (final specId in toRemove) {
        try {
          await _api.delete('/services/$sid/visibility/$specId');
        } catch (_) {}
      }

      // Add newly selected specs
      final toAdd = _selectedSpecIds.difference(_originalSpecIds);
      for (final specId in toAdd) {
        try {
          await _api.post('/services/$sid/visibility',
              body: {'specializationId': specId});
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Η υπηρεσία ενημερώθηκε')),
      );
      context.pop();
    } else {
      // ── Create new service ──
      // create() returns int (service ID) on success, or String (error).
      final result = await context.read<ServiceProvider>().create(data);
      if (!mounted) return;

      if (result is String) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
        return;
      }

      final serviceId = result as int?;

      // Assign specialization visibility requirements
      if (serviceId != null && _selectedSpecIds.isNotEmpty) {
        for (final specId in _selectedSpecIds) {
          try {
            await _api.post('/services/$serviceId/visibility',
                body: {'specializationId': specId});
          } catch (_) {}
        }
      }

      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Η υπηρεσία δημιουργήθηκε')),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final isEditing = widget.isEditing;
    final title = isEditing ? 'Επεξεργασία Υπηρεσίας' : 'Νέα Υπηρεσία';

    if (_initialLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: Text(title, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(title, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 800;
            final hPad = isWide ? ((constraints.maxWidth - 700) / 2).clamp(20.0, 200.0) : 20.0;

            return Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 24),
            children: [
              // ── Department selector ──
              Text('Τμήμα *', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: _selectedDeptId,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business),
                  hintText: 'Επιλογή τμήματος',
                ),
                items: _departments.map((d) {
                  return DropdownMenuItem<int>(
                    value: d['id'] as int,
                    child: Text(d['name'] ?? ''),
                  );
                }).toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedDeptId = v;
                    _selectedDeptName = _departments
                        .firstWhere((d) => d['id'] == v, orElse: () => {})['name'] as String?;
                  });
                },
                validator: (v) => v == null ? 'Απαιτείται' : null,
              ),
              const SizedBox(height: 20),

              // ── Name ──
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Όνομα Υπηρεσίας *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.miscellaneous_services),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Απαιτείται' : null,
              ),
              const SizedBox(height: 16),

              // ── Description ──
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Περιγραφή',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),

              // ── Location & Carrier ──
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _locationCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Τοποθεσία',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _carrierCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Φορέας',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.groups),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Specialization requirements ──
              Text('Απαιτούμενες Ειδικεύσεις', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Μόνο χρήστες με αυτές τις ειδικεύσεις θα βλέπουν αυτή την υπηρεσία',
                  style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
              const SizedBox(height: 8),
              if (_allSpecs.isEmpty)
                const Text('Φόρτωση ειδικεύσεων...', style: TextStyle(color: Colors.grey))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _allSpecs.map((s) {
                    final specId = s['id'] as int;
                    final selected = _selectedSpecIds.contains(specId);
                    return FilterChip(
                      label: Text(s['name'] ?? ''),
                      selected: selected,
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            _selectedSpecIds.add(specId);
                          } else {
                            _selectedSpecIds.remove(specId);
                          }
                        });
                      },
                      selectedColor: cs.primary.withAlpha(30),
                      checkmarkColor: cs.primary,
                      avatar: selected ? null : const Icon(Icons.school, size: 16),
                    );
                  }).toList(),
                ),
              if (_selectedSpecIds.isEmpty) ...[
                const SizedBox(height: 4),
                Text('Καμία ειδίκευση — η υπηρεσία είναι ορατή σε όλα τα μέλη',
                    style: tt.bodySmall?.copyWith(color: Colors.orange.shade700, fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 20),

              // ── Date/Time pickers ──
              Text('Πρόγραμμα', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDateTime(isStart: true),
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(_startAt != null ? _formatDt(_startAt!) : 'Έναρξη'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDateTime(isStart: false),
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(_endAt != null ? _formatDt(_endAt!) : 'Λήξη'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Hours ──
              Text('Προεπιλεγμένες Ώρες', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _hoursCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Ώρες',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _hoursVolCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Εθελ.',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _hoursTrainingCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Εκπαίδ.',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _hoursTrainersCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Εκπαιδευτές',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _hoursTEPCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'ΤΕΠ',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // ── Submit ──
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check),
                  label: Text(_saving
                      ? (isEditing ? 'Αποθήκευση...' : 'Δημιουργία...')
                      : (isEditing ? 'Αποθήκευση' : 'Δημιουργία Υπηρεσίας')),
                ),
              ),
            ],
          ),
        );
          },
        ),
      ),
    );
  }
}
