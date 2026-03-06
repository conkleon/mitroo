import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/service_provider.dart';
import '../services/api_client.dart';

/// Lists all services for a given department.
/// Mission admins can view details, create new, edit, and delete services.
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
  String _statusFilter = 'all'; // all, upcoming, past, active

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
      final res =
          await _api.get('/services?departmentId=${widget.departmentId}');
      if (res.statusCode == 200 && mounted) {
        _services = jsonDecode(res.body);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<dynamic> get _filtered {
    var list = List<dynamic>.from(_services);
    final now = DateTime.now();

    // Status filter
    if (_statusFilter == 'upcoming') {
      list = list.where((s) {
        final start = DateTime.tryParse(s['startAt'] ?? '');
        return start != null && start.isAfter(now);
      }).toList();
    } else if (_statusFilter == 'active') {
      list = list.where((s) {
        final start = DateTime.tryParse(s['startAt'] ?? '');
        final end = DateTime.tryParse(s['endAt'] ?? '');
        return start != null &&
            start.isBefore(now) &&
            (end == null || end.isAfter(now));
      }).toList();
    } else if (_statusFilter == 'past') {
      list = list.where((s) {
        final end = DateTime.tryParse(s['endAt'] ?? '');
        return end != null && end.isBefore(now);
      }).toList();
    }

    // Text search
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((s) {
        final name = (s['name'] ?? '').toString().toLowerCase();
        final loc = (s['location'] ?? '').toString().toLowerCase();
        final carrier = (s['carrier'] ?? '').toString().toLowerCase();
        return name.contains(q) || loc.contains(q) || carrier.contains(q);
      }).toList();
    }

    return list;
  }

  Future<void> _deleteService(int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Service'),
        content: Text('Are you sure you want to delete "$name"?\nThis cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
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
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service deleted')));
      _load();
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '—';
    final local = dt.toLocal();
    return '${local.day}/${local.month}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _serviceStatusLabel(Map<String, dynamic> svc) {
    final now = DateTime.now();
    final start = DateTime.tryParse(svc['startAt'] ?? '');
    final end = DateTime.tryParse(svc['endAt'] ?? '');
    if (start == null) return 'No date';
    if (start.isAfter(now)) return 'Upcoming';
    if (end != null && end.isBefore(now)) return 'Completed';
    return 'Active';
  }

  Color _serviceStatusColor(String status) {
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

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push(
              '/admin/services/create?departmentId=${widget.departmentId}&departmentName=${Uri.encodeComponent(widget.departmentName)}');
          if (mounted) _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('New Service'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 800;

            return Column(
              children: [
                // ── Search & Filters ──
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isWide ? 32 : 16, vertical: 12),
                  child: Column(
                    children: [
                      // Search bar
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search services...',
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
                      const SizedBox(height: 12),
                      // Filter chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _FilterChip(
                              label: 'All',
                              selected: _statusFilter == 'all',
                              onTap: () =>
                                  setState(() => _statusFilter = 'all'),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'Upcoming',
                              selected: _statusFilter == 'upcoming',
                              onTap: () =>
                                  setState(() => _statusFilter = 'upcoming'),
                              color: const Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'Active',
                              selected: _statusFilter == 'active',
                              onTap: () =>
                                  setState(() => _statusFilter = 'active'),
                              color: const Color(0xFF059669),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'Past',
                              selected: _statusFilter == 'past',
                              onTap: () =>
                                  setState(() => _statusFilter = 'past'),
                              color: const Color(0xFF6B7280),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Stats summary ──
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: isWide ? 32 : 16),
                  child: _StatsSummary(
                    total: _services.length,
                    upcoming: _services.where((s) {
                      final start = DateTime.tryParse(s['startAt'] ?? '');
                      return start != null && start.isAfter(DateTime.now());
                    }).length,
                    totalEnrolled: _services.fold<int>(0, (sum, s) {
                      final count = s['_count']?['userServices'] ?? 0;
                      return sum + (count as int);
                    }),
                  ),
                ),
                const SizedBox(height: 8),

                // ── Service list ──
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.inbox,
                                      size: 64, color: Colors.grey.shade300),
                                  const SizedBox(height: 12),
                                  Text('No services found',
                                      style: tt.bodyLarge?.copyWith(
                                          color: Colors.grey.shade500)),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: isWide
                                  ? _buildGrid(filtered)
                                  : _buildList(filtered),
                            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(List<dynamic> services) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
      itemCount: services.length,
      itemBuilder: (ctx, i) => _ServiceCard(
        service: services[i],
        formatDate: _formatDate,
        statusLabel: _serviceStatusLabel,
        statusColor: _serviceStatusColor,
        onTap: () => _openDetail(services[i]),
        onEdit: () => _editService(services[i]),
        onDelete: () => _deleteService(
            services[i]['id'] as int, services[i]['name'] ?? ''),
      ),
    );
  }

  Widget _buildGrid(List<dynamic> services) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 80),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2.2,
      ),
      itemCount: services.length,
      itemBuilder: (ctx, i) => _ServiceCard(
        service: services[i],
        formatDate: _formatDate,
        statusLabel: _serviceStatusLabel,
        statusColor: _serviceStatusColor,
        onTap: () => _openDetail(services[i]),
        onEdit: () => _editService(services[i]),
        onDelete: () => _deleteService(
            services[i]['id'] as int, services[i]['name'] ?? ''),
      ),
    );
  }

  void _openDetail(Map<String, dynamic> service) {
    context.push('/admin/services/${service['id']}');
  }

  void _editService(Map<String, dynamic> service) async {
    final id = service['id'] as int;
    await context.push(
        '/admin/services/$id/edit?departmentId=${widget.departmentId}&departmentName=${Uri.encodeComponent(widget.departmentName)}');
    if (mounted) _load();
  }
}

