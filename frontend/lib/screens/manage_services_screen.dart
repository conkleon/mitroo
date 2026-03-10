import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/service_provider.dart';
import '../services/api_client.dart';

/// Lists all services for a given department using a card layout.
/// Enrollments are shown inline inside each card.
class ManageServicesScreen extends StatefulWidget {
  final int departmentId;
  final String departmentName;

  const ManageServicesScreen({
    super.key,
    required this.departmentId,
    required this.departmentName,
  });

  @override
  State<ManageServicesScreen> createState() => _ManageServicesScreenState();
}

class _ManageServicesScreenState extends State<ManageServicesScreen> {
  final _api = ApiClient();
  List<dynamic> _services = [];
  bool _loading = true;
  String _search = '';
  final Set<int> _expandedCards = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ManageServicesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.departmentId != widget.departmentId) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get(
          '/services?departmentId=${widget.departmentId}&includeEnrollments=true');
      if (res.statusCode == 200 && mounted) {
        _services = jsonDecode(res.body);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<dynamic> get _filtered {
    var list = List<dynamic>.from(_services);
    final now = DateTime.now();

    // Show only current & upcoming (exclude past)
    list = list.where((s) {
      final end = DateTime.tryParse(s['endAt'] ?? '');
      if (end != null && end.isBefore(now)) return false;
      return true;
    }).toList();

    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((s) {
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

    // Sort: closest start date first
    list.sort((a, b) {
      final aDate = DateTime.tryParse(a['startAt'] ?? '') ?? DateTime(2099);
      final bDate = DateTime.tryParse(b['startAt'] ?? '') ?? DateTime(2099);
      return aDate.compareTo(bDate);
    });

    return list;
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '—';
    return DateFormat('dd/MM/yy HH:mm').format(dt.toLocal());
  }

  String _statusLabel(Map<String, dynamic> svc) {
    final now = DateTime.now();
    final start = DateTime.tryParse(svc['startAt'] ?? '');
    final end = DateTime.tryParse(svc['endAt'] ?? '');
    if (start == null) return 'Χωρίς ημ/νία';
    if (start.isAfter(now)) return 'Προσεχής';
    if (end != null && end.isBefore(now)) return 'Ολοκληρωμένη';
    return 'Ενεργή';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Προσεχής':
        return const Color(0xFF2563EB);
      case 'Ενεργή':
        return const Color(0xFF059669);
      case 'Ολοκληρωμένη':
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  Color _enrollColor(String status) {
    switch (status) {
      case 'accepted':
        return const Color(0xFF059669);
      case 'rejected':
        return const Color(0xFFDC2626);
      case 'requested':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF6B7280);
    }
  }

  Future<void> _deleteService(int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή Υπηρεσίας'),
        content: Text(
            'Είστε σίγουροι ότι θέλετε να διαγράψετε "$name";\nΔεν μπορεί να αναιρεθεί.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final err = await context.read<ServiceProvider>().deleteService(id);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Η υπηρεσία διαγράφηκε')));
      _load();
    }
  }

  Future<void> _updateEnrollmentStatus(
      int serviceId, int userId, String status) async {
    try {
      final res = await _api.patch(
          '/services/$serviceId/users/$userId/status',
          body: {'status': status});
      if (res.statusCode == 200) {
        _load();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Αποτυχία ενημέρωσης κατάστασης')));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Σφάλμα ενημέρωσης κατάστασης')));
      }
    }
  }

  Future<void> _updateEnrollmentHours(
      int serviceId, int userId, Map<String, dynamic> currentUs) async {
    final hrsCtrl =
        TextEditingController(text: '${currentUs['hours'] ?? 0}');
    final volCtrl =
        TextEditingController(text: '${currentUs['hoursVol'] ?? 0}');
    final trnCtrl =
        TextEditingController(text: '${currentUs['hoursTraining'] ?? 0}');
    final trnrCtrl =
        TextEditingController(text: '${currentUs['hoursTrainers'] ?? 0}');

    final user = currentUs['user'] as Map<String, dynamic>?;
    final uName = user != null
        ? '${user['forename'] ?? ''} ${user['surname'] ?? ''}'.trim()
        : 'Unknown';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ώρες — $uName'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HoursField(controller: hrsCtrl, label: 'Ώρες'),
              const SizedBox(height: 8),
              _HoursField(controller: volCtrl, label: 'Εθελοντικές'),
              const SizedBox(height: 8),
              _HoursField(controller: trnCtrl, label: 'Επανεκπαίδευση'),
              const SizedBox(height: 8),
              _HoursField(controller: trnrCtrl, label: 'Εκπαιδευτές'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Άκυρο')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Αποθήκευση')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final res = await _api.patch(
          '/services/$serviceId/users/$userId/hours',
          body: {
            'hours': int.tryParse(hrsCtrl.text) ?? 0,
            'hoursVol': int.tryParse(volCtrl.text) ?? 0,
            'hoursTraining': int.tryParse(trnCtrl.text) ?? 0,
            'hoursTrainers': int.tryParse(trnrCtrl.text) ?? 0,
          });
      if (res.statusCode == 200) {
        _load();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Αποτυχία ενημέρωσης ωρών')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Σφάλμα ενημέρωσης ωρών')));
      }
    }
  }

  Future<void> _removeEnrollment(int serviceId, int userId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Αφαίρεση Εγγραφής'),
        content: Text('Αφαίρεση "$name" από την υπηρεσία;'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Αφαίρεση'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _api.delete('/services/$serviceId/users/$userId');
      _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Σφάλμα αφαίρεσης εγγραφής')));
      }
    }
  }

  void _openDetail(Map<String, dynamic> svc) =>
      context.push('/admin/services/${svc['id']}');

  void _editService(Map<String, dynamic> svc) async {
    final id = svc['id'] as int;
    await context.push(
        '/admin/services/$id/edit?departmentId=${widget.departmentId}&departmentName=${Uri.encodeComponent(widget.departmentName)}');
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(widget.departmentName,
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () {
              context.push(
                  '/admin/services/past?departmentId=${widget.departmentId}&departmentName=${Uri.encodeComponent(widget.departmentName)}');
            },
            icon: const Icon(Icons.history, size: 18),
            label: const Text('Προηγούμενες'),
          ),
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _load,
              tooltip: 'Ανανέωση'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push(
              '/admin/services/create?departmentId=${widget.departmentId}&departmentName=${Uri.encodeComponent(widget.departmentName)}');
          if (mounted) _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Νέα Υπηρεσία'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(builder: (context, box) {
                final isWide = box.maxWidth >= 800;
                final hPad = isWide ? 32.0 : 16.0;

                return Column(
                  children: [
                    // ── Search bar ──
                    Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: hPad, vertical: 4),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Αναζήτηση υπηρεσιών...',
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
                    const SizedBox(height: 8),

                    // ── Service cards ──
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.inbox,
                                        size: 64,
                                        color: Colors.grey.shade300),
                                    const SizedBox(height: 12),
                                    Text('Δεν βρέθηκαν υπηρεσίες',
                                        style: tt.bodyLarge?.copyWith(
                                            color: Colors.grey.shade500)),
                                  ]))
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: isWide
                                  ? _buildGrid(filtered)
                                  : _buildList(filtered),
                            ),
                    ),
                  ],
                );
              }),
      ),
    );
  }

  Widget _buildList(List<dynamic> services) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
      itemCount: services.length,
      itemBuilder: (ctx, i) => _buildCard(services[i]),
    );
  }

  Widget _buildGrid(List<dynamic> services) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 80),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 1.45,
      ),
      itemCount: services.length,
      itemBuilder: (ctx, i) => _buildCard(services[i]),
    );
  }

  Widget _buildCard(Map<String, dynamic> svc) {
    final tt = Theme.of(context).textTheme;
    final id = svc['id'] as int;
    final name = svc['name'] ?? '';
    final location = svc['location'] ?? '';
    final carrier = svc['carrier'] ?? '';
    final status = _statusLabel(svc);
    final sColor = _statusColor(status);
    final enrolledCount = (svc['_count']?['userServices'] ?? 0) as int;
    final visSpecs = svc['visibility'] as List<dynamic>? ?? [];
    final userServices = svc['userServices'] as List<dynamic>? ?? [];
    final isExpanded = _expandedCards.contains(id);
    final requestedCount =
        userServices.where((us) => us['status'] == 'requested').length;
    final acceptedCount =
        userServices.where((us) => us['status'] == 'accepted').length;
    final responsibleUser = svc['responsibleUser'] as Map<String, dynamic>?;
    final responsibleName = responsibleUser != null
        ? '${responsibleUser['forename'] ?? ''} ${responsibleUser['surname'] ?? ''}'.trim()
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shadowColor: Colors.black.withAlpha(18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade100),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Main card content ──
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            onTap: () => _openDetail(svc),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status accent strip
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [sColor, sColor.withAlpha(120)],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // Top row: name + status badge
                  Row(children: [
                    Expanded(
                      child: Text(name,
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: sColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: sColor.withAlpha(50)),
                      ),
                      child: Text(status,
                          style: TextStyle(
                              color: sColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                  ]),
                  const SizedBox(height: 10),

                  // Info chips
                  Wrap(spacing: 14, runSpacing: 6, children: [
                    if (location.isNotEmpty)
                      _InfoChip(Icons.location_on, location),
                    if (carrier.isNotEmpty) _InfoChip(Icons.groups, carrier),
                    _InfoChip(
                        Icons.calendar_today, _fmtDate(svc['startAt'])),
                    if (responsibleName != null)
                      _InfoChip(Icons.admin_panel_settings, responsibleName),
                  ]),

                  if (visSpecs.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: visSpecs
                          .map((v) => Chip(
                                label: Text(
                                    v['specialization']?['name'] ?? '',
                                    style: const TextStyle(fontSize: 10)),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                labelPadding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                              ))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 10),

                  // Action row
                  Row(children: [
                    // Enrollment summary + expand toggle
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: enrolledCount > 0
                          ? () => setState(() {
                                isExpanded
                                    ? _expandedCards.remove(id)
                                    : _expandedCards.add(id);
                              })
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F4FF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFDBEAFE)),
                        ),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.people,
                                  size: 14,
                                  color: Color(0xFF2563EB)),
                              const SizedBox(width: 5),
                              Text('$enrolledCount μέλη',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF2563EB))),
                              if (requestedCount > 0) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text('$requestedCount',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ],
                              if (enrolledCount > 0) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  isExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 16,
                                  color: const Color(0xFF2563EB),
                                ),
                              ],
                            ]),
                      ),
                    ),
                    const Spacer(),
                    _CardActionButton(
                      icon: Icons.visibility_outlined,
                      label: 'Προβολή',
                      color: const Color(0xFF2563EB),
                      onTap: () => _openDetail(svc),
                    ),
                    const SizedBox(width: 6),
                    _CardActionButton(
                      icon: Icons.edit_outlined,
                      label: 'Επεξ.',
                      color: const Color(0xFF059669),
                      onTap: () => _editService(svc),
                    ),
                    const SizedBox(width: 6),
                    _CardActionButton(
                      icon: Icons.delete_outline,
                      label: 'Διαγρ.',
                      color: Colors.red.shade400,
                      onTap: () => _deleteService(id, name),
                    ),
                  ]),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Enrollment panel (inside card) ──
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: isExpanded && userServices.isNotEmpty
                ? _buildEnrollmentPanel(svc, userServices, tt)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildEnrollmentPanel(
      Map<String, dynamic> svc, List<dynamic> userServices, TextTheme tt) {
    // Sort: requested first, then accepted, then rejected
    final sorted = List<dynamic>.from(userServices);
    const order = {'requested': 0, 'accepted': 1, 'rejected': 2};
    sorted.sort(
        (a, b) => (order[a['status']] ?? 3).compareTo(order[b['status']] ?? 3));

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Icon(Icons.people, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text('Εγγραφές (${userServices.length})',
                style: tt.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF374151))),
            const Spacer(),
            // Quick counts
            _EnrollBadge(
                'Εγκρ.',
                userServices
                    .where((u) => u['status'] == 'accepted')
                    .length,
                const Color(0xFF059669)),
            const SizedBox(width: 6),
            _EnrollBadge(
                'Εκκρ.',
                userServices
                    .where((u) => u['status'] == 'requested')
                    .length,
                const Color(0xFFF59E0B)),
            const SizedBox(width: 6),
            _EnrollBadge(
                'Απορ.',
                userServices
                    .where((u) => u['status'] == 'rejected')
                    .length,
                const Color(0xFFDC2626)),
          ]),
          const SizedBox(height: 8),

          // User rows
          ...sorted.map((us) {
            final user = us['user'] as Map<String, dynamic>?;
            final userId = us['userId'] as int? ?? user?['id'] as int? ?? 0;
            final uName = user != null
                ? '${user['forename'] ?? ''} ${user['surname'] ?? ''}'.trim()
                : 'Unknown';
            final ename = user?['ename'] ?? '';
            final st = (us['status'] ?? 'requested') as String;
            final stColor = _enrollColor(st);
            final serviceId = svc['id'] as int;

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: st == 'requested'
                    ? const Color(0xFFFFFBEB)
                    : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: st == 'requested'
                        ? const Color(0xFFFDE68A)
                        : Colors.grey.shade200,
                    width: st == 'requested' ? 1.5 : 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Top: user info + status ──
                  Row(children: [
                    // Avatar
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: stColor.withAlpha(30),
                      child: Text(
                        uName.isNotEmpty ? uName[0].toUpperCase() : '?',
                        style: TextStyle(
                            color: stColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(uName,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          if (ename.isNotEmpty)
                            Text('@$ename',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: stColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: stColor.withAlpha(60)),
                      ),
                      child: Text(
                        st.substring(0, 1).toUpperCase() + st.substring(1),
                        style: TextStyle(
                            color: stColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  // ── Bottom: action buttons ──
                  Row(children: [
                    if (st != 'accepted')
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.check_circle_outline,
                          label: 'Αποδοχή',
                          color: const Color(0xFF059669),
                          filled: true,
                          onTap: () => _updateEnrollmentStatus(
                              serviceId, userId, 'accepted'),
                        ),
                      ),
                    if (st != 'accepted') const SizedBox(width: 8),
                    if (st != 'rejected')
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.cancel_outlined,
                          label: 'Απόρριψη',
                          color: const Color(0xFFDC2626),
                          filled: false,
                          onTap: () => _updateEnrollmentStatus(
                              serviceId, userId, 'rejected'),
                        ),
                      ),
                    if (st != 'rejected') const SizedBox(width: 8),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.schedule,
                        label: 'Ώρες',
                        color: const Color(0xFF2563EB),
                        filled: false,
                        onTap: () => _updateEnrollmentHours(
                            serviceId, userId, us),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 40,
                      child: _ActionButton(
                        icon: Icons.person_remove_outlined,
                        label: '',
                        color: Colors.grey.shade400,
                        filled: false,
                        compact: true,
                        onTap: () => _removeEnrollment(
                            serviceId, userId, uName),
                      ),
                    ),
                  ]),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Reusable widgets ─────────────────────────────────────



class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: const Color(0xFF6B7280)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text,
              style: const TextStyle(fontSize: 11, color: Color(0xFF4B5563), fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

class _CardActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CardActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

class _EnrollBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _EnrollBadge(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Text('$count $label',
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _HourLabel extends StatelessWidget {
  final String label;
  final dynamic value;

  const _HourLabel(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final v = value is int ? value : 0;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Column(children: [
        Text('$v',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: v > 0 ? const Color(0xFF374151) : Colors.grey.shade400)),
        Text(label,
            style: const TextStyle(fontSize: 9, color: Color(0xFF9CA3AF))),
      ]),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool filled;
  final bool compact;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? color : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 6 : 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: filled ? null : Border.all(color: color.withAlpha(80)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16, color: filled ? Colors.white : color),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: filled ? Colors.white : color)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HoursField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _HoursField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}
