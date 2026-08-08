import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/service_provider.dart';
import '../providers/victim_provider.dart';
import '../services/api_client.dart';

import 'package:mitroo_frontend/theme/theme.dart';

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
    final lcs = _service!['lifecycleStatus'] as String?;
    if (lcs == 'finalized') return 'Οριστικοποιημένη';
    if (lcs == 'completed') return 'Ολοκληρωμένη';
    if (lcs == 'closed') return 'Κλειστή';
    if (lcs == 'active') return 'Ενεργή';
    // Fallback: date-based heuristic
    final now = DateTime.now();
    final start = DateTime.tryParse(_service!['startAt'] ?? '');
    final end = DateTime.tryParse(_service!['endAt'] ?? '');
    if (start == null) return 'Χωρίς ημ/νία';
    if (start.isAfter(now)) return 'Προσεχής';
    if (end != null && end.isBefore(now)) return 'Ολοκληρωμένη';
    return 'Ενεργή';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Προσεχής':
        return AppColors.red600;
      case 'Ενεργή':
        return AppColors.emerald600;
      case 'Κλειστή':
        return AppColors.amber600;
      case 'Ολοκληρωμένη':
        return AppColors.gray500;
      case 'Οριστικοποιημένη':
        return AppColors.gray600;
      default:
        return AppColors.gray400;
    }
  }

  // ── User enrollment management ──

  Future<void> _updateUserStatus(int userId, String status) async {
    final err = await context
        .read<ServiceProvider>()
        .updateUserStatus(widget.serviceId, userId, status);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      _load();
    }
  }

  Future<void> _removeUser(int userId, String userName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Αφαίρεση Μέλους'),
        content: Text('Αφαίρεση "$userName" από αυτή την υπηρεσία;'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red600),
            child: const Text('Αφαίρεση'),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Το μέλος αφαιρέθηκε')));
      _load();
    }
  }

  Future<void> _updateParticipation(int userId, String status) async {
    final err = await context
        .read<ServiceProvider>()
        .updateParticipation(widget.serviceId, userId, status);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      _load();
    }
  }

  Future<void> _returnItem(int itemId, String itemName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Επιστροφή Εξοπλισμού'),
        content: Text('Επιστροφή "$itemName";'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red600),
            child: const Text('Επιστροφή'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Use self-unassign for own items, admin endpoint for others
    final auth = context.read<AuthProvider>();
    final isAdmin = auth.isAdmin || auth.isMissionAdmin;
    final res = isAdmin
        ? await _api.delete('/items/$itemId/assign-user')
        : await _api.post('/items/$itemId/self-unassign');
    if (!mounted) return;
    if (res.statusCode == 200) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('"$itemName" επεστράφη')));
      _load();
    } else {
      final body = jsonDecode(res.body);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(body['error'] ?? 'Σφάλμα')));
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
    final hoursTEPCtrl =
        TextEditingController(text: '${userService['hoursTEP'] ?? 0}');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ώρες — $userName'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HoursField(controller: hoursCtrl, label: 'Ώρες Κάλυψης'),
              const SizedBox(height: 12),
              _HoursField(controller: hoursVolCtrl, label: 'Εθελοντικές Ώρες'),
              const SizedBox(height: 12),
              _HoursField(
                  controller: hoursTrainingCtrl, label: 'Ώρες Επανεκπαίδευσης'),
              const SizedBox(height: 12),
              _HoursField(
                  controller: hoursTrainersCtrl, label: 'Ώρες Εκπαιδευτών'),
              const SizedBox(height: 12),
              _HoursField(controller: hoursTEPCtrl, label: 'Ώρες ΤΕΠ'),
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
          'hoursTEP': int.tryParse(hoursTEPCtrl.text) ?? 0,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Οι ώρες ενημερώθηκαν')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Σφάλμα: $e')));
      }
    }

    hoursCtrl.dispose();
    hoursVolCtrl.dispose();
    hoursTrainingCtrl.dispose();
    hoursTrainersCtrl.dispose();
    hoursTEPCtrl.dispose();
  }

  // ── Self enroll / unenroll ──

  Future<void> _enrollSelf() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.user?['id'] as int?;
    if (userId == null) return;

    final err = await context
        .read<ServiceProvider>()
        .enrollSelf(widget.serviceId, userId);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Η αίτηση υποβλήθηκε')));
      _load();
    }
  }

  Future<void> _unenrollSelf() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ακύρωση Αίτησης'),
        content: const Text('Θέλετε να αποσύρετε την αίτησή σας;'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Όχι')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red600),
            child: const Text('Απόσυρση'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final err =
        await context.read<ServiceProvider>().unenrollSelf(widget.serviceId);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Η αίτηση αποσύρθηκε')));
      _load();
    }
  }

  // ── Responsible user management ──

  Future<void> _pickResponsibleUser() async {
    // Build list from users already enrolled in this service
    final userServices = _service?['userServices'] as List<dynamic>? ?? [];
    final users = userServices
        .map((us) => us['user'] as Map<String, dynamic>?)
        .where((u) => u != null)
        .cast<Map<String, dynamic>>()
        .toList();

    if (!mounted || users.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Δεν υπάρχουν εγγεγραμμένα μέλη')),
        );
      }
      return;
    }

    final currentResponsible = _service?['responsibleUser'];
    final currentId = currentResponsible?['id'];
    String search = '';

    final selected = await showDialog<int?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          final filtered = users.where((u) {
            if (search.isEmpty) return true;
            final q = search.toLowerCase();
            final name =
                '${u['forename'] ?? ''} ${u['surname'] ?? ''}'.toLowerCase();
            final eame = (u['eame'] ?? '').toString().toLowerCase();
            return name.contains(q) || eame.contains(q);
          }).toList();

          return AlertDialog(
            title: const Text('Επιλογή Υπεύθυνου'),
            content: SizedBox(
              width: 400,
              height: 450,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Αναζήτηση μελών...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: AppRadius.r10),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    onChanged: (v) => setDialogState(() => search = v),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final u = filtered[i];
                        final uid = u['id'] as int;
                        final name =
                            '${u['forename'] ?? ''} ${u['surname'] ?? ''}'
                                .trim();
                        final eame = u['eame'] ?? '';
                        final isSelected = uid == currentId;

                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          selectedTileColor: AppColors.violet100,
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: isSelected
                                ? AppColors.violet600
                                : AppColors.gray500,
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: AppFontWeight.semibold,
                                  fontSize: AppFontSize.lg),
                            ),
                          ),
                          title: Text(name,
                              style: const TextStyle(
                                  fontWeight: AppFontWeight.semibold,
                                  fontSize: AppFontSize.lg)),
                          subtitle: Text('@$eame',
                              style: const TextStyle(
                                  fontSize: AppFontSize.base,
                                  color: AppColors.gray500)),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle,
                                  color: AppColors.violet600, size: 20)
                              : null,
                          onTap: () => Navigator.pop(ctx, uid),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (currentId != null)
                TextButton(
                  onPressed: () =>
                      Navigator.pop(ctx, -1), // sentinel for "clear"
                  child: const Text('Καθαρισμός',
                      style: TextStyle(color: AppColors.red600)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Άκυρο'),
              ),
            ],
          );
        });
      },
    );

    if (selected == null || !mounted) return;

    final userId = selected == -1 ? null : selected;
    final err = await context
        .read<ServiceProvider>()
        .setResponsibleUser(widget.serviceId, userId);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            userId == null ? 'Ο υπεύθυνος αφαιρέθηκε' : 'Ορίστηκε υπεύθυνος'),
      ));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Λεπτομέρειες Υπηρεσίας')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_service == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Λεπτομέρειες Υπηρεσίας')),
        body: const Center(child: Text('Η υπηρεσία δεν βρέθηκε')),
      );
    }

    final svc = _service!;
    final status = _statusLabel();
    final sColor = _statusColor(status);
    final userServices = svc['userServices'] as List<dynamic>? ?? [];
    final vehicleLogs = svc['vehicleLogs'] as List<dynamic>? ?? [];
    final visibility = svc['visibility'] as List<dynamic>? ?? [];
    final dept = svc['department'] as Map<String, dynamic>? ?? {};
    final responsibleUser = svc['responsibleUser'] as Map<String, dynamic>?;
    final lifecycleStatus = svc['lifecycleStatus'] as String? ?? 'active';
    final auth = context.read<AuthProvider>();
    final canManage = auth.isAdmin || auth.isMissionAdmin;
    final currentUserId = auth.user?['id'] as int?;

    // Check if current user is an accepted member of this service (incl. participated/not-participated)
    final isAcceptedMember = userServices.any((us) =>
        us['user']?['id'] == currentUserId &&
        (us['status'] == 'accepted' ||
            us['status'] == 'participated' ||
            us['status'] == 'not-participated'));
    final isMember =
        userServices.any((us) => us['user']?['id'] == currentUserId);

    final requested =
        userServices.where((u) => u['status'] == 'requested').toList();
    final accepted =
        userServices.where((u) => u['status'] == 'accepted').toList();
    final rejected =
        userServices.where((u) => u['status'] == 'rejected').toList();
    final participated =
        userServices.where((u) => u['status'] == 'participated').toList();
    final notParticipated =
        userServices.where((u) => u['status'] == 'not-participated').toList();
    // Accepted + participation statuses shown together
    final allAccepted = [...accepted, ...participated, ...notParticipated];

    // Format short date for header
    String _shortDate(String? iso) {
      if (iso == null) return '—';
      final dt = DateTime.tryParse(iso);
      if (dt == null) return '—';
      final local = dt.toLocal();
      return '${local.day}/${local.month}/${local.year}';
    }

    // Determine enrollment state for FAB
    final isPending = userServices.any((us) =>
        us['user']?['id'] == currentUserId && us['status'] == 'requested');

    return Scaffold(
      floatingActionButton: !canManage &&
              !isAcceptedMember &&
              lifecycleStatus != 'finalized'
          ? FloatingActionButton.extended(
              heroTag: 'service_detail_fab',
              onPressed: isPending ? _unenrollSelf : _enrollSelf,
              backgroundColor: isPending ? AppColors.orange600 : sColor,
              foregroundColor: Colors.white,
              icon: Icon(isPending ? Icons.cancel_outlined : Icons.how_to_reg),
              label: Text(isPending ? 'Ακύρωση Αίτησης' : 'Εγγραφή'),
            )
          : null,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;

            return NestedScrollView(
              headerSliverBuilder: (context, innerBoxScrolled) => [
                SliverAppBar(
                  expandedHeight: isWide ? 168 : 188,
                  pinned: true,
                  backgroundColor: sColor,
                  foregroundColor: Colors.white,
                  iconTheme: const IconThemeData(color: Colors.white, size: 24),
                  actionsIconTheme:
                      const IconThemeData(color: Colors.white, size: 24),
                  actions: [
                    if (canManage)
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () async {
                          final deptId = dept['id'];
                          final deptName = dept['name'] ?? '';
                          await context.push(
                              '/admin/services/${svc['id']}/edit?departmentId=$deptId&departmentName=${Uri.encodeComponent(deptName)}');
                          if (mounted) _load();
                        },
                        tooltip: 'Επεξεργασία',
                      ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _load,
                      tooltip: 'Ανανέωση',
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [sColor, sColor.withAlpha(180)],
                        ),
                      ),
                      child: SafeArea(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                              isWide ? 80 : 20, 44, isWide ? 80 : 20, 12),
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
                                          fontWeight: AppFontWeight.bold),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withAlpha(50),
                                      borderRadius: AppRadius.r20,
                                      border: Border.all(
                                          color: Colors.white.withAlpha(80),
                                          width: 1),
                                    ),
                                    child: Text(status,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: AppFontWeight.bold,
                                            fontSize: AppFontSize.base,
                                            letterSpacing: 0.5)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                dept['name'] ?? '',
                                style: TextStyle(
                                    color: Colors.white.withAlpha(220),
                                    fontSize: AppFontSize.lg,
                                    fontWeight: AppFontWeight.medium),
                              ),
                              const SizedBox(height: 6),
                              // Quick-info chips in header
                              Wrap(
                                spacing: 10,
                                runSpacing: 6,
                                children: [
                                  _HeaderChip(
                                    icon: Icons.calendar_today,
                                    text:
                                        '${_shortDate(svc['startAt'])} — ${_shortDate(svc['endAt'])}',
                                  ),
                                  _HeaderChip(
                                    icon: Icons.people,
                                    text: '${allAccepted.length} μέλη',
                                  ),
                                  if (requested.isNotEmpty && canManage)
                                    _HeaderChip(
                                      icon: Icons.hourglass_top,
                                      text: '${requested.length} αιτήσεις',
                                    ),
                                ],
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
                  ? _buildWideLayout(
                      svc,
                      requested,
                      accepted,
                      rejected,
                      participated,
                      notParticipated,
                      allAccepted,
                      vehicleLogs,
                      visibility,
                      responsibleUser,
                      canManage,
                      isAcceptedMember,
                      isMember,
                      lifecycleStatus,
                      userServices)
                  : _buildCompactLayout(
                      svc,
                      requested,
                      accepted,
                      rejected,
                      participated,
                      notParticipated,
                      allAccepted,
                      vehicleLogs,
                      visibility,
                      responsibleUser,
                      canManage,
                      isAcceptedMember,
                      isMember,
                      lifecycleStatus,
                      userServices),
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
    List<dynamic> participated,
    List<dynamic> notParticipated,
    List<dynamic> allAccepted,
    List<dynamic> vehicleLogs,
    List<dynamic> visibility,
    Map<String, dynamic>? responsibleUser,
    bool canManage,
    bool isAcceptedMember,
    bool isMember,
    String lifecycleStatus,
    List<dynamic> userServices,
  ) {
    final canManageParticipation = canManage &&
        (lifecycleStatus == 'closed' || lifecycleStatus == 'completed');
    final isFinalized = lifecycleStatus == 'finalized';
    final showEnrollmentActions = canManage && !isFinalized;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left column: Service info
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ServiceInfoCard(svc: svc, formatDate: _formatDate),
                  const SizedBox(height: 16),
                  _ResponsibleUserCard(
                    responsibleUser: responsibleUser,
                    canManage: canManage && !isFinalized,
                    onPick: _pickResponsibleUser,
                  ),
                  const SizedBox(height: 16),
                  if (visibility.isNotEmpty)
                    _VisibilityCard(visibility: visibility),
                  if (visibility.isNotEmpty) const SizedBox(height: 16),
                  _HoursDefaultCard(svc: svc),
                  const SizedBox(height: 16),
                  _VehicleLogsCard(
                      vehicleLogs: vehicleLogs, formatDate: _formatDate),
                  const SizedBox(height: 16),
                  _VictimsSection(
                    serviceId: svc['id'] as int,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            // Right column: Equipment + People
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MemberEquipmentCard(
                    userServices: userServices,
                    visible: isMember || canManage,
                    currentUserId:
                        context.read<AuthProvider>().user?['id'] as int?,
                    canManage: canManage,
                    onReturnItem: _returnItem,
                    onTakeItems: () => context.push('/items'),
                  ),
                  const SizedBox(height: 16),
                  _PeopleSection(
                    requested: requested,
                    accepted: allAccepted,
                    rejected: rejected,
                    responsibleUserId: responsibleUser?['id'] as int?,
                    canManage: showEnrollmentActions,
                    canManageParticipation: canManageParticipation,
                    lifecycleStatus: lifecycleStatus,
                    onAccept: showEnrollmentActions
                        ? (uid) => _updateUserStatus(uid, 'accepted')
                        : null,
                    onReject: showEnrollmentActions
                        ? (uid) => _updateUserStatus(uid, 'rejected')
                        : null,
                    onRemove: showEnrollmentActions ? _removeUser : null,
                    onEditHours: canManage ? _editUserHours : null,
                    onUpdateParticipation:
                        canManageParticipation ? _updateParticipation : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompactLayout(
    Map<String, dynamic> svc,
    List<dynamic> requested,
    List<dynamic> accepted,
    List<dynamic> rejected,
    List<dynamic> participated,
    List<dynamic> notParticipated,
    List<dynamic> allAccepted,
    List<dynamic> vehicleLogs,
    List<dynamic> visibility,
    Map<String, dynamic>? responsibleUser,
    bool canManage,
    bool isAcceptedMember,
    bool isMember,
    String lifecycleStatus,
    List<dynamic> userServices,
  ) {
    final canManageParticipation = canManage &&
        (lifecycleStatus == 'closed' || lifecycleStatus == 'completed');
    final isFinalized = lifecycleStatus == 'finalized';
    final showEnrollmentActions = canManage && !isFinalized;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _ServiceInfoCard(svc: svc, formatDate: _formatDate),
        const SizedBox(height: 16),
        _ResponsibleUserCard(
          responsibleUser: responsibleUser,
          canManage: canManage && !isFinalized,
          onPick: _pickResponsibleUser,
        ),
        const SizedBox(height: 16),
        if (visibility.isNotEmpty) _VisibilityCard(visibility: visibility),
        if (visibility.isNotEmpty) const SizedBox(height: 16),
        _HoursDefaultCard(svc: svc),
        const SizedBox(height: 20),
        _MemberEquipmentCard(
          userServices: userServices,
          visible: isMember || canManage,
          currentUserId: context.read<AuthProvider>().user?['id'] as int?,
          canManage: canManage,
          onReturnItem: _returnItem,
          onTakeItems: () => context.push('/items'),
        ),
        const SizedBox(height: 16),
        _PeopleSection(
          requested: requested,
          accepted: allAccepted,
          rejected: rejected,
          responsibleUserId: responsibleUser?['id'] as int?,
          canManage: showEnrollmentActions,
          canManageParticipation: canManageParticipation,
          lifecycleStatus: lifecycleStatus,
          onAccept: showEnrollmentActions
              ? (uid) => _updateUserStatus(uid, 'accepted')
              : null,
          onReject: showEnrollmentActions
              ? (uid) => _updateUserStatus(uid, 'rejected')
              : null,
          onRemove: showEnrollmentActions ? _removeUser : null,
          onEditHours: canManage ? _editUserHours : null,
          onUpdateParticipation:
              canManageParticipation ? _updateParticipation : null,
        ),
        const SizedBox(height: 16),
        _VehicleLogsCard(vehicleLogs: vehicleLogs, formatDate: _formatDate),
        const SizedBox(height: 16),
        _VictimsSection(
          serviceId: svc['id'] as int,
        ),
      ],
    );
  }
}

