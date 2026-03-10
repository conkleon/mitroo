import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';

/// Reusable bottom sheet that shows the user's assigned equipment with
/// the ability to return (self-unassign) items.
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

class _MyEquipmentSheetState extends State<MyEquipmentSheet> {
  late List<Map<String, dynamic>> _items;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.equipment);
  }

  Future<void> _returnItem(Map<String, dynamic> item) async {
    final itemId = item['id'] as int;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Επιστροφή Εξοπλισμού'),
        content: Text('Επιστροφή "${item['name']}";'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
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
            SnackBar(content: Text(body['error'] ?? 'Αποτυχία επιστροφής')),
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
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: cs.primary, size: 22),
              const SizedBox(width: 8),
              Text('Ο Εξοπλισμός Μου', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primary.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_items.length}',
                  style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(Icons.check_circle_outline, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 8),
                  Text('Κανένας εξοπλισμός', style: tt.bodyMedium?.copyWith(color: const Color(0xFF6B7280))),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final item = _items[i];
                  final itemId = item['id'] as int;
                  final isBusy = _busy.contains(itemId);
                  final isExpired = item['expirationDate'] != null &&
                      DateTime.tryParse(item['expirationDate'] ?? '')?.isBefore(DateTime.now()) == true;

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: isExpired ? Colors.red.shade200 : const Color(0xFFE5E7EB)),
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
                            item['isContainer'] == true ? Icons.inventory_2 : Icons.build_outlined,
                            color: cs.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['name'] ?? '', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                              if (item['barCode'] != null)
                                Text(item['barCode'].toString(), style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
                              if (item['location'] != null)
                                Text(item['location'].toString(), style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
                            ],
                          ),
                        ),
                        if (isExpired)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('Έληξε', style: TextStyle(color: Colors.red.shade700, fontSize: 10, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        // View detail
                        IconButton(
                          icon: const Icon(Icons.open_in_new, size: 18),
                          tooltip: 'Λεπτομέρειες',
                          color: const Color(0xFF6B7280),
                          onPressed: () {
                            Navigator.pop(context);
                            GoRouter.of(context).push('/items/$itemId');
                          },
                        ),
                        // Return button
                        IconButton(
                          icon: isBusy
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : Icon(Icons.assignment_return, size: 18, color: Colors.red.shade600),
                          tooltip: 'Επιστροφή',
                          onPressed: isBusy ? null : () => _returnItem(item),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
