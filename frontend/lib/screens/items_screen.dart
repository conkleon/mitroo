import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/item_provider.dart';
import '../providers/category_provider.dart';
import '../providers/department_provider.dart';
import '../services/api_client.dart';
import 'scanner_screen.dart';
import 'my_equipment_sheet.dart';
import 'item_detail_screen.dart';

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key});

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  final _searchCtrl = TextEditingController();
  final _api = ApiClient();
  List<Map<String, dynamic>> _myEquipment = [];
  int _myVehiclesCount = 0;
  int? _selectedCategoryId;
  int? _selectedDepartmentId;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final auth = context.read<AuthProvider>();
      final canManage = auth.isAdmin || auth.isItemAdmin;
      // Regular users only see available (unassigned) items
      context.read<ItemProvider>().fetchItems(available: canManage ? null : true);
      context.read<CategoryProvider>().fetchCategories();
      context.read<DepartmentProvider>().fetchDepartments();
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
    // Also load active vehicles count
    try {
      final vRes = await _api.get('/vehicles/my/active');
      if (vRes.statusCode == 200 && mounted) {
        final list = jsonDecode(vRes.body) as List<dynamic>;
        setState(() => _myVehiclesCount = list.length);
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
    int? selectedCategoryId;
    final depts = context.read<DepartmentProvider>().departments;
    int? selectedDeptId = _selectedDepartmentId ?? (depts.isNotEmpty ? depts.first['id'] as int : null);

    /// Scan barcode via camera, put result in barcodeCtrl, then auto-fill.
    Future<void> scanBarcode(StateSetter setSt) async {
      final result = await Navigator.of(context, rootNavigator: true).push<ScanResult>(
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
                const SizedBox(height: 12),
                Builder(
                  builder: (_) {
                    final depts = context.read<DepartmentProvider>().departments;
                    return DropdownButtonFormField<int>(
                      value: selectedDeptId,
                      decoration: const InputDecoration(labelText: 'Τμήμα'),
                      items: depts.map<DropdownMenuItem<int>>((d) => DropdownMenuItem(
                        value: d['id'] as int,
                        child: Text(d['name'] ?? ''),
                      )).toList(),
                      onChanged: (v) => setSt(() => selectedDeptId = v),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Builder(
                  builder: (_) {
                    final cats = context.read<CategoryProvider>().categories;
                    return DropdownButtonFormField<int?>(
                      value: selectedCategoryId,
                      decoration: const InputDecoration(labelText: 'Κατηγορία'),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('Χωρίς κατηγορία')),
                        ...cats.map((c) => DropdownMenuItem<int?>(
                          value: c['id'] as int,
                          child: Text('${c['name']}'),
                        )),
                      ],
                      onChanged: (v) => setSt(() => selectedCategoryId = v),
                    );
                  },
                ),
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
                if (selectedDeptId == null) return;
                final data = <String, dynamic>{'name': nameCtrl.text.trim(), 'isContainer': isContainer, 'departmentId': selectedDeptId};
                if (barcodeCtrl.text.isNotEmpty) data['barCode'] = barcodeCtrl.text.trim();
                if (locationCtrl.text.isNotEmpty) data['location'] = locationCtrl.text.trim();
                if (descCtrl.text.isNotEmpty) data['description'] = descCtrl.text.trim();
                if (expirationDate != null) data['expirationDate'] = expirationDate!.toIso8601String();
                if (selectedCategoryId != null) data['categoryId'] = selectedCategoryId;
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
    final choice = await showScanChoiceDialog(context);
    if (choice == null || !mounted) return;

    if (choice == ScanChoice.manual) {
      _showManualEntryDialog();
      return;
    }

    final result = await Navigator.of(context).push<ScanResult>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (result == null || !mounted) return;

    final isQr = choice == ScanChoice.qrCode ? true : choice == ScanChoice.barcode ? false : result.isQr;
    await _handleScanResult(result.value, isQr);
  }

  Future<void> _handleScanResult(String value, bool isQr) async {
    // If the value is a pure integer, treat it as an item ID (QR code)
    // regardless of what the scanner reported, since our QR codes encode
    // only the numeric item ID.
    final parsedId = int.tryParse(value);
    if (isQr || (parsedId != null && value == parsedId.toString())) {
      if (parsedId != null) {
        ItemDetailScreen.show(context, parsedId);
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
                                  : const Color(0xFFDC2626))
                              .withAlpha(25),
                          child: Icon(
                            isContainer ? Icons.inventory : Icons.build_outlined,
                            color: isContainer
                                ? const Color(0xFF7C3AED)
                                : const Color(0xFFDC2626),
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
                          ItemDetailScreen.show(context, item['id'] as int);
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
      // Refresh the list and my equipment
      _loadMyEquipment();
      _fetchWithFilters(page: _currentPage);
    }
  }

  void _fetchWithFilters({int page = 1}) {
    final auth = context.read<AuthProvider>();
    final canManage = auth.isAdmin || auth.isItemAdmin;
    final search = _searchCtrl.text.trim().isNotEmpty ? _searchCtrl.text.trim() : null;
    setState(() => _currentPage = page);
    context.read<ItemProvider>().fetchItems(
      available: canManage ? null : true,
      search: search,
      categoryId: _selectedCategoryId,
      departmentId: _selectedDepartmentId,
      page: page,
    );
  }

  Widget _buildDepartmentChips(ColorScheme cs) {
    final deptProv = context.watch<DepartmentProvider>();
    final depts = deptProv.departments;
    if (depts.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 34,
      child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: depts.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (context, i) {
            if (i == 0) {
              final selected = _selectedDepartmentId == null;
              return FilterChip(
                label: const Text('Όλα τα τμήματα'),
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    _selectedDepartmentId = null;
                    _selectedCategoryId = null;
                  });
                  _fetchWithFilters();
                },
                visualDensity: VisualDensity.compact,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
                padding: EdgeInsets.zero,
              );
            }
            final dept = depts[i - 1];
            final deptId = dept['id'] as int;
            final selected = _selectedDepartmentId == deptId;
            return FilterChip(
              label: Text(dept['name'] ?? ''),
              selected: selected,
              onSelected: (_) {
                setState(() {
                  _selectedDepartmentId = selected ? null : deptId;
                  _selectedCategoryId = null;
                });
                _fetchWithFilters();
              },
              visualDensity: VisualDensity.compact,
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
              padding: EdgeInsets.zero,
            );
          },
        ),
    );
  }

  Widget _buildCategoryChips(ColorScheme cs) {
    final catProv = context.watch<CategoryProvider>();
    final cats = catProv.categories;
    if (cats.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: cats.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (context, i) {
            if (i == 0) {
              final selected = _selectedCategoryId == null;
              return FilterChip(
                label: const Text('Όλα'),
                selected: selected,
                onSelected: (_) {
                  setState(() => _selectedCategoryId = null);
                  _fetchWithFilters();
                },
                visualDensity: VisualDensity.compact,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
                padding: EdgeInsets.zero,
              );
            }
            final cat = cats[i - 1];
            final catId = cat['id'] as int;
            final selected = _selectedCategoryId == catId;
            return FilterChip(
              label: Text(cat['name'] ?? ''),
              selected: selected,
              onSelected: (_) {
                setState(() => _selectedCategoryId = selected ? null : catId);
                _fetchWithFilters();
              },
              visualDensity: VisualDensity.compact,
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
              padding: EdgeInsets.zero,
            );
          },
        ),
      ),
    );
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
          onRefresh: () async {
            await prov.fetchItems(available: canManage ? null : true, categoryId: _selectedCategoryId, departmentId: _selectedDepartmentId, page: _currentPage);
            await context.read<CategoryProvider>().fetchCategories();
            await context.read<DepartmentProvider>().fetchDepartments();
          },
          child: CustomScrollView(
            slivers: [
              // ── Top bar ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      // My assigned items button
                      Material(
                        color: cs.primary.withAlpha(15),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: _showMyEquipmentSheet,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inventory_2_outlined, size: 18, color: cs.primary),
                                const SizedBox(width: 8),
                                Text('Τα αντικείμενά μου',
                                    style: tt.labelLarge?.copyWith(
                                        fontWeight: FontWeight.w700, color: cs.primary)),
                                if (_myEquipment.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF059669).withAlpha(20),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${_myEquipment.length}',
                                      style: const TextStyle(
                                          fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF059669)),
                                    ),
                                  ),
                                ],
                                if (_myVehiclesCount > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withAlpha(25),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.directions_car, size: 12, color: Colors.orange.shade800),
                                        const SizedBox(width: 3),
                                        Text(
                                          '$_myVehiclesCount',
                                          style: TextStyle(
                                              fontSize: 11, fontWeight: FontWeight.w700, color: Colors.orange.shade800),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: _buildDepartmentChips(cs)),
                      if (canManage)
                        IconButton(
                          onPressed: () => context.push('/items/csv'),
                          icon: Icon(Icons.settings, size: 22, color: cs.primary),
                          tooltip: 'Εισαγωγή / Εξαγωγή CSV',
                          visualDensity: VisualDensity.compact,
                        ),
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
                          _fetchWithFilters();
                        },
                      ),
                    ),
                    onSubmitted: (v) => _fetchWithFilters(),
                  ),
                ),
              ),
              // ── Category filter chips ──
              SliverToBoxAdapter(
                child: _buildCategoryChips(cs),
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
                      Text('${prov.totalItems} σύνολο', style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
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
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Card(
                      elevation: 0,
                      margin: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: List.generate(prov.items.length, (i) {
                          return Column(
                            children: [
                              if (i > 0) Divider(height: 1, thickness: 1, color: Colors.grey.shade100),
                              _ItemRow(
                                item: prov.items[i],
                                canManage: canManage,
                                onTake: canManage ? null : () => _selfAssignItem(prov.items[i]),
                                onToggleAvailability: canManage ? () async {
                                  await context.read<ItemProvider>().toggleAvailability(prov.items[i]['id']);
                                } : null,
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              // ── Pagination controls ──
              if (!prov.loading && prov.items.isNotEmpty && prov.totalPages > 1)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: _currentPage > 1 ? () => _fetchWithFilters(page: _currentPage - 1) : null,
                          icon: const Icon(Icons.chevron_left),
                          tooltip: 'Προηγούμενη',
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$_currentPage / ${prov.totalPages}',
                          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _currentPage < prov.totalPages ? () => _fetchWithFilters(page: _currentPage + 1) : null,
                          icon: const Icon(Icons.chevron_right),
                          tooltip: 'Επόμενη',
                        ),
                      ],
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

// ── Compact table-row item widget ──

class _ItemRow extends StatelessWidget {
  final dynamic item;
  final bool canManage;
  final VoidCallback? onTake;
  final VoidCallback? onToggleAvailability;
  const _ItemRow({required this.item, this.canManage = true, this.onTake, this.onToggleAvailability});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final parent = item['containedBy'];
    final childCount = item['_count']?['contents'] ?? 0;
    final isContainer = item['isContainer'] == true;
    final assignedTo = item['assignedTo'];
    final isAvailable = item['availableForAssignment'] == true;
    final category = item['category'];
    final accentColor = isContainer ? const Color(0xFF7C3AED) : const Color(0xFFDC2626);

    // First image thumbnail
    final attachments = item['attachments'] as List?;
    final thumbPath = attachments != null && attachments.isNotEmpty
        ? attachments.first['thumbnailPath'] as String?
        : null;

    // Build subtitle parts
    final infoParts = <String>[
      if (category != null) category['name'],
      if (item['barCode'] != null) item['barCode'],
      if (parent != null) parent['name'],
      if (item['location'] != null) item['location'],
    ];

    return InkWell(
      onTap: () => ItemDetailScreen.show(context, item['id'] as int),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        color: Colors.white,
        child: Row(
          children: [
            // Thumbnail or accent bar
            if (thumbPath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  '${ApiClient.uploadsBaseUrl}$thumbPath',
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accentColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(isContainer ? Icons.inventory : Icons.build_outlined, size: 18, color: accentColor),
                  ),
                ),
              )
            else ...[
              Container(
                width: 3,
                height: 32,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
            const SizedBox(width: 10),
            // Name + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item['name'] ?? '',
                          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (childCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C3AED).withAlpha(18),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$childCount',
                            style: const TextStyle(fontSize: 10, color: Color(0xFF7C3AED), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (infoParts.isNotEmpty || assignedTo != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      [
                        ...infoParts,
                        if (assignedTo != null)
                          '${assignedTo['forename'] ?? ''} ${assignedTo['surname'] ?? ''}'.trim(),
                      ].join(' · '),
                      style: tt.bodySmall?.copyWith(
                        color: const Color(0xFF6B7280),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // Availability toggle for admin/itemAdmin
            if (canManage && onToggleAvailability != null)
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  onPressed: onToggleAvailability,
                  icon: Icon(
                    isAvailable ? Icons.visibility : Icons.visibility_off_outlined,
                    size: 18,
                    color: isAvailable ? const Color(0xFF059669) : const Color(0xFFD1D5DB),
                  ),
                  tooltip: isAvailable ? 'Απόκρυψη' : 'Διαθέσιμο',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ),
            // "Take" button for regular users
            if (!canManage && onTake != null)
              SizedBox(
                height: 28,
                child: FilledButton.tonal(
                  onPressed: onTake,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Λήψη'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
