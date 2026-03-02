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

  const CreateServiceScreen({
    super.key,
    this.initialDepartmentId,
    this.initialDepartmentName,
  });

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

    if (mounted) setState(() {});
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
        const SnackBar(content: Text('Please select a department')),
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
    if (_startAt != null) data['startAt'] = _startAt!.toUtc().toIso8601String();
    if (_endAt != null) data['endAt'] = _endAt!.toUtc().toIso8601String();

    // 1. Create the service
    final err = await context.read<ServiceProvider>().create(data);
    if (!mounted) return;

    if (err != null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }

    // 2. Find the newly created service's ID (latest in the provider)
    final services = context.read<ServiceProvider>().services;
    final newService = services.isNotEmpty ? services.last : null;
    final serviceId = newService?['id'] as int?;

    // 3. Assign specialization visibility requirements
    if (serviceId != null && _selectedSpecIds.isNotEmpty) {
      for (final specId in _selectedSpecIds) {
        try {
          await _api.post('/services/$serviceId/visibility', body: {'specializationId': specId});
        } catch (_) {}
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Service created successfully')),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text('New Service', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              // ── Department selector ──
              Text('Department *', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: _selectedDeptId,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business),
                  hintText: 'Select department',
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
                validator: (v) => v == null ? 'Required' : null,
              ),
              const SizedBox(height: 20),

              // ── Name ──
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Service Name *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.miscellaneous_services),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              // ── Description ──
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description',
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
                        labelText: 'Location',
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
                        labelText: 'Carrier',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.groups),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Specialization requirements ──
              Text('Required Specializations', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Only users with these specializations will see this service',
                  style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
              const SizedBox(height: 8),
              if (_allSpecs.isEmpty)
                const Text('Loading specializations...', style: TextStyle(color: Colors.grey))
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
                Text('No specializations selected — service visible to all department members',
                    style: tt.bodySmall?.copyWith(color: Colors.orange.shade700, fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 20),

              // ── Date/Time pickers ──
              Text('Schedule', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDateTime(isStart: true),
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(_startAt != null ? _formatDt(_startAt!) : 'Start date/time'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDateTime(isStart: false),
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(_endAt != null ? _formatDt(_endAt!) : 'End date/time'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Hours ──
              Text('Default Hours', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _hoursCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Hours',
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
                        labelText: 'Vol. Hours',
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
                        labelText: 'Training',
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
                        labelText: 'Trainers',
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
                  label: Text(_saving ? 'Creating...' : 'Create Service'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
