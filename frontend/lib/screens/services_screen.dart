import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
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

class _ServicesScreenState extends State<ServicesScreen>
    with SingleTickerProviderStateMixin {
  int? _selectedSpecId; // null = show all, otherwise filter by specialization id
  final Set<int> _expandedIds = {};
  final _api = ApiClient();
  List<Map<String, dynamic>> _myEquipment = [];
  bool _equipmentLoading = false;

  late final TabController _tabController;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 1);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    Future.microtask(() {
      context.read<ServiceProvider>().fetchMyServices();
    });
    _loadMyEquipment();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
                      // My accepted services button
                      Material(
                        color: cs.primary.withAlpha(15),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: () => _showMyAcceptedServicesSheet(context),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.assignment_turned_in_outlined, size: 18, color: cs.primary),
                                const SizedBox(width: 8),
                                Text('Οι υπηρεσίες μου',
                                    style: tt.labelLarge?.copyWith(
                                        fontWeight: FontWeight.w700, color: cs.primary)),
                              ],
                            ),
                          ),
                        ),
                      ),
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

              // ── Tab bar ──────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: Colors.white,
                      unselectedLabelColor: const Color(0xFF6B7280),
                      labelStyle: tt.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                      unselectedLabelStyle: tt.labelMedium?.copyWith(fontWeight: FontWeight.w500),
                      dividerHeight: 0,
                      indicatorPadding: const EdgeInsets.all(3),
                      tabs: const [
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.list_alt_rounded, size: 16),
                              SizedBox(width: 6),
                              Text('Λίστα'),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.calendar_month_rounded, size: 16),
                              SizedBox(width: 6),
                              Text('Ημερολόγιο'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ═══ TAB 0: LIST VIEW ═══════════════════════
              if (_tabController.index == 0) ...[
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
                            final svc = row as Map<String, dynamic>;
                            final svcId = svc['id'] as int;
                            return _CalendarServiceCard(
                              svc: svc,
                              showEnrollmentNeed: true,
                              onTap: () => _showServiceInfoSheet(context, svc),
                              onApply: () => _applyToService(svcId),
                              onUnenroll: () => _withdrawFromService(svcId),
                            );
                          },
                          childCount: rows.length,
                        ),
                      );
                    }),
                  ),
              ],

              // ═══ TAB 1: CALENDAR VIEW ═══════════════════
              if (_tabController.index == 1) ...[
                if (svcProv.loading)
                  const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()))
                else
                  SliverToBoxAdapter(
                    child: _buildCalendarView(context, filtered, cs, tt),
                  ),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 90)),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  "My Accepted Services" Bottom Sheet
  // ═══════════════════════════════════════════════════════════
  void _showMyAcceptedServicesSheet(BuildContext context) {
    final svcProv = context.read<ServiceProvider>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Filter only services where current user is accepted
    final accepted = svcProv.services.where((s) {
      final us = s['userServices'] as List<dynamic>?;
      if (us == null || us.isEmpty) return false;
      return us.first['status'] == 'accepted';
    }).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: Row(
                children: [
                  Icon(Icons.assignment_turned_in, size: 22, color: cs.primary),
                  const SizedBox(width: 10),
                  Text('Οι υπηρεσίες μου',
                      style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800, color: const Color(0xFF1F2937))),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669).withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${accepted.length}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF059669)),
                    ),
                  ),
                ],
              ),
            ),
            if (accepted.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_available, size: 48, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('Δεν έχετε εγκεκριμένες υπηρεσίες',
                          style: tt.bodyMedium?.copyWith(color: Colors.grey)),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: accepted.length,
                  itemBuilder: (_, i) {
                    final svc = Map<String, dynamic>.from(accepted[i] as Map);
                    return _CalendarServiceCard(
                      svc: svc,
                      onTap: () {
                        Navigator.pop(ctx);
                        context.push('/services/${svc['id']}');
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Calendar View Builder
  // ═══════════════════════════════════════════════════════════
  Widget _buildCalendarView(
    BuildContext context,
    List<dynamic> filtered,
    ColorScheme cs,
    TextTheme tt,
  ) {
    // ── Map services to their start dates ────────────
    final Map<DateTime, List<Map<String, dynamic>>> servicesByDate = {};
    for (final svc in filtered) {
      final start = DateTime.tryParse(svc['startAt'] ?? '');
      if (start == null) continue;
      final dateKey = DateTime(start.year, start.month, start.day);
      servicesByDate.putIfAbsent(dateKey, () => []);
      servicesByDate[dateKey]!.add(Map<String, dynamic>.from(svc as Map));
    }

    // ── Services for the selected day ────────────────
    final selectedDayKey = _selectedDay != null
        ? DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day)
        : null;
    final selectedDayServices = selectedDayKey != null
        ? (servicesByDate[selectedDayKey] ?? [])
        : <Map<String, dynamic>>[];

    // ── Recommended: sorted by least enrollments ─────
    final allFiltered = List<Map<String, dynamic>>.from(
      filtered.map((s) => Map<String, dynamic>.from(s as Map)),
    );
    allFiltered.sort((a, b) {
      final aCount = (a['_count'] as Map?)?['userServices'] ?? 0;
      final bCount = (b['_count'] as Map?)?['userServices'] ?? 0;
      return (aCount as int).compareTo(bCount as int);
    });
    // Only show upcoming services (start date >= today)
    // Exclude services already shown in the selected day section
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDayIds = selectedDayServices.map((s) => s['id']).toSet();
    final recommended = allFiltered.where((s) {
      final start = DateTime.tryParse(s['startAt'] ?? '');
      if (start == null) return false;
      if (selectedDayIds.contains(s['id'])) return false;
      return DateTime(start.year, start.month, start.day).isAfter(today) ||
          DateTime(start.year, start.month, start.day).isAtSameMomentAs(today);
    }).take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Calendar widget ────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(12),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TableCalendar(
              firstDay: DateTime.utc(2024, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              },
              onPageChanged: (focusedDay) {
                _focusedDay = focusedDay;
              },
              locale: 'el_GR',
              startingDayOfWeek: StartingDayOfWeek.monday,
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: tt.titleSmall!.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1F2937),
                ),
                leftChevronIcon: Icon(Icons.chevron_left, color: cs.primary),
                rightChevronIcon: Icon(Icons.chevron_right, color: cs.primary),
                headerPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: tt.labelSmall!.copyWith(
                  color: const Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
                weekendStyle: tt.labelSmall!.copyWith(
                  color: const Color(0xFF9CA3AF),
                  fontWeight: FontWeight.w600,
                ),
              ),
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                todayDecoration: BoxDecoration(
                  color: cs.primary.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                todayTextStyle: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
                selectedDecoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
                selectedTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                defaultTextStyle: const TextStyle(
                  color: Color(0xFF374151),
                  fontWeight: FontWeight.w500,
                ),
                weekendTextStyle: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w500,
                ),
                cellMargin: const EdgeInsets.all(4),
              ),
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, date, events) {
                  final dayKey = DateTime(date.year, date.month, date.day);
                  final services = servicesByDate[dayKey];
                  if (services == null || services.isEmpty) return null;

                  // Sum total enrollments for the day
                  int totalEnrollments = 0;
                  for (final s in services) {
                    totalEnrollments += ((s['_count'] as Map?)?['userServices'] ?? 0) as int;
                  }

                  // Color based on enrollment density
                  final Color dotColor;
                  if (totalEnrollments == 0) {
                    dotColor = const Color(0xFFEF4444); // red – needs people
                  } else if (totalEnrollments <= 2) {
                    dotColor = const Color(0xFFF59E0B); // amber – few people
                  } else if (totalEnrollments <= 5) {
                    dotColor = const Color(0xFFEF4444); // red – moderate
                  } else {
                    dotColor = const Color(0xFF10B981); // green – well staffed
                  }

                  return Positioned(
                    bottom: 1,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: services.length > 1 ? 18 : 8,
                          height: 6,
                          decoration: BoxDecoration(
                            color: dotColor,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        if (services.length > 2) ...[
                          const SizedBox(width: 2),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: dotColor.withAlpha(120),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // ── Color legend ───────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _legendDot(const Color(0xFFEF4444), 'Χωρίς αιτήσεις'),
              _legendDot(const Color(0xFFF59E0B), 'Λίγες (1-2)'),
              _legendDot(const Color(0xFFEF4444), 'Μέτριες (3-5)'),
              _legendDot(const Color(0xFF10B981), 'Πολλές (6+)'),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Selected day services ──────────────────────
        if (_selectedDay != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 4, height: 18,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  _dayLabel(_selectedDay!),
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${selectedDayServices.length} υπηρεσίες',
                    style: tt.labelSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (selectedDayServices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.event_available, size: 32, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    Text(
                      'Δεν υπάρχουν υπηρεσίες αυτή την ημέρα',
                      style: tt.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else
            ...selectedDayServices.map((svc) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _CalendarServiceCard(
                    svc: svc,
                    onTap: () => _showServiceInfoSheet(context, svc),
                    onApply: () => _applyToService(svc['id'] as int),
                    onUnenroll: () => _withdrawFromService(svc['id'] as int),
                  ),
                )),
          const SizedBox(height: 20),
        ],

        // ── Recommended services ─────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Προτεινόμενες Υπηρεσίες',
                style: tt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1F2937),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Υπηρεσίες που χρειάζονται περισσότερα μέλη',
            style: tt.bodySmall?.copyWith(color: const Color(0xFF9CA3AF)),
          ),
        ),
        const SizedBox(height: 10),

        if (recommended.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Text(
                'Δεν υπάρχουν προτεινόμενες υπηρεσίες',
                style: tt.bodySmall?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...recommended.map((svc) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _CalendarServiceCard(
                  svc: svc,
                  showEnrollmentNeed: true,
                  onTap: () => _showServiceInfoSheet(context, svc),
                  onApply: () => _applyToService(svc['id'] as int),
                  onUnenroll: () => _withdrawFromService(svc['id'] as int),
                ),
              )),

        const SizedBox(height: 16),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Service Info Bottom Sheet
  // ═══════════════════════════════════════════════════════════
  void _showServiceInfoSheet(BuildContext context, Map<String, dynamic> svc) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final carrier = (svc['carrier'] as String? ?? '').isNotEmpty
        ? svc['carrier'] as String
        : (svc['name'] as String? ?? 'Υπηρεσία');
    final timeRange = _timeRange(svc);
    final location = svc['location'] as String? ?? '';
    final description = svc['description'] as String? ?? '';
    final enrollCount = ((svc['_count'] as Map?)?['userServices'] ?? 0) as int;

    final defaultHours = svc['defaultHours'] ?? 0;
    final defaultHoursVol = svc['defaultHoursVol'] ?? 0;
    final defaultHoursTraining = svc['defaultHoursTraining'] ?? 0;
    final defaultHoursTrainers = svc['defaultHoursTrainers'] ?? 0;
    final defaultHoursTEP = svc['defaultHoursTEP'] ?? 0;

    final responsible = svc['responsibleUser'] as Map<String, dynamic>?;
    final rName = responsible != null
        ? '${responsible['forename'] ?? ''} ${responsible['surname'] ?? ''}'.trim()
        : '';

    final us = svc['userServices'] as List<dynamic>?;
    final status = (us != null && us.isNotEmpty) ? us.first['status'] as String? : null;
    final isApplied = status != null;
    final svcId = svc['id'] as int;

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
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title
              Text(
                carrier,
                style: tt.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 12),

              // Time
              if (timeRange.isNotEmpty)
                _sheetInfoRow(Icons.schedule, 'Ώρα', timeRange, cs),

              // Location
              if (location.isNotEmpty)
                _sheetInfoRow(Icons.location_on_outlined, 'Τοποθεσία', location, cs),

              // Responsible
              if (rName.isNotEmpty)
                _sheetInfoRow(Icons.star_rounded, 'Υπεύθυνος', rName, cs),

              // Enrollments count
              _sheetInfoRow(Icons.people_outline, 'Αιτήσεις', '$enrollCount μέλη', cs),

              // Description
              if (description.isNotEmpty) ...[                const SizedBox(height: 12),
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
                      style: tt.bodySmall?.copyWith(color: const Color(0xFF4B5563))),
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
                    _sheetHourChip('Εθελοντικές', defaultHoursVol, const Color(0xFF7C3AED)),
                  if (defaultHoursTraining > 0)
                    _sheetHourChip('Επανεκπ.', defaultHoursTraining, const Color(0xFFD97706)),
                  if (defaultHoursTrainers > 0)
                    _sheetHourChip('Εκπαιδευτών', defaultHoursTrainers, const Color(0xFF059669)),
                  if (defaultHoursTEP > 0)
                    _sheetHourChip('ΤΕΠ', defaultHoursTEP, const Color(0xFF0891B2)),
                  if (defaultHours == 0 && defaultHoursVol == 0 &&
                      defaultHoursTraining == 0 && defaultHoursTrainers == 0 && defaultHoursTEP == 0)
                    _sheetHourChip('Κάλυψη', 0, Colors.grey),
                ],
              ),

              const SizedBox(height: 24),

              // Action buttons
              if (isApplied)
                status == 'requested'
                    ? SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _withdrawFromService(svcId);
                          },
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('Ακύρωση αίτησης'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFD97706),
                            side: const BorderSide(color: Color(0xFFD97706)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      )
                    : SizedBox(
                        width: double.infinity,
                        child: status == 'accepted'
                            ? FilledButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  context.push('/services/$svcId');
                                },
                                icon: const Icon(Icons.open_in_new, size: 16),
                                label: const Text('Λεπτομέρειες'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF059669),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              )
                            : OutlinedButton.icon(
                                onPressed: null,
                                icon: const Icon(Icons.cancel, size: 18),
                                label: const Text('Απορρίφθηκε'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFDC2626),
                                  side: const BorderSide(color: Color(0xFFDC2626)),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                      )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _applyToService(svcId);
                    },
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Υποβολή Αίτησης',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetInfoRow(IconData icon, String label, String value, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF1F2937))),
          ),
        ],
      ),
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
          Text('$label: ${hours}ω',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
        ),
      ],
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
    final defaultHoursTEP = svc['defaultHoursTEP'] ?? 0;

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
                        if (defaultHoursTEP > 0)
                          _HourChip(label: 'Ώρες ΤΕΠ', hours: defaultHoursTEP, color: const Color(0xFF0891B2)),
                        if (defaultHours == 0 && defaultHoursVol == 0 &&
                            defaultHoursTraining == 0 && defaultHoursTrainers == 0 && defaultHoursTEP == 0)
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

