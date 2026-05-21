import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/sync_provider.dart';
import '../services/api_client.dart';

/// Shows past (completed) services with search, specialization filter,
/// and date-range filter.
class PastServicesScreen extends StatefulWidget {
  final int departmentId;
  final String departmentName;

  const PastServicesScreen({
    super.key,
    required this.departmentId,
    required this.departmentName,
  });

  @override
  State<PastServicesScreen> createState() => _PastServicesScreenState();
}

class _PastServicesScreenState extends State<PastServicesScreen> {
  final _api = ApiClient();

  List<dynamic> _services = [];
  List<dynamic> _specializations = [];
  bool _loading = true;
  bool _isSyncing = false;
  String _search = '';
  int? _selectedSpecId;
  DateTime? _fromDate;
  DateTime? _toDate;
  String _selectedLifecycle = 'active';

  @override
  void initState() {
    super.initState();
    _loadSpecs();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _backgroundSync();
    });
  }

  Future<void> _backgroundSync() async {
    if (_isSyncing) return;
    if (mounted) setState(() => _isSyncing = true);
    try {
      final sync = context.read<SyncProvider>();
      await sync.syncServices(widget.departmentId);
    } catch (_) {}
    if (mounted) {
      setState(() => _isSyncing = false);
      _load();
    }
  }

  Future<void> _loadSpecs() async {
    try {
      final res = await _api.get('/specializations');
      if (res.statusCode == 200 && mounted) {
        setState(() => _specializations = jsonDecode(res.body));
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final params = <String, String>{
        'departmentId': '${widget.departmentId}',
        'includeEnrollments': 'true',
      };
      // Active tab: only show services whose end date has already passed (overdue-active).
      // Closed/completed tabs: bypass all date filters — lifecycle status is authoritative
      // and these missions can have any date (e.g. a future mission closed early by admin,
      // or a past mission that was completed).
      if (_selectedLifecycle == 'active') {
        params['pastOnly'] = 'true';
      } else {
        params['includeExpired'] = 'true';
      }
      if (_selectedSpecId != null) {
        params['specializationId'] = '$_selectedSpecId';
      }
      if (_fromDate != null) {
        params['fromDate'] = _fromDate!.toUtc().toIso8601String();
      }
      if (_toDate != null) {
        final eod = DateTime(_toDate!.year, _toDate!.month, _toDate!.day, 23, 59, 59);
        params['toDate'] = eod.toUtc().toIso8601String();
      }

      final parts = params.entries.map((e) => '${e.key}=${e.value}').toList();
      parts.add('lifecycleStatus=$_selectedLifecycle');
      final query = parts.join('&');
      final res = await _api.get('/services?$query');
      if (res.statusCode == 200 && mounted) {
        _services = jsonDecode(res.body);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<dynamic> get _filtered {
    if (_search.isEmpty) return _services;
    final q = _search.toLowerCase();
    return _services.where((s) {
      final name = (s['name'] ?? '').toString().toLowerCase();
      final loc = (s['location'] ?? '').toString().toLowerCase();
      final carrier = (s['carrier'] ?? '').toString().toLowerCase();
      final desc = (s['description'] ?? '').toString().toLowerCase();
      return name.contains(q) ||
          loc.contains(q) ||
          carrier.contains(q) ||
          desc.contains(q);
    }).toList();
  }

  String _fmtDay(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  String _fmtDate(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '—';
    return DateFormat('dd/MM/yy HH:mm').format(dt.toLocal());
  }

  Future<void> _closeService(int serviceId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Κλείσιμο Υπηρεσίας'),
        content: Text('Κλείσιμο "$name"; Θα σταλούν ειδοποιήσεις σε όλους τους αποδεκτούς εθελοντές.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ακύρωση')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
            child: const Text('Κλείσιμο'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final res = await _api.post('/services/$serviceId/close', body: {});
    if (!mounted) return;
    if (res.statusCode == 200) {
      setState(() {
        for (final s in _services) {
          if ((s as Map)['id'] == serviceId) {
            s['lifecycleStatus'] = 'closed';
            break;
          }
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Αποτυχία κλεισίματος υπηρεσίας')),
      );
    }
  }

  Future<void> _completeService(int serviceId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ολοκλήρωση Υπηρεσίας'),
        content: Text('Ολοκλήρωση "$name"; Όλοι οι αποδεκτοί εθελοντές θα σημανθούν ως παρόντες.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ακύρωση')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
            child: const Text('Ολοκλήρωση'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final res = await _api.post('/services/$serviceId/complete', body: {});
    if (!mounted) return;
    if (res.statusCode == 200) {
      setState(() {
        for (final s in _services) {
          if ((s as Map)['id'] == serviceId) {
            s['lifecycleStatus'] = 'completed';
            final us = s['userServices'];
            if (us is List) {
              for (final u in us) {
                if ((u as Map)['status'] == 'accepted') u['status'] = 'participated';
              }
            }
            break;
          }
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Αποτυχία ολοκλήρωσης υπηρεσίας')),
      );
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: isFrom ? 'Επιλέξτε ημ/νία έναρξης' : 'Επιλέξτε ημ/νία λήξης',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: Text('Παλαιότερες Υπηρεσίες — ${widget.departmentName}',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isSyncing ? null : _backgroundSync,
            tooltip: _isSyncing ? 'Συγχρονισμός...' : 'Ανανέωση',
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final isWide = box.maxWidth >= 800;
          final hPad = isWide ? 32.0 : 16.0;

          return Column(
            children: [
              // ── Search bar ──
              Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 8),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Αναζήτηση παλαιοτέρων...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),

              // ── Date range buttons (prominent) ──
              Padding(
                padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 8),
                child: Row(
                  children: [
                    Expanded(child: _buildDateButton(isFrom: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildDateButton(isFrom: false)),
                  ],
                ),
              ),

              // ── Lifecycle status tabs ──
              Padding(
                padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 8),
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      _lifecycleTab('active', 'Ενεργές'),
                      _lifecycleTab('closed', 'Κλειστές'),
                      _lifecycleTab('completed', 'Ολοκληρωμένες'),
                    ],
                  ),
                ),
              ),

              // ── Spec filter strip ──
              if (_specializations.isNotEmpty ||
                  _selectedSpecId != null ||
                  _fromDate != null ||
                  _toDate != null)
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: hPad),
                    children: [
                      ..._specializations.map((s) {
                        final specId = s['id'] as int;
                        final selected = _selectedSpecId == specId;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            avatar: Icon(Icons.workspace_premium,
                                size: 14,
                                color: selected
                                    ? const Color(0xFF7C3AED)
                                    : const Color(0xFF6B7280)),
                            label: Text(s['name'] ?? ''),
                            selected: selected,
                            onSelected: (_) {
                              setState(() =>
                                  _selectedSpecId = selected ? null : specId);
                              _load();
                            },
                            selectedColor: const Color(0xFFF5F3FF),
                            checkmarkColor: const Color(0xFF7C3AED),
                            side: BorderSide(
                                color: selected
                                    ? const Color(0xFFDDD6FE)
                                    : const Color(0xFFD1D5DB)),
                            visualDensity: VisualDensity.compact,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: selected
                                  ? const Color(0xFF6D28D9)
                                  : const Color(0xFF6B7280),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                        );
                      }),
                      if (_selectedSpecId != null ||
                          _fromDate != null ||
                          _toDate != null)
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _selectedSpecId = null;
                              _fromDate = null;
                              _toDate = null;
                              _selectedLifecycle = 'active';
                            });
                            _load();
                          },
                          icon: const Icon(Icons.clear_all, size: 16),
                          label: const Text('Καθαρισμός',
                              style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF4B5563),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                ),

              Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _loading
                        ? 'Φόρτωση...'
                        : 'Βρέθηκαν ${filtered.length} υπηρεσίες',
                    style:
                        tt.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // ── Table ──
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                        ? Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.history,
                                      size: 64, color: Color(0xFFD1D5DB)),
                                  const SizedBox(height: 12),
                                  Text('Δεν βρέθηκαν παλαιότερες',
                                      style: tt.bodyLarge?.copyWith(
                                          color: const Color(0xFF6B7280))),
                                  const SizedBox(height: 4),
                                  Text('Δοκιμάστε διαφορετικά φίλτρα',
                                      style: tt.bodySmall?.copyWith(
                                          color: const Color(0xFF9CA3AF))),
                                ]))
                        : _buildTable(filtered, isWide, hPad),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildDateButton({required bool isFrom}) {
    final date = isFrom ? _fromDate : _toDate;
    final isSet = date != null;
    final label = isSet
        ? '${isFrom ? 'Από' : 'Έως'}: ${_fmtDay(date)}'
        : (isFrom ? 'Από ημ/νία' : 'Έως ημ/νία');

    return GestureDetector(
      onTap: () => _pickDate(isFrom: isFrom),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSet ? const Color(0xFF7C3AED) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSet ? const Color(0xFF7C3AED) : const Color(0xFFD1D5DB),
          ),
          boxShadow: isSet
              ? [
                  BoxShadow(
                    color: const Color(0xFF7C3AED).withAlpha(50),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today,
              size: 14,
              color: isSet ? Colors.white : const Color(0xFF6B7280),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSet ? FontWeight.w600 : FontWeight.w400,
                  color: isSet ? Colors.white : const Color(0xFF6B7280),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSet)
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (isFrom) {
                      _fromDate = null;
                    } else {
                      _toDate = null;
                    }
                  });
                  _load();
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.close,
                      size: 14, color: Colors.white.withAlpha(220)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _lifecycleTab(String value, String label) {
    final selected = _selectedLifecycle == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (selected) return;
          setState(() => _selectedLifecycle = value);
          _load();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 4, offset: const Offset(0, 1))]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? const Color(0xFF7C3AED) : const Color(0xFF6B7280),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTable(List<dynamic> services, bool isWide, double hPad) {
    final startW = isWide ? 88.0 : 72.0;
    final endW = isWide ? 88.0 : 72.0;
    final countW = isWide ? 64.0 : 54.0;
    const chevronW = 24.0;
    const lifecycleW = 90.0;
    final nameFlex = isWide ? 3 : 2;

    Widget hdrText(String t) => Text(t,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF9CA3AF)),
        overflow: TextOverflow.ellipsis);

    return Column(
      children: [
        // Sticky header
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Row(
              children: [
                const SizedBox(width: 4), // aligns with left strip in rows
                Expanded(
                  flex: nameFlex,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: hdrText('Υπηρεσία'),
                  ),
                ),
                SizedBox(width: startW, child: hdrText('Έναρξη')),
                SizedBox(width: endW, child: hdrText('Λήξη')),
                if (isWide)
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: hdrText('Τοποθεσία'),
                    ),
                  ),
                SizedBox(width: countW, child: hdrText('Αιτήσεις')),
                const SizedBox(width: chevronW),
                const SizedBox(width: lifecycleW),
              ],
            ),
          ),
        ),

        // Scrollable rows
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(hPad, 6, hPad, 24),
              itemCount: services.length,
              separatorBuilder: (_, __) => const SizedBox(height: 3),
              itemBuilder: (ctx, i) {
                final svc = services[i] as Map<String, dynamic>;
                final auth = context.read<AuthProvider>();
                final lc = (svc['lifecycleStatus'] ?? 'active') as String;
                final svcId = svc['id'] as int;
                final svcName = (svc['name'] ?? '') as String;
                Widget lifecycleWidget;
                if (!auth.isAdmin && !auth.isMissionAdmin) {
                  lifecycleWidget = const SizedBox.shrink();
                } else if (lc == 'active') {
                  lifecycleWidget = SizedBox(
                    width: lifecycleW,
                    child: TextButton(
                      onPressed: () => _closeService(svcId, svcName),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFFD97706)),
                      child: const Text('Κλείσιμο', style: TextStyle(fontSize: 12)),
                    ),
                  );
                } else if (lc == 'closed') {
                  lifecycleWidget = SizedBox(
                    width: lifecycleW,
                    child: TextButton(
                      onPressed: () => _completeService(svcId, svcName),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFF059669)),
                      child: const Text('Ολοκλήρωση', style: TextStyle(fontSize: 12)),
                    ),
                  );
                } else {
                  lifecycleWidget = SizedBox(
                    width: lifecycleW,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6B7280).withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Ολοκληρώθηκε',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                    ),
                  );
                }
                return _PastServiceRow(
                  svc: svc,
                  isWide: isWide,
                  startW: startW,
                  endW: endW,
                  countW: countW,
                  nameFlex: nameFlex,
                  lifecycleWidget: lifecycleWidget,
                  onTap: () => _showPastServiceSheet(svc),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _showPastServiceSheet(Map<String, dynamic> svc) {
    final auth = context.read<AuthProvider>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final isAdmin = auth.isAdmin || auth.isMissionAdmin;

    final name = (svc['name'] ?? '').toString();
    final location = (svc['location'] ?? '').toString();
    final carrier = (svc['carrier'] ?? '').toString();
    final description = (svc['description'] ?? '').toString();
    final userServices = svc['userServices'] as List<dynamic>? ?? [];
    final enrolledCount =
        (svc['_count']?['userServices'] as int?) ?? userServices.length;

    final responsible =
        svc['responsibleUser'] as Map<String, dynamic>?;
    final rName = responsible != null
        ? '${responsible['forename'] ?? ''} ${responsible['surname'] ?? ''}'
            .trim()
        : '';

    final defaultHours = (svc['defaultHours'] as int?) ?? 0;
    final defaultHoursVol = (svc['defaultHoursVol'] as int?) ?? 0;
    final defaultHoursTraining = (svc['defaultHoursTraining'] as int?) ?? 0;
    final defaultHoursTrainers = (svc['defaultHoursTrainers'] as int?) ?? 0;
    final defaultHoursTEP = (svc['defaultHoursTEP'] as int?) ?? 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Title + completed badge
              Row(children: [
                Expanded(
                  child: Text(name,
                      style: tt.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1F2937))),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Ολοκληρωμένη',
                      style: TextStyle(
                          color: Color(0xFF059669),
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 16),
              // Info rows
              _sheetInfoRow(Icons.schedule, 'Ώρα',
                  '${_fmtDate(svc['startAt'] as String?)} → ${_fmtDate(svc['endAt'] as String?)}',
                  cs),
              if (location.isNotEmpty)
                _sheetInfoRow(Icons.location_on_outlined, 'Τοποθεσία',
                    location, cs),
              if (carrier.isNotEmpty)
                _sheetInfoRow(Icons.groups, 'Φορέας', carrier, cs),
              if (rName.isNotEmpty)
                _sheetInfoRow(
                    Icons.star_rounded, 'Υπεύθυνος', rName, cs),
              _sheetInfoRow(Icons.people_outline, 'Αιτήσεις',
                  '$enrolledCount μέλη', cs),
              // Description
              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Επιπλέον πληροφορίες',
                    style: tt.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF374151))),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Text(description,
                      style: tt.bodySmall
                          ?.copyWith(color: const Color(0xFF4B5563))),
                ),
              ],
              // Hours
              const SizedBox(height: 16),
              Text('Ώρες υπηρεσίας',
                  style: tt.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF374151))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (defaultHours > 0)
                    _sheetHourChip('Κάλυψη', defaultHours, cs.primary),
                  if (defaultHoursVol > 0)
                    _sheetHourChip('Εθελοντικές', defaultHoursVol,
                        const Color(0xFF7C3AED)),
                  if (defaultHoursTraining > 0)
                    _sheetHourChip('Επανεκπ.', defaultHoursTraining,
                        const Color(0xFFD97706)),
                  if (defaultHoursTrainers > 0)
                    _sheetHourChip('Εκπαιδευτών', defaultHoursTrainers,
                        const Color(0xFF059669)),
                  if (defaultHoursTEP > 0)
                    _sheetHourChip(
                        'ΤΕΠ', defaultHoursTEP, const Color(0xFF0891B2)),
                  if (defaultHours == 0 &&
                      defaultHoursVol == 0 &&
                      defaultHoursTraining == 0 &&
                      defaultHoursTrainers == 0 &&
                      defaultHoursTEP == 0)
                    _sheetHourChip(
                        'Κάλυψη', 0, const Color(0xFF6B7280)),
                ],
              ),
              // Applications section
              const SizedBox(height: 20),
              Row(children: [
                Text('Αιτήσεις',
                    style: tt.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6B7280).withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$enrolledCount',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6B7280))),
                ),
              ]),
              const SizedBox(height: 8),
              if (userServices.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Δεν υπάρχουν αιτήσεις',
                      style: tt.bodySmall
                          ?.copyWith(color: const Color(0xFF9CA3AF))),
                )
              else
                ...userServices.map((us) {
                  final user = (us as Map<String, dynamic>)['user']
                      as Map<String, dynamic>? ?? {};
                  final fullName =
                      '${user['forename'] ?? ''} ${user['surname'] ?? ''}'
                          .trim();
                  final eame = (user['eame'] ?? '').toString();
                  final displayName =
                      fullName.isNotEmpty ? fullName : eame;
                  final status = (us['status'] ?? '').toString();
                  final hours = (us['hours'] as int?) ?? 0;

                  final Color statusColor;
                  final String statusLabel;
                  switch (status) {
                    case 'accepted':
                      statusColor = const Color(0xFF059669);
                      statusLabel = 'Εγκρίθηκε';
                      break;
                    case 'rejected':
                      statusColor = const Color(0xFFDC2626);
                      statusLabel = 'Απορρίφθηκε';
                      break;
                    default:
                      statusColor = const Color(0xFFD97706);
                      statusLabel = 'Αίτηση';
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Expanded(
                        child: Text(displayName,
                            style: tt.bodySmall?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF1F2937)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (hours > 0) ...[
                        Text('${hours}h',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF6B7280))),
                        const SizedBox(width: 8),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: statusColor.withAlpha(60)),
                        ),
                        child: Text(statusLabel,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: statusColor)),
                      ),
                    ]),
                  );
                }),
              // Edit button — admin only
              if (isAdmin) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      final id = svc['id'];
                      Navigator.pop(ctx);
                      if (id != null) context.push('/admin/services/$id');
                    },
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Επεξεργασία υπηρεσίας',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetInfoRow(
      IconData icon, String label, String value, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 10),
        SizedBox(
          width: 90,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1F2937))),
        ),
      ]),
    );
  }

  Widget _sheetHourChip(String label, int hours, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 13, color: color),
          const SizedBox(width: 4),
          Text('$label: $hoursω',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}

