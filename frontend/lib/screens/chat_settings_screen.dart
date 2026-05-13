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
