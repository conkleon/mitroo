import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/department_provider.dart';
import '../providers/service_provider.dart';
import '../providers/item_provider.dart';
import '../providers/vehicle_provider.dart';

// ─── Responsive breakpoints ───────────────────────────────
const double _kCompactWidth = 600;
const double _kMediumWidth = 900;

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      context.read<DepartmentProvider>().fetchDepartments();
      context.read<ServiceProvider>().fetchServices();
      context.read<ItemProvider>().fetchItems();
      context.read<VehicleProvider>().fetchVehicles();
    });
  }

  Future<void> _refresh() async {
    await Future.wait([
      context.read<DepartmentProvider>().fetchDepartments(),
      context.read<ServiceProvider>().fetchServices(),
      context.read<ItemProvider>().fetchItems(),
      context.read<VehicleProvider>().fetchVehicles(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final deptProv = context.watch<DepartmentProvider>();
    final svcProv = context.watch<ServiceProvider>();
    final itemProv = context.watch<ItemProvider>();
    final vehProv = context.watch<VehicleProvider>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final isSysAdmin = auth.isAdmin;
    final isMissionAdmin = auth.isMissionAdmin;
    final isItemAdmin = auth.isItemAdmin;

    // Departments where user has each role (system admin sees all)
    final missionDepts = isSysAdmin
        ? deptProv.departments.cast<Map<String, dynamic>>()
        : auth.missionAdminDepartments;
    final itemDepts = isSysAdmin
        ? deptProv.departments.cast<Map<String, dynamic>>()
        : auth.itemAdminDepartments;

    String subtitle;
    if (isSysAdmin) {
      subtitle = 'Διαχειριστής Συστήματος';
    } else {
      final roles = <String>[];
      if (isMissionAdmin) roles.add('Διαχ. Αποστολών');
      if (isItemAdmin) roles.add('Διαχ. Υλικού');
      subtitle = roles.join(' · ');
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isCompact = width < _kCompactWidth;
            final isWide = width >= _kMediumWidth;
            // Horizontal padding scales with width
            final hPad = isCompact ? 16.0 : (isWide ? 40.0 : 24.0);
            // Max content width on very wide screens
            final contentWidth = math.min(width, 1200.0);

            return RefreshIndicator(
              onRefresh: _refresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(hPad, isCompact ? 12 : 20, hPad, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: contentWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Header ──
                        _HeaderBar(
                          subtitle: subtitle,
                          auth: auth,
                          isCompact: isCompact,
                        ),
                        SizedBox(height: isCompact ? 16 : 28),

                        // ── System Management ──
                        if (isSysAdmin) ...[
                          _SectionHeader(icon: Icons.settings, label: 'Διαχείρηση Συστήματος'),
                          const SizedBox(height: 12),
                          _ResponsiveTileGrid(
                            isWide: isWide,
                            isCompact: isCompact,
                            tiles: [
                              _AdminTileData(
                                icon: Icons.people,
                                iconColor: const Color(0xFF2563EB),
                                bgColor: const Color(0xFFDBEAFE),
                                title: 'Διαχείρηση Χρηστών',
                                subtitle: 'Δημιουργία, επεξεργασία & ανάθεση ρόλων στους χρήστες',
                                onTap: () => context.push('/admin/users'),
                              ),
                              _AdminTileData(
                                icon: Icons.business,
                                iconColor: const Color(0xFF7C3AED),
                                bgColor: const Color(0xFFEDE9FE),
                                title: 'Διαχείρηση Τμημάτων',
                                subtitle: 'Δημιουργία & ρύθμιση τμημάτων',
                                onTap: () => context.push('/admin/departments'),
                              ),
                              _AdminTileData(
                                icon: Icons.school,
                                iconColor: const Color(0xFFD97706),
                                bgColor: const Color(0xFFFEF3C7),
                                title: 'Διαχείρηση Ειδικεύσεων',
                                subtitle: 'Δημιουργία & ανάθεση τύπων ειδικεύσεων',
                                onTap: () => context.push('/admin/specializations'),
                              ),
                            ],
                          ),
                          SizedBox(height: isCompact ? 20 : 28),
                        ],

                        // ── Service Management ──
                        if (isMissionAdmin) ...[
                          _SectionHeader(
                              icon: Icons.miscellaneous_services,
                              label: 'Διαχείρηση Υπηρεσιών'),
                          const SizedBox(height: 12),
                          if (missionDepts.isEmpty)
                            const _EmptyCard(message: 'Κανένα τμήμα ανατεθειμένο')
                          else
                            _ResponsiveTileGrid(
                              isWide: isWide,
                              isCompact: isCompact,
                              tiles: missionDepts.map((dept) {
                                final deptName = dept['name'] ?? 'Department';
                                final deptId = dept['id'] as int;
                                return _AdminTileData(
                                  icon: Icons.miscellaneous_services,
                                  iconColor: const Color(0xFF059669),
                                  bgColor: const Color(0xFFD1FAE5),
                                  title: deptName,
                                  subtitle: 'Προβολή, δημιουργία & διαχείριση υπηρεσιών',
                                  onTap: () => context.push(
                                      '/admin/services?departmentId=$deptId&departmentName=${Uri.encodeComponent(deptName)}'),
                                );
                              }).toList(),
                            ),
                          SizedBox(height: isCompact ? 20 : 28),
                        ],

                        // ── Item & Vehicle Management ──
                        if (isItemAdmin) ...[
                          _SectionHeader(
                              icon: Icons.inventory_2,
                              label: 'Διαχείρηση Υλικού & Οχημάτων'),
                          const SizedBox(height: 12),
                          if (itemDepts.isEmpty)
                            const _EmptyCard(message: 'Κανένα τμήμα ανατεθειμένο')
                          else
                            _ResponsiveTileGrid(
                              isWide: isWide,
                              isCompact: isCompact,
                              tiles: itemDepts.expand((dept) {
                                final deptName = dept['name'] ?? 'Department';
                                return [
                                  _AdminTileData(
                                    icon: Icons.inventory_2,
                                    iconColor: const Color(0xFF7C3AED),
                                    bgColor: const Color(0xFFEDE9FE),
                                    title: '$deptName – Αντικείμενα',
                                    subtitle: 'Διαχείριση εξοπλισμού & κουτιών',
                                    onTap: () => context.go('/items'),
                                  ),
                                  _AdminTileData(
                                    icon: Icons.directions_car,
                                    iconColor: const Color(0xFFD97706),
                                    bgColor: const Color(0xFFFEF3C7),
                                    title: '$deptName – Οχήματα',
                                    subtitle: 'Διαχείριση στόλου & χιλιομέτρων',
                                    onTap: () => context.go('/vehicles'),
                                  ),
                                ];
                              }).toList(),
                            ),
                          SizedBox(height: isCompact ? 20 : 28),
                        ],

                        const SizedBox(height: 60),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Data classes ──────────────────────────────────────────

class _StatData {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String value;
  final String label;
  const _StatData({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.value,
    required this.label,
  });
}

class _AdminTileData {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _AdminTileData({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

// ─── Header ───────────────────────────────────────────────

class _HeaderBar extends StatelessWidget {
  final String subtitle;
  final AuthProvider auth;
  final bool isCompact;

  const _HeaderBar({
    required this.subtitle,
    required this.auth,
    required this.isCompact,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(isCompact ? 8 : 10),
          decoration: BoxDecoration(
            color: cs.primary.withAlpha(25),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.admin_panel_settings,
              color: cs.primary, size: isCompact ? 24 : 28),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Πίνακας Διαχείρισης',
                  style: (isCompact ? tt.titleLarge : tt.headlineSmall)
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: tt.bodySmall
                      ?.copyWith(color: const Color(0xFF6B7280))),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => context.push('/profile'),
          child: CircleAvatar(
            radius: isCompact ? 18 : 20,
            backgroundColor: cs.primary,
            child: Text(
              auth.displayName.isNotEmpty
                  ? auth.displayName[0].toUpperCase()
                  : 'A',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: isCompact ? 14 : 16),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Stats row ────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final bool isCompact;
  final bool isWide;
  final List<_StatData> stats;

  const _StatsRow({
    required this.isCompact,
    required this.isWide,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    final crossCount = isWide ? 4 : (isCompact ? 2 : 4);
    final aspectRatio = isCompact ? 1.3 : (isWide ? 1.6 : 1.5);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: aspectRatio,
      ),
      itemCount: stats.length,
      itemBuilder: (ctx, i) => _StatCard(data: stats[i], isCompact: isCompact),
    );
  }
}

// ─── Responsive tile grid ─────────────────────────────────

class _ResponsiveTileGrid extends StatelessWidget {
  final bool isWide;
  final bool isCompact;
  final List<_AdminTileData> tiles;

  const _ResponsiveTileGrid({
    required this.isWide,
    required this.isCompact,
    required this.tiles,
  });

  @override
  Widget build(BuildContext context) {
    if (isWide) {
      // Desktop: 2‑ or 3‑column grid of cards
      final crossCount = tiles.length <= 2 ? 2 : 3;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossCount,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.6,
        ),
        itemCount: tiles.length,
        itemBuilder: (ctx, i) =>
            _AdminTileCard(data: tiles[i], isCompact: false),
      );
    }

    // Mobile / tablet: stacked list
    return Column(
      children: tiles
          .map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _AdminTileCard(data: t, isCompact: isCompact),
              ))
          .toList(),
    );
  }
}

// ─── Helper widgets ────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: 8),
        Text(label,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _AdminTileCard extends StatefulWidget {
  final _AdminTileData data;
  final bool isCompact;

  const _AdminTileCard({required this.data, required this.isCompact});

  @override
  State<_AdminTileCard> createState() => _AdminTileCardState();
}

class _AdminTileCardState extends State<_AdminTileCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final d = widget.data;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.identity()..scale(_hovering ? 1.01 : 1.0),
        transformAlignment: Alignment.center,
        child: Card(
          elevation: _hovering ? 4 : 1,
          shadowColor: Colors.black.withAlpha(_hovering ? 30 : 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: _hovering ? d.iconColor.withAlpha(60) : Colors.transparent,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: d.onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.isCompact ? 14 : 18,
                vertical: widget.isCompact ? 12 : 16,
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(widget.isCompact ? 8 : 10),
                    decoration: BoxDecoration(
                      color: d.bgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(d.icon,
                        color: d.iconColor,
                        size: widget.isCompact ? 22 : 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(d.title,
                            style: tt.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(d.subtitle,
                            style: tt.bodySmall?.copyWith(
                                color: const Color(0xFF6B7280)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right,
                      color: Colors.grey.shade400, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;
  const _EmptyCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey)),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final _StatData data;
  final bool isCompact;

  const _StatCard({required this.data, required this.isCompact});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final d = data;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: EdgeInsets.all(isCompact ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: d.bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(d.icon, color: d.iconColor, size: 20),
            ),
            const Spacer(),
            Text(d.value,
                style: (isCompact ? tt.titleLarge : tt.headlineMedium)
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(d.label,
                style:
                    tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
          ],
        ),
      ),
    );
  }
}
