import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/department_provider.dart';

import 'package:mitroo_frontend/theme/theme.dart';

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
    Future.microtask(() {
      if (mounted) context.read<DepartmentProvider>().fetchDepartments();
    });
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
                        labelText: 'Όνομα *', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Περιγραφή', border: OutlineInputBorder()),
                    maxLines: 2),
                const SizedBox(height: 12),
                TextField(
                    controller: locationCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Τοποθεσία', border: OutlineInputBorder())),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () async {
              final data = <String, dynamic>{'name': nameCtrl.text.trim()};
              if (descCtrl.text.isNotEmpty) {
                data['description'] = descCtrl.text.trim();
              }
              if (locationCtrl.text.isNotEmpty) {
                data['location'] = locationCtrl.text.trim();
              }
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
    final tt = Theme.of(context).textTheme;
    final prov = context.watch<DepartmentProvider>();
    final filtered = _filtered;

    final totalMembers = prov.departments.fold<int>(0, (sum, d) {
      return sum + ((d['_count']?['userDepartments'] ?? 0) as int);
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('Διαχείριση Τμημάτων',
            style: tt.titleLarge?.copyWith(fontWeight: AppFontWeight.bold)),
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
        heroTag: 'manage_departments_fab',
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
                // ── Section header ──
                Padding(
                  padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 4),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 22,
                        decoration: BoxDecoration(
                          color: AppColors.violet600,
                          borderRadius: AppRadius.r2,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Τμήματα',
                        style: GoogleFonts.inter(
                          fontSize: AppFontSize.xl3,
                          fontWeight: AppFontWeight.bold,
                          color: AppColors.ink,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Search ──
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 12),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Αναζήτηση τμημάτων...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: AppRadius.r12),
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
                          color: AppColors.violet600),
                      const SizedBox(width: 12),
                      _MiniStat(
                          label: 'Μέλη',
                          value: '$totalMembers',
                          icon: Icons.people,
                          color: AppColors.red600),
                      const SizedBox(width: 12),
                      _MiniStat(
                          label: 'Εμφαν.',
                          value: '${filtered.length}',
                          icon: Icons.filter_list,
                          color: AppColors.gray500),
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
                              child: Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 40),
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
                                      style: GoogleFonts.inter(
                                        fontSize: AppFontSize.lg,
                                        color: AppColors.gray500,
                                        fontWeight: AppFontWeight.semibold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _search.isNotEmpty
                                          ? 'Δοκιμάστε άλλη αναζήτηση'
                                          : 'Πατήστε το + για να προσθέσετε',
                                      style: GoogleFonts.inter(
                                          fontSize: AppFontSize.base,
                                          color: AppColors.gray400),
                                    ),
                                  ],
                                ),
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
      itemBuilder: (ctx, i) => _DeptCard(
        dept: depts[i] as Map<String, dynamic>,
        onTap: () async {
          await ctx.push('/admin/departments/${depts[i]['id']}');
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
        childAspectRatio: 3.5,
      ),
      itemCount: depts.length,
      itemBuilder: (ctx, i) => _DeptCard(
        dept: depts[i] as Map<String, dynamic>,
        onTap: () async {
          await ctx.push('/admin/departments/${depts[i]['id']}');
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
    final location = (dept['location'] ?? '').toString();
    final description = (dept['description'] ?? '').toString();
    final subtitle =
        [location, description].where((s) => s.isNotEmpty).join(' • ');

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.r12),
      elevation: 0,
      child: InkWell(
        borderRadius: AppRadius.r12,
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 4,
                decoration: const BoxDecoration(
                  color: AppColors.violet600,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(dept['name'] ?? '',
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: AppFontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: GoogleFonts.inter(
                                fontSize: AppFontSize.base,
                                color: AppColors.gray500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                      ] else
                        const SizedBox(height: 2),
                      Wrap(
                        spacing: 10,
                        children: [
                          _CountBadge(
                              icon: Icons.people,
                              count: memberCount,
                              color: AppColors.red600),
                          _CountBadge(
                              icon: Icons.miscellaneous_services,
                              count: serviceCount,
                              color: AppColors.emerald600),
                          _CountBadge(
                              icon: Icons.directions_car,
                              count: vehicleCount,
                              color: AppColors.amber600),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.chevron_right,
                    color: AppColors.gray400, size: 18),
              ),
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
            style: GoogleFonts.inter(
                fontSize: AppFontSize.base,
                fontWeight: AppFontWeight.semibold,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadius.r12,
          border: Border.all(color: AppColors.gray200),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: GoogleFonts.inter(
                    fontWeight: AppFontWeight.bold,
                    fontSize: AppFontSize.xl,
                    color: color)),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: AppFontSize.sm, color: AppColors.gray500)),
          ]),
        ]),
      ),
    );
  }
}
