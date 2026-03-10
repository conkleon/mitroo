import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/department_provider.dart';

class DepartmentsScreen extends StatefulWidget {
  const DepartmentsScreen({super.key});

  @override
  State<DepartmentsScreen> createState() => _DepartmentsScreenState();
}

class _DepartmentsScreenState extends State<DepartmentsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<DepartmentProvider>().fetchDepartments());
  }

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Νέο Τμήμα'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Όνομα', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Περιγραφή', border: OutlineInputBorder()), maxLines: 2),
            const SizedBox(height: 12),
            TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: 'Τοποθεσία', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () async {
              final data = <String, dynamic>{'name': nameCtrl.text.trim()};
              if (descCtrl.text.isNotEmpty) data['description'] = descCtrl.text.trim();
              if (locationCtrl.text.isNotEmpty) data['location'] = locationCtrl.text.trim();
              final err = await context.read<DepartmentProvider>().create(data);
              if (ctx.mounted) Navigator.pop(ctx);
              if (err != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
              }
            },
            child: const Text('Δημιουργία'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<DepartmentProvider>();
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: prov.loading
          ? const Center(child: CircularProgressIndicator())
          : prov.departments.isEmpty
              ? const Center(child: Text('Δεν υπάρχουν τμήματα'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: prov.departments.length,
                  itemBuilder: (context, i) {
                    final dept = prov.departments[i];
                    final counts = dept['_count'] ?? {};
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.business),
                        title: Text(dept['name'] ?? '', style: tt.titleMedium),
                        subtitle: Text(dept['description'] ?? dept['location'] ?? ''),
                        trailing: Wrap(
                          spacing: 16,
                          children: [
                            Chip(label: Text('${counts['userDepartments'] ?? 0} members')),
                            Chip(label: Text('${counts['services'] ?? 0} services')),
                            Chip(label: Text('${counts['vehicles'] ?? 0} vehicles')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
