import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/service_provider.dart';
import '../services/api_client.dart';
import 'my_equipment_sheet.dart';

// ── Greek day-of-week names ──────────────────────────────────
const _greekDays = <int, String>{
  1: 'Δευτέρα',
  2: 'Τρίτη',
  3: 'Τετάρτη',
  4: 'Πέμπτη',
  5: 'Παρασκευή',
  6: 'Σάββατο',
  7: 'Κυριακή',
};

String _pad2(int n) => n.toString().padLeft(2, '0');

/// "Δευτέρα, 2/3" — used for day-group headers
String _dayLabel(DateTime dt) {
  final dayName = _greekDays[dt.weekday] ?? '';
  return '$dayName, ${dt.day}/${dt.month}';
}

/// "2/3 19:30 → 11/3 22:30" — shown as subtitle on each card
/// Shows dates when start and end are on different days; time-only when same day.
String _timeRange(Map<String, dynamic> svc) {
  final start = DateTime.tryParse(svc['startAt'] ?? '');
  final end   = DateTime.tryParse(svc['endAt']   ?? '');
  if (start == null) return '';

  final sTime = '${_pad2(start.hour)}:${_pad2(start.minute)}';
  final sDate = '${start.day}/${start.month}';

  if (end == null) return '$sDate $sTime';

  final eTime = '${_pad2(end.hour)}:${_pad2(end.minute)}';
  final eDate = '${end.day}/${end.month}';
  final sameDay = start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;

  if (sameDay) return '$sTime → $eTime';
  return '$sDate $sTime → $eDate $eTime';
}

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  int? _selectedSpecId; // null = show all, otherwise filter by specialization id
  final Set<int> _expandedIds = {};
  final _api = ApiClient();
  List<Map<String, dynamic>> _myEquipment = [];
  bool _equipmentLoading = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      context.read<ServiceProvider>().fetchMyServices();
    });
    _loadMyEquipment();
  }

  Future<void> _loadMyEquipment() async {
    setState(() => _equipmentLoading = true);
    try {
      final res = await _api.get('/auth/me/profile');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _myEquipment = (data['equipment'] as List<dynamic>?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [];
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _equipmentLoading = false);
  }

  void _showMyEquipmentSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => MyEquipmentSheet(
        equipment: _myEquipment,
        api: _api,
        onChanged: () {
          _loadMyEquipment();
        },
      ),
    );
  }

  // ── Filter: by specialization visibility ────────
  List<dynamic> get _filteredServices {
    final all = context.read<ServiceProvider>().services;
    if (_selectedSpecId == null) return all;
    return all.where((s) {
      final vis = s['visibility'] as List<dynamic>? ?? [];
      return vis.any((v) => v['specializationId'] == _selectedSpecId);
    }).toList();
  }

  int _countForSpec(int specId) {
    return context.read<ServiceProvider>().services.where((s) {
      final vis = s['visibility'] as List<dynamic>? ?? [];
      return vis.any((v) => v['specializationId'] == specId);
    }).length;
  }

  // ── Apply (request enrollment) ──────────────────
  void _applyToService(int serviceId) async {
    final auth = context.read<AuthProvider>();
    final userId = auth.user?['id'];
    if (userId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Υποβολή αίτησης'),
        content: const Text('Θέλετε να υποβάλετε αίτηση για αυτή την υπηρεσία;'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Υποβολή')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final err = await context.read<ServiceProvider>().enrollSelf(serviceId, userId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ?? 'Η αίτηση υποβλήθηκε επιτυχώς!'),
        backgroundColor: err != null ? Colors.red.shade700 : const Color(0xFF059669),
      ),
    );
  }

  // ── Withdraw (cancel pending request) ────────────
  void _withdrawFromService(int serviceId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ακύρωση αίτησης'),
        content: const Text('Θέλετε να ακυρώσετε την αίτησή σας;'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Όχι')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            child: const Text('Ακύρωση αίτησης'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final err = await context.read<ServiceProvider>().unenrollSelf(serviceId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ?? 'Η αίτηση ακυρώθηκε'),
        backgroundColor: err != null ? Colors.red.shade700 : const Color(0xFF059669),
      ),
    );
  }

  // ── Create dialog (admin) ───────────────────────
  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final deptIdCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Νέα Υπηρεσία'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Όνομα')),
            const SizedBox(height: 12),
            TextField(controller: deptIdCtrl, decoration: const InputDecoration(labelText: 'Department ID'), keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Περιγραφή'), maxLines: 2),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () async {
              final data = <String, dynamic>{
                'name': nameCtrl.text.trim(),
                'departmentId': int.tryParse(deptIdCtrl.text.trim()) ?? 0,
              };
              if (descCtrl.text.isNotEmpty) data['description'] = descCtrl.text.trim();
              final result = await context.read<ServiceProvider>().create(data);
              if (ctx.mounted) Navigator.pop(ctx);
              if (result is String && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
              }
            },
            child: const Text('Δημιουργία'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final svcProv = context.watch<ServiceProvider>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final name = auth.displayName.isNotEmpty
        ? auth.displayName
        : (auth.user?['ename'] ?? 'Χρήστης');

    final userSpecs = auth.specializations; // [{id, name, description}, ...]

    // Build dynamic spec filters from services that actually exist
    final allServices = svcProv.services;
    final specMap = <int, String>{}; // id -> name
    for (final svc in allServices) {
      final vis = svc['visibility'] as List<dynamic>? ?? [];
      for (final v in vis) {
        final spec = v['specialization'] as Map<String, dynamic>?;
        if (spec != null) {
          specMap[spec['id'] as int] = spec['name'] as String? ?? '';
        }
      }
    }
    // Sort by name for consistent order
    final dynamicSpecs = specMap.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    final filtered = _filteredServices;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => svcProv.fetchMyServices(),
          child: CustomScrollView(
            slivers: [
              // ── Top bar ──────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      Image.asset('assets/logo.png', height: 32),
                      const SizedBox(width: 10),
                      Text('Mitroo',
                          style: tt.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700, color: cs.primary)),
                      const Spacer(),
                      // My Equipment button with badge
                      Stack(
                        children: [
                          IconButton(
                            onPressed: _showMyEquipmentSheet,
                            icon: const Icon(Icons.inventory_2_outlined),
                            tooltip: 'Ο Εξοπλισμός Μου',
                            style: IconButton.styleFrom(
                              backgroundColor: cs.primary.withAlpha(20),
                            ),
                          ),
                          if (_myEquipment.isNotEmpty)
                            Positioned(
                              right: 2,
                              top: 2,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade600,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                child: Text(
                                  '${_myEquipment.length}',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => context.push('/profile'),
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: cs.primary,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'U',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Specialization filter bubbles ────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                  child: SizedBox(
                    height: 40,
                    child: dynamicSpecs.isEmpty
                        ? const SizedBox.shrink()
                        : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemCount: dynamicSpecs.length,
                      itemBuilder: (context, i) {
                        final specId = dynamicSpecs[i].key;
                        final specName = dynamicSpecs[i].value;
                        final count = _countForSpec(specId);
                        final selected = _selectedSpecId == specId;

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedSpecId = selected ? null : specId;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color:
                                  selected ? cs.primary : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? cs.primary
                                    : const Color(0xFFD1D5DB),
                              ),
                            ),
                            child: Text(
                              '$specName($count)',
                              style: tt.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color:
                                    selected ? Colors.white : const Color(0xFF374151),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              // ── Loading indicator ────────────────────
              if (svcProv.loading)
                const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()))

              // ── Empty state ──────────────────────────
              else if (filtered.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_busy,
                            size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('Δεν υπάρχουν υπηρεσίες',
                            style: tt.bodyLarge
                                ?.copyWith(color: Colors.grey)),
                      ],
                    ),
                  ),
                )

              // ── Service list grouped by day ────────────
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: Builder(builder: (context) {
                    // Build a flat list interleaving day-header strings and service maps
                    final List<dynamic> rows = [];
                    String? lastKey;
                    for (final svc in filtered) {
                      final start = DateTime.tryParse(svc['startAt'] ?? '');
                      final key = start != null
                          ? '${start.year}-${start.month}-${start.day}'
                          : 'none';
                      if (key != lastKey) {
                        rows.add(start != null ? _dayLabel(start) : '');
                        lastKey = key;
                      }
                      rows.add(svc);
                    }

                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final row = rows[i];
                          // Day header
                          if (row is String) {
                            return Padding(
                              padding: EdgeInsets.only(
                                  top: i == 0 ? 8 : 20, bottom: 8),
                              child: Row(children: [
                                Container(
                                  width: 4, height: 18,
                                  margin: const EdgeInsets.only(right: 10),
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                Text(row,
                                    style: tt.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: cs.primary,
                                      letterSpacing: 0.2,
                                    )),
                              ]),
                            );
                          }
                          // Service card
                          final svc = row as Map<String, dynamic>;
                          final svcId = svc['id'] as int;
                          final isExpanded = _expandedIds.contains(svcId);
                          return _ServiceAccordion(
                            svc: svc,
                            isExpanded: isExpanded,
                            onToggle: () {
                              setState(() {
                                if (isExpanded) {
                                  _expandedIds.remove(svcId);
                                } else {
                                  _expandedIds.add(svcId);
                                }
                              });
                            },
                            onApply: () => _applyToService(svcId),
                            onUnenroll: () => _withdrawFromService(svcId),

                          );
                        },
                        childCount: rows.length,
                      ),
                    );
                  }),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 90)),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Accordion card for a single service
