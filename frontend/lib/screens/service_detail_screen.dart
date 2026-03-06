import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/service_provider.dart';
import '../services/api_client.dart';

/// Full-detail view for a single service.
/// Shows service info, enrolled users (with status management),
/// assigned items, vehicle logs, and visibility restrictions.
class ServiceDetailScreen extends StatefulWidget {
  final int serviceId;

  const ServiceDetailScreen({super.key, required this.serviceId});

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiClient();
  Map<String, dynamic>? _service;
  bool _loading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get('/services/${widget.serviceId}');
      if (res.statusCode == 200 && mounted) {
        _service = jsonDecode(res.body);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '—';
    final local = dt.toLocal();
    return '${local.day}/${local.month}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _statusLabel() {
    if (_service == null) return '';
    final now = DateTime.now();
    final start = DateTime.tryParse(_service!['startAt'] ?? '');
    final end = DateTime.tryParse(_service!['endAt'] ?? '');
    if (start == null) return 'No date';
    if (start.isAfter(now)) return 'Upcoming';
    if (end != null && end.isBefore(now)) return 'Completed';
    return 'Active';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Upcoming':
        return const Color(0xFF2563EB);
      case 'Active':
        return const Color(0xFF059669);
      case 'Completed':
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  // ── User enrollment management ──

  Future<void> _updateUserStatus(int userId, String status) async {
    final err = await context
        .read<ServiceProvider>()
        .updateUserStatus(widget.serviceId, userId, status);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    } else {
      _load();
    }
  }

  Future<void> _removeUser(int userId, String userName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove User'),
        content: Text('Remove "$userName" from this service?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final err = await context
        .read<ServiceProvider>()
        .removeUser(widget.serviceId, userId);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User removed')));
      _load();
    }
  }