// ═══════════════════════════════════════════════════════════════
//  Compact card used in Calendar view & Recommended section
// ═══════════════════════════════════════════════════════════════
class _CalendarServiceCard extends StatelessWidget {
  final Map<String, dynamic> svc;
  final VoidCallback? onTap;
  final VoidCallback? onApply;
  final VoidCallback? onUnenroll;
  final bool showEnrollmentNeed;

  const _CalendarServiceCard({
    required this.svc,
    this.onTap,
    this.onApply,
    this.onUnenroll,
    this.showEnrollmentNeed = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final carrier = (svc['carrier'] as String? ?? '').isNotEmpty
        ? svc['carrier'] as String
        : (svc['name'] as String? ?? 'Υπηρεσία');
    final timeRange = _timeRange(svc);
    final location = svc['location'] as String? ?? '';
    final enrollCount = ((svc['_count'] as Map?)?['userServices'] ?? 0) as int;

    // Enrollment status for current user
    final us = svc['userServices'] as List<dynamic>?;
    final status = (us != null && us.isNotEmpty) ? us.first['status'] as String? : null;
    final isApplied = status != null;

    final Color accentColor;
    if (isApplied) {
      switch (status) {
        case 'accepted':
          accentColor = const Color(0xFF059669);
          break;
        case 'rejected':
          accentColor = const Color(0xFFDC2626);
          break;
        default:
          accentColor = const Color(0xFFD97706);
      }
    } else {
      accentColor = cs.primary;
    }

    // Need color for recommended
    final Color needColor;
    final String needLabel;
    if (enrollCount == 0) {
      needColor = const Color(0xFFEF4444);
      needLabel = 'Χρειάζεται μέλη';
    } else if (enrollCount <= 2) {
      needColor = const Color(0xFFF59E0B);
      needLabel = 'Λίγες αιτήσεις';
    } else {
      needColor = const Color(0xFFEF4444);
      needLabel = '$enrollCount αιτήσεις';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isApplied
                    ? accentColor.withAlpha(60)
                    : const Color(0xFFE5E7EB),
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  // Left accent strip
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                      ),
                    ),
                  ),
                  // Content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  carrier,
                                  style: tt.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1F2937),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Time & location row
                          Row(
                            children: [
                              if (timeRange.isNotEmpty) ...[
                                Icon(Icons.schedule, size: 13, color: Colors.grey.shade500),
                                const SizedBox(width: 4),
                                Text(
                                  timeRange,
                                  style: tt.bodySmall?.copyWith(
                                    color: const Color(0xFF6B7280),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                              if (timeRange.isNotEmpty && location.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Container(
                                    width: 3, height: 3,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade400,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              if (location.isNotEmpty) ...[
                                Icon(Icons.location_on_outlined, size: 13, color: Colors.grey.shade500),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    location,
                                    style: tt.bodySmall?.copyWith(
                                      color: const Color(0xFF6B7280),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          // Enrollment info & apply button
                          if (showEnrollmentNeed || onApply != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: needColor.withAlpha(18),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: needColor.withAlpha(50)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.people_outline, size: 13, color: needColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        needLabel,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: needColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                if (!isApplied && onApply != null)
                                  SizedBox(
                                    height: 28,
                                    child: FilledButton.icon(
                                      onPressed: onApply,
                                      icon: const Icon(Icons.send_rounded, size: 12),
                                      label: const Text('Αίτηση',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: cs.primary,
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(7),
                                        ),
                                      ),
                                    ),
                                  )
                                else if (isApplied && status == 'requested' && onUnenroll != null)
                                  SizedBox(
                                    height: 28,
                                    child: OutlinedButton.icon(
                                      onPressed: onUnenroll,
                                      icon: const Icon(Icons.close_rounded, size: 12),
                                      label: const Text('Ακύρωση',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFFD97706),
                                        side: const BorderSide(color: Color(0xFFD97706)),
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(7),
                                        ),
                                      ),
                                    ),
                                  )
                                else if (isApplied)
                                  Text(
                                    status == 'accepted' ? '✓ Εγκρίθηκε' : status == 'rejected' ? '✗ Απορρίφθηκε' : '⏳ Αίτηση',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accentColor),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
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