// ═══════════════════════════════════════════════════════════════
class _ServiceAccordion extends StatelessWidget {
  final Map<String, dynamic> svc;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onApply;
  final VoidCallback onUnenroll;
  const _ServiceAccordion({
    required this.svc,
    required this.isExpanded,
    required this.onToggle,
    required this.onApply,
    required this.onUnenroll,
  });

  /// Check if the current user already has an enrollment record
  String? _enrollmentStatus() {
    final us = svc['userServices'] as List<dynamic>?;
    if (us == null || us.isEmpty) return null;
    return us.first['status'] as String?;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final carrier = (svc['carrier'] as String? ?? '').isNotEmpty
        ? svc['carrier'] as String
        : (svc['name'] as String? ?? 'Υπηρεσία');
    final timeRange = _timeRange(svc);
    final location = svc['location'] as String? ?? '';
    final description = svc['description'] as String? ?? '';

    final defaultHours = svc['defaultHours'] ?? 0;
    final defaultHoursVol = svc['defaultHoursVol'] ?? 0;
    final defaultHoursTraining = svc['defaultHoursTraining'] ?? 0;
    final defaultHoursTrainers = svc['defaultHoursTrainers'] ?? 0;

    final status = _enrollmentStatus();
    final isApplied = status != null;
    final Color accentColor = isApplied ? _statusColor(status!) : cs.primary;
    final Color lightBg = isApplied ? _statusBgColor(status!) : cs.primary.withAlpha(8);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isExpanded ? 20 : 10),
              blurRadius: isExpanded ? 12 : 6,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: isApplied
                ? accentColor.withAlpha(80)
                : isExpanded
                    ? cs.primary.withAlpha(60)
                    : const Color(0xFFE5E7EB),
            width: isApplied ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // ── Colored left-accent header ───────────
            InkWell(
              onTap: status == 'accepted'
                  ? () => context.push('/services/${svc['id']}')
                  : onToggle,
              child: Container(
                decoration: BoxDecoration(
                  color: isApplied
                      ? lightBg
                      : isExpanded
                          ? cs.primary.withAlpha(8)
                          : Colors.white,
                ),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      // Left accent bar
                      Container(
                        width: 4,
                        color: accentColor,
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        isExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: accentColor,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                carrier,
                                style: tt.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: accentColor,
                                ),
                              ),
                              if (timeRange.isNotEmpty) ...
                                [
                                  const SizedBox(height: 2),
                                  Text(
                                    timeRange,
                                    style: tt.bodySmall?.copyWith(
                                      color: accentColor.withAlpha(180),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                            ],
                          ),
                        ),
                      ),
                      if (isApplied)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: accentColor.withAlpha(25),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _statusLabel(status!),
                              style: tt.labelSmall?.copyWith(
                                color: accentColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Expandable body ──────────────────────
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(color: Colors.grey.shade200, height: 1),
                    const SizedBox(height: 14),

                    // Responsible user
                    Builder(builder: (context) {
                      final responsible = svc['responsibleUser'] as Map<String, dynamic>?;
                      if (responsible == null) return const SizedBox.shrink();
                      final rName = '${responsible['forename'] ?? ''} ${responsible['surname'] ?? ''}'.trim();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.star_rounded, size: 16, color: Color(0xFF7C3AED)),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 140,
                              child: Text(
                                'Υπεύθυνος',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF374151)),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7C3AED).withAlpha(15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  rName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF7C3AED),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    // Location
                    if (location.isNotEmpty)
                      _DetailRow(icon: Icons.location_on_outlined, label: 'Τοποθεσία', value: location),

