import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/victim_provider.dart';
import '../services/api_client.dart';
import 'dart:convert';

class CreateVictimScreen extends StatefulWidget {
  final int? prefilledServiceId;

  const CreateVictimScreen({super.key, this.prefilledServiceId});

  @override
  State<CreateVictimScreen> createState() => _CreateVictimScreenState();
}

class _CreateVictimScreenState extends State<CreateVictimScreen> {
  int _currentStep = 0;
  final _api = ApiClient();

  // Step 0: Στοιχεία
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  DateTime? _dateOfBirth;
  String? _gender;
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _postalCodeCtrl = TextEditingController();
  final _telephoneCtrl = TextEditingController();
  final _emergencyContactCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();

  // Step 1: Ιατρικό ιστορικό
  final _chiefComplaintCtrl = TextEditingController();
  final _allergiesCtrl = TextEditingController();
  final _medicationsCtrl = TextEditingController();
  final _medicalHistoryCtrl = TextEditingController();

  // Step 2: Αξιολόγηση
  double _gcsEye = 4;
  double _gcsVerbal = 5;
  double _gcsMotor = 6;
  String? _avpu;
  final _locationNotesCtrl = TextEditingController();
  int? _serviceId;
  List<Map<String, dynamic>> _acceptedServices = [];

  // Step 3: Notes
  final _notesCtrl = TextEditingController();

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _serviceId = widget.prefilledServiceId;
    _loadAcceptedServices();
  }

  Future<void> _loadAcceptedServices() async {
    try {
      final res = await _api.get('/services/my');
      if (res.statusCode == 200) {
        final all = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
        setState(() {
          _acceptedServices = all.where((s) {
            final userServices = s['userServices'];
            if (userServices is List) {
              return userServices.any((us) => us['status'] == 'accepted');
            }
            return false;
          }).toList();
        });
      }
    } catch (_) {}
  }

  int get _gcsTotal => _gcsEye.round() + _gcsVerbal.round() + _gcsMotor.round();

  Map<String, dynamic> _buildPayload() {
    return {
      'name': _nameCtrl.text.trim(),
      if (_ageCtrl.text.isNotEmpty) 'age': int.tryParse(_ageCtrl.text),
      if (_dateOfBirth != null) 'dateOfBirth': _dateOfBirth!.toIso8601String(),
      if (_gender != null) 'gender': _gender,
      if (_addressCtrl.text.isNotEmpty) 'address': _addressCtrl.text.trim(),
      if (_cityCtrl.text.isNotEmpty) 'city': _cityCtrl.text.trim(),
      if (_postalCodeCtrl.text.isNotEmpty) 'postalCode': _postalCodeCtrl.text.trim(),
      if (_telephoneCtrl.text.isNotEmpty) 'telephone': _telephoneCtrl.text.trim(),
      if (_emergencyContactCtrl.text.isNotEmpty) 'emergencyContact': _emergencyContactCtrl.text.trim(),
      if (_emergencyPhoneCtrl.text.isNotEmpty) 'emergencyPhone': _emergencyPhoneCtrl.text.trim(),
      if (_chiefComplaintCtrl.text.isNotEmpty) 'chiefComplaint': _chiefComplaintCtrl.text.trim(),
      if (_allergiesCtrl.text.isNotEmpty) 'allergies': _allergiesCtrl.text.trim(),
      if (_medicationsCtrl.text.isNotEmpty) 'medications': _medicationsCtrl.text.trim(),
      if (_medicalHistoryCtrl.text.isNotEmpty) 'medicalHistory': _medicalHistoryCtrl.text.trim(),
      'gcsEye': _gcsEye.round(),
      'gcsVerbal': _gcsVerbal.round(),
      'gcsMotor': _gcsMotor.round(),
      'gcsTotal': _gcsTotal,
      if (_avpu != null) 'avpu': _avpu,
      if (_locationNotesCtrl.text.isNotEmpty) 'locationNotes': _locationNotesCtrl.text.trim(),
      if (_serviceId != null) 'serviceId': _serviceId,
      if (_notesCtrl.text.isNotEmpty) 'notes': _notesCtrl.text.trim(),
    };
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Το όνομα είναι υποχρεωτικό'),
          backgroundColor: Color(0xFFB91C1C),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    final err = await context.read<VictimProvider>().createVictim(_buildPayload());
    setState(() => _submitting = false);

    if (!mounted) return;

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: const Color(0xFFB91C1C)),
      );
    } else {
      context.go('/victims');
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _postalCodeCtrl.dispose();
    _telephoneCtrl.dispose();
    _emergencyContactCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    _chiefComplaintCtrl.dispose();
    _allergiesCtrl.dispose();
    _medicationsCtrl.dispose();
    _medicalHistoryCtrl.dispose();
    _locationNotesCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefilled = widget.prefilledServiceId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Νέο Περιστατικό')),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep < 3) {
            setState(() => _currentStep += 1);
          } else {
            _submit();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) setState(() => _currentStep -= 1);
        },
        onStepTapped: (step) => setState(() => _currentStep = step),
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                if (_currentStep > 0)
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: const Text('Προηγούμενο'),
                  ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _submitting ? null : details.onStepContinue,
                  child: Text(_currentStep == 3 ? 'Υποβολή' : 'Επόμενο'),
                ),
              ],
            ),
          );
        },
        steps: [
          // Step 0: Στοιχεία
          Step(
            title: const Text('Στοιχεία'),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            content: Column(
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Ονοματεπώνυμο *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ageCtrl,
                  decoration: const InputDecoration(labelText: 'Ηλικία'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime(1990),
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _dateOfBirth = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Ημερομηνία γέννησης'),
                    child: Text(
                      _dateOfBirth != null
                          ? '${_dateOfBirth!.day}/${_dateOfBirth!.month}/${_dateOfBirth!.year}'
                          : 'Επιλέξτε...',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _gender,
                  decoration: const InputDecoration(labelText: 'Φύλο'),
                  items: const [
                    DropdownMenuItem(value: 'male', child: Text('Άνδρας')),
                    DropdownMenuItem(value: 'female', child: Text('Γυναίκα')),
                    DropdownMenuItem(value: 'other', child: Text('Άλλο')),
                    DropdownMenuItem(value: 'unknown', child: Text('Άγνωστο')),
                  ],
                  onChanged: (v) => setState(() => _gender = v),
                ),
                const SizedBox(height: 12),
                TextField(controller: _addressCtrl, decoration: const InputDecoration(labelText: 'Διεύθυνση')),
                const SizedBox(height: 12),
                TextField(controller: _cityCtrl, decoration: const InputDecoration(labelText: 'Πόλη')),
                const SizedBox(height: 12),
                TextField(controller: _postalCodeCtrl, decoration: const InputDecoration(labelText: 'Τ.Κ.')),
                const SizedBox(height: 12),
                TextField(controller: _telephoneCtrl, decoration: const InputDecoration(labelText: 'Τηλέφωνο'), keyboardType: TextInputType.phone),
                const SizedBox(height: 12),
                TextField(controller: _emergencyContactCtrl, decoration: const InputDecoration(labelText: 'Επαφή έκτακτης ανάγκης')),
                const SizedBox(height: 12),
                TextField(controller: _emergencyPhoneCtrl, decoration: const InputDecoration(labelText: 'Τηλέφωνο επαφής έκτακτης ανάγκης'), keyboardType: TextInputType.phone),
              ],
            ),
          ),

          // Step 1: Ιατρικό ιστορικό
          Step(
            title: const Text('Ιατρικό ιστορικό'),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
            content: Column(
              children: [
                TextField(
                  controller: _chiefComplaintCtrl,
                  decoration: const InputDecoration(labelText: 'Κύριο σύμπτωμα'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _allergiesCtrl,
                  decoration: const InputDecoration(labelText: 'Αλλεργίες'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _medicationsCtrl,
                  decoration: const InputDecoration(labelText: 'Φαρμακευτική αγωγή'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _medicalHistoryCtrl,
                  decoration: const InputDecoration(labelText: 'Ιατρικό ιστορικό'),
                  maxLines: 2,
                ),
              ],
            ),
          ),

          // Step 2: Αξιολόγηση
          Step(
            title: const Text('Αξιολόγηση'),
            isActive: _currentStep >= 2,
            state: _currentStep > 2 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('GCS (Glasgow Coma Scale)', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Σύνολο: $_gcsTotal / 15', style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFFC62828), fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _GcsSlider(label: 'Οφθαλμοί (E)', value: _gcsEye, min: 1, max: 4, onChanged: (v) => setState(() => _gcsEye = v)),
                _GcsSlider(label: 'Λεκτική (V)', value: _gcsVerbal, min: 1, max: 5, onChanged: (v) => setState(() => _gcsVerbal = v)),
                _GcsSlider(label: 'Κινητική (M)', value: _gcsMotor, min: 1, max: 6, onChanged: (v) => setState(() => _gcsMotor = v)),
                const SizedBox(height: 16),
                const Text('AVPU', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['ALERT', 'VOICE', 'PAIN', 'UNRESPONSIVE'].map((v) {
                    return ChoiceChip(
                      label: Text(v == 'ALERT' ? 'Σε εγρήγορση' : v == 'VOICE' ? 'Αντιδρά σε φωνή' : v == 'PAIN' ? 'Αντιδρά στον πόνο' : 'Χωρίς αντίδραση'),
                      selected: _avpu == v,
                      onSelected: (_) => setState(() => _avpu = _avpu == v ? null : v),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _locationNotesCtrl,
                  decoration: const InputDecoration(labelText: 'Σημειώσεις τοποθεσίας'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                if (prefilled && widget.prefilledServiceId != null)
                  Text('Υπηρεσία: Προσυμπληρωμένη', style: GoogleFonts.inter(color: const Color(0xFF6B7280)))
                else ...[
                  DropdownButtonFormField<int>(
                    value: _serviceId,
                    decoration: const InputDecoration(labelText: 'Υπηρεσία'),
                    items: [
                      const DropdownMenuItem<int>(value: null, child: Text('Καμία')),
                      ..._acceptedServices.map((s) => DropdownMenuItem<int>(
                        value: s['id'],
                        child: Text(s['name'] ?? 'Υπηρεσία ${s['id']}'),
                      )),
                    ],
                    onChanged: (v) => setState(() => _serviceId = v),
                  ),
                ],
              ],
            ),
          ),

          // Step 3: Επισκόπηση
          Step(
            title: const Text('Επισκόπηση'),
            isActive: _currentStep >= 3,
            state: _currentStep > 3 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SummaryRow(label: 'Ονοματεπώνυμο', value: _nameCtrl.text.trim()),
                if (_ageCtrl.text.isNotEmpty) _SummaryRow(label: 'Ηλικία', value: _ageCtrl.text),
                if (_dateOfBirth != null)
                  _SummaryRow(label: 'Ημ/νία γέννησης', value: '${_dateOfBirth!.day}/${_dateOfBirth!.month}/${_dateOfBirth!.year}'),
                if (_gender != null) _SummaryRow(label: 'Φύλο', value: _gender!),
                if (_chiefComplaintCtrl.text.isNotEmpty) _SummaryRow(label: 'Κύριο σύμπτωμα', value: _chiefComplaintCtrl.text),
                _SummaryRow(label: 'GCS', value: '$_gcsTotal (E$_gcsEye / V$_gcsVerbal / M$_gcsMotor)'),
                if (_avpu != null) _SummaryRow(label: 'AVPU', value: _avpu!),
                if (_serviceId != null) _SummaryRow(label: 'Συνδεδεμένη υπηρεσία', value: 'ID $_serviceId'),
                if (_notesCtrl.text.isNotEmpty) _SummaryRow(label: 'Σημειώσεις', value: _notesCtrl.text),
                const SizedBox(height: 16),
                TextField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(labelText: 'Σημειώσεις'),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GcsSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _GcsSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 130, child: Text(label, style: GoogleFonts.inter(fontSize: 13))),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: (max - min).round(),
            label: value.round().toString(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 24, child: Text(value.round().toString(), textAlign: TextAlign.center)),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text('$label:', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280))),
          ),
          Expanded(child: Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
