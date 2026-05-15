import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
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
  int? _selectedSpecId;
  final Set<int> _expandedCards = {};
  List<dynamic> _deptMembers = [];

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
      final results = await Future.wait([
        _api.get('/services?departmentId=${widget.departmentId}&includeEnrollments=true'),
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

  List<dynamic> get _filtered {
    var list = List<dynamic>.from(_services);
    final now = DateTime.now();

    // Show only current & upcoming (exclude past)
    list = list.where((s) {
      final end = DateTime.tryParse(s['endAt'] ?? '');
      if (end != null && end.isBefore(now)) return false;
      final start = DateTime.tryParse(s['startAt'] ?? '');
      if (end == null && start != null && start.isBefore(now)) return false;
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

    // Filter by specialization via service type chain
    if (_selectedSpecId != null) {
      list = list.where((s) {
        final st = s['serviceType'] as Map<String, dynamic>?;
        if (st == null) return false;
        final specs2 = st['specializations'] as List<dynamic>? ?? [];
        return specs2.any((row) => row['specialization']?['id'] == _selectedSpecId);
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
        return const Color(0xFFDC2626);
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
            style: FilledButton.styleFrom(backgroundColor: Color(0xFFDC2626)),
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
    final err = await context.read<ServiceProvider>().updateUserStatus(serviceId, userId, status);
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
            style: FilledButton.styleFrom(backgroundColor: Color(0xFFDC2626)),
            child: const Text('Αφαίρεση'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final err = await context.read<ServiceProvider>().removeUser(serviceId, userId);
    if (!mounted) return;
    if (err == null) {
      _localRemoveEnrollment(serviceId, userId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Σφάλμα αφαίρεσης εγγραφής')));
    }
  }

  Future<void> _directEnroll(int serviceId, Map<String, dynamic> member) async {
    final userId = member['user']['id'] as int;
    final err = await context.read<ServiceProvider>().enrollUser(serviceId, userId, status: 'accepted');
    if (!mounted) return;
    if (err == null) {
      _localAddEnrollment(serviceId, userId, member);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  void _localUpdateStatus(int serviceId, int userId, String newStatus) {
    setState(() {
      for (final svc in _services) {
        if ((svc['id'] as int?) == serviceId) {
          final us = (svc['userServices'] as List<dynamic>? ?? []);
          for (final e in us) {
            final uid = e['userId'] as int? ?? (e['user']?['id'] as int?);
            if (uid == userId) { e['status'] = newStatus; break; }
          }
          break;
        }
      }
    });
  }

  void _localUpdateHours(int serviceId, int userId, Map<String, dynamic> hours) {
    setState(() {
      for (final svc in _services) {
        if ((svc['id'] as int?) == serviceId) {
          final us = (svc['userServices'] as List<dynamic>? ?? []);
          for (final e in us) {
            final uid = e['userId'] as int? ?? (e['user']?['id'] as int?);
            if (uid == userId) { hours.forEach((k, v) => e[k] = v); break; }
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
          (svc['_count'] as Map<String, dynamic>?)?['userServices'] = us.length;
          break;
        }
      }
    });
  }

  void _localAddEnrollment(int serviceId, int userId, Map<String, dynamic> member) {
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
          (svc['_count'] as Map<String, dynamic>?)?['userServices'] = us.length;
          break;
        }
      }
    });
  }

  Widget _buildDirectEnrollField(Map<String, dynamic> svc, List<dynamic> userServices) {
    final serviceId = svc['id'] as int;
    final enrolledIds = userServices
        .map((us) => ((us['userId'] ?? us['user']?['id']) as int?) ?? 0)
        .toSet();
    final available = _deptMembers.where((m) {
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
      onSelected: (m) {
        _directEnroll(serviceId, m);
      },
      fieldViewBuilder: (context, controller, focusNode, _) => TextField(
        controller: controller,
        focusNode: focusNode,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          hintText: 'Προσθήκη μέλους...',
          hintStyle: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
          prefixIcon: const Icon(Icons.person_add_outlined, size: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          isDense: true,
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
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
                      ? Text('@$eame', style: const TextStyle(fontSize: 11))
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

  void _openDetail(Map<String, dynamic> svc) =>
      context.push('/admin/services/${svc['id']}');

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

  Future<void> _assignResponsible(int serviceId, int? userId) async {
    final err = await context.read<ServiceProvider>().setResponsibleUser(serviceId, userId);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
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
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Υπεύθυνος Υπηρεσίας',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(svc['name'] ?? '',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Color(0xFF6B7280))),
            const SizedBox(height: 12),
            if (current != null) ...[
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: cs.primary.withAlpha(20),
                    child: Text(
                      '${current['forename'] ?? ''} ${current['surname'] ?? ''}'.trim().isNotEmpty
                          ? '${current['forename'] ?? ''} ${current['surname'] ?? ''}'.trim()[0].toUpperCase()
                          : '?',
                      style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${current['forename'] ?? ''} ${current['surname'] ?? ''}'.trim(),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _assignResponsible(serviceId, null);
                      _localSetResponsible(serviceId, null);
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.close, size: 16, color: Color(0xFFDC2626)),
                    label: const Text('Αφαίρεση', style: TextStyle(color: Color(0xFFDC2626))),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
            ],
            Builder(builder: (ctx) {
              // Only accepted users on this service
              final userServices = svc['userServices'] as List<dynamic>? ?? [];
              final acceptedUsers = userServices
                  .where((us) => us['status'] == 'accepted' && us['user'] != null)
                  .map((us) => us['user'] as Map<String, dynamic>)
                  .toList();

              if (acceptedUsers.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Δεν υπάρχουν εγκεκριμένα μέλη σε αυτή την υπηρεσία',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Color(0xFF9CA3AF))),
                );
              }

              return Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: acceptedUsers.map((u) {
                    final name = '${u['forename'] ?? ''} ${u['surname'] ?? ''}'.trim();
                    final isCurrent = current != null && current['id'] == u['id'];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: isCurrent ? const Color(0xFF7C3AED) : cs.primary.withAlpha(20),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: isCurrent ? Colors.white : cs.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      trailing: isCurrent
                          ? const Icon(Icons.check_circle, size: 20, color: Color(0xFF7C3AED))
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

  void _editService(Map<String, dynamic> svc) async {
    final id = svc['id'] as int;
    await context.push(
        '/admin/services/$id/edit?departmentId=${widget.departmentId}&departmentName=${Uri.encodeComponent(widget.departmentName)}');
    if (mounted) _load();
  }

  /// Collect all unique specializations from loaded services via serviceType chain
  List<Map<String, dynamic>> get _allSpecs {
    final seen = <int>{};
    final specs = <Map<String, dynamic>>[];
    for (final svc in _services) {
      final st = svc['serviceType'] as Map<String, dynamic>?;
      if (st == null) continue;
      final specs2 = st['specializations'] as List<dynamic>? ?? [];
      for (final row in specs2) {
        final spec = row['specialization'] as Map<String, dynamic>?;
        if (spec != null) {
          final id = spec['id'] as int;
          if (seen.add(id)) specs.add(spec);
        }
      }
    }
    return specs;
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final filtered = _filtered;
    final specs = _allSpecs;

    return Scaffold(
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

                    // ── Specialization filter chips ──
                    if (specs.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 0),
                        child: SizedBox(
                          height: 36,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: specs.length + 1,
                            separatorBuilder: (_, __) => const SizedBox(width: 6),
                            itemBuilder: (context, i) {
                              if (i == 0) {
                                final selected = _selectedSpecId == null;
                                return FilterChip(
                                  avatar: Icon(Icons.apps,
                                      size: 14,
                                      color: selected
                                          ? const Color(0xFF7C3AED)
                                          : const Color(0xFF6B7280)),
                                  label: const Text('Όλες'),
                                  selected: selected,
                                  onSelected: (_) =>
                                      setState(() => _selectedSpecId = null),
                                  selectedColor: const Color(0xFFF5F3FF),
                                  checkmarkColor: const Color(0xFF7C3AED),
                                  side: BorderSide(
                                      color: selected
                                          ? const Color(0xFFDDD6FE)
                                          : Color(0xFFD1D5DB)),
                                  visualDensity: VisualDensity.compact,
                                  labelStyle: TextStyle(
                                    fontSize: 12,
                                    fontWeight:
                                        selected ? FontWeight.w600 : FontWeight.w400,
                                    color: selected
                                        ? const Color(0xFF6D28D9)
                                        : const Color(0xFF6B7280),
                                  ),
                                  padding: EdgeInsets.zero,
                                );
                              }
                              final spec = specs[i - 1];
                              final specId = spec['id'] as int;
                              final selected = _selectedSpecId == specId;
                              return FilterChip(
                                avatar: Icon(Icons.workspace_premium,
                                    size: 14,
                                    color: selected
                                        ? const Color(0xFF7C3AED)
                                        : const Color(0xFF6B7280)),
                                label: Text(spec['name'] ?? ''),
                                selected: selected,
                                onSelected: (_) => setState(() =>
                                    _selectedSpecId = selected ? null : specId),
                                selectedColor: const Color(0xFFF5F3FF),
                                checkmarkColor: const Color(0xFF7C3AED),
                                side: BorderSide(
                                    color: selected
                                        ? const Color(0xFFDDD6FE)
                                        : Color(0xFFD1D5DB)),
                                visualDensity: VisualDensity.compact,
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  fontWeight:
                                      selected ? FontWeight.w600 : FontWeight.w400,
                                  color: selected
                                      ? const Color(0xFF6D28D9)
                                      : const Color(0xFF6B7280),
                                ),
                                padding: EdgeInsets.zero,
                              );
                            },
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),

                    // ── Service rows ──
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.inbox,
                                        size: 64,
                                        color: Color(0xFFD1D5DB)),
                                    const SizedBox(height: 12),
                                    Text('Δεν βρέθηκαν υπηρεσίες',
                                        style: tt.bodyLarge?.copyWith(
                                            color: Color(0xFF6B7280))),
                                  ]))
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: _buildList(filtered),
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

  Widget _buildCard(Map<String, dynamic> svc) {
    final tt = Theme.of(context).textTheme;
    final id = svc['id'] as int;
    final name = svc['name'] ?? '';
    final location = svc['location'] ?? '';
    final status = _statusLabel(svc);
    final sColor = _statusColor(status);
    final enrolledCount = (svc['_count']?['userServices'] ?? 0) as int;
    final st = svc['serviceType'] as Map<String, dynamic>?;
    final visSpecs = st?['specializations'] as List<dynamic>? ?? [];
    final userServices = svc['userServices'] as List<dynamic>? ?? [];
    final isExpanded = _expandedCards.contains(id);
    final requestedCount =
        userServices.where((us) => us['status'] == 'requested').length;
    final description = (svc['description'] ?? '') as String;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shadowColor: Colors.black.withAlpha(12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Color(0xFFE5E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() {
              isExpanded
                  ? _expandedCards.remove(id)
                  : _expandedCards.add(id);
            }),
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(0, 8, 4, 8),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Status accent bar
                    Container(
                      width: 4,
                      color: sColor,
                    ),
                  const SizedBox(width: 12),
                  // Main content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title row
                        Row(
                          children: [
                            Expanded(
                              child: Text(name,
                                  style: tt.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(description,
                              style: tt.bodySmall?.copyWith(
                                  color: const Color(0xFF9CA3AF),
                                  fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                        const SizedBox(height: 4),
                        // Info row — compact single line
                        Row(
                          children: [
                            if (location.isNotEmpty) ...[
                              Icon(Icons.location_on,
                                  size: 11,
                                  color: Color(0xFF6B7280)),
                              const SizedBox(width: 2),
                              Flexible(
                                child: Text(location,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF4B5563)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Icon(Icons.calendar_today,
                                size: 11, color: Color(0xFF6B7280)),
                            const SizedBox(width: 2),
                            Text(_fmtDate(svc['startAt']),
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF4B5563))),
                            const SizedBox(width: 8),
                            const Icon(Icons.people,
                                size: 11,
                                color: Color(0xFFDC2626)),
                            const SizedBox(width: 2),
                            Text('$enrolledCount',
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFDC2626))),
                            if (requestedCount > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: const Color(0xFFF59E0B)),
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
                                        borderRadius:
                                            BorderRadius.circular(4),
                                        border: Border.all(
                                            color:
                                                const Color(0xFFDDD6FE)),
                                      ),
                                      child: Text(
                                          v['specialization']?['name'] ?? '',
                                          style: const TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF6D28D9))),
                                    ),
                                  )),
                              if (visSpecs.length > 2)
                                Text('+${visSpecs.length - 2}',
                                    style: const TextStyle(
                                        fontSize: 9,
                                        color: Color(0xFF6D28D9))),
                            ],
                          ],
                        ),
                        // Responsible user indicator
                        Builder(builder: (_) {
                          final resp = svc['responsibleUser'] as Map<String, dynamic>?;
                          final rName = resp != null
                              ? '${resp['forename'] ?? ''} ${resp['surname'] ?? ''}'.trim()
                              : '';
                          return GestureDetector(
                            onTap: () => _showResponsiblePicker(svc),
                            child: Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                                    resp != null ? Icons.star_rounded : Icons.star_outline_rounded,
                                    size: 11,
                                    color: resp != null ? const Color(0xFF7C3AED) : const Color(0xFF9CA3AF),
                                  ),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      resp != null ? rName : 'Υπεύθυνος',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: resp != null ? const Color(0xFF7C3AED) : const Color(0xFF9CA3AF),
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
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Action buttons — compact column
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Expand toggle
                      InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => setState(() {
                            isExpanded
                                ? _expandedCards.remove(id)
                                : _expandedCards.add(id);
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: isExpanded
                                  ? const Color(0xFFDC2626).withAlpha(20)
                                  : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.people_outline,
                                    size: 14,
                                    color: const Color(0xFFDC2626)),
                                const SizedBox(width: 3),
                                Text('$enrolledCount',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFDC2626))),
                                Icon(
                                  isExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 16,
                                  color: const Color(0xFFDC2626),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.open_in_new,
                                size: 15, color: Color(0xFF6B7280)),
                            onPressed: () => _openDetail(svc),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Λεπτομέρειες',
                            constraints: const BoxConstraints(
                                minWidth: 28, minHeight: 28),
                            padding: EdgeInsets.zero,
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined,
                                size: 16, color: Color(0xFF059669)),
                            onPressed: () => _editService(svc),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Επεξεργασία',
                            constraints: const BoxConstraints(
                                minWidth: 28, minHeight: 28),
                            padding: EdgeInsets.zero,
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                size: 16, color: Color(0xFFF87171)),
                            onPressed: () => _deleteService(id, name),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Διαγραφή',
                            constraints: const BoxConstraints(
                                minWidth: 28, minHeight: 28),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ),
          ),

          // ── Enrollment panel (inside card) ──
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: isExpanded
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

    final acceptedCount = userServices.where((u) => u['status'] == 'accepted').length;
    final requestedCount = userServices.where((u) => u['status'] == 'requested').length;
    final rejectedCount = userServices.where((u) => u['status'] == 'rejected').length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Compact header
          Row(children: [
            Icon(Icons.people, size: 13, color: Color(0xFF4B5563)),
            const SizedBox(width: 4),
            Text('Εγγραφές (${userServices.length})',
                style: tt.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF374151),
                    fontSize: 11)),
            const Spacer(),
            _EnrollBadge('Εγκρ.', acceptedCount, const Color(0xFF059669)),
            const SizedBox(width: 4),
            _EnrollBadge('Εκκρ.', requestedCount, const Color(0xFFF59E0B)),
            const SizedBox(width: 4),
            _EnrollBadge('Απορ.', rejectedCount, const Color(0xFFDC2626)),
          ]),
          const SizedBox(height: 6),

          // User rows — compact single-line
          ...sorted.map((us) {
            final user = us['user'] as Map<String, dynamic>?;
            final userId = us['userId'] as int? ?? user?['id'] as int? ?? 0;
            final uName = user != null
                ? '${user['forename'] ?? ''} ${user['surname'] ?? ''}'.trim()
                : 'Unknown';
            final st = (us['status'] ?? 'requested') as String;
            final stColor = _enrollColor(st);
            final serviceId = svc['id'] as int;

            return Container(
              margin: const EdgeInsets.only(bottom: 3),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: st == 'requested' ? const Color(0xFFFFFBEB) : Colors.white,
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
                    Container(width: 3, height: 28, color: const Color(0xFFF59E0B)),
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
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
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
                    child: Text(
                      st == 'accepted' ? 'Εγκρ.' : st == 'rejected' ? 'Απορ.' : 'Εκκρ.',
                      style: TextStyle(
                          color: stColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Compact icon-only actions
                  if (st != 'accepted')
                    _CompactIconBtn(
                      icon: Icons.check, color: const Color(0xFF059669),
                      tooltip: 'Αποδοχή',
                      onTap: () => _updateEnrollmentStatus(
                          serviceId, userId, 'accepted'),
                    ),
                  if (st != 'rejected')
                    _CompactIconBtn(
                      icon: Icons.close, color: const Color(0xFFDC2626),
                      tooltip: 'Απόρριψη',
                      onTap: () => _updateEnrollmentStatus(
                          serviceId, userId, 'rejected'),
                    ),
                  if (st != 'requested')
                    _CompactIconBtn(
                      icon: Icons.schedule, color: const Color(0xFF6B7280),
                      tooltip: 'Ώρες',
                      onTap: () => _updateEnrollmentHours(
                          serviceId, userId, us),
                    ),
                  _CompactIconBtn(
                    icon: Icons.person_remove_outlined,
                    color: const Color(0xFF9CA3AF),
                    tooltip: 'Αφαίρεση',
                    onTap: () => _removeEnrollment(serviceId, userId, uName),
                  ),
                ],
              ),
            );
          }),
          // ── Direct enroll field ──
          const SizedBox(height: 8),
          Divider(color: Color(0xFFE5E7EB), height: 1),
          const SizedBox(height: 8),
          _buildDirectEnrollField(svc, userServices),
        ],
      ),
    );
  }
}

// ─── Reusable widgets ─────────────────────────────────────


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

class _CompactIconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _CompactIconBtn({
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
