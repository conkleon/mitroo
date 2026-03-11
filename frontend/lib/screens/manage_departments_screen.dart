import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/department_provider.dart';
import '../services/api_client.dart';

/// Professional department list with search, stats, grid/list layout.
class ManageDepartmentsScreen extends StatefulWidget {
  const ManageDepartmentsScreen({super.key});

  @override
  State<ManageDepartmentsScreen> createState() =>
      _ManageDepartmentsScreenState();
}

class _ManageDepartmentsScreenState extends State<ManageDepartmentsScreen> {
  String _search = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => context.read<DepartmentProvider>().fetchDepartments());
  }

  List<dynamic> get _filtered {
    final all = context.read<DepartmentProvider>().departments;
    if (_search.isEmpty) return all;
    final q = _search.toLowerCase();
    return all.where((d) {
      final name = (d['name'] ?? '').toString().toLowerCase();
      final loc = (d['location'] ?? '').toString().toLowerCase();
      return name.contains(q) || loc.contains(q);
    }).toList();
  }

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final locationCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Νέο Τμήμα'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Όνομα *',
                        border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Περιγραφή',
                        border: OutlineInputBorder()),
                    maxLines: 2),
                const SizedBox(height: 12),
                TextField(
                    controller: locationCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Τοποθεσία',
                        border: OutlineInputBorder())),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () async {
              final data = <String, dynamic>{'name': nameCtrl.text.trim()};
              if (descCtrl.text.isNotEmpty) {
                data['description'] = descCtrl.text.trim();
              }
              if (locationCtrl.text.isNotEmpty) {
                data['location'] = locationCtrl.text.trim();
              }
              final err =
                  await context.read<DepartmentProvider>().create(data);
              if (ctx.mounted) Navigator.pop(ctx);
              if (err != null && mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(err)));
              }
            },
            child: const Text('Δημιουργία'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final prov = context.watch<DepartmentProvider>();
    final filtered = _filtered;

    final totalMembers = prov.departments.fold<int>(0, (sum, d) {
      return sum + ((d['_count']?['userDepartments'] ?? 0) as int);
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text('Διαχείριση Τμημάτων',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => prov.fetchDepartments(),
            tooltip: 'Ανανέωση',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text('Νέο Τμήμα'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            final hPad = isWide ? 32.0 : 16.0;

            return Column(
              children: [
                // ── Search ──
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: hPad, vertical: 12),
                  child: TextField(
                    decoration: InputDecoration(
                    hintText: 'Αναζήτηση τμημάτων...',
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

                // ── Stats ──
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  child: Row(
                    children: [
                      _MiniStat(
                          label: 'Τμήματα',
                          value: '${prov.departments.length}',
                          icon: Icons.business,
                          color: const Color(0xFF7C3AED)),
                      const SizedBox(width: 12),
                      _MiniStat(
                          label: 'Μέλη',
                          value: '$totalMembers',
                          icon: Icons.people,
                          color: const Color(0xFFDC2626)),
                      const SizedBox(width: 12),
                      _MiniStat(
                          label: 'Εμφαν.',
                          value: '${filtered.length}',
                          icon: Icons.filter_list,
                          color: const Color(0xFF6B7280)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // ── List / Grid ──
                Expanded(
                  child: prov.loading
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.business,
                                      size: 64,
                                      color: Colors.grey.shade300),
                                  const SizedBox(height: 12),
                                  Text('Δεν βρέθηκαν τμήματα',
                                      style: tt.bodyLarge?.copyWith(
                                          color: Colors.grey.shade500)),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: () => prov.fetchDepartments(),
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

  Widget _buildList(List<dynamic> depts) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
      itemCount: depts.length,
      itemBuilder: (context, i) => _DeptCard(
        dept: depts[i] as Map<String, dynamic>,
        onTap: () async {
          await context.push('/admin/departments/${depts[i]['id']}');
          if (mounted) context.read<DepartmentProvider>().fetchDepartments();
        },
      ),
    );
  }

  Widget _buildGrid(List<dynamic> depts) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 90),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 12,
        childAspectRatio: 3.0,
      ),
      itemCount: depts.length,
      itemBuilder: (context, i) => _DeptCard(
        dept: depts[i] as Map<String, dynamic>,
        onTap: () async {
          await context.push('/admin/departments/${depts[i]['id']}');
          if (mounted) context.read<DepartmentProvider>().fetchDepartments();
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
class _DeptCard extends StatelessWidget {
  final Map<String, dynamic> dept;
  final VoidCallback onTap;
  const _DeptCard({required this.dept, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final counts = dept['_count'] as Map<String, dynamic>? ?? {};
    final memberCount = counts['userDepartments'] ?? 0;
    final serviceCount = counts['services'] ?? 0;
    final vehicleCount = counts['vehicles'] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE9FE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.business,
                    color: Color(0xFF7C3AED), size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dept['name'] ?? '',
                        style: tt.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      children: [
                        _CountBadge(
                            icon: Icons.people,
                            count: memberCount,
                            color: const Color(0xFFDC2626)),
                        _CountBadge(
                            icon: Icons.miscellaneous_services,
                            count: serviceCount,
                            color: const Color(0xFF059669)),
                        _CountBadge(
                            icon: Icons.directions_car,
                            count: vehicleCount,
                            color: const Color(0xFFD97706)),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: Colors.grey.shade400, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color color;
  const _CountBadge(
      {required this.icon, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text('$count',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color)),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MiniStat(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: color)),
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6B7280))),
              ]),
        ]),
      ),
    );
  }
}
