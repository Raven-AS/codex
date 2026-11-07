import '../../auth/domain/auth_models.dart' show jsonObject, requiredString;

const ticketCategories = [
  'GENERAL',
  'ACCOUNT',
  'PROFILE',
  'BILLING',
  'TECHNICAL',
  'LEGAL',
];
const ticketStatuses = ['OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED'];

String? ticketSubjectError(String? text) {
  final value = text?.trim() ?? '';
  if (value.isEmpty) return 'Subject is required.';
  return value.length > 160 ? 'Subject must be at most 160 characters.' : null;
}

String? ticketMessageError(String? text) {
  final value = text?.trim() ?? '';
  return value.length < 10 || value.length > 4000
      ? 'Message must be between 10 and 4000 characters.'
      : null;
}

class SupportTicket {
  SupportTicket.fromJson(Object? value) {
    final json = jsonObject(value);
    if (json['id'] is! int || (json['id'] as int) <= 0) {
      throw const FormatException('Invalid ticket ID');
    }
    id = json['id'] as int;
    reference = requiredString(json, 'referenceNumber');
    subject = requiredString(json, 'subject');
    message = requiredString(json, 'message');
    category = requiredString(json, 'category');
    status = requiredString(json, 'status');
    if (!ticketCategories.contains(category) ||
        !ticketStatuses.contains(status)) {
      throw const FormatException('Unknown support category or status');
    }
    createdAt = requiredString(json, 'createdAt');
    if (json['updatedAt'] != null && json['updatedAt'] is! String) {
      throw const FormatException('Invalid update timestamp');
    }
    updatedAt = json['updatedAt'] as String?;
  }
  late final int id;
  late final String reference, subject, message, category, status, createdAt;
  late final String? updatedAt;
}
