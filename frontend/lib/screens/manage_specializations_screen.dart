import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_client.dart';

/// System-admin screen: list, create & edit specializations.
class ManageSpecializationsScreen extends StatefulWidget {
  const ManageSpecializationsScreen({super.key});

  @override
  State<ManageSpecializationsScreen> createState() => _ManageSpecializationsScreenState();
}

class _ManageSpecializationsScreenState extends State<ManageSpecializationsScreen> {
  final _api = ApiClient();
  List<dynamic> _specs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get('/specializations');
      if (res.statusCode == 200) _specs = jsonDecode(res.body);
    } catch (_) {}
    setState(() => _loading = false);
  }

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final hoursCtrl = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Specialization'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name *', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()), maxLines: 2),
              const SizedBox(height: 12),
              TextField(controller: hoursCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Training Hours', border: OutlineInputBorder())),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final body = <String, dynamic>{
                'name': nameCtrl.text.trim(),
              };
              if (descCtrl.text.isNotEmpty) body['description'] = descCtrl.text.trim();
              body['hoursTraining'] = int.tryParse(hoursCtrl.text) ?? 0;
              try {
                final res = await _api.post('/specializations', body: body);
                if (ctx.mounted) Navigator.pop(ctx);
                if (res.statusCode == 201) {
                  _fetch();
                } else {
                  final err = jsonDecode(res.body)['error'] ?? 'Failed';
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                }
              } catch (e) {
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> spec) {
    final nameCtrl = TextEditingController(text: spec['name'] ?? '');
    final descCtrl = TextEditingController(text: spec['description'] ?? '');
    final hoursCtrl = TextEditingController(text: '${spec['hoursTraining'] ?? 0}');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit ${spec['name']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()), maxLines: 2),
              const SizedBox(height: 12),
              TextField(controller: hoursCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Training Hours', border: OutlineInputBorder())),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final body = <String, dynamic>{
                'name': nameCtrl.text.trim(),
                'hoursTraining': int.tryParse(hoursCtrl.text) ?? 0,
              };
              if (descCtrl.text.isNotEmpty) body['description'] = descCtrl.text.trim();
              try {
                await _api.patch('/specializations/${spec['id']}', body: body);
                if (ctx.mounted) Navigator.pop(ctx);
                _fetch();
              } catch (e) {
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> spec) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${spec['name']}"?'),
        content: const Text('This will remove all user assignments for this specialization.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        final res = await _api.delete('/specializations/${spec['id']}');
        if (res.statusCode == 204) {
          _fetch();
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete')));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text('Manage Specializations', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetch,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                itemCount: _specs.length,
                itemBuilder: (context, i) {
                  final spec = _specs[i] as Map<String, dynamic>;
                  final userCount = spec['_count']?['users'] ?? 0;
                  final childCount = spec['_count']?['children'] ?? 0;
                  final root = spec['root'] as Map<String, dynamic>?;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.school, color: Color(0xFFD97706), size: 22),
                      ),
                      title: Text(spec['name'] ?? '', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        [
                          if (root != null) 'Parent: ${root['name']}',
                          '$userCount users',
                          if (childCount > 0) '$childCount sub-specs',
                          '${spec['hoursTraining'] ?? 0}h training',
                        ].join(' · '),
                        style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _showEditDialog(spec)),
                          IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.red), onPressed: () => _confirmDelete(spec)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
