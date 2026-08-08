import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/department_provider.dart';

import 'package:mitroo_frontend/theme/theme.dart';

class DepartmentsScreen extends StatefulWidget {
  const DepartmentsScreen({super.key});

  @override
  State<DepartmentsScreen> createState() => _DepartmentsScreenState();
}

class _DepartmentsScreenState extends State<DepartmentsScreen> {
  String _search = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => context.read<DepartmentProvider>().fetchDepartments());
  }

  List<dynamic> _filtered(List<dynamic> depts) {
    if (_search.isEmpty) return depts;
    final q = _search.toLowerCase();
    return depts.where((d) {
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
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Περιγραφή',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: locationCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Τοποθεσία',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () async {
              final data = <String, dynamic>{'name': nameCtrl.text.trim()};
              if (descCtrl.text.isNotEmpty)
                data['description'] = descCtrl.text.trim();
              if (locationCtrl.text.isNotEmpty)
                data['location'] = locationCtrl.text.trim();
              final err = await context.read<DepartmentProvider>().create(data);
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
    final auth = context.watch<AuthProvider>();
    final prov = context.watch<DepartmentProvider>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final name = auth.displayName.isNotEmpty
        ? auth.displayName
        : (auth.user?['eame'] ?? 'User');

    final depts = prov.departments;
    final filtered = _filtered(depts);
    final totalMembers = depts.fold<int>(0, (sum, d) {
      return sum + ((d['_count']?['userDepartments'] ?? 0) as int);
    });

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => prov.fetchDepartments(),
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
                      Text('R.C.D.',
                          style: tt.titleMedium?.copyWith(
                              fontWeight: AppFontWeight.bold,
                              color: cs.primary)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => context.push('/profile'),
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: cs.primary,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'U',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: AppFontWeight.semibold,
                                fontSize: AppFontSize.lg),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Search ──
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Αναζήτηση τμημάτων...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: AppRadius.r12,
                        borderSide: const BorderSide(color: AppColors.gray200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: AppRadius.r12,
                        borderSide: const BorderSide(color: AppColors.gray200),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
              ),

              // ── Stats ──
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      _MiniStat(
                        label: 'Τμήματα',
                        value: '${depts.length}',
                        icon: Icons.business,
                        color: AppColors.violet600,
                      ),
                      const SizedBox(width: 10),
                      _MiniStat(
                        label: 'Μέλη',
                        value: '$totalMembers',
                        icon: Icons.people,
                        color: AppColors.red600,
                      ),
                      const SizedBox(width: 10),
                      _MiniStat(
                        label: 'Εμφαν.',
                        value: '${filtered.length}',
                        icon: Icons.filter_list,
                        color: AppColors.gray500,
                      ),
                    ],
                  ),
                ),
              ),

              // ── Content ──
              if (prov.loading)
                const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()))
              else if (filtered.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      padding: const EdgeInsets.symmetric(
                          vertical: 40, horizontal: 24),
                      decoration: BoxDecoration(
                        color: AppColors.gray50,
                        borderRadius: AppRadius.r20,
                        border: Border.all(color: AppColors.gray200),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.gray100,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.business,
                                size: 32, color: AppColors.gray400),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _search.isNotEmpty
                                ? 'Δεν βρέθηκαν τμήματα'
                                : 'Δεν υπάρχουν τμήματα',
                            style: tt.bodyLarge?.copyWith(
                                color: AppColors.gray500,
                                fontWeight: AppFontWeight.semibold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _search.isNotEmpty
                                ? 'Δοκιμάστε άλλη αναζήτηση'
                                : 'Πατήστε το + για να προσθέσετε',
                            style: tt.bodySmall
                                ?.copyWith(color: AppColors.gray400),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _DeptCard(
                        dept: filtered[i] as Map<String, dynamic>,
                        onTap: () async {
                          await context
                              .push('/admin/departments/${filtered[i]['id']}');
                          if (mounted) prov.fetchDepartments();
                        },
                      ),
                      childCount: filtered.length,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'departments_fab',
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
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
    final location = dept['location'] as String?;
    final description = dept['description'] as String?;
    final subtitle = description != null && description.isNotEmpty
        ? description
        : location ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.r16,
          side: const BorderSide(color: AppColors.gray200),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.violet600, AppColors.violet800],
                        ),
                        borderRadius: AppRadius.r12,
                      ),
                      child: const Icon(Icons.business,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dept['name'] ?? '',
                            style: tt.titleSmall
                                ?.copyWith(fontWeight: AppFontWeight.semibold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              style: tt.bodySmall
                                  ?.copyWith(color: AppColors.gray500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right,
                        size: 20, color: AppColors.gray300),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _DeptChip(
                      icon: Icons.people,
                      label: '$memberCount μέλη',
                      color: AppColors.red600,
                    ),
                    _DeptChip(
                      icon: Icons.miscellaneous_services,
                      label: '$serviceCount υπηρεσίες',
                      color: AppColors.emerald600,
                    ),
                    _DeptChip(
                      icon: Icons.directions_car,
                      label: '$vehicleCount οχήματα',
                      color: AppColors.amber600,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeptChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _DeptChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: AppRadius.r8,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: AppFontSize.base,
                  color: color,
                  fontWeight: AppFontWeight.medium)),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadius.r12,
          border: Border.all(color: AppColors.gray200),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        fontWeight: AppFontWeight.bold,
                        fontSize: AppFontSize.xl,
                        color: color)),
                Text(label,
                    style: const TextStyle(
                        fontSize: AppFontSize.sm, color: AppColors.gray500)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
