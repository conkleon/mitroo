import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/service_provider.dart';
import '../providers/sync_provider.dart';
import '../services/api_client.dart';
import 'service_card.dart';

class ClosedServicesTab extends StatefulWidget {
  final int departmentId;
  final String departmentName;

  const ClosedServicesTab({
    super.key,
    required this.departmentId,
    required this.departmentName,
  });

  @override
  State<ClosedServicesTab> createState() => ClosedServicesTabState();
}

class ClosedServicesTabState extends State<ClosedServicesTab>
    with AutomaticKeepAliveClientMixin {
  final _api = ApiClient();
  List<dynamic> _services = [];
  List<dynamic> _deptMembers = [];
  bool _loading = true;
  bool _isSyncing = false;
  String _search = '';
  final Set<int> _expandedCards = {};

  @override
  bool get wantKeepAlive => true;

  int get departmentId => widget.departmentId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ClosedServicesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.departmentId != widget.departmentId) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.get(
            '/services?departmentId=${widget.departmentId}&includeEnrollments=true&includeExpired=true&lifecycleStatus=closed'),
        _api.get('/departments/${widget.departmentId}/members'),
      ]);
      if (results[0].statusCode == 200 && mounted) {
        _services = jsonDecode(results[0].body);
      }
      if (results[1].statusCode == 200 && mounted) {
        _deptMembers = jsonDecode(results[1].body);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> sync() async {
    if (_isSyncing) return;
    if (mounted) setState(() => _isSyncing = true);
    try {
      final sync = context.read<SyncProvider>();
      await sync.syncClosed(widget.departmentId);
    } catch (_) {}
    if (mounted) {
      setState(() => _isSyncing = false);
      _load();
    }
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

  void _localUpdateStatus(int serviceId, int userId, String newStatus) {
    setState(() {
      for (final svc in _services) {
        if ((svc['id'] as int?) == serviceId) {
          final us = (svc['userServices'] as List<dynamic>? ?? []);
          for (final e in us) {
            final uid = e['userId'] as int? ?? (e['user']?['id'] as int?);
            if (uid == userId) {
              e['status'] = newStatus;
              break;
            }
          }
          break;
        }
      }
    });
  }

  void _localRemoveEnrollment(int serviceId, int userId) {
    setState(() {
      for (final svc in _services) {
        if ((svc['id'] as int?) == serviceId) {
          final us = (svc['userServices'] as List<dynamic>? ?? []);
          us.removeWhere((e) {
            final uid = e['userId'] as int? ?? (e['user']?['id'] as int?);
            return uid == userId;
          });
          (svc['_count'] as Map<String, dynamic>?)?['userServices'] =
              us.length;
          break;
        }
      }
    });
  }

  void _localSetResponsible(int serviceId, Map<String, dynamic>? user) {
    setState(() {
      for (final svc in _services) {
        if ((svc['id'] as int?) == serviceId) {
          if (user == null) {
            svc.remove('responsibleUser');
          } else {
            svc['responsibleUser'] = user;
          }
          break;
        }
      }
    });
  }

  Future<void> _updateEnrollmentStatus(
      int serviceId, int userId, String status) async {
    final err = await context
        .read<ServiceProvider>()
        .updateUserStatus(serviceId, userId, status);
    if (!mounted) return;
    if (err == null) {
      _localUpdateStatus(serviceId, userId, status);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _updateParticipation(
      int serviceId, int userId, String status) async {
    final err = await context
        .read<ServiceProvider>()
        .updateParticipation(serviceId, userId, status);
    if (!mounted) return;
    if (err == null) {
      _localUpdateStatus(serviceId, userId, status);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
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
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Αφαίρεση'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final err = await context
        .read<ServiceProvider>()
        .removeUser(serviceId, userId);
    if (!mounted) return;
    if (err == null) {
      _localRemoveEnrollment(serviceId, userId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Σφάλμα αφαίρεσης εγγραφής')));
    }
  }

  Future<void> _completeService(int serviceId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ολοκλήρωση Υπηρεσίας'),
        content: Text(
            'Ολοκλήρωση "$name"; Όλοι οι αποδεκτοί εθελοντές θα σημανθούν ως παρόντες.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Ακύρωση')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF059669)),
            child: const Text('Ολοκλήρωση'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final res = await _api.post('/services/$serviceId/complete', body: {});
    if (!mounted) return;
    if (res.statusCode == 200) {
      setState(() {
        _services.removeWhere((s) => (s as Map)['id'] == serviceId);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Αποτυχία ολοκλήρωσης υπηρεσίας')),
      );
    }
  }

  Future<void> _assignResponsible(int serviceId, int? userId) async {
    final err = await context
        .read<ServiceProvider>()
        .setResponsibleUser(serviceId, userId);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
  }

  void _showResponsiblePicker(Map<String, dynamic> svc) {
    final serviceId = svc['id'] as int;
    final current = svc['responsibleUser'] as Map<String, dynamic>?;
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Υπεύθυνος Υπηρεσίας',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(svc['name'] ?? '',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: const Color(0xFF6B7280))),
            const SizedBox(height: 12),
            if (current != null) ...[
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: cs.primary.withAlpha(20),
                    child: Text(
                      '${current['forename'] ?? ''} ${current['surname'] ?? ''}'
                              .trim()
                              .isNotEmpty
                          ? '${current['forename'] ?? ''} ${current['surname'] ?? ''}'
                              .trim()[0]
                              .toUpperCase()
                          : '?',
                      style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${current['forename'] ?? ''} ${current['surname'] ?? ''}'
                          .trim(),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _assignResponsible(serviceId, null);
                      _localSetResponsible(serviceId, null);
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.close,
                        size: 16, color: Color(0xFFDC2626)),
                    label: const Text('Αφαίρεση',
                        style: TextStyle(color: Color(0xFFDC2626))),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
            ],
            Builder(builder: (ctx) {
              final userServices =
                  svc['userServices'] as List<dynamic>? ?? [];
              final acceptedUsers = userServices
                  .where(
                      (us) => us['status'] == 'accepted' && us['user'] != null)
                  .map((us) => us['user'] as Map<String, dynamic>)
                  .toList();

              if (acceptedUsers.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      'Δεν υπάρχουν εγκεκριμένα μέλη σε αυτή την υπηρεσία',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF9CA3AF))),
                );
              }

              return Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: acceptedUsers.map((u) {
                    final name =
                        '${u['forename'] ?? ''} ${u['surname'] ?? ''}'.trim();
                    final isCurrent =
                        current != null && current['id'] == u['id'];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: isCurrent
                            ? const Color(0xFF7C3AED)
                            : cs.primary.withAlpha(20),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: isCurrent ? Colors.white : cs.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      title: Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      trailing: isCurrent
                          ? const Icon(Icons.check_circle,
                              size: 20, color: Color(0xFF7C3AED))
                          : null,
                      onTap: () {
                        final userId = u['id'] as int;
                        _assignResponsible(serviceId, userId);
                        _localSetResponsible(serviceId, u);
                        Navigator.pop(ctx);
                      },
                    );
                  }).toList(),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final filtered = _filtered;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Αναζήτηση υπηρεσιών...',
              prefixIcon: const Icon(Icons.search),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.inbox,
                            size: 64, color: Color(0xFFD1D5DB)),
                        const SizedBox(height: 12),
                        Text('Δεν βρέθηκαν υπηρεσίες',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: const Color(0xFF6B7280))),
                      ]))
              : RefreshIndicator(
                  onRefresh: sync,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final svc = filtered[i] as Map<String, dynamic>;
                      final id = svc['id'] as int;
                      final name = svc['name'] ?? '';
                      return ServiceCard(
                        service: svc,
                        isExpanded: _expandedCards.contains(id),
                        onToggleExpand: () => setState(() {
                          _expandedCards.contains(id)
                              ? _expandedCards.remove(id)
                              : _expandedCards.add(id);
                        }),
                        deptMembers: _deptMembers,
                        onComplete: () => _completeService(id, name),
                        onUpdateStatus:
                            (userId, status) =>
                                _updateEnrollmentStatus(id, userId, status),
                        onUpdateParticipation: (userId, status) =>
                            _updateParticipation(id, userId, status),
                        onRemoveEnrollment: (userId, uName) =>
                            _removeEnrollment(id, userId, uName),
                        onAssignResponsible: () => _showResponsiblePicker(svc),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
