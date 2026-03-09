import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/item_provider.dart';
import '../services/api_client.dart';

/// Full detail view for a single item.
/// Shows item info, assigned user, container contents, edit/delete actions.
class ItemDetailScreen extends StatefulWidget {
  final int itemId;
  const ItemDetailScreen({super.key, required this.itemId});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  final _api = ApiClient();
  Map<String, dynamic>? _item;
  List<dynamic> _allUsers = [];
  List<dynamic> _allContainers = [];
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
        _api.get('/items?'), // all items for container picker
      ]);
      if (results[0].statusCode == 200 && mounted) {
        _item = jsonDecode(results[0].body);
      }
      if (results[1].statusCode == 200) {
        _allUsers = jsonDecode(results[1].body);
      }
      if (results[2].statusCode == 200) {
        final all = jsonDecode(results[2].body) as List;
        _allContainers = all.where((i) => i['isContainer'] == true && i['id'] != widget.itemId).toList();
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
    DateTime? expirationDate;
    if (_item!['expirationDate'] != null) {
      expirationDate = DateTime.tryParse(_item!['expirationDate']);
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Edit Item'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: barcodeCtrl,
                    decoration: const InputDecoration(labelText: 'Barcode', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationCtrl,
                    decoration: const InputDecoration(labelText: 'Location', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Is Container'),
                    subtitle: const Text('Can hold other items'),
                    value: isContainer,
                    onChanged: (v) => setSt(() => isContainer = v),
                  ),
                  SwitchListTile(
                    title: const Text('Available for Assignment'),
                    value: availableForAssignment,
                    onChanged: (v) => setSt(() => availableForAssignment = v),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(expirationDate != null
                        ? 'Expires: ${expirationDate!.day}/${expirationDate!.month}/${expirationDate!.year}'
                        : 'No expiration date'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.calendar_today, size: 20),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              firstDate: DateTime(2020),
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
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
                };
                final err = await context.read<ItemProvider>().update(widget.itemId, data);
                if (ctx.mounted) Navigator.pop(ctx);
                if (err != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                } else {
                  _load();
                }
              },
              child: const Text('Save'),
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
        title: const Text('Delete Item'),
        content: const Text('Are you sure? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final err = await context.read<ItemProvider>().deleteItem(widget.itemId);
              if (ctx.mounted) Navigator.pop(ctx);
              if (err != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
              } else if (mounted) {
                context.pop();
              }
            },
            child: const Text('Delete'),
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
          title: const Text('Assign to User'),
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
                          'Currently: ${currentAssigned['forename']} ${currentAssigned['surname']}',
                          style: const TextStyle(color: Color(0xFF059669)),
                        ),
                      ],
                    ),
                  ),
                Autocomplete<Map<String, dynamic>>(
                  displayStringForOption: (u) =>
                      '${u['forename'] ?? ''} ${u['surname'] ?? ''} (${u['ename'] ?? ''})'.trim(),
                  optionsBuilder: (textEditingValue) {
                    final q = textEditingValue.text.toLowerCase();
                    final opts = _allUsers.cast<Map<String, dynamic>>();
                    if (q.isEmpty) return opts;
                    return opts.where((u) {
                      final name = '${u['forename'] ?? ''} ${u['surname'] ?? ''}'.toLowerCase();
                      final ename = (u['ename'] ?? '').toString().toLowerCase();
                      return name.contains(q) || ename.contains(q);
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
                        labelText: 'Search user…',
                        prefixIcon: Icon(Icons.person_search),
                        border: OutlineInputBorder(),
                      ),
                    );
                  },
                ),
                if (selectedUserName != null) ...[
                  const SizedBox(height: 8),
                  Text('Selected: $selectedUserName', style: const TextStyle(fontWeight: FontWeight.w500)),
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
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User unassigned')));
                      _load();
                    }
                  }
                },
                child: const Text('Unassign', style: TextStyle(color: Colors.red)),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User assigned')));
                          _load();
                        }
                      }
                    },
              child: const Text('Assign'),
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
          title: const Text('Move to Container'),
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
                        Text('Currently in: ${_item!['containedBy']['name']}',
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
                        labelText: 'Search container…',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    );
                  },
                ),
                if (selectedContainerName != null) ...[
                  const SizedBox(height: 8),
                  Text('Target: $selectedContainerName', style: const TextStyle(fontWeight: FontWeight.w500)),
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
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed from container')));
                      _load();
                    }
                  }
                },
                child: const Text('Remove from container', style: TextStyle(color: Colors.red)),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Moved to container')));
                          _load();
                        }
                      }
                    },
              child: const Text('Move'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final canManage = _canManage;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(_item?['name'] ?? 'Item'),
        actions: [
          if (canManage) ...[
            IconButton(icon: const Icon(Icons.edit), onPressed: _item != null ? _editItem : null, tooltip: 'Edit'),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _item != null ? _deleteItem : null,
              tooltip: 'Delete',
              color: Colors.red,
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _item == null
              ? const Center(child: Text('Item not found'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _buildInfoCard(tt, cs),
                      const SizedBox(height: 16),
                      _buildAssignedUserCard(tt, cs, canManage),
                      const SizedBox(height: 16),
                      if (_item!['isContainer'] == true) ...[
                        _buildContentsCard(tt, cs),
                        const SizedBox(height: 16),
                      ],
                      _buildContainerCard(tt, cs, canManage),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
    );
  }

  // ── Info card ──

  Widget _buildInfoCard(TextTheme tt, ColorScheme cs) {
    final isContainer = _item!['isContainer'] == true;
    final expDate = _item!['expirationDate'];
    final isExpired = expDate != null && DateTime.tryParse(expDate)?.isBefore(DateTime.now()) == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (isContainer ? const Color(0xFF7C3AED) : const Color(0xFF2563EB)).withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isContainer ? Icons.inventory : Icons.build_outlined,
                    color: isContainer ? const Color(0xFF7C3AED) : const Color(0xFF2563EB),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_item!['name'] ?? '', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      if (isContainer)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C3AED).withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Container', style: TextStyle(fontSize: 11, color: Color(0xFF7C3AED), fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            _infoRow(Icons.qr_code, 'ID (QR)', '#${_item!['id']}'),
            if (_item!['barCode'] != null) _infoRow(Icons.barcode_reader, 'Barcode', _item!['barCode']),
            if (_item!['location'] != null) _infoRow(Icons.location_on_outlined, 'Location', _item!['location']),
            if (_item!['description'] != null && (_item!['description'] as String).isNotEmpty)
              _infoRow(Icons.description_outlined, 'Description', _item!['description']),
            _infoRow(Icons.calendar_today, 'Created', _formatDate(_item!['createdAt'])),
            if (expDate != null)
              _infoRow(
                isExpired ? Icons.warning_amber : Icons.event,
                'Expires',
                _formatDate(expDate),
                valueColor: isExpired ? Colors.red : null,
              ),
            if (_item!['availableForAssignment'] == true)
              _infoRow(Icons.assignment_turned_in, 'Available for Assignment', 'Yes', valueColor: const Color(0xFF059669)),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF6B7280)),
          const SizedBox(width: 10),
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13))),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }

  // ── Assigned user card ──

  Widget _buildAssignedUserCard(TextTheme tt, ColorScheme cs, bool canManage) {
    final assigned = _item!['assignedTo'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_pin, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('Assigned User', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                if (canManage)
                  TextButton.icon(
                    icon: Icon(assigned != null ? Icons.swap_horiz : Icons.person_add_alt_1, size: 18),
                    label: Text(assigned != null ? 'Change' : 'Assign'),
                    onPressed: _showAssignUserDialog,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (assigned != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withAlpha(15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF059669).withAlpha(40)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF059669),
                      child: Text(
                        (assigned['forename'] ?? 'U')[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
                          if (assigned['ename'] != null)
                            Text(assigned['ename'], style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_off_outlined, color: Colors.grey.shade400, size: 20),
                    const SizedBox(width: 8),
                    Text('No user assigned', style: TextStyle(color: Colors.grey.shade500)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Container contents card (only if isContainer) ──

  Widget _buildContentsCard(TextTheme tt, ColorScheme cs) {
    final contents = (_item!['contents'] as List<dynamic>?) ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inbox, size: 20, color: Color(0xFF7C3AED)),
                const SizedBox(width: 8),
                Text('Contents', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${contents.length} items', style: const TextStyle(fontSize: 12, color: Color(0xFF7C3AED), fontWeight: FontWeight.w500)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (contents.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inbox_outlined, color: Colors.grey.shade400, size: 20),
                    const SizedBox(width: 8),
                    Text('Empty container', style: TextStyle(color: Colors.grey.shade500)),
                  ],
                ),
              )
            else
              ...contents.map((child) {
                final childIsContainer = child['isContainer'] == true;
                final childAssigned = child['assignedTo'];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      childIsContainer ? Icons.inventory : Icons.build_outlined,
                      color: childIsContainer ? const Color(0xFF7C3AED) : const Color(0xFF2563EB),
                    ),
                    title: Text(child['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (child['barCode'] != null) Text('Barcode: ${child['barCode']}', style: tt.bodySmall),
                        if (childAssigned != null)
                          Text(
                            'Assigned: ${childAssigned['forename']} ${childAssigned['surname']}',
                            style: tt.bodySmall?.copyWith(color: const Color(0xFF059669)),
                          ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    tileColor: Colors.grey.shade50,
                    onTap: () => context.push('/items/${child['id']}'),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ── Container placement card ──

  Widget _buildContainerCard(TextTheme tt, ColorScheme cs, bool canManage) {
    final parent = _item!['containedBy'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.move_to_inbox, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('Container', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                if (canManage)
                  TextButton.icon(
                    icon: const Icon(Icons.drive_file_move_outline, size: 18),
                    label: const Text('Move'),
                    onPressed: _showMoveToContainerDialog,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (parent != null)
              ListTile(
                leading: const Icon(Icons.inventory, color: Color(0xFF7C3AED)),
                title: Text(parent['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right, size: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: const Color(0xFF7C3AED).withAlpha(10),
                onTap: () => context.push('/items/${parent['id']}'),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.all_inbox_outlined, color: Colors.grey.shade400, size: 20),
                    const SizedBox(width: 8),
                    Text('Not inside any container', style: TextStyle(color: Colors.grey.shade500)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
