import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/department_provider.dart';

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
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final isSysAdmin = auth.isAdmin;
    final adminExpanded = currentPath.startsWith('/admin');

    return Container(
      width: 240,
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // ── App header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Center(
              child: Image.asset('assets/logo.png', height: 72),
            ),
          ),
          const SizedBox(height: 8),

          // ── Navigation items ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                const _SidebarSectionLabel('Κύριο Μενού'),

                _SidebarItem(
                  icon: Icons.miscellaneous_services_outlined,
                  selectedIcon: Icons.miscellaneous_services,
                  label: 'Υπηρεσίες',
                  selected: selectedIndex == 0,
                  onTap: () => context.go('/services'),
                ),
                _SidebarItem(
                  icon: Icons.inventory_2_outlined,
                  selectedIcon: Icons.inventory_2,
                  label: 'Αντικείμενα',
                  selected: selectedIndex == 1,
                  onTap: () => context.go('/items'),
                ),
                _SidebarItem(
                  icon: Icons.directions_car_outlined,
                  selectedIcon: Icons.directions_car,
                  label: 'Οχήματα',
                  selected: selectedIndex == 2,
                  onTap: () => context.go('/vehicles'),
                ),
                _SidebarItem(
                  icon: Icons.chat_bubble_outline,
                  selectedIcon: Icons.chat_bubble,
                  label: 'Συνομιλία',
                  selected: currentPath.startsWith('/chat'),
                  onTap: () => context.go('/chat'),
                ),

                if (showAdmin) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: _SidebarSectionLabel('Διαχείριση'),
                  ),

                  _SidebarItem(
                    icon: Icons.admin_panel_settings_outlined,
                    selectedIcon: Icons.admin_panel_settings,
                    label: 'Πίνακας Ελέγχου',
                    selected: currentPath == '/admin',
                    onTap: () => context.go('/admin'),
                  ),

                  if (isSysAdmin) ...[
                    _SidebarItem(
                      icon: Icons.people_outline,
                      selectedIcon: Icons.people,
                      label: 'Χρήστες',
                      selected: currentPath.startsWith('/admin/users'),
                      onTap: () => context.push('/admin/users'),
                      indent: true,
                    ),
                    _SidebarItem(
                      icon: Icons.business_outlined,
                      selectedIcon: Icons.business,
                      label: 'Τμήματα',
                      selected: currentPath.startsWith('/admin/departments'),
                      onTap: () => context.push('/admin/departments'),
                      indent: true,
                    ),
                    _SidebarItem(
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
                      child: _SidebarSectionLabel('Διαχείριση Υπηρεσιών'),
                    ),
                    ..._buildDeptServiceItems(context, isSysAdmin),
                  ],
                ],
              ],
            ),
          ),

          // ── Profile footer ──
          const Divider(height: 1),
          InkWell(
            onTap: () => context.push('/profile'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: cs.primary,
                    child: Text(
                      auth.displayName.isNotEmpty
                          ? auth.displayName[0].toUpperCase()
                          : 'U',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.displayName.isNotEmpty ? auth.displayName : 'Χρήστης',
                          style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          auth.isAdmin ? 'Διαχειριστής' : 'Μέλος',
                          style: tt.labelSmall?.copyWith(color: const Color(0xFF9CA3AF)),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 16, color: Color(0xFFD1D5DB)),
                ],
              ),
            ),
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
        const Padding(
          padding: EdgeInsets.only(left: 24, top: 4, bottom: 4),
          child: Text('Κανένα τμήμα', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
        ),
      ];
    }

    return depts.map((dept) {
      final deptName = dept['name'] ?? 'Τμήμα';
      final deptId = dept['id'] as int;
      final path = '/admin/services?departmentId=$deptId&departmentName=${Uri.encodeComponent(deptName)}';
      // Check if this department's services page is currently active
      final isActive = currentUri.contains('departmentId=$deptId');

      return _SidebarItem(
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
// Sidebar helper widgets
// ═══════════════════════════════════════════════════════════

class _SidebarSectionLabel extends StatelessWidget {
  final String label;
  const _SidebarSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Color(0xFF9CA3AF),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool indent;

  const _SidebarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.indent = false,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    const activeColor = Color(0xFF2563EB);
    final bgColor = selected
        ? activeColor.withAlpha(20)
        : _hovering
            ? const Color(0xFFEEF0F4)
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                selected ? widget.selectedIcon : widget.icon,
                size: widget.indent ? 18 : 20,
                color: selected ? activeColor : const Color(0xFF6B7280),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: widget.indent ? 13 : 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? activeColor : const Color(0xFF374151),
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
