import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../helpers/chat_models.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  bool _socketConnected = false;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Αναζήτηση συνομιλιών...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) =>
                  setState(() => _searchQuery = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: chatProv.loading && chatProv.chats.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      _SectionHeader(
                        label: 'ΣΥΝΟΜΙΛΙΕΣ ΟΜΑΔΩΝ',
                      ),
                      if (groupChats.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Text(
                            _searchQuery.isNotEmpty
                                ? 'Δεν βρέθηκαν συνομιλίες'
                                : 'Δεν υπάρχουν συνομιλίες ομάδων',
                            style: tt.bodySmall
                                ?.copyWith(color: const Color(0xFF9CA3AF)),
                          ),
                        )
                      else
                        ...groupChats.map((chat) => _buildChatTile(
                            context, chat, chatProv, cs, tt)),
                      _SectionHeader(
                        label: 'ΑΜΕΣΑ ΜΗΝΥΜΑΤΑ',
                        trailing: IconButton(
                          icon: Icon(Icons.add_circle,
                              color: cs.primary, size: 20),
                          tooltip: 'Νέο άμεσο μήνυμα',
                          onPressed: () =>
                              context.push('/chat/direct/new'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                      if (directChats.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Text(
                            _searchQuery.isNotEmpty
                                ? 'Δεν βρέθηκαν άμεσα μηνύματα'
                                : 'Δεν υπάρχουν άμεσα μηνύματα',
                            style: tt.bodySmall
                                ?.copyWith(color: const Color(0xFF9CA3AF)),
                          ),
                        )
                      else
                        ...directChats.map((chat) => _buildChatTile(
                            context, chat, chatProv, cs, tt)),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: auth.isMissionAdmin
          ? FloatingActionButton(
              onPressed: () => context.push('/chat/create'),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildChatTile(
    BuildContext context,
    ChatSummary chat,
    ChatProvider chatProv,
    ColorScheme cs,
    TextTheme tt,
  ) {
    final unread = chatProv.unread[chat.id] ?? 0;
    final icon = _chatIcon(chat.type);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: cs.primary.withAlpha(25),
            child: Icon(icon, color: cs.primary, size: 22),
          ),
          title: Text(
            chat.name,
            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: chat.lastMessage != null
              ? Text(
                  '${chat.lastMessage!.user.forename}: ${chat.lastMessage!.text}',
                  style:
                      tt.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : Text(
                  '${chat.memberCount} μέλη',
                  style:
                      tt.bodySmall?.copyWith(color: const Color(0xFF9CA3AF)),
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (chat.lastMessage != null)
                Text(
                  _formatTime(chat.lastMessage!.createdAt),
                  style: tt.labelSmall
                      ?.copyWith(color: const Color(0xFF9CA3AF)),
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
        ),
        const Divider(height: 1, indent: 72),
      ],
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
      case 'direct':
        return Icons.person;
      default:
        return Icons.chat;
    }
  }

  List<ChatSummary> _filteredChats(ChatProvider chatProv) {
    if (_searchQuery.isEmpty) return chatProv.chats;
    return chatProv.chats
        .where((c) => c.name.toLowerCase().contains(_searchQuery))
        .toList();
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

class _SectionHeader extends StatelessWidget {
  final String label;
  final Widget? trailing;

  const _SectionHeader({required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: tt.labelSmall?.copyWith(
                color: const Color(0xFF9CA3AF),
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
