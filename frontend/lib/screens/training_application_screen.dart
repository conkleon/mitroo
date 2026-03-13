import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_client.dart';

class TrainingApplicationScreen extends StatefulWidget {
  const TrainingApplicationScreen({super.key});

  @override
  State<TrainingApplicationScreen> createState() => _TrainingApplicationScreenState();
}

class _TrainingApplicationScreenState extends State<TrainingApplicationScreen> {
  final _api = ApiClient();
  final _formKey = GlobalKey<FormState>();

  final _forenameCtrl = TextEditingController();
  final _surnameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phonePrimaryCtrl = TextEditingController();
  final _phoneSecondaryCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _extraInfoCtrl = TextEditingController();

  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _rootSpecs = [];
  int? _selectedDeptId;
  String? _selectedDeptName;
  int? _selectedSpecId;
  DateTime? _birthDate;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void dispose() {
    _forenameCtrl.dispose();
    _surnameCtrl.dispose();
    _emailCtrl.dispose();
    _phonePrimaryCtrl.dispose();
    _phoneSecondaryCtrl.dispose();
    _addressCtrl.dispose();
    _extraInfoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get('/training-applications/meta');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _departments = (data['departments'] as List).cast<Map<String, dynamic>>();
        _rootSpecs = (data['rootSpecializations'] as List).cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25, 1, 1),
      firstDate: DateTime(1940, 1, 1),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() => _birthDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDeptId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Παρακαλώ επιλέξτε τμήμα.')),
      );
      return;
    }
    if (_selectedSpecId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Παρακαλώ επιλέξτε ειδίκευση.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final body = <String, dynamic>{
        'forename': _forenameCtrl.text.trim(),
        'surname': _surnameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phonePrimary': _phonePrimaryCtrl.text.trim(),
        'departmentId': _selectedDeptId,
        'specializationId': _selectedSpecId,
      };

      if (_phoneSecondaryCtrl.text.trim().isNotEmpty) {
        body['phoneSecondary'] = _phoneSecondaryCtrl.text.trim();
      }
      if (_addressCtrl.text.trim().isNotEmpty) {
        body['address'] = _addressCtrl.text.trim();
      }
      if (_extraInfoCtrl.text.trim().isNotEmpty) {
        body['extraInfo'] = _extraInfoCtrl.text.trim();
      }
      if (_birthDate != null) {
        body['birthDate'] = DateTime(
          _birthDate!.year,
          _birthDate!.month,
          _birthDate!.day,
          12,
        ).toUtc().toIso8601String();
      }

      final res = await _api.post('/training-applications', body: body);
      if (!mounted) return;

      if (res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Η αίτηση καταχωρήθηκε. Θα λάβετε επικοινωνία από το τμήμα επιλογής σας.'),
          ),
        );
        _formKey.currentState?.reset();
        _forenameCtrl.clear();
        _surnameCtrl.clear();
        _emailCtrl.clear();
        _phonePrimaryCtrl.clear();
        _phoneSecondaryCtrl.clear();
        _addressCtrl.clear();
        _extraInfoCtrl.clear();
        setState(() {
          _selectedDeptId = null;
          _selectedDeptName = null;
          _selectedSpecId = null;
          _birthDate = null;
        });
      } else {
        final err = jsonDecode(res.body)['error'] ?? 'Αποτυχία υποβολής αίτησης';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.toString())));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Σφάλμα: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_rootSpecs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Αίτηση Εκπαίδευσης')),
        body: const Center(child: Text('Δεν υπάρχουν διαθέσιμες ριζικές ειδικεύσεις.')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Αίτηση Εκπαίδευσης'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Θέλω να εκπαιδευτώ στον Ελληνικό Ερυθρό Σταυρό',
                      style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Συμπληρώστε τη φόρμα συμμετοχής εκπαίδευσης.',
                      style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: _selectedSpecId,
                    decoration: const InputDecoration(
                      labelText: 'Ειδίκευση *',
                      border: OutlineInputBorder(),
                    ),
                    items: _rootSpecs.map((s) {
                      return DropdownMenuItem<int>(
                        value: s['id'] as int,
                        child: Text((s['name'] ?? '').toString()),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedSpecId = value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _forenameCtrl,
                    decoration: const InputDecoration(labelText: 'Όνομα *', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Υποχρεωτικό' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _surnameCtrl,
                    decoration: const InputDecoration(labelText: 'Επώνυμο *', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Υποχρεωτικό' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email *', border: OutlineInputBorder()),
                    validator: (v) => (v == null || !v.contains('@')) ? 'Εισάγετε έγκυρο email' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phonePrimaryCtrl,
                    decoration: const InputDecoration(labelText: 'Κινητό Τηλέφωνο *', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().length < 5) ? 'Υποχρεωτικό' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneSecondaryCtrl,
                    decoration: const InputDecoration(labelText: 'Δευτερεύον Τηλέφωνο', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  Autocomplete<Map<String, dynamic>>(
                    displayStringForOption: (d) => d['name']?.toString() ?? '',
                    optionsBuilder: (textEditingValue) {
                      final q = textEditingValue.text.toLowerCase().trim();
                      if (q.isEmpty) return _departments;
                      return _departments.where((d) => (d['name'] ?? '').toString().toLowerCase().contains(q));
                    },
                    onSelected: (d) {
                      setState(() {
                        _selectedDeptId = d['id'] as int;
                        _selectedDeptName = d['name']?.toString();
                      });
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      if (_selectedDeptName != null && controller.text.isEmpty) {
                        controller.text = _selectedDeptName!;
                      }
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: 'Τμήμα Επιλογής *',
                          hintText: 'Αναζήτηση τμήματος...',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: controller.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    controller.clear();
                                    setState(() {
                                      _selectedDeptId = null;
                                      _selectedDeptName = null;
                                    });
                                  },
                                )
                              : null,
                        ),
                        onChanged: (_) {
                          setState(() {
                            _selectedDeptId = null;
                            _selectedDeptName = null;
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _pickBirthDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Ημερομηνία Γέννησης',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                        _birthDate == null
                            ? 'Επιλογή ημερομηνίας'
                            : '${_birthDate!.day}/${_birthDate!.month}/${_birthDate!.year}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Διεύθυνση', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _extraInfoCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Επιπλέον Στοιχεία', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Με την υποβολή θα λάβετε ενημέρωση ότι η φόρμα παραλήφθηκε και θα περιμένετε επικοινωνία από το τμήμα επιλογής σας.',
                    style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: const Icon(Icons.send, size: 18),
                      label: _submitting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Υποβολή Αίτησης'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
