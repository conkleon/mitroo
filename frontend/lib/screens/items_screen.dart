import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/item_provider.dart';
import '../services/api_client.dart';
import 'scanner_screen.dart';
import 'my_equipment_sheet.dart';

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key});

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  final _searchCtrl = TextEditingController();
  final _api = ApiClient();
  List<Map<String, dynamic>> _myEquipment = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final auth = context.read<AuthProvider>();
      final canManage = auth.isAdmin || auth.isItemAdmin;
      // Regular users only see available (unassigned) items
      context.read<ItemProvider>().fetchItems(available: canManage ? null : true);
    });
    _loadMyEquipment();
  }

  Future<void> _loadMyEquipment() async {
    try {
      final res = await _api.get('/auth/me/profile');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _myEquipment = (data['equipment'] as List<dynamic>?)
                    ?.map((e) => Map<String, dynamic>.from(e as Map))
                    .toList() ??
                [];
          });
        }
      }
    } catch (_) {}
  }

  void _showMyEquipmentSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => MyEquipmentSheet(
        equipment: _myEquipment,
        api: _api,
        onChanged: () {
          _loadMyEquipment();
          // Also refresh the items list
          final auth = context.read<AuthProvider>();
          final canManage = auth.isAdmin || auth.isItemAdmin;
          context.read<ItemProvider>().fetchItems(available: canManage ? null : true);
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Create dialog ──

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final barcodeCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    bool isContainer = false;
    DateTime? expirationDate;
    bool autoFilling = false;

    /// Scan barcode via camera, put result in barcodeCtrl, then auto-fill.
    Future<void> scanBarcode(StateSetter setSt) async {
      if (kIsWeb) return; // camera not available on web
      final result = await Navigator.of(context).push<ScanResult>(
        MaterialPageRoute(builder: (_) => const ScannerScreen()),
      );
      if (result == null || !mounted) return;
      barcodeCtrl.text = result.value;
      await _autoFillFromBarcode(barcodeCtrl.text.trim(), setSt, nameCtrl, descCtrl, locationCtrl, (v) => isContainer = v, (v) => expirationDate = v, () => autoFilling, (v) => autoFilling = v);
    }

    /// Look up barcode value and auto-fill if matches found.
    Future<void> onBarcodeSubmitted(StateSetter setSt) async {
      await _autoFillFromBarcode(barcodeCtrl.text.trim(), setSt, nameCtrl, descCtrl, locationCtrl, (v) => isContainer = v, (v) => expirationDate = v, () => autoFilling, (v) => autoFilling = v);
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Νέο Αντικείμενο'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Όνομα')),
                const SizedBox(height: 12),
                TextField(
                  controller: barcodeCtrl,
                  decoration: InputDecoration(
                    labelText: 'Barcode',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (autoFilling)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        if (!kIsWeb)
                          IconButton(
                            icon: const Icon(Icons.qr_code_scanner),
                            tooltip: 'Σάρωση barcode',
                            onPressed: () => scanBarcode(setSt),
                          ),
                      ],
                    ),
                  ),
                  onSubmitted: (_) => onBarcodeSubmitted(setSt),
                ),
                const SizedBox(height: 12),
                TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: 'Τοποθεσία')),
                const SizedBox(height: 12),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Περιγραφή'), maxLines: 2),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Κουτί'),
                  value: isContainer,
                  onChanged: (v) => setSt(() => isContainer = v),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(expirationDate != null
                      ? 'Expires: ${expirationDate!.day}/${expirationDate!.month}/${expirationDate!.year}'
                      : 'Χωρίς ημερομηνία λήξης'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.calendar_today, size: 20),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2100),
                            initialDate: expirationDate ?? DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) setSt(() => expirationDate = picked);
                        },
                      ),
                      if (expirationDate != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setSt(() => expirationDate = null),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final data = <String, dynamic>{'name': nameCtrl.text.trim(), 'isContainer': isContainer};
                if (barcodeCtrl.text.isNotEmpty) data['barCode'] = barcodeCtrl.text.trim();
                if (locationCtrl.text.isNotEmpty) data['location'] = locationCtrl.text.trim();
                if (descCtrl.text.isNotEmpty) data['description'] = descCtrl.text.trim();
                if (expirationDate != null) data['expirationDate'] = expirationDate!.toIso8601String();
                final err = await context.read<ItemProvider>().create(data);
                if (ctx.mounted) Navigator.pop(ctx);
                if (err != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                }
              },
              child: const Text('Δημιουργία'),
            ),
          ],
        ),
      ),
    );
  }

  /// Looks up existing items by barcode and auto-fills the create dialog fields
  /// with data from the most recent match.
  Future<void> _autoFillFromBarcode(
    String barcode,
    StateSetter setSt,
    TextEditingController nameCtrl,
    TextEditingController descCtrl,
    TextEditingController locationCtrl,
    void Function(bool) setIsContainer,
    void Function(DateTime?) setExpiration,
    bool Function() getAutoFilling,
    void Function(bool) setAutoFilling,
  ) async {
    if (barcode.isEmpty) return;
    setSt(() => setAutoFilling(true));
    final results = await context.read<ItemProvider>().fetchByBarcode(barcode);
    if (!mounted) return;
    setSt(() => setAutoFilling(false));
    if (results.isEmpty) return;

    // Use the first result (latest / most relevant) to populate fields.
    final item = results.first as Map<String, dynamic>;
    setSt(() {
      if (nameCtrl.text.isEmpty) nameCtrl.text = item['name'] ?? '';
      if (descCtrl.text.isEmpty) descCtrl.text = item['description'] ?? '';
      if (locationCtrl.text.isEmpty) locationCtrl.text = item['location'] ?? '';
      setIsContainer(item['isContainer'] == true);
      if (item['expirationDate'] != null) {
        setExpiration(DateTime.tryParse(item['expirationDate']));
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Συμπληρώθηκε από "${item['name']}" (${results.length} αποτέλεσμα${results.length > 1 ? 'τα' : ''})'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ── Scan FAB handler ──

  Future<void> _openScanner() async {
    // mobile_scanner doesn't support web – use manual entry there.
    if (kIsWeb) {
      _showManualEntryDialog();
      return;
    }

    final result = await Navigator.of(context).push<ScanResult>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (result == null || !mounted) return;

    await _handleScanResult(result.value, result.isQr);
  }

  Future<void> _handleScanResult(String value, bool isQr) async {
    if (isQr) {
      // QR code contains the item ID
      final id = int.tryParse(value);
      if (id != null) {
        context.push('/items/$id');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Μη έγκυρος κωδικός QR')),
        );
      }
    } else {
      // Barcode → look up all items matching this barcode
      final results = await context.read<ItemProvider>().fetchByBarcode(value);
      if (!mounted) return;
      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Δεν βρέθηκαν αντικείμενα για barcode "$value"')),
        );
      } else {
        _showBarcodeResults(results, value);
      }
    }
  }

  /// Fallback dialog for manual code entry (used on web or when camera is unavailable).
  void _showManualEntryDialog() {
    bool isQr = true;
    String selectedValue = '';

    // Items already loaded in provider for autocomplete suggestions.
    final allItems = context.read<ItemProvider>().items;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          List<Map<String, dynamic>> buildOptions(String query) {
            if (query.length < 3) return [];
            final q = query.toLowerCase();
            return allItems.cast<Map<String, dynamic>>().where((item) {
              if (isQr) {
                // Match by ID prefix or name
                final id = item['id']?.toString() ?? '';
                final name = (item['name'] ?? '').toString().toLowerCase();
                return id.startsWith(q) || name.contains(q);
              } else {
                // Match by barcode substring
                final bc = (item['barCode'] ?? '').toString().toLowerCase();
                return bc.isNotEmpty && bc.contains(q);
              }
            }).toList();
          }

          return AlertDialog(
            title: const Text('Εισαγωγή Κωδικού'),
            content: SizedBox(
              width: 350,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('QR Code'), icon: Icon(Icons.qr_code)),
                      ButtonSegment(value: false, label: Text('Barcode'), icon: Icon(Icons.barcode_reader)),
                    ],
                    selected: {isQr},
                    onSelectionChanged: (v) => setSt(() => isQr = v.first),
                  ),
                  const SizedBox(height: 16),
                  Autocomplete<Map<String, dynamic>>(
                    displayStringForOption: (item) => isQr
                        ? '${item['id']} – ${item['name']}'
                        : '${item['barCode']} – ${item['name']}',
                    optionsBuilder: (textEditingValue) {
                      selectedValue = textEditingValue.text;
                      return buildOptions(textEditingValue.text);
                    },
                    onSelected: (item) {
                      selectedValue = isQr
                          ? item['id'].toString()
                          : (item['barCode'] ?? '').toString();
                    },
                    fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: isQr ? 'ID Αντικειμένου' : 'Τιμή Barcode',
                          hintText: isQr ? 'Εισάγετε αριθμό ID' : 'Εισάγετε barcode',
                          prefixIcon: Icon(isQr ? Icons.tag : Icons.barcode_reader),
                          helperText: 'Πληκτρολογήστε 3+ χαρακτήρες',
                          helperStyle: const TextStyle(fontSize: 11),
                        ),
                        keyboardType: isQr ? TextInputType.number : TextInputType.text,
                        onChanged: (v) => selectedValue = v,
                      );
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
              FilledButton.icon(
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Αναζήτηση'),
                onPressed: () async {
                  final value = selectedValue.trim();
                  if (value.isEmpty) return;
                  // Extract just the ID/barcode if the user selected a suggestion
                  final cleanValue = value.contains(' – ') ? value.split(' – ').first.trim() : value;
                  Navigator.pop(ctx);
                  await _handleScanResult(cleanValue, isQr);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _showBarcodeResults(List<dynamic> results, String barCode) {
    showDialog(
      context: context,
      builder: (ctx) {
        final tt = Theme.of(ctx).textTheme;
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.barcode_reader, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text('Barcode "$barCode"')),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${results.length} αντικείμενο${results.length == 1 ? '' : 'α'} βρέθηκαν',
                  style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final item = results[i];
                      final isContainer = item['isContainer'] == true;
                      final assigned = item['assignedTo'];
                      final parent = item['containedBy'];
                      final subtitleParts = <String>[
                        if (item['location'] != null) item['location'],
                        if (parent != null) 'In: ${parent['name']}',
                        if (assigned != null)
                          'Assigned: ${assigned['forename']} ${assigned['surname']}',
                      ];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: CircleAvatar(
                          backgroundColor: (isContainer
                                  ? const Color(0xFF7C3AED)
                                  : const Color(0xFF2563EB))
                              .withAlpha(25),
                          child: Icon(
                            isContainer ? Icons.inventory : Icons.build_outlined,
                            color: isContainer
                                ? const Color(0xFF7C3AED)
                                : const Color(0xFF2563EB),
                            size: 20,
                          ),
                        ),
                        title: Text(item['name'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: subtitleParts.isNotEmpty
                            ? Text(subtitleParts.join(' · '),
                                maxLines: 1, overflow: TextOverflow.ellipsis)
                            : null,
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () {
                          Navigator.pop(ctx);
                          context.push('/items/${item['id']}');
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Κλείσιμο')),
          ],
        );
      },
    );
  }

  /// Regular user self-assigns an available item.
  Future<void> _selfAssignItem(dynamic item) async {
    final itemId = item['id'] as int;
    final itemName = item['name'] ?? 'this item';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Λήψη Εξοπλισμού'),
        content: Text('Ανάθεση του "$itemName" σε εσάς;'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
          FilledButton.icon(
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Λήψη'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final err = await context.read<ItemProvider>().selfAssign(itemId);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Το "$itemName" ανατέθηκε σε εσάς')),
      );
      // Refresh the list (item should disappear from available)
      final auth = context.read<AuthProvider>();
      final canManage = auth.isAdmin || auth.isItemAdmin;
      context.read<ItemProvider>().fetchItems(available: canManage ? null : true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final prov = context.watch<ItemProvider>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final name = auth.displayName.isNotEmpty ? auth.displayName : (auth.user?['ename'] ?? 'User');
    final canManage = auth.isAdmin || auth.isItemAdmin;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => prov.fetchItems(available: canManage ? null : true),
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
              // ── Search bar ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: canManage ? 'Αναζήτηση αντικειμένων...' : 'Αναζήτηση διαθέσιμου εξοπλισμού...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          context.read<ItemProvider>().fetchItems(available: canManage ? null : true);
                        },
                      ),
                    ),
                    onSubmitted: (v) => context.read<ItemProvider>().fetchItems(search: v, available: canManage ? null : true),
                  ),
                ),
              ),
              // ── Section header with See Assigned button ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2, size: 20, color: cs.primary),
                      const SizedBox(width: 8),
                      Text('Αντικείμενα', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      _AssignedBadgeButton(
                        count: _myEquipment.length,
                        onTap: _showMyEquipmentSheet,
                      ),
                      const SizedBox(width: 10),
                      Text('${prov.items.length} σύνολο', style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
                    ],
                  ),
                ),
              ),
              // ── Item cards ──
              if (prov.loading)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
              else if (prov.items.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('Δεν βρέθηκαν αντικείμενα', style: tt.bodyLarge?.copyWith(color: Colors.grey)),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _ItemCard(
                        item: prov.items[i],
                        canManage: canManage,
                        onTake: canManage ? null : () => _selfAssignItem(prov.items[i]),
                      ),
                      childCount: prov.items.length,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Scan button
          FloatingActionButton.small(
            heroTag: 'scan',
            onPressed: _openScanner,
            child: const Icon(Icons.qr_code_scanner),
          ),
          const SizedBox(height: 12),
          // Create button (only for item managers / admins)
          if (canManage)
            FloatingActionButton(
              heroTag: 'create',
              onPressed: _showCreateDialog,
              child: const Icon(Icons.add),
            ),
        ],
      ),
    );
  }
}

