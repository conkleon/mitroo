class ChatSummary {
  final int id;
  final String type;
  final String name;
  final int? departmentId;
  final int? serviceId;
  final bool itemAdminsCanSend;
  final bool volunteersCanSend;
  final bool deleteAfter24h;
  final int memberCount;
  final LastMessage? lastMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatSummary({
    required this.id,
    required this.type,
    required this.name,
    this.departmentId,
    this.serviceId,
    this.itemAdminsCanSend = false,
    this.volunteersCanSend = false,
    this.deleteAfter24h = false,
    this.memberCount = 0,
    this.lastMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChatSummary.fromJson(Map<String, dynamic> json) {
    return ChatSummary(
      id: json['id'] as int,
      type: json['type'] as String,
      name: json['name'] as String? ?? 'Chat',
      departmentId: json['departmentId'] as int?,
      serviceId: json['serviceId'] as int?,
      itemAdminsCanSend: json['itemAdminsCanSend'] as bool? ?? false,
      volunteersCanSend: json['volunteersCanSend'] as bool? ?? false,
      deleteAfter24h: json['deleteAfter24h'] as bool? ?? false,
      memberCount: json['memberCount'] as int? ?? 0,
      lastMessage: json['lastMessage'] != null
          ? LastMessage.fromJson(json['lastMessage'] as Map<String, dynamic>)
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

class LastMessage {
  final int id;
  final String text;
  final DateTime createdAt;
  final LastMessageUser user;

  LastMessage({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.user,
  });

  factory LastMessage.fromJson(Map<String, dynamic> json) {
    return LastMessage(
      id: json['id'] as int,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      user: LastMessageUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}

class LastMessageUser {
  final int id;
  final String forename;
  final String surname;

  LastMessageUser({
    required this.id,
    required this.forename,
    required this.surname,
  });

  factory LastMessageUser.fromJson(Map<String, dynamic> json) {
    return LastMessageUser(
      id: json['id'] as int,
      forename: json['forename'] as String? ?? '',
      surname: json['surname'] as String? ?? '',
    );
  }
}

class ChatMessage {
  final int id;
  final int chatId;
  final int userId;
  final String text;
  final DateTime createdAt;
  final ChatUser user;
  final List<ChatAttachment> attachments;

  ChatMessage({
    required this.id,
    required this.chatId,
    required this.userId,
    required this.text,
    required this.createdAt,
    required this.user,
    this.attachments = const [],
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as int,
      chatId: json['chatId'] as int,
      userId: json['userId'] as int,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      user: ChatUser.fromJson(json['user'] as Map<String, dynamic>),
      attachments: (json['attachments'] as List<dynamic>?)
              ?.map((a) => ChatAttachment.fromJson(a as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class ChatUser {
  final int id;
  final String forename;
  final String surname;
  final String? imagePath;

  ChatUser({
    required this.id,
    required this.forename,
    required this.surname,
    this.imagePath,
  });

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    return ChatUser(
      id: json['id'] as int,
      forename: json['forename'] as String? ?? '',
      surname: json['surname'] as String? ?? '',
      imagePath: json['imagePath'] as String?,
    );
  }
}

class ChatAttachment {
  final int id;
  final String fileName;
  final String filePath;
  final String? mimeType;
  final int? fileSize;

  ChatAttachment({
    required this.id,
    required this.fileName,
    required this.filePath,
    this.mimeType,
    this.fileSize,
  });

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      id: json['id'] as int,
      fileName: json['fileName'] as String,
      filePath: json['filePath'] as String,
      mimeType: json['mimeType'] as String?,
      fileSize: json['fileSize'] as int?,
    );
  }
}
