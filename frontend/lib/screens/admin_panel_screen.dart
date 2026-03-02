import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/department_provider.dart';
import '../providers/service_provider.dart';
import '../providers/item_provider.dart';
import '../providers/vehicle_provider.dart';

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
      subtitle = 'System Administrator';
    } else {
      final roles = <String>[];
      if (isMissionAdmin) roles.add('Mission Admin');
      if (isItemAdmin) roles.add('Item Admin');
      subtitle = roles.join(' · ');
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              // ── Header ──
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primary.withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.admin_panel_settings, color: cs.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Admin Panel',
                            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        Text(subtitle,
                            style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.push('/profile'),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: cs.primary,
                      child: Text(
                        auth.displayName.isNotEmpty ? auth.displayName[0].toUpperCase() : 'A',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Stats (system admin only) ──
              if (isSysAdmin) ...[
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.55,
                  children: [
                    _StatCard(
                      icon: Icons.business_rounded,
                      iconColor: const Color(0xFF2563EB),
                      bgColor: const Color(0xFFDBEAFE),
                      value: '${deptProv.departments.length}',
                      label: 'Departments',
                    ),
                    _StatCard(
                      icon: Icons.miscellaneous_services_rounded,
                      iconColor: const Color(0xFF059669),
                      bgColor: const Color(0xFFD1FAE5),
                      value: '${svcProv.services.length}',
                      label: 'Services',
                    ),
                    _StatCard(
                      icon: Icons.inventory_2_rounded,
                      iconColor: const Color(0xFF7C3AED),
                      bgColor: const Color(0xFFEDE9FE),
                      value: '${itemProv.items.length}',
                      label: 'Items',
                    ),
                    _StatCard(
                      icon: Icons.directions_car_rounded,
                      iconColor: const Color(0xFFD97706),
                      bgColor: const Color(0xFFFEF3C7),
                      value: '${vehProv.vehicles.length}',
                      label: 'Vehicles',
                    ),
                  ],
                ),
                const SizedBox(height: 28),
              ],

              // ════════════════════════════════════════════════
              // SYSTEM ADMIN – full management section
              // ════════════════════════════════════════════════
              if (isSysAdmin) ...[
                _SectionHeader(icon: Icons.settings, label: 'System Management'),
                const SizedBox(height: 12),
                _AdminTile(
                  icon: Icons.people,
                  iconColor: const Color(0xFF2563EB),
                  bgColor: const Color(0xFFDBEAFE),
                  title: 'Manage Users',
                  subtitle: 'Create, edit & assign roles to users',
                  onTap: () => context.push('/admin/users'),
                ),
                const SizedBox(height: 8),
                _AdminTile(
                  icon: Icons.business,
                  iconColor: const Color(0xFF7C3AED),
                  bgColor: const Color(0xFFEDE9FE),
                  title: 'Manage Departments',
                  subtitle: 'Create & configure departments',
                  onTap: () => context.push('/admin/departments'),
                ),
                const SizedBox(height: 8),
                _AdminTile(
                  icon: Icons.school,
                  iconColor: const Color(0xFFD97706),
                  bgColor: const Color(0xFFFEF3C7),
                  title: 'Manage Specializations',
                  subtitle: 'Create & assign specialization types',
                  onTap: () => context.push('/admin/specializations'),
                ),
                const SizedBox(height: 24),
              ],

              // ════════════════════════════════════════════════
              // MISSION ADMIN – service creation per department
              // ════════════════════════════════════════════════
              if (isMissionAdmin) ...[
                _SectionHeader(icon: Icons.miscellaneous_services, label: 'Service Management'),
                const SizedBox(height: 12),
                if (missionDepts.isEmpty)
                  const _EmptyCard(message: 'No departments assigned')
                else
                  ...missionDepts.map((dept) {
                    final deptName = dept['name'] ?? 'Department';
                    final deptId = dept['id'] as int;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _AdminTile(
                        icon: Icons.add_circle_outline,
                        iconColor: const Color(0xFF059669),
                        bgColor: const Color(0xFFD1FAE5),
                        title: deptName,
                        subtitle: 'Create & manage services',
                        onTap: () => context.push('/admin/services/create?departmentId=$deptId&departmentName=${Uri.encodeComponent(deptName)}'),
                      ),
                    );
                  }),
                const SizedBox(height: 24),
              ],

              // ════════════════════════════════════════════════
              // ITEM ADMIN – item & vehicle management
              // ════════════════════════════════════════════════
              if (isItemAdmin) ...[
                _SectionHeader(icon: Icons.inventory_2, label: 'Item & Vehicle Management'),
                const SizedBox(height: 12),
                if (itemDepts.isEmpty)
                  const _EmptyCard(message: 'No departments assigned')
                else
                  ...itemDepts.map((dept) {
                    final deptName = dept['name'] ?? 'Department';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        children: [
                          _AdminTile(
                            icon: Icons.inventory_2,
                            iconColor: const Color(0xFF7C3AED),
                            bgColor: const Color(0xFFEDE9FE),
                            title: '$deptName – Items',
                            subtitle: 'Manage equipment & containers',
                            onTap: () => context.go('/items'),
                          ),
                          const SizedBox(height: 8),
                          _AdminTile(
                            icon: Icons.directions_car,
                            iconColor: const Color(0xFFD97706),
                            bgColor: const Color(0xFFFEF3C7),
                            title: '$deptName – Vehicles',
                            subtitle: 'Manage fleet & mileage logs',
                            onTap: () => context.go('/vehicles'),
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 24),
              ],

              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
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
        Text(label, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _AdminTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AdminTile({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(title, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
        trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
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
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const Spacer(),
            Text(value, style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label, style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
          ],
        ),
      ),
    );
  }
}
