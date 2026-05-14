import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/department_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;

/// Responsive shell: bottom nav on mobile, sidebar on desktop (≥900px).
class ShellScreen extends StatelessWidget {
  final Widget child;
  const ShellScreen({super.key, required this.child});

  static const double _kDesktopBreakpoint = 900;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final showAdmin = auth.canAccessAdminPanel;

    final mainPaths = ['/services', '/items', '/vehicles', if (showAdmin) '/admin', '/chat'];

    final location = GoRouterState.of(context).matchedLocation;
    final fullUri = GoRouterState.of(context).uri.toString();
    int idx = mainPaths.indexWhere((p) => location.startsWith(p));
    if (idx == -1) idx = 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _kDesktopBreakpoint;

        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                _DesktopSidebar(
                  auth: auth,
                  showAdmin: showAdmin,
                  currentPath: location,
                  currentUri: fullUri,
                  selectedIndex: idx,
                  mainPaths: mainPaths,
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: child),
              ],
            ),
          );
        }

        // Mobile: bottom nav
        return Scaffold(
          body: child,
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(13),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: NavigationBar(
                selectedIndex: idx,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
                onDestinationSelected: (i) => context.go(mainPaths[i]),
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.miscellaneous_services_outlined),
                    selectedIcon: Icon(Icons.miscellaneous_services),
                    label: 'Υπηρεσίες',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.inventory_2_outlined),
                    selectedIcon: Icon(Icons.inventory_2),
                    label: 'Αντικείμενα',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.directions_car_outlined),
                    selectedIcon: Icon(Icons.directions_car),
                    label: 'Οχήματα',
                  ),
                  if (showAdmin)
                    const NavigationDestination(
                      icon: Icon(Icons.admin_panel_settings_outlined),
                      selectedIcon: Icon(Icons.admin_panel_settings),
                      label: 'Διαχείριση',
                    ),
                  const NavigationDestination(
                    icon: Icon(Icons.chat_bubble_outline),
                    selectedIcon: Icon(Icons.chat_bubble),
                    label: 'Συνομιλία',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Desktop sidebar
// ═══════════════════════════════════════════════════════════

class _DesktopSidebar extends StatelessWidget {
  final AuthProvider auth;
  final bool showAdmin;
  final String currentPath;
  final String currentUri;
  final int selectedIndex;
  final List<String> mainPaths;

  const _DesktopSidebar({
    required this.auth,
    required this.showAdmin,
    required this.currentPath,
    required this.currentUri,
    required this.selectedIndex,
    required this.mainPaths,
  });

  @override
  Widget build(BuildContext context) {
    final isSysAdmin = auth.isAdmin;

    return Container(
      width: 240,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6B0000), Color(0xFFC62828), Color(0xFFD84315)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _CrossGridPainter())),
          // Diagonal accent stripe
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: Container(color: Colors.white.withAlpha(25)),
          ),
          Column(
            children: [
              // ── App header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
                child: Row(
                  children: [
                    Image.asset('assets/logo.png', height: 44),
                    const SizedBox(width: 10),
                    Text(
                      'R.C.D.',
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // ── Navigation items ──
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: [
                    const _SidebarBrandSectionLabel('Κύριο Μενού'),
                    _BrandSidebarItem(
                      icon: Icons.miscellaneous_services_outlined,
                      selectedIcon: Icons.miscellaneous_services,
                      label: 'Υπηρεσίες',
                      selected: selectedIndex == 0,
                      onTap: () => context.go('/services'),
                    ),
                    _BrandSidebarItem(
                      icon: Icons.inventory_2_outlined,
                      selectedIcon: Icons.inventory_2,
                      label: 'Αντικείμενα',
                      selected: selectedIndex == 1,
                      onTap: () => context.go('/items'),
                    ),
                    _BrandSidebarItem(
                      icon: Icons.directions_car_outlined,
                      selectedIcon: Icons.directions_car,
                      label: 'Οχήματα',
                      selected: selectedIndex == 2,
                      onTap: () => context.go('/vehicles'),
                    ),
                    _BrandSidebarItem(
                      icon: Icons.chat_bubble_outline,
                      selectedIcon: Icons.chat_bubble,
                      label: 'Συνομιλία',
                      selected: currentPath.startsWith('/chat'),
                      onTap: () => context.go('/chat'),
                    ),
                    if (showAdmin) ...[
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: _SidebarBrandSectionLabel('Διαχείριση'),
                      ),
                      _BrandSidebarItem(
                        icon: Icons.admin_panel_settings_outlined,
                        selectedIcon: Icons.admin_panel_settings,
                        label: 'Πίνακας Ελέγχου',
                        selected: currentPath == '/admin',
                        onTap: () => context.go('/admin'),
                      ),
                      if (isSysAdmin) ...[
                        _BrandSidebarItem(
                          icon: Icons.people_outline,
                          selectedIcon: Icons.people,
                          label: 'Χρήστες',
                          selected: currentPath.startsWith('/admin/users'),
                          onTap: () => context.push('/admin/users'),
                          indent: true,
                        ),
                        _BrandSidebarItem(
                          icon: Icons.business_outlined,
                          selectedIcon: Icons.business,
                          label: 'Τμήματα',
                          selected: currentPath.startsWith('/admin/departments'),
                          onTap: () => context.push('/admin/departments'),
                          indent: true,
                        ),
                        _BrandSidebarItem(
                          icon: Icons.school_outlined,
                          selectedIcon: Icons.school,
                          label: 'Ειδικότητες',
                          selected: currentPath.startsWith('/admin/specializations'),
                          onTap: () => context.push('/admin/specializations'),
                          indent: true,
                        ),
                      ],
                      if (auth.isMissionAdmin || isSysAdmin) ...[
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: _SidebarBrandSectionLabel('Διαχείριση Υπηρεσιών'),
                        ),
                        ..._buildDeptServiceItems(context, isSysAdmin),
                      ],
                    ],
                  ],
                ),
              ),
              // ── Profile footer (glass style) ──
              Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  onTap: () => context.push('/profile'),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 15,
                          backgroundColor: Colors.white.withAlpha(40),
                          child: Text(
                            auth.displayName.isNotEmpty
                                ? auth.displayName[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                auth.displayName.isNotEmpty ? auth.displayName : 'Χρήστης',
                                style: GoogleFonts.spaceGrotesk(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                auth.isAdmin ? 'Διαχειριστής' : 'Εθελοντής',
                                style: GoogleFonts.spaceGrotesk(
                                  color: Colors.white.withAlpha(150),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 16, color: Colors.white54),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDeptServiceItems(BuildContext context, bool isSysAdmin) {
    List<Map<String, dynamic>> depts;
    if (isSysAdmin) {
      final deptProv = context.watch<DepartmentProvider>();
      if (deptProv.departments.isEmpty && !deptProv.loading) {
        // Trigger fetch if not yet loaded
        Future.microtask(() => deptProv.fetchDepartments());
      }
      depts = deptProv.departments.cast<Map<String, dynamic>>();
    } else {
      depts = auth.missionAdminDepartments;
    }

    if (depts.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(left: 24, top: 4, bottom: 4),
          child: Text('Κανένα τμήμα', style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(120))),
        ),
      ];
    }

    return depts.map((dept) {
      final deptName = dept['name'] ?? 'Τμήμα';
      final deptId = dept['id'] as int;
      final path = '/admin/services?departmentId=$deptId&departmentName=${Uri.encodeComponent(deptName)}';
      // Check if this department's services page is currently active
      final isActive = currentUri.contains('departmentId=$deptId');

      return _BrandSidebarItem(
        icon: Icons.folder_outlined,
        selectedIcon: Icons.folder,
        label: deptName,
        selected: isActive,
        onTap: () => context.go(path),
        indent: true,
      );
    }).toList();
  }
}

