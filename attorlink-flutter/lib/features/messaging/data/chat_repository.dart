import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../auth/domain/auth_models.dart';
import '../domain/chat_models.dart';
import '../../../app/live_updates.dart';

class ChatRepository {
  ChatRepository(
    this.api, {
    required this.ownerId,
    required this.currentUser,
    this.accessChanges,
    this.live,
    this.sessionGeneration,
  }) : _initialGeneration = sessionGeneration?.call();
  final ApiClient api;
  final int ownerId;
  final AuthUser? Function() currentUser;
  final Stream<Object?>? accessChanges;
  final LiveUpdates? live;
  final int Function()? sessionGeneration;
  final int? _initialGeneration;

  bool acceptsEvent(LiveEvent event) {
    try {
      checkAccess();
    } on ApiException {
      return false;
    }
    return event.ownerId == ownerId &&
        (sessionGeneration == null ||
            event.sessionGeneration == _initialGeneration);
  }

  void checkAccess() {
    final user = currentUser();
    if (sessionGeneration?.call() != _initialGeneration ||
        user == null ||
        user.id != ownerId ||
        user.status != UserStatus.active ||
        ![UserRole.client, UserRole.lawyer].contains(user.role)) {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        message:
            'Sign in with an active client or lawyer account to use messages.',
      );
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    checkAccess();
    final result = await action();
    checkAccess();
    return result;
  }

  ChatConversation _conversation(Object? value, {int? id}) {
    final conversation = ChatConversation.fromJson(value);
    if (!conversation.contains(ownerId) ||
        (id != null && conversation.id != id)) {
      throw const FormatException('Unexpected conversation');
    }
    return conversation;
  }