// ─── Responsible User Card ────────────────────────────────

class _ResponsibleUserCard extends StatelessWidget {
  final Map<String, dynamic>? responsibleUser;
  final bool canManage;
  final VoidCallback onPick;

  const _ResponsibleUserCard({
    required this.responsibleUser,
    required this.canManage,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final hasUser = responsibleUser != null;
    final name = hasUser
        ? '${responsibleUser!['forename'] ?? ''} ${responsibleUser!['surname'] ?? ''}'
            .trim()
        : '';
    final eame = hasUser ? (responsibleUser!['eame'] ?? '') : '';

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withAlpha(20),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.r16,
        side: BorderSide(color: AppColors.gray100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.admin_panel_settings,
                    size: 20, color: AppColors.violet600),
                const SizedBox(width: 8),
                Text('Υπεύθυνος',
                    style: tt.titleMedium
                        ?.copyWith(fontWeight: AppFontWeight.semibold)),
                const Spacer(),
                if (canManage)
                  FilledButton.tonalIcon(
                    onPressed: onPick,
                    icon: Icon(
                      hasUser ? Icons.swap_horiz : Icons.person_add,
                      size: 16,
                    ),
                    label: Text(
                      hasUser ? 'Αλλαγή' : 'Ορισμός',
                      style: const TextStyle(fontSize: AppFontSize.base),
                    ),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (hasUser)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.violet50,
                  borderRadius: AppRadius.r10,
                  border: Border.all(color: AppColors.violet200),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.violet600,
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: AppFontWeight.semibold,
                            fontSize: AppFontSize.xl2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontWeight: AppFontWeight.semibold,
                                  fontSize: AppFontSize.xl)),
                          Text('@$eame',
                              style: const TextStyle(
                                  fontSize: AppFontSize.base,
                                  color: AppColors.gray500)),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                width: double.infinity,
                child: Column(
                  children: [
                    Icon(Icons.person_off, size: 32, color: AppColors.gray300),
                    const SizedBox(height: 6),
                    Text('Δεν έχει οριστεί υπεύθυνος',
                        style:
                            tt.bodySmall?.copyWith(color: AppColors.gray500)),
                  ],
                ),
              ),
          ],
        ),
      ),
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
      elevation: 2,
      shadowColor: Colors.black.withAlpha(20),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.r16,
        side: BorderSide(color: AppColors.gray100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Πληροφορίες Υπηρεσίας',
                style: tt.titleMedium
                    ?.copyWith(fontWeight: AppFontWeight.semibold)),
            const Divider(height: 20),
            if (desc.isNotEmpty) ...[
              Text(desc, style: tt.bodyMedium),
              const SizedBox(height: 16),
            ],
            _DetailRow(
                icon: Icons.calendar_today,
                label: 'Έναρξη',
                value: formatDate(svc['startAt'])),
            const SizedBox(height: 10),
            _DetailRow(
                icon: Icons.calendar_today,
                label: 'Λήξη',
                value: formatDate(svc['endAt'])),
            if (location.isNotEmpty) ...[
              const SizedBox(height: 10),
              _DetailRow(
                  icon: Icons.location_on, label: 'Τοποθεσία', value: location),
            ],
            if (carrier.isNotEmpty) ...[
              const SizedBox(height: 10),
              _DetailRow(icon: Icons.groups, label: 'Φορέας', value: carrier),
            ],
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.access_time,
              label: 'Δημιουργία',
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
        Icon(icon, size: 16, color: AppColors.gray500),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: Text(label,
              style: tt.bodySmall?.copyWith(color: AppColors.gray500)),
        ),
        Expanded(
          child: Text(value,
              style: tt.bodyMedium?.copyWith(fontWeight: AppFontWeight.medium)),
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
      elevation: 2,
      shadowColor: Colors.black.withAlpha(20),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.r16,
        side: BorderSide(color: AppColors.gray100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.schedule, size: 18, color: AppColors.red600),
                const SizedBox(width: 8),
                Text('Προεπιλεγμένες Ώρες',
                    style: tt.titleMedium
                        ?.copyWith(fontWeight: AppFontWeight.semibold)),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                _HoursBadge(
                    label: 'Κάλυψη',
                    value: svc['defaultHours'] ?? 0,
                    color: AppColors.red600),
                const SizedBox(width: 8),
                _HoursBadge(
                    label: 'Εθελοντικές',
                    value: svc['defaultHoursVol'] ?? 0,
                    color: AppColors.emerald600),
                const SizedBox(width: 8),
                _HoursBadge(
                    label: 'Επανεκπ.',
                    value: svc['defaultHoursTraining'] ?? 0,
                    color: AppColors.violet600),
                const SizedBox(width: 8),
                _HoursBadge(
                    label: 'Εκπαιδ.',
                    value: svc['defaultHoursTrainers'] ?? 0,
                    color: AppColors.amber600),
                const SizedBox(width: 8),
                _HoursBadge(
                    label: 'ΤΕΠ',
                    value: svc['defaultHoursTEP'] ?? 0,
                    color: AppColors.cyan600),
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
  final Color color;
  const _HoursBadge(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(15),
          borderRadius: AppRadius.r12,
          border: Border.all(color: color.withAlpha(40)),
        ),
        child: Column(
          children: [
            Text('$value',
                style: tt.titleMedium
                    ?.copyWith(fontWeight: AppFontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: tt.bodySmall?.copyWith(
                    color: color.withAlpha(180), fontSize: AppFontSize.xs),
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
      elevation: 2,
      shadowColor: Colors.black.withAlpha(20),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.r16,
        side: BorderSide(color: AppColors.gray100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.visibility,
                    size: 18, color: AppColors.violet600),
                const SizedBox(width: 8),
                Text('Απαιτούμενες Ειδικότητες',
                    style: tt.titleMedium
                        ?.copyWith(fontWeight: AppFontWeight.semibold)),
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
                  backgroundColor: AppColors.violet100,
                  labelStyle: const TextStyle(fontSize: AppFontSize.base),
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
  final int? responsibleUserId;
  final bool canManage;
  final bool canManageParticipation;
  final String lifecycleStatus;
  final void Function(int userId)? onAccept;
  final void Function(int userId)? onReject;
  final void Function(int userId, String userName)? onRemove;
  final void Function(Map<String, dynamic> userService)? onEditHours;
  final void Function(int userId, String status)? onUpdateParticipation;

  const _PeopleSection({
    required this.requested,
    required this.accepted,
    required this.rejected,
    this.responsibleUserId,
    this.canManage = true,
    this.canManageParticipation = false,
    this.lifecycleStatus = 'active',
    this.onAccept,
    this.onReject,
    this.onRemove,
    this.onEditHours,
    this.onUpdateParticipation,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final totalPeople = canManage
        ? requested.length + accepted.length + rejected.length
        : accepted.length;

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withAlpha(20),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.r16,
        side: BorderSide(color: AppColors.gray100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.people, size: 20, color: AppColors.red600),
                const SizedBox(width: 8),
                Text('Μέλη Υπηρεσίας',
                    style: tt.titleMedium
                        ?.copyWith(fontWeight: AppFontWeight.semibold)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.red600.withAlpha(15),
                    borderRadius: AppRadius.r12,
                  ),
                  child: Text('$totalPeople σύνολο',
                      style: const TextStyle(
                          color: AppColors.red600,
                          fontSize: AppFontSize.base,
                          fontWeight: AppFontWeight.semibold)),
                ),
              ],
            ),
            const Divider(height: 20),

            // ── Pending requests (highlighted, admin only) ──
            if (requested.isNotEmpty && canManage) ...[
              _PeopleGroupHeader(
                label: 'Εκκρεμείς Αιτήσεις',
                count: requested.length,
                color: AppColors.amber600,
                icon: Icons.hourglass_top,
              ),
              const SizedBox(height: 8),
              ...requested.map((us) {
                final user = us['user'] as Map<String, dynamic>? ?? {};
                return _PendingUserTile(
                  userService: us,
                  isResponsible: (user['id'] as int?) == responsibleUserId,
                  onAccept: onAccept != null
                      ? () => onAccept!(user['id'] as int)
                      : null,
                  onReject: onReject != null
                      ? () => onReject!(user['id'] as int)
                      : null,
                );
              }),
              const SizedBox(height: 16),
            ],

            // ── Accepted / Participated (visible to all) ──
            if (accepted.isNotEmpty) ...[
              _PeopleGroupHeader(
                label: 'Εγκεκριμένοι',
                count: accepted.length,
                color: AppColors.emerald600,
                icon: Icons.check_circle,
              ),
              const SizedBox(height: 8),
              ...accepted.map((us) {
                final user = us['user'] as Map<String, dynamic>? ?? {};
                final uid = user['id'] as int;
                final name =
                    '${user['forename'] ?? ''} ${user['surname'] ?? ''}'.trim();
                final participationStatus = us['status'] as String?;
                return _AcceptedUserTile(
                  userService: us,
                  isResponsible: (user['id'] as int?) == responsibleUserId,
                  showActions: canManage || canManageParticipation,
                  participationStatus:
                      canManageParticipation ? participationStatus : null,
                  onToggleParticipation: onUpdateParticipation != null
                      ? (status) => onUpdateParticipation!(uid, status)
                      : null,
                  onRemove:
                      onRemove != null ? () => onRemove!(uid, name) : null,
                  onEditHours:
                      onEditHours != null ? () => onEditHours!(us) : null,
                );
              }),
              const SizedBox(height: 16),
            ],

            // ── Rejected (admin only) ──
            if (rejected.isNotEmpty && canManage) ...[
              _PeopleGroupHeader(
                label: 'Απορριφθέντες',
                count: rejected.length,
                color: AppColors.red600,
                icon: Icons.cancel,
              ),
              const SizedBox(height: 8),
              ...rejected.map((us) {
                final user = us['user'] as Map<String, dynamic>? ?? {};
                final uid = user['id'] as int;
                final name =
                    '${user['forename'] ?? ''} ${user['surname'] ?? ''}'.trim();
                return _RejectedUserTile(
                  userService: us,
                  isResponsible: (user['id'] as int?) == responsibleUserId,
                  onAccept: onAccept != null ? () => onAccept!(uid) : null,
                  onRemove:
                      onRemove != null ? () => onRemove!(uid, name) : null,
                );
              }),
            ],

            if (totalPeople == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.people_outline,
                          size: 48, color: AppColors.gray300),
                      const SizedBox(height: 8),
                      Text('Κανένα μέλος',
                          style: tt.bodyMedium
                              ?.copyWith(color: AppColors.gray500)),
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
                ?.copyWith(fontWeight: AppFontWeight.semibold, color: color)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: AppRadius.r10,
          ),
          child: Text('$count',
              style: TextStyle(
                  color: color,
                  fontSize: AppFontSize.sm,
                  fontWeight: AppFontWeight.semibold)),
        ),
      ],
    );
  }
}