  Future<void> _editUserHours(Map<String, dynamic> userService) async {
    final user = userService['user'] as Map<String, dynamic>? ?? {};
    final userName =
        '${user['forename'] ?? ''} ${user['surname'] ?? ''}'.trim();

    final hoursCtrl =
        TextEditingController(text: '${userService['hours'] ?? 0}');
    final hoursVolCtrl =
        TextEditingController(text: '${userService['hoursVol'] ?? 0}');
    final hoursTrainingCtrl =
        TextEditingController(text: '${userService['hoursTraining'] ?? 0}');
    final hoursTrainersCtrl =
        TextEditingController(text: '${userService['hoursTrainers'] ?? 0}');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Hours — $userName'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HoursField(controller: hoursCtrl, label: 'Hours'),
              const SizedBox(height: 12),
              _HoursField(controller: hoursVolCtrl, label: 'Voluntary Hours'),
              const SizedBox(height: 12),
              _HoursField(
                  controller: hoursTrainingCtrl, label: 'Training Hours'),
              const SizedBox(height: 12),
              _HoursField(
                  controller: hoursTrainersCtrl, label: 'Trainer Hours'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );

    if (result != true || !mounted) return;

    final userId = user['id'] as int;
    try {
      await _api.patch(
        '/services/${widget.serviceId}/users/$userId/hours',
        body: {
          'hours': int.tryParse(hoursCtrl.text) ?? 0,
          'hoursVol': int.tryParse(hoursVolCtrl.text) ?? 0,
          'hoursTraining': int.tryParse(hoursTrainingCtrl.text) ?? 0,
          'hoursTrainers': int.tryParse(hoursTrainersCtrl.text) ?? 0,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hours updated')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }

    hoursCtrl.dispose();
    hoursVolCtrl.dispose();
    hoursTrainingCtrl.dispose();
    hoursTrainersCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Service Details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_service == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Service Details')),
        body: const Center(child: Text('Service not found')),
      );
    }

    final svc = _service!;
    final status = _statusLabel();
    final sColor = _statusColor(status);
    final userServices = svc['userServices'] as List<dynamic>? ?? [];
    final itemServices = svc['itemServices'] as List<dynamic>? ?? [];
    final vehicleLogs = svc['vehicleLogs'] as List<dynamic>? ?? [];
    final visibility = svc['visibility'] as List<dynamic>? ?? [];
    final dept = svc['department'] as Map<String, dynamic>? ?? {};

    final requested =
        userServices.where((u) => u['status'] == 'requested').toList();
    final accepted =
        userServices.where((u) => u['status'] == 'accepted').toList();
    final rejected =
        userServices.where((u) => u['status'] == 'rejected').toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;

            return NestedScrollView(
              headerSliverBuilder: (context, innerBoxScrolled) => [
                SliverAppBar(
                  expandedHeight: isWide ? 180 : 200,
                  pinned: true,
                  backgroundColor: cs.primary,
                  foregroundColor: Colors.white,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        final deptId = dept['id'];
                        final deptName = dept['name'] ?? '';
                        await context.push(
                            '/admin/services/${svc['id']}/edit?departmentId=$deptId&departmentName=${Uri.encodeComponent(deptName)}');
                        if (mounted) _load();
                      },
                      tooltip: 'Edit service',
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _load,
                      tooltip: 'Refresh',
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [cs.primary, cs.primary.withAlpha(180)],
                        ),
                      ),
                      child: SafeArea(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                              isWide ? 80 : 20, 60, isWide ? 80 : 20, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      svc['name'] ?? '',
                                      style: tt.headlineSmall?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withAlpha(40),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(status,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                dept['name'] ?? '',
                                style: TextStyle(
                                    color: Colors.white.withAlpha(200),
                                    fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    collapseMode: CollapseMode.parallax,
                  ),
                ),
              ],
              body: isWide
                  ? _buildWideLayout(svc, requested, accepted, rejected,
                      itemServices, vehicleLogs, visibility)
                  : _buildCompactLayout(svc, requested, accepted, rejected,
                      itemServices, vehicleLogs, visibility),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWideLayout(
    Map<String, dynamic> svc,
    List<dynamic> requested,
    List<dynamic> accepted,
    List<dynamic> rejected,
    List<dynamic> itemServices,
    List<dynamic> vehicleLogs,
    List<dynamic> visibility,
  ) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left column: Service info
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ServiceInfoCard(svc: svc, formatDate: _formatDate),
                  const SizedBox(height: 16),
                  if (visibility.isNotEmpty)
                    _VisibilityCard(visibility: visibility),
                  if (visibility.isNotEmpty) const SizedBox(height: 16),
                  _HoursDefaultCard(svc: svc),
                  const SizedBox(height: 16),
                  _AssignedItemsCard(itemServices: itemServices),
                  const SizedBox(height: 16),
                  _VehicleLogsCard(
                      vehicleLogs: vehicleLogs, formatDate: _formatDate),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          // Right column: People
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              child: _PeopleSection(
                requested: requested,
                accepted: accepted,
                rejected: rejected,
                onAccept: (uid) => _updateUserStatus(uid, 'accepted'),
                onReject: (uid) => _updateUserStatus(uid, 'rejected'),
                onRemove: _removeUser,
                onEditHours: _editUserHours,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactLayout(
    Map<String, dynamic> svc,
    List<dynamic> requested,
    List<dynamic> accepted,
    List<dynamic> rejected,
    List<dynamic> itemServices,
    List<dynamic> vehicleLogs,
    List<dynamic> visibility,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _ServiceInfoCard(svc: svc, formatDate: _formatDate),
        const SizedBox(height: 16),
        if (visibility.isNotEmpty) _VisibilityCard(visibility: visibility),
        if (visibility.isNotEmpty) const SizedBox(height: 16),
        _HoursDefaultCard(svc: svc),
        const SizedBox(height: 20),
        _PeopleSection(
          requested: requested,
          accepted: accepted,
          rejected: rejected,
          onAccept: (uid) => _updateUserStatus(uid, 'accepted'),
          onReject: (uid) => _updateUserStatus(uid, 'rejected'),
          onRemove: _removeUser,
          onEditHours: _editUserHours,
        ),
        const SizedBox(height: 16),
        _AssignedItemsCard(itemServices: itemServices),
        const SizedBox(height: 16),
        _VehicleLogsCard(vehicleLogs: vehicleLogs, formatDate: _formatDate),
      ],
    );
  }
}

// ─── Service Info Card ────────────────────────────────────

class _ServiceInfoCard extends StatelessWidget {
  final Map<String, dynamic> svc;
  final String Function(String?) formatDate;

