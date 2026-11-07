import '../../auth/domain/auth_models.dart';
import '../../client/domain/client_models.dart' show optionalString;

int notificationCount(Object? value, String field) {
  final count = jsonObject(value)[field];
  if (count is! int || count < 0) {
    throw FormatException('Invalid $field');
  }
  return count;
}

class NotificationItem {
  NotificationItem.fromJson(Object? value)
    : fields = Map.unmodifiable(jsonObject(value)) {
    if (fields['id'] is! int ||
        (fields['id'] as int) <= 0 ||
        fields['recipientId'] is! int ||
        (fields['recipientId'] as int) <= 0 ||
        fields['read'] is! bool) {
      throw const FormatException('Invalid notification identity/read state');
    }
    for (final key in ['actorId', 'relatedEntityId']) {
      if (fields[key] != null &&
          (fields[key] is! int || (fields[key] as int) <= 0)) {
        throw FormatException('Invalid $key');
      }
    }
    for (final key in ['title', 'message', 'type']) {
      requiredString(fields, key);
    }
    for (final key in ['relatedEntityType', 'eventId', 'createdAt', 'readAt']) {
      optionalString(fields, key);
    }
  }
  final Map<String, dynamic> fields;
  int get id => fields['id'] as int;
  int get recipientId => fields['recipientId'] as int;
  bool get read => fields['read'] as bool;
  int? get actorId => fields['actorId'] as int?;
  int? get resourceId => fields['relatedEntityId'] as int?;
  String get title => fields['title'] as String;
  String get message => fields['message'] as String;
  String get type => fields['type'] as String;
  String? text(String key) => fields[key] as String?;
  String? get resourceType => text('relatedEntityType');
  NotificationItem asRead() =>
      NotificationItem.fromJson({...fields, 'read': true});
}

/// Read is monotonic: a duplicate creation event cannot undo a REST read.
class NotificationCache {
  final _items = <int, NotificationItem>{};
  void clear() => _items.clear();
  void merge(NotificationItem item) {
    if (_items[item.id]?.read == true && !item.read) return;
    _items[item.id] = item;
  }

  List<NotificationItem> get items => _items.values.toList()
    ..sort((a, b) {
      final time = (b.text('createdAt') ?? '').compareTo(
        a.text('createdAt') ?? '',
      );
      return time == 0 ? b.id.compareTo(a.id) : time;
    });
}
