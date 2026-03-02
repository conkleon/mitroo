import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/vehicle_provider.dart';

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<VehicleProvider>().fetchVehicles());
  }

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final typeCtrl = TextEditingController();
    final regCtrl = TextEditingController();
    String meterType = 'km';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('New Vehicle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 12),
              TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: 'Type (car, boat, etc.)')),
              const SizedBox(height: 12),
              TextField(controller: regCtrl, decoration: const InputDecoration(labelText: 'Registration #')),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'km', label: Text('Kilometers')),
                  ButtonSegment(value: 'hours', label: Text('Hours')),
                ],
                selected: {meterType},
                onSelectionChanged: (v) => setSt(() => meterType = v.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final data = <String, dynamic>{
                  'name': nameCtrl.text.trim(),
                  'type': typeCtrl.text.trim(),
                  'meterType': meterType,
                };
                if (regCtrl.text.isNotEmpty) data['registrationNumber'] = regCtrl.text.trim();
                final err = await context.read<VehicleProvider>().create(data);
                if (ctx.mounted) Navigator.pop(ctx);
                if (err != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _vehicleIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'boat':
      case 'ship':
        return Icons.directions_boat;
      case 'truck':
        return Icons.local_shipping;
      case 'motorcycle':
      case 'bike':
        return Icons.two_wheeler;
      case 'bus':
        return Icons.directions_bus;
      default:
        return Icons.directions_car;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final prov = context.watch<VehicleProvider>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final name = auth.displayName.isNotEmpty ? auth.displayName : (auth.user?['ename'] ?? 'User');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => prov.fetchVehicles(),
          child: CustomScrollView(
            slivers: [
              // ── Top bar ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
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
                ),
              ),
              // ── Section header ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(
                    children: [
                      Icon(Icons.directions_car, size: 20, color: cs.primary),
                      const SizedBox(width: 8),
                      Text('Vehicles', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text('${prov.vehicles.length} total', style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
                    ],
                  ),
                ),
              ),
              // ── Vehicle cards ──
              if (prov.loading)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
              else if (prov.vehicles.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.directions_car_outlined, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('No vehicles yet', style: tt.bodyLarge?.copyWith(color: Colors.grey)),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final v = prov.vehicles[i];
                        final dept = v['department'];
                        final meter = v['currentMeter'] ?? 0;
                        final meterType = v['meterType'] ?? 'km';
                        final vehicleType = v['type'] as String?;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {},
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFD97706).withAlpha(20),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(_vehicleIcon(vehicleType), color: const Color(0xFFD97706), size: 22),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(v['name'] ?? '', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                                              if (vehicleType != null && vehicleType.isNotEmpty)
                                                Text(vehicleType, style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
                                            ],
                                          ),
                                        ),
                                        Icon(Icons.chevron_right, color: Colors.grey.shade400),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        if (v['registrationNumber'] != null)
                                          _VehicleChip(
                                            icon: Icons.confirmation_number_outlined,
                                            label: v['registrationNumber'],
                                            color: const Color(0xFF2563EB),
                                          ),
                                        if (v['registrationNumber'] != null) const SizedBox(width: 8),
                                        _VehicleChip(
                                          icon: Icons.speed,
                                          label: '$meter $meterType',
                                          color: const Color(0xFFD97706),
                                        ),
                                        if (dept != null) ...[
                                          const SizedBox(width: 8),
                                          _VehicleChip(
                                            icon: Icons.business_outlined,
                                            label: dept['name'] ?? '',
                                            color: const Color(0xFF059669),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: prov.vehicles.length,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _VehicleChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _VehicleChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
