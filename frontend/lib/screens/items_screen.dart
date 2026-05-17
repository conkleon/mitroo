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
  final int? initialDepartmentId;
  const ItemsScreen({super.key, this.initialDepartmentId});

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  final _api = ApiClient();
  final _searchCtrl = TextEditingController();

  // Data
  List<Map<String, dynamic>> _allItems = [];
  bool _loading = true;

  // Filters
  String _search = '';
  int? _deptFilter;
  int? _selectedCategoryId;

  // Sorting
  String _sortField = 'name';
  bool _sortAsc = true;

  // Pagination
  int _page = 0;
  int _rowsPerPage = 25;

  // Selection
  bool _selectionMode = false;
  final Set<int> _selectedIds = {};
  bool _filtersExpanded = false;

  // My equipment
  List<Map<String, dynamic>> _myEquipment = [];
  int _myVehiclesCount = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (widget.initialDepartmentId != null) {
        _deptFilter = widget.initialDepartmentId;
      }
      _fetch();
    });
    _loadMyEquipment();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthProvider>();
      final canManage = auth.isAdmin || auth.isItemAdmin;
      await context.read<ItemProvider>().fetchItems(
        available: canManage ? null : true,
        limit: 10000,
      );
      await Future.wait([
        context.read<CategoryProvider>().fetchCategories(),
        context.read<DepartmentProvider>().fetchDepartments(),
      ]);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _allItems = List<Map<String, dynamic>>.from(
          context.read<ItemProvider>().items.cast<Map<String, dynamic>>(),
        );
        _loading = false;
      });
    }
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
    try {
      final vRes = await _api.get('/vehicles/my/active');
      if (vRes.statusCode == 200 && mounted) {
        final list = jsonDecode(vRes.body) as List<dynamic>;
        setState(() => _myVehiclesCount = list.length);
      }
    } catch (_) {}
  }

  Future<void> _showMyEquipmentSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => MyEquipmentSheet(
        equipment: _myEquipment,
        api: _api,
        onChanged: () {}, // sheet handles its own local state removal
      ),
    );
    if (mounted) {
      await _loadMyEquipment();
      await _fetch();
    }
  }

  // ── Filtering + Sorting ──────────────────────────

  List<Map<String, dynamic>> get _processed {
    var list = List<Map<String, dynamic>>.from(_allItems);

    if (_deptFilter != null) {
      list = list.where((item) => item['departmentId'] == _deptFilter).toList();
    }

    if (_selectedCategoryId != null) {
      list = list.where((item) => item['categoryId'] == _selectedCategoryId).toList();
    }

    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((item) {
        final name = (item['name'] ?? '').toString().toLowerCase();
        final desc = (item['description'] ?? '').toString().toLowerCase();
        final barcode = (item['barCode'] ?? '').toString().toLowerCase();
        final loc = (item['location'] ?? '').toString().toLowerCase();
        final deptName = (item['department']?['name'] ?? '').toString().toLowerCase();
        return name.contains(q) || desc.contains(q) || barcode.contains(q) || loc.contains(q) || deptName.contains(q);
      }).toList();
    }

    list.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case 'category':
          cmp = ((a['category']?['name'] ?? '') as String).toLowerCase()
              .compareTo(((b['category']?['name'] ?? '') as String).toLowerCase());
          break;
        case 'location':
          cmp = ((a['location'] ?? '') as String).toLowerCase()
              .compareTo(((b['location'] ?? '') as String).toLowerCase());
          break;
        case 'quantity':
          cmp = ((a['quantity'] ?? 0) as int).compareTo((b['quantity'] ?? 0) as int);
          break;
        case 'department':
          cmp = ((a['department']?['name'] ?? '') as String).toLowerCase()
              .compareTo(((b['department']?['name'] ?? '') as String).toLowerCase());
          break;
        case 'available':
          cmp = ((a['availableForAssignment'] == true) ? 0 : 1)
              .compareTo((b['availableForAssignment'] == true) ? 0 : 1);
          break;
        case 'isContainer':
          cmp = ((a['isContainer'] == true) ? 0 : 1)
              .compareTo((b['isContainer'] == true) ? 0 : 1);
          break;
        case 'assignedTo':
          cmp = _assignedName(a).toLowerCase().compareTo(_assignedName(b).toLowerCase());
          break;
        default:
          cmp = ((a['name'] ?? '') as String).toLowerCase()
              .compareTo(((b['name'] ?? '') as String).toLowerCase());
      }
      return _sortAsc ? cmp : -cmp;
    });

    return list;
  }

  String _assignedName(Map<String, dynamic> item) {
    final a = item['assignedTo'] as Map<String, dynamic>?;
    if (a == null) return '';
    return '${a['surname'] ?? ''} ${a['forename'] ?? ''}'.trim();
  }

  int _countCat(int catId) {
    var items = List<Map<String, dynamic>>.from(_allItems);
    if (_deptFilter != null) {
      items = items.where((i) => i['departmentId'] == _deptFilter).toList();
    }
    return items.where((i) => i['categoryId'] == catId).length;
  }

  void _setSort(String field) {
    setState(() {
      if (_sortField == field) {
        _sortAsc = !_sortAsc;
      } else {
        _sortField = field;
        _sortAsc = field == 'name';
      }
      _page = 0;
    });
  }

  // ── Selection ───────────────────────────────────

  void _enterSelectionMode(int itemId) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(itemId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  int get _activeFilterCount {
    int count = 0;
    if (_deptFilter != null) count++;
    if (_selectedCategoryId != null) count++;
    return count;
  }

  void _toggleSelect(int itemId) {
    setState(() {
      if (_selectedIds.contains(itemId)) {
        _selectedIds.remove(itemId);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(itemId);
      }
    });
  }

  void _toggleSelectAll(List<Map<String, dynamic>> pageItems) {
    setState(() {
      final pageIds = pageItems.map((i) => i['id'] as int).toSet();
      if (pageIds.every((id) => _selectedIds.contains(id))) {
        _selectedIds.removeAll(pageIds);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.addAll(pageIds);
      }
    });
  }

  // ── Bulk actions ────────────────────────────────

  Future<void> _bulkToggleAvailability() async {
    final prov = context.read<ItemProvider>();
    int ok = 0, fail = 0;
    await Future.wait(_selectedIds.map((id) async {
      final err = await prov.toggleAvailability(id);
      err == null ? ok++ : fail++;
    }));
    if (!mounted) return;
    _exitSelectionMode();
    _fetch();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(fail == 0 ? '$ok αντικείμενα ενημερώθηκαν' : '$ok ενημερώθηκαν, $fail αποτυχίες'),
    ));
  }

  Future<void> _bulkDelete() async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή Αντικειμένων'),
        content: Text('Διαγραφή $count αντικειμένων; Αυτή η ενέργεια δεν μπορεί να αναιρεθεί.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final prov = context.read<ItemProvider>();
    int ok = 0, fail = 0;
    await Future.wait(_selectedIds.map((id) async {
      final err = await prov.deleteItem(id);
      err == null ? ok++ : fail++;
    }));
    if (!mounted) return;
    _exitSelectionMode();
    _fetch();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(fail == 0 ? '$ok αντικείμενα διαγράφηκαν' : '$ok διαγράφηκαν, $fail αποτυχίες'),
    ));
  }

  // ── Department Filter ────────────────────────────

  Widget _buildDeptFilter() {
    final deptProv = context.watch<DepartmentProvider>();
    final depts = deptProv.departments;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: _deptFilter,
          isExpanded: true,
          isDense: true,
          icon: const Icon(Icons.filter_list, size: 18),
          hint: const Text('Όλα τα Τμήματα', style: TextStyle(fontSize: 13)),
          style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Όλα τα Τμήματα')),
            ...depts.map((d) => DropdownMenuItem<int?>(
                  value: d['id'] as int?,
                  child: Text(d['name'] ?? 'Τμήμα'),
                )),
          ],
          onChanged: (v) => setState(() { _deptFilter = v; _page = 0; }),
        ),
      ),
    );
  }

  // ── Chip widget ──────────────────────────────────

  Widget _chip(String label, int? key, {Color? color}) {
    final selected = _selectedCategoryId == key;
    final c = color ?? Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () => setState(() { _selectedCategoryId = key; _page = 0; }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? c : const Color(0xFFD1D5DB)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF374151))),
      ),
    );
  }

  // ── Sortable header cell ────────────────────────

  Widget _headerCell(String label, String field, {int flex = 1}) {
    final isActive = _sortField == field;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => _setSort(field),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                    color: isActive ? const Color(0xFFDC2626) : const Color(0xFF374151))),
            if (isActive)
              Icon(_sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 12, color: const Color(0xFFDC2626)),
          ],
        ),
      ),
    );
  }

  // ── Page dropdown ───────────────────────────────

  Widget _pageDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _rowsPerPage,
          isDense: true,
          style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
          items: const [
            DropdownMenuItem(value: 10, child: Text('10')),
            DropdownMenuItem(value: 25, child: Text('25')),
            DropdownMenuItem(value: 50, child: Text('50')),
            DropdownMenuItem(value: 100, child: Text('100')),
          ],
          onChanged: (v) => setState(() {
            _rowsPerPage = v ?? 25;
            _page = 0;
          }),
        ),
      ),
    );
  }

  // ── Thumbnail ──────────────────────────────────

  String? _thumbPath(Map<String, dynamic> item) {
    final attachments = item['attachments'] as List<dynamic>?;
    if (attachments == null || attachments.isEmpty) return null;
    return attachments.first['thumbnailPath'] as String?;
  }

  Widget _buildThumbnail(Map<String, dynamic> item) {
    final path = _thumbPath(item);
    final isContainer = item['isContainer'] == true;
    final accentColor = isContainer ? const Color(0xFF2563EB) : const Color(0xFFDC2626);
    if (path != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          '${ApiClient.uploadsBaseUrl}$path',
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _iconFallback(isContainer, accentColor),
        ),
      );
    }
    return _iconFallback(isContainer, accentColor);
  }

  Widget _iconFallback(bool isContainer, Color accentColor) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: accentColor.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        isContainer ? Icons.check_box_outline_blank : Icons.circle_outlined,
        size: 18,
        color: accentColor,
      ),
    );
  }

  // ── Row builder ─────────────────────────────────

  Widget _buildRow(Map<String, dynamic> item, bool even) {
    final auth = context.read<AuthProvider>();
    final canManage = auth.isAdmin || auth.isItemAdmin;
    final name = (item['name'] ?? '').toString();
    final barcode = item['barCode']?.toString();
    final categoryName = item['category']?['name']?.toString() ?? '—';
    final location = item['location']?.toString();
    final quantity = item['quantity'] ?? 1;
    final isAvailable = item['availableForAssignment'] == true;
    final assignedTo = item['assignedTo'] as Map<String, dynamic>?;
    final childCount = item['_count']?['contents'] ?? 0;
    final itemId = item['id'] as int;
    final isSelected = _selectedIds.contains(itemId);
    return GestureDetector(
      onLongPress: canManage ? () => _enterSelectionMode(itemId) : null,
      child: InkWell(
        onTap: () {
          if (_selectionMode) {
            _toggleSelect(itemId);
          } else {
            ItemDetailScreen.show(context, itemId).then((_) {
              if (mounted) _fetch();
            });
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: isSelected
              ? const Color(0xFFEEF2FF)
              : even
                  ? Colors.white
                  : const Color(0xFFF9FAFB),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            if (_selectionMode)
              Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleSelect(itemId),
                visualDensity: VisualDensity.compact,
                activeColor: const Color(0xFF7C3AED),
              )
            else ...[
              _buildThumbnail(item),
            ],
            const SizedBox(width: 8),
            Expanded(
              flex: canManage ? 3 : 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(name,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (childCount > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withAlpha(25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('$childCount',
                            style: const TextStyle(fontSize: 10, color: Color(0xFF2563EB), fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ]),
                  if (barcode != null && barcode.isNotEmpty)
                    Text(barcode,
                        style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (assignedTo != null)
                    Text(
                      '${assignedTo['surname'] ?? ''} ${assignedTo['forename'] ?? ''}'.trim(),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF374151)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Expanded(
              flex: canManage ? 2 : 3,
              child: Text(categoryName,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF374151)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              flex: canManage ? 2 : 3,
              child: Text(location ?? '—',
                  style: TextStyle(fontSize: 11, color: location != null ? const Color(0xFF374151) : const Color(0xFFD1D5DB)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (canManage)
              Expanded(
                child: Text('$quantity',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center),
              ),
            if (canManage)
              IconButton(
                icon: Icon(isAvailable ? Icons.visibility : Icons.visibility_off_outlined,
                    size: 16, color: isAvailable ? const Color(0xFF059669) : const Color(0xFFD1D5DB)),
                onPressed: () async {
                  await context.read<ItemProvider>().toggleAvailability(itemId);
                  if (mounted) _fetch();
                },
                tooltip: isAvailable ? 'Απόκρυψη' : 'Διαθέσιμο',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                visualDensity: VisualDensity.compact,
              )
            else
              SizedBox(
                height: 28,
                child: FilledButton.tonal(
                  onPressed: () => _selfAssignItem(item),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Λήψη'),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  // ── Create dialog (kept intact) ─────────────────

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final barcodeCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    bool isContainer = false;
    DateTime? expirationDate;
    int quantity = 1;
    bool autoFilling = false;
    int? selectedCategoryId;
    final depts = context.read<DepartmentProvider>().departments;
    int? selectedDeptId = _deptFilter ?? (depts.isNotEmpty ? depts.first['id'] as int : null);

    Future<void> scanBarcode(StateSetter setSt) async {
      final result = await Navigator.of(context, rootNavigator: true).push<ScanResult>(
        MaterialPageRoute(builder: (_) => const ScannerScreen()),
      );
      if (result == null || !mounted) return;
      barcodeCtrl.text = result.value;
      await _autoFillFromBarcode(barcodeCtrl.text.trim(), setSt, nameCtrl, descCtrl, locationCtrl, (v) => isContainer = v, (v) => expirationDate = v, () => autoFilling, (v) => autoFilling = v);
    }

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
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(labelText: 'Ποσότητα'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => quantity = int.tryParse(v) ?? 1,
                  controller: TextEditingController(text: '1'),
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
                final data = <String, dynamic>{'name': nameCtrl.text.trim(), 'isContainer': isContainer, 'quantity': quantity, 'departmentId': selectedDeptId};
                if (barcodeCtrl.text.isNotEmpty) data['barCode'] = barcodeCtrl.text.trim();
                if (locationCtrl.text.isNotEmpty) data['location'] = locationCtrl.text.trim();
                if (descCtrl.text.isNotEmpty) data['description'] = descCtrl.text.trim();
                if (expirationDate != null) data['expirationDate'] = expirationDate!.toIso8601String();
                if (selectedCategoryId != null) data['categoryId'] = selectedCategoryId;
                final err = await context.read<ItemProvider>().create(data);
                if (ctx.mounted) Navigator.pop(ctx);
                if (err != null) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                } else {
                  _fetch();
                }
              },
              child: const Text('Δημιουργία'),
            ),
          ],
        ),
      ),
    );
  }

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

  // ── Scanner ──────────────────────────────────────

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

  void _showManualEntryDialog() {
    bool isQr = true;
    String selectedValue = '';
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
                final id = item['id']?.toString() ?? '';
                final name = (item['name'] ?? '').toString().toLowerCase();
                return id.startsWith(q) || name.contains(q);
              } else {
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
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFFDC2626))
                              .withAlpha(25),
                          child: Icon(
                            isContainer ? Icons.check_box_outline_blank : Icons.circle_outlined,
                            color: isContainer
                                ? const Color(0xFF2563EB)
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
      await _loadMyEquipment();
      await _fetch();
    }
  }

  // ── Build ────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final name = auth.displayName.isNotEmpty ? auth.displayName : (auth.user?['eame'] ?? 'User');
    final canManage = auth.isAdmin || auth.isItemAdmin;
    final processed = _processed;
    final totalPages = (processed.length / _rowsPerPage).ceil();
    final pageStart = _page * _rowsPerPage;
    final pageEnd = (pageStart + _rowsPerPage).clamp(0, processed.length);
    final pageItems = processed.sublist(pageStart, pageEnd);
    final cats = context.watch<CategoryProvider>().categories;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // ── Top bar ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(children: [
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
                                      Icon(Icons.directions_car, size: 12, color: Color(0xFF9A3412)),
                                      const SizedBox(width: 3),
                                      Text(
                                        '$_myVehiclesCount',
                                        style: TextStyle(
                                            fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF9A3412)),
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
                    const Spacer(),
                    if (canManage) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => context.push('/items/csv'),
                        icon: Icon(Icons.settings, size: 22, color: cs.primary),
                        tooltip: 'Εισαγωγή / Εξαγωγή CSV',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
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
                  ]),
                ),

                // ── Search + filter toggle ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: canManage ? 'Αναζήτηση αντικειμένων...' : 'Αναζήτηση διαθέσιμου εξοπλισμού...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _search.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() { _search = ''; _page = 0; });
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() { _search = v; _page = 0; }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: (_filtersExpanded || _activeFilterCount > 0)
                                ? cs.primary.withAlpha(15)
                                : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: (_filtersExpanded || _activeFilterCount > 0)
                                  ? cs.primary.withAlpha(60)
                                  : const Color(0xFFE5E7EB),
                            ),
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 20,
                                color: (_filtersExpanded || _activeFilterCount > 0)
                                    ? cs.primary
                                    : const Color(0xFF6B7280),
                              ),
                              if (_activeFilterCount > 0)
                                Positioned(
                                  right: -4, top: -4,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFC62828),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '$_activeFilterCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Collapsible filters ─────────────
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: _filtersExpanded
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                              child: _buildDeptFilter(),
                            ),
                            if (cats.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: SizedBox(
                                  height: 34,
                                  child: ListView(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    children: [
                                      _chip('Όλα (${_processed.length})', null),
                                      const SizedBox(width: 6),
                                      ...cats.map((c) {
                                        final catId = c['id'] as int;
                                        return Padding(
                                          padding: const EdgeInsets.only(right: 6),
                                          child: _chip(
                                            '${c['name']} (${_countCat(catId)})',
                                            catId,
                                            color: const Color(0xFF7C3AED),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),

                // ── Table ──
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : processed.isEmpty
                          ? Center(
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.inventory_2_outlined, size: 64, color: const Color(0xFFD1D5DB)),
                                const SizedBox(height: 12),
                                Text('Δεν βρέθηκαν αντικείμενα',
                                    style: tt.bodyLarge?.copyWith(color: const Color(0xFF6B7280))),
                              ]),
                            )
                          : Column(children: [
                              // ── Pagination ──
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                child: Row(children: [
                                  Text('${processed.length} αντικείμενα',
                                      style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
                                  const Spacer(),
                                  const Text('Γραμμές: ', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                                  _pageDropdown(),
                                  const SizedBox(width: 12),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_left, size: 20),
                                    onPressed: _page > 0 ? () => setState(() => _page--) : null,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  Text('${_page + 1} / ${totalPages.clamp(1, 999)}',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right, size: 20),
                                    onPressed: _page < totalPages - 1 ? () => setState(() => _page++) : null,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ]),
                              ),

                              // ── Header ──
                              Container(
                                color: const Color(0xFFEEF0F4),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                child: Row(children: [
                                  if (_selectionMode)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Checkbox(
                                        value: pageItems.isNotEmpty &&
                                            pageItems.every((i) => _selectedIds.contains(i['id'] as int)),
                                        tristate: false,
                                        onChanged: (_) => _toggleSelectAll(pageItems),
                                        visualDensity: VisualDensity.compact,
                                        activeColor: const Color(0xFF7C3AED),
                                      ),
                                    )
                                  else
                                    const SizedBox(width: 8),
                                  _headerCell('Όνομα', 'name', flex: canManage ? 3 : 4),
                                  _headerCell('Κατ.', 'category', flex: canManage ? 2 : 3),
                                  _headerCell('Τοποθεσία', 'location', flex: canManage ? 2 : 3),
                                  if (canManage) _headerCell('Ποσ.', 'quantity'),
                                  SizedBox(width: canManage ? 32 : 80),
                                ]),
                              ),

                              // ── Rows ──
                              Expanded(
                                child: RefreshIndicator(
                                  onRefresh: _fetch,
                                  child: ListView.builder(
                                    padding: const EdgeInsets.only(bottom: 120),
                                    itemCount: pageItems.length,
                                    itemBuilder: (context, i) => _buildRow(pageItems[i], i.isEven),
                                  ),
                                ),
                              ),
                            ]),
                ),
              ],
            ),
          ),
          // ── Bulk action bar ──
          if (canManage) _buildBulkBar(),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'scan',
            onPressed: _openScanner,
            child: const Icon(Icons.qr_code_scanner),
          ),
          const SizedBox(height: 12),
          if (canManage && !_selectionMode)
            FloatingActionButton(
              heroTag: 'create',
              onPressed: _showCreateDialog,
              child: const Icon(Icons.add),
            ),
        ],
      ),
    );
  }

  Widget _buildBulkBar() {
    return AnimatedSlide(
      offset: _selectionMode ? Offset.zero : const Offset(0, 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: _selectionMode ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1B4B),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withAlpha(60),
                    blurRadius: 16,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                onPressed: _exitSelectionMode,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              const SizedBox(width: 6),
              Text(
                '${_selectedIds.length} επιλεγμένα',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const Spacer(),
              _BulkAction(
                icon: Icons.visibility_outlined,
                label: 'Ορατότητα',
                onTap: _bulkToggleAvailability,
              ),
              _BulkAction(
                icon: Icons.delete_outline,
                label: 'Διαγραφή',
                color: const Color(0xFFEF4444),
                onTap: _bulkDelete,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _BulkAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _BulkAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