class _PastServiceRow extends StatelessWidget {
  final Map<String, dynamic> svc;
  final bool isWide;
  final double startW;
  final double endW;
  final double countW;
  final int nameFlex;
  final Widget lifecycleWidget;
  final VoidCallback onTap;

  const _PastServiceRow({
    required this.svc,
    required this.isWide,
    required this.startW,
    required this.endW,
    required this.countW,
    required this.nameFlex,
    required this.lifecycleWidget,
    required this.onTap,
  });

  String _fmtShort(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '—';
    return DateFormat('dd/MM/yy').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final name = (svc['name'] ?? '').toString();
    final location = (svc['location'] ?? '').toString();
    final userServices = svc['userServices'] as List<dynamic>? ?? [];
    final enrolledCount =
        (svc['_count']?['userServices'] as int?) ?? userServices.length;
    final acceptedCount =
        userServices.where((us) => us['status'] == 'accepted').length;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // Green left strip
                Container(
                  width: 4,
                  decoration: const BoxDecoration(
                    color: Color(0xFF059669),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(8),
                      bottomLeft: Radius.circular(8),
                    ),
                  ),
                ),
                // Name column
                Expanded(
                  flex: nameFlex,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    child: Text(name,
                        style: tt.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
                // Start date
                SizedBox(
                  width: startW,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      _fmtShort(svc['startAt'] as String?),
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6B7280)),
                    ),
                  ),
                ),
                // End date
                SizedBox(
                  width: endW,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      _fmtShort(svc['endAt'] as String?),
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6B7280)),
                    ),
                  ),
                ),
                // Location (wide only)
                if (isWide)
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      child: Text(
                        location.isEmpty ? '—' : location,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6B7280)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                // Enrollment counts
                SizedBox(
                  width: countW,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.people,
                              size: 11, color: Color(0xFF6B7280)),
                          const SizedBox(width: 3),
                          Text('$enrolledCount',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF6B7280),
                                  fontWeight: FontWeight.w600)),
                        ]),
                        if (acceptedCount > 0) ...[
                          const SizedBox(height: 2),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.check,
                                size: 11, color: Color(0xFF059669)),
                            const SizedBox(width: 3),
                            Text('$acceptedCount',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF059669),
                                    fontWeight: FontWeight.w600)),
                          ]),
                        ],
                      ],
                    ),
                  ),
                ),
                // Chevron
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.chevron_right,
                      size: 16, color: Color(0xFF9CA3AF)),
                ),
                // Lifecycle action
                lifecycleWidget,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
