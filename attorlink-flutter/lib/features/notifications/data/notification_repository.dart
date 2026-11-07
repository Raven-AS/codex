import '../../../app/live_updates.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../auth/domain/auth_models.dart';
import '../domain/notification_models.dart';

class NotificationRepository {
  NotificationRepository(
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
        kind: ApiErrorKind.unauthorized,
        message: 'Sign in to view your notifications.',
      );
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    checkAccess();
    final value = await action();
    checkAccess();
    return value;
  }

  NotificationItem _item(Object? value, {int? id}) {
    final item = NotificationItem.fromJson(value);
    if (item.recipientId != ownerId || (id != null && item.id != id)) {
      throw const FormatException('Unexpected notification');
    }
    return item;
  }

  Future<ApiPage<NotificationItem>> list({int page = 0}) => _guard(
    () async => (await api.request(
      'GET',
      'notifications',
      authenticated: true,
      accessGuard: checkAccess,
      query: {'page': '$page', 'size': '20'},
      decode: (value) {
        final result = ApiPage.fromJson(value, _item);
        if (result.page != page || result.size != 20) {
          throw const FormatException('Unexpected notifications page');
        }
        return result;
      },
    )).data,
  );
  Future<int> unread() => _guard(
    () async => (await api.request(
      'GET',
      'notifications/unread-count',
      authenticated: true,
      accessGuard: checkAccess,
      decode: (value) => notificationCount(value, 'unreadCount'),
    )).data,
  );
  Future<NotificationItem> read(int id) => _guard(() async {
    final item = (await api.request(
      'PATCH',
      'notifications/$id/read',
      authenticated: true,
      accessGuard: checkAccess,
      decode: (value) {
        final item = _item(value, id: id);
        if (!item.read) {
          throw const FormatException('Read not confirmed');
        }
        return item;
      },
    )).data;
    live?.notificationsChanged(ownerId);
    return item;
  });
  Future<int> readAll() => _guard(() async {
    final count = (await api.request(
      'PATCH',
      'notifications/read-all',
      authenticated: true,
      accessGuard: checkAccess,
      decode: (value) => notificationCount(value, 'updatedCount'),
    )).data;
    live?.notificationsChanged(ownerId);
    return count;
  });
}
