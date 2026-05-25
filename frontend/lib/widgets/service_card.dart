import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
      return const Color(0xFFDC2626);
    case 'Ενεργή':
      return const Color(0xFF059669);
    case 'Ολοκληρωμένη':
      return const Color(0xFF6B7280);
    default:
      return const Color(0xFF9CA3AF);
  }
}

Color enrollmentStatusColor(String status) {
  switch (status) {
    case 'accepted':
      return const Color(0xFF059669);
    case 'rejected':
      return const Color(0xFFDC2626);
    case 'requested':
      return const Color(0xFFF59E0B);
    case 'participated':
      return const Color(0xFF0891B2);
    case 'not-participated':
    case 'not_participated':
      return const Color(0xFF6B7280);
    default:
      return const Color(0xFF6B7280);
  }
}

Map<String, dynamic> enrollStatusDisplay(String status) {
  switch (status) {
    case 'requested':
      return {'label': 'Εκκρεμής', 'color': const Color(0xFFF59E0B)};
    case 'accepted':
      return {'label': 'Εγκρίθηκε', 'color': const Color(0xFF059669)};
    case 'rejected':
      return {'label': 'Απορρίφθηκε', 'color': const Color(0xFFDC2626)};
    case 'participated':
      return {'label': 'Παρουσιάστηκε', 'color': const Color(0xFF0891B2)};
    case 'not-participated':
    case 'not_participated':
      return {'label': 'Δεν παρ.', 'color': const Color(0xFF6B7280)};
    default:
      return {'label': status, 'color': const Color(0xFF6B7280)};
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Text('$count $label',
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
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
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          margin: const EdgeInsets.only(left: 3),
          decoration: BoxDecoration(
            color: color.withAlpha(15),
            borderRadius: BorderRadius.circular(6),
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
  final void Function(int serviceId, int userId, Map<String, dynamic> us)? onUpdateHours;
  final void Function(int userId, String name)? onRemoveEnrollment;
  final void Function(Map<String, dynamic> member)? onDirectEnroll;
  final void Function(int userId, String newStatus)? onUpdateParticipation;
  final VoidCallback? onAssignResponsible;

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
  });

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
    final requestedCount =
        userServices.where((us) => us['status'] == 'requested').length;
    final description = (service['description'] ?? '') as String;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shadowColor: Colors.black.withAlpha(12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
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
                          tt, name, description, location, enrolledCount,
                          requestedCount, visSpecs),
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
    int enrolledCount,
    int requestedCount,
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
                      fontWeight: FontWeight.w700, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 1),
          Text(description,
              style: tt.bodySmall?.copyWith(
                  color: const Color(0xFF9CA3AF), fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 4),
        Row(
          children: [
            if (location.isNotEmpty) ...[
              const Icon(Icons.location_on, size: 11, color: Color(0xFF6B7280)),
              const SizedBox(width: 2),
              Flexible(
                child: Text(location,
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF4B5563)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.calendar_today, size: 11, color: Color(0xFF6B7280)),
            const SizedBox(width: 2),
            Text(fmtServiceDate(service['startAt']),
                style: const TextStyle(fontSize: 10, color: Color(0xFF4B5563))),
            const SizedBox(width: 8),
            const Icon(Icons.people, size: 11, color: Color(0xFFDC2626)),
            const SizedBox(width: 2),
            Text('$enrolledCount',
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFDC2626))),
            if (requestedCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: Text('$requestedCount εκκρ.',
                    style: const TextStyle(
                        color: Color(0xFFB45309),
                        fontSize: 9,
                        fontWeight: FontWeight.w700)),
              ),
            ],
            if (visSpecs.isNotEmpty) ...[
              const SizedBox(width: 6),
              ...visSpecs.take(2).map((v) => Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F3FF),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFDDD6FE)),
                      ),
                      child: Text(v['specialization']?['name'] ?? '',
                          style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6D28D9))),
                    ),
                  )),
              if (visSpecs.length > 2)
                Text('+${visSpecs.length - 2}',
                    style: const TextStyle(
                        fontSize: 9, color: Color(0xFF6D28D9))),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: resp != null
                    ? const Color(0xFF7C3AED).withAlpha(15)
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: resp != null
                      ? const Color(0xFF7C3AED).withAlpha(60)
                      : const Color(0xFFD1D5DB),
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
                    color: resp != null
                        ? const Color(0xFF7C3AED)
                        : const Color(0xFF9CA3AF),
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      resp != null ? rName : 'Υπεύθυνος',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: resp != null
                            ? const Color(0xFF7C3AED)
                            : const Color(0xFF9CA3AF),
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
          borderRadius: BorderRadius.circular(6),
          onTap: onToggleExpand,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: isExpanded
                  ? const Color(0xFFDC2626).withAlpha(20)
                  : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.people_outline,
                    size: 14, color: Color(0xFFDC2626)),
                const SizedBox(width: 3),
                Text('$enrolledCount',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFDC2626))),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: const Color(0xFFDC2626),
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
                        foregroundColor: const Color(0xFFD97706),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(fontSize: 11),
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
                        foregroundColor: const Color(0xFF059669),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(fontSize: 11),
                      ),
                      child: const Text('Ολοκλήρωση'),
                    ),
                  ),
                ),
              if (onOpenDetail != null)
                IconButton(
                  icon: const Icon(Icons.open_in_new,
                      size: 15, color: Color(0xFF6B7280)),
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
                      size: 16, color: Color(0xFF059669)),
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
                      size: 16, color: Color(0xFFF87171)),
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
    sorted.sort((a, b) =>
        (order[a['status']] ?? 5).compareTo(order[b['status']] ?? 5));

    final acceptedCount =
        userServices.where((u) => u['status'] == 'accepted').length;
    final requestedCount =
        userServices.where((u) => u['status'] == 'requested').length;
    final rejectedCount =
        userServices.where((u) => u['status'] == 'rejected').length;
    final participatedCount =
        userServices.where((u) => u['status'] == 'participated').length;
    final notParticipatedCount =
        userServices
            .where((u) =>
                u['status'] == 'not-participated' ||
                u['status'] == 'not_participated')
            .length;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Icon(Icons.people, size: 13, color: Color(0xFF4B5563)),
            const SizedBox(width: 4),
            Text('Εγγραφές (${userServices.length})',
                style: tt.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF374151),
                    fontSize: 11)),
            const Spacer(),
            ServiceEnrollBadge(
                'Εγκρ.', acceptedCount, const Color(0xFF059669)),
            const SizedBox(width: 4),
            ServiceEnrollBadge(
                'Εκκρ.', requestedCount, const Color(0xFFF59E0B)),
            const SizedBox(width: 4),
            ServiceEnrollBadge(
                'Απορ.', rejectedCount, const Color(0xFFDC2626)),
            if (participatedCount > 0) ...[
              const SizedBox(width: 4),
              ServiceEnrollBadge(
                  'Παρ.', participatedCount, const Color(0xFF0891B2)),
            ],
            if (notParticipatedCount > 0) ...[
              const SizedBox(width: 4),
              ServiceEnrollBadge(
                  'Μη παρ.', notParticipatedCount, const Color(0xFF6B7280)),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: st == 'requested'
                    ? const Color(0xFFFFFBEB)
                    : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: st == 'requested'
                      ? const Color(0xFFFDE68A)
                      : const Color(0xFFE5E7EB),
                ),
              ),
              child: Row(
                children: [
                  if (st == 'requested')
                    Container(
                        width: 3,
                        height: 28,
                        color: const Color(0xFFF59E0B)),
                  if (st == 'requested') const SizedBox(width: 6),
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: stColor.withAlpha(30),
                    child: Text(
                      uName.isNotEmpty ? uName[0].toUpperCase() : '?',
                      style: TextStyle(
                          color: stColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(uName,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: stColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(stLabel,
                        style: TextStyle(
                            color: stColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w700)),
                  ),
                  if (hasActions) ...[
                    const SizedBox(width: 4),
                    _buildEnrollmentActions(us, st, serviceId, userId, uName),
                  ],
                ],
              ),
            );
          }),
          if (onDirectEnroll != null && deptMembers != null) ...[
            const SizedBox(height: 8),
            const Divider(color: Color(0xFFE5E7EB), height: 1),
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
          color: const Color(0xFF6B7280),
          tooltip: 'Μη συμμετοχή',
          onTap: () => onUpdateParticipation!(userId, 'not-participated'),
        ));
      } else if (st == 'not-participated' || st == 'not_participated') {
        actions.add(ServiceCompactIconBtn(
          icon: Icons.undo,
          color: const Color(0xFFF59E0B),
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
          color: const Color(0xFF6B7280),
          tooltip: 'Μη συμμετοχή',
          onTap: () => onUpdateParticipation!(userId, 'not-participated'),
        ));
      }
    }

    if (onUpdateStatus != null) {
      if (st != 'accepted' && st != 'participated') {
        actions.add(ServiceCompactIconBtn(
          icon: Icons.check,
          color: const Color(0xFF059669),
          tooltip: 'Αποδοχή',
          onTap: () => onUpdateStatus!(userId, 'accepted'),
        ));
      }
      if (st != 'rejected') {
        actions.add(ServiceCompactIconBtn(
          icon: Icons.close,
          color: const Color(0xFFDC2626),
          tooltip: 'Απόρριψη',
          onTap: () => onUpdateStatus!(userId, 'rejected'),
        ));
      }
    }

    if (onUpdateHours != null) {
      actions.add(ServiceCompactIconBtn(
        icon: Icons.schedule,
        color: const Color(0xFF6B7280),
        tooltip: 'Ώρες',
        onTap: () => onUpdateHours!(serviceId, userId, us),
      ));
    }

    if (onRemoveEnrollment != null) {
      actions.add(ServiceCompactIconBtn(
        icon: Icons.person_remove_outlined,
        color: const Color(0xFF9CA3AF),
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
          final name =
              '${u['forename'] ?? ''} ${u['surname'] ?? ''}'.trim().toLowerCase();
          final eame = (u['eame'] ?? '').toString().toLowerCase();
          return name.contains(q) || eame.contains(q);
        }).cast<Map<String, dynamic>>();
      },
      onSelected: (m) => onDirectEnroll!(m),
      fieldViewBuilder: (context, controller, focusNode, _) => TextField(
        controller: controller,
        focusNode: focusNode,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          hintText: 'Προσθήκη μέλους...',
          hintStyle:
              const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
          prefixIcon:
              const Icon(Icons.person_add_outlined, size: 16),
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 6),
          isDense: true,
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxHeight: 200, maxWidth: 320),
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
                    backgroundColor: const Color(0xFFF5F3FF),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6D28D9),
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  title: Text(name, style: const TextStyle(fontSize: 13)),
                  subtitle: eame.isNotEmpty
                      ? Text('@$eame',
                          style: const TextStyle(fontSize: 11))
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