  const _ServiceInfoCard({required this.svc, required this.formatDate});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final desc = svc['description'] ?? '';
    final location = svc['location'] ?? '';
    final carrier = svc['carrier'] ?? '';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Service Information',
                style:
                    tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const Divider(height: 20),
            if (desc.isNotEmpty) ...[
              Text(desc, style: tt.bodyMedium),
              const SizedBox(height: 16),
            ],
            _DetailRow(
                icon: Icons.calendar_today,
                label: 'Start',
                value: formatDate(svc['startAt'])),
            const SizedBox(height: 10),
            _DetailRow(
                icon: Icons.calendar_today,
                label: 'End',
                value: formatDate(svc['endAt'])),
            if (location.isNotEmpty) ...[
              const SizedBox(height: 10),
              _DetailRow(
                  icon: Icons.location_on,
                  label: 'Location',
                  value: location),
            ],
            if (carrier.isNotEmpty) ...[
              const SizedBox(height: 10),
              _DetailRow(
                  icon: Icons.groups, label: 'Carrier', value: carrier),
            ],
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.access_time,
              label: 'Created',
              value: formatDate(svc['createdAt']),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF6B7280)),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: Text(label,
              style: tt.bodySmall
                  ?.copyWith(color: const Color(0xFF6B7280))),
        ),
        Expanded(
          child: Text(value,
              style:
                  tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

// ─── Hours defaults card ──────────────────────────────────

class _HoursDefaultCard extends StatelessWidget {
  final Map<String, dynamic> svc;
  const _HoursDefaultCard({required this.svc});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Default Hours',
                style:
                    tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const Divider(height: 20),
            Row(
              children: [
                _HoursBadge(
                    label: 'Hours', value: svc['defaultHours'] ?? 0),
                const SizedBox(width: 8),
                _HoursBadge(
                    label: 'Voluntary', value: svc['defaultHoursVol'] ?? 0),
                const SizedBox(width: 8),
                _HoursBadge(
                    label: 'Training',
                    value: svc['defaultHoursTraining'] ?? 0),
                const SizedBox(width: 8),
                _HoursBadge(
                    label: 'Trainers',
                    value: svc['defaultHoursTrainers'] ?? 0),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HoursBadge extends StatelessWidget {
  final String label;
  final int value;
  const _HoursBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text('$value',
                style: tt.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label,
                style: tt.bodySmall
                    ?.copyWith(color: const Color(0xFF6B7280), fontSize: 10),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ─── Visibility Card ──────────────────────────────────────

class _VisibilityCard extends StatelessWidget {
  final List<dynamic> visibility;
  const _VisibilityCard({required this.visibility});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.visibility, size: 18, color: Color(0xFF7C3AED)),
                const SizedBox(width: 8),
                Text('Required Specializations',
                    style: tt.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: visibility.map((v) {
                final spec = v['specialization'] as Map<String, dynamic>?;
                return Chip(
                  avatar: const Icon(Icons.school, size: 14),
                  label: Text(spec?['name'] ?? ''),
                  backgroundColor: const Color(0xFFEDE9FE),
                  labelStyle: const TextStyle(fontSize: 12),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── People Section ───────────────────────────────────────

class _PeopleSection extends StatelessWidget {
  final List<dynamic> requested;
  final List<dynamic> accepted;
  final List<dynamic> rejected;
  final void Function(int userId) onAccept;
  final void Function(int userId) onReject;
  final void Function(int userId, String userName) onRemove;
  final void Function(Map<String, dynamic> userService) onEditHours;

  const _PeopleSection({
    required this.requested,
    required this.accepted,
    required this.rejected,
    required this.onAccept,
    required this.onReject,
    required this.onRemove,
    required this.onEditHours,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final totalPeople = requested.length + accepted.length + rejected.length;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.people, size: 20, color: Color(0xFF2563EB)),
                const SizedBox(width: 8),
                Text('Enrolled People',
                    style: tt.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withAlpha(15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('$totalPeople total',
                      style: const TextStyle(
                          color: Color(0xFF2563EB),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const Divider(height: 20),

            // ── Pending requests (highlighted) ──
            if (requested.isNotEmpty) ...[
              _PeopleGroupHeader(
                label: 'Pending Requests',
                count: requested.length,
                color: const Color(0xFFD97706),
                icon: Icons.hourglass_top,
              ),
              const SizedBox(height: 8),
              ...requested.map((us) => _PendingUserTile(
                    userService: us,
                    onAccept: () {
                      final user = us['user'] as Map<String, dynamic>? ?? {};
                      onAccept(user['id'] as int);
                    },
                    onReject: () {
                      final user = us['user'] as Map<String, dynamic>? ?? {};
                      onReject(user['id'] as int);
                    },
                  )),
              const SizedBox(height: 16),
            ],

            // ── Accepted ──
            if (accepted.isNotEmpty) ...[
              _PeopleGroupHeader(
                label: 'Accepted',
                count: accepted.length,
                color: const Color(0xFF059669),
                icon: Icons.check_circle,
              ),
              const SizedBox(height: 8),
              ...accepted.map((us) => _AcceptedUserTile(
                    userService: us,
                    onRemove: () {
                      final user = us['user'] as Map<String, dynamic>? ?? {};
                      final name =
                          '${user['forename'] ?? ''} ${user['surname'] ?? ''}'
                              .trim();
                      onRemove(user['id'] as int, name);
                    },
                    onEditHours: () => onEditHours(us),
                  )),
              const SizedBox(height: 16),
            ],

            // ── Rejected ──
            if (rejected.isNotEmpty) ...[
              _PeopleGroupHeader(
                label: 'Rejected',
                count: rejected.length,
                color: Colors.red,
                icon: Icons.cancel,
              ),
              const SizedBox(height: 8),
              ...rejected.map((us) => _RejectedUserTile(
                    userService: us,
                    onAccept: () {
                      final user = us['user'] as Map<String, dynamic>? ?? {};
                      onAccept(user['id'] as int);
                    },
                    onRemove: () {
                      final user = us['user'] as Map<String, dynamic>? ?? {};
                      final name =
                          '${user['forename'] ?? ''} ${user['surname'] ?? ''}'
                              .trim();
                      onRemove(user['id'] as int, name);
                    },
                  )),
            ],

            if (totalPeople == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.people_outline,
                          size: 48, color: Colors.grey.shade300),
                      const SizedBox(height: 8),
                      Text('No enrollments yet',
                          style: tt.bodyMedium
                              ?.copyWith(color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PeopleGroupHeader extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _PeopleGroupHeader({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: tt.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600, color: color)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$count',
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// ── User tiles ──

class _PendingUserTile extends StatelessWidget {
  final Map<String, dynamic> userService;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _PendingUserTile({
    required this.userService,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final user = userService['user'] as Map<String, dynamic>? ?? {};
    final name =
        '${user['forename'] ?? ''} ${user['surname'] ?? ''}'.trim();
    final ename = user['ename'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFFD97706),
          child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
        ),
        title: Text(name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(ename,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onAccept,
              icon: const Icon(Icons.check_circle, color: Color(0xFF059669)),
              iconSize: 22,
              tooltip: 'Accept',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: onReject,
              icon: const Icon(Icons.cancel, color: Colors.red),
              iconSize: 22,
              tooltip: 'Reject',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _AcceptedUserTile extends StatelessWidget {
  final Map<String, dynamic> userService;
  final VoidCallback onRemove;
  final VoidCallback onEditHours;

  const _AcceptedUserTile({
    required this.userService,
    required this.onRemove,
    required this.onEditHours,
  });

  @override
  Widget build(BuildContext context) {
    final user = userService['user'] as Map<String, dynamic>? ?? {};
    final name =
        '${user['forename'] ?? ''} ${user['surname'] ?? ''}'.trim();
    final ename = user['ename'] ?? '';
    final hours = userService['hours'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFF059669),
          child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
        ),
        title: Text(name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text('$ename · ${hours}h',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onEditHours,
              icon: const Icon(Icons.timer, color: Color(0xFF2563EB)),
              iconSize: 20,
              tooltip: 'Edit hours',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: onRemove,
              icon: Icon(Icons.person_remove,
                  color: Colors.red.shade400, size: 20),
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _RejectedUserTile extends StatelessWidget {
  final Map<String, dynamic> userService;
  final VoidCallback onAccept;
  final VoidCallback onRemove;

  const _RejectedUserTile({
    required this.userService,
    required this.onAccept,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final user = userService['user'] as Map<String, dynamic>? ?? {};
    final name =
        '${user['forename'] ?? ''} ${user['surname'] ?? ''}'.trim();
    final ename = user['ename'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: Colors.red.shade400,
          child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
        ),
        title: Text(name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(ename,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onAccept,
              icon: const Icon(Icons.check_circle,
                  color: Color(0xFF059669), size: 20),
              tooltip: 'Accept instead',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: onRemove,
              icon: Icon(Icons.delete, color: Colors.red.shade400, size: 20),
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Assigned Items Card ──────────────────────────────────

class _AssignedItemsCard extends StatelessWidget {
  final List<dynamic> itemServices;
  const _AssignedItemsCard({required this.itemServices});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2,
                    size: 18, color: Color(0xFF7C3AED)),
                const SizedBox(width: 8),
                Text('Assigned Items',
                    style: tt.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${itemServices.length}',
                    style: tt.bodySmall?.copyWith(
                        color: const Color(0xFF6B7280))),
              ],
            ),
            if (itemServices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('No items assigned',
                      style: tt.bodySmall
                          ?.copyWith(color: Colors.grey.shade400)),
                ),
              )
            else ...[
              const Divider(height: 20),
              ...itemServices.map((is_) {
                final item = is_['item'] as Map<String, dynamic>? ?? {};
                final user = is_['user'] as Map<String, dynamic>? ?? {};
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.inventory,
                      size: 20, color: Colors.grey.shade600),
                  title: Text(item['name'] ?? '',
                      style: const TextStyle(fontSize: 14)),
                  subtitle: Text(
                    'Assigned by ${user['forename'] ?? ''} ${user['surname'] ?? ''}'
                        .trim(),
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6B7280)),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Vehicle Logs Card ────────────────────────────────────

class _VehicleLogsCard extends StatelessWidget {
  final List<dynamic> vehicleLogs;
  final String Function(String?) formatDate;

  const _VehicleLogsCard(
      {required this.vehicleLogs, required this.formatDate});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_car,
                    size: 18, color: Color(0xFFD97706)),
                const SizedBox(width: 8),
                Text('Vehicle Logs',
                    style: tt.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${vehicleLogs.length}',
                    style: tt.bodySmall?.copyWith(
                        color: const Color(0xFF6B7280))),
              ],
            ),
            if (vehicleLogs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('No vehicle logs',
                      style: tt.bodySmall
                          ?.copyWith(color: Colors.grey.shade400)),
                ),
              )
            else ...[
              const Divider(height: 20),
              ...vehicleLogs.map((log) {
                final vehicle =
                    log['vehicle'] as Map<String, dynamic>? ?? {};
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.directions_car,
                      size: 20, color: Colors.grey.shade600),
                  title: Text(vehicle['name'] ?? '',
                      style: const TextStyle(fontSize: 14)),
                  subtitle: Text(
                    '${formatDate(log['startAt'])} → ${formatDate(log['endAt'])}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6B7280)),
                  ),
                  trailing: Text(
                    '${log['meterStart']}→${log['meterEnd']}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6B7280)),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Helpers ──

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
      ),
    );
  }
}