  Future<ApiPage<ChatConversation>> inbox(ChatInbox tab, {int page = 0}) =>
      _guard(() async {
        if (page < 0) {
          throw ArgumentError.value(page);
        }
        return (await api.request(
          'GET',
          'chat/${tab.path}',
          authenticated: true,
          accessGuard: checkAccess,
          query: {'page': '$page', 'size': '20'},
          decode: (value) {
            final result = ApiPage.fromJson(
              value,
              (value) => _conversation(value),
            );
            if (result.page != page || result.size != 20) {
              throw const FormatException('Unexpected inbox page');
            }
            return result;
          },
        )).data;
      });
  Future<ChatConversation> get(int id) => _guard(
    () async => (await api.request(
      'GET',
      'chat/conversations/$id',
      authenticated: true,
      accessGuard: checkAccess,
      decode: (value) => _conversation(value, id: id),
    )).data,
  );
  Future<ChatConversation> start(int recipient, String firstText) =>
      _guard(() async {
        if (recipient <= 0 || recipient == ownerId || firstText.length > 4000) {
          throw const ApiException(
            kind: ApiErrorKind.validation,
            message: 'Choose another user ID and an optional first message up to 4000 characters.',
          );
        }
        return (await api.request(
          'POST',
          'chat/conversations',
          authenticated: true,
          accessGuard: checkAccess,
          body: {
            'recipientUserId': recipient,
            if (firstText.trim().isNotEmpty) 'firstMessageText': firstText,
          },
          decode: (value) {
            final result = _conversation(value);
            if (result.other(ownerId) != recipient) {
              throw const FormatException('Unexpected recipient');
            }
            return result;
          },
        )).data;
      });
  Future<ChatConversation> decide(
    ChatConversation conversation, {
    required bool accept,
  }) => _guard(() async {
    if (!conversation.canDecide(ownerId)) {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        message: 'Only the intended recipient can decide a pending request.',
      );
    }
    return (await api.request(
      'POST',
      'chat/conversations/${conversation.id}/${accept ? 'accept' : 'reject'}',
      authenticated: true,
      accessGuard: checkAccess,
      decode: (value) {
        final result = _conversation(value, id: conversation.id);
        if (result.status != (accept ? 'ACCEPTED' : 'REJECTED')) {
          throw const FormatException('Decision not confirmed');
        }
        return result;
      },
    )).data;
  });
  Future<ApiPage<ChatMessage>> history(int conversationId, {int page = 0}) =>
      _guard(
        () async => (await api.request(
          'GET',
          'chat/conversations/$conversationId/messages',
          authenticated: true,
          accessGuard: checkAccess,
          query: {'page': '$page', 'size': '20'},
          decode: (value) {
            final result = ApiPage.fromJson(
              value,
              (value) => _message(value, conversationId),
            );
            if (result.page != page || result.size != 20) {
              throw const FormatException('Unexpected history page');
            }
            return result;
          },
        )).data,
      );
  ChatMessage _message(Object? value, int conversationId, {int? id}) {
    final message = ChatMessage.fromJson(value);
    if (message.conversationId != conversationId ||
        (id != null && message.id != id)) {
      throw const FormatException('Unexpected message');
    }
    return message;
  }

  void _accepted(ChatConversation conversation) {
    if (!conversation.contains(ownerId) || conversation.status != 'ACCEPTED') {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        message: 'The conversation must be accepted before messaging.',
      );
    }
  }

  void _text(String text) {
    if (text.trim().isEmpty || text.length > 4000) {
      throw const ApiException(
        kind: ApiErrorKind.validation,
        message: 'Enter message text of at most 4000 characters.',
      );
    }
  }

  Future<ChatMessage> send(ChatConversation conversation, String text) =>
      _guard(() async {
        _accepted(conversation);
        _text(text);
        return (await api.request(
          'POST',
          'chat/conversations/${conversation.id}/messages',
          authenticated: true,
          accessGuard: checkAccess,
          body: {'text': text},
          decode: (value) {
            final result = _message(value, conversation.id);
            if (result.senderId != ownerId ||
                result.type != 'TEXT' ||
                result.deleted) {
              throw const FormatException('Unexpected sent message');
            }
            return result;
          },
        )).data;
      });
  Future<ChatMessage> change(
    ChatConversation conversation,
    ChatMessage message, {
    String? text,
  }) => _guard(() async {
    _accepted(conversation);
    if (message.conversationId != conversation.id ||
        message.senderId != ownerId ||
        message.deleted ||
        (text != null && message.type != 'TEXT')) {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        message: 'Only your own eligible messages can be changed.',
      );
    }
    if (text != null) {
      _text(text);
    }
    return (await api.request(
      text == null ? 'DELETE' : 'PATCH',
      'chat/conversations/${conversation.id}/messages/${message.id}',
      authenticated: true,
      accessGuard: checkAccess,
      body: text == null ? null : {'text': text},
      decode: (value) {
        final result = _message(value, conversation.id, id: message.id);
        if (result.senderId != ownerId || result.deleted != (text == null)) {
          throw const FormatException('Message change not confirmed');
        }
        return result;
      },
    )).data;
  });
  Future<ChatMessage> acknowledge(
    int conversationId,
    ChatMessage message, {
    required bool seen,
  }) => _guard(() async {
    if (message.conversationId != conversationId ||
        message.senderId == null ||
        message.senderId == ownerId ||
        message.deleted) {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        message: 'Only incoming live messages can be acknowledged.',
      );
    }
    return (await api.request(
      'POST',
      'chat/conversations/$conversationId/messages/${message.id}/${seen ? 'seen' : 'delivered'}',
      authenticated: true,
      accessGuard: checkAccess,
      decode: (value) {
        final result = _message(value, conversationId, id: message.id);
        if (result.senderId != message.senderId ||
            result.deleted ||
            (seen ? result.status != 'SEEN' : result.status == 'SENT')) {
          throw const FormatException('Receipt not confirmed');
        }
        return result;
      },
    )).data;
  });
  Future<ChatReadResult> markRead(int conversationId, ChatMessage through) =>
      _guard(() async {
        if (through.conversationId != conversationId ||
            through.senderId == null ||
            through.senderId == ownerId ||
            through.deleted) {
          throw const ApiException(
            kind: ApiErrorKind.validation,
            message: 'Choose an incoming message as the read cursor.',
          );
        }
        return (await api.request(
          'POST',
          'chat/conversations/$conversationId/read',
          authenticated: true,
          accessGuard: checkAccess,
          body: {'lastReadMessageId': through.id},
          decode: (value) {
            final result = ChatReadResult.fromJson(value);
            if (result.conversationId != conversationId ||
                result.messageId != through.id) {
              throw const FormatException('Unexpected read marker');
            }
            return result;
          },
        )).data;
      });
  Future<ChatSync> sync(
    ChatConversation conversation,
    ChatCursor cursor, {
    int limit = 50,
  }) => _guard(() async {
    _accepted(conversation);
    if (limit < 1 || limit > 200) {
      throw const ApiException(
        kind: ApiErrorKind.validation,
        message: 'Sync limit must be between 1 and 200.',
      );
    }
    return (await api.request(
      'GET',
      'chat/conversations/${conversation.id}/sync',
      authenticated: true,
      accessGuard: checkAccess,
      query: {
        'lastMessageId': '${cursor.id}',
        'lastEventTimestamp': cursor.timestamp,
        'limit': '$limit',
      },
      decode: (value) {
        final result = ChatSync.fromJson(value);
        if (result.conversationId != conversation.id ||
            result.cursor.compareTo(cursor) < 0 ||
            (result.hasMore && result.cursor.compareTo(cursor) == 0) ||
            result.messages.any(
              (message) => message.conversationId != conversation.id,
            ) ||
            result.tombstones.any(
              (event) => event.conversationId != conversation.id,
            )) {
          throw const FormatException('Unexpected synchronization batch');
        }
        return result;
      },
    )).data;
  });
}

bool uncertainChatOutcome(ApiException error) => [
  ApiErrorKind.network,
  ApiErrorKind.timeout,
  ApiErrorKind.server,
  ApiErrorKind.invalidResponse,
].contains(error.kind);
