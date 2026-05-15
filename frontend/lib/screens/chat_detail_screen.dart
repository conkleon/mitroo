import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../helpers/chat_models.dart';
import '../services/api_client.dart';
import '../services/download_helper.dart';

class ChatDetailScreen extends StatefulWidget {
  final int chatId;

  const ChatDetailScreen({super.key, required this.chatId});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _loadingOlder = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProv = context.read<ChatProvider>();
      chatProv.setActiveChat(widget.chatId);
      chatProv.fetchMessages(widget.chatId);
    });
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels <= 100 && !_loadingOlder) {
      final msgs =
          context.read<ChatProvider>().messagesForChat(widget.chatId);
      if (msgs.isNotEmpty) {
        setState(() => _loadingOlder = true);
        context
            .read<ChatProvider>()
            .fetchMessages(widget.chatId, before: msgs.first.id)
            .then((_) {
          if (mounted) setState(() => _loadingOlder = false);
        });
      }
    }
  }

  void _send() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    context.read<ChatProvider>().sendMessage(widget.chatId, text);
  }

  Future<void> _attachFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    final chatProv = context.read<ChatProvider>();
    final attId =
        await chatProv.uploadAttachment(widget.chatId, file.bytes!, file.name);
    if (attId != null) {
      chatProv.sendMessage(widget.chatId, file.name,
          attachmentIds: [attId]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final chatProv = context.watch<ChatProvider>();
    final auth = context.watch<AuthProvider>();

    final chat =
        chatProv.chats.where((c) => c.id == widget.chatId).firstOrNull;
    final msgs = chatProv.messagesForChat(widget.chatId);

    final bool canSend = _canSend(chat, auth);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            chatProv.setActiveChat(null);
            context.pop();
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(chat?.name ?? 'Συνομιλία', style: tt.titleSmall),
            Text('${chat?.memberCount ?? 0} μέλη',
                style: tt.labelSmall
                    ?.copyWith(color: const Color(0xFF6B7280))),
          ],
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: () => _showParticipants(context),
          ),
          if (chat?.type == 'custom') ...[
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () =>
                  context.push('/chat/${widget.chatId}/settings'),
            ),
            IconButton(
              icon: const Icon(Icons.exit_to_app, color: Color(0xFFDC2626)),
              onPressed: () => _confirmLeaveChat(context),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (_loadingOlder)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              reverse: true,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: msgs.length,
              itemBuilder: (context, index) {
                final reversed = msgs.reversed.toList();
                final msg = reversed[index];
                final isMe = msg.userId == (auth.user?['id'] as int?);
                final showAvatar = index == reversed.length - 1 ||
                    reversed[index + 1].userId != msg.userId;
                final canDelete = isMe || auth.isMissionAdmin;
                return _MessageBubble(
                  message: msg,
                  isMe: isMe,
                  showAvatar: showAvatar,
                  canDelete: canDelete,
                  onDelete: () => _onDeleteMessage(msg),
                );
              },
            ),
          ),
          _BottomBar(
            textCtrl: _textCtrl,
            onSend: _send,
            onAttach: _attachFile,
            canSend: canSend,
          ),
        ],
      ),
    );
  }

  void _confirmLeaveChat(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Αποχώρηση από συνομιλία'),
        content: const Text(
            'Είστε σίγουροι ότι θέλετε να αποχωρήσετε από αυτή τη συνομιλία;'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Ακύρωση'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final chatProv = context.read<ChatProvider>();
              chatProv.leaveChat(widget.chatId).then((_) {
                if (mounted) {
                  chatProv.setActiveChat(null);
                  context.pop();
                }
              });
            },
            style: TextButton.styleFrom(foregroundColor: Color(0xFFDC2626)),
            child: const Text('Αποχώρηση'),
          ),
        ],
      ),
    );
  }

  void _onDeleteMessage(ChatMessage msg) {
    context.read<ChatProvider>().deleteMessage(msg.chatId, msg.id);
  }

  void _showParticipants(BuildContext context) {
    final chatProv = context.read<ChatProvider>();
    chatProv.fetchChatMembers(widget.chatId);
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Μέλη', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              Flexible(
                child: Consumer<ChatProvider>(
                  builder: (_, prov, __) {
                    final members = prov.membersForChat(widget.chatId);
                    if (members.isEmpty) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: members.length,
                      itemBuilder: (_, i) {
                        final m = members[i];
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 16,
                            child: Text(
                              m.forename.isNotEmpty
                                  ? m.forename[0]
                                  : '?',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          title: Text(
                              '${m.forename} ${m.surname}'.trim()),
                          dense: true,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _canSend(ChatSummary? chat, AuthProvider auth) {
    if (chat == null) return false;
    if (auth.isMissionAdmin) return true;
    switch (chat.type) {
      case 'department':
        return false;
      case 'mission':
      case 'custom':
        return true; // Permission handled server-side
      default:
        return false;
    }
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final bool showAvatar;
  final bool canDelete;
  final VoidCallback? onDelete;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showAvatar,
    this.canDelete = false,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        top: showAvatar ? 12 : 2,
        bottom: 2,
      ),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe && showAvatar) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: cs.primary.withAlpha(30),
              child: Text(
                message.user.forename.isNotEmpty
                    ? message.user.forename[0]
                    : '?',
                style: TextStyle(
                    fontSize: 12,
                    color: cs.primary,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (!isMe && !showAvatar) const SizedBox(width: 36),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.7),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? cs.primary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(8),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showAvatar && !isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${message.user.forename} ${message.user.surname}',
                        style: tt.labelSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (message.attachments.isNotEmpty)
                    ...message.attachments.map((att) => _AttachmentTile(
                          attachment: att,
                          isMe: isMe,
                        )),
                  Text(
                    message.text,
                    style: tt.bodyMedium?.copyWith(
                      color: isMe ? Colors.white : const Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('HH:mm').format(message.createdAt),
                        style: tt.labelSmall?.copyWith(
                          color: isMe
                              ? Colors.white.withAlpha(180)
                              : const Color(0xFF9CA3AF),
                        ),
                      ),
                      if (canDelete) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => _confirmDelete(context),
                          child: Icon(
                            Icons.delete_outline,
                            size: 14,
                            color: isMe
                                ? Colors.white.withAlpha(180)
                                : const Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isMe && showAvatar) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 14,
              backgroundColor: cs.primary,
              child: Text(
                message.user.forename.isNotEmpty
                    ? message.user.forename[0]
                    : '?',
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
          if (isMe && !showAvatar) const SizedBox(width: 36),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή μηνύματος'),
        content: const Text('Είστε σίγουροι ότι θέλετε να διαγράψετε αυτό το μήνυμα;'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Ακύρωση'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onDelete?.call();
            },
            style: TextButton.styleFrom(foregroundColor: Color(0xFFDC2626)),
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  final ChatAttachment attachment;
  final bool isMe;

  const _AttachmentTile({
    required this.attachment,
    required this.isMe,
  });

  bool get _isImage {
    final mime = attachment.mimeType ?? '';
    return mime.startsWith('image/');
  }

  Uri get _url => Uri.parse(
      '${ApiClient.uploadsBaseUrl}/uploads/chat/${attachment.filePath}');

  Future<void> _download() async {
    try {
      final res = await http.get(_url);
      if (res.statusCode == 200) {
        await downloadFile(res.bodyBytes, attachment.fileName);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_isImage) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                _url.toString(),
                height: 160,
                width: 200,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(),
              ),
            ),
            Positioned(
              bottom: 4,
              right: 4,
              child: Material(
                color: Colors.black.withAlpha(120),
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: _download,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.download, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attach_file, size: 16,
              color: isMe ? Colors.white.withAlpha(200) : const Color(0xFF6B7280)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              attachment.fileName,
              style: TextStyle(
                fontSize: 12,
                color: isMe ? Colors.white.withAlpha(200) : const Color(0xFF6B7280),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: _download,
            child: Icon(Icons.download, size: 16,
                color: isMe ? Colors.white.withAlpha(200) : const Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final TextEditingController textCtrl;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final bool canSend;

  const _BottomBar({
    required this.textCtrl,
    required this.onSend,
    required this.onAttach,
    required this.canSend,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!canSend) {
      return SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Center(
            child: Text(
              'Μόνο οι διαχειριστές μπορούν να στείλουν μηνύματα',
              style: TextStyle(
                  color: const Color(0xFF9CA3AF), fontSize: 13),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        color: Colors.white,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file, size: 22),
              color: const Color(0xFF6B7280),
              onPressed: onAttach,
            ),
            Expanded(
              child: TextField(
                controller: textCtrl,
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Μήνυμα...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF3F4F6),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 20,
              backgroundColor: cs.primary,
              child: IconButton(
                icon: const Icon(Icons.send, size: 18, color: Colors.white),
                onPressed: onSend,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
