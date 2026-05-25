import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/service_provider.dart';
import '../providers/sync_provider.dart';
import '../services/api_client.dart';
import 'service_card.dart';

class ActiveServicesTab extends StatefulWidget {
  final int departmentId;
  final String departmentName;

  const ActiveServicesTab({
    super.key,
    required this.departmentId,
    required this.departmentName,
  });

  @override
  State<ActiveServicesTab> createState() => ActiveServicesTabState();
}

class ActiveServicesTabState extends State<ActiveServicesTab>
    with AutomaticKeepAliveClientMixin {
  final _api = ApiClient();
  List<dynamic> _services = [];
  List<dynamic> _deptMembers = [];
  bool _loading = true;
  bool _isSyncing = false;
  String _search = '';
  int? _selectedServiceTypeId;
  bool _filtersExpanded = false;
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
  void didUpdateWidget(covariant ActiveServicesTab oldWidget) {
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
            '/services?departmentId=${widget.departmentId}&includeEnrollments=true&lifecycleStatus=active'),
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
      await sync.syncActive(widget.departmentId);
    } catch (_) {}
    if (mounted) {
      setState(() => _isSyncing = false);
      _load();
    }
  }

  List<dynamic> get _filtered {
    var list = List<dynamic>.from(_services);
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
    if (_selectedServiceTypeId != null) {
      list = list.where((s) {
        final st = s['serviceType'] as Map<String, dynamic>?;
        return st?['id'] == _selectedServiceTypeId;
      }).toList();
    }
    list.sort((a, b) {
      final aDate = DateTime.tryParse(a['startAt'] ?? '') ?? DateTime(2099);
      final bDate = DateTime.tryParse(b['startAt'] ?? '') ?? DateTime(2099);
      return aDate.compareTo(bDate);
    });
    return list;
  }

  List<Map<String, dynamic>> get _allServiceTypes {
    final seen = <int>{};
    final types = <Map<String, dynamic>>[];
    for (final svc in _services) {
      final st = svc['serviceType'] as Map<String, dynamic>?;
      if (st == null) continue;
      final id = st['id'] as int?;
      if (id != null && seen.add(id)) types.add(st);
    }
    return types;
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

  void _localUpdateHours(
      int serviceId, int userId, Map<String, dynamic> hours) {
    setState(() {
      for (final svc in _services) {
        if ((svc['id'] as int?) == serviceId) {
          final us = (svc['userServices'] as List<dynamic>? ?? []);
          for (final e in us) {
            final uid = e['userId'] as int? ?? (e['user']?['id'] as int?);
            if (uid == userId) {
              hours.forEach((k, v) => e[k] = v);
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

  void _localAddEnrollment(
      int serviceId, int userId, Map<String, dynamic> member) {
    setState(() {
      for (final svc in _services) {
        if ((svc['id'] as int?) == serviceId) {
          final us = (svc['userServices'] as List<dynamic>? ?? []);
          us.add({
            'userId': userId,
            'status': 'accepted',
            'hours': 0,
            'hoursVol': 0,
            'hoursTraining': 0,
            'hoursTrainers': 0,
            'user': member['user'],
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
              ServiceHoursField(controller: hrsCtrl, label: 'Ώρες'),
              const SizedBox(height: 8),
              ServiceHoursField(controller: volCtrl, label: 'Εθελοντικές'),
              const SizedBox(height: 8),
              ServiceHoursField(
                  controller: trnCtrl, label: 'Επανεκπαίδευση'),
              const SizedBox(height: 8),
              ServiceHoursField(
                  controller: trnrCtrl, label: 'Εκπαιδευτές'),
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
      final hours = {
        'hours': int.tryParse(hrsCtrl.text) ?? 0,
        'hoursVol': int.tryParse(volCtrl.text) ?? 0,
        'hoursTraining': int.tryParse(trnCtrl.text) ?? 0,
        'hoursTrainers': int.tryParse(trnrCtrl.text) ?? 0,
      };
      final res = await _api.patch(
          '/services/$serviceId/users/$userId/hours',
          body: hours);
      if (res.statusCode == 200) {
        _localUpdateHours(serviceId, userId, hours);
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

  Future<void> _directEnroll(
      int serviceId, Map<String, dynamic> member) async {
    final userId = member['user']['id'] as int;
    final err = await context
        .read<ServiceProvider>()
        .enrollUser(serviceId, userId, status: 'accepted');
    if (!mounted) return;
    if (err == null) {
      _localAddEnrollment(serviceId, userId, member);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _closeService(int serviceId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Κλείσιμο Υπηρεσίας'),
        content: Text(
            'Κλείσιμο "$name"; Θα σταλούν ειδοποιήσεις σε όλους τους αποδεκτούς εθελοντές.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD97706)),
            child: const Text('Κλείσιμο'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final res = await _api.post('/services/$serviceId/close', body: {});
    if (!mounted) return;
    if (res.statusCode == 200) {
      setState(() {
        _services.removeWhere((s) => (s as Map)['id'] == serviceId);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Αποτυχία κλεισίματος υπηρεσίας')),
      );
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
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
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
    final serviceTypes = _allServiceTypes;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              Expanded(
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
              if (serviceTypes.isNotEmpty) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(
                      () => _filtersExpanded = !_filtersExpanded),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: (_filtersExpanded ||
                              _selectedServiceTypeId != null)
                          ? const Color(0xFF7C3AED).withAlpha(15)
                          : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (_filtersExpanded ||
                                _selectedServiceTypeId != null)
                            ? const Color(0xFF7C3AED).withAlpha(60)
                            : const Color(0xFFE5E7EB),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 16,
                          color: (_filtersExpanded ||
                                  _selectedServiceTypeId != null)
                              ? const Color(0xFF7C3AED)
                              : const Color(0xFF6B7280),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _selectedServiceTypeId != null
                              ? 'Φίλτρα (1)'
                              : 'Φίλτρα',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: (_filtersExpanded ||
                                    _selectedServiceTypeId != null)
                                ? const Color(0xFF7C3AED)
                                : const Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: (_filtersExpanded && serviceTypes.isNotEmpty)
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemCount: serviceTypes.length,
                      itemBuilder: (context, i) {
                        final st = serviceTypes[i];
                        final stId = st['id'] as int;
                        final selected = _selectedServiceTypeId == stId;
                        return GestureDetector(
                          onTap: () => setState(() {
                            _selectedServiceTypeId =
                                selected ? null : stId;
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFF7C3AED)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFF7C3AED)
                                    : const Color(0xFFD1D5DB),
                              ),
                            ),
                            child: Text(
                              st['name'] ?? '',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFF374151),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                )
              : const SizedBox.shrink(),
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
                        onClose: () => _closeService(id, name),
                        onEdit: () => context.push(
                            '/admin/services/$id/edit?departmentId=${widget.departmentId}&departmentName=${Uri.encodeComponent(widget.departmentName)}'),
                        onDelete: () => _deleteService(id, name),
                        onOpenDetail: () => context.push('/admin/services/$id'),
                        onUpdateStatus:
                            (userId, status) =>
                                _updateEnrollmentStatus(id, userId, status),
                        onUpdateHours:
                            (svcId, userId, us) =>
                                _updateEnrollmentHours(svcId, userId, us),
                        onRemoveEnrollment: (userId, uName) =>
                            _removeEnrollment(id, userId, uName),
                        onDirectEnroll:
                            (member) => _directEnroll(id, member),
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
