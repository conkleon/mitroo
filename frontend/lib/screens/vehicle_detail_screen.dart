import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/vehicle_provider.dart';
import '../providers/department_provider.dart';
import '../services/api_client.dart';
import '../helpers/vehicle_helpers.dart';
import '../widgets/image_gallery_card.dart';

import 'package:mitroo_frontend/theme/theme.dart';

/// Detail view for a single vehicle shown as a modal bottom sheet.
class VehicleDetailScreen extends StatefulWidget {
  final int vehicleId;
  const VehicleDetailScreen({super.key, required this.vehicleId});

  /// Show vehicle detail as a modal bottom sheet dialog.
  static Future<bool?> show(BuildContext context, int vehicleId) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VehicleDetailScreen(vehicleId: vehicleId),
    );
  }

  @override
  State<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<VehicleDetailScreen> {
  final _api = ApiClient();
  Map<String, dynamic>? _vehicle;
  List<dynamic> _comments = [];
  final _commentCtrl = TextEditingController();
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.get('/vehicles/${widget.vehicleId}'),
        _api.get('/vehicles/${widget.vehicleId}/comments'),
      ]);
      if (mounted) {
        setState(() {
          if (results[0].statusCode == 200) {
            _vehicle = jsonDecode(results[0].body);
          }
          if (results[1].statusCode == 200) {
            _comments = jsonDecode(results[1].body) as List;
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  // ── Edit dialog ──

  Future<void> _showEditDialog() async {
    final v = _vehicle!;
    final auth = context.read<AuthProvider>();
    final isAdmin = auth.isAdmin;
    final nameCtrl = TextEditingController(text: v['name'] ?? '');
    final typeCtrl = TextEditingController(text: v['type'] ?? '');
    final regCtrl = TextEditingController(text: v['registrationNumber'] ?? '');
    final serialCtrl = TextEditingController(text: v['serialNumber'] ?? '');
    final locationCtrl = TextEditingController(text: v['location'] ?? '');
    final descCtrl = TextEditingController(text: v['description'] ?? '');
    final meterCtrl = TextEditingController(text: '${v['currentMeter'] ?? 0}');

    int? selectedDeptId = v['departmentId'];
    if (isAdmin) {
      final deptProv = context.read<DepartmentProvider>();
      if (deptProv.departments.isEmpty) await deptProv.fetchDepartments();
    }

    if (!mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Επεξεργασία Οχήματος'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Όνομα')),
                const SizedBox(height: 12),
                TextField(
                    controller: typeCtrl,
                    decoration: const InputDecoration(labelText: 'Τύπος')),
                const SizedBox(height: 12),
                TextField(
                    controller: regCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Αρ. Κυκλοφορίας')),
                const SizedBox(height: 12),
                TextField(
                    controller: serialCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Σειριακός Αρ.')),
                const SizedBox(height: 12),
                TextField(
                    controller: locationCtrl,
                    decoration: const InputDecoration(labelText: 'Τοποθεσία')),
                const SizedBox(height: 12),
                TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(labelText: 'Περιγραφή'),
                    maxLines: 2),
                const SizedBox(height: 12),
                TextField(
                  controller: meterCtrl,
                  decoration: InputDecoration(
                    labelText: 'Τρέχων Μετρητής',
                    suffixText:
                        (v['meterType'] ?? 'km') == 'hours' ? 'h' : 'km',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                if (isAdmin) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: selectedDeptId,
                    decoration: const InputDecoration(labelText: 'Τμήμα'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Κανένα')),
                      ...context
                          .read<DepartmentProvider>()
                          .departments
                          .map((d) => DropdownMenuItem(
                                value: d['id'] as int,
                                child: Text(d['name'] ?? ''),
                              )),
                    ],
                    onChanged: (v) => setSt(() => selectedDeptId = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Άκυρο')),
            FilledButton(
              onPressed: () async {
                final data = <String, dynamic>{
                  'name': nameCtrl.text.trim(),
                  'type': typeCtrl.text.trim(),
                  if (isAdmin) 'departmentId': selectedDeptId,
                };
                if (regCtrl.text.isNotEmpty) {
                  data['registrationNumber'] = regCtrl.text.trim();
                }
                if (serialCtrl.text.isNotEmpty) {
                  data['serialNumber'] = serialCtrl.text.trim();
                }
                if (locationCtrl.text.isNotEmpty) {
                  data['location'] = locationCtrl.text.trim();
                }
                if (descCtrl.text.isNotEmpty) {
                  data['description'] = descCtrl.text.trim();
                }
                final meterVal = num.tryParse(meterCtrl.text);
                if (meterVal != null) data['currentMeter'] = meterVal;

                final err = await context
                    .read<VehicleProvider>()
                    .update(widget.vehicleId, data);
                if (ctx.mounted) Navigator.pop(ctx, err == null);
                if (err != null && mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(err)));
                }
              },
              child: const Text('Αποθήκευση'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) _load();
  }

  // ── Delete ──

  Future<void> _deleteVehicle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή Οχήματος'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.red50,
                shape: BoxShape.circle,
              ),
              child:
                  Icon(Icons.delete_outline, size: 32, color: AppColors.red400),
            ),
            const SizedBox(height: 16),
            Text(
              'Διαγραφή "${_vehicle?['name']}";',
              style: const TextStyle(
                  fontWeight: AppFontWeight.semibold, fontSize: AppFontSize.xl),
            ),
            const SizedBox(height: 6),
            Text(
              'Θα χαθούν όλα τα αρχεία καταγραφής.',
              style:
                  TextStyle(color: AppColors.gray600, fontSize: AppFontSize.md),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red600),
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final err =
        await context.read<VehicleProvider>().deleteVehicle(widget.vehicleId);
    setState(() => _busy = false);
    if (mounted) {
      if (err == null) {
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
      }
    }
  }

  // ── Take vehicle ──

  Future<void> _takeVehicle() async {
    final v = _vehicle!;
    final meterType = (v['meterType'] ?? 'km') as String;
    final currentMeter = v['currentMeter'] ?? 0;
    final label = meterType == 'hours' ? 'Ώρες' : 'Χιλιόμετρα';
    final suffix = meterType == 'hours' ? 'h' : 'km';

    final meterCtrl = TextEditingController(text: '$currentMeter');
    final destCtrl = TextEditingController();
    String? meterError;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('Λήψη ${v['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.gray50,
                  borderRadius: AppRadius.r10,
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: AppColors.gray600),
                    const SizedBox(width: 8),
                    Text(
                      'Τρέχων μετρητής: $currentMeter $suffix',
                      style: TextStyle(
                          color: AppColors.gray700,
                          fontSize: AppFontSize.md,
                          fontWeight: AppFontWeight.medium),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text('$label έναρξης:',
                  style: const TextStyle(fontWeight: AppFontWeight.semibold)),
              const SizedBox(height: 8),
              TextField(
                controller: meterCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: label,
                  suffixText: suffix,
                  errorText: meterError,
                  border: OutlineInputBorder(borderRadius: AppRadius.r10),
                  isDense: true,
                ),
                autofocus: true,
                onChanged: (_) => setSt(() => meterError = null),
              ),
              const SizedBox(height: 12),
              const Text('Προορισμός:',
                  style: TextStyle(fontWeight: AppFontWeight.semibold)),
              const SizedBox(height: 8),
              TextField(
                controller: destCtrl,
                decoration: InputDecoration(
                  hintText: 'Προορισμός (προαιρετικό)',
                  border: OutlineInputBorder(borderRadius: AppRadius.r10),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Άκυρο')),
            FilledButton(
              onPressed: () {
                final val = num.tryParse(meterCtrl.text);
                if (val == null || val < 0) {
                  setSt(() => meterError = 'Εισάγετε έγκυρη τιμή');
                  return;
                }
                Navigator.pop(ctx,
                    {'meterStart': val, 'destination': destCtrl.text.trim()});
              },
              child: const Text('Λήψη'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    setState(() => _busy = true);
    final res = await _api.post('/vehicles/${widget.vehicleId}/take', body: {
      'meterStart': result['meterStart'],
      if ((result['destination'] as String).isNotEmpty)
        'destination': result['destination'],
    });
    setState(() => _busy = false);
    if (mounted) {
      final body = jsonDecode(res.body);
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${v['name']}" ανατέθηκε σε εσάς')),
        );
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(body['error'] ?? 'Σφάλμα')),
        );
      }
    }
  }

  // ── Return vehicle ──

  Future<void> _returnVehicle() async {
    final logs = (_vehicle?['logs'] as List?) ?? [];
    final auth = context.read<AuthProvider>();
    final userId = auth.user?['id'];
    final openLog = logs
        .cast<Map<String, dynamic>>()
        .where((l) => l['endAt'] == null && l['user']?['id'] == userId)
        .firstOrNull;

    if (openLog == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Δεν έχετε ανοιχτό αρχείο για αυτό το όχημα')),
      );
      return;
    }

    final v = _vehicle!;
    final meterType = (v['meterType'] ?? 'km') as String;
    final meterStart = openLog['meterStart'] ?? 0;
    final label = meterType == 'hours' ? 'Ώρες' : 'Χιλιόμετρα';
    final suffix = meterType == 'hours' ? 'h' : 'km';

    final meterCtrl = TextEditingController();
    final destCtrl = TextEditingController(text: openLog['destination'] ?? '');
    String? meterError;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('Επιστροφή ${v['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.amber100,
                  borderRadius: AppRadius.r10,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.speed,
                        size: 16, color: AppColors.amber600),
                    const SizedBox(width: 8),
                    Text(
                      '$label εκκίνησης: $meterStart $suffix',
                      style: const TextStyle(
                          color: AppColors.amber800,
                          fontSize: AppFontSize.md,
                          fontWeight: AppFontWeight.medium),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text('$label τέλους:',
                  style: const TextStyle(fontWeight: AppFontWeight.semibold)),
              const SizedBox(height: 8),
              TextField(
                controller: meterCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: label,
                  suffixText: suffix,
                  errorText: meterError,
                  border: OutlineInputBorder(borderRadius: AppRadius.r10),
                  isDense: true,
                ),
                autofocus: true,
                onChanged: (_) => setSt(() => meterError = null),
              ),
              const SizedBox(height: 12),
              const Text('Προορισμός:',
                  style: TextStyle(fontWeight: AppFontWeight.semibold)),
              const SizedBox(height: 8),
              TextField(
                controller: destCtrl,
                decoration: InputDecoration(
                  hintText: 'Προορισμός',
                  border: OutlineInputBorder(borderRadius: AppRadius.r10),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Άκυρο')),
            FilledButton(
              onPressed: () {
                final val = num.tryParse(meterCtrl.text);
                if (val == null) {
                  setSt(() => meterError = 'Εισάγετε έγκυρη τιμή');
                  return;
                }
                if (val < num.parse('$meterStart')) {
                  setSt(() =>
                      meterError = 'Πρέπει να είναι >= $meterStart $suffix');
                  return;
                }
                Navigator.pop(ctx,
                    {'meterEnd': val, 'destination': destCtrl.text.trim()});
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.red600),
              child: const Text('Επιστροφή'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    setState(() => _busy = true);
    final res = await _api.post('/vehicles/${widget.vehicleId}/return', body: {
      'meterEnd': result['meterEnd'],
      if ((result['destination'] as String).isNotEmpty)
        'destination': result['destination'],
    });
    setState(() => _busy = false);
    if (mounted) {
      final body = jsonDecode(res.body);
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${v['name']}" επεστράφη')),
        );
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(body['error'] ?? 'Σφάλμα')),
        );
      }
    }
  }

  // ── Comments ──

  Future<void> _addComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      final res = await _api
          .post('/vehicles/${widget.vehicleId}/comments', body: {'text': text});
      if (res.statusCode == 201 && mounted) {
        _commentCtrl.clear();
        final commentsRes =
            await _api.get('/vehicles/${widget.vehicleId}/comments');
        if (commentsRes.statusCode == 200 && mounted) {
          setState(() => _comments = jsonDecode(commentsRes.body) as List);
        }
      }
    } catch (_) {}
  }

  Future<void> _deleteComment(int commentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή Σχολίου'),
        content: const Text('Είστε σίγουροι;'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red600),
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final res = await _api
          .delete('/vehicles/${widget.vehicleId}/comments/$commentId');
      if (res.statusCode == 204 && mounted) {
        setState(() => _comments.removeWhere((c) => c['id'] == commentId));
      }
    } catch (_) {}
  }

  // ── Build ──

  bool _computeCanManage(AuthProvider auth) {
    if (_vehicle == null) return auth.isAdmin;
    final ownerId = _vehicle!['ownerId'] as int?;
    final currentUserId = auth.user?['id'] as int?;
    final dept = _vehicle!['department'] as Map<String, dynamic>?;
    final deptId = dept?['id'] as int?;
    return auth.isAdmin ||
        auth.isDeptAdminOf(deptId) ||
        (ownerId != null && ownerId == currentUserId);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final isAdmin = auth.isAdmin;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildSheetHeader(tt, cs, _computeCanManage(auth)),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _vehicle == null
                    ? _buildNotFound(tt)
                    : _buildBody(tt, cs, auth, isAdmin),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFound(TextTheme tt) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
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
              child: Icon(Icons.directions_car_outlined,
                  size: 32, color: AppColors.gray400),
            ),
            const SizedBox(height: 16),
            Text('Το όχημα δεν βρέθηκε',
                style: tt.bodyLarge?.copyWith(
                    color: AppColors.gray500,
                    fontWeight: AppFontWeight.semibold)),
            const SizedBox(height: 6),
            Text('Μπορεί να έχει διαγραφεί',
                style: tt.bodySmall?.copyWith(color: AppColors.gray400)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
      TextTheme tt, ColorScheme cs, AuthProvider auth, bool isAdmin) {
    final v = _vehicle!;
    final vehicleType = v['type'] as String?;
    final meterType = (v['meterType'] ?? 'km') as String;
    final meterUnit = meterType == 'hours' ? 'h' : 'km';
    final currentMeter = v['currentMeter'] ?? 0;
    final dept = v['department'] as Map<String, dynamic>?;
    final logs = (v['logs'] as List?) ?? [];

    final userId = auth.user?['id'];
    final hasOpenLog =
        logs.any((l) => l['endAt'] == null && l['user']?['id'] == userId);
    final isInUse = logs.any((l) => l['endAt'] == null);

    final ownerId = v['ownerId'] as int?;
    final currentUserId = auth.user?['id'] as int?;
    final isOwner = ownerId != null && ownerId == currentUserId;
    final deptId = dept?['id'] as int?;
    final canManage = isAdmin || auth.isDeptAdminOf(deptId) || isOwner;
    final isPersonal = ownerId != null;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── Quick info chips ──
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(
                  Icons.speed, '$currentMeter $meterUnit', AppColors.amber600),
              _chip(Icons.category_outlined, vehicleTypeLabel(vehicleType),
                  AppColors.indigo500),
              if (v['registrationNumber'] != null)
                _chip(Icons.confirmation_number_outlined,
                    v['registrationNumber'], AppColors.red600),
              if (dept != null)
                _chip(Icons.business_outlined, dept['name'] ?? '',
                    AppColors.emerald600),
              if (isInUse)
                _chip(Icons.lock, 'Σε χρήση', AppColors.red600)
              else
                _chip(Icons.lock_open, 'Διαθέσιμο', AppColors.emerald600),
            ],
          ),
          const SizedBox(height: 16),

          // ── Take / Return buttons ──
          if (!hasOpenLog && !isInUse && (!isPersonal || isOwner || isAdmin))
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _takeVehicle,
                icon: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.key),
                label: Text(_busy ? 'Παρακαλώ περιμένετε...' : 'Λήψη Οχήματος'),
              ),
            ),
          if (hasOpenLog && (!isPersonal || isOwner || isAdmin))
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _returnVehicle,
                icon: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.assignment_return),
                label: Text(
                    _busy ? 'Παρακαλώ περιμένετε...' : 'Επιστροφή Οχήματος'),
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.red600),
              ),
            ),
          const SizedBox(height: 16),

          _buildDetailsCard(v, tt, cs, auth: auth),
          const SizedBox(height: 16),
          _buildLogsCard(logs, meterUnit, tt, cs),
          const SizedBox(height: 16),
          ImageGalleryCard(
            entityParam: 'vehicleId',
            entityId: widget.vehicleId,
            canManage: canManage,
          ),
          const SizedBox(height: 16),
          _buildCommentsCard(tt, cs, isAdmin),
        ],
      ),
    );
  }

  // ── Sheet header ──

  Widget _buildSheetHeader(TextTheme tt, ColorScheme cs, bool canManage) {
    final vehicleType = _vehicle?['type'] as String?;
    final logs = (_vehicle?['logs'] as List?) ?? [];
    final isInUse = logs.any((l) => l['endAt'] == null);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.amber600, AppColors.amber700],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(100),
                  borderRadius: AppRadius.r2,
                ),
              ),
            ),
            // Action row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (canManage && _vehicle != null) ...[
                    IconButton(
                      icon: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.edit_outlined, size: 20),
                      color: Colors.white,
                      onPressed: _busy ? null : _showEditDialog,
                      tooltip: 'Επεξεργασία',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: Colors.white,
                      onPressed: _busy ? null : _deleteVehicle,
                      tooltip: 'Διαγραφή',
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.close, size: 22),
                    color: Colors.white,
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Κλείσιμο',
                  ),
                ],
              ),
            ),
            // Title
            if (_vehicle != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(30),
                        borderRadius: AppRadius.r14,
                      ),
                      child: Icon(
                        vehicleIcon(vehicleType),
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _vehicle!['name'] ?? '',
                            style: tt.titleLarge?.copyWith(
                              fontWeight: AppFontWeight.extrabold,
                              color: Colors.white,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isInUse
                                  ? Colors.white.withAlpha(30)
                                  : AppColors.emerald600.withAlpha(200),
                              borderRadius: AppRadius.r6,
                            ),
                            child: Text(
                              isInUse ? 'Σε χρήση' : 'Διαθέσιμο',
                              style: TextStyle(
                                fontSize: AppFontSize.sm,
                                color: isInUse
                                    ? Colors.white.withAlpha(220)
                                    : Colors.white,
                                fontWeight: AppFontWeight.semibold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Chip helper ──

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: AppRadius.r10,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: AppFontSize.base,
                  color: color,
                  fontWeight: AppFontWeight.semibold)),
        ],
      ),
    );
  }

  // ── Details card ──

  Widget _buildDetailsCard(Map<String, dynamic> v, TextTheme tt, ColorScheme cs,
      {required AuthProvider auth}) {
    final rows = <Widget>[];
    final entries = <MapEntry<String, String>>[
      MapEntry('Όνομα', v['name'] ?? ''),
      MapEntry('Τύπος', vehicleTypeLabel(v['type'])),
    ];
    if (v['registrationNumber'] != null) {
      entries.add(MapEntry('Αρ. Κυκλοφορίας', v['registrationNumber']));
    }
    if (v['serialNumber'] != null) {
      entries.add(MapEntry('Σειριακός Αρ.', v['serialNumber']));
    }
    if (v['location'] != null) {
      entries.add(MapEntry('Τοποθεσία', v['location']));
    }
    if (v['description'] != null && v['description'].toString().isNotEmpty) {
      entries.add(MapEntry('Περιγραφή', v['description']));
    }
    entries.add(MapEntry('Μετρητής',
        '${v['currentMeter'] ?? 0} ${(v['meterType'] ?? 'km') == 'hours' ? 'h' : 'km'}'));
    if (v['department'] != null) {
      entries.add(MapEntry('Τμήμα', v['department']['name'] ?? ''));
    }
    final owner = v['owner'] as Map<String, dynamic>?;
    if (owner != null && (auth.isAdmin || auth.isDeptAdmin)) {
      entries.add(
          MapEntry('Ιδιοκτήτης', '${owner['forename']} ${owner['surname']}'));
    }

    for (var i = 0; i < entries.length; i++) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i < entries.length - 1 ? 10 : 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(entries[i].key,
                    style: tt.bodySmall?.copyWith(
                        color: AppColors.gray500,
                        fontWeight: AppFontWeight.medium)),
              ),
              Expanded(
                  child: Text(entries[i].value,
                      style: tt.bodyMedium
                          ?.copyWith(fontWeight: AppFontWeight.medium))),
            ],
          ),
        ),
      );
      if (i < entries.length - 1) {
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Divider(height: 1, color: AppColors.gray100),
        ));
      }
    }

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.r16,
        side: BorderSide(color: AppColors.gray200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: cs.primary.withAlpha(15),
                    borderRadius: AppRadius.r8,
                  ),
                  child: Icon(Icons.info_outline, size: 18, color: cs.primary),
                ),
                const SizedBox(width: 10),
                Text('Λεπτομέρειες',
                    style: tt.titleSmall
                        ?.copyWith(fontWeight: AppFontWeight.semibold)),
              ],
            ),
            const SizedBox(height: 14),
            ...rows,
          ],
        ),
      ),
    );
  }

  // ── Logs card ──

  Widget _buildLogsCard(
      List logs, String meterUnit, TextTheme tt, ColorScheme cs) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.r16,
        side: BorderSide(color: AppColors.gray200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.indigo500.withAlpha(15),
                    borderRadius: AppRadius.r8,
                  ),
                  child: const Icon(Icons.history,
                      size: 18, color: AppColors.indigo500),
                ),
                const SizedBox(width: 10),
                Text('Ιστορικό Χρήσης',
                    style: tt.titleSmall
                        ?.copyWith(fontWeight: AppFontWeight.semibold)),
                const Spacer(),
                if (logs.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.indigo500.withAlpha(15),
                      borderRadius: AppRadius.r8,
                    ),
                    child: Text(
                      '${logs.length}',
                      style: const TextStyle(
                          fontSize: AppFontSize.base,
                          color: AppColors.indigo500,
                          fontWeight: AppFontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (logs.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                    color: AppColors.gray50, borderRadius: AppRadius.r12),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.history, color: AppColors.gray400, size: 28),
                      const SizedBox(height: 6),
                      Text('Δεν υπάρχουν αρχεία',
                          style: TextStyle(
                              color: AppColors.gray500,
                              fontSize: AppFontSize.md)),
                    ],
                  ),
                ),
              )
            else
              ...List.generate(logs.length, (i) {
                final log = logs[i];
                final user = log['user'];
                final userName = user != null
                    ? '${user['forename']} ${user['surname']}'
                    : 'Άγνωστος';
                final isOpen = log['endAt'] == null;
                final meterStart = log['meterStart'] ?? '';
                final meterEnd = log['meterEnd'] ?? '—';
                final destination = log['destination'] as String?;
                final comment = log['comment'] as String?;
                final service = log['service'];
                final isLast = i == logs.length - 1;

                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Timeline
                      SizedBox(
                        width: 20,
                        child: Column(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isOpen
                                    ? AppColors.amber600
                                    : AppColors.indigo500,
                                border:
                                    Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                            if (!isLast)
                              Expanded(
                                child: Container(
                                  width: 2,
                                  color: AppColors.gray200,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Content
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isOpen
                                  ? AppColors.amber100
                                  : AppColors.gray50,
                              borderRadius: AppRadius.r12,
                              border: isOpen
                                  ? Border.all(
                                      color: AppColors.amber600.withAlpha(60))
                                  : null,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor:
                                          cs.primary.withAlpha(180),
                                      child: Text(
                                        userName.isNotEmpty
                                            ? userName[0].toUpperCase()
                                            : 'U',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: AppFontSize.sm,
                                            fontWeight: AppFontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(userName,
                                              style: tt.bodySmall?.copyWith(
                                                  fontWeight:
                                                      AppFontWeight.semibold)),
                                          Text(
                                            '${_formatDate(log['startAt'])} → ${isOpen ? 'σε χρήση' : _formatDate(log['endAt'])}',
                                            style: tt.bodySmall?.copyWith(
                                                color: AppColors.gray400,
                                                fontSize: AppFontSize.xs),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isOpen)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color:
                                              AppColors.amber600.withAlpha(20),
                                          borderRadius: AppRadius.r6,
                                        ),
                                        child: const Text('Ενεργό',
                                            style: TextStyle(
                                                fontSize: AppFontSize.xs,
                                                color: AppColors.amber600,
                                                fontWeight:
                                                    AppFontWeight.semibold)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.speed,
                                        size: 14, color: AppColors.gray600),
                                    const SizedBox(width: 4),
                                    Text('$meterStart → $meterEnd $meterUnit',
                                        style: tt.bodySmall?.copyWith(
                                            fontWeight: AppFontWeight.medium)),
                                  ],
                                ),
                                if (destination != null &&
                                    destination.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.place,
                                          size: 14, color: AppColors.gray600),
                                      const SizedBox(width: 4),
                                      Expanded(
                                          child: Text(destination,
                                              style: tt.bodySmall)),
                                    ],
                                  ),
                                ],
                                if (service != null) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.medical_services_outlined,
                                          size: 14, color: AppColors.gray600),
                                      const SizedBox(width: 4),
                                      Expanded(
                                          child: Text(service['name'] ?? '',
                                              style: tt.bodySmall)),
                                    ],
                                  ),
                                ],
                                if (comment != null && comment.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.notes,
                                          size: 14, color: AppColors.gray600),
                                      const SizedBox(width: 4),
                                      Expanded(
                                          child: Text(comment,
                                              style: tt.bodySmall)),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ── Comments card ──

  Widget _buildCommentsCard(TextTheme tt, ColorScheme cs, bool canManage) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.r16,
        side: BorderSide(color: AppColors.gray200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.amber500.withAlpha(15),
                    borderRadius: AppRadius.r8,
                  ),
                  child: const Icon(Icons.chat_bubble_outline,
                      size: 18, color: AppColors.amber500),
                ),
                const SizedBox(width: 10),
                Text('Σχόλια',
                    style: tt.titleSmall
                        ?.copyWith(fontWeight: AppFontWeight.semibold)),
                const Spacer(),
                if (_comments.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.amber500.withAlpha(15),
                      borderRadius: AppRadius.r8,
                    ),
                    child: Text(
                      '${_comments.length}',
                      style: const TextStyle(
                          fontSize: AppFontSize.base,
                          color: AppColors.amber500,
                          fontWeight: AppFontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (_comments.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                    color: AppColors.gray50, borderRadius: AppRadius.r12),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          color: AppColors.gray400, size: 28),
                      const SizedBox(height: 6),
                      Text('Δεν υπάρχουν σχόλια',
                          style: TextStyle(
                              color: AppColors.gray500,
                              fontSize: AppFontSize.md)),
                    ],
                  ),
                ),
              )
            else
              ..._comments.map((comment) {
                final user = comment['user'];
                final userName = user != null
                    ? '${user['forename']} ${user['surname']}'
                    : 'Άγνωστος';
                final dateStr = _formatDate(comment['createdAt']);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: AppColors.gray50, borderRadius: AppRadius.r12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: cs.primary.withAlpha(180),
                              child: Text(
                                userName.isNotEmpty
                                    ? userName[0].toUpperCase()
                                    : 'U',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: AppFontSize.sm,
                                    fontWeight: AppFontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(userName,
                                      style: tt.bodySmall?.copyWith(
                                          fontWeight: AppFontWeight.semibold)),
                                  Text(dateStr,
                                      style: tt.bodySmall?.copyWith(
                                          color: AppColors.gray400,
                                          fontSize: AppFontSize.xs)),
                                ],
                              ),
                            ),
                            if (canManage)
                              InkWell(
                                onTap: () => _deleteComment(comment['id']),
                                borderRadius: AppRadius.r6,
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(Icons.close,
                                      size: 16, color: AppColors.gray400),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(comment['text'] ?? '',
                            style: tt.bodyMedium?.copyWith(height: 1.4)),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  color: AppColors.gray100, borderRadius: AppRadius.r14),
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Γράψε σχόλιο...',
                        hintStyle: TextStyle(fontSize: AppFontSize.md),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      style: const TextStyle(fontSize: AppFontSize.md),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _addComment(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Material(
                    color: cs.primary,
                    borderRadius: AppRadius.r10,
                    child: InkWell(
                      onTap: _addComment,
                      borderRadius: AppRadius.r10,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.send, size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