// ── User tiles ──

class _PendingUserTile extends StatelessWidget {
  final Map<String, dynamic> userService;
  final bool isResponsible;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  const _PendingUserTile({
    required this.userService,
    this.isResponsible = false,
    this.onAccept,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final user = userService['user'] as Map<String, dynamic>? ?? {};
    final name = '${user['forename'] ?? ''} ${user['surname'] ?? ''}'.trim();
    final eame = user['eame'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.orange50,
        borderRadius: AppRadius.r10,
        border: Border.all(color: AppColors.orange300),
      ),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.amber600,
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: AppFontWeight.semibold,
                  fontSize: AppFontSize.lg)),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(name,
                  style: const TextStyle(
                      fontWeight: AppFontWeight.semibold,
                      fontSize: AppFontSize.lg),
                  overflow: TextOverflow.ellipsis),
            ),
            if (isResponsible) ...[
              const SizedBox(width: 6),
              const _ResponsibleBadge(),
            ],
          ],
        ),
        subtitle: Text(eame,
            style: const TextStyle(
                fontSize: AppFontSize.base, color: AppColors.gray500)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onAccept != null)
              IconButton(
                onPressed: onAccept,
                icon:
                    const Icon(Icons.check_circle, color: AppColors.emerald600),
                iconSize: 22,
                tooltip: 'Έγκριση',
                visualDensity: VisualDensity.compact,
              ),
            if (onReject != null)
              IconButton(
                onPressed: onReject,
                icon: const Icon(Icons.cancel, color: AppColors.red600),
                iconSize: 22,
                tooltip: 'Απόρριψη',
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
  final bool isResponsible;
  final bool showActions;
  final String? participationStatus;
  final void Function(String status)? onToggleParticipation;
  final VoidCallback? onRemove;
  final VoidCallback? onEditHours;

  const _AcceptedUserTile({
    required this.userService,
    this.isResponsible = false,
    this.showActions = true,
    this.participationStatus,
    this.onToggleParticipation,
    this.onRemove,
    this.onEditHours,
  });

  @override
  Widget build(BuildContext context) {
    final user = userService['user'] as Map<String, dynamic>? ?? {};
    final name = '${user['forename'] ?? ''} ${user['surname'] ?? ''}'.trim();
    final eame = user['eame'] ?? '';
    final hours = userService['hours'] ?? 0;
    final hoursVol = userService['hoursVol'] ?? 0;
    final hoursTraining = userService['hoursTraining'] ?? 0;
    final hoursTrainers = userService['hoursTrainers'] ?? 0;
    final hoursTEP = userService['hoursTEP'] ?? 0;
    final totalHours = (hours as int) +
        (hoursVol as int) +
        (hoursTraining as int) +
        (hoursTrainers as int) +
        (hoursTEP as int);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.green50,
        borderRadius: AppRadius.r12,
        border: Border.all(color: AppColors.green200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.emerald600,
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: AppFontWeight.semibold,
                          fontSize: AppFontSize.lg)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(name,
                                style: const TextStyle(
                                    fontWeight: AppFontWeight.semibold,
                                    fontSize: AppFontSize.lg),
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (isResponsible) ...[
                            const SizedBox(width: 6),
                            const _ResponsibleBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(eame,
                          style: const TextStyle(
                              fontSize: AppFontSize.base,
                              color: AppColors.gray500)),
                    ],
                  ),
                ),
                if (showActions) ...[
                  if (onToggleParticipation != null)
                    _ParticipationToggle(
                      currentStatus: participationStatus ?? 'accepted',
                      onToggle: onToggleParticipation!,
                    ),
                  if (onEditHours != null)
                    IconButton(
                      onPressed: onEditHours!,
                      icon: const Icon(Icons.timer, color: AppColors.red600),
                      iconSize: 20,
                      tooltip: 'Επεξεργασία ωρών',
                      visualDensity: VisualDensity.compact,
                    ),
                  if (onRemove != null)
                    IconButton(
                      onPressed: onRemove!,
                      icon: Icon(Icons.person_remove,
                          color: AppColors.red400, size: 20),
                      tooltip: 'Αφαίρεση',
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ],
            ),
            if (totalHours > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 46), // align with name
                  if (hours > 0)
                    _MiniHoursBadge(
                        label: 'Κάλ.', value: hours, color: AppColors.red600),
                  if (hoursVol > 0)
                    _MiniHoursBadge(
                        label: 'Εθελ.',
                        value: hoursVol,
                        color: AppColors.emerald600),
                  if (hoursTraining > 0)
                    _MiniHoursBadge(
                        label: 'Επαν.',
                        value: hoursTraining,
                        color: AppColors.violet600),
                  if (hoursTrainers > 0)
                    _MiniHoursBadge(
                        label: 'Εκπ.',
                        value: hoursTrainers,
                        color: AppColors.amber600),
                  if (hoursTEP > 0)
                    _MiniHoursBadge(
                        label: 'ΤΕΠ',
                        value: hoursTEP,
                        color: AppColors.cyan600),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RejectedUserTile extends StatelessWidget {
  final Map<String, dynamic> userService;
  final bool isResponsible;
  final VoidCallback? onAccept;
  final VoidCallback? onRemove;

  const _RejectedUserTile({
    required this.userService,
    this.isResponsible = false,
    this.onAccept,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final user = userService['user'] as Map<String, dynamic>? ?? {};
    final name = '${user['forename'] ?? ''} ${user['surname'] ?? ''}'.trim();
    final eame = user['eame'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.red50,
        borderRadius: AppRadius.r10,
        border: Border.all(color: AppColors.red200),
      ),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.red400,
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: AppFontWeight.semibold,
                  fontSize: AppFontSize.lg)),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(name,
                  style: const TextStyle(
                      fontWeight: AppFontWeight.semibold,
                      fontSize: AppFontSize.lg),
                  overflow: TextOverflow.ellipsis),
            ),
            if (isResponsible) ...[
              const SizedBox(width: 6),
              const _ResponsibleBadge(),
            ],
          ],
        ),
        subtitle: Text(eame,
            style: const TextStyle(
                fontSize: AppFontSize.base, color: AppColors.gray500)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onAccept != null)
              IconButton(
                onPressed: onAccept,
                icon: const Icon(Icons.check_circle,
                    color: AppColors.emerald600, size: 20),
                tooltip: 'Έγκριση',
                visualDensity: VisualDensity.compact,
              ),
            if (onRemove != null)
              IconButton(
                onPressed: onRemove,
                icon: Icon(Icons.delete, color: AppColors.red400, size: 20),
                tooltip: 'Αφαίρεση',
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Member Equipment Card ────────────────────────────────

class _MemberEquipmentCard extends StatelessWidget {
  final List<dynamic> userServices;
  final bool visible;
  final int? currentUserId;
  final bool canManage;
  final Future<void> Function(int itemId, String itemName) onReturnItem;
  final VoidCallback onTakeItems;

  const _MemberEquipmentCard({
    required this.userServices,
    required this.visible,
    required this.currentUserId,
    required this.canManage,
    required this.onReturnItem,
    required this.onTakeItems,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final tt = Theme.of(context).textTheme;

    // Collect items from accepted members
    final List<Map<String, dynamic>> memberItems = [];
    for (final us in userServices) {
      if (us['status'] != 'accepted') continue;
      final user = us['user'] as Map<String, dynamic>? ?? {};
      final items = user['assignedItems'] as List<dynamic>? ?? [];
      for (final item in items) {
        memberItems.add({
          'user': user,
          'item': item as Map<String, dynamic>,
        });
      }
    }

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withAlpha(20),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.r16,
        side: BorderSide(color: AppColors.gray100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2,
                    size: 18, color: AppColors.violet600),
                const SizedBox(width: 8),
                Text('Εξοπλισμός μελών',
                    style: tt.titleMedium
                        ?.copyWith(fontWeight: AppFontWeight.semibold)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.violet600.withAlpha(20),
                    borderRadius: AppRadius.r10,
                  ),
                  child: Text('${memberItems.length}',
                      style: tt.bodySmall?.copyWith(
                          color: AppColors.violet600,
                          fontWeight: AppFontWeight.bold)),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: onTakeItems,
                  icon: const Icon(Icons.add_circle_outline, size: 22),
                  tooltip: 'Προσθήκη Εξοπλισμού',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.red600,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            if (memberItems.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 40, color: AppColors.gray300),
                      const SizedBox(height: 8),
                      Text('Κανένα αντικείμενο',
                          style:
                              tt.bodySmall?.copyWith(color: AppColors.gray400)),
                      const SizedBox(height: 4),
                      Text(
                          'Τα μέλη μπορούν να πάρουν εξοπλισμό από τα Αντικείμενα',
                          style: tt.bodySmall?.copyWith(
                              color: AppColors.gray400,
                              fontSize: AppFontSize.sm)),
                    ],
                  ),
                ),
              )
            else ...[
              const Divider(height: 20),
              ...memberItems.map((entry) {
                final user = entry['user'] as Map<String, dynamic>;
                final item = entry['item'] as Map<String, dynamic>;
                final isContainer = item['isContainer'] == true;
                final userName =
                    '${user['forename'] ?? ''} ${user['surname'] ?? ''}'.trim();

                final isOwn = user['id'] == currentUserId;
                final canReturn = isOwn || canManage;
                final itemId = item['id'] as int?;

                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor:
                        (isContainer ? AppColors.blue600 : AppColors.red600)
                            .withAlpha(25),
                    child: Icon(
                      isContainer
                          ? Icons.check_box_outline_blank
                          : Icons.circle_outlined,
                      color: isContainer ? AppColors.blue600 : AppColors.red600,
                      size: 18,
                    ),
                  ),
                  title: Text(item['name'] ?? '',
                      style: const TextStyle(
                          fontSize: AppFontSize.lg,
                          fontWeight: AppFontWeight.semibold)),
                  subtitle: Text(
                    [
                      userName,
                      if (item['barCode'] != null) 'BC: ${item['barCode']}',
                      if (item['location'] != null) item['location'],
                    ].join(' · '),
                    style: const TextStyle(
                        fontSize: AppFontSize.sm, color: AppColors.gray500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: canReturn && itemId != null
                      ? TextButton.icon(
                          onPressed: () =>
                              onReturnItem(itemId, item['name'] ?? ''),
                          icon: const Icon(Icons.undo, size: 16),
                          label: const Text('Επιστροφή',
                              style: TextStyle(fontSize: AppFontSize.base)),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.red600,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                      : null,
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

  const _VehicleLogsCard({required this.vehicleLogs, required this.formatDate});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      elevation: 2,
      shadowColor: Colors.black.withAlpha(20),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.r16,
        side: BorderSide(color: AppColors.gray100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_car,
                    size: 18, color: AppColors.amber600),
                const SizedBox(width: 8),
                Text('Αρχεία Οχημάτων',
                    style: tt.titleMedium
                        ?.copyWith(fontWeight: AppFontWeight.semibold)),
                const Spacer(),
                Text('${vehicleLogs.length}',
                    style: tt.bodySmall?.copyWith(color: AppColors.gray500)),
              ],
            ),
            if (vehicleLogs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('Κανένα αρχείο οχήματος',
                      style: tt.bodySmall?.copyWith(color: AppColors.gray400)),
                ),
              )
            else ...[
              const Divider(height: 20),
              ...vehicleLogs.map((log) {
                final vehicle = log['vehicle'] as Map<String, dynamic>? ?? {};
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.directions_car,
                      size: 20, color: AppColors.gray600),
                  title: Text(vehicle['name'] ?? '',
                      style: const TextStyle(fontSize: AppFontSize.lg)),
                  subtitle: Text(
                    '${formatDate(log['startAt'])} → ${formatDate(log['endAt'])}',
                    style: const TextStyle(
                        fontSize: AppFontSize.sm, color: AppColors.gray500),
                  ),
                  trailing: Text(
                    '${log['meterStart']}→${log['meterEnd']}',
                    style: const TextStyle(
                        fontSize: AppFontSize.sm, color: AppColors.gray500),
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

class _ResponsibleBadge extends StatelessWidget {
  const _ResponsibleBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.violet600.withAlpha(20),
        borderRadius: AppRadius.r6,
        border: Border.all(color: AppColors.violet600.withAlpha(60)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 12, color: AppColors.violet600),
          SizedBox(width: 2),
          Text(
            'Υπεύθυνος',
            style: TextStyle(
              fontSize: AppFontSize.xs,
              fontWeight: AppFontWeight.semibold,
              color: AppColors.violet600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticipationToggle extends StatelessWidget {
  final String currentStatus;
  final void Function(String status) onToggle;

  const _ParticipationToggle({
    required this.currentStatus,
    required this.onToggle,
  });

  bool get _isParticipated =>
      currentStatus == 'participated' || currentStatus == 'accepted';

  @override
  Widget build(BuildContext context) {
    final next = _isParticipated ? 'not-participated' : 'participated';
    final color = _isParticipated ? AppColors.emerald600 : AppColors.red400;
    final icon = _isParticipated ? Icons.thumb_up_alt : Icons.thumb_down_alt;
    final tooltip = _isParticipated
        ? 'Παρών — κλικ για Απουσία'
        : 'Απών — κλικ για Παρουσία';

    return IconButton(
      onPressed: () => onToggle(next),
      icon: Icon(icon, color: color),
      iconSize: 20,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _MiniHoursBadge extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _MiniHoursBadge(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: AppRadius.r8,
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Text(
        '$label ${value}ω',
        style: TextStyle(
          fontSize: AppFontSize.xs,
          fontWeight: AppFontWeight.semibold,
          color: color,
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
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _HeaderChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(30),
        borderRadius: AppRadius.r16,
        border: Border.all(color: Colors.white.withAlpha(50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white.withAlpha(220)),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: Colors.white.withAlpha(222),
              fontSize: AppFontSize.sm,
              fontWeight: AppFontWeight.medium,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Victims Section for Service Detail
// ═══════════════════════════════════════════════════════════════

class _VictimsSection extends StatefulWidget {
  final int serviceId;

  const _VictimsSection({
    required this.serviceId,
  });

  @override
  State<_VictimsSection> createState() => _VictimsSectionState();
}

class _VictimsSectionState extends State<_VictimsSection> {
  List<Map<String, dynamic>> _victims = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadVictims();
  }

  Future<void> _loadVictims() async {
    final provider = context.read<VictimProvider>();
    await provider.fetchVictims(
      serviceId: widget.serviceId,
      limit: 100,
    );
    if (mounted)
      setState(() {
        _victims = List<Map<String, dynamic>>.from(provider.victims);
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withAlpha(20),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.r16,
        side: BorderSide(color: AppColors.gray100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.personal_injury_outlined,
                    size: 18, color: AppColors.brandPrimary),
                const SizedBox(width: 8),
                Text('Περιστατικά',
                    style: tt.titleMedium
                        ?.copyWith(fontWeight: AppFontWeight.semibold)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.brandPrimary.withAlpha(20),
                    borderRadius: AppRadius.r10,
                  ),
                  child: Text('${_victims.length}',
                      style: tt.bodySmall?.copyWith(
                          color: AppColors.brandPrimary,
                          fontWeight: AppFontWeight.bold)),
                ),
              ],
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_victims.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.personal_injury_outlined,
                          size: 40, color: AppColors.gray300),
                      const SizedBox(height: 8),
                      Text('Κανένα περιστατικό',
                          style:
                              tt.bodySmall?.copyWith(color: AppColors.gray400)),
                    ],
                  ),
                ),
              )
            else ...[
              const Divider(height: 20),
              ..._victims.take(5).map((v) {
                final name = v['name'] ?? '';
                final age = v['age'];
                final createdAt = v['createdAt'] as String?;
                final isFinalized = v['isFinalized'] == true;

                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: isFinalized
                        ? AppColors.amber500.withAlpha(25)
                        : AppColors.brandPrimary.withAlpha(25),
                    child: Icon(
                      isFinalized ? Icons.lock : Icons.personal_injury,
                      size: 18,
                      color: isFinalized
                          ? AppColors.amber500
                          : AppColors.brandPrimary,
                    ),
                  ),
                  title: Text(
                    [name, if (age != null) '$age ετών'].join(', '),
                    style: const TextStyle(
                        fontSize: AppFontSize.lg,
                        fontWeight: AppFontWeight.semibold),
                  ),
                  subtitle: Text(
                    createdAt != null ? _formatDt(createdAt) : '',
                    style: const TextStyle(
                        fontSize: AppFontSize.sm, color: AppColors.gray500),
                  ),
                  onTap: () => context.push('/victims/${v['id']}'),
                );
              }),
              if (_victims.length > 5)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('...και ${_victims.length - 5} ακόμα',
                      style: tt.bodySmall?.copyWith(color: AppColors.gray500)),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDt(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
