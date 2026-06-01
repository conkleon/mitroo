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
  final _maxParticipantsCtrl = TextEditingController(text: '100');

  DateTime? _startAt;
  DateTime? _endAt;
  bool _saving = false;

  // Department selection
  int? _selectedDeptId;
  String? _selectedDeptName;
  List<Map<String, dynamic>> _departments = [];

  // Service type selection
  List<dynamic> _serviceTypes = [];
  int? _selectedServiceTypeId;

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

    // Load all service types
    try {
      final res = await _api.get('/service-types');
      if (res.statusCode == 200 && mounted) {
        _serviceTypes = jsonDecode(res.body);
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
          _maxParticipantsCtrl.text = '${svc['maxParticipants'] ?? 100}';
          if (svc['startAt'] != null) _startAt = DateTime.tryParse(svc['startAt']);
          if (svc['endAt'] != null) _endAt = DateTime.tryParse(svc['endAt']);
          _selectedDeptId = svc['departmentId'] as int?;
          final dept = svc['department'] as Map<String, dynamic>?;
          if (dept != null) _selectedDeptName = dept['name'] as String?;
          _selectedServiceTypeId = svc['serviceTypeId'] as int?;
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
    _maxParticipantsCtrl.dispose();
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
    data['maxParticipants'] = int.tryParse(_maxParticipantsCtrl.text) ?? 100;
    if (_startAt != null) data['startAt'] = _startAt!.toUtc().toIso8601String();
    if (_endAt != null) data['endAt'] = _endAt!.toUtc().toIso8601String();

    if (_selectedServiceTypeId != null) data['serviceTypeId'] = _selectedServiceTypeId;

    if (widget.isEditing) {
      // ── Update existing service ──
      final err = await context.read<ServiceProvider>().update(widget.editServiceId!, data);
      if (!mounted) return;
      if (err != null) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
        return;
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

      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Η υπηρεσία δημιουργήθηκε')),
      );
      context.pop();
    }
  }

  Widget _hourCard({
    required TextEditingController ctrl,
    required IconData icon,
    required Color color,
    required String label,
    required String subtitle,
  }) {
    return Container(
      width: 150,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF374151))),
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
          const SizedBox(height: 10),
          TextFormField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: color),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: color.withAlpha(60))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: color.withAlpha(60))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: color, width: 2)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final isEditing = widget.isEditing;
    final title = isEditing ? 'Επεξεργασία Υπηρεσίας' : 'Νέα Υπηρεσία';

    if (_initialLoading) {
      return Scaffold(
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

              // ── Service type dropdown ──
              Text('Τύπος Υπηρεσίας', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Επιλέξτε τον τύπο της υπηρεσίας',
                  style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
              const SizedBox(height: 8),
              if (_serviceTypes.isEmpty)
                const Text('Φόρτωση τύπων...', style: TextStyle(color: Color(0xFF6B7280)))
              else
                DropdownButtonFormField<int>(
                  value: _selectedServiceTypeId,
                  decoration: const InputDecoration(
                    labelText: 'Τύπος Υπηρεσίας',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int>(
                      value: null,
                      child: Text('— Κανένας (ορατό σε όλους) —'),
                    ),
                    ..._serviceTypes.map((t) => DropdownMenuItem<int>(
                      value: t['id'] as int,
                      child: Text(t['name'] ?? ''),
                    )),
                  ],
                  onChanged: (v) => setState(() => _selectedServiceTypeId = v),
                ),
              if (_selectedServiceTypeId == null) ...[
                const SizedBox(height: 4),
                Text('Χωρίς τύπο — η υπηρεσία είναι ορατή σε όλα τα μέλη',
                    style: tt.bodySmall?.copyWith(color: Color(0xFFC2410C), fontStyle: FontStyle.italic)),
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

              Text('Μέγιστοι Εθελοντές', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SizedBox(
                width: 200,
                child: TextFormField(
                  controller: _maxParticipantsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Μέγιστος αριθμός',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Hours ──
              Text('Προεπιλεγμένες Ώρες', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Ώρες που αποδίδονται αυτόματα σε κάθε συμμετέχοντα',
                  style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _hourCard(ctrl: _hoursCtrl, icon: Icons.access_time_rounded,
                        color: const Color(0xFF3B82F6), label: 'Υπηρεσία', subtitle: 'Ώρες υπηρεσίας'),
                    _hourCard(ctrl: _hoursVolCtrl, icon: Icons.volunteer_activism,
                        color: const Color(0xFF10B981), label: 'Εθελοντικές', subtitle: 'Ώρες εθελοντισμού'),
                    _hourCard(ctrl: _hoursTrainingCtrl, icon: Icons.school_rounded,
                        color: const Color(0xFF8B5CF6), label: 'Επανεκπαίδευση', subtitle: 'Ώρες ως εκπαιδευόμενος'),
                    _hourCard(ctrl: _hoursTrainersCtrl, icon: Icons.co_present,
                        color: const Color(0xFFF59E0B), label: 'Εκπαιδευτές', subtitle: 'Ώρες ως εκπαιδευτής'),
                    _hourCard(ctrl: _hoursTEPCtrl, icon: Icons.local_hospital_rounded,
                        color: const Color(0xFFEF4444), label: 'ΤΕΠ', subtitle: 'Ώρες τμήματος επειγόντων'),
                  ],
                ),
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