                    // ── Hour chips ─────────────────────
                    const SizedBox(height: 4),
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
                          _HourChip(label: 'Ώρες Κάλυψης', hours: defaultHours, color: cs.primary),
                        if (defaultHoursVol > 0)
                          _HourChip(label: 'Εθελοντικές Ώρες', hours: defaultHoursVol, color: const Color(0xFF7C3AED)),
                        if (defaultHoursTraining > 0)
                          _HourChip(label: 'Ώρες Επανεκπαίδευσης', hours: defaultHoursTraining, color: const Color(0xFFD97706)),
                        if (defaultHoursTrainers > 0)
                          _HourChip(label: 'Ώρες Εκπαιδευτών', hours: defaultHoursTrainers, color: const Color(0xFF059669)),
                        if (defaultHours == 0 && defaultHoursVol == 0 &&
                            defaultHoursTraining == 0 && defaultHoursTrainers == 0)
                          _HourChip(label: 'Ώρες Κάλυψης', hours: 0, color: Colors.grey),
                      ],
                    ),

                    // Extra info
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _DetailRow(icon: Icons.info_outline, label: 'Επιπλέον πληροφορίες', value: description),
                    ],

                    const SizedBox(height: 18),

                    // ── Action row ──────────────────
                    Row(
                      children: [
                        // Apply / Applied button
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          child: isApplied
                              ? status == 'requested'
                                  // ── Pending: tappable to withdraw ──
                                  ? OutlinedButton.icon(
                                      onPressed: onUnenroll,
                                      icon: const Icon(Icons.close_rounded, size: 18),
                                      label: const Text('ΑΚΥΡΩΣΗ'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _statusColor(status),
                                        side: BorderSide(color: _statusColor(status)),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 20, vertical: 10),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                    )
                                  // ── Accepted/Rejected: non-interactive ──
                                  : OutlinedButton.icon(
                                      onPressed: null,
                                      icon: Icon(
                                        status == 'accepted'
                                            ? Icons.check_circle
                                            : Icons.cancel,
                                        size: 18,
                                      ),
                                      label: Text(_statusButtonLabel(status)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _statusColor(status),
                                        side: BorderSide(color: _statusColor(status)),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 20, vertical: 10),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                    )
                              : FilledButton.icon(
                                  onPressed: onApply,
                                  icon: const Icon(Icons.send_rounded, size: 16),
                                  label: const Text('ΑΙΤΗΣΗ',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5)),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: cs.primary,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: TextButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Προστέθηκε στο ημερολόγιο')),
                              );
                            },
                            icon: Icon(Icons.calendar_today, size: 15, color: cs.primary),
                            label: Text(
                              'Προσθήκη στο ημερολόγιο',
                              style: tt.bodySmall?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // ── Details button (accepted members) ──
                    if (status == 'accepted') ...[                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => context.push('/services/${svc['id']}'),
                        icon: const Icon(Icons.open_in_new, size: 15),
                        label: const Text('Λεπτομέρειες',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            ),
          ],
        ),
      ),
    );
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'accepted': return 'Εγκρίθηκε';
      case 'rejected': return 'Απορρίφθηκε';
      default:         return 'Αίτηση';
    }
  }

  static String _statusButtonLabel(String status) {
    switch (status) {
      case 'accepted': return 'ΕΓΚΡΙΘΗΚΕ';
      case 'rejected': return 'ΑΠΟΡΡΙΦΘΗΚΕ';
      default:         return 'ΥΠΟΒΛΗΘΗΚΕ';
    }
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'accepted': return const Color(0xFF059669);
      case 'rejected': return const Color(0xFFDC2626);
      default:         return const Color(0xFFD97706);
    }
  }

  static Color _statusBgColor(String status) {
    switch (status) {
      case 'accepted': return const Color(0xFFF0FDF4); // light green
      case 'rejected': return const Color(0xFFFEF2F2); // light red
      default:         return const Color(0xFFFFFBEB); // light amber
    }
  }
}

// ═══════════════════════════════════════════════════════════════
//  Label: value row with icon
// ═══════════════════════════════════════════════════════════════
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF6B7280)),
          const SizedBox(width: 8),
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: tt.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF374151)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: tt.bodySmall?.copyWith(color: const Color(0xFF4B5563)),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Chip showing hours for a specific type
// ═══════════════════════════════════════════════════════════════
class _HourChip extends StatelessWidget {
  final String label;
  final int hours;
  final Color color;
  const _HourChip({required this.label, required this.hours, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$label: $hours\u03C9',
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
