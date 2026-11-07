import '../../auth/domain/auth_models.dart';
import '../../client/domain/client_models.dart' show optionalString;

int chatId(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value <= 0) {
    throw FormatException('Invalid $key');
  }
  return value;
}

int? _id(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : chatId(json, key);
String _enum(Map<String, dynamic> json, String key, List<String> values) {
  final value = requiredString(json, key);
  if (!values.contains(value)) {
    throw FormatException('Invalid $key');
  }
  return value;
}

bool _boolean(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw FormatException('Invalid $key');
  }
  return value;
}

enum ChatInbox {
  all('Inbox', 'conversations'),
  incoming('Incoming requests', 'requests/incoming'),
  outgoing('Pending outgoing', 'requests/outgoing'),
  sent('Sent conversations', 'conversations');

  const ChatInbox(this.label, this.path);
  final String label, path;
}

class ChatConversation {
  ChatConversation.fromJson(Object? value) {
    final json = jsonObject(value);
    id = chatId(json, 'id');
    a = _id(json, 'participantAId');
    b = _id(json, 'participantBId');
    initiator = _id(json, 'initiatedByUserId');
    type = _enum(json, 'conversationType', ['CLIENT_LAWYER', 'LAWYER_LAWYER']);
    status = _enum(json, 'requestStatus', ['PENDING', 'ACCEPTED', 'REJECTED']);
    lastMessageAt = optionalString(json, 'lastMessageAt');
    createdAt = optionalString(json, 'createdAt');
    updatedAt = optionalString(json, 'updatedAt');
    final count = json['unreadCount'];
    if (count is! int || count < 0) {
      throw const FormatException('Invalid unreadCount');
    }
    unreadCount = count;
  }
  late final int id, unreadCount;
  late final int? a, b, initiator;
  late final String type, status;
  late final String? lastMessageAt, createdAt, updatedAt;
  bool contains(int user) => a == user || b == user;
  bool canDecide(int user) =>
      status == 'PENDING' &&
      contains(user) &&
      initiator != null &&
      initiator != user;
  int? other(int user) => a == user ? b : a;
}

/// Canonical comparison only; never change the timestamp sent back to Spring.
String chatTimeKey(String stamp) {
  final match = RegExp(
    r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,9}))?$',
  ).firstMatch(stamp);
  if (match == null) {
    throw const FormatException('Invalid chat timestamp');
  }
  return '${match.group(1)}.${(match.group(2) ?? '').padRight(9, '0')}';
}

class ChatCursor {
  ChatCursor(this.id, this.timestamp) {
    if (id <= 0) {
      throw const FormatException('Invalid cursor');
    }
    chatTimeKey(timestamp);
  }
  final int id;
  final String timestamp;
  int compareTo(ChatCursor other) {
    final order = chatTimeKey(timestamp)
        .compareTo(chatTimeKey(other.timestamp));
    return order == 0 ? id.compareTo(other.id) : order;
  }
}

class ChatMessage {
  ChatMessage.fromJson(Object? value) {
    final json = jsonObject(value);
    id = chatId(json, 'id');
    conversationId = chatId(json, 'conversationId');
    senderId = _id(json, 'senderId');
    type = _enum(json, 'messageType', ['TEXT', 'SYSTEM']);
    status = _enum(json, 'deliveryStatus', ['SENT', 'DELIVERED', 'SEEN']);
    edited = _boolean(json, 'isEdited');
    deleted = _boolean(json, 'isDeleted');
    // The delete response may retain text: never retain/display it as live text.
    text = deleted ? null : optionalString(json, 'text');
    createdAt = requiredString(json, 'createdAt');
    chatTimeKey(createdAt);
    updatedAt = optionalString(json, 'updatedAt');
    editedAt = optionalString(json, 'editedAt');
    deletedAt = optionalString(json, 'deletedAt');
    for (final stamp in [updatedAt, editedAt, deletedAt]) {
      if (stamp != null) {
        chatTimeKey(stamp);
      }
    }
    if (deleted && deletedAt == null) {
      throw const FormatException('Missing deletion timestamp');
    }
  }
  late final int id, conversationId;
  late final int? senderId;
  late final String type, status, createdAt;
  late final String? text, updatedAt, editedAt, deletedAt;
  late final bool edited, deleted;
  ChatMessage withStatus(String receipt) => ChatMessage.fromJson({
    'id': id,
    'conversationId': conversationId,
    'senderId': senderId,
    'messageType': type,
    'text': text,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'editedAt': editedAt,
    'deletedAt': deletedAt,
    'deliveryStatus': receipt,
    'isEdited': edited,
    'isDeleted': deleted,
  });

  String get version => [
    createdAt,
    ?updatedAt,
    ?editedAt,
    ?deletedAt,
  ].map(chatTimeKey).reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
}

class ChatTombstone {
  ChatTombstone.fromJson(Object? value) {
    final json = jsonObject(value);
    id = chatId(json, 'id');
    conversationId = chatId(json, 'conversationId');
    deletedAt = requiredString(json, 'deletedAt');
    chatTimeKey(deletedAt);
  }
  ChatTombstone(this.id, this.conversationId, this.deletedAt);
  late final int id, conversationId;
  late final String deletedAt;
}

class ChatSync {
  ChatSync.fromJson(Object? value) {
    final json = jsonObject(value);
    conversationId = chatId(json, 'conversationId');
    cursor = ChatCursor(
      chatId(json, 'nextCursorMessageId'),
      requiredString(json, 'nextCursorCreatedAt'),
    );
    hasMore = _boolean(json, 'hasMore');
    if (json['messages'] is! List || json['tombstones'] is! List) {
      throw const FormatException('Invalid sync events');
    }
    messages = List.unmodifiable(
      (json['messages'] as List).map(ChatMessage.fromJson),
    );
    tombstones = List.unmodifiable(
      (json['tombstones'] as List).map(ChatTombstone.fromJson),
    );
  }
  late final int conversationId;
  late final ChatCursor cursor;
  late final bool hasMore;
  late final List<ChatMessage> messages;
  late final List<ChatTombstone> tombstones;
}

class ChatReadResult {
  ChatReadResult.fromJson(Object? value) {
    final json = jsonObject(value);
    conversationId = chatId(json, 'conversationId');
    messageId = chatId(json, 'lastReadMessageId');
    final count = json['markedSeenCount'];
    if (count is! int || count < 0) {
      throw const FormatException('Invalid read count');
    }
    markedSeenCount = count;
  }
  late final int conversationId, messageId, markedSeenCount;
}
