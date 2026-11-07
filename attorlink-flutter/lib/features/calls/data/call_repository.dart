import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../messaging/data/chat_repository.dart';
import '../domain/call_models.dart';

class CallRepository {
  CallRepository(this.chat);
  final ChatRepository chat;
  static const path = 'video-calls';
  String _path(bool scheduled) => '$path${scheduled ? '/scheduled' : ''}';
  Future<T> _guard<T>(Future<T> Function() action) async {
    chat.checkAccess();
    final value = await action();
    chat.checkAccess();
    return value;
  }

  CallRecord _record(Object? value, bool scheduled, {int? id}) {
    final record = CallRecord.fromJson(value, scheduled: scheduled);
    if (!record.contains(chat.ownerId) || (id != null && record.id != id)) {
      throw const FormatException('Unexpected call participant or ID');
    }
    return record;
  }

  Future<ApiPage<CallRecord>> list({
    required bool scheduled,
    required bool incoming,
    int page = 0,
  }) => _guard(() async {
    if (page < 0) throw ArgumentError.value(page);
    return (await chat.api.request(
      'GET',
      _path(scheduled),
      authenticated: true,
      accessGuard: chat.checkAccess,
      query: {'incoming': '$incoming', 'page': '$page', 'size': '20'},
      decode: (value) {
        final result = ApiPage.fromJson(
          value,
          (row) => _record(row, scheduled),
        );
        if (result.page != page ||
            result.size != 20 ||
            result.content.any(
              (r) => (incoming ? r.recipientId : r.callerId) != chat.ownerId,
            )) {
          throw const FormatException('Unexpected call history page');
        }
        return result;
      },
    )).data;
  });
  Future<CallRecord> get(int id, {required bool scheduled}) => _guard(
    () async => (await chat.api.request(
      'GET',
      '${_path(scheduled)}/$id',
      authenticated: true,
      accessGuard: chat.checkAccess,
      decode: (value) => _record(value, scheduled, id: id),
    )).data,
  );
  Future<CallRecord> create({
    required int recipient,
    int? conversationId,
    String note = '',
    String? scheduledAt,
  }) => _guard(() async {
    if (recipient <= 0 ||
        recipient == chat.ownerId ||
        (conversationId != null && conversationId <= 0)) {
      throw const ApiException(
        kind: ApiErrorKind.validation,
        message: 'Choose another positive user ID and, optionally, an accepted conversation ID.',
      );
    }
    final scheduled = scheduledAt != null;
    if (scheduled && note.length > 500) {
      throw const ApiException(
        kind: ApiErrorKind.validation,
        message: 'Scheduled-call notes must be at most 500 characters.',
      );
    }
    final stamp = scheduled ? callLocalTime(scheduledAt) : null;
    return (await chat.api.request(
      'POST',
      _path(scheduled),
      authenticated: true,
      accessGuard: chat.checkAccess,
      body: {
        'recipientUserId': recipient,
        'conversationId': ?conversationId,
        if (note.trim().isNotEmpty) 'note': note,
        'scheduledAt': ?stamp,
      },
      decode: (value) {
        final result = _record(value, scheduled);
        if (result.callerId != chat.ownerId ||
            result.recipientId != recipient) {
          throw const FormatException('Unexpected call recipient');
        }
        return result;
      },
    )).data;
  });
  Future<CallRecord> action(
    CallRecord record,
    String action, {
    String? reason,
    String? scheduledAt,
    String? signalType,
    String? payload,
  }) => _guard(() async {
    if (!record.actions(chat.ownerId).contains(action) || action == 'join') {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        message: 'This call action is unavailable. Refresh its status.',
      );
    }
    Map<String, Object?>? body;
    final signal = action == 'signal';
    if (signal) {
      if (signalType == null ||
          signalType.trim().isEmpty ||
          payload == null ||
          payload.trim().isEmpty) {
        throw const ApiException(
          kind: ApiErrorKind.validation,
          message: 'Supply an actual signal type and payload.',
        );
      }
      body = {'signalType': signalType, 'payload': payload};
    } else if (action == 'reschedule') {
      if (scheduledAt == null) {
        throw const FormatException('New scheduled time is required');
      }
      if ((reason?.length ?? 0) > 500) {
        throw const FormatException('Reason exceeds 500 characters');
      }
      body = {
        'scheduledAt': callLocalTime(scheduledAt),
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      };
    } else if ((reason?.length ?? 0) > 255) {
      throw const FormatException('Reason exceeds 255 characters');
    }
    return (await chat.api.request(
      signal ? 'POST' : 'PATCH',
      '${_path(record.scheduled)}/${record.id}/$action',
      authenticated: true,
      accessGuard: chat.checkAccess,
      query:
          !signal &&
              action != 'reschedule' &&
              reason != null &&
              reason.isNotEmpty
          ? {'reason': reason}
          : null,
      body: body,
      decode: (value) => _record(value, record.scheduled, id: record.id),
    )).data;
  });
  Future<CallCredentials> credentials(CallRecord record) => _guard(() async {
    if (!record.canJoin(chat.ownerId)) {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        message: 'This call cannot currently issue join credentials.',
      );
    }
    return (await chat.api.request(
      'POST',
      '${_path(record.scheduled)}/${record.id}/join',
      authenticated: true,
      accessGuard: chat.checkAccess,
      decode: (value) {
        final result = CallCredentials.fromJson(value);
        if ((record.scheduled
                ? result.callId != null
                : result.callId != record.id) ||
            result.roomId != record.fields['roomId'] ||
            result.identity != 'user-${chat.ownerId}' ||
            result.provider != 'livekit') {
          throw const FormatException('Unexpected media credentials');
        }
        return result;
      },
    )).data;
  });
}
