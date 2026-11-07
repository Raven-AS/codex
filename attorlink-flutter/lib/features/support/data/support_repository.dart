import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../auth/domain/auth_models.dart';
import '../domain/support_ticket.dart';

class SupportRepository {
  SupportRepository(
    this.api, {
    required this.ownerId,
    required this.currentUser,
    this.accessChanges,
    this.sessionGeneration,
    this.parentAccess,
  }) : _initialGeneration = sessionGeneration?.call();
  final void Function()? parentAccess;
  final ApiClient api;
  final int ownerId;
  final AuthUser? Function() currentUser;
  final Stream<Object?>? accessChanges;
  final int Function()? sessionGeneration;
  final int? _initialGeneration;
  void checkAccess() {
    parentAccess?.call();
    final user = currentUser();
    if ((_initialGeneration != null &&
            sessionGeneration!() != _initialGeneration) ||
        user == null ||
        user.id != ownerId ||
        user.status != UserStatus.active ||
        ![UserRole.client, UserRole.lawyer].contains(user.role)) {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        message: 'Sign in with the same active client or lawyer account to use support.',
      );
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    checkAccess();
    final result = await action();
    checkAccess();
    return result;
  }

  Future<ApiPage<SupportTicket>> list({int page = 0}) => _guard(() async {
    if (page < 0) throw ArgumentError.value(page);
    return (await api.request(
      'GET',
      'support/tickets',
      authenticated: true,
      accessGuard: checkAccess,
      query: {'page': '$page', 'size': '10'},
      decode: (value) {
        final result = ApiPage.fromJson(value, SupportTicket.fromJson);
        if (result.page != page ||
            result.size != 10 ||
            result.content.length > result.size) {
          throw const FormatException('Unexpected support page');
        }
        return result;
      },
    )).data;
  });
  Future<SupportTicket> get(int id) => _guard(
    () async => (await api.request(
      'GET',
      'support/tickets/$id',
      authenticated: true,
      accessGuard: checkAccess,
      decode: (value) {
        final result = SupportTicket.fromJson(value);
        if (result.id != id) {
          throw const FormatException('Unexpected ticket ID');
        }
        return result;
      },
    )).data,
  );
  Future<SupportTicket> create({
    required String subject,
    required String message,
    String category = 'GENERAL',
  }) => _guard(() async {
    final error = ticketSubjectError(subject) ?? ticketMessageError(message);
    if (error != null || !ticketCategories.contains(category)) {
      throw ApiException(
        kind: ApiErrorKind.validation,
        message: error ?? 'Choose a supported category.',
      );
    }
    return (await api.request(
      'POST',
      'support/tickets',
      authenticated: true,
      accessGuard: checkAccess,
      body: {
        'subject': subject.trim(),
        'message': message.trim(),
        'category': category,
      },
      decode: SupportTicket.fromJson,
    )).data;
  });
}