// ─── Stats summary bar ─────────────────────────────────────

class _StatsSummary extends StatelessWidget {
  final int total;
  final int upcoming;
  final int totalEnrolled;

  const _StatsSummary({
    required this.total,
    required this.upcoming,
    required this.totalEnrolled,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        _MiniStat(
            icon: Icons.list_alt,
            value: '$total',
            label: 'Total',
            color: const Color(0xFF2563EB)),
        const SizedBox(width: 8),
        _MiniStat(
            icon: Icons.schedule,
            value: '$upcoming',
            label: 'Upcoming',
            color: const Color(0xFF7C3AED)),
        const SizedBox(width: 8),
        _MiniStat(
            icon: Icons.people,
            value: '$totalEnrolled',
            label: 'Enrolled',
            color: const Color(0xFF059669)),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(40)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: tt.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700, color: color)),
                Text(label,
                    style: tt.bodySmall
                        ?.copyWith(color: const Color(0xFF6B7280), fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Filter chip ──────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.withAlpha(20) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? c : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? c : const Color(0xFF6B7280),
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ─── Service card ─────────────────────────────────────────

class _ServiceCard extends StatelessWidget {
  final Map<String, dynamic> service;
  final String Function(String?) formatDate;
  final String Function(Map<String, dynamic>) statusLabel;
  final Color Function(String) statusColor;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ServiceCard({
    required this.service,
    required this.formatDate,
    required this.statusLabel,
    required this.statusColor,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final name = service['name'] ?? '';
    final location = service['location'] ?? '';
    final carrier = service['carrier'] ?? '';
    final status = statusLabel(service);
    final sColor = statusColor(status);
    final enrolledCount = service['_count']?['userServices'] ?? 0;
    final visSpecs = service['visibility'] as List<dynamic>? ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: name + status badge
              Row(
                children: [
                  Expanded(
                    child: Text(name,
                        style: tt.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: sColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(status,
                        style: TextStyle(
                            color: sColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Info chips
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (location.isNotEmpty)
                    _InfoChip(
                        icon: Icons.location_on, text: location, size: 12),
                  if (carrier.isNotEmpty)
                    _InfoChip(icon: Icons.groups, text: carrier, size: 12),
                  _InfoChip(
                      icon: Icons.people,
                      text: '$enrolledCount enrolled',
                      size: 12),
                  _InfoChip(
                    icon: Icons.calendar_today,
                    text: formatDate(service['startAt']),
                    size: 12,
                  ),
                ],
              ),
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
              const SizedBox(height: 8),
              // Action row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('View', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Edit', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: Icon(Icons.delete, size: 16, color: Colors.red.shade400),
                    label: Text('Delete',
                        style:
                            TextStyle(fontSize: 12, color: Colors.red.shade400)),
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final double size;

  const _InfoChip(
      {required this.icon, required this.text, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: size, color: const Color(0xFF6B7280)),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                fontSize: size, color: const Color(0xFF6B7280))),
      ],
    );
  }
}
