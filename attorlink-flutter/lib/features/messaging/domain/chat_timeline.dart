import 'chat_models.dart';

/// Stable IDs, server cursors and deletion wins. No optimistic message/receipt.
class ChatTimeline {
  ChatTimeline(this.conversationId);
  final int conversationId;
  final _messages = <int, ChatMessage>{};
  final _deleted = <int, ChatTombstone>{};
  ChatCursor? cursor;
  bool hasMoreSync = false;
  List<ChatMessage> get messages => _messages.values.toList()
    ..sort((a, b) {
      final order = chatTimeKey(a.createdAt)
          .compareTo(chatTimeKey(b.createdAt));
      return order == 0 ? a.id.compareTo(b.id) : order;
    });
  List<ChatTombstone> get tombstones => _deleted.values.toList()
    ..sort(
      (a, b) => chatTimeKey(a.deletedAt).compareTo(chatTimeKey(b.deletedAt)),
    );
  void clear() {
    _messages.clear();
    _deleted.clear();
    cursor = null;
    hasMoreSync = false;
  }

  void resetHistory() {
    _messages.clear();
    hasMoreSync = false;
  } // Retain known tombstones/cursor if the new history is empty.

  void merge(ChatMessage message) {
    if (message.conversationId != conversationId) {
      throw const FormatException('Wrong message conversation');
    }
    if (message.deleted) {
      remove(ChatTombstone(message.id, conversationId, message.deletedAt!));
      return;
    }
    if (_deleted.containsKey(message.id)) return;
    final previous = _messages[message.id];
    if (previous == null) {
      _messages[message.id] = message;
      return;
    }
    const receipts = ['SENT', 'DELIVERED', 'SEEN'];
    final content = message.version.compareTo(previous.version) >= 0
        ? message
        : previous;
    final status =
        receipts.indexOf(message.status) > receipts.indexOf(previous.status)
        ? message.status
        : previous.status;
    _messages[message.id] = content.status == status
        ? content
        : content.withStatus(status);
  }

  void remove(ChatTombstone tombstone) {
    if (tombstone.conversationId != conversationId) {
      throw const FormatException('Wrong deletion conversation');
    }
    _messages.remove(tombstone.id);
    final previous = _deleted[tombstone.id];
    if (previous == null ||
        chatTimeKey(tombstone.deletedAt)
                .compareTo(chatTimeKey(previous.deletedAt)) >=
            0) {
      _deleted[tombstone.id] = tombstone;
    }
  }

  void history(List<ChatMessage> messages, {bool seed = false}) {
    for (final message in messages) {
      merge(message);
    }
    if (seed && cursor == null && messages.isNotEmpty) {
      final last = messages.last;
      cursor = ChatCursor(last.id, last.createdAt);
    }
  }

  void apply(ChatSync sync) {
    if (sync.conversationId != conversationId ||
        (cursor != null && sync.cursor.compareTo(cursor!) < 0)) {
      throw const FormatException('Invalid sync cursor');
    }
    for (final message in sync.messages) {
      merge(message);
    }
    for (final tombstone in sync.tombstones) {
      remove(tombstone);
    }
    cursor = sync.cursor;
    hasMoreSync = sync.hasMore;
  }
}
