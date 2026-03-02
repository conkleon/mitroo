import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';

/// System-admin screen: list all users, create new ones, edit roles.
class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  final _api = ApiClient();
  List<dynamic> _users = [];
  List<dynamic> _allSpecs = []; // all available specializations
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.get('/users'),
        _api.get('/specializations'),
      ]);
      if (results[0].statusCode == 200) _users = jsonDecode(results[0].body);
      if (results[1].statusCode == 200) _allSpecs = jsonDecode(results[1].body);
    } catch (_) {}
    setState(() => _loading = false);
  }

  void _showCreateDialog() {
    final enameCtrl = TextEditingController();
    final forenameCtrl = TextEditingController();
    final surnameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create User'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: enameCtrl, decoration: const InputDecoration(labelText: 'Username (ename)', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: forenameCtrl, decoration: const InputDecoration(labelText: 'First Name', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: surnameCtrl, decoration: const InputDecoration(labelText: 'Last Name', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: passwordCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password (min 8)', border: OutlineInputBorder())),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final body = {
                'ename': enameCtrl.text.trim(),
                'forename': forenameCtrl.text.trim(),
                'surname': surnameCtrl.text.trim(),
                'email': emailCtrl.text.trim(),
                'password': passwordCtrl.text,
              };
              try {
                final res = await _api.post('/auth/register', body: body);
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

  void _showSpecializationsDialog(Map<String, dynamic> user) async {
    final userId = user['id'] as int;
    final name = '${user['forename'] ?? ''} ${user['surname'] ?? ''}'.trim();

    // Fetch current specializations for this user
    List<dynamic> userSpecs = [];
    try {
      final res = await _api.get('/users/$userId/specializations');
      if (res.statusCode == 200) userSpecs = jsonDecode(res.body);
    } catch (_) {}

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final assignedIds = userSpecs
              .map((us) => (us['specialization']?['id'] ?? us['specializationId']) as int)
              .toSet();
          final available = _allSpecs
              .where((s) => !assignedIds.contains(s['id'] as int))
              .toList();

          return AlertDialog(
            title: Text('Specializations – $name'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Current specializations
                  if (userSpecs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No specializations assigned', style: TextStyle(color: Colors.grey)),
                    )
                  else
                    ...userSpecs.map((us) {
                      final spec = us['specialization'] as Map<String, dynamic>?;
                      final specName = spec?['name'] ?? 'Unknown';
                      final specId = (spec?['id'] ?? us['specializationId']) as int;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.school, size: 20, color: Color(0xFFD97706)),
                        title: Text(specName),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle, color: Colors.red, size: 20),
                          onPressed: () async {
                            try {
                              final res = await _api.delete('/users/$userId/specializations/$specId');
                              if (res.statusCode == 204) {
                                userSpecs.removeWhere((us) =>
                                    (us['specialization']?['id'] ?? us['specializationId']) == specId);
                                setDlgState(() {});
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
                              }
                            }
                          },
                        ),
                      );
                    }),

                  const Divider(),

                  // Add specialization dropdown
                  if (available.isNotEmpty) ...[
                    const Text('Add specialization:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: available.map((s) {
                        return ActionChip(
                          avatar: const Icon(Icons.add, size: 16),
                          label: Text(s['name'] ?? '', style: const TextStyle(fontSize: 12)),
                          onPressed: () async {
                            try {
                              final res = await _api.post(
                                '/users/$userId/specializations',
                                body: {'specializationId': s['id']},
                              );
                              if (res.statusCode == 201) {
                                userSpecs.add(jsonDecode(res.body));
                                setDlgState(() {});
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
                              }
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ] else
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('All specializations assigned', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ),
                ],
              ),
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
            ],
          );
        },
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> user) {
    final forenameCtrl = TextEditingController(text: user['forename'] ?? '');
    final surnameCtrl = TextEditingController(text: user['surname'] ?? '');
    final emailCtrl = TextEditingController(text: user['email'] ?? '');
    bool isAdmin = user['isAdmin'] == true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('Edit ${user['ename']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: forenameCtrl, decoration: const InputDecoration(labelText: 'First Name', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: surnameCtrl, decoration: const InputDecoration(labelText: 'Last Name', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('System Admin'),
                  value: isAdmin,
                  onChanged: (v) => setDlgState(() => isAdmin = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final body = <String, dynamic>{
                  'forename': forenameCtrl.text.trim(),
                  'surname': surnameCtrl.text.trim(),
                  'email': emailCtrl.text.trim(),
                  'isAdmin': isAdmin,
                };
                try {
                  await _api.patch('/users/${user['id']}', body: body);
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text('Manage Users', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.person_add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetch,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                itemCount: _users.length,
                itemBuilder: (context, i) {
                  final u = _users[i] as Map<String, dynamic>;
                  final name = '${u['forename'] ?? ''} ${u['surname'] ?? ''}'.trim();
                  final roles = (u['departments'] as List<dynamic>?)
                      ?.map((d) => '${d['department']?['name'] ?? ''} (${d['role']})')
                      .join(', ') ?? '';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: u['isAdmin'] == true ? Colors.amber : Colors.blueGrey,
                        child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                      title: Text(name.isNotEmpty ? name : u['ename'] ?? '',
                          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        roles.isNotEmpty ? roles : u['email'] ?? '',
                        style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (u['isAdmin'] == true)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.withAlpha(30),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('Admin', style: tt.labelSmall?.copyWith(color: Colors.amber.shade800)),
                            ),
                          IconButton(
                            icon: const Icon(Icons.school, size: 20),
                            tooltip: 'Specializations',
                            onPressed: () => _showSpecializationsDialog(u),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => _showEditDialog(u),
                          ),
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
