import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import 'scanner_screen.dart';
import 'item_detail_screen.dart';
import 'vehicle_detail_screen.dart';

/// Bottom sheet that shows the user's assigned equipment & active vehicles,
/// with the ability to take / return both.
class MyEquipmentSheet extends StatefulWidget {
  final List<Map<String, dynamic>> equipment;
  final ApiClient api;
  final VoidCallback? onChanged;
  const MyEquipmentSheet({
    super.key,
    required this.equipment,
    required this.api,
    this.onChanged,
  });

  @override
  State<MyEquipmentSheet> createState() => _MyEquipmentSheetState();
}

class _MyEquipmentSheetState extends State<MyEquipmentSheet>
    with SingleTickerProviderStateMixin {
  late List<Map<String, dynamic>> _items;
  final Set<int> _busy = {};

  // Equipment search
  bool _showSearch = false;
  String _searchQuery = '';
  List<dynamic> _searchResults = [];
  bool _searchLoading = false;
  bool _searchInitial = true;

  // Vehicles
  late TabController _tabCtrl;
  List<dynamic> _myVehicles = [];
  bool _vehiclesLoading = false;
  bool _vehiclesLoaded = false;
  bool _showVehicleSearch = false;
  String _vehicleSearchQuery = '';
  List<dynamic> _vehicleSearchResults = [];
  bool _vehicleSearchLoading = false;
  bool _vehicleSearchInitial = true;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.equipment);
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.index == 1 && !_vehiclesLoaded) _loadMyVehicles();
      setState(() {}); // rebuild for tab switch
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════
  //  Equipment methods
  // ═══════════════════════════════════════════════

  Future<void> _returnItem(Map<String, dynamic> item) async {
    final itemId = item['id'] as int;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Επιστροφή Εξοπλισμού'),
        content: Text('Επιστροφή "${item['name']}";'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            child: const Text('Επιστροφή'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy.add(itemId));
    try {
      final res = await widget.api.post('/items/$itemId/self-unassign');
      if (res.statusCode == 200) {
        setState(() => _items.removeWhere((i) => i['id'] == itemId));
        widget.onChanged?.call();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${item['name']}" επεστράφη')),
          );
        }
      } else {
        final body = jsonDecode(res.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(body['error'] ?? 'Αποτυχία επιστροφής')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Σφάλμα σύνδεσης')),
        );
      }
    }
    if (mounted) setState(() => _busy.remove(itemId));
  }

  Future<void> _fetchAvailableItems([String query = '']) async {
    setState(() => _searchLoading = true);
    try {
      final params = <String>['available=true'];
      if (query.isNotEmpty) {
        params.add('search=${Uri.encodeComponent(query)}');
      }
      final res = await widget.api.get('/items?${params.join('&')}');
      if (res.statusCode == 200 && mounted) {
        setState(
            () => _searchResults = jsonDecode(res.body) as List<dynamic>);
      }
    } catch (_) {}
    if (mounted) setState(() => _searchLoading = false);
  }

  Future<void> _selfAssignItem(Map<String, dynamic> item) async {
    final itemId = item['id'] as int;
    final name = item['name'] ?? '';
    setState(() => _busy.add(itemId));
    try {
      final res =
          await widget.api.post('/items/$itemId/self-assign', body: {});
      if (res.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$name" ανατέθηκε σε εσάς')),
        );
        setState(() => _items.add(item));
        widget.onChanged?.call();
        _fetchAvailableItems(_searchQuery);
      } else if (mounted) {
        final body = jsonDecode(res.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(body['error'] ?? 'Σφάλμα')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Σφάλμα σύνδεσης')),
        );
      }
    }
    if (mounted) setState(() => _busy.remove(itemId));
  }

  // ═══════════════════════════════════════════════
  //  Vehicle methods
  // ═══════════════════════════════════════════════

  Future<void> _loadMyVehicles() async {
    setState(() => _vehiclesLoading = true);
    try {
      final res = await widget.api.get('/vehicles/my/active');
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _myVehicles = jsonDecode(res.body) as List<dynamic>;
          _vehiclesLoaded = true;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _vehiclesLoading = false);
  }

  Future<void> _fetchAvailableVehicles([String query = '']) async {
    setState(() => _vehicleSearchLoading = true);
    try {
      final q =
          query.isNotEmpty ? '?search=${Uri.encodeComponent(query)}' : '';
      final res = await widget.api.get('/vehicles/available/list$q');
      if (res.statusCode == 200 && mounted) {
        setState(() =>
            _vehicleSearchResults = jsonDecode(res.body) as List<dynamic>);
      }
    } catch (_) {}
    if (mounted) setState(() => _vehicleSearchLoading = false);
  }

  Future<void> _takeVehicle(Map<String, dynamic> vehicle) async {
    final vehicleId = vehicle['id'] as int;
    final meterType = (vehicle['meterType'] ?? 'km') as String;
    final currentMeter = vehicle['currentMeter'] ?? 0;
    final label = meterType == 'hours' ? 'Ώρες' : 'Χιλιόμετρα';

    final meterCtrl = TextEditingController(text: '$currentMeter');
    final destCtrl = TextEditingController();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Λήψη ${vehicle['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label έναρξης:',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: meterCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: label,
                suffixText: meterType == 'hours' ? 'h' : 'km',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            const Text('Προορισμός:',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: destCtrl,
              decoration: InputDecoration(
                hintText: 'Προορισμός (προαιρετικό)',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
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

    setState(() => _busy.add(vehicleId));
    try {
      final body = <String, dynamic>{'meterStart': result['meterStart']};
      final dest = result['destination'] as String;
      if (dest.isNotEmpty) body['destination'] = dest;
      final res = await widget.api
          .post('/vehicles/$vehicleId/take', body: body);
      if (mounted) {
        final respBody = jsonDecode(res.body);
        if (res.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('"${vehicle['name']}" ανατέθηκε σε εσάς')),
          );
          _loadMyVehicles();
          _fetchAvailableVehicles(_vehicleSearchQuery);
          widget.onChanged?.call();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(respBody['error'] ?? 'Σφάλμα')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Σφάλμα σύνδεσης')),
        );
      }
    }
    if (mounted) setState(() => _busy.remove(vehicleId));
  }

  Future<void> _returnVehicle(Map<String, dynamic> log) async {
    final vehicleId = log['vehicleId'] as int;
    final vehicle = log['vehicle'] as Map<String, dynamic>? ?? {};
    final meterType = (vehicle['meterType'] ?? 'km') as String;
    final meterStart = log['meterStart'] ?? 0;
    final label = meterType == 'hours' ? 'Ώρες' : 'Χιλιόμετρα';
    final vehicleName = vehicle['name'] ?? '';

    final meterCtrl = TextEditingController(text: '$meterStart');
    final destCtrl = TextEditingController(text: (log['destination'] ?? '') as String);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Επιστροφή $vehicleName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label εκκίνησης: $meterStart',
                style: const TextStyle(color: Color(0xFF6B7280))),
            const SizedBox(height: 12),
            Text('$label τέλους:',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: meterCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: label,
                suffixText: meterType == 'hours' ? 'h' : 'km',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            const Text('Προορισμός:',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: destCtrl,
              decoration: InputDecoration(
                hintText: 'Προορισμός',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
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
              if (val != null && val >= num.parse('$meterStart')) {
                Navigator.pop(ctx, {'meterEnd': val, 'destination': destCtrl.text.trim()});
              }
            },
            style:
                FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            child: const Text('Επιστροφή'),
          ),
        ],
      ),
    );

    if (result == null) return;

    setState(() => _busy.add(vehicleId));
    try {
      final body = <String, dynamic>{'meterEnd': result['meterEnd']};
      final dest = result['destination'] as String;
      if (dest.isNotEmpty) body['destination'] = dest;
      final res = await widget.api.post('/vehicles/$vehicleId/return',
          body: body);
      if (mounted) {
        final respBody = jsonDecode(res.body);
        if (res.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"$vehicleName" επεστράφη')),
          );
          _loadMyVehicles();
          widget.onChanged?.call();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(respBody['error'] ?? 'Σφάλμα')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Σφάλμα σύνδεσης')),
        );
      }
    }
    if (mounted) setState(() => _busy.remove(vehicleId));
  }

  // ═══════════════════════════════════════════════
  //  Build
  // ═══════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Tab bar
          TabBar(
            controller: _tabCtrl,
            labelColor: cs.primary,
            unselectedLabelColor: const Color(0xFF6B7280),
            indicatorColor: cs.primary,
            tabs: [
              Tab(
                icon: const Icon(Icons.inventory_2_outlined, size: 20),
                text: 'Εξοπλισμός (${_items.length})',
              ),
              Tab(
                icon: const Icon(Icons.directions_car_outlined, size: 20),
                text: 'Οχήματα (${_myVehicles.length})',
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Tab content
          if (_tabCtrl.index == 0) _buildEquipmentTab(tt, cs),
          if (_tabCtrl.index == 1) _buildVehicleTab(tt, cs),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  Equipment tab
  // ═══════════════════════════════════════════════

  Widget _buildEquipmentTab(TextTheme tt, ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Title row with search toggle
        Row(
          children: [
            Text(
                _showSearch
                    ? 'Αναζήτηση Εξοπλισμού'
                    : 'Ο Εξοπλισμός Μου',
                style:
                    tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _showSearch = !_showSearch;
                  if (_showSearch && _searchInitial) {
                    _searchInitial = false;
                    _fetchAvailableItems();
                  }
                });
              },
              icon: Icon(_showSearch ? Icons.arrow_back : Icons.search,
                  size: 18),
              label: Text(_showSearch ? 'Πίσω' : 'Λήψη',
                  style: const TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: _showSearch
                    ? const Color(0xFF6B7280)
                    : cs.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_showSearch) _buildEquipmentSearch(tt, cs) else _buildMyEquipment(tt, cs),
      ],
    );
  }

  Widget _buildEquipmentSearch(TextTheme tt, ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Search bar + scan
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Αναζήτηση με όνομα ή barcode...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                onChanged: (v) {
                  _searchQuery = v;
                  _fetchAvailableItems(v);
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () async {
                final choice = await showScanChoiceDialog(context);
                if (choice == null || !mounted) return;
                if (choice == ScanChoice.manual) return; // user can type in search field
                final result =
                    await Navigator.of(context).push<ScanResult>(
                  MaterialPageRoute(
                      builder: (_) => const ScannerScreen()),
                );
                if (result == null || !mounted) return;
                if (result.isQr) {
                  final id = int.tryParse(result.value);
                  if (id != null) {
                    Navigator.pop(context);
                    ItemDetailScreen.show(context, id);
                  }
                } else {
                  setState(() => _searchLoading = true);
                  try {
                    final res = await widget.api.get(
                        '/items/barcode/${Uri.encodeComponent(result.value)}');
                    if (mounted) {
                      setState(() {
                        _searchResults = res.statusCode == 200
                            ? jsonDecode(res.body) as List<dynamic>
                            : [];
                        _searchLoading = false;
                      });
                    }
                  } catch (_) {
                    if (mounted) {
                      setState(() => _searchLoading = false);
                    }
                  }
                }
              },
              icon: const Icon(Icons.qr_code_scanner, size: 20),
              tooltip: 'Σάρωση',
              style: IconButton.styleFrom(backgroundColor: cs.primary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_searchLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_searchResults.isEmpty)
          _emptyState(Icons.search_off, 'Δεν βρέθηκαν διαθέσιμα αντικείμενα', tt)
        else
          _constrainedList(
            itemCount: _searchResults.length,
            itemBuilder: (_, i) {
              final item = _searchResults[i] as Map<String, dynamic>;
              final itemId = item['id'] as int;
              final isBusy = _busy.contains(itemId);
              final isContainer = item['isContainer'] == true;
              final subtitle = [
                if ((item['barCode'] ?? '').toString().isNotEmpty)
                  'BC: ${item['barCode']}',
                if ((item['location'] ?? '').toString().isNotEmpty)
                  item['location'],
              ].join(' · ');

              return _card(
                icon: isContainer
                    ? Icons.inventory_2
                    : Icons.build_outlined,
                iconColor: isContainer
                    ? const Color(0xFF7C3AED)
                    : cs.primary,
                title: item['name'] ?? '',
                subtitle: subtitle,
                tt: tt,
                trailing: FilledButton.icon(
                  onPressed:
                      isBusy ? null : () => _selfAssignItem(item),
                  icon: isBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add, size: 16),
                  label: const Text('Λήψη',
                      style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildMyEquipment(TextTheme tt, ColorScheme cs) {
    if (_items.isEmpty) {
      return _emptyState(
          Icons.check_circle_outline, 'Κανένας εξοπλισμός', tt);
    }
    return _constrainedList(
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final item = _items[i];
        final itemId = item['id'] as int;
        final isBusy = _busy.contains(itemId);
        final isExpired = item['expirationDate'] != null &&
            DateTime.tryParse(item['expirationDate'] ?? '')
                    ?.isBefore(DateTime.now()) ==
                true;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
                color: isExpired
                    ? Colors.red.shade200
                    : const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(12),
            color: isExpired ? Colors.red.shade50 : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  item['isContainer'] == true
                      ? Icons.inventory_2
                      : Icons.build_outlined,
                  color: cs.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['name'] ?? '',
                        style: tt.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if (item['barCode'] != null)
                      Text(item['barCode'].toString(),
                          style: tt.bodySmall?.copyWith(
                              color: const Color(0xFF6B7280))),
                    if (item['location'] != null)
                      Text(item['location'].toString(),
                          style: tt.bodySmall?.copyWith(
                              color: const Color(0xFF6B7280))),
                  ],
                ),
              ),
              if (isExpired)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Έληξε',
                        style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.open_in_new, size: 18),
                tooltip: 'Λεπτομέρειες',
                color: const Color(0xFF6B7280),
                onPressed: () {
                  Navigator.pop(context);
                  ItemDetailScreen.show(context, itemId);
                },
              ),
              IconButton(
                icon: isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.assignment_return,
                        size: 18, color: Colors.red.shade600),
                tooltip: 'Επιστροφή',
                onPressed: isBusy ? null : () => _returnItem(item),
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════
  //  Vehicle tab
  // ═══════════════════════════════════════════════

  Widget _buildVehicleTab(TextTheme tt, ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Title row with search toggle
        Row(
          children: [
            Text(
                _showVehicleSearch
                    ? 'Αναζήτηση Οχημάτων'
                    : 'Τα Οχήματά Μου',
                style:
                    tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _showVehicleSearch = !_showVehicleSearch;
                  if (_showVehicleSearch && _vehicleSearchInitial) {
                    _vehicleSearchInitial = false;
                    _fetchAvailableVehicles();
                  }
                });
              },
              icon: Icon(
                  _showVehicleSearch ? Icons.arrow_back : Icons.search,
                  size: 18),
              label: Text(_showVehicleSearch ? 'Πίσω' : 'Λήψη',
                  style: const TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: _showVehicleSearch
                    ? const Color(0xFF6B7280)
                    : cs.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_vehiclesLoading && !_vehiclesLoaded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_showVehicleSearch)
          _buildVehicleSearch(tt, cs)
        else
          _buildMyVehicles(tt, cs),
      ],
    );
  }

  Widget _buildVehicleSearch(TextTheme tt, ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          decoration: InputDecoration(
            hintText: 'Αναζήτηση με όνομα ή αρ. κυκλοφορίας...',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
          ),
          onChanged: (v) {
            _vehicleSearchQuery = v;
            _fetchAvailableVehicles(v);
          },
        ),
        const SizedBox(height: 12),
        if (_vehicleSearchLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_vehicleSearchResults.isEmpty)
          _emptyState(
              Icons.search_off, 'Δεν βρέθηκαν διαθέσιμα οχήματα', tt)
        else
          _constrainedList(
            itemCount: _vehicleSearchResults.length,
            itemBuilder: (_, i) {
              final v = _vehicleSearchResults[i] as Map<String, dynamic>;
              final vid = v['id'] as int;
              final isBusy = _busy.contains(vid);
              final meterType = (v['meterType'] ?? 'km') as String;
              final subtitle = [
                _vehicleTypeLabel(v['type'] ?? ''),
                if ((v['registrationNumber'] ?? '').toString().isNotEmpty)
                  v['registrationNumber'],
                '${v['currentMeter'] ?? 0} ${meterType == 'hours' ? 'h' : 'km'}',
              ].join(' · ');

              return _card(
                icon: _vehicleIcon(v['type'] ?? ''),
                iconColor: const Color(0xFF0D47A1),
                title: v['name'] ?? '',
                subtitle: subtitle,
                tt: tt,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      tooltip: 'Λεπτομέρειες',
                      color: const Color(0xFF6B7280),
                      onPressed: () {
                        Navigator.pop(context);
                        VehicleDetailScreen.show(context, vid);
                      },
                    ),
                    FilledButton.icon(
                      onPressed: isBusy ? null : () => _takeVehicle(v),
                      icon: isBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.key, size: 16),
                      label: const Text('Λήψη',
                          style: TextStyle(fontSize: 12)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildMyVehicles(TextTheme tt, ColorScheme cs) {
    if (_myVehicles.isEmpty) {
      return _emptyState(
          Icons.directions_car_outlined, 'Κανένα ενεργό όχημα', tt);
    }
    return _constrainedList(
      itemCount: _myVehicles.length,
      itemBuilder: (_, i) {
        final log = _myVehicles[i] as Map<String, dynamic>;
        final vehicle = log['vehicle'] as Map<String, dynamic>? ?? {};
        final vehicleId = log['vehicleId'] as int;
        final isBusy = _busy.contains(vehicleId);
        final meterType = (vehicle['meterType'] ?? 'km') as String;
        final meterUnit = meterType == 'hours' ? 'h' : 'km';

        return _card(
          icon: _vehicleIcon(vehicle['type'] ?? ''),
          iconColor: const Color(0xFF0D47A1),
          title: vehicle['name'] ?? '',
          subtitle:
              '${_vehicleTypeLabel(vehicle['type'] ?? '')} · Έναρξη: ${log['meterStart']} $meterUnit',
          tt: tt,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.open_in_new, size: 18),
                tooltip: 'Λεπτομέρειες',
                color: const Color(0xFF6B7280),
                onPressed: () {
                  Navigator.pop(context);
                  VehicleDetailScreen.show(context, vehicleId);
                },
              ),
              FilledButton.icon(
                onPressed: isBusy ? null : () => _returnVehicle(log),
                icon: isBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.assignment_return, size: 16),
                label:
                    const Text('Επιστροφή', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════
  //  Helpers
  // ═══════════════════════════════════════════════

  Widget _emptyState(IconData icon, String text, TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text(text,
              style: tt.bodyMedium
                  ?.copyWith(color: const Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _constrainedList({
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.45),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: itemBuilder,
      ),
    );
  }

  Widget _card({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required TextTheme tt,
    required Widget trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: tt.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      style: tt.bodySmall
                          ?.copyWith(color: const Color(0xFF6B7280)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  IconData _vehicleIcon(String type) {
    switch (type.toLowerCase()) {
      case 'boat':
        return Icons.directions_boat;
      case 'jet_ski':
        return Icons.surfing;
      case 'motorcycle':
        return Icons.two_wheeler;
      default:
        return Icons.directions_car;
    }
  }

  String _vehicleTypeLabel(String type) {
    switch (type.toLowerCase()) {
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
      default:
        return type;
    }
  }
}
