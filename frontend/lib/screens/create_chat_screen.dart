import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/department_provider.dart';
import '../services/api_client.dart';

class CreateChatScreen extends StatefulWidget {
  const CreateChatScreen({super.key});

  @override
  State<CreateChatScreen> createState() => _CreateChatScreenState();
}

class _CreateChatScreenState extends State<CreateChatScreen> {
  final _nameCtrl = TextEditingController();
  int? _selectedDeptId;
  final _selectedUserIds = <int>{};
  bool _itemAdminsCanSend = false;
  bool _volunteersCanSend = false;
  bool _deleteAfter24h = false;
  bool _creating = false;

  List<Map<String, dynamic>> _deptUsers = [];
  bool _loadingUsers = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DepartmentProvider>().fetchDepartments();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchDeptUsers(int deptId) async {
    setState(() => _loadingUsers = true);
    try {
      final api = ApiClient();
      final res = await api.get('/users?departmentId=$deptId');
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        _deptUsers = list.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    setState(() => _loadingUsers = false);
  }

  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _selectedDeptId == null ||
        _selectedUserIds.isEmpty) {
      return;
    }
    setState(() => _creating = true);
    final chatProv = context.read<ChatProvider>();
    final chat = await chatProv.createChat(
      name: _nameCtrl.text.trim(),
      departmentId: _selectedDeptId!,
      memberIds: _selectedUserIds.toList(),
      itemAdminsCanSend: _itemAdminsCanSend,
      volunteersCanSend: _volunteersCanSend,
      deleteAfter24h: _deleteAfter24h,
    );
    setState(() => _creating = false);
    if (chat != null && mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final auth = context.watch<AuthProvider>();
    final deptProv = context.watch<DepartmentProvider>();

    final depts = auth.isAdmin
        ? deptProv.departments
            .map((d) => {'id': d['id'] as int, 'name': d['name'] as String})
            .toList()
        : auth.missionAdminDepartments
            .map((d) => {'id': d['id'] as int, 'name': d['name'] as String})
            .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Νέα Ομαδική Συνομιλία'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Όνομα συνομιλίας',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            value: _selectedDeptId,
            decoration: const InputDecoration(
              labelText: 'Τμήμα',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
            items: depts
                .map((d) => DropdownMenuItem(
                      value: d['id'] as int,
                      child: Text(d['name'] as String),
                    ))
                .toList(),
            onChanged: (val) {
              setState(() {
                _selectedDeptId = val;
                _selectedUserIds.clear();
                _deptUsers = [];
              });
              if (val != null) _fetchDeptUsers(val);
            },
          ),
          const SizedBox(height: 24),
          Text('Επιλογή Μελών', style: tt.titleSmall),
          const SizedBox(height: 8),
          if (_loadingUsers)
            const Center(child: CircularProgressIndicator())
          else if (_deptUsers.isEmpty && _selectedDeptId != null)
            Text('Δεν βρέθηκαν χρήστες', style: tt.bodySmall)
          else
            ...(_deptUsers.map((u) => CheckboxListTile(
                  title: Text(
                      '${u['forename'] ?? ''} ${u['surname'] ?? ''}'.trim()),
                  subtitle:
                      Text(u['eame'] as String? ?? ''),
                  value: _selectedUserIds.contains(u['id'] as int),
                  onChanged: (sel) {
                    setState(() {
                      if (sel == true) {
                        _selectedUserIds.add(u['id'] as int);
                      } else {
                        _selectedUserIds.remove(u['id'] as int);
                      }
                    });
                  },
                  dense: true,
                ))),
          const SizedBox(height: 24),
          Text('Δικαιώματα', style: tt.titleSmall),
          SwitchListTile(
            title: const Text(
                'Οι διαχειριστές αντικειμένων μπορούν να στέλνουν'),
            value: _itemAdminsCanSend,
            onChanged: (v) =>
                setState(() => _itemAdminsCanSend = v),
            dense: true,
          ),
          SwitchListTile(
            title: const Text('Οι εθελοντές μπορούν να στέλνουν'),
            value: _volunteersCanSend,
            onChanged: (v) =>
                setState(() => _volunteersCanSend = v),
            dense: true,
          ),
          SwitchListTile(
            title: const Text(
                'Αυτόματη διαγραφή μετά από 24 ώρες'),
            value: _deleteAfter24h,
            onChanged: (v) =>
                setState(() => _deleteAfter24h = v),
            dense: true,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _creating ? null : _create,
            icon: _creating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check),
            label: const Text('Δημιουργία'),
          ),
        ],
      ),
    );
  }
}