// ── Extracted item card widget ──

class _ItemCard extends StatelessWidget {
  final dynamic item;
  final bool canManage;
  final VoidCallback? onTake;
  const _ItemCard({required this.item, this.canManage = true, this.onTake});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final parent = item['containedBy'];
    final childCount = item['_count']?['contents'] ?? 0;
    final isContainer = item['isContainer'] == true;
    final assignedTo = item['assignedTo'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 2,
        shadowColor: Colors.black.withAlpha(20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade100),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/items/${item['id']}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (isContainer ? const Color(0xFF7C3AED) : const Color(0xFF2563EB)).withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isContainer ? Icons.inventory : Icons.build_outlined,
                    color: isContainer ? const Color(0xFF7C3AED) : const Color(0xFF2563EB),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['name'] ?? '', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (item['barCode'] != null) 'Barcode: ${item['barCode']}',
                          if (parent != null) 'In: ${parent['name']}',
                          if (item['location'] != null) item['location'],
                        ].join(' · '),
                        style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (assignedTo != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.person, size: 14, color: Color(0xFF059669)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '${assignedTo['forename'] ?? ''} ${assignedTo['surname'] ?? ''}'.trim(),
                                style: tt.bodySmall?.copyWith(color: const Color(0xFF059669), fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (childCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$childCount μέσα',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF7C3AED), fontWeight: FontWeight.w500),
                    ),
                  ),
                // "Take" button for regular (non-admin) users
                if (!canManage && onTake != null) ...[
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: onTake,
                    icon: const Icon(Icons.add_circle_outline, size: 16),
                    label: const Text('Λήψη', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                  ),
                ] else ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 20, color: Color(0xFF9CA3AF)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact "See Assigned" button with a badge count.
class _AssignedBadgeButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _AssignedBadgeButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: cs.primary.withAlpha(20),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.primary.withAlpha(60)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 14, color: cs.primary),
            const SizedBox(width: 4),
            Text(
              'Ανατεθ.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