// ═══════════════════════════════════════════════════════════
// Brand sidebar helper widgets
// ═══════════════════════════════════════════════════════════

class _SidebarBrandSectionLabel extends StatelessWidget {
  final String label;
  const _SidebarBrandSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 4),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.spaceGrotesk(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: Colors.white.withAlpha(120),
        ),
      ),
    );
  }
}

class _BrandSidebarItem extends StatefulWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool indent;

  const _BrandSidebarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.indent = false,
  });

  @override
  State<_BrandSidebarItem> createState() => _BrandSidebarItemState();
}

class _BrandSidebarItemState extends State<_BrandSidebarItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final bgColor = selected
        ? Colors.white.withAlpha(30)
        : _hovering
            ? Colors.white.withAlpha(12)
            : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: EdgeInsets.only(
            bottom: 2,
            left: widget.indent ? 12 : 0,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                widget.selected ? widget.selectedIcon : widget.icon,
                size: widget.indent ? 18 : 20,
                color: selected ? Colors.white : Colors.white.withAlpha(160),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: widget.indent ? 13 : 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? Colors.white : Colors.white.withAlpha(200),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Cross grid pattern painter (reused from login screen)
// ═══════════════════════════════════════════════════════════

class _CrossGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(14)
      ..style = PaintingStyle.fill;

    void drawCross(double cx, double cy, double s, double angle) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);
      final arm = s * 0.28;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: s, height: arm),
          const Radius.circular(3),
        ),
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: arm, height: s),
          const Radius.circular(3),
        ),
        paint,
      );
      canvas.restore();
    }

    drawCross(size.width * 0.78, size.height * 0.12, 80, 0);
    drawCross(size.width * 0.12, size.height * 0.22, 45, math.pi / 12);
    drawCross(size.width * 0.65, size.height * 0.72, 110, math.pi / 8);
    drawCross(size.width * 0.35, size.height * 0.88, 50, 0);
    drawCross(size.width * 0.88, size.height * 0.52, 40, math.pi / 6);
    drawCross(size.width * 0.20, size.height * 0.58, 60, -math.pi / 10);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
