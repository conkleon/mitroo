import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/department_provider.dart';
import '../providers/vehicle_provider.dart';
import '../services/api_client.dart';
import '../helpers/vehicle_helpers.dart';
import 'vehicle_detail_screen.dart';

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  bool _creating = false;
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text));
    Future.microtask(() {
      context.read<VehicleProvider>().fetchVehicles();
      final auth = context.read<AuthProvider>();
      if (auth.isAdmin || auth.isDeptAdmin) {
        context.read<DepartmentProvider>().fetchDepartments();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showCreateDialog() {
    final auth = context.read<AuthProvider>();
    final canCreateDept = auth.isAdmin || auth.isDeptAdmin;

    final nameCtrl = TextEditingController();
    final typeCtrl = TextEditingController();
    final regCtrl = TextEditingController();
    String meterType = 'km';
    String? nameError;
    bool isPersonal = !canCreateDept;
    int? selectedDeptId;
    List<Map<String, dynamic>> deptOptions = [];

    if (canCreateDept) {
      if (auth.isAdmin) {
        final deptProv = context.read<DepartmentProvider>();
        deptOptions = deptProv.departments
            .map((d) => {'id': d['id'] as int, 'name': d['name'] as String})
            .toList();
      } else {
        deptOptions = auth.itemAdminDepartments;
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Νέο Όχημα'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canCreateDept) ...[
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Προσωπικό')),
                      ButtonSegment(value: false, label: Text('Τμήματος')),
                    ],
                    selected: {isPersonal},
                    onSelectionChanged: (v) => setSt(() {
                      isPersonal = v.first;
                      if (isPersonal) selectedDeptId = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Όνομα',
                    errorText: nameError,
                  ),
                  onChanged: (_) => setSt(() => nameError = null),
                ),
                const SizedBox(height: 12),
                TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: 'Τύπος (αυτοκίνητο, σκάφος, κλπ)')),
                const SizedBox(height: 12),
                TextField(controller: regCtrl, decoration: const InputDecoration(labelText: 'Αρ. Κυκλοφορίας')),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'km', label: Text('Χιλιόμετρα')),
                    ButtonSegment(value: 'hours', label: Text('Ώρες')),
                  ],
                  selected: {meterType},
                  onSelectionChanged: (v) => setSt(() => meterType = v.first),
                ),
                if (!isPersonal && deptOptions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: selectedDeptId,
                    decoration: const InputDecoration(labelText: 'Τμήμα'),
                    items: deptOptions.map((d) => DropdownMenuItem(
                      value: d['id'] as int,
                      child: Text(d['name'] as String),
                    )).toList(),
                    onChanged: (v) => setSt(() => selectedDeptId = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
            FilledButton(
              onPressed: _creating
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty) {
                        setSt(() => nameError = 'Το όνομα είναι υποχρεωτικό');
                        return;
                      }
                      setSt(() => _creating = true);
                      final data = <String, dynamic>{
                        'name': nameCtrl.text.trim(),
                        'type': typeCtrl.text.trim(),
                        'meterType': meterType,
                      };
                      if (regCtrl.text.isNotEmpty) data['registrationNumber'] = regCtrl.text.trim();
                      if (!isPersonal && selectedDeptId != null) data['departmentId'] = selectedDeptId;
                      final err = await context.read<VehicleProvider>().create(data);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (err != null && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                      }
                      setSt(() => _creating = false);
                    },
              child: _creating
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Δημιουργία'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final prov = context.watch<VehicleProvider>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final name = auth.displayName.isNotEmpty ? auth.displayName : (auth.user?['eame'] ?? 'User');

    final filtered = _search.isEmpty
        ? prov.vehicles
        : prov.vehicles.where((v) {
            final q = _search.toLowerCase();
            return (v['name'] as String? ?? '').toLowerCase().contains(q) ||
                (v['type'] as String? ?? '').toLowerCase().contains(q) ||
                (v['registrationNumber'] as String? ?? '').toLowerCase().contains(q);
          }).toList();

    return Scaffold(
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
                      Text('R.C.D.', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: cs.primary)),
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
              // ── Search bar ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Αναζήτηση οχήματος...',
                      hintStyle: const TextStyle(fontSize: 14),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _search.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => _searchCtrl.clear(),
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: cs.primary),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              // ── Vehicle cards ──
              if (prov.loading)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
              else if (prov.vehicles.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                      decoration: BoxDecoration(
                        color: Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Color(0xFFF3F4F6),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.directions_car_outlined, size: 32, color: Color(0xFF9CA3AF)),
                          ),
                          const SizedBox(height: 16),
                          Text('Δεν υπάρχουν οχήματα', style: tt.bodyLarge?.copyWith(color: const Color(0xFF6B7280), fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text('Πατήστε το + για να προσθέσετε', style: tt.bodySmall?.copyWith(color: Color(0xFF9CA3AF))),
                        ],
                      ),
                    ),
                  ),
                )
              else if (filtered.isEmpty && _search.isNotEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Text('Δεν βρέθηκαν αποτελέσματα', style: tt.bodyMedium?.copyWith(color: const Color(0xFF6B7280))),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final v = filtered[i];
                        final dept = v['department'];
                        final owner = v['owner'] as Map<String, dynamic>?;
                        final showOwner = owner != null && (auth.isAdmin || auth.isDeptAdmin);
                        final meter = v['currentMeter'] ?? 0;
                        final meterType = v['meterType'] ?? 'km';
                        final vehicleType = v['type'] as String?;
                        final attachments = v['attachments'] as List?;
                        final thumbPath = attachments != null && attachments.isNotEmpty
                            ? attachments.first['thumbnailPath'] as String?
                            : null;
                        final logs = v['logs'] as List? ?? [];
                        final isInUse = logs.any((l) => l['endAt'] == null);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                            elevation: 0,
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: Color(0xFFE5E7EB)),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => VehicleDetailScreen.show(context, v['id'] as int),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        if (thumbPath != null)
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: Image.network(
                                              '${ApiClient.uploadsBaseUrl}$thumbPath',
                                              width: 48,
                                              height: 48,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => _vehicleIconContainer(vehicleType),
                                            ),
                                          )
                                        else
                                          _vehicleIconContainer(vehicleType),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      v['name'] ?? '',
                                                      style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: isInUse ? const Color(0xFFDC2626) : const Color(0xFF059669),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    isInUse ? 'Σε χρήση' : 'Διαθέσιμο',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: isInUse ? const Color(0xFFDC2626) : const Color(0xFF059669),
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (vehicleType != null && vehicleType.isNotEmpty)
                                                Text(vehicleTypeLabel(vehicleType), style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(Icons.chevron_right, size: 20, color: Color(0xFFD1D5DB)),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        if (v['registrationNumber'] != null)
                                          _VehicleChip(
                                            icon: Icons.confirmation_number_outlined,
                                            label: v['registrationNumber'],
                                            color: const Color(0xFFDC2626),
                                          ),
                                        _VehicleChip(
                                          icon: Icons.speed,
                                          label: '$meter ${meterType == 'hours' ? 'h' : 'km'}',
                                          color: const Color(0xFFD97706),
                                        ),
                                        if (dept != null)
                                          _VehicleChip(
                                            icon: Icons.business_outlined,
                                            label: dept['name'] ?? '',
                                            color: const Color(0xFF059669),
                                          ),
                                        if (showOwner)
                                          _VehicleChip(
                                            icon: Icons.person_outline,
                                            label: '${owner!['forename']} ${owner['surname']}',
                                            color: const Color(0xFF7C3AED),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
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
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _vehicleIconContainer(String? vehicleType) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD97706), Color(0xFFB45309)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(vehicleIcon(vehicleType), color: Colors.white, size: 22),
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
        color: color.withAlpha(18),
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
