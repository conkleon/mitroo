import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mitroo_frontend/theme/theme.dart';

String fmtServiceDate(String? iso) {
  if (iso == null) return '—';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '—';
  return DateFormat('dd/MM/yy HH:mm').format(dt.toLocal());
}

String serviceStatusLabel(Map<String, dynamic> svc) {
  final now = DateTime.now();
  final start = DateTime.tryParse(svc['startAt'] ?? '');
  final end = DateTime.tryParse(svc['endAt'] ?? '');
  if (start == null) return 'Χωρίς ημ/νία';
  if (start.isAfter(now)) return 'Προσεχής';
  if (end != null && end.isBefore(now)) return 'Ολοκληρωμένη';
  return 'Ενεργή';
}

Color serviceStatusColor(String status) {
  switch (status) {
    case 'Προσεχής':
      return AppColors.red600;
    case 'Ενεργή':
      return AppColors.emerald600;
    case 'Ολοκληρωμένη':
      return AppColors.gray500;
    default:
      return AppColors.gray400;
  }
}

Color enrollmentStatusColor(String status) {
  switch (status) {
    case 'accepted':
      return AppColors.emerald600;
    case 'rejected':
      return AppColors.red600;
    case 'requested':
      return AppColors.amber500;
    case 'participated':
      return AppColors.cyan600;
    case 'not-participated':
    case 'not_participated':
      return AppColors.gray500;
    default:
      return AppColors.gray500;
  }
}

Map<String, dynamic> enrollStatusDisplay(String status) {
  switch (status) {
    case 'requested':
      return {'label': 'Εκκρεμής', 'color': AppColors.amber500};
    case 'accepted':
      return {'label': 'Εγκρίθηκε', 'color': AppColors.emerald600};
    case 'rejected':
      return {'label': 'Απορρίφθηκε', 'color': AppColors.red600};
    case 'participated':
      return {'label': 'Παρουσιάστηκε', 'color': AppColors.cyan600};
    case 'not-participated':
    case 'not_participated':
      return {'label': 'Δεν παρ.', 'color': AppColors.gray500};
    default:
      return {'label': status, 'color': AppColors.gray500};
  }
}

class ServiceEnrollBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const ServiceEnrollBadge(this.label, this.count, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: AppRadius.r8,
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Text('$count $label',
          style: TextStyle(
              fontSize: AppFontSize.xs,
              color: color,
              fontWeight: AppFontWeight.semibold)),
    );
  }
}

class ServiceCompactIconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const ServiceCompactIconBtn({
    super.key,
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: AppRadius.r6,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          margin: const EdgeInsets.only(left: 3),
          decoration: BoxDecoration(
            color: color.withAlpha(15),
            borderRadius: AppRadius.r6,
            border: Border.all(color: color.withAlpha(40)),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

class ServiceHoursField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const ServiceHoursField({
    super.key,
    required this.controller,
    required this.label,
  });

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

class ServiceCard extends StatelessWidget {
  final Map<String, dynamic> service;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final List<dynamic>? deptMembers;

  final VoidCallback? onClose;
  final VoidCallback? onComplete;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onOpenDetail;
  final void Function(int userId, String status)? onUpdateStatus;
  final void Function(int serviceId, int userId, Map<String, dynamic> us)?
      onUpdateHours;
  final void Function(int userId, String name)? onRemoveEnrollment;
  final void Function(Map<String, dynamic> member)? onDirectEnroll;
  final void Function(int userId, String newStatus)? onUpdateParticipation;
  final VoidCallback? onAssignResponsible;
  final VoidCallback? onSync;
  final bool isSyncing;

  const ServiceCard({
    super.key,
    required this.service,
    required this.isExpanded,
    required this.onToggleExpand,
    this.deptMembers,
    this.onClose,
    this.onComplete,
    this.onEdit,
    this.onDelete,
    this.onOpenDetail,
    this.onUpdateStatus,
    this.onUpdateHours,
    this.onRemoveEnrollment,
    this.onDirectEnroll,
    this.onUpdateParticipation,
    this.onAssignResponsible,
    this.onSync,
    this.isSyncing = false,
  }) : assert(!isSyncing || onSync != null,
            'isSyncing requires onSync to be set');

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final id = service['id'] as int;
    final name = service['name'] ?? '';
    final location = service['location'] ?? '';
    final status = serviceStatusLabel(service);
    final sColor = serviceStatusColor(status);
    final enrolledCount = (service['_count']?['userServices'] ?? 0) as int;
    final st = service['serviceType'] as Map<String, dynamic>?;
    final visSpecs = st?['specializations'] as List<dynamic>? ?? [];
    final userServices = service['userServices'] as List<dynamic>? ?? [];
    final description = (service['description'] ?? '') as String;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shadowColor: Colors.black.withAlpha(12),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.r12,
        side: const BorderSide(color: AppColors.gray200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onToggleExpand,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(0, 8, 4, 8),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 4, color: sColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCardContent(
                          tt, name, description, location, visSpecs),
                    ),
                    const SizedBox(width: 4),
                    _buildActionColumn(context, enrolledCount, name, id),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: isExpanded
                ? _buildEnrollmentPanel(userServices, tt)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildCardContent(
    TextTheme tt,
    String name,
    String description,
    String location,
    List<dynamic> visSpecs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(name,
                  style: tt.titleSmall?.copyWith(
                      fontWeight: AppFontWeight.bold, fontSize: AppFontSize.lg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 1),
          Text(description,
              style: tt.bodySmall?.copyWith(
                  color: AppColors.gray400, fontSize: AppFontSize.sm),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 4),
        Row(
          children: [
            if (location.isNotEmpty) ...[
              const Icon(Icons.location_on, size: 11, color: AppColors.gray500),
              const SizedBox(width: 2),
              Flexible(
                child: Text(location,
                    style: const TextStyle(
                        fontSize: AppFontSize.xs, color: AppColors.gray600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.calendar_today,
                size: 11, color: AppColors.gray500),
            const SizedBox(width: 2),
            Text(fmtServiceDate(service['startAt']),
                style: const TextStyle(
                    fontSize: AppFontSize.xs, color: AppColors.gray600)),
            if (visSpecs.isNotEmpty) ...[
              const SizedBox(width: 6),
              ...visSpecs.take(2).map((v) => Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.violet50,
                        borderRadius: AppRadius.r4,
                        border: Border.all(color: AppColors.violet200),
                      ),
                      child: Text(v['specialization']?['name'] ?? '',
                          style: const TextStyle(
                              fontSize: AppFontSize.xxs,
                              fontWeight: AppFontWeight.semibold,
                              color: AppColors.violet700)),
                    ),
                  )),
              if (visSpecs.length > 2)
                Text('+${visSpecs.length - 2}',
                    style: const TextStyle(
                        fontSize: AppFontSize.xxs, color: AppColors.violet700)),
            ],
          ],
        ),
        Builder(builder: (_) {
          final resp = service['responsibleUser'] as Map<String, dynamic>?;
          final rName = resp != null
              ? '${resp['forename'] ?? ''} ${resp['surname'] ?? ''}'.trim()
              : '';
          return GestureDetector(
            onTap: onAssignResponsible,
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: resp != null
                    ? AppColors.violet600.withAlpha(15)
                    : AppColors.gray100,
                borderRadius: AppRadius.r4,
                border: Border.all(
                  color: resp != null
                      ? AppColors.violet600.withAlpha(60)
                      : AppColors.gray300,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    resp != null
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 11,
                    color:
                        resp != null ? AppColors.violet600 : AppColors.gray400,
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      resp != null ? rName : 'Υπεύθυνος',
                      style: TextStyle(
                        fontSize: AppFontSize.xxs,
                        fontWeight: AppFontWeight.semibold,
                        color: resp != null
                            ? AppColors.violet600
                            : AppColors.gray400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildActionColumn(
    BuildContext context,
    int enrolledCount,
    String name,
    int id,
  ) {
    final hasActions = onClose != null ||
        onComplete != null ||
        onEdit != null ||
        onDelete != null ||
        onOpenDetail != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: AppRadius.r6,
          onTap: onToggleExpand,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color:
                  isExpanded ? AppColors.red600.withAlpha(20) : AppColors.red50,
              borderRadius: AppRadius.r6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.people_outline,
                    size: 14, color: AppColors.red600),
                const SizedBox(width: 3),
                Text('$enrolledCount',
                    style: const TextStyle(
                        fontSize: AppFontSize.sm,
                        fontWeight: AppFontWeight.semibold,
                        color: AppColors.red600)),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: AppColors.red600,
                ),
              ],
            ),
          ),
        ),
        if (hasActions) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onClose != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: SizedBox(
                    height: 28,
                    child: TextButton(
                      onPressed: onClose,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.amber600,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(fontSize: AppFontSize.sm),
                      ),
                      child: const Text('Κλείσιμο'),
                    ),
                  ),
                ),
              if (onComplete != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: SizedBox(
                    height: 28,
                    child: TextButton(
                      onPressed: onComplete,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.emerald600,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(fontSize: AppFontSize.sm),
                      ),
                      child: const Text('Ολοκλήρωση'),
                    ),
                  ),
                ),
              if (onOpenDetail != null)
                IconButton(
                  icon: const Icon(Icons.open_in_new,
                      size: 15, color: AppColors.gray500),
                  onPressed: onOpenDetail,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Λεπτομέρειες',
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                ),
              if (onEdit != null)
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      size: 16, color: AppColors.emerald600),
                  onPressed: onEdit,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Επεξεργασία',
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: AppColors.red400),
                  onPressed: onDelete,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Διαγραφή',
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
        ],
        if (service['externalMissionId'] != null) ...[
          const SizedBox(height: 4),
          Tooltip(
            message: 'Συγχρονισμός με Mitroo',
            child: InkWell(
              onTap: isSyncing ? null : onSync,
              borderRadius: AppRadius.r6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.cyan600.withAlpha(15),
                  borderRadius: AppRadius.r6,
                  border: Border.all(color: AppColors.cyan600.withAlpha(40)),
                ),
                child: isSyncing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AppColors.cyan600,
                        ),
                      )
                    : const Icon(Icons.sync,
                        size: 14, color: AppColors.cyan600),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEnrollmentPanel(
    List<dynamic> userServices,
    TextTheme tt,
  ) {
    final sorted = List<dynamic>.from(userServices);
    const order = {
      'requested': 0,
      'accepted': 1,
      'rejected': 2,
      'participated': 3,
      'not-participated': 4,
      'not_participated': 4,
    };
    sorted.sort(
        (a, b) => (order[a['status']] ?? 5).compareTo(order[b['status']] ?? 5));

    final acceptedCount =
        userServices.where((u) => u['status'] == 'accepted').length;
    final requestedCount =
        userServices.where((u) => u['status'] == 'requested').length;
    final rejectedCount =
        userServices.where((u) => u['status'] == 'rejected').length;
    final participatedCount =
        userServices.where((u) => u['status'] == 'participated').length;
    final notParticipatedCount = userServices
        .where((u) =>
            u['status'] == 'not-participated' ||
            u['status'] == 'not_participated')
        .length;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.slate50,
        border: Border(top: BorderSide(color: AppColors.gray200)),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Icon(Icons.people, size: 13, color: AppColors.gray600),
            const SizedBox(width: 4),
            Text('Εγγραφές (${userServices.length})',
                style: tt.labelSmall?.copyWith(
                    fontWeight: AppFontWeight.semibold,
                    color: AppColors.gray700,
                    fontSize: AppFontSize.sm)),
            const Spacer(),
            ServiceEnrollBadge('Εγκρ.', acceptedCount, AppColors.emerald600),
            const SizedBox(width: 4),
            ServiceEnrollBadge('Εκκρ.', requestedCount, AppColors.amber500),
            const SizedBox(width: 4),
            ServiceEnrollBadge('Απορ.', rejectedCount, AppColors.red600),
            if (participatedCount > 0) ...[
              const SizedBox(width: 4),
              ServiceEnrollBadge('Παρ.', participatedCount, AppColors.cyan600),
            ],
            if (notParticipatedCount > 0) ...[
              const SizedBox(width: 4),
              ServiceEnrollBadge(
                  'Μη παρ.', notParticipatedCount, AppColors.gray500),
            ],
          ]),
          const SizedBox(height: 6),
          ...sorted.map((us) {
            final user = us['user'] as Map<String, dynamic>?;
            final userId = us['userId'] as int? ?? user?['id'] as int? ?? 0;
            final uName = user != null
                ? '${user['forename'] ?? ''} ${user['surname'] ?? ''}'.trim()
                : 'Unknown';
            final st = (us['status'] ?? 'requested') as String;
            final display = enrollStatusDisplay(st);
            final stColor = display['color'] as Color;
            final stLabel = display['label'] as String;
            final serviceId = service['id'] as int;
            final hasActions = onUpdateStatus != null ||
                onRemoveEnrollment != null ||
                onUpdateParticipation != null ||
                onUpdateHours != null;

            return Container(
              margin: const EdgeInsets.only(bottom: 3),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: st == 'requested' ? AppColors.amber50 : Colors.white,
                borderRadius: AppRadius.r6,
                border: Border.all(
                  color: st == 'requested'
                      ? AppColors.amber300
                      : AppColors.gray200,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (st == 'requested')
                    Container(width: 3, height: 40, color: AppColors.amber500),
                  if (st == 'requested') const SizedBox(width: 6),
                  Builder(
                    builder: (ctx) {
                      final scale = MediaQuery.textScalerOf(ctx).scale(1);
                      final r = (11 * scale).clamp(11.0, 18.0);
                      return CircleAvatar(
                        radius: r,
                        backgroundColor: stColor.withAlpha(30),
                        child: Text(
                          uName.isNotEmpty ? uName[0].toUpperCase() : '?',
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                              color: stColor,
                              fontWeight: AppFontWeight.bold,
                              fontSize: (11 * scale).clamp(11.0, 15.0)),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (ctx, constraints) {
                        final scale = MediaQuery.textScalerOf(ctx).scale(1);
                        final actions = hasActions
                            ? _buildEnrollmentActions(
                                us, st, serviceId, userId, uName)
                            : null;
                        final nameText = Text(uName,
                            style: const TextStyle(
                                fontSize: AppFontSize.base,
                                fontWeight: AppFontWeight.semibold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis);
                        if (actions == null) return nameText;
                        if (constraints.maxWidth < 160 * scale) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              nameText,
                              const SizedBox(height: 2),
                              actions,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: nameText),
                            const SizedBox(width: 4),
                            actions,
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          }),
          if (onDirectEnroll != null && deptMembers != null) ...[
            const SizedBox(height: 8),
            const Divider(color: AppColors.gray200, height: 1),
            const SizedBox(height: 8),
            _buildDirectEnrollField(userServices),
          ],
        ],
      ),
    );
  }

  Widget _buildEnrollmentActions(
    Map<String, dynamic> us,
    String st,
    int serviceId,
    int userId,
    String uName,
  ) {
    final List<Widget> actions = [];

    if (onUpdateParticipation != null) {
      if (st == 'accepted') {
        actions.add(ServiceCompactIconBtn(
          icon: Icons.person_off_outlined,
          color: AppColors.gray500,
          tooltip: 'Μη συμμετοχή',
          onTap: () => onUpdateParticipation!(userId, 'not-participated'),
        ));
      } else if (st == 'not-participated' || st == 'not_participated') {
        actions.add(ServiceCompactIconBtn(
          icon: Icons.undo,
          color: AppColors.amber500,
          tooltip: 'Επαναφορά',
          onTap: () {
            if (onUpdateStatus != null) {
              onUpdateStatus!(userId, 'accepted');
            } else {
              onUpdateParticipation!(userId, 'participated');
            }
          },
        ));
      } else if (st == 'participated') {
        actions.add(ServiceCompactIconBtn(
          icon: Icons.person_off_outlined,
          color: AppColors.gray500,
          tooltip: 'Μη συμμετοχή',
          onTap: () => onUpdateParticipation!(userId, 'not-participated'),
        ));
      }
    }

    if (onUpdateStatus != null) {
      if (st != 'accepted' && st != 'participated') {
        actions.add(ServiceCompactIconBtn(
          icon: Icons.check,
          color: AppColors.emerald600,
          tooltip: 'Αποδοχή',
          onTap: () => onUpdateStatus!(userId, 'accepted'),
        ));
      }
      if (st != 'rejected') {
        actions.add(ServiceCompactIconBtn(
          icon: Icons.close,
          color: AppColors.red600,
          tooltip: 'Απόρριψη',
          onTap: () => onUpdateStatus!(userId, 'rejected'),
        ));
      }
    }

    if (onUpdateHours != null) {
      actions.add(ServiceCompactIconBtn(
        icon: Icons.schedule,
        color: AppColors.gray500,
        tooltip: 'Ώρες',
        onTap: () => onUpdateHours!(serviceId, userId, us),
      ));
    }

    if (onRemoveEnrollment != null) {
      actions.add(ServiceCompactIconBtn(
        icon: Icons.person_remove_outlined,
        color: AppColors.gray400,
        tooltip: 'Αφαίρεση',
        onTap: () => onRemoveEnrollment!(userId, uName),
      ));
    }

    return Row(mainAxisSize: MainAxisSize.min, children: actions);
  }

  Widget _buildDirectEnrollField(List<dynamic> userServices) {
    final members = deptMembers;
    if (members == null) return const SizedBox.shrink();

    final enrolledIds = userServices
        .map((us) => ((us['userId'] ?? us['user']?['id']) as int?) ?? 0)
        .toSet();
    final available = members.where((m) {
      final uid = m['user']?['id'] as int? ?? 0;
      return uid != 0 && !enrolledIds.contains(uid);
    }).toList();

    return Autocomplete<Map<String, dynamic>>(
      displayStringForOption: (m) {
        final u = m['user'] as Map<String, dynamic>;
        return '${u['forename'] ?? ''} ${u['surname'] ?? ''}'.trim();
      },
      optionsBuilder: (TextEditingValue value) {
        if (available.isEmpty) return const [];
        if (value.text.isEmpty) return available.cast<Map<String, dynamic>>();
        final q = value.text.toLowerCase();
        return available.where((m) {
          final u = m['user'] as Map<String, dynamic>;
          final name = '${u['forename'] ?? ''} ${u['surname'] ?? ''}'
              .trim()
              .toLowerCase();
          final eame = (u['eame'] ?? '').toString().toLowerCase();
          return name.contains(q) || eame.contains(q);
        }).cast<Map<String, dynamic>>();
      },
      onSelected: (m) => onDirectEnroll!(m),
      fieldViewBuilder: (context, controller, focusNode, _) => TextField(
        controller: controller,
        focusNode: focusNode,
        style: const TextStyle(fontSize: AppFontSize.base),
        decoration: InputDecoration(
          hintText: 'Προσθήκη μέλους...',
          hintStyle: const TextStyle(
              fontSize: AppFontSize.sm, color: AppColors.gray400),
          prefixIcon: const Icon(Icons.person_add_outlined, size: 16),
          border: OutlineInputBorder(borderRadius: AppRadius.r6),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          isDense: true,
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: AppRadius.r8,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200, maxWidth: 320),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, i) {
                final m = options.elementAt(i);
                final u = m['user'] as Map<String, dynamic>;
                final name =
                    '${u['forename'] ?? ''} ${u['surname'] ?? ''}'.trim();
                final eame = (u['eame'] ?? '').toString();
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.violet50,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          fontSize: AppFontSize.base,
                          color: AppColors.violet700,
                          fontWeight: AppFontWeight.bold),
                    ),
                  ),
                  title: Text(name,
                      style: const TextStyle(fontSize: AppFontSize.md)),
                  subtitle: eame.isNotEmpty
                      ? Text('@$eame',
                          style: const TextStyle(fontSize: AppFontSize.sm))
                      : null,
                  onTap: () => onSelected(m),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
