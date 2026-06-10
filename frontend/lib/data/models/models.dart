class UserModel {
  final int id;
  final String name;
  final String email;
  final String? avatar;
  final String? phone;
  final bool isOnline;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.avatar,
    this.phone,
    this.isOnline = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'],
        name: json['name'],
        email: json['email'],
        avatar: json['avatar'],
        phone: json['phone'],
        isOnline: json['is_online'] ?? false,
      );
}

class MessageModel {
  final int id;
  final int chatRoomId;
  final int userId;
  final String content;
  final String type;
  final bool isEdited;
  final DateTime createdAt;
  final UserModel? user;

  const MessageModel({
    required this.id,
    required this.chatRoomId,
    required this.userId,
    required this.content,
    required this.type,
    required this.createdAt,
    this.isEdited = false,
    this.user,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) => MessageModel(
        id: json['id'],
        chatRoomId: json['chat_room_id'],
        userId: json['user_id'],
        content: json['content'],
        type: json['type'] ?? 'text',
        isEdited: json['is_edited'] ?? false,
        createdAt: DateTime.parse(json['created_at']),
        user: json['user'] != null ? UserModel.fromJson(json['user']) : null,
      );
}

class ChatRoomModel {
  final int id;
  final String name;
  final String type;
  final int unreadCount;
  final MessageModel? latestMessage;
  final List<UserModel> members;

  const ChatRoomModel({
    required this.id,
    required this.name,
    required this.type,
    this.unreadCount = 0,
    this.latestMessage,
    this.members = const [],
  });

  factory ChatRoomModel.fromJson(Map<String, dynamic> json) => ChatRoomModel(
        id: json['id'],
        name: json['name'],
        type: json['type'],
        unreadCount: json['unread_count'] ?? 0,
        latestMessage: json['latest_message'] != null
            ? MessageModel.fromJson(json['latest_message'])
            : null,
        members: (json['members'] as List<dynamic>? ?? [])
            .map((m) => UserModel.fromJson(m))
            .toList(),
      );
}
