import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/vehicle_provider.dart';
import '../providers/department_provider.dart';
import '../services/api_client.dart';
import '../widgets/image_gallery_card.dart';

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
          if (results[0].statusCode == 200) _vehicle = jsonDecode(results[0].body);
          if (results[1].statusCode == 200) _comments = jsonDecode(results[1].body) as List;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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
      case 'jet_ski':
        return Icons.surfing;
      default:
        return Icons.directions_car;
    }
  }

  String _vehicleTypeLabel(String? type) {
    switch (type?.toLowerCase()) {
      case 'car':
        return 'Αυτοκίνητο';
      case 'boat':
        return 'Σκάφος';
      case 'jet_ski':
        return 'Jet Ski';
      case 'motorcycle':
        return 'Μοτοσικλέτα';
      case 'truck':
        return 'Φορτηγό';
      case 'van':
        return 'Βαν';
      case 'bus':
        return 'Λεωφορείο';
      default:
        return type ?? '';
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
    final nameCtrl = TextEditingController(text: v['name'] ?? '');
    final typeCtrl = TextEditingController(text: v['type'] ?? '');
    final regCtrl = TextEditingController(text: v['registrationNumber'] ?? '');
    final serialCtrl = TextEditingController(text: v['serialNumber'] ?? '');
    final locationCtrl = TextEditingController(text: v['location'] ?? '');
    final descCtrl = TextEditingController(text: v['description'] ?? '');
    final meterCtrl = TextEditingController(text: '${v['currentMeter'] ?? 0}');

    final deptProv = context.read<DepartmentProvider>();
    if (deptProv.departments.isEmpty) await deptProv.fetchDepartments();
    int? selectedDeptId = v['departmentId'];

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
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Όνομα')),
                const SizedBox(height: 12),
                TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: 'Τύπος')),
                const SizedBox(height: 12),
                TextField(controller: regCtrl, decoration: const InputDecoration(labelText: 'Αρ. Κυκλοφορίας')),
                const SizedBox(height: 12),
                TextField(controller: serialCtrl, decoration: const InputDecoration(labelText: 'Σειριακός Αρ.')),
                const SizedBox(height: 12),
                TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: 'Τοποθεσία')),
                const SizedBox(height: 12),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Περιγραφή'), maxLines: 2),
                const SizedBox(height: 12),
                TextField(
                  controller: meterCtrl,
                  decoration: InputDecoration(
                    labelText: 'Τρέχον Μετρητή',
                    suffixText: (v['meterType'] ?? 'km') == 'hours' ? 'h' : 'km',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  value: selectedDeptId,
                  decoration: const InputDecoration(labelText: 'Τμήμα'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Κανένα')),
                    ...deptProv.departments.map((d) => DropdownMenuItem(
                      value: d['id'] as int,
                      child: Text(d['name'] ?? ''),
                    )),
                  ],
                  onChanged: (v) => setSt(() => selectedDeptId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
            FilledButton(
              onPressed: () async {
                final data = <String, dynamic>{
                  'name': nameCtrl.text.trim(),
                  'type': typeCtrl.text.trim(),
                  'departmentId': selectedDeptId,
                };
                if (regCtrl.text.isNotEmpty) data['registrationNumber'] = regCtrl.text.trim();
                if (serialCtrl.text.isNotEmpty) data['serialNumber'] = serialCtrl.text.trim();
                if (locationCtrl.text.isNotEmpty) data['location'] = locationCtrl.text.trim();
                if (descCtrl.text.isNotEmpty) data['description'] = descCtrl.text.trim();
                final meterVal = num.tryParse(meterCtrl.text);
                if (meterVal != null) data['currentMeter'] = meterVal;

                final err = await context.read<VehicleProvider>().update(widget.vehicleId, data);
                if (ctx.mounted) Navigator.pop(ctx, err == null);
                if (err != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
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
        content: Text('Διαγραφή "${_vehicle?['name']}";\nΘα χαθούν όλα τα αρχεία καταγραφής.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final err = await context.read<VehicleProvider>().deleteVehicle(widget.vehicleId);
    if (mounted) {
      if (err == null) {
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    }
  }

  // ── Take vehicle ──

  Future<void> _takeVehicle() async {
    final v = _vehicle!;
    final meterType = (v['meterType'] ?? 'km') as String;
    final currentMeter = v['currentMeter'] ?? 0;
    final label = meterType == 'hours' ? 'Ώρες' : 'Χιλιόμετρα';

    final meterCtrl = TextEditingController(text: '$currentMeter');
    final destCtrl = TextEditingController();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Λήψη ${v['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label έναρξης:', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: meterCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: label,
                suffixText: meterType == 'hours' ? 'h' : 'km',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            const Text('Προορισμός:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: destCtrl,
              decoration: InputDecoration(
                hintText: 'Προορισμός (προαιρετικό)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () {
              final val = num.tryParse(meterCtrl.text);
              if (val != null && val >= 0) {
                Navigator.pop(ctx, {'meterStart': val, 'destination': destCtrl.text.trim()});
              }
            },
            child: const Text('Λήψη'),
          ),
        ],
      ),
    );

    if (result == null) return;

    final res = await _api.post('/vehicles/${widget.vehicleId}/take', body: {
      'meterStart': result['meterStart'],
      if ((result['destination'] as String).isNotEmpty) 'destination': result['destination'],
    });
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
    // Find open log for current user
    final logs = (_vehicle?['logs'] as List?) ?? [];
    final auth = context.read<AuthProvider>();
    final userId = auth.user?['id'];
    final openLog = logs.cast<Map<String, dynamic>>().where((l) =>
      l['endAt'] == null && l['user']?['id'] == userId).firstOrNull;

    if (openLog == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Δεν έχετε ανοιχτό αρχείο για αυτό το όχημα')),
      );
      return;
    }

    final v = _vehicle!;
    final meterType = (v['meterType'] ?? 'km') as String;
    final meterStart = openLog['meterStart'] ?? 0;
    final label = meterType == 'hours' ? 'Ώρες' : 'Χιλιόμετρα';

    final meterCtrl = TextEditingController(text: '$meterStart');
    final destCtrl = TextEditingController(text: openLog['destination'] ?? '');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Επιστροφή ${v['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label εκκίνησης: $meterStart', style: const TextStyle(color: Color(0xFF6B7280))),
            const SizedBox(height: 12),
            Text('$label τέλους:', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: meterCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: label,
                suffixText: meterType == 'hours' ? 'h' : 'km',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            const Text('Προορισμός:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: destCtrl,
              decoration: InputDecoration(
                hintText: 'Προορισμός',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () {
              final val = num.tryParse(meterCtrl.text);
              if (val != null && val >= num.parse('$meterStart')) {
                Navigator.pop(ctx, {'meterEnd': val, 'destination': destCtrl.text.trim()});
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            child: const Text('Επιστροφή'),
          ),
        ],
      ),
    );

    if (result == null) return;

    final res = await _api.post('/vehicles/${widget.vehicleId}/return', body: {
      'meterEnd': result['meterEnd'],
      if ((result['destination'] as String).isNotEmpty) 'destination': result['destination'],
    });
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
      final res = await _api.post('/vehicles/${widget.vehicleId}/comments', body: {'text': text});
      if (res.statusCode == 201 && mounted) {
        _commentCtrl.clear();
        final commentsRes = await _api.get('/vehicles/${widget.vehicleId}/comments');
        if (commentsRes.statusCode == 200 && mounted) {
          setState(() => _comments = jsonDecode(commentsRes.body) as List);
        }
      }
    } catch (_) {}
  }

  Future<void> _deleteComment(int commentId) async {
    try {
      final res = await _api.delete('/vehicles/${widget.vehicleId}/comments/$commentId');
      if (res.statusCode == 204 && mounted) {
        setState(() => _comments.removeWhere((c) => c['id'] == commentId));
      }
    } catch (_) {}
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final isAdmin = auth.isAdmin;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7FA),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── Header ──
          _buildSheetHeader(tt, cs, isAdmin),
          // ── Body ──
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _vehicle == null
                    ? const Center(child: Text('Όχημα δεν βρέθηκε'))
                    : _buildBody(tt, cs, auth, isAdmin),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(TextTheme tt, ColorScheme cs, AuthProvider auth, bool isAdmin) {
    final v = _vehicle!;
    final vehicleType = v['type'] as String?;
    final meterType = (v['meterType'] ?? 'km') as String;
    final meterUnit = meterType == 'hours' ? 'h' : 'km';
    final currentMeter = v['currentMeter'] ?? 0;
    final dept = v['department'] as Map<String, dynamic>?;
    final logs = (v['logs'] as List?) ?? [];

    final userId = auth.user?['id'];
    final hasOpenLog = logs.any((l) => l['endAt'] == null && l['user']?['id'] == userId);
    final isInUse = logs.any((l) => l['endAt'] == null);

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
              _chip(Icons.speed, '$currentMeter $meterUnit', const Color(0xFFD97706)),
              _chip(Icons.category_outlined, _vehicleTypeLabel(vehicleType), const Color(0xFF6366F1)),
              if (v['registrationNumber'] != null)
                _chip(Icons.confirmation_number_outlined, v['registrationNumber'], const Color(0xFFDC2626)),
              if (dept != null)
                _chip(Icons.business_outlined, dept['name'] ?? '', const Color(0xFF059669)),
              if (isInUse)
                _chip(Icons.lock, 'Σε χρήση', const Color(0xFFDC2626))
              else
                _chip(Icons.lock_open, 'Διαθέσιμο', const Color(0xFF059669)),
            ],
          ),
          const SizedBox(height: 16),

          // ── Take / Return buttons ──
          if (!hasOpenLog && !isInUse)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _takeVehicle,
                icon: const Icon(Icons.key),
                label: const Text('Λήψη Οχήματος'),
              ),
            ),
          if (hasOpenLog)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _returnVehicle,
                icon: const Icon(Icons.assignment_return),
                label: const Text('Επιστροφή Οχήματος'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
              ),
            ),
          const SizedBox(height: 16),

          _buildDetailsCard(v, tt, cs),
          const SizedBox(height: 16),
          _buildLogsCard(logs, meterUnit, tt, cs),
          const SizedBox(height: 16),
          ImageGalleryCard(
            entityParam: 'vehicleId',
            entityId: widget.vehicleId,
            canManage: isAdmin,
          ),
          const SizedBox(height: 16),
          _buildCommentsCard(tt, cs, isAdmin),
        ],
      ),
    );
  }

  // ── Modal header with gradient, drag handle, title & actions ──

  Widget _buildSheetHeader(TextTheme tt, ColorScheme cs, bool isAdmin) {
    final vehicleType = _vehicle?['type'] as String?;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD97706), Color(0xFFB45309)],
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
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Action row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isAdmin && _vehicle != null) ...[
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      color: Colors.white,
                      onPressed: _showEditDialog,
                      tooltip: 'Επεξεργασία',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: Colors.white,
                      onPressed: _deleteVehicle,
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
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(30),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        _vehicleIcon(vehicleType),
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        _vehicle!['name'] ?? '',
                        style: tt.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Details card ──

  Widget _buildDetailsCard(Map<String, dynamic> v, TextTheme tt, ColorScheme cs) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
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
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.info_outline, size: 18, color: cs.primary),
                ),
                const SizedBox(width: 10),
                Text('Λεπτομέρειες', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 14),
            _detailRow('Όνομα', v['name'] ?? '', tt),
            _detailRow('Τύπος', _vehicleTypeLabel(v['type']), tt),
            if (v['registrationNumber'] != null) _detailRow('Αρ. Κυκλοφορίας', v['registrationNumber'], tt),
            if (v['serialNumber'] != null) _detailRow('Σειριακός Αρ.', v['serialNumber'], tt),
            if (v['location'] != null) _detailRow('Τοποθεσία', v['location'], tt),
            if (v['description'] != null && v['description'].toString().isNotEmpty)
              _detailRow('Περιγραφή', v['description'], tt),
            _detailRow('Μετρητής', '${v['currentMeter'] ?? 0} ${(v['meterType'] ?? 'km') == 'hours' ? 'h' : 'km'}', tt),
            if (v['department'] != null) _detailRow('Τμήμα', v['department']['name'] ?? '', tt),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280), fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  // ── Logs card ──

  Widget _buildLogsCard(List logs, String meterUnit, TextTheme tt, ColorScheme cs) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
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
                    color: const Color(0xFF6366F1).withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.history, size: 18, color: Color(0xFF6366F1)),
                ),
                const SizedBox(width: 10),
                Text('Ιστορικό Χρήσης', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                if (logs.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withAlpha(15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${logs.length}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6366F1), fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (logs.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.history, color: Colors.grey.shade400, size: 28),
                      const SizedBox(height: 6),
                      Text('Δεν υπάρχουν αρχεία', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                    ],
                  ),
                ),
              )
            else
              ...logs.map((log) {
                final user = log['user'];
                final userName = user != null ? '${user['forename']} ${user['surname']}' : 'Άγνωστος';
                final isOpen = log['endAt'] == null;
                final meterStart = log['meterStart'] ?? '';
                final meterEnd = log['meterEnd'] ?? '—';
                final destination = log['destination'] as String?;
                final comment = log['comment'] as String?;
                final service = log['service'];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isOpen ? const Color(0xFFFEF3C7) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: isOpen ? Border.all(color: const Color(0xFFD97706).withAlpha(60)) : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: cs.primary.withAlpha(180),
                              child: Text(
                                userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(userName, style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                                  Text(
                                    '${_formatDate(log['startAt'])} → ${isOpen ? 'σε χρήση' : _formatDate(log['endAt'])}',
                                    style: tt.bodySmall?.copyWith(color: const Color(0xFF9CA3AF), fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                            if (isOpen)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD97706).withAlpha(20),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('Ενεργό', style: TextStyle(fontSize: 10, color: Color(0xFFD97706), fontWeight: FontWeight.w600)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.speed, size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text('$meterStart → $meterEnd $meterUnit', style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
                          ],
                        ),
                        if (destination != null && destination.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.place, size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Expanded(child: Text(destination, style: tt.bodySmall)),
                            ],
                          ),
                        ],
                        if (service != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.medical_services_outlined, size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Expanded(child: Text(service['name'] ?? '', style: tt.bodySmall)),
                            ],
                          ),
                        ],
                        if (comment != null && comment.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.notes, size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Expanded(child: Text(comment, style: tt.bodySmall)),
                            ],
                          ),
                        ],
                      ],
                    ),
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
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
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
                    color: const Color(0xFFF59E0B).withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.chat_bubble_outline, size: 18, color: Color(0xFFF59E0B)),
                ),
                const SizedBox(width: 10),
                Text('Σχόλια', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                if (_comments.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withAlpha(15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_comments.length}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFF59E0B), fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (_comments.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.chat_bubble_outline, color: Colors.grey.shade400, size: 28),
                      const SizedBox(height: 6),
                      Text('Δεν υπάρχουν σχόλια', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                    ],
                  ),
                ),
              )
            else
              ..._comments.map((comment) {
                final user = comment['user'];
                final userName = user != null ? '${user['forename']} ${user['surname']}' : 'Άγνωστος';
                final dateStr = _formatDate(comment['createdAt']);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: cs.primary.withAlpha(180),
                              child: Text(
                                userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(userName, style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                                  Text(dateStr, style: tt.bodySmall?.copyWith(color: const Color(0xFF9CA3AF), fontSize: 10)),
                                ],
                              ),
                            ),
                            if (canManage)
                              InkWell(
                                onTap: () => _deleteComment(comment['id']),
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(comment['text'] ?? '', style: tt.bodyMedium?.copyWith(height: 1.4)),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Γράψε σχόλιο...',
                        hintStyle: TextStyle(fontSize: 13),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      style: const TextStyle(fontSize: 13),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _addComment(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Material(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: _addComment,
                      borderRadius: BorderRadius.circular(10),
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
