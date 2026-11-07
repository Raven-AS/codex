import '../../auth/domain/auth_models.dart' show jsonObject, requiredString;
import '../../messaging/domain/chat_models.dart' show chatId;

const instantCallStatuses = [
  'INITIATED',
  'RINGING',
  'ACCEPTED',
  'REJECTED',
  'CANCELLED',
  'ENDED',
  'MISSED',
  'FAILED',
];
const scheduledCallStatuses = [
  'SCHEDULED',
  'RESCHEDULED',
  'READY',
  'STARTED',
  'CANCELLED',
  'MISSED',
  'FAILED',
];

/// Spring LocalDateTime: preserve wall time and nanoseconds, without assigning a zone.
String callLocalTime(String value) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,9}))?)?$',
  ).firstMatch(value);
  if (match == null) {
    throw const FormatException(
      'Use YYYY-MM-DDTHH:mm[:ss], without a timezone.',
    );
  }
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i) ?? '0')];
  final d = DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  if (d.year != parts[0] ||
      d.month != parts[1] ||
      d.day != parts[2] ||
      d.hour != parts[3] ||
      d.minute != parts[4] ||
      d.second != parts[5]) {
    throw const FormatException('Invalid calendar date or time.');
  }
  return match.group(6) == null ? '$value:00' : value;
}

class CallRecord {
  CallRecord.fromJson(Object? value, {required this.scheduled}) {
    final json = jsonObject(value);
    id = chatId(json, 'id');
    callerId = chatId(json, 'callerId');
    recipientId = chatId(json, 'recipientId');
    if (json['conversationId'] != null) chatId(json, 'conversationId');
    status = requiredString(json, 'status');
    if (!(scheduled ? scheduledCallStatuses : instantCallStatuses).contains(
      status,
    )) {
      throw const FormatException('Unknown call status');
    }
    final stringFields = scheduled
        ? [
            'roomId',
            'scheduledAt',
            'notes',
            'cancelReason',
            'lastReminderSentAt',
            'startedAt',
            'cancelledAt',
            'missedAt',
            'createdAt',
            'updatedAt',
          ]
        : [
            'roomId',
            'initiatedAt',
            'acceptedAt',
            'rejectedAt',
            'cancelledAt',
            'endedAt',
            'failureReason',
            'createdAt',
            'updatedAt',
          ];
    for (final key in stringFields) {
      if (json[key] != null && json[key] is! String) {
        throw FormatException('Invalid $key');
      }
      if (json[key] != null && key.endsWith('At')) {
        callLocalTime(json[key] as String);
      }
    }
    if (scheduled) {
      callLocalTime(requiredString(json, 'scheduledAt'));
      if (json['reminderCount'] is! int || (json['reminderCount'] as int) < 0) {
        throw const FormatException('Invalid reminder count');
      }
    }
    fields = Map.unmodifiable(json);
  }
  final bool scheduled;
  late final int id, callerId, recipientId;
  late final String status;
  late final Map<String, dynamic> fields;
  bool contains(int owner) => callerId == owner || recipientId == owner;
  bool get pending => ['INITIATED', 'RINGING'].contains(status);
  bool get activeSchedule =>
      ['SCHEDULED', 'RESCHEDULED', 'READY'].contains(status);
  bool canJoin(int owner) =>
      contains(owner) &&
      (scheduled
          ? activeSchedule || status == 'STARTED'
          : status == 'ACCEPTED' ||
                (status == 'INITIATED' && callerId == owner) ||
                (status == 'RINGING' && recipientId == owner));
  List<String> actions(int owner) {
    if (!contains(owner)) return [];
    if (scheduled) {
      return [
        if (activeSchedule) ...['reschedule', 'cancel', 'start'],
        if (canJoin(owner)) 'join',
      ];
    }
    return [
      if (status == 'INITIATED') 'ring',
      if (pending && recipientId == owner) ...['accept', 'reject'],
      if (pending && callerId == owner) 'cancel',
      if (status == 'ACCEPTED') 'end',
      if (pending || status == 'ACCEPTED') 'signal',
      if (canJoin(owner)) 'join',
    ];
  }
}

/// Sensitive credentials are short lived in memory and never rendered or persisted.
class CallCredentials {
  CallCredentials.fromJson(Object? value) {
    final json = jsonObject(value);
    callId = json['callId'] == null ? null : chatId(json, 'callId');
    roomId = requiredString(json, 'roomId');
    provider = requiredString(json, 'provider');
    serverUrl = requiredString(json, 'serverUrl');
    identity = requiredString(json, 'identity');
    token = requiredString(json, 'token');
    expiresAt = callLocalTime(requiredString(json, 'expiresAt'));
    for (final key in [
      'canPublishAudio',
      'canPublishVideo',
      'canSubscribe',
      'canPublishData',
    ]) {
      if (json[key] is! bool) throw FormatException('Invalid $key');
    }
    canPublishAudio = json['canPublishAudio'] as bool;
    canPublishVideo = json['canPublishVideo'] as bool;
    canSubscribe = json['canSubscribe'] as bool;
    canPublishData = json['canPublishData'] as bool;
  }
  late final int? callId;
  late final String roomId, provider, serverUrl, identity, token, expiresAt;
  late final bool canPublishAudio,
      canPublishVideo,
      canSubscribe,
      canPublishData;
}
