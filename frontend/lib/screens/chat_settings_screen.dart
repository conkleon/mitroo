import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../services/api_client.dart';

class ChatSettingsScreen extends StatefulWidget {
  final int chatId;

  const ChatSettingsScreen({super.key, required this.chatId});

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  bool _loading = true;
  Map<String, dynamic>? _chatDetail;
  List<Map<String, dynamic>> _members = [];

  final _inviteSearchCtrl = TextEditingController();
  List<Map<String, dynamic>> _deptUsers = [];
  bool _loadingDeptUsers = false;
  String _inviteSearch = '';
  final _inviteSelectedIds = <int>{};
  bool _inviting = false;

  List<Map<String, dynamic>> get _filteredDeptUsers {
    if (_inviteSearch.isEmpty) return _deptUsers;
    final q = _inviteSearch.toLowerCase();
    return _deptUsers.where((u) {
      final name = '${u['forename'] ?? ''} ${u['surname'] ?? ''}'.toLowerCase();
      final eame = (u['eame'] as String? ?? '').toLowerCase();
      return name.contains(q) || eame.contains(q);
    }).toList();
  }

  @override
  void dispose() {
    _inviteSearchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadChat();
  }

  Future<void> _loadChat() async {
    final api = ApiClient();
    final res = await api.get('/chats/${widget.chatId}');
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _chatDetail = data;
        _members = (data['members'] as List<dynamic>?)
                ?.map((m) => m as Map<String, dynamic>)
                .toList() ??
            [];
        _loading = false;
      });
    }
  }

  Future<void> _kickUser(int userId) async {
    final chatProv = context.read<ChatProvider>();
    final ok = await chatProv.kickMember(widget.chatId, userId);
    if (ok) {
      setState(() => _members.removeWhere((m) => m['userId'] == userId));
      final count = _chatDetail?['_count'];
      if (count is Map<String, dynamic>) {
        count['members'] = (count['members'] as int) - 1;
      }
    }
  }

  Future<void> _loadDeptUsers() async {
    final deptId = _chatDetail?['departmentId'];
    if (deptId == null) return;
    setState(() => _loadingDeptUsers = true);
    try {
      final api = ApiClient();
      final res = await api.get('/users?departmentId=$deptId');
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        final existingIds = _members.map((m) => m['userId'] as int).toSet();
        _deptUsers = list
            .cast<Map<String, dynamic>>()
            .where((u) => !existingIds.contains(u['id'] as int))
            .toList();
      }
    } catch (_) {}
    setState(() => _loadingDeptUsers = false);
  }

  Future<void> _inviteMembers() async {
    if (_inviteSelectedIds.isEmpty) return;
    setState(() => _inviting = true);
    final chatProv = context.read<ChatProvider>();
    final ok = await chatProv.inviteMembers(
        widget.chatId, _inviteSelectedIds.toList());
    if (ok) {
      final api = ApiClient();
      final res = await api.get('/chats/${widget.chatId}');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _chatDetail = data;
          _members = (data['members'] as List<dynamic>?)
                  ?.map((m) => m as Map<String, dynamic>)
                  .toList() ??
              [];
          _inviteSelectedIds.clear();
          _inviteSearchCtrl.clear();
          _inviteSearch = '';
          _deptUsers = [];
        });
      }
    }
    setState(() => _inviting = false);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final chatProv = context.read<ChatProvider>();

    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7FA),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final detail = _chatDetail!;
    final itemAdminsCanSend =
        detail['itemAdminsCanSend'] as bool? ?? false;
    final volunteersCanSend =
        detail['volunteersCanSend'] as bool? ?? false;
    final deleteAfter24h =
        detail['deleteAfter24h'] as bool? ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Ρυθμίσεις Συνομιλίας'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Μέλη (${_members.length})', style: tt.titleSmall),
          const SizedBox(height: 8),
          ...(_members.map((m) {
            final user = m['user'] as Map<String, dynamic>?;
            final userName =
                '${user?['forename'] ?? ''} ${user?['surname'] ?? ''}'
                    .trim();
            return Card(
              color: Colors.white,
              child: ListTile(
                leading: CircleAvatar(
                  radius: 14,
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                title: Text(userName),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline,
                      color: Colors.red),
                  onPressed: () => _kickUser(m['userId'] as int),
                ),
              ),
            );
          })),
          const SizedBox(height: 24),
          ExpansionTile(
            title: Text('Προσθήκη Μελών', style: tt.titleSmall),
            onExpansionChanged: (expanded) {
              if (expanded) _loadDeptUsers();
            },
            children: [
              if (_loadingDeptUsers)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _inviteSearchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Αναζήτηση χρηστών...',
                      prefixIcon:
                          const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF3F4F6),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 12),
                    ),
                    onChanged: (v) =>
                        setState(() => _inviteSearch = v.trim().toLowerCase()),
                  ),
                ),
                ...(_filteredDeptUsers.map((u) {
                  final uid = u['id'] as int;
                  return CheckboxListTile(
                    title: Text(
                        '${u['forename'] ?? ''} ${u['surname'] ?? ''}'
                            .trim()),
                    subtitle: Text(u['eame'] as String? ?? ''),
                    value: _inviteSelectedIds.contains(uid),
                    onChanged: (sel) {
                      setState(() {
                        if (sel == true) {
                          _inviteSelectedIds.add(uid);
                        } else {
                          _inviteSelectedIds.remove(uid);
                        }
                      });
                    },
                    dense: true,
                  );
                })),
                if (_filteredDeptUsers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                        _inviteSearch.isNotEmpty
                            ? 'Δεν βρέθηκαν χρήστες'
                            : 'Όλοι οι χρήστες είναι ήδη μέλη',
                        style: tt.bodySmall),
                  ),
                if (_inviteSelectedIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      onPressed: _inviting ? null : _inviteMembers,
                      icon: _inviting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white))
                          : const Icon(Icons.person_add, size: 18),
                      label: Text(
                          'Προσθήκη (${_inviteSelectedIds.length})'),
                    ),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          Text('Δικαιώματα', style: tt.titleSmall),
          SwitchListTile(
            title: const Text(
                'Οι διαχειριστές αντικειμένων μπορούν να στέλνουν'),
            value: itemAdminsCanSend,
            onChanged: (v) async {
              await chatProv.updateChatSettings(widget.chatId,
                  itemAdminsCanSend: v);
              setState(
                  () => _chatDetail!['itemAdminsCanSend'] = v);
            },
          ),
          SwitchListTile(
            title: const Text('Οι εθελοντές μπορούν να στέλνουν'),
            value: volunteersCanSend,
            onChanged: (v) async {
              await chatProv.updateChatSettings(widget.chatId,
                  volunteersCanSend: v);
              setState(() => _chatDetail!['volunteersCanSend'] = v);
            },
          ),
          SwitchListTile(
            title: const Text(
                'Αυτόματη διαγραφή μετά από 24 ώρες'),
            value: deleteAfter24h,
            onChanged: (v) async {
              await chatProv.updateChatSettings(widget.chatId,
                  deleteAfter24h: v);
              setState(
                  () => _chatDetail!['deleteAfter24h'] = v);
            },
          ),
        ],
      ),
    );
  }
}
