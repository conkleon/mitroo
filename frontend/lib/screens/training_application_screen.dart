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
  String? _selectedSpecDescription;
  DateTime? _birthDate;
  bool _loading = true;
  bool _submitting = false;

  static const _primaryRed = Color(0xFFC62828);
  static const _subtleGray = Color(0xFF6B7280);
  static const _lightBg = Color(0xFFF0F2F5);

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
          _selectedSpecDescription = null;
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

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: _primaryRed.withAlpha(18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: _primaryRed),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8ECF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: padding ?? const EdgeInsets.all(20),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 720;

    if (_loading) {
      return const Scaffold(
        backgroundColor: _lightBg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_rootSpecs.isEmpty) {
      return Scaffold(
        backgroundColor: _lightBg,
        appBar: AppBar(title: const Text('Αίτηση Εκπαίδευσης')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_outlined, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text('Δεν υπάρχουν διαθέσιμες εκπαιδεύσεις αυτήν τη στιγμή.'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _lightBg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 160,
            floating: false,
            pinned: true,
            backgroundColor: _primaryRed,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFB71C1C), Color(0xFFC62828), Color(0xFFD32F2F)],
                      ),
                    ),
                  ),
                  Positioned(
                    right: -30,
                    top: -30,
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withAlpha(15),
                      ),
                    ),
                  ),
                  Positioned(
                    left: -20,
                    bottom: -40,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withAlpha(10),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 70, 20, 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.school, color: Colors.white, size: 22),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Αίτηση Εκπαίδευσης',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Ελληνικός Ερυθρός Σταυρός',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWide ? 24 : 16,
                    vertical: 20,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: _primaryRed.withAlpha(18),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.info_outline, color: _primaryRed, size: 20),
                                  ),
                                  const SizedBox(width: 14),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Θέλω να εκπαιδευτώ στον Ελληνικό Ερυθρό Σταυρό',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1A1C1E),
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'Το πρόγραμμα εκπαίδευσης του Ελληνικού Ερυθρού Σταυρού παρέχει εξειδικευμένη κατάρτιση σε τομείς Α\' Βοηθειών, Διάσωσης και Κοινωνικής Πρόνοιας. Συμπληρώστε τα στοιχεία σας και θα λάβετε επικοινωνία από το τμήμα επιλογής σας.',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: _subtleGray,
                                            height: 1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (_selectedSpecDescription != null) ...[
                                const SizedBox(height: 16),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: _primaryRed.withAlpha(12),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: _primaryRed.withAlpha(40)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.bookmark_outline, color: _primaryRed, size: 18),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _selectedSpecDescription!,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF374151),
                                            height: 1.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader('Επιλογή Εκπαίδευσης', Icons.school_outlined),
                              DropdownButtonFormField<int>(
                                value: _selectedSpecId,
                                decoration: const InputDecoration(
                                  labelText: 'Ειδίκευση *',
                                  prefixIcon: Icon(Icons.category_outlined),
                                ),
                                items: _rootSpecs.map((s) {
                                  return DropdownMenuItem<int>(
                                    value: s['id'] as int,
                                    child: Text((s['name'] ?? '').toString()),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  final spec = _rootSpecs.firstWhere(
                                    (s) => s['id'] == value,
                                    orElse: () => {},
                                  );
                                  setState(() {
                                    _selectedSpecId = value;
                                    _selectedSpecDescription = spec['description']?.toString();
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader('Προσωπικά Στοιχεία', Icons.person_outline),
                              if (isWide)
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _forenameCtrl,
                                        textInputAction: TextInputAction.next,
                                        decoration: const InputDecoration(
                                          labelText: 'Όνομα *',
                                          prefixIcon: Icon(Icons.person_outline),
                                        ),
                                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Υποχρεωτικό' : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _surnameCtrl,
                                        textInputAction: TextInputAction.next,
                                        decoration: const InputDecoration(
                                          labelText: 'Επώνυμο *',
                                          prefixIcon: Icon(Icons.person_outline),
                                        ),
                                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Υποχρεωτικό' : null,
                                      ),
                                    ),
                                  ],
                                )
                              else ...[
                                TextFormField(
                                  controller: _forenameCtrl,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Όνομα *',
                                    prefixIcon: Icon(Icons.person_outline),
                                  ),
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Υποχρεωτικό' : null,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _surnameCtrl,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Επώνυμο *',
                                    prefixIcon: Icon(Icons.person_outline),
                                  ),
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Υποχρεωτικό' : null,
                                ),
                              ],
                              const SizedBox(height: 12),
                              InkWell(
                                onTap: _pickBirthDate,
                                borderRadius: BorderRadius.circular(12),
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'Ημερομηνία Γέννησης',
                                    prefixIcon: Icon(Icons.cake_outlined),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _birthDate == null
                                            ? 'Επιλογή ημερομηνίας'
                                            : '${_birthDate!.day.toString().padLeft(2, '0')}/${_birthDate!.month.toString().padLeft(2, '0')}/${_birthDate!.year}',
                                        style: TextStyle(
                                          color: _birthDate == null ? _subtleGray : const Color(0xFF1A1C1E),
                                        ),
                                      ),
                                      const Icon(Icons.calendar_today_outlined, size: 16, color: _subtleGray),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader('Στοιχεία Επικοινωνίας', Icons.contact_phone_outlined),
                              TextFormField(
                                controller: _emailCtrl,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Email *',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                validator: (v) => (v == null || !v.contains('@')) ? 'Εισάγετε έγκυρο email' : null,
                              ),
                              const SizedBox(height: 12),
                              if (isWide)
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _phonePrimaryCtrl,
                                        keyboardType: TextInputType.phone,
                                        textInputAction: TextInputAction.next,
                                        decoration: const InputDecoration(
                                          labelText: 'Κινητό Τηλέφωνο *',
                                          prefixIcon: Icon(Icons.phone_android_outlined),
                                        ),
                                        validator: (v) => (v == null || v.trim().length < 5) ? 'Υποχρεωτικό' : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _phoneSecondaryCtrl,
                                        keyboardType: TextInputType.phone,
                                        textInputAction: TextInputAction.next,
                                        decoration: const InputDecoration(
                                          labelText: 'Δευτερεύον Τηλέφωνο',
                                          prefixIcon: Icon(Icons.phone_outlined),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              else ...[
                                TextFormField(
                                  controller: _phonePrimaryCtrl,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Κινητό Τηλέφωνο *',
                                    prefixIcon: Icon(Icons.phone_android_outlined),
                                  ),
                                  validator: (v) => (v == null || v.trim().length < 5) ? 'Υποχρεωτικό' : null,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _phoneSecondaryCtrl,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Δευτερεύον Τηλέφωνο',
                                    prefixIcon: Icon(Icons.phone_outlined),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _addressCtrl,
                                maxLines: 2,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Διεύθυνση',
                                  prefixIcon: Padding(
                                    padding: EdgeInsets.only(bottom: 28),
                                    child: Icon(Icons.location_on_outlined),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader('Επιλογή Τμήματος', Icons.apartment_outlined),
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
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader('Επιπλέον Πληροφορίες', Icons.notes_outlined),
                              TextFormField(
                                controller: _extraInfoCtrl,
                                maxLines: 4,
                                textInputAction: TextInputAction.newline,
                                decoration: const InputDecoration(
                                  labelText: 'Επιπλέον Στοιχεία',
                                  hintText: 'Αναφέρετε τυχόν σχετική εμπειρία, κίνητρα συμμετοχής ή οποιαδήποτε άλλη πληροφορία...',
                                  alignLabelWithHint: true,
                                  prefixIcon: Padding(
                                    padding: EdgeInsets.only(bottom: 72),
                                    child: Icon(Icons.notes_outlined),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline, color: Colors.amber.shade700, size: 18),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Με την υποβολή θα λάβετε ενημέρωση ότι η φόρμα παραλήφθηκε και θα περιμένετε επικοινωνία από το τμήμα επιλογής σας.',
                                  style: TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: FilledButton.icon(
                            onPressed: _submitting ? null : _submit,
                            icon: _submitting
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                : const Icon(Icons.send_outlined, size: 20),
                            label: _submitting
                                ? const SizedBox.shrink()
                                : const Text(
                                    'Υποβολή Αίτησης',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
