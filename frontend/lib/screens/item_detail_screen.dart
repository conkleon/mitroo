import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:ui' as ui;
import '../providers/auth_provider.dart';
import '../providers/item_provider.dart';
import '../providers/category_provider.dart';
import '../providers/department_provider.dart';
import '../services/api_client.dart';
import '../services/download_helper.dart';
import '../widgets/image_gallery_card.dart';

/// Detail view for a single item shown as a modal bottom sheet.
class ItemDetailScreen extends StatefulWidget {
  final int itemId;
  const ItemDetailScreen({super.key, required this.itemId});

  /// Show item detail as a modal bottom sheet dialog.
  static Future<bool?> show(BuildContext context, int itemId) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ItemDetailScreen(itemId: itemId),
    );
  }

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  final _api = ApiClient();
  Map<String, dynamic>? _item;
  List<dynamic> _allUsers = [];
  List<dynamic> _allContainers = [];
  List<dynamic> _comments = [];
  List<dynamic> _allServices = [];
  final _commentCtrl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.get('/items/${widget.itemId}'),
        _api.get('/users'),
        _api.get('/items?limit=10000'), // all items for container picker
        _api.get('/items/${widget.itemId}/comments'),
        _api.get('/services'),
      ]);
      if (results[0].statusCode == 200 && mounted) {
        _item = jsonDecode(results[0].body);
      }
      if (results[1].statusCode == 200) {
        _allUsers = jsonDecode(results[1].body);
      }
      if (results[2].statusCode == 200) {
        final parsed = jsonDecode(results[2].body);
        final all = (parsed['data'] ?? parsed) as List;
        _allContainers = all.cast<Map<String, dynamic>>().where((i) => i['isContainer'] == true && i['id'] != widget.itemId).toList();
      }
      if (results[3].statusCode == 200) {
        _comments = jsonDecode(results[3].body) as List;
      }
      if (results[4].statusCode == 200) {
        _allServices = jsonDecode(results[4].body) as List;
      }
      // Ensure departments are loaded for the edit dialog
      if (mounted) {
        context.read<DepartmentProvider>().fetchDepartments();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // ── Helpers ──

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '—';
    final local = dt.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }

  bool get _canManage {
    final auth = context.read<AuthProvider>();
    return auth.isAdmin || auth.isItemAdmin;
  }

  // ── Edit item ──

  void _editItem() {
    if (_item == null) return;
    final nameCtrl = TextEditingController(text: _item!['name'] ?? '');
    final descCtrl = TextEditingController(text: _item!['description'] ?? '');
    final barcodeCtrl = TextEditingController(text: _item!['barCode'] ?? '');
    final locationCtrl = TextEditingController(text: _item!['location'] ?? '');
    bool isContainer = _item!['isContainer'] == true;
    bool availableForAssignment = _item!['availableForAssignment'] == true;
    int? selectedCategoryId = _item!['category']?['id'] as int?;
    int? selectedDeptId = _item!['department']?['id'] as int?;
    DateTime? expirationDate;
    if (_item!['expirationDate'] != null) {
      expirationDate = DateTime.tryParse(_item!['expirationDate']);
    }
    final quantityCtrl = TextEditingController(text: '${_item!['quantity'] ?? 1}');

    const gap = SizedBox(height: 14);
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Color(0xFFD1D5DB)),
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: null,
          titlePadding: EdgeInsets.zero,
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withAlpha(15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFFDC2626)),
                      ),
                      const SizedBox(width: 12),
                      const Text('Επεξεργασία Αντικειμένου',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Όνομα',
                      border: inputBorder,
                      enabledBorder: inputBorder,
                      focusedBorder: inputBorder.copyWith(
                        borderSide: BorderSide(color: Theme.of(ctx).colorScheme.primary, width: 1.5),
                      ),
                    ),
                  ),
                  gap,
                  TextField(
                    controller: barcodeCtrl,
                    decoration: InputDecoration(
                      labelText: 'Barcode',
                      border: inputBorder,
                      enabledBorder: inputBorder,
                      focusedBorder: inputBorder.copyWith(
                        borderSide: BorderSide(color: Theme.of(ctx).colorScheme.primary, width: 1.5),
                      ),
                    ),
                  ),
                  gap,
                  TextField(
                    controller: locationCtrl,
                    decoration: InputDecoration(
                      labelText: 'Τοποθεσία',
                      border: inputBorder,
                      enabledBorder: inputBorder,
                      focusedBorder: inputBorder.copyWith(
                        borderSide: BorderSide(color: Theme.of(ctx).colorScheme.primary, width: 1.5),
                      ),
                    ),
                  ),
                  gap,
                  TextField(
                    controller: descCtrl,
                    decoration: InputDecoration(
                      labelText: 'Περιγραφή',
                      border: inputBorder,
                      enabledBorder: inputBorder,
                      focusedBorder: inputBorder.copyWith(
                        borderSide: BorderSide(color: Theme.of(ctx).colorScheme.primary, width: 1.5),
                      ),
                    ),
                    maxLines: 3,
                  ),
                  gap,
                  Builder(
                    builder: (_) {
                      final depts = context.read<DepartmentProvider>().departments;
                      return DropdownButtonFormField<int>(
                        value: selectedDeptId,
                        decoration: InputDecoration(
                          labelText: 'Τμήμα',
                          border: inputBorder,
                          enabledBorder: inputBorder,
                          focusedBorder: inputBorder.copyWith(
                            borderSide: BorderSide(color: Theme.of(ctx).colorScheme.primary, width: 1.5),
                          ),
                        ),
                        items: depts.map<DropdownMenuItem<int>>((d) => DropdownMenuItem(
                          value: d['id'] as int,
                          child: Text(d['name'] ?? ''),
                        )).toList(),
                        onChanged: (v) => setSt(() => selectedDeptId = v),
                      );
                    },
                  ),
                  gap,
                  Builder(
                    builder: (_) {
                      final cats = context.read<CategoryProvider>().categories;
                      return DropdownButtonFormField<int?>(
                        value: selectedCategoryId,
                        decoration: InputDecoration(
                          labelText: 'Κατηγορία',
                          border: inputBorder,
                          enabledBorder: inputBorder,
                          focusedBorder: inputBorder.copyWith(
                            borderSide: BorderSide(color: Theme.of(ctx).colorScheme.primary, width: 1.5),
                          ),
                        ),
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
                  gap,
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                              initialDate: expirationDate ?? DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) setSt(() => expirationDate = picked);
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Ημερομηνία λήξης',
                              border: inputBorder,
                              enabledBorder: inputBorder,
                              focusedBorder: inputBorder.copyWith(
                                borderSide: BorderSide(color: Theme.of(ctx).colorScheme.primary, width: 1.5),
                              ),
                              suffixIcon: expirationDate != null
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () => setSt(() => expirationDate = null),
                                    )
                                  : const Icon(Icons.calendar_today_outlined, size: 20),
                            ),
                            child: Text(
                              expirationDate != null
                                  ? '${expirationDate!.day}/${expirationDate!.month}/${expirationDate!.year}'
                                  : 'Δεν έχει οριστεί',
                              style: TextStyle(
                                color: expirationDate != null ? null : Color(0xFF6B7280),
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: TextField(
                          controller: quantityCtrl,
                          decoration: InputDecoration(
                            labelText: 'Ποσότητα',
                            border: inputBorder,
                            enabledBorder: inputBorder,
                            focusedBorder: inputBorder.copyWith(
                              borderSide: BorderSide(color: Theme.of(ctx).colorScheme.primary, width: 1.5),
                            ),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  gap,
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Color(0xFFD1D5DB)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.inventory_2, size: 18, color: Color(0xFF374151)),
                            const SizedBox(width: 10),
                            const Expanded(child: Text('Κουτί', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                            const Text('Μπορεί να περιέχει αντικείμενα', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                            const SizedBox(width: 10),
                            Switch(
                              value: isContainer,
                              onChanged: (v) => setSt(() => isContainer = v),
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        Row(
                          children: [
                            Icon(Icons.assignment_outlined, size: 18, color: Color(0xFF374151)),
                            const SizedBox(width: 10),
                            const Expanded(child: Text('Διαθέσιμο για ανάθεση', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                            Switch(
                              value: availableForAssignment,
                              onChanged: (v) => setSt(() => availableForAssignment = v),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final data = <String, dynamic>{
                  'name': nameCtrl.text.trim(),
                  'isContainer': isContainer,
                  'availableForAssignment': availableForAssignment,
                  'barCode': barcodeCtrl.text.isNotEmpty ? barcodeCtrl.text.trim() : null,
                  'location': locationCtrl.text.isNotEmpty ? locationCtrl.text.trim() : null,
                  'description': descCtrl.text.isNotEmpty ? descCtrl.text.trim() : null,
                  'expirationDate': expirationDate?.toIso8601String(),
                  'quantity': int.tryParse(quantityCtrl.text) ?? 1,
                  'categoryId': selectedCategoryId,
                  'departmentId': selectedDeptId,
                };
                final err = await context.read<ItemProvider>().update(widget.itemId, data);
                if (ctx.mounted) Navigator.pop(ctx);
                if (err != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                } else {
                  _load();
                }
              },
              child: const Text('Αποθήκευση'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Delete item ──

  void _deleteItem() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή Αντικειμένου'),
        content: const Text('Είστε σίγουροι; Δεν μπορεί να αναιρεθεί.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Color(0xFFDC2626)),
            onPressed: () async {
              final err = await context.read<ItemProvider>().deleteItem(widget.itemId);
              if (ctx.mounted) Navigator.pop(ctx);
              if (err != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
              } else if (mounted) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
  }

  // ── Assign to user ──

  void _showAssignUserDialog() {
    int? selectedUserId;
    String? selectedUserName;
    final currentAssigned = _item?['assignedTo'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Ανάθεση σε Χρήστη'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (currentAssigned != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.person, size: 16, color: Color(0xFF059669)),
                        const SizedBox(width: 6),
                        Text(
                          'Τρέχων: ${currentAssigned['forename']} ${currentAssigned['surname']}',
                          style: const TextStyle(color: Color(0xFF059669)),
                        ),
                      ],
                    ),
                  ),
                Autocomplete<Map<String, dynamic>>(
                  displayStringForOption: (u) =>
                      '${u['forename'] ?? ''} ${u['surname'] ?? ''} (${u['eame'] ?? ''})'.trim(),
                  optionsBuilder: (textEditingValue) {
                    final q = textEditingValue.text.toLowerCase();
                    final opts = _allUsers.cast<Map<String, dynamic>>();
                    if (q.isEmpty) return opts;
                    return opts.where((u) {
                      final name = '${u['forename'] ?? ''} ${u['surname'] ?? ''}'.toLowerCase();
                      final eame = (u['eame'] ?? '').toString().toLowerCase();
                      return name.contains(q) || eame.contains(q);
                    });
                  },
                  onSelected: (u) {
                    setSt(() {
                      selectedUserId = u['id'] as int;
                      selectedUserName = '${u['forename']} ${u['surname']}';
                    });
                  },
                  fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Αναζήτηση χρήστη…',
                        prefixIcon: Icon(Icons.person_search),
                        border: OutlineInputBorder(),
                      ),
                    );
                  },
                ),
                if (selectedUserName != null) ...[
                  const SizedBox(height: 8),
                  Text('Επιλογή: $selectedUserName', style: const TextStyle(fontWeight: FontWeight.w500)),
                ],
              ],
            ),
          ),
          actions: [
            if (currentAssigned != null)
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final err = await context.read<ItemProvider>().unassignUser(widget.itemId);
                  if (mounted) {
                    if (err != null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ο χρήστης αφαιρέθηκε')));
                      _load();
                    }
                  }
                },
                child: const Text('Αφαίρεση', style: TextStyle(color: Color(0xFFDC2626))),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
            FilledButton(
              onPressed: selectedUserId == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      final err = await context.read<ItemProvider>().assignToUser(widget.itemId, selectedUserId!);
                      if (mounted) {
                        if (err != null) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ανάθεση επιτυχής')));
                          _load();
                        }
                      }
                    },
              child: const Text('Ανάθεση'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Move to container dialog ──

  void _showMoveToContainerDialog() {
    int? selectedContainerId;
    String? selectedContainerName;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Μετακίνηση σε Κουτί'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_item?['containedBy'] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.inventory, size: 16, color: Color(0xFF7C3AED)),
                        const SizedBox(width: 6),
                        Text('Τρέχον: ${_item!['containedBy']['name']}',
                            style: const TextStyle(color: Color(0xFF7C3AED))),
                      ],
                    ),
                  ),
                Autocomplete<Map<String, dynamic>>(
                  displayStringForOption: (c) => c['name'] ?? '',
                  optionsBuilder: (textEditingValue) {
                    final q = textEditingValue.text.toLowerCase();
                    final opts = _allContainers.cast<Map<String, dynamic>>();
                    if (q.isEmpty) return opts;
                    return opts.where((c) => (c['name'] ?? '').toString().toLowerCase().contains(q));
                  },
                  onSelected: (c) {
                    setSt(() {
                      selectedContainerId = c['id'] as int;
                      selectedContainerName = c['name'];
                    });
                  },
                  fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Αναζήτηση κουτιού…',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    );
                  },
                ),
                if (selectedContainerName != null) ...[
                  const SizedBox(height: 8),
                  Text('Προορισμός: $selectedContainerName', style: const TextStyle(fontWeight: FontWeight.w500)),
                ],
              ],
            ),
          ),
          actions: [
            if (_item?['containedBy'] != null)
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final err = await context.read<ItemProvider>().moveToContainer(widget.itemId, null);
                  if (mounted) {
                    if (err != null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Αφαιρέθηκε από κουτί')));
                      _load();
                    }
                  }
                },
                child: const Text('Αφαίρεση από κουτί', style: TextStyle(color: Color(0xFFDC2626))),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
            FilledButton(
              onPressed: selectedContainerId == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      final err = await context.read<ItemProvider>().moveToContainer(widget.itemId, selectedContainerId!);
                      if (mounted) {
                        if (err != null) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Μετακινήθηκε σε κουτί')));
                          _load();
                        }
                      }
                    },
              child: const Text('Μετακίνηση'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Self-assign / unassign ──

  Future<void> _selfAssign() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Λήψη Εξοπλισμού'),
        content: Text('Ανάθεση του "${_item?['name']}" σε εσάς;'),
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

    final err = await context.read<ItemProvider>().selfAssign(widget.itemId);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Το "${_item?['name']}" ανατέθηκε σε εσάς')),
      );
      _load();
    }
  }

  Future<void> _selfUnassign() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Επιστροφή'),
        content: Text('Επιστροφή του "${_item?['name']}";'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Color(0xFFDC2626)),
            child: const Text('Επιστροφή'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final err = await context.read<ItemProvider>().selfUnassign(widget.itemId);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Το "${_item?['name']}" επιστράφηκε')),
      );
      _load();
    }
  }

  // ── Service assignments ──

  Future<void> _showAssignToServiceDialog() async {
    if (_allServices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Δεν υπάρχουν διαθέσιμες υπηρεσίες')),
      );
      return;
    }

    int? selectedServiceId;
    int? selectedUserId;
    final commentCtrl = TextEditingController();

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: const Text('Ανάθεση σε Υπηρεσία'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'Υπηρεσία', border: OutlineInputBorder()),
                    items: _allServices.map<DropdownMenuItem<int>>((s) {
                      return DropdownMenuItem<int>(value: s['id'] as int, child: Text(s['name'] as String? ?? ''));
                    }).toList(),
                    onChanged: (v) => setS(() => selectedServiceId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'Χρήστης', border: OutlineInputBorder()),
                    items: _allUsers.map<DropdownMenuItem<int>>((u) {
                      final name = '${u['forename'] ?? ''} ${u['surname'] ?? ''}'.trim();
                      return DropdownMenuItem<int>(value: u['id'] as int, child: Text(name));
                    }).toList(),
                    onChanged: (v) => setS(() => selectedUserId = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentCtrl,
                    decoration: const InputDecoration(labelText: 'Σχόλιο (προαιρετικό)', border: OutlineInputBorder()),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
              FilledButton(
                onPressed: selectedServiceId != null && selectedUserId != null
                    ? () => Navigator.pop(ctx, true)
                    : null,
                child: const Text('Ανάθεση'),
              ),
            ],
          ),
        ),
      );

      if (confirmed != true || !mounted) return;

      final comment = commentCtrl.text.trim().isEmpty ? null : commentCtrl.text.trim();
      final err = await context.read<ItemProvider>().assignToService(
        selectedServiceId!,
        selectedUserId!,
        widget.itemId,
        comment: comment,
      );
      if (!mounted) return;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Η ανάθεση αποθηκεύτηκε')),
        );
        _load();
      }
    } finally {
      commentCtrl.dispose();
    }
  }

  Future<void> _removeServiceAssignment(int itemServiceId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Αφαίρεση Ανάθεσης'),
        content: const Text('Αφαίρεση αυτής της ανάθεσης από την υπηρεσία;'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Color(0xFFDC2626)),
            child: const Text('Αφαίρεση'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final err = await context.read<ItemProvider>().unassignFromService(itemServiceId, widget.itemId);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Η ανάθεση αφαιρέθηκε')),
      );
      _load();
    }
  }

  // ── QR Code Generation ──

  void _showQrDialog() {
    if (_item == null) return;
    final itemId = _item!['id'].toString();
    final itemName = _item!['name'] ?? 'Αντικείμενο';
    final itemDesc = (_item!['description'] ?? '') as String;
    final repaintKey = GlobalKey();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          title: Row(
            children: [
              Icon(Icons.qr_code, color: Theme.of(ctx).colorScheme.primary),
              const SizedBox(width: 8),
              const Expanded(child: Text('QR Code')),
            ],
          ),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          content: SizedBox(
            width: 280,
            child: RepaintBoundary(
              key: repaintKey,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                      Text(
                        itemName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1C1E),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (itemDesc.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          itemDesc,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF6B7280),
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 16),
                      QrImageView(
                        data: itemId,
                        version: QrVersions.auto,
                        size: 200,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Color(0xFF1A1C1E),
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF1A1C1E),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'ID: #$itemId',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Κλείσιμο'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.save_alt, size: 18),
              label: const Text('Αποθήκευση'),
              onPressed: () async {
                try {
                  final boundary = repaintKey.currentContext
                      ?.findRenderObject() as RenderRepaintBoundary?;
                  if (boundary == null) return;
                  final image = await boundary.toImage(pixelRatio: 3.0);
                  final byteData =
                      await image.toByteData(format: ui.ImageByteFormat.png);
                  if (byteData == null) return;
                  final pngBytes = byteData.buffer.asUint8List();
                  await _saveQrImage(pngBytes, 'qr_item_$itemId.png');
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('QR Code αποθηκεύτηκε')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Σφάλμα: $e')),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveQrImage(Uint8List pngBytes, String filename) async {
    await downloadFile(pngBytes, filename);
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final canManage = _canManage;
    final isContainer = _item?['isContainer'] == true;
    final accentColor = isContainer ? const Color(0xFF7C3AED) : const Color(0xFFDC2626);

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
          _buildHeader(tt, cs, canManage, accentColor),
          // ── Body ──
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _item == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline, size: 48, color: Color(0xFF9CA3AF)),
                            const SizedBox(height: 12),
                            const Text('Αντικείμενο δεν βρέθηκε'),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          children: [
                            _buildQuickInfoRow(tt, cs),
                            const SizedBox(height: 16),
                            _buildDetailsCard(tt, cs),
                            const SizedBox(height: 12),
                            _buildAssignedUserCard(tt, cs, canManage),
                            const SizedBox(height: 12),
                            _buildServiceAssignmentsCard(tt, cs, canManage),
                            const SizedBox(height: 12),
                            if (_item!['isContainer'] == true) ...[
                              _buildContentsCard(tt, cs),
                              const SizedBox(height: 12),
                            ],
                            _buildContainerCard(tt, cs, canManage),
                            const SizedBox(height: 12),
                            ImageGalleryCard(
                              entityParam: 'itemId',
                              entityId: widget.itemId,
                              canManage: canManage,
                            ),
                            const SizedBox(height: 12),
                            _buildCommentsCard(tt, cs, canManage),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ── Header with gradient, drag handle, title & actions ──

  Widget _buildHeader(TextTheme tt, ColorScheme cs, bool canManage, Color accentColor) {
    final isAvailable = _item?['availableForAssignment'] == true;
    final assigned = _item?['assignedTo'];
    final isContainer = _item?['isContainer'] == true;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentColor, accentColor.withAlpha(180)],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                  if (canManage && _item != null) ...[
                    IconButton(
                      icon: const Icon(Icons.qr_code, size: 20),
                      color: Colors.white,
                      onPressed: _showQrDialog,
                      tooltip: 'QR Code',
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      color: Colors.white,
                      onPressed: _editItem,
                      tooltip: 'Επεξεργασία',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: Colors.white,
                      onPressed: _deleteItem,
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
            // Title & badges
            if (_item != null)
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
                        isContainer ? Icons.inventory_2 : Icons.build_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _item!['name'] ?? '',
                            style: tt.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (isContainer)
                                _heroBadge('Κουτί', Icons.inventory_2, Colors.white.withAlpha(30)),
                              if (isAvailable)
                                _heroBadge('Διαθέσιμο', Icons.check_circle_outline, const Color(0xFF34D399).withAlpha(60)),
                              if (assigned != null)
                                _heroBadge(
                                  '${assigned['forename'] ?? ''} ${assigned['surname'] ?? ''}'.trim(),
                                  Icons.person,
                                  Colors.white.withAlpha(30),
                                ),
                            ],
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

  Widget _heroBadge(String text, IconData icon, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Quick info chips row ──

  Widget _buildQuickInfoRow(TextTheme tt, ColorScheme cs) {
    final expDate = _item!['expirationDate'];
    final isExpired = expDate != null && DateTime.tryParse(expDate)?.isBefore(DateTime.now()) == true;
    final qty = _item!['quantity'];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _infoChip(Icons.tag, 'ID: #${_item!['id']}', const Color(0xFF6366F1)),
        if (_item!['department'] != null)
          _infoChip(Icons.business_outlined, _item!['department']['name'], const Color(0xFF0D9488)),
        if (_item!['barCode'] != null)
          _infoChip(Icons.qr_code, _item!['barCode'], const Color(0xFFDC2626)),
        if (_item!['location'] != null)
          _infoChip(Icons.location_on_outlined, _item!['location'], const Color(0xFF0891B2)),
        if (_item!['category'] != null)
          _infoChip(Icons.category_outlined, _item!['category']['name'], const Color(0xFF8B5CF6)),
        if (qty != null && qty > 1)
          _infoChip(Icons.inventory, '×$qty', const Color(0xFF059669)),
        if (expDate != null)
          _infoChip(
            isExpired ? Icons.warning_amber_rounded : Icons.event,
            _formatDate(expDate),
            isExpired ? Color(0xFFDC2626) : const Color(0xFFF59E0B),
          ),
        _infoChip(Icons.calendar_today, _formatDate(_item!['createdAt']), const Color(0xFF6B7280)),
      ],
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  // ── Details card ──

  Widget _buildDetailsCard(TextTheme tt, ColorScheme cs) {
    final qty = _item!['quantity'];
    final expDate = _item!['expirationDate'];
    final isExpired = expDate != null && DateTime.tryParse(expDate)?.isBefore(DateTime.now()) == true;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Color(0xFFE5E7EB)),
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
                  child: const Icon(Icons.info_outline, size: 18, color: Color(0xFF6366F1)),
                ),
                const SizedBox(width: 10),
                Text('Λεπτομέρειες', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 14),
            _detailRow(tt, 'Όνομα', _item!['name'] ?? '—'),
            if (_item!['description'] != null && (_item!['description'] as String).isNotEmpty)
              _detailRow(tt, 'Περιγραφή', _item!['description'], maxLines: 5),
            _detailRow(tt, 'Barcode', _item!['barCode'] ?? '—'),
            _detailRow(tt, 'Τοποθεσία', _item!['location'] ?? '—'),
            _detailRow(tt, 'Ποσότητα', qty != null ? '$qty' : '1'),
            if (expDate != null)
              _detailRow(
                tt,
                'Ημερομηνία λήξης',
                _formatDate(expDate),
                valueColor: isExpired ? Color(0xFFDC2626) : null,
              ),
            if (_item!['category'] != null)
              _detailRow(tt, 'Κατηγορία', _item!['category']['name']),
            _detailRow(tt, 'Τμήμα', _item!['department']?['name'] ?? '—'),
            _detailRow(tt, 'Τύπος', _item!['isContainer'] == true ? 'Κουτί' : 'Αντικείμενο'),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(TextTheme tt, String label, String value, {Color? valueColor, int maxLines = 2}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280), fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value,
              style: tt.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: valueColor ?? const Color(0xFF1F2937),
              ),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── Assigned user card ──

  Widget _buildAssignedUserCard(TextTheme tt, ColorScheme cs, bool canManage) {
    final assigned = _item!['assignedTo'];
    final auth = context.read<AuthProvider>();
    final isMe = assigned != null && assigned['id'] == auth.user?['id'];
    final canTake = !canManage &&
        _item!['availableForAssignment'] == true &&
        assigned == null;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Color(0xFFE5E7EB)),
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
                    color: (assigned != null ? const Color(0xFF059669) : const Color(0xFF6B7280)).withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    assigned != null ? Icons.person : Icons.person_off_outlined,
                    size: 18,
                    color: assigned != null ? const Color(0xFF059669) : const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Ανατεθειμένος Χρήστης', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (canManage)
                  _actionChip(
                    label: assigned != null ? 'Αλλαγή' : 'Ανάθεση',
                    icon: assigned != null ? Icons.swap_horiz : Icons.person_add_alt_1,
                    onTap: _showAssignUserDialog,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (assigned != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [const Color(0xFF059669).withAlpha(10), const Color(0xFF059669).withAlpha(5)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF059669).withAlpha(30)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: const Color(0xFF059669),
                      child: Text(
                        (assigned['forename'] ?? 'U')[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${assigned['forename'] ?? ''} ${assigned['surname'] ?? ''}'.trim(),
                            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (assigned['eame'] != null)
                            Text(assigned['eame'], style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
                        ],
                      ),
                    ),
                    if (isMe)
                      FilledButton.tonalIcon(
                        onPressed: _selfUnassign,
                        icon: const Icon(Icons.assignment_return, size: 16),
                        label: const Text('Επιστροφή', style: TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          backgroundColor: Color(0xFFFEF2F2),
                          foregroundColor: Color(0xFFB91C1C),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        ),
                      ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Color(0xFFE5E7EB), style: BorderStyle.solid),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.person_off_outlined, color: Color(0xFF9CA3AF), size: 28),
                      const SizedBox(height: 6),
                      Text('Κανένας χρήστης', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
                    ],
                  ),
                ),
              ),
            if (canTake) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _selfAssign,
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Λήψη'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionChip({required String label, required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626).withAlpha(10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFDC2626).withAlpha(30)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: const Color(0xFFDC2626)),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFDC2626))),
            ],
          ),
        ),
      ),
    );
  }

  // ── Service assignments card ──

  Widget _buildServiceAssignmentsCard(TextTheme tt, ColorScheme cs, bool canManage) {
    final assignments = (_item!['itemServices'] as List<dynamic>?) ?? [];

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Color(0xFFE5E7EB)),
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
                    color: const Color(0xFF2563EB).withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.miscellaneous_services_outlined, size: 18, color: Color(0xFF2563EB)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text('Αναθέσεις Υπηρεσιών', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
                if (canManage)
                  _actionChip(label: 'Προσθήκη', icon: Icons.add, onTap: _showAssignToServiceDialog),
              ],
            ),
            const SizedBox(height: 14),
            if (assignments.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Color(0xFFE5E7EB)),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.inbox_outlined, color: Color(0xFF9CA3AF), size: 28),
                      const SizedBox(height: 6),
                      Text('Δεν υπάρχουν αναθέσεις', style: tt.bodySmall?.copyWith(color: Color(0xFF6B7280))),
                    ],
                  ),
                ),
              )
            else
              ...assignments.map((a) {
                final service = a['service'] as Map<String, dynamic>? ?? {};
                final user = a['user'] as Map<String, dynamic>? ?? {};
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withAlpha(8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2563EB).withAlpha(25)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(service['name'] ?? '—', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              '${user['forename'] ?? ''} ${user['surname'] ?? ''}'.trim(),
                              style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
                            ),
                            if (a['assignedAt'] != null)
                              Text(
                                _formatDate(a['assignedAt'] as String?),
                                style: tt.labelSmall?.copyWith(color: Color(0xFF9CA3AF)),
                              ),
                            if ((a['comment'] as String?)?.isNotEmpty == true) ...[
                              const SizedBox(height: 4),
                              Text(a['comment'] as String, style: tt.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                            ],
                          ],
                        ),
                      ),
                      if (canManage)
                        IconButton(
                          icon: Icon(Icons.close, size: 18, color: Color(0xFFF87171)),
                          onPressed: () => _removeServiceAssignment(a['id'] as int),
                          tooltip: 'Αφαίρεση',
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

  // ── Container contents card (only if isContainer) ──

  Widget _buildContentsCard(TextTheme tt, ColorScheme cs) {
    final contents = (_item!['contents'] as List<dynamic>?) ?? [];

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Color(0xFFE5E7EB)),
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
                    color: const Color(0xFF7C3AED).withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.inbox, size: 18, color: Color(0xFF7C3AED)),
                ),
                const SizedBox(width: 10),
                Text('Περιεχόμενα', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${contents.length}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7C3AED), fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (contents.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.inbox_outlined, color: Color(0xFF9CA3AF), size: 28),
                      const SizedBox(height: 6),
                      Text('Άδειο κουτί', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
                    ],
                  ),
                ),
              )
            else
              ...contents.asMap().entries.map((entry) {
                final child = entry.value;
                final childIsContainer = child['isContainer'] == true;
                final childAssigned = child['assignedTo'];
                final childColor = childIsContainer ? const Color(0xFF7C3AED) : const Color(0xFFDC2626);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => ItemDetailScreen.show(context, child['id'] as int),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: childColor.withAlpha(6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: childColor.withAlpha(25)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: childColor.withAlpha(15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                childIsContainer ? Icons.inventory : Icons.build_outlined,
                                color: childColor,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(child['name'] ?? '', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                                  if (child['barCode'] != null || childAssigned != null)
                                    const SizedBox(height: 2),
                                  if (child['barCode'] != null)
                                    Text('${child['barCode']}', style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
                                  if (childAssigned != null)
                                    Row(
                                      children: [
                                        const Icon(Icons.person, size: 12, color: Color(0xFF059669)),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${childAssigned['forename']} ${childAssigned['surname']}',
                                          style: tt.bodySmall?.copyWith(color: const Color(0xFF059669), fontSize: 11),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, size: 18, color: Color(0xFF9CA3AF)),
                          ],
                        ),
                      ),
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

  bool get _canComment {
    final auth = context.read<AuthProvider>();
    if (auth.isAdmin || auth.isItemAdmin) return true;
    final assignedToId = _item?['assignedToId'];
    return assignedToId != null && assignedToId == auth.user?['id'];
  }

  Future<void> _addComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      final res = await _api.post('/items/${widget.itemId}/comments', body: {'text': text});
      if (res.statusCode == 201 && mounted) {
        _commentCtrl.clear();
        final commentsRes = await _api.get('/items/${widget.itemId}/comments');
        if (commentsRes.statusCode == 200 && mounted) {
          setState(() => _comments = jsonDecode(commentsRes.body) as List);
        }
      }
    } catch (_) {}
  }

  Future<void> _deleteComment(int commentId) async {
    try {
      final res = await _api.delete('/items/${widget.itemId}/comments/$commentId');
      if (res.statusCode == 200 && mounted) {
        setState(() => _comments.removeWhere((c) => c['id'] == commentId));
      }
    } catch (_) {}
  }

  Widget _buildCommentsCard(TextTheme tt, ColorScheme cs, bool canManage) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Color(0xFFE5E7EB)),
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
                decoration: BoxDecoration(
                  color: Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.chat_bubble_outline, color: Color(0xFF9CA3AF), size: 28),
                      const SizedBox(height: 6),
                      Text('Δεν υπάρχουν σχόλια', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
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
                    decoration: BoxDecoration(
                      color: Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(12),
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
                                  child: Icon(Icons.close, size: 16, color: Color(0xFF9CA3AF)),
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
            if (_canComment) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(14),
                ),
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
          ],
        ),
      ),
    );
  }

  // ── Container placement card ──

  Widget _buildContainerCard(TextTheme tt, ColorScheme cs, bool canManage) {
    final parent = _item!['containedBy'];

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Color(0xFFE5E7EB)),
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
                    color: const Color(0xFF7C3AED).withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.move_to_inbox, size: 18, color: Color(0xFF7C3AED)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Κουτί', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (canManage)
                  _actionChip(
                    label: 'Μετακίνηση',
                    icon: Icons.drive_file_move_outline,
                    onTap: _showMoveToContainerDialog,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (parent != null)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => ItemDetailScreen.show(context, parent['id'] as int),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withAlpha(8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF7C3AED).withAlpha(25)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C3AED).withAlpha(15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.inventory, color: Color(0xFF7C3AED), size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(parent['name'] ?? '', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        Icon(Icons.chevron_right, size: 18, color: Color(0xFF9CA3AF)),
                      ],
                    ),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.all_inbox_outlined, color: Color(0xFF9CA3AF), size: 28),
                      const SizedBox(height: 6),
                      Text('Δεν βρίσκεται σε κουτί', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
