import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/pwa_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _api = ApiClient();
  bool _loading = true;
  String? _error;

  // Hours data
  int _totalHours = 0;
  int _yearHours = 0;
  int _yearServiceHours = 0;
  int _yearVolHours = 0;
  int _yearTrainingHours = 0;
  int _yearTrainerHours = 0;

  // Services table
  List<Map<String, dynamic>> _services = [];
  String _svcSearch = '';
  String _svcStatusFilter = 'all';
  String _svcSortField = 'date';
  bool _svcSortAsc = false;
  int _svcPage = 0;
  int _svcRowsPerPage = 10;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.get('/auth/me/profile');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _totalHours = data['totalHours'] ?? 0;
          _yearHours = data['yearHours'] ?? 0;
          _yearServiceHours = data['yearServiceHours'] ?? 0;
          _yearVolHours = data['yearVolHours'] ?? 0;
          _yearTrainingHours = data['yearTrainingHours'] ?? 0;
          _yearTrainerHours = data['yearTrainerHours'] ?? 0;
        });
      } else {
        setState(() => _error = 'Αποτυχία φόρτωσης προφίλ');
      }

      // Fetch services list for the table
      try {
        final auth = context.read<AuthProvider>();
        final userId = auth.user?['id'];
        if (userId != null) {
          final svcRes = await _api.get('/users/$userId/services');
          if (svcRes.statusCode == 200) {
            setState(() {
              _services = (jsonDecode(svcRes.body) as List).cast<Map<String, dynamic>>();
            });
          }
        }
      } catch (_) {}
    } catch (e) {
      setState(() => _error = 'Σφάλμα σύνδεσης');
    }
    setState(() => _loading = false);
  }

  // ── Change password dialog ──────────────────────
  Future<void> _showChangePasswordDialog() async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool busy = false;
    String? dialogError;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Αλλαγή Κωδικού'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dialogError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(dialogError!, style: TextStyle(color: Color(0xFFB91C1C), fontSize: 13)),
                  ),
                TextFormField(
                  controller: currentCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Τρέχων Κωδικός',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Υποχρεωτικό' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: newCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Νέος Κωδικός',
                    prefixIcon: Icon(Icons.lock_reset),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Υποχρεωτικό';
                    if (v.length < 8) return 'Τουλάχιστον 8 χαρακτήρες';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Επιβεβαίωση Κωδικού',
                    prefixIcon: Icon(Icons.lock_reset),
                  ),
                  validator: (v) {
                    if (v != newCtrl.text) return 'Οι κωδικοί δεν ταιριάζουν';
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Άκυρο')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() {
                        busy = true;
                        dialogError = null;
                      });
                      try {
                        final res = await _api.post('/auth/change-password', body: {
                          'currentPassword': currentCtrl.text,
                          'newPassword': newCtrl.text,
                        });
                        if (res.statusCode == 200) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Ο κωδικός άλλαξε επιτυχώς')),
                            );
                          }
                        } else {
                          final body = jsonDecode(res.body);
                          setDialogState(() {
                            dialogError = body['error'] ?? 'Αποτυχία αλλαγής κωδικού';
                            busy = false;
                          });
                        }
                      } catch (_) {
                        setDialogState(() {
                          dialogError = 'Σφάλμα σύνδεσης';
                          busy = false;
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Αλλαγή'),
            ),
          ],
        ),
      ),
    );
    currentCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
  }

  Future<void> _forceUpdate() async {
    final updated = await PwaService.forceUpdate();
    if (!mounted) return;
    if (!updated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Δεν υπάρχουν νέες ενημερώσεις')),
      );
    }
  }

  // ── Services table helpers ──────────────────────

  List<Map<String, dynamic>> get _processedServices {
    var list = List<Map<String, dynamic>>.from(_services);

    if (_svcStatusFilter != 'all') {
      list = list.where((s) => s['status'] == _svcStatusFilter).toList();
    }

    if (_svcSearch.isNotEmpty) {
      final q = _svcSearch.toLowerCase();
      list = list.where((s) {
        final svc = s['service'] as Map<String, dynamic>? ?? {};
        final name = (svc['name'] ?? '').toString().toLowerCase();
        final loc = (svc['location'] ?? '').toString().toLowerCase();
        final dept = (svc['department']?['name'] ?? '').toString().toLowerCase();
        return name.contains(q) || loc.contains(q) || dept.contains(q);
      }).toList();
    }

    list.sort((a, b) {
      int cmp;
      switch (_svcSortField) {
        case 'name':
          final na = (a['service']?['name'] ?? '').toString().toLowerCase();
          final nb = (b['service']?['name'] ?? '').toString().toLowerCase();
          cmp = na.compareTo(nb);
          break;
        case 'totalHours':
          cmp = ((a['totalHours'] ?? 0) as int).compareTo((b['totalHours'] ?? 0) as int);
          break;
        case 'hours':
          cmp = ((a['hours'] ?? 0) as int).compareTo((b['hours'] ?? 0) as int);
          break;
        case 'hoursVol':
          cmp = ((a['hoursVol'] ?? 0) as int).compareTo((b['hoursVol'] ?? 0) as int);
          break;
        case 'hoursTraining':
          cmp = ((a['hoursTraining'] ?? 0) as int).compareTo((b['hoursTraining'] ?? 0) as int);
          break;
        case 'hoursTrainers':
          cmp = ((a['hoursTrainers'] ?? 0) as int).compareTo((b['hoursTrainers'] ?? 0) as int);
          break;
        default:
          final da = a['service']?['startAt'] ?? '';
          final db = b['service']?['startAt'] ?? '';
          cmp = da.toString().compareTo(db.toString());
      }
      return _svcSortAsc ? cmp : -cmp;
    });

    return list;
  }

  void _setSvcSort(String field) {
    setState(() {
      if (_svcSortField == field) {
        _svcSortAsc = !_svcSortAsc;
      } else {
        _svcSortField = field;
        _svcSortAsc = field == 'name' || field == 'date';
      }
      _svcPage = 0;
    });
  }

  Widget _svcHeaderCell(String label, String field, {int flex = 1}) {
    final isActive = _svcSortField == field;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => _setSvcSort(field),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                    color: isActive ? const Color(0xFFDC2626) : const Color(0xFF374151))),
            if (isActive)
              Icon(_svcSortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 10, color: const Color(0xFFDC2626)),
          ],
        ),
      ),
    );
  }

  Widget _svcHoursCell(dynamic val, {bool bold = false}) {
    final h = (val ?? 0) as int;
    return Expanded(
      child: Text(
        h > 0 ? '$h' : '—',
        style: TextStyle(
          fontSize: 11,
          fontWeight: h > 0 && bold ? FontWeight.w700 : (h > 0 ? FontWeight.w600 : FontWeight.w400),
          color: h > 0 ? const Color(0xFF111827) : const Color(0xFFD1D5DB),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildSvcRow(Map<String, dynamic> enrolment, bool even) {
    final svc = enrolment['service'] as Map<String, dynamic>? ?? {};
    final name = svc['name'] ?? 'Unknown';
    final dept = svc['department']?['name'] ?? '';
    final status = enrolment['status'] as String? ?? '';
    final startAt = DateTime.tryParse(svc['startAt']?.toString() ?? '');
    final endAt = DateTime.tryParse(svc['endAt']?.toString() ?? '');

    String dateStr = '—';
    if (startAt != null) {
      dateStr = '${startAt.day}/${startAt.month}/${startAt.year}';
      if (endAt != null && endAt != startAt) {
        dateStr += ' - ${endAt.day}/${endAt.month}/${endAt.year}';
      }
    }

    Color statusColor;
    switch (status) {
      case 'accepted': statusColor = const Color(0xFF059669); break;
      case 'participated': statusColor = const Color(0xFF0891B2); break;
      case 'rejected': statusColor = const Color(0xFFDC2626); break;
      case 'not-participated':
      case 'not_participated': statusColor = const Color(0xFF6B7280); break;
      default: statusColor = const Color(0xFFF59E0B);
    }

    return Container(
      color: even ? Colors.white : const Color(0xFFF9FAFB),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (dept.isNotEmpty)
                Text(dept, style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(dateStr, style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(20),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              status.isNotEmpty ? status[0].toUpperCase() + status.substring(1) : '',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: statusColor),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        _svcHoursCell(enrolment['totalHours'], bold: true),
        _svcHoursCell(enrolment['hours']),
        _svcHoursCell(enrolment['hoursVol']),
        _svcHoursCell(enrolment['hoursTraining']),
        _svcHoursCell(enrolment['hoursTrainers']),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final String name = auth.displayName.isNotEmpty ? auth.displayName : (user?['eame'] ?? 'Χρήστης').toString();
    final initials = name.split(' ').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();
    final currentYear = DateTime.now().year;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Προφίλ'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Avatar & name card ──
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: cs.primary,
                    child: Text(
                      initials,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 28),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(name, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    user?['email'] ?? '',
                    style: tt.bodyMedium?.copyWith(color: const Color(0xFF6B7280)),
                  ),
                  if (auth.isAdmin) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('Διαχειριστής', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 12)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Hours summary card ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.schedule, color: cs.primary, size: 22),
                      const SizedBox(width: 8),
                      Text('Ώρες', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_loading)
                    const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                  else if (_error != null)
                    Center(child: Text(_error!, style: TextStyle(color: Color(0xFFDC2626))))
                  else ...[
                    // Total hours (all time)
                    _HoursHighlight(label: 'Συνολικές Ώρες', hours: _totalHours, color: cs.primary),
                    const Divider(height: 24),
                    Text('Ανάλυση $currentYear',
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF374151))),
                    const SizedBox(height: 12),
                    _HoursRow(label: 'Κάλυψη', hours: _yearServiceHours, icon: Icons.medical_services_outlined, color: const Color(0xFFDC2626)),
                    const SizedBox(height: 8),
                    _HoursRow(label: 'Εθελοντικές', hours: _yearVolHours, icon: Icons.volunteer_activism, color: const Color(0xFF059669)),
                    const SizedBox(height: 8),
                    _HoursRow(label: 'Επανεκπαίδευση', hours: _yearTrainingHours, icon: Icons.school_outlined, color: const Color(0xFFD97706)),
                    const SizedBox(height: 8),
                    _HoursRow(label: 'Εκπαιδευτές', hours: _yearTrainerHours, icon: Icons.co_present_outlined, color: const Color(0xFF7C3AED)),
                    const Divider(height: 24),
                    _HoursHighlight(label: 'Σύνολο $currentYear', hours: _yearHours, color: const Color(0xFF059669)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Services table card ──
          if (_services.isNotEmpty)
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.work_history, color: cs.primary, size: 22),
                      const SizedBox(width: 10),
                      Text('Υπηρεσίες / Αποστολές', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text('${_services.length} total',
                          style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
                    ]),
                    const SizedBox(height: 8),
                    // Summary chips
                    Builder(builder: (_) {
                      int sumTotal = 0, sumH = 0, sumVol = 0, sumTrain = 0, sumTrainer = 0;
                      for (final s in _services.where((s) => s['status'] == 'accepted' || s['status'] == 'participated')) {
                        sumTotal += (s['totalHours'] ?? 0) as int;
                        sumH += (s['hours'] ?? 0) as int;
                        sumVol += (s['hoursVol'] ?? 0) as int;
                        sumTrain += (s['hoursTraining'] ?? 0) as int;
                        sumTrainer += (s['hoursTrainers'] ?? 0) as int;
                      }
                      return Wrap(spacing: 8, runSpacing: 6, children: [
                        _HoursChip('Total', sumTotal, const Color(0xFFDC2626)),
                        _HoursChip('Hours', sumH, const Color(0xFF059669)),
                        _HoursChip('Vol', sumVol, const Color(0xFF7C3AED)),
                        _HoursChip('Training', sumTrain, const Color(0xFFD97706)),
                        _HoursChip('Trainer', sumTrainer, const Color(0xFFDC2626)),
                      ]);
                    }),
                    const SizedBox(height: 12),
                    // Filters row
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _svcStatusFilter,
                            isDense: true,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('Όλες οι καταστάσεις')),
                              DropdownMenuItem(value: 'accepted', child: Text('Εγκεκριμένη')),
                              DropdownMenuItem(value: 'participated', child: Text('Παρουσιάστηκε')),
                              DropdownMenuItem(value: 'requested', child: Text('Εκκρεμής')),
                              DropdownMenuItem(value: 'rejected', child: Text('Απορριφθείσα')),
                              DropdownMenuItem(value: 'not-participated', child: Text('Δεν παρουσιάστηκε')),
                            ],
                            onChanged: (v) => setState(() { _svcStatusFilter = v ?? 'all'; _svcPage = 0; }),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Αναζήτηση υπηρεσιών...',
                            prefixIcon: const Icon(Icons.search, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            filled: true,
                            fillColor: const Color(0xFFF9FAFB),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 12),
                          onChanged: (v) => setState(() { _svcSearch = v; _svcPage = 0; }),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    // Pagination
                    Builder(builder: (_) {
                      final processed = _processedServices;
                      final totalPages = processed.isEmpty ? 1 : (processed.length / _svcRowsPerPage).ceil();
                      final pageStart = _svcPage * _svcRowsPerPage;
                      final pageEnd = (pageStart + _svcRowsPerPage).clamp(0, processed.length);
                      final pageItems = processed.sublist(pageStart, pageEnd);
                      return Column(children: [
                        Row(children: [
                          Text('${processed.length} shown',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                          const Spacer(),
                          const Text('Γραμμές: ', style: TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9FAFB),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: _svcRowsPerPage,
                                isDense: true,
                                style: const TextStyle(fontSize: 11, color: Color(0xFF374151)),
                                items: const [
                                  DropdownMenuItem(value: 5, child: Text('5')),
                                  DropdownMenuItem(value: 10, child: Text('10')),
                                  DropdownMenuItem(value: 25, child: Text('25')),
                                  DropdownMenuItem(value: 50, child: Text('50')),
                                ],
                                onChanged: (v) => setState(() { _svcRowsPerPage = v ?? 10; _svcPage = 0; }),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.chevron_left, size: 18),
                            onPressed: _svcPage > 0 ? () => setState(() => _svcPage--) : null,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          Text('${_svcPage + 1}/${totalPages.clamp(1, 999)}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                          IconButton(
                            icon: const Icon(Icons.chevron_right, size: 18),
                            onPressed: _svcPage < totalPages - 1 ? () => setState(() => _svcPage++) : null,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        // Table header
                        Container(
                          color: const Color(0xFFEEF0F4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          child: Row(children: [
                            _svcHeaderCell('Service', 'name', flex: 3),
                            _svcHeaderCell('Date', 'date', flex: 2),
                            _svcHeaderCell('Status', 'status'),
                            _svcHeaderCell('Total', 'totalHours'),
                            _svcHeaderCell('Hrs', 'hours'),
                            _svcHeaderCell('Vol', 'hoursVol'),
                            _svcHeaderCell('Trng', 'hoursTraining'),
                            _svcHeaderCell('Trnr', 'hoursTrainers'),
                          ]),
                        ),
                        if (pageItems.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: Text('Δεν βρέθηκαν υπηρεσίες', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13))),
                          )
                        else
                          ...pageItems.asMap().entries.map((e) => _buildSvcRow(e.value, e.key.isEven)),
                      ]);
                    }),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),

          // ── Details card ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Στοιχεία', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  _DetailRow(icon: Icons.badge_outlined, label: 'EAME', value: user?['eame'] ?? '-'),
                  const Divider(height: 24),
                  _DetailRow(icon: Icons.person_outline, label: 'Όνομα', value: user?['forename'] ?? '-'),
                  const Divider(height: 24),
                  _DetailRow(icon: Icons.person_outline, label: 'Επώνυμο', value: user?['surname'] ?? '-'),
                  const Divider(height: 24),
                  _DetailRow(icon: Icons.email_outlined, label: 'Email', value: user?['email'] ?? '-'),
                  if (user?['phonePrimary'] != null) ...[
                    const Divider(height: 24),
                    _DetailRow(icon: Icons.phone_outlined, label: 'Τηλέφωνο', value: user?['phonePrimary'] ?? '-'),
                  ],
                  if (user?['address'] != null) ...[
                    const Divider(height: 24),
                    _DetailRow(icon: Icons.home_outlined, label: 'Διεύθυνση', value: user?['address'] ?? '-'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Departments card ──
          if (user?['departments'] != null && (user!['departments'] as List).isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Τμήματα', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    ...(user['departments'] as List).map((d) {
                      final dept = d['department'];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: cs.primary.withAlpha(20),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.business, color: cs.primary, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(dept?['name'] ?? '', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w500)),
                                  Text(d['role'] ?? '', style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),

          // ── Change password ──
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showChangePasswordDialog,
              icon: const Icon(Icons.lock_outline, size: 18),
              label: const Text('Αλλαγή Κωδικού'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Force update ──
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _forceUpdate,
              icon: const Icon(Icons.system_update_rounded, size: 18),
              label: const Text('Έλεγχος για ενημερώσεις'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Sign out ──
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                auth.logout();
                context.go('/login');
              },
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Αποσύνδεση'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Color(0xFFDC2626),
                side: BorderSide(color: Color(0xFFFCA5A5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────

class _HoursHighlight extends StatelessWidget {
  final String label;
  final int hours;
  final Color color;
  const _HoursHighlight({required this.label, required this.hours, required this.color});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$hours h',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: color),
          ),
        ),
      ],
    );
  }
}

class _HoursRow extends StatelessWidget {
  final String label;
  final int hours;
  final IconData icon;
  final Color color;
  const _HoursRow({required this.label, required this.hours, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: tt.bodyMedium)),
        Text('$hours h', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF6B7280)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
              const SizedBox(height: 2),
              Text(value, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}

class _HoursChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _HoursChip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$value', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, color: color.withAlpha(180))),
      ]),
    );
  }
}
