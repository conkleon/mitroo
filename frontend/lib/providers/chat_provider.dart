import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/chat_models.dart';
import '../services/api_client.dart';
import '../config/api_config.dart';
import '../services/chat_sound_service.dart';

class ChatProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient();

  List<ChatSummary> _chats = [];
  final Map<int, List<ChatMessage>> _messages = {};
  final Map<int, int> _unread = {};
  bool _loading = false;
  int? _activeChatId;
  io.Socket? _socket;

  List<ChatSummary> get chats => _chats;
  Map<int, List<ChatMessage>> get messages => _messages;
  Map<int, int> get unread => _unread;
  bool get loading => _loading;
  int? get activeChatId => _activeChatId;

  final Map<int, List<ChatUser>> _members = {};

  List<ChatMessage> messagesForChat(int chatId) => _messages[chatId] ?? [];
  List<ChatUser> membersForChat(int chatId) => _members[chatId] ?? [];

  String get _serverUrl {
    final base = ApiConfig.baseUrl;
    // Full URL (dev mode, e.g. http://localhost:4000/api)
    if (base.startsWith('http://') || base.startsWith('https://')) {
      if (base.endsWith('/api')) return base.substring(0, base.length - 4);
      return base;
    }
    // Relative path (production, e.g. /api) — socket.io connects to same origin
    return Uri.base.origin;
  }

  Future<void> connect() async {
    if (_socket?.connected == true) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return;

    _socket = io.io(
      _serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .build(),
    );
    _socket!.connect();

    _socket!.on('chat:message', (data) {
      final msg = ChatMessage.fromJson(data as Map<String, dynamic>);
      _messages.putIfAbsent(msg.chatId, () => []);
      _messages[msg.chatId]!.add(msg);

      if (_activeChatId != msg.chatId) {
        _unread[msg.chatId] = (_unread[msg.chatId] ?? 0) + 1;
        ChatSoundService().play();
      }

      final idx = _chats.indexWhere((c) => c.id == msg.chatId);
      if (idx > 0) {
        final chat = _chats.removeAt(idx);
        _chats.insert(0, chat);
      }

      notifyListeners();
    });

    _socket!.on('chat:message-deleted', (data) {
      final chatId = data['chatId'] as int;
      final messageId = data['messageId'] as int;
      final msgs = _messages[chatId];
      if (msgs != null) {
        msgs.removeWhere((m) => m.id == messageId);
        notifyListeners();
      }
    });

    _socket!.on('chat:new', (data) {
      fetchChats();
    });

    _socket!.on('chat:member-joined', (data) {
      fetchChats();
    });

    _socket!.on('chat:member-left', (data) {
      fetchChats();
    });

    _socket!.on('chat:error', (data) {
      debugPrint('Chat socket error: ${data['message']}');
    });
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  void setActiveChat(int? chatId) {
    _activeChatId = chatId;
    if (chatId != null) {
      _unread[chatId] = 0;
      _socket?.emit('chat:join', {'chatId': chatId});
      notifyListeners();
    }
  }

  Future<void> fetchChats() async {
    _loading = true;
    notifyListeners();
    try {
      final res = await _api.get('/chats');
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        _chats = list
            .map((j) => ChatSummary.fromJson(j as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Error fetching chats: $e');
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> fetchMessages(int chatId, {int? before, int limit = 50}) async {
    var path = '/chats/$chatId/messages?limit=$limit';
    if (before != null) path += '&before=$before';
    try {
      final res = await _api.get(path);
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        final msgs = list
            .map((j) => ChatMessage.fromJson(j as Map<String, dynamic>))
            .toList();
        if (before != null) {
          _messages.putIfAbsent(chatId, () => []);
          _messages[chatId] = [...msgs, ..._messages[chatId]!];
        } else {
          _messages[chatId] = msgs;
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching messages: $e');
    }
  }

  void sendMessage(int chatId, String text, {List<int>? attachmentIds}) {
    _socket?.emit('chat:send', {
      'chatId': chatId,
      'text': text,
      if (attachmentIds != null) 'attachmentIds': attachmentIds,
    });
  }

  Future<ChatSummary?> createChat({
    required String name,
    required int departmentId,
    required List<int> memberIds,
    bool itemAdminsCanSend = false,
    bool volunteersCanSend = false,
    bool deleteAfter24h = false,
  }) async {
    try {
      final res = await _api.post('/chats', body: {
        'name': name,
        'departmentId': departmentId,
        'memberIds': memberIds,
        'itemAdminsCanSend': itemAdminsCanSend,
        'volunteersCanSend': volunteersCanSend,
        'deleteAfter24h': deleteAfter24h,
      });
      if (res.statusCode == 201) {
        final chat =
            ChatSummary.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
        _chats.insert(0, chat);
        notifyListeners();
        return chat;
      }
    } catch (e) {
      debugPrint('Error creating chat: $e');
    }
    return null;
  }

  Future<bool> inviteMembers(int chatId, List<int> userIds) async {
    try {
      final res = await _api.post('/chats/$chatId/members', body: {
        'userIds': userIds,
      });
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Error inviting members: $e');
      return false;
    }
  }

  Future<bool> kickMember(int chatId, int userId) async {
    try {
      final res = await _api.delete('/chats/$chatId/members/$userId');
      return res.statusCode == 204;
    } catch (e) {
      debugPrint('Error kicking member: $e');
      return false;
    }
  }

  Future<bool> leaveChat(int chatId) async {
    try {
      final res = await _api.delete('/chats/$chatId/leave');
      if (res.statusCode == 204) {
        _chats.removeWhere((c) => c.id == chatId);
        _messages.remove(chatId);
        _members.remove(chatId);
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Error leaving chat: $e');
    }
    return false;
  }

  Future<bool> updateChatSettings(
    int chatId, {
    String? name,
    bool? itemAdminsCanSend,
    bool? volunteersCanSend,
    bool? deleteAfter24h,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (itemAdminsCanSend != null) {
        body['itemAdminsCanSend'] = itemAdminsCanSend;
      }
      if (volunteersCanSend != null) {
        body['volunteersCanSend'] = volunteersCanSend;
      }
      if (deleteAfter24h != null) {
        body['deleteAfter24h'] = deleteAfter24h;
      }
      final res = await _api.patch('/chats/$chatId', body: body);
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Error updating chat: $e');
      return false;
    }
  }

  Future<bool> deleteMessage(int chatId, int messageId) async {
    try {
      final res = await _api.delete('/chats/$chatId/messages/$messageId');
      return res.statusCode == 204;
    } catch (e) {
      debugPrint('Error deleting message: $e');
      return false;
    }
  }

  Future<void> fetchChatMembers(int chatId) async {
    try {
      final res = await _api.get('/chats/$chatId');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final membersList = data['members'] as List<dynamic>? ?? [];
        _members[chatId] = membersList
            .map((m) => ChatUser.fromJson(m['user'] as Map<String, dynamic>))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching chat members: $e');
    }
  }

  Future<int?> uploadAttachment(
      int chatId, List<int> fileBytes, String fileName) async {
    try {
      final res = await _api.uploadFile(
        '/chats/$chatId/upload',
        fileBytes: fileBytes,
        fileName: fileName,
        fieldName: 'file',
      );
      if (res.statusCode == 201) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['id'] as int;
      }
    } catch (e) {
      debugPrint('Error uploading attachment: $e');
    }
    return null;
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
