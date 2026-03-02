import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/item_provider.dart';

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key});

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<ItemProvider>().fetchItems());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final barcodeCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    bool isContainer = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('New Item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 12),
              TextField(controller: barcodeCtrl, decoration: const InputDecoration(labelText: 'Barcode')),
              const SizedBox(height: 12),
              TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: 'Location')),
              const SizedBox(height: 12),
              TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2),
              const SizedBox(height: 8),
              SwitchListTile(title: const Text('Is Container'), value: isContainer, onChanged: (v) => setSt(() => isContainer = v)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final data = <String, dynamic>{'name': nameCtrl.text.trim(), 'isContainer': isContainer};
                if (barcodeCtrl.text.isNotEmpty) data['barCode'] = barcodeCtrl.text.trim();
                if (locationCtrl.text.isNotEmpty) data['location'] = locationCtrl.text.trim();
                if (descCtrl.text.isNotEmpty) data['description'] = descCtrl.text.trim();
                final err = await context.read<ItemProvider>().create(data);
                if (ctx.mounted) Navigator.pop(ctx);
                if (err != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                }
              },
              child: const Text('Create'),
            ),
          ],
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

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => prov.fetchItems(),
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
                      hintText: 'Search items...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          context.read<ItemProvider>().fetchItems();
                        },
                      ),
                    ),
                    onSubmitted: (v) => context.read<ItemProvider>().fetchItems(search: v),
                  ),
                ),
              ),
              // ── Section header ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2, size: 20, color: cs.primary),
                      const SizedBox(width: 8),
                      Text('Items', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text('${prov.items.length} total', style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
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
                        Text('No items found', style: tt.bodyLarge?.copyWith(color: Colors.grey)),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final item = prov.items[i];
                        final parent = item['containedBy'];
                        final childCount = item['_count']?['contents'] ?? 0;
                        final isContainer = item['isContainer'] == true;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {},
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
                                          '$childCount inside',
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF7C3AED), fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: prov.items.length,
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
}
