import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  bool _socketConnected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProv = context.read<ChatProvider>();
      chatProv.setActiveChat(null);
      chatProv.fetchChats();
      _connectSocket();
    });
  }

  Future<void> _connectSocket() async {
    if (_socketConnected) return;
    _socketConnected = true;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token != null) {
      await context.read<ChatProvider>().connect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final chatProv = context.watch<ChatProvider>();
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Συνομιλίες'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: chatProv.loading && chatProv.chats.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : chatProv.chats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 48, color: const Color(0xFF9CA3AF)),
                      const SizedBox(height: 16),
                      Text('Δεν υπάρχουν συνομιλίες',
                          style: tt.bodyLarge
                              ?.copyWith(color: const Color(0xFF6B7280))),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: chatProv.chats.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 72),
                  itemBuilder: (context, index) {
                    final chat = chatProv.chats[index];
                    final unread = chatProv.unread[chat.id] ?? 0;
                    final icon = _chatIcon(chat.type);

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: cs.primary.withAlpha(25),
                        child: Icon(icon, color: cs.primary, size: 22),
                      ),
                      title: Text(
                        chat.name,
                        style: tt.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: chat.lastMessage != null
                          ? Text(
                              '${chat.lastMessage!.user.forename}: ${chat.lastMessage!.text}',
                              style: tt.bodySmall?.copyWith(
                                  color: const Color(0xFF6B7280)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : Text(
                              '${chat.memberCount} μέλη',
                              style: tt.bodySmall?.copyWith(
                                  color: const Color(0xFF9CA3AF)),
                            ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (chat.lastMessage != null)
                            Text(
                              _formatTime(chat.lastMessage!.createdAt),
                              style: tt.labelSmall?.copyWith(
                                  color: const Color(0xFF9CA3AF)),
                            ),
                          if (unread > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: cs.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$unread',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ],
                      ),
                      onTap: () => context.push('/chat/${chat.id}'),
                    );
                  },
                ),
      floatingActionButton: auth.isMissionAdmin
          ? FloatingActionButton(
              onPressed: () => context.push('/chat/create'),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  IconData _chatIcon(String type) {
    switch (type) {
      case 'department':
        return Icons.business;
      case 'mission':
        return Icons.assignment;
      case 'custom':
        return Icons.group;
      default:
        return Icons.chat;
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'τώρα';
    if (diff.inHours < 1) return '${diff.inMinutes}λ';
    if (diff.inDays < 1) return DateFormat('HH:mm').format(dt);
    if (diff.inDays < 7) return DateFormat('EEEE', 'el').format(dt);
    return DateFormat('d/M').format(dt);
  }
}
