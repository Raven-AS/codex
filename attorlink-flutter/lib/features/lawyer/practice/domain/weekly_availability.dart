import '../../../auth/domain/auth_models.dart' show jsonObject, requiredString;
import '../../../../core/network/api_exception.dart';

enum WorkingDay {
  monday('MONDAY', 'Monday'),
  tuesday('TUESDAY', 'Tuesday'),
  wednesday('WEDNESDAY', 'Wednesday'),
  thursday('THURSDAY', 'Thursday'),
  friday('FRIDAY', 'Friday'),
  saturday('SATURDAY', 'Saturday'),
  sunday('SUNDAY', 'Sunday');

  const WorkingDay(this.wire, this.label);
  final String wire;
  final String label;
  static WorkingDay parse(Object? value) => values.firstWhere(
    (d) => d.wire == value,
    orElse: () => throw const FormatException('Invalid day of week'),
  );
}

class WorkingTime {
  WorkingTime._(this.wire, this.nanoseconds);
  factory WorkingTime.parse(String input) {
    final match = RegExp(
      r'^([01]\d|2[0-3]):([0-5]\d)(?::([0-5]\d)(?:\.(\d{1,9}))?)?$',
    ).firstMatch(input.trim());
    if (match == null) {
      throw const FormatException(
        'Use HH:mm, HH:mm:ss, or seconds with up to 9 fractional digits.',
      );
    }
    final seconds = match[3] ?? '00';
    final fraction = match[4] ?? '';
    final nanos =
        ((int.parse(match[1]!) * 60 + int.parse(match[2]!)) * 60 +
                int.parse(seconds)) *
            1000000000 +
        (fraction.isEmpty ? 0 : int.parse(fraction.padRight(9, '0')));
    final trimmed = fraction.replaceFirst(RegExp(r'0+$'), '');
    return WorkingTime._(
      '${match[1]}:${match[2]}:$seconds${trimmed.isEmpty ? '' : '.$trimmed'}',
      nanos,
    );
  }
  final String wire;
  final int nanoseconds;
}

class AvailabilityRange {
  AvailabilityRange({
    required this.day,
    required this.start,
    required this.end,
  });
  final WorkingDay day;
  final WorkingTime start;
  final WorkingTime end;
  bool get valid => start.nanoseconds < end.nanoseconds;
  Map<String, Object> toJson() => {
    'dayOfWeek': day.wire,
    'startTime': start.wire,
    'endTime': end.wire,
    'available': true,
  };
}

class SavedAvailability {
  SavedAvailability.fromJson(Object? value) {
    final json = jsonObject(value);
    if (json['id'] is! int ||
        (json['id'] as int) <= 0 ||
        json['available'] is! bool) {
      throw const FormatException('Invalid availability record');
    }
    id = json['id'] as int;
    available = json['available'] as bool;
    range = AvailabilityRange(
      day: WorkingDay.parse(json['dayOfWeek']),
      start: WorkingTime.parse(requiredString(json, 'startTime')),
      end: WorkingTime.parse(requiredString(json, 'endTime')),
    );
  }
  late final int id;
  late final bool available;
  late final AvailabilityRange range;
}

List<SavedAvailability> decodeAvailability(Object? value) {
  if (value is! List) throw const FormatException('Expected availability list');
  return value.map(SavedAvailability.fromJson).toList();
}

void validateAvailability(List<AvailabilityRange> ranges) {
  final errors = <String, String>{};
  for (var i = 0; i < ranges.length; i++) {
    if (!ranges[i].valid) {
      errors['slots[$i].endTime'] =
          'Start time must be before end time for ${ranges[i].day.label}.';
    }
  }
  if (errors.isNotEmpty) {
    throw ApiException(
      kind: ApiErrorKind.validation,
      message: 'Check the working-hour ranges. Overnight ranges must be represented on separate days.',
      fieldErrors: errors,
    );
  }
}
