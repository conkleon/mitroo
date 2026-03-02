import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/department_provider.dart';
import '../providers/service_provider.dart';
import '../providers/item_provider.dart';
import '../providers/vehicle_provider.dart';
import '../providers/auth_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
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

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
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
    final name = auth.displayName.isNotEmpty
        ? auth.displayName
        : (auth.user?['ename'] ?? 'User');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              // ── Top bar ──
              Row(
                children: [
                  Image.asset('assets/logo.png', height: 32),
                  const SizedBox(width: 10),
                  Text('Mitroo', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: cs.primary)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => context.push('/profile'),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: cs.primary,
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'U',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Greeting ──
              Text(_greeting(), style: tt.bodyMedium?.copyWith(color: const Color(0xFF6B7280))),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(name, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: Icon(Icons.refresh, color: cs.primary),
                    onPressed: _refresh,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Stat cards grid (2-column like the reference) ──
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

              // ── Recent Services Section ──
              Row(
                children: [
                  Icon(Icons.miscellaneous_services, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('Recent Services', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('${svcProv.services.length} total',
                      style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
                ],
              ),
              const SizedBox(height: 12),
              if (svcProv.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (svcProv.services.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text('No services yet', style: tt.bodyMedium?.copyWith(color: Colors.grey)),
                    ),
                  ),
                )
              else
                ...svcProv.services.take(5).map((svc) {
                  final dept = svc['department'];
                  final enrolled = svc['_count']?['userServices'] ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: cs.primary.withAlpha(20),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.miscellaneous_services, color: cs.primary, size: 20),
                        ),
                        title: Text(svc['name'] ?? '', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${dept?['name'] ?? ''} · $enrolled enrolled',
                          style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
                        ),
                        trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 80),
            ],
          ),
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
